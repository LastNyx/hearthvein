class_name Settlement
extends RefCounted
## The central simulation object. Holds registry, map, clock, event bus and a list of systems.
## Features are added as SimSystem subclasses, not by growing this class.

var registry: DataRegistry
var map: MapState
var clock := GameClock.new()
var events := EventBus.new()
var systems: Array[SimSystem] = []
var _system_cache_size: int = -1
var _system_cache: Dictionary = {}  # script -> system, so per-building lookups (ticket 55) skip the scan

const ROAD_NONE := 0
const ROAD_DIRT := 1
const ROAD_PAVED := 2  # stored only for now; the paving tool comes in Town
## Irrigation channels (design.md section 9) are a separate overlay grid, like roads: 1 where a channel is dug.
const CHANNEL_NONE := 0
const CHANNEL_DUG := 1

## Building instances by id, plus an occupancy grid (building id per tile, -1 free) and a road grid.
var buildings: Dictionary = {}  # int -> Building
var occupancy := PackedInt32Array()
var roads := PackedByteArray()
## Channel grid, parallel to roads. Whether a channel flows is derived (WaterSystem.flowing_channels), not stored.
var channels := PackedByteArray()
## Rail track grid (ticket 37), parallel to roads: 1 where a track tile lies. A separate layer: no road and no walking
## speed, so citizens ignore it. Which depots a track joins is derived (RailSystem), never stored.
var track := PackedByteArray()
## Sky layer (ticket 40): same tile coordinates as the ground, so sky tile (x, y) floats above ground tile (x, y).
## sky_map is "void" everywhere except raised islands ("skystone"); its blight, fertility and wet stay 0. The sky has
## its own occupancy and road grids (roads only on skystone). Route by layer with map_for_layer, occupancy_for_layer
## and roads_for_layer (Building.LAYER_GROUND / LAYER_SKY).
var sky_map: MapState = MapState.new_sky()
var sky_occupancy := PackedInt32Array()
var sky_roads := PackedByteArray()
## True once the free first Lift Anchor (BuildingDef.free_first_with) has been placed. Saved.
var free_anchor_used: bool = false
var hearth: Building = null
## Global gold counter. Gold is never stored in inventories.
var gold: float = 0.0
## Citizens by id (plain sim objects, see Citizen). Housing and jobs are kept current by JobSystem.
var citizens: Dictionary = {}  # int -> Citizen
var _next_citizen_id: int = 0
## New-game stock (design.md section 5), put in the Hearth.
const START_STOCK := {"food": 60.0, "wood": 100.0, "lumen": 10.0}
const START_CITIZENS := 8
## Hour a player's new game opens at (main.start_new_game), so the first screen is daylight, not night. new_game()
## itself stays at hour 0 so sim tests and the balance bot keep their clock.
const PLAYER_START_HOUR := 6
const PRIORITIES: Array[String] = ["low", "normal", "high", "paused"]
var _next_building_id: int = 0
## Bumped whenever roads or buildings change, so path caches know to drop themselves.
var grid_version: int = 0
## Cut stone still owed toward the next whole unit of paving (design.md section 6: 0.2 per tile). Kept here so a run
## of tiles pays whole cut stone as it accumulates and no fractional cut stone ever sits in storage. Saved; older
## saves without the key load it as 0, so it is not in SaveGame.REQUIRED_STATE_KEYS.
var _pave_stone_debt: float = 0.0
## Bumped whenever a construction site completes (complete_site). A cache key only (not saved): caches that depend
## on which buildings are finished key on (structure_version, completion_version) and rebuild after a load.
var completion_version: int = 0
## Bumps with grid_version for roads and buildings only (not terrain). WalkerSystem rewrites its whole A* grid when this
## moves and only the tiles in terrain_dirty when just terrain changed (ticket 55).
var structure_version: int = 0
## Bumped by LightingSystem whenever a lamp's lit state changes (dusk fuel burn, dawn). A cache key only (not saved):
## JobSystem includes it so night slots open and close with the lamps (ticket 133, note from 132).
var light_version: int = 0
var terrain_dirty: Array[Vector2i] = []
## Bumped when a tile becomes forest (the only change that can bring a forest tile nearer to a woodcutter).
var forest_gain_version: int = 0
## Road reachability from the Hearth (see _recompute_connections).
var _reached := {}
## Sky road tiles joined to a connected Sky Lift or island dock (see _reach_sky), a cache like _reached.
var _sky_reached := {}
var _roads_dirty := true
## Game seconds already spent inside the current hour (only non-zero between step_seconds calls).
var _hour_acc: float = 0.0


## Fraction of the current hour already simulated, 0..1. Read-only, render-side (the clock bar and the day and night
## tint); the sim itself only moves in whole hours.
func hour_fraction() -> float:
	return clampf(_hour_acc / GameClock.REAL_SECONDS_PER_HOUR, 0.0, 1.0)


static func new_game(seed: int, reg: DataRegistry, endless_start: bool = false, tutorial: bool = false) -> Settlement:
	var s := Settlement.new()
	s.registry = reg
	s.map = MapGen.generate(seed, reg)
	s.occupancy.resize(MapState.WIDTH * MapState.HEIGHT)
	s.occupancy.fill(-1)
	s._init_sky_grids()
	s.roads.resize(MapState.WIDTH * MapState.HEIGHT)
	s.channels.resize(MapState.WIDTH * MapState.HEIGHT)
	s.track.resize(MapState.WIDTH * MapState.HEIGHT)
	var hdef := reg.get_building("hearth")
	if hdef != null and s.map.hearth_spot.x >= 0:
		s.hearth = s._insert_building(hdef, s.map.hearth_spot, false)
		for g in START_STOCK:
			s.hearth.inventory.add(g, START_STOCK[g])
		s.place_road(s.map.hearth_spot + Vector2i(hdef.size.x, 0))
		for i in START_CITIZENS:
			s.add_citizen()
	s.add_default_systems()
	if endless_start:
		(s.get_system(CampaignSystem) as CampaignSystem).set_endless_start(true)
	if tutorial:
		(s.get_system(TutorialSystem) as TutorialSystem).start(s)
	WaterSystem.recompute(s)  # the map starts dry; a new game's first day should not wait for the day hook
	return s


## The UI moved the camera (tutorial goal 1, ticket 83 calls this once the player pans, zooms or rotates).
func report_camera_moved() -> void:
	(get_system(TutorialSystem) as TutorialSystem).report_camera_moved(self)


## Ends the tutorial at once (the goal panel's skip button).
func skip_tutorial() -> void:
	(get_system(TutorialSystem) as TutorialSystem).skip(self)


## Road tiles joined to the Hearth (ground layer). Brings the road BFS up to date first, so a road_changed handler
## sees the road that was just placed.
func connected_road_count() -> int:
	if _roads_dirty:
		_recompute_connections()
	return _reached.size()


func _init_sky_grids() -> void:
	sky_occupancy.resize(MapState.WIDTH * MapState.HEIGHT)
	sky_occupancy.fill(-1)
	sky_roads.resize(MapState.WIDTH * MapState.HEIGHT)


## The tile map of a layer: the ground map or the sky map.
func map_for_layer(layer: int) -> MapState:
	return sky_map if layer == Building.LAYER_SKY else map


func occupancy_for_layer(layer: int) -> PackedInt32Array:
	return sky_occupancy if layer == Building.LAYER_SKY else occupancy


func roads_for_layer(layer: int) -> PackedByteArray:
	return sky_roads if layer == Building.LAYER_SKY else roads


## Every game system a real game runs, in hook order. Each feature ticket appends its system here.
func add_default_systems() -> void:
	add_system(EraSystem.new())
	add_system(StorageSystem.new())
	var ledger := ResourceLedgerSystem.new()  # made/used per good per day (ticket 109); rolls on day_started
	add_system(ledger)
	events.subscribe("day_started", ledger.on_day_started.bind(self))
	add_system(GridSystem.new())  # Lumen grid membership cache (ticket 36); no hooks, queried by Upkeep, Production, Hauling
	add_system(IslandSystem.new())  # sky island list (ticket 40) and the hourly island Lumen draw and still state (40b); after GridSystem
	add_system(RailSystem.new())  # rail network cache (ticket 37); no hooks, queried by connections and 37b manifests
	add_system(RailManifestSystem.new())  # daily train manifests between linked depots (ticket 37b), hourly arrivals
	add_system(AirshipSystem.new())  # after the rail manifests (rail first): air freight between docks, survey flights (ticket 38)
	add_system(LightingSystem.new())  # burns lamp fuel at dusk and answers Settlement.is_lit (ticket 133); before
	# JobSystem, so its hourly refresh at dusk already sees the night's light (and so before WalkerSystem)
	add_system(GloomSystem.new())  # spreads gloom over unlit land in a Dimming night (ticket 149), after the light burns
	add_system(JobSystem.new())
	add_system(WalkerSystem.new())
	add_system(WaterSystem.new())  # before Production: the day's wet grid feeds the farm modifier
	add_system(FoulingSystem.new())  # hourly river fouling; its modifier feeds Production (ticket 29c)
	add_system(FertilitySystem.new())  # before Production: supplies the farm fertility modifier
	add_system(ProductionSystem.new())
	add_system(UpkeepSystem.new())  # spends the day's Lumen before Production and Market gold read the flag
	add_system(HaulingSystem.new())
	add_system(ConstructionSystem.new())
	add_system(SkyheartSystem.new())  # stage gold and the finished Skyheart's reservoir fill (ticket 45); after the grid
	add_system(GreatDimmingSystem.new())  # the Skyheart's Great Dimming (ticket 45b); before the regular Dimming, which yields to it
	add_system(CampaignSystem.new())  # win and loss outcome (ticket 45c): hourly population check, Great Dimming result
	var dimming := DimmingSystem.new()  # before Growth: darkness blocks the day's growth
	add_system(dimming)
	events.subscribe("great_dimming_ended", dimming.on_great_dimming_ended.bind(self))  # the vein surge (ticket 150)
	var ms := MilestoneSystem.new()  # milestones (ticket 46b): daily state checks and the event kinds; after Dimming so a day's darkness is seen
	add_system(ms)
	for kind in ["dimming_ended", "skyheart_finished", "campaign_won"]:
		events.subscribe(kind, ms.on_event.bind(self))
	add_system(GrowthSystem.new())
	add_system(BlightSystem.new())  # blight first, so the day's health sees it
	add_system(CleaningSystem.new())  # cleaners clear after the spread, before the day's health is counted
	add_system(HealingSystem.new())  # Verdant Spring and Rewilding Grove act daily, before the day's health is counted
	add_system(PlanetHealthSystem.new())
	add_system(ForestSystem.new())  # reads the day's planet health; stumps regrow and Foresters plant here
	add_system(MarketSystem.new())  # pays gold and caches Market reach; Spirit reads the reach for food variety
	add_system(CaravanSystem.new())  # the night caravan at a lit, staffed Night Market (ticket 141); after Market, before Spirit
	add_system(CoverageSystem.new())  # caches covered homes (Shrine r6); Spirit reads it for the coverage factor
	add_system(RegionSystem.new())  # region rewards: modifier hooks, the spring wet pass and the one-time ruins claim
	add_system(SpiritSystem.new())  # after Growth: reads its hunger report; after Planet: grief
	var tut := TutorialSystem.new()  # guided goals (ticket 82): off unless new_game(tutorial); last, so it sees the hour's results
	tut.setup(registry.tutorial_goals_in_order())
	add_system(tut)
	for kind in ["building_completed", "road_changed", "building_connection_changed", "citizen_added",
			"citizen_born", "citizen_immigrated", "dimming_forecast", "dimming_ended"]:
		events.subscribe(kind, tut.on_event.bind(self))
	var prod := get_system(ProductionSystem) as ProductionSystem
	prod.modifiers.append(FertilitySystem.output_modifier)
	prod.modifiers.append(SpiritSystem.work_modifier)
	prod.modifiers.append(PlanetHealthSystem.vein_modifier)
	prod.modifiers.append(DimmingSystem.output_modifier)
	prod.modifiers.append(DimmingSystem.vein_surge_modifier)
	prod.modifiers.append(Moon.output_modifier)
	prod.modifiers.append(ProductionSystem.winter_modifier)
	prod.modifiers.append(RegionSystem.rich_vein_modifier)
	prod.modifiers.append(UpkeepSystem.output_modifier)
	prod.modifiers.append(FoulingSystem.output_modifier)
	prod.modifiers.append(ProductionSystem.wheel_speed_modifier)
	prod.modifiers.append(ProductionSystem.tier_modifier)
	prod.modifiers.append(BlightSystem.output_modifier)
	var forest_sys := get_system(ForestSystem) as ForestSystem
	forest_sys.regrow_factors.append(RegionSystem.regrow_factor)
	var sp := get_system(SpiritSystem) as SpiritSystem
	sp.set_hook("coverage", CoverageSystem.spirit_factor)
	sp.set_hook("water", CoverageSystem.water_factor)
	sp.set_hook("blight", BlightSystem.spirit_factor)
	sp.set_hook("darkness", DimmingSystem.darkness_factor)
	sp.set_hook("planet_grief", PlanetHealthSystem.grief_factor)
	(get_system(PlanetHealthSystem) as PlanetHealthSystem).extra_sources.append(GreatDimmingSystem.planet_source)


func add_system(system: SimSystem) -> void:
	systems.append(system)
	_system_cache.clear()


## Deterministic advance, one hour at a time. Per hour: on_seconds hooks get the hour's game seconds, the clock
## moves, then on_hour hooks run; when the new hour starts a day, day_started is emitted and on_day hooks run;
## likewise season_started / on_season.
func step_hours(n: int) -> void:
	_frame_step = false
	_held.clear()  # a coarse step starts from a settled sim
	_run_deferred(true)
	for i in n:
		var rest := GameClock.REAL_SECONDS_PER_HOUR - _hour_acc
		_hour_acc = 0.0
		for sys in systems:
			sys.on_seconds(self, rest)
		_advance_hour()


## Finer seam for movement: advance `seconds` of game time (1x seconds). on_seconds hooks see the time in pieces that
## never cross an hour boundary; every completed hour runs exactly the hooks step_hours(1) would.
## A frame-sized step spreads an hour end (ticket 89, and the day and season hooks of 57c): the hour's hooks are queued
## and run over the following steps, about SPREAD_BUDGET_USEC of them per step, while the clock holds at the boundary.
## The steps that come meanwhile wait in _held and are played, piece by piece as they came, once the queue is empty, so
## the hooks and movement see the same sequence as an unspread run. A coarse step runs everything at once.
func step_seconds(seconds: float) -> void:
	_frame_step = seconds < DEFER_BELOW_SECONDS
	_step_seconds(seconds)
	_frame_step = false  # is_spreading() is only true while a frame step runs


func _step_seconds(seconds: float) -> void:
	if _frame_step:
		_run_deferred_budget()
		if _deferred_head < _deferred.size():
			_held.append(seconds)
			return
	else:
		_run_deferred(true)
	var pieces := _held
	_held = []
	pieces.append(seconds)
	for p in pieces.size():
		var left := pieces[p]
		while left > 0.0:
			var chunk := minf(left, GameClock.REAL_SECONDS_PER_HOUR - _hour_acc)
			for sys in systems:
				sys.on_seconds(self, chunk)
			left -= chunk
			_hour_acc += chunk
			if _hour_acc >= GameClock.REAL_SECONDS_PER_HOUR - 0.000001:
				_hour_acc = 0.0
				_advance_hour()
				if _deferred_head < _deferred.size():  # the hour end is queued: hold the rest of the time
					if left > 0.0:
						_held.append(left)
					_held.append_array(pieces.slice(p + 1))
					return


## Steps shorter than this (game seconds, 0.5 s = a frame at 7 fps and 1x) spread the hour end over several steps.
const DEFER_BELOW_SECONDS := GameClock.REAL_SECONDS_PER_HOUR / 10.0
## Wall time one frame-sized step spends on pending hour-end work (at least one item runs).
const SPREAD_BUDGET_USEC := 1000

## Pending hour-end work (hourly, day and season hooks, their events) that a frame-sized step spread out, in the order
## it runs (Callables). Runtime only: ticket 19 calls flush_deferred() before saving so nothing is pending in a save file.
var _deferred: Array[Callable] = []
var _deferred_head: int = 0
var _frame_step: bool = false  # inside a step_seconds call short enough to spread the hour-end work
var _held: Array[float] = []  # game seconds of the steps that came while the queue was not empty, in order; runtime only


## Runs every pending item.
func _run_deferred(all: bool) -> void:
	while _deferred_head < _deferred.size():
		var d: Callable = _deferred[_deferred_head]
		_deferred_head += 1
		d.call()
		if not all:
			break
	_reset_deferred()


## Runs pending items until the step's time budget is spent (at least one).
func _run_deferred_budget() -> void:
	var t0 := Time.get_ticks_usec()
	while _deferred_head < _deferred.size():
		var d: Callable = _deferred[_deferred_head]
		_deferred_head += 1
		d.call()
		if Time.get_ticks_usec() - t0 >= SPREAD_BUDGET_USEC:
			break
	_reset_deferred()


func _reset_deferred() -> void:
	if _deferred_head >= _deferred.size():
		_deferred.clear()
		_deferred_head = 0


## Queues one more piece of work behind the pending hour-end items. It runs in a later frame step with the clock held
## (so the sim does not change in between), or at once when the queue is flushed.
func defer_work(work: Callable) -> void:
	_deferred.append(work)


## True inside a frame-sized step (the queue is being spread over frames), false for coarse steps and flushes.
func is_spreading() -> bool:
	return _frame_step


## Runs every pending hour, day and season hook now (a save, or code that reads the sim right after a change).
func flush_deferred() -> void:
	var was := _frame_step
	_frame_step = false  # a flush is a coarse run: work the items queue for later (the autosave) happens right here
	_run_deferred(true)
	_frame_step = was


func _advance_hour() -> void:
	_run_deferred(true)  # work still pending from the last hour must not run after this hour's
	clock.total_hours += 1
	events.now_hours = clock.total_hours
	for sys in systems:
		_deferred.append(sys.on_hour.bind(self))
	if clock.is_day_start():
		_deferred.append(func() -> void:
			events.emit("day_started", {"day": clock.day(), "season": clock.season_name(), "year": clock.year()}))
		for sys in systems:
			_deferred.append(sys.on_day.bind(self))
		if clock.is_season_start():
			for sys in systems:
				_deferred.append(sys.on_season.bind(self))
			# After the season hooks: the autosave on this event flushes whatever is pending, and by now that is nothing.
			_deferred.append(func() -> void:
				events.emit("season_started", {"season": clock.season_name(), "year": clock.year()}))
	if not _frame_step:
		_run_deferred(true)


var _kind_ids: Dictionary = {}  # job kind -> citizen ids in id order, see citizen_ids_of_kind
var _kind_key := Vector2i(-1, -1)


## Citizen ids whose job_kind is `kind`, in id order, kept until a job kind changes (Citizen.job_epoch) or the number of
## citizens does. Per-frame systems used to sort and scan every citizen each frame. A citizen swapped for another with no
## job change in between can leave a stale id: callers check the citizen they get, as they did before.
func citizen_ids_of_kind(kind: String) -> Array:
	var key := Vector2i(Citizen.job_epoch, citizens.size())
	if key != _kind_key:
		_kind_key = key
		_kind_ids.clear()
	if not _kind_ids.has(kind):
		var out: Array = []
		for cid in citizens:
			if (citizens[cid] as Citizen).job_kind == kind:
				out.append(cid)
		out.sort()
		_kind_ids[kind] = out
	return _kind_ids[kind]


## The registered system of a class, or null.
func get_system(script: GDScript) -> SimSystem:
	if _system_cache_size != systems.size():  # added or erased since the cache was filled
		_system_cache.clear()
		_system_cache_size = systems.size()
	if _system_cache.has(script):
		return _system_cache[script]
	for sys in systems:
		if is_instance_of(sys, script):
			_system_cache[script] = sys
			return sys
	return null


func step_days(n: int) -> void:
	step_hours(n * GameClock.HOURS_PER_DAY)


# ---------------------------------------------------------------- save state
# The whole simulation as plain data (see SaveGame). Defs are stored by id and resolved through the registry on load;
# runtime caches are left out and rebuilt. Buildings, citizens and walkers are kept as ordered [id, dict] lists so a
# loaded settlement iterates in the same order as the one that was saved (dictionary order is part of determinism).

func to_dict() -> Dictionary:
	var out := {}
	for step in to_dict_steps(out, false):
		step.call()
	return out


## to_dict as a list of steps that fill `out` (a Dictionary the caller owns) piece by piece, each about a millisecond:
## the autosave runs them one per frame while the clock is held (ticket 89b). The keys are laid out in to_dict's order up
## front. `isolate` copies the containers that live objects keep and later change (map arrays, system state), so a thread
## may read the finished dictionary while the sim runs on; to_dict() itself skips that, its caller owns the result at once.
func to_dict_steps(out: Dictionary, isolate: bool) -> Array[Callable]:
	for key in ["map", "occupancy", "roads", "sky_map", "sky_occupancy", "sky_roads", "free_anchor_used", "channels",
			"track", "buildings", "citizens", "hearth", "gold", "next_building_id", "next_citizen_id", "grid_version",
			"pave_stone_debt", "structure_version", "forest_gain_version", "terrain_dirty", "hour_acc", "clock", "events",
			"era_current", "era_override", "planet_health_override", "spirit_override", "systems"]:
		out[key] = null
	var steps: Array[Callable] = []
	steps.append(func() -> void:
		var dirty := []
		for t in terrain_dirty:
			dirty.append(t)
		out["map"] = map.to_dict().duplicate(true) if isolate else map.to_dict()
		out["occupancy"] = occupancy.duplicate() if isolate else occupancy
		out["roads"] = roads.duplicate() if isolate else roads
		out["sky_map"] = sky_map.to_dict().duplicate(true) if isolate else sky_map.to_dict()
		out["sky_occupancy"] = sky_occupancy.duplicate() if isolate else sky_occupancy
		out["sky_roads"] = sky_roads.duplicate() if isolate else sky_roads
		out["free_anchor_used"] = free_anchor_used
		out["channels"] = channels.duplicate() if isolate else channels
		out["track"] = track.duplicate() if isolate else track
		out["hearth"] = hearth.id if hearth != null else -1
		out["gold"] = gold
		out["next_building_id"] = _next_building_id
		out["next_citizen_id"] = _next_citizen_id
		out["grid_version"] = grid_version
		out["pave_stone_debt"] = _pave_stone_debt
		out["structure_version"] = structure_version
		out["forest_gain_version"] = forest_gain_version
		out["terrain_dirty"] = dirty
		out["hour_acc"] = _hour_acc
		out["clock"] = clock.to_dict()
		out["events"] = events.to_dict()
		out["era_current"] = era_current
		out["era_override"] = era_override
		out["planet_health_override"] = planet_health_override
		out["spirit_override"] = spirit_override
		out["buildings"] = []
		out["citizens"] = []
		out["systems"] = {})
	var building_ids: Array = buildings.keys()
	for from in range(0, building_ids.size(), SAVE_CHUNK_BUILDINGS):
		steps.append(func() -> void:
			var bl: Array = out["buildings"]
			for k in range(from, mini(from + SAVE_CHUNK_BUILDINGS, building_ids.size())):
				var id: int = building_ids[k]
				bl.append([id, (buildings[id] as Building).to_dict()]))
	var citizen_ids: Array = citizens.keys()
	for from in range(0, citizen_ids.size(), SAVE_CHUNK_CITIZENS):
		steps.append(func() -> void:
			var cl: Array = out["citizens"]
			for k in range(from, mini(from + SAVE_CHUNK_CITIZENS, citizen_ids.size())):
				var id: int = citizen_ids[k]
				cl.append([id, (citizens[id] as Citizen).to_dict()]))
	for sys in systems:
		var key := SimSystem.save_key_of(sys)
		if key != "":
			steps.append(func() -> void:
				var st := sys.save_state()
				(out["systems"] as Dictionary)[key] = st.duplicate(true) if isolate else st)
	return steps


## Buildings and citizens per to_dict step (a building is about 5 microseconds, a citizen far less).
const SAVE_CHUNK_BUILDINGS := 150
const SAVE_CHUNK_CITIZENS := 500


## Builds a settlement from to_dict() data. Null when the data names a def the registry does not know.
## Selectors and caches (_reached, the road-connection BFS) are rebuilt here; system state is applied after
## add_default_systems(), so the systems are the same objects a new game gets.
static func from_dict(d: Dictionary, registry: DataRegistry) -> Settlement:
	var s := Settlement.new()
	s.registry = registry
	s.map = MapState.from_dict(d["map"])
	s.occupancy = d["occupancy"]
	s.roads = d["roads"]
	s.channels = d["channels"]
	if d.has("sky_map"):
		s.sky_map = MapState.from_dict(d["sky_map"])
		s.sky_occupancy = d["sky_occupancy"]
		s.sky_roads = d["sky_roads"]
	else:  # a save from before the sky layer: no islands
		s._init_sky_grids()
	s.free_anchor_used = bool(d.get("free_anchor_used", false))
	if d.has("track"):
		s.track = d["track"]
	else:  # a save from before rail track
		s.track.resize(MapState.WIDTH * MapState.HEIGHT)
	for pair in d["buildings"]:
		var b := Building.from_dict(pair[1], registry)
		if b == null:
			return null
		s.buildings[b.id] = b
		if b.site and b.input_buffer != null:  # the site's need comes from the def, not the save (ticket 99)
			var cap := 0.0
			for g in b.effective_cost():
				if g != BuildingDef.GOLD:
					cap = maxf(cap, float(b.effective_cost()[g]))
			b.input_buffer.cap = cap
	for pair in d["citizens"]:
		var c := Citizen.from_dict(pair[1])
		s.citizens[c.id] = c
	s.hearth = s.buildings.get(int(d["hearth"]))
	s.gold = float(d["gold"])
	s._next_building_id = int(d["next_building_id"])
	s._next_citizen_id = int(d["next_citizen_id"])
	s.grid_version = int(d["grid_version"])
	s._pave_stone_debt = float(d.get("pave_stone_debt", 0.0))
	s.structure_version = int(d["structure_version"])
	s.forest_gain_version = int(d["forest_gain_version"])
	s.terrain_dirty.assign(d["terrain_dirty"])
	s._hour_acc = float(d["hour_acc"])
	s.clock = GameClock.from_dict(d["clock"])
	s.events = EventBus.from_dict(d["events"])
	s.era_current = str(d["era_current"])
	s.era_override = str(d["era_override"])
	s.planet_health_override = float(d["planet_health_override"])
	s.spirit_override = float(d["spirit_override"])
	s.add_default_systems()
	var sys_state: Dictionary = d["systems"]
	for sys in s.systems:
		var key := SimSystem.save_key_of(sys)
		if key != "" and sys_state.has(key):
			sys.load_state(sys_state[key], s)
	# The road BFS result is a cache; rebuild it so later placements see the same reachable roads. Recomputed
	# connection flags match the saved ones, so this emits nothing.
	s._roads_dirty = true
	s._recompute_connections()
	return s


# ---------------------------------------------------------------- placement

func building_at(tile: Vector2i, layer: int = Building.LAYER_GROUND) -> Building:
	if not MapState.in_bounds(tile.x, tile.y):
		return null
	var id := occupancy_for_layer(layer)[MapState.idx(tile.x, tile.y)]
	return buildings.get(id) if id >= 0 else null


func road_at(tile: Vector2i) -> int:
	if not MapState.in_bounds(tile.x, tile.y):
		return ROAD_NONE
	return roads[MapState.idx(tile.x, tile.y)]


## Returns {ok: bool, reason: String}. Reason is "" when ok.
## Reason "era_locked" when the building's era is later than era_id() (ticket 16); ignore_era skips only that check
## (used by place_building_instant, the debug/test path).
## `layer` is Building.LAYER_GROUND (default, every old caller) or LAYER_SKY. The def's `layers` rule must allow it
## (reason "wrong_layer"). On the sky every footprint tile must be skystone of a raised island (reason "no_island"),
## free of sky buildings ("overlap") and sky roads ("road"); the ground-only checks (region ownership, water, channels,
## track, region depot and dock) do not apply. A Lift Anchor (raises_island) is rejected with "region_island" when its
## region already has an anchor and "island_cap" at LogisticsDef.island_max anchors, sites counting.
func can_place(def_id: String, origin: Vector2i, ignore_era: bool = false, layer: int = Building.LAYER_GROUND) -> Dictionary:
	var def := registry.get_building(def_id)
	if def == null:
		return {"ok": false, "reason": "unknown_building"}
	if not ignore_era and not is_unlocked(def):
		return {"ok": false, "reason": "era_locked"}
	if def_id == "hearth" and hearth != null:
		return {"ok": false, "reason": "unique"}
	if def.unique:
		for other: Building in buildings.values():
			if other.def.id == def_id:
				return {"ok": false, "reason": "unique"}  # sites count
	if layer != Building.LAYER_GROUND and layer != Building.LAYER_SKY:
		return {"ok": false, "reason": "wrong_layer"}
	if (layer == Building.LAYER_SKY and def.layers == "ground") or (layer == Building.LAYER_GROUND and def.layers == "island"):
		return {"ok": false, "reason": "wrong_layer"}
	if layer == Building.LAYER_SKY:
		return _can_place_sky(def, origin)
	if def.raises_island and MapState.in_bounds(origin.x, origin.y):
		var anchor_region := map.get_region(origin.x, origin.y)
		var anchors := 0
		for other: Building in buildings.values():
			if other.def.raises_island:
				anchors += 1
				if map.get_region(other.origin.x, other.origin.y) == anchor_region:
					return {"ok": false, "reason": "region_island"}  # one island per region, sites count
		if anchors >= registry.logistics.island_max:
			return {"ok": false, "reason": "island_cap"}
	if def.rail_depot and MapState.in_bounds(origin.x, origin.y):
		var region := map.get_region(origin.x, origin.y)
		for other: Building in buildings.values():
			if other.def.rail_depot and map.get_region(other.origin.x, other.origin.y) == region:
				return {"ok": false, "reason": "region_depot"}  # one Rail Depot per region, sites count
	if def.airship_dock and MapState.in_bounds(origin.x, origin.y):
		var dock_region := map.get_region(origin.x, origin.y)
		for other: Building in buildings.values():
			if other.def.airship_dock and other.layer == Building.LAYER_GROUND \
					and map.get_region(other.origin.x, other.origin.y) == dock_region:
				return {"ok": false, "reason": "region_dock"}  # one ground Airship Dock per region, sites count
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			if not MapState.in_bounds(x, y):
				return {"ok": false, "reason": "out_of_bounds"}
			if not map.is_region_owned(map.get_region(x, y)):
				return {"ok": false, "reason": "locked_region"}
			var tid := map.terrain_id_at(x, y)
			var on_river := def.placement_rule == "on_river" and map.is_river(x, y)  # a weir may stand in the river
			if tid == "water" and not on_river:
				return {"ok": false, "reason": "water"}
			var tdef := registry.get_terrain(tid)
			if tdef != null and not tdef.buildable and not on_river:
				return {"ok": false, "reason": "blocked_terrain"}
			var i := MapState.idx(x, y)
			if occupancy[i] >= 0:
				return {"ok": false, "reason": "overlap"}
			if roads[i] != ROAD_NONE:
				return {"ok": false, "reason": "road"}
			if channels[i] != CHANNEL_NONE:
				return {"ok": false, "reason": "channel"}
			if track[i] != 0:
				return {"ok": false, "reason": "track"}
	var why := Placement.check_rule(map, registry, def, origin)
	if why != "":
		return {"ok": false, "reason": why}
	if def.sky_lift:  # a Sky Lift also holds the sky tile right above: skystone of an island, free of buildings and roads
		var si := MapState.idx(origin.x, origin.y)
		if sky_map.terrain_id_at(origin.x, origin.y) != MapState.SKY_STONE:
			return {"ok": false, "reason": "no_island"}
		if sky_occupancy[si] >= 0:
			return {"ok": false, "reason": "overlap"}
		if sky_roads[si] != ROAD_NONE:
			return {"ok": false, "reason": "road"}
	return {"ok": true, "reason": ""}


## Sky-layer half of can_place: the footprint must lie on skystone (a raised island) and be free.
func _can_place_sky(def: BuildingDef, origin: Vector2i) -> Dictionary:
	if def.airship_dock and MapState.in_bounds(origin.x, origin.y):  # one island dock per region (ground docks count apart)
		var dock_region := map.get_region(origin.x, origin.y)
		for other: Building in buildings.values():
			if other.def.airship_dock and other.layer == Building.LAYER_SKY \
					and map.get_region(other.origin.x, other.origin.y) == dock_region:
				return {"ok": false, "reason": "region_dock"}
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			if not MapState.in_bounds(x, y):
				return {"ok": false, "reason": "out_of_bounds"}
			if sky_map.terrain_id_at(x, y) != MapState.SKY_STONE:
				return {"ok": false, "reason": "no_island"}
			var i := MapState.idx(x, y)
			if sky_occupancy[i] >= 0:
				return {"ok": false, "reason": "overlap"}
			if sky_roads[i] != ROAD_NONE:
				return {"ok": false, "reason": "road"}
	var why := Placement.check_rule(sky_map, registry, def, origin)
	if why != "":
		return {"ok": false, "reason": why}
	return {"ok": true, "reason": ""}


## The cost placing `def_id` would charge now: the def's cost, or nothing for the free first Lift Anchor (the def names
## a free_first_with building, a finished one stands, and free_anchor_used is still false). The build UI shows this.
func cost_for(def_id: String, have: Dictionary = {}) -> Dictionary:
	var def := registry.get_building(def_id)
	if def == null:
		return {}
	if _free_anchor_available(def) or _free_when_dry(def, have):
		return {}
	return def.entry_cost()


## The wood dead end rule (BuildingDef.free_when_dry): the stock of the good (`have`, goods totals; computed when left
## out) is below the def's cost of it and no site of the def is open.
func _free_when_dry(def: BuildingDef, have: Dictionary = {}) -> bool:
	if def.free_when_dry == "":
		return false
	for b: Building in buildings.values():
		if b.site and b.def == def:
			return false
	if have.is_empty():
		have = totals()
	return float(have.get(def.free_when_dry, 0.0)) + Inventory.EPS < float(def.entry_cost().get(def.free_when_dry, 0.0))


func _free_anchor_available(def: BuildingDef) -> bool:
	if def.free_first_with == "" or free_anchor_used:
		return false
	for b: Building in buildings.values():
		if not b.site and b.def.id == def.free_first_with:
			return true
	return false


## Normal play (D48): places a construction site and returns its building id, or -1 when invalid (see can_place) or
## when the gold part of the cost is not in the treasury. Gold is paid now; every other good is hauled to the site
## (HaulingSystem), then builders build it (ConstructionSystem). Priority via set_building_priority.
func place_building(def_id: String, origin: Vector2i, layer: int = Building.LAYER_GROUND) -> int:
	if not can_place(def_id, origin, false, layer)["ok"]:
		return -1
	var def := registry.get_building(def_id)
	var anchor_free := _free_anchor_available(def)
	var free := anchor_free or _free_when_dry(def)
	var g := float(cost_for(def_id).get(BuildingDef.GOLD, 0))
	if g > gold + Inventory.EPS:
		return -1
	gold -= g
	ResourceLedgerSystem.record_used(self, BuildingDef.GOLD, g, "placement")
	if anchor_free:
		free_anchor_used = true
	var b := _insert_building(def, origin, true, layer, free)
	events.emit("building_placed", {"id": b.id, "def": def.id, "origin": origin, "site": true})
	refresh_population()
	return b.id


## Debug and test path: a finished building at once, free, no site. Never used by normal play (the build UI calls
## place_building). Same validity rules as place_building. Returns the building id, or -1.
## Bypasses the era lock (tests and tools may place later-era buildings).
func place_building_instant(def_id: String, origin: Vector2i, layer: int = Building.LAYER_GROUND) -> int:
	if not can_place(def_id, origin, true, layer)["ok"]:
		return -1
	var def := registry.get_building(def_id)
	var b := _insert_building(def, origin, false, layer)
	events.emit("building_placed", {"id": b.id, "def": def.id, "origin": origin, "site": false})
	return b.id


## Build time in days with a full crew (design.md section 6: 1-6 days by size and era), numbers in LogisticsDef.
func build_days(def: BuildingDef) -> float:
	var lg := registry.logistics
	var era := registry.get_era(def.era)
	var order := era.order if era != null else 1
	var d := float(def.size.x * def.size.y) * lg.build_days_per_tile + float(order - 1) * lg.build_days_per_era
	return clampf(d, lg.build_days_min, lg.build_days_max)


## Called by ConstructionSystem when the work is done: the site becomes a normal building (buffers, jobs, housing).
func complete_site(b: Building) -> void:
	if not b.site:
		return
	if not b.def.stages.is_empty():
		var done_stage := b.stage
		b.stage += 1
		events.emit("skyheart_stage", {"id": b.id, "stage": done_stage + 1,
				"name": str(b.def.stages[done_stage].get("name", ""))})
		if b.stage < b.def.stages.size():
			_open_stage(b)  # the next stage's site opens on the same building, no command
			return
		events.emit("skyheart_finished", {"id": b.id})
		var gd := get_system(GreatDimmingSystem) as GreatDimmingSystem
		if gd != null:
			gd.schedule(self)
	b.site = false
	b.priority = "normal"  # the site's build priority is not the building's work priority (ticket 104)
	b.paused = false
	b.gold_due = 0
	b.input_buffer = null
	_init_buffers(b)
	completion_version += 1
	_raise_island_for(b)
	if b.def.wet_radius > 0:
		WaterSystem.recompute(self)
	if b.def.rail_depot or b.def.sky_lift or b.def.airship_dock:
		_roads_dirty = true  # a finished depot, lift or dock can join road networks; refresh_population runs below
		_recompute_connections()
	events.emit("building_completed", {"id": b.id, "def": b.def.id, "origin": b.origin})
	refresh_population()


## Opens the current stage of a staged building as a fresh site: empty buffer sized for the stage's goods, no work done,
## the stage's gold owed (paid at once when the treasury has it).
func _open_stage(b: Building) -> void:
	var cost := b.effective_cost()
	var cap := 0.0
	for g in cost:
		if g != BuildingDef.GOLD:
			cap = maxf(cap, float(cost[g]))
	b.input_buffer = Inventory.new("per_good", cap)
	b.build_work = 0.0
	b.build_work_needed = build_days(b.def) * float(registry.logistics.builder_crew)
	b.gold_due = int(cost.get(BuildingDef.GOLD, 0))
	pay_stage_gold(b)
	completion_version += 1
	grid_version += 1


## Takes the gold a stage still owes from the treasury when it is all there. Stage gold is not paid on placement
## (only the first stage is), so the stage waits for it like it waits for hauled goods.
func pay_stage_gold(b: Building) -> void:
	if b.gold_due > 0 and gold >= float(b.gold_due) - Inventory.EPS:
		var due := float(b.gold_due)
		gold -= due
		b.gold_due = 0
		ResourceLedgerSystem.record_used(self, BuildingDef.GOLD, due, "placement")


func _init_buffers(b: Building) -> void:
	var def := b.def
	if def.storage_mode != "none":
		b.inventory = Inventory.new(def.storage_mode, float(def.storage_cap))
	if def.recipe != null and registry.logistics != null:
		b.door_buffer = Inventory.new("total", registry.logistics.door_buffer_cap)
	# A consumer keeps recipe inputs and its Lumen upkeep; a building with upkeep alone (no recipe inputs) still
	# needs a buffer for the haulers to fill.
	var need := HaulingSystem.input_need(registry, def)
	if not need.is_empty():
		var cap := 0.0
		for g in need:
			cap = maxf(cap, need[g])
		b.input_buffer = Inventory.new("per_good", cap)


## A finished Lift Anchor raises its island (complete_site, or at once for an instant placement).
func _raise_island_for(b: Building) -> void:
	if not b.def.raises_island or b.layer != Building.LAYER_GROUND:
		return
	var isl := get_system(IslandSystem) as IslandSystem
	if isl != null:
		isl.raise(self, b)


func _insert_building(def: BuildingDef, origin: Vector2i, as_site: bool = false, layer: int = Building.LAYER_GROUND,
		free: bool = false) -> Building:
	var b := Building.new()
	b.id = _next_building_id
	_next_building_id += 1
	b.def = def
	b.origin = origin
	b.layer = layer
	b.cost_free = free
	if as_site:
		b.site = true
		var cap := 0.0
		var site_cost := b.effective_cost()
		for g in site_cost:
			if g != BuildingDef.GOLD:
				cap = maxf(cap, float(site_cost[g]))
		b.input_buffer = Inventory.new("per_good", cap)
		b.build_work_needed = build_days(def) * float(registry.logistics.builder_crew)
	else:
		_init_buffers(b)
		b.stage = def.stages.size()  # a staged building placed finished is past every stage
	buildings[b.id] = b
	grid_version += 1
	structure_version += 1
	var occ := occupancy_for_layer(layer)
	for t in b.tiles():
		occ[MapState.idx(t.x, t.y)] = b.id
	if def.sky_lift:
		sky_occupancy[MapState.idx(origin.x, origin.y)] = b.id  # the lift also stands in the sky tile above
	if not as_site:
		_raise_island_for(b)
	if (def.rail_depot or def.sky_lift or def.airship_dock) and not as_site:
		_roads_dirty = true
	if def.wet_radius > 0 and not as_site and hearth != null:
		WaterSystem.recompute(self)  # a finished wetting building wets its tiles at once
	_recompute_connections(b)
	if hearth == null:
		refresh_population()  # the Hearth itself: no connection pass yet
	return b


func demolish(id: int) -> bool:
	var b: Building = buildings.get(id)
	if b == null or b == hearth:
		return false
	var isys := get_system(IslandSystem) as IslandSystem
	var island: Island = isys.island_of_anchor(id) if isys != null and b.def.raises_island else null
	if island != null:
		if not isys.buildings_on(self, island).is_empty():
			return false  # an island with buildings on it cannot be dropped
		isys.remove(self, island)
	var occ := occupancy_for_layer(b.layer)
	for t in b.tiles():
		occ[MapState.idx(t.x, t.y)] = -1
	if b.def.sky_lift:
		sky_occupancy[MapState.idx(b.origin.x, b.origin.y)] = -1
	# Contents of a demolished storehouse are lost.
	buildings.erase(id)
	grid_version += 1
	structure_version += 1
	if b.def.wet_radius > 0 and not b.site:
		WaterSystem.recompute(self)
	var refund := _refund_for(b)
	_return_goods(refund, b.origin, b.layer)
	events.emit("building_demolished", {"id": id, "def": b.def.id, "origin": b.origin, "site": b.site, "refund": refund})
	if b.def.rail_depot or b.def.sky_lift or b.def.airship_dock:
		_roads_dirty = true  # losing a depot, lift or dock can cut a rail or sky link, and with it connections
		_recompute_connections()
	refresh_population()  # otherwise removing a building changes no road, so no connection can change
	return true


## What a demolish gives back (LogisticsDef.demolish_refund, 50%): of the full cost for a finished building, of the
## goods already delivered for a site (design.md is silent on sites, ticket 11 decided; the gold paid counts too).
## Goods in transit are not part of it: a hauler whose destination vanishes puts its load back at the source.
func _refund_for(b: Building) -> Dictionary:
	var share := registry.logistics.demolish_refund
	var out := {}
	var cost := b.effective_cost()
	for g in cost:
		var have := float(cost[g])
		if b.site and g != BuildingDef.GOLD:
			have = b.input_buffer.amount_of(g) if b.input_buffer != null else 0.0
		elif b.site and b.gold_due > 0:
			have = 0.0  # a staged site's gold not yet paid
		if have * share > Inventory.EPS:
			out[g] = have * share
	# An in-place upgrade in flight: goods already delivered for it come back at the same share (like a site's).
	if b.upgrading() and b.upgrade_buffer != null:
		for g in b.upgrade_cost:
			var got := b.upgrade_buffer.amount_of(g) * share
			if got > Inventory.EPS:
				out[g] = float(out.get(g, 0.0)) + got
	return out


## Public form of _return_goods for a grant that is not a refund (the ruins reward, ticket 25b).
## Gold goes to the counter; each good to the nearest storage with room (measured from `from`).
func store_goods(goods: Dictionary, from: Vector2i) -> void:
	_return_goods(goods, from)


## Gold goes to the counter; each good to the nearest storage with room (measured from `from`), spilling over to
## the next nearest when one fills up. What fits nowhere is lost.
func _return_goods(goods: Dictionary, from: Vector2i, from_layer: int = Building.LAYER_GROUND) -> void:
	for g in goods:
		var left: float = goods[g]
		if g == BuildingDef.GOLD:
			gold += left
			continue
		while left > Inventory.EPS:
			var st := find_storage_with_room(g, from, 0.000001, from_layer)
			if st == null:
				break
			var put := st.inventory.add(g, left)
			if put <= 0.0:
				break
			left -= put


## Command: change one tile's terrain (woodcutting, regrowth, blight later). Bumps grid_version because walk speeds
## change, and emits terrain_changed {tile, from, to} so views redraw the tile. False when nothing changed.
func set_terrain(tile: Vector2i, terrain_id: String) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or map.terrain_index(terrain_id) < 0:
		return false
	var from := map.terrain_id_at(tile.x, tile.y)
	if from == terrain_id:
		return false
	map.set_terrain_id(tile.x, tile.y, terrain_id)
	grid_version += 1
	if from == "water" or terrain_id == "water":
		map.water_version += 1  # invalidates WaterSystem's cached water-terrain wet base
	terrain_dirty.append(tile)
	if terrain_dirty.size() > 512:
		structure_version += 1
		terrain_dirty.clear()
	if terrain_id == "forest":
		forest_gain_version += 1
	events.emit("terrain_changed", {"tile": tile, "from": from, "to": terrain_id})
	return true


## Command: set or clear blight on one tile (spreaders, cleaners). Emits blight_changed {tile, blighted} so views
## redraw it. False when nothing changed.
func set_blighted(tile: Vector2i, v: bool) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or map.is_blighted(tile.x, tile.y) == v:
		return false
	map.set_blighted(tile.x, tile.y, v)
	events.emit("blight_changed", {"tile": tile, "blighted": v})
	return true


## Command: set or clear fouling on one water tile (FoulingSystem, and tests). Bumps MapState.foul_version so the
## fouling mask and the water-coverage cache drop themselves, and emits fouled_changed {tile, fouled} for views.
## False when nothing changed. Only river tiles foul in normal play; this command does not enforce that.
func set_fouled(tile: Vector2i, v: bool) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or map.is_fouled(tile.x, tile.y) == v:
		return false
	map.set_fouled(tile.x, tile.y, v)
	map.foul_version += 1
	events.emit("fouled_changed", {"tile": tile, "fouled": v})
	return true


## Era reached by the real progression (EraSystem advances it, one era at a time). Save state for ticket 19.
var era_current: String = "camp"
## Tests and debug: non-empty pins era_id() (the progression state is kept underneath).
var era_override: String = ""


func era_id() -> String:
	return era_override if era_override != "" else era_current


## True when the building's era is the current era or an earlier one.
func is_unlocked(def: BuildingDef) -> bool:
	var cur := registry.get_era(era_id())
	var e := registry.get_era(def.era)
	if cur == null or e == null:
		return true
	return e.order <= cur.order


## Building defs that can be placed now (build menu list), sorted by era order then id.
func unlocked_buildings() -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for d: BuildingDef in registry.buildings.values():
		if is_unlocked(d):
			out.append(d)
	out.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		var oa := registry.get_era(a.era).order
		var ob := registry.get_era(b.era).order
		return oa < ob or (oa == ob and a.id < b.id))
	return out


var _landmark_key := Vector2i(-1, -1)
var _landmarks: Dictionary = {}  # landmark def id -> the buildings of that def, kept per layout key (era_gate runs hourly)


## True when a finished building of this def stands. The buildings of the def are cached until buildings are placed or
## removed; whether each is still a site is read fresh.
func _landmark_built(def_id: String) -> bool:
	var key := Vector2i(buildings.size(), grid_version)
	if key != _landmark_key:
		_landmark_key = key
		_landmarks.clear()
	if not _landmarks.has(def_id):
		var found: Array[Building] = []
		for b: Building in buildings.values():
			if b.def.id == def_id:
				found.append(b)
		_landmarks[def_id] = found
	for b: Building in _landmarks[def_id]:
		if not b.site:
			return true
	return false


## Gate state for the era after the current one (HUD, ticket 17): {next, pop, pop_need, gold, gold_need, landmark,
## landmark_built, met}. next is "" at the last era. Needs come from the EraDef row only.
func era_gate() -> Dictionary:
	var cur := registry.get_era(era_current)
	var nxt: EraDef = null
	for e in registry.eras_in_order():
		if cur != null and e.order == cur.order + 1:
			nxt = e
	if nxt == null:
		return {"next": "", "met": false}
	var built := _landmark_built(nxt.gate_landmark)
	var pop := citizens.size()
	return {"next": nxt.id, "pop": pop, "pop_need": nxt.gate_pop, "gold": gold, "gold_need": nxt.gate_gold,
		"landmark": nxt.gate_landmark, "landmark_built": built,
		"met": pop >= nxt.gate_pop and gold + Inventory.EPS >= nxt.gate_gold and built}


var planet_health_override: float = -1.0  # tests and debug: >= 0 pins planet health


## Planet health now (0-100). planet_health_override wins when >= 0; 100 with no PlanetHealthSystem.
func planet_health() -> float:
	if planet_health_override >= 0.0:
		return planet_health_override
	var sys := get_system(PlanetHealthSystem) as PlanetHealthSystem
	if sys == null:
		return 100.0
	return sys.current(self)


# ---------------------------------------------------------------- citizens and jobs

## True when `hour` falls in a [start, end) window that may wrap midnight.
static func in_window(hour: int, window: Vector2i) -> bool:
	if window.x < window.y:
		return hour >= window.x and hour < window.y
	return hour >= window.x or hour < window.y


## The long night of a Dimming as [start, end] (ticket 148, spec N8), from DayNightDef (16-09). The single source the
## shift, the lamps, the tint and the day shift all read while DimmingSystem.is_active.
func dimming_night_window() -> Vector2i:
	var dn := registry.day_night if registry != null else null
	return Vector2i(dn.dimming_night_start, dn.dimming_night_end) if dn != null else Vector2i(16, 9)


## Hours of tonight's night shift as [start, end] (wrapping midnight): normal LogisticsDef.night_shift_start/end
## (20-06); in a Dimming the long night dimming_night_window (16-09).
func night_window() -> Vector2i:
	if DimmingSystem.is_active(self):
		return dimming_night_window()
	var lg := registry.logistics if registry != null else null
	return Vector2i(lg.night_shift_start if lg != null else 20, lg.night_shift_end if lg != null else 6)


## Hours the lamps burn as [start, end] (wrapping midnight): normal LogisticsDef.lamp_light_start/end (19-07); in a
## Dimming the same long night as the shift, so the light comes up and goes out with it.
func lamp_window() -> Vector2i:
	if DimmingSystem.is_active(self):
		return dimming_night_window()
	var lg := registry.logistics if registry != null else null
	return Vector2i(lg.lamp_light_start if lg != null else 19, lg.lamp_light_end if lg != null else 7)


## Hours the day shift works as [start, end] (never wrapping): normal WalkerSystem.WORK_START_HOUR/WORK_END_HOUR
## (06-18); in a Dimming the short day between the long nights, dimming_night_end to dimming_night_start (09-16).
func day_window() -> Vector2i:
	if DimmingSystem.is_active(self):
		var w := dimming_night_window()
		return Vector2i(w.y, w.x)
	return Vector2i(WalkerSystem.WORK_START_HOUR, WalkerSystem.WORK_END_HOUR)


## True while the night shift runs (night_window, wrapping midnight). `hour` defaults to the clock's hour. Night slots,
## their walkers and their production all read this one answer.
func is_night(hour: int = -1) -> bool:
	return in_window(clock.hour() if hour < 0 else hour, night_window())


## True when `b` counts as lit, so its night slots work (spec N2: a night-shift building works only inside a working
## lamp's radius). Any footprint tile inside a fuelled lamp's radius lights the building; at least one must be lit.
## Returns true while no LightingSystem runs (plain terminals and unit fixtures), so night work needs no lamp there.
func is_lit(b: Building) -> bool:
	var ls := get_system(LightingSystem) as LightingSystem
	return ls == null or ls.is_building_lit(self, b)


## True when `tile` is inside a fuelled lamp's radius tonight (ticket 133). The answer comes from a per-night cache that
## LightingSystem rebuilds on a build, a demolish or a change of any lamp's lit state. Always true with no LightingSystem.
func is_tile_lit(tile: Vector2i) -> bool:
	var ls := get_system(LightingSystem) as LightingSystem
	return ls == null or ls.is_tile_lit(self, tile)


## The 0-based day count of tonight's moon (ticket 145): the clock's day, but the small hours before the lamps go out
## (the end of lamp_window: 07:00, or 09:00 in a Dimming) still belong to the night that began the evening before.
func moon_days() -> int:
	return clock.total_days() - (1 if clock.hour() < lamp_window().y else 0)


## Lamp radius of `b` tonight: its own radius plus the full moon's bonus (ticket 145).
func lamp_radius(b: Building) -> int:
	var r := b.lamp_radius(registry)
	var dn := registry.day_night if registry != null else null
	return r + Moon.lamp_bonus(moon_days(), dn) if dn != null and r > 0 else r


## Tiles the moon adds to every lamp tonight (cache key for the lit-tile set).
func lamp_radius_bonus() -> int:
	var dn := registry.day_night if registry != null else null
	return Moon.lamp_bonus(moon_days(), dn) if dn != null else 0


## True during the lamp hours (lamp_window: normal 19 to 7, a Dimming's long night 16 to 9, wrapping midnight).
func is_lamp_hour(hour: int = -1) -> bool:
	return in_window(clock.hour() if hour < 0 else hour, lamp_window())


## Re-run housing and job assignment now (also runs every hour via JobSystem).
func refresh_population() -> void:
	JobSystem.refresh(self)


## Adds a homeless idle citizen, then assigns a bed and a job if available. Returns the citizen id.
## Tickets 12 (growth/immigration) call this; the Hearth is where newcomers appear.
func add_citizen() -> int:
	var c := Citizen.new()
	c.id = _next_citizen_id
	_next_citizen_id += 1
	citizens[c.id] = c
	refresh_population()
	events.emit("citizen_added", {"id": c.id})
	return c.id


## Removes a citizen (emigration, starvation). Frees their bed and slot.
func remove_citizen(id: int) -> bool:
	if not citizens.has(id):
		return false
	citizens.erase(id)
	refresh_population()
	events.emit("citizen_removed", {"id": id})
	return true


var spirit_override: float = -1.0  # tests and debug: >= 0 pins Spirit


## Spirit now (0-100). spirit_override wins when >= 0; with no SpiritSystem it is GrowthDef.default_spirit.
func spirit() -> float:
	if spirit_override >= 0.0:
		return spirit_override
	var sys := get_system(SpiritSystem) as SpiritSystem
	if sys == null:
		return registry.growth.default_spirit
	return sys.current(self)


func homeless_count() -> int:
	var n := 0
	for id in citizens:
		if (citizens[id] as Citizen).is_homeless():
			n += 1
	return n


func beds_total() -> int:
	var n := 0
	for id in buildings:
		var b: Building = buildings[id]
		if not b.site:
			n += b.effective_beds(registry)
	return n


func idle_citizens() -> Array:
	var out: Array = []
	for id in citizens:
		if (citizens[id] as Citizen).is_idle():
			out.append(citizens[id])
	return out


## Command: set one building's priority. One of "low", "normal", "high", "paused". "paused" keeps the old
## priority so un-pausing (any other value) restores a normal run; never assigns a person (D15).
func set_building_priority(building_id: int, priority: String) -> bool:
	var b: Building = buildings.get(building_id)
	if b == null or not PRIORITIES.has(priority):
		return false
	if priority == "paused":
		b.paused = true
	else:
		b.paused = false
		b.priority = priority
	events.emit("building_priority_changed", {"id": building_id, "priority": priority})
	refresh_population()
	return true


# ---------------------------------------------------------------- upgrade tiers (ticket 31)

## Why a building cannot start an in-place upgrade: {"ok": bool, "reason": String}, shaped like can_pave_road.
## Reasons: unknown_building, site (still under construction), category (not housing/food/resources/lumen; the Lamp is
## exempt), not_upgradable (the def carries no tiers), in_progress, max_tier, era_locked (tier II needs Town, tier III
## City from data/tiers/tiers.tres, or the TierDef's own era: the Lamp's II Village, III Town, IV City), needs_wet (the
## target tier only works on wet ground and the footprint is not half wet, e.g. the Irrigated Farm).
func can_upgrade(building_id: int) -> Dictionary:
	var b: Building = buildings.get(building_id)
	if b == null:
		return {"ok": false, "reason": "unknown_building"}
	if b.site:
		return {"ok": false, "reason": "site"}
	# The Lamp is civic but upgrades by era (ticket 133): its def says so, so the category rule steps aside.
	if not BuildingDef.UPGRADABLE_CATEGORIES.has(b.def.category) and not b.def.lamp:
		return {"ok": false, "reason": "category"}
	if not b.def.upgradable or b.def.tiers.is_empty():
		return {"ok": false, "reason": "not_upgradable"}
	if b.upgrading():
		return {"ok": false, "reason": "in_progress"}
	if b.tier >= 1 + b.def.tiers.size():
		return {"ok": false, "reason": "max_tier"}
	var target := b.tier_def(registry, b.tier + 1)
	# A TierDef may name its own era (the Lamp: II Village, III Town, IV City, ticket 133).
	if target != null and target.era != "":
		if not era_reached(target.era):
			return {"ok": false, "reason": "era_locked"}
	elif not tier_unlocked(b.tier + 1):
		return {"ok": false, "reason": "era_locked"}
	if target != null and target.needs_wet and not WaterSystem.footprint_wet(self, b):
		return {"ok": false, "reason": "needs_wet"}
	return {"ok": true, "reason": ""}


## True when the era required by a tier (TierRuleDef.eras) is the current one or an earlier one.
func tier_unlocked(tier: int) -> bool:
	var rule := registry.tiers
	if rule == null:
		return true
	var req_id := rule.era_for(tier)
	return req_id == "" or era_reached(req_id)


## True when `era` is the current era or an earlier one (a plain era id, e.g. a TierDef.era override).
func era_reached(id: String) -> bool:
	var cur := registry.get_era(era_id())
	var req := registry.get_era(id)
	return cur == null or req == null or cur.order >= req.order


## Command: start an in-place upgrade (design.md section 10). The building keeps its spot, its workers and its
## current tier; haulers deliver the tier's cost into Building.upgrade_buffer and builders work it like a site
## (ConstructionSystem), and only on completion does Building.tier move up. False and nothing changed when
## can_upgrade says no.
func upgrade(building_id: int) -> bool:
	if not can_upgrade(building_id)["ok"]:
		return false
	var b: Building = buildings[building_id]
	var target := b.tier + 1
	var cost := b.tier_cost(registry, target)
	var cap := 1.0
	for g in cost:
		cap = maxf(cap, float(cost[g]))
	b.upgrade_tier = target
	b.upgrade_cost = cost
	b.upgrade_buffer = Inventory.new("per_good", cap)
	b.upgrade_work = 0.0
	b.upgrade_work_needed = build_days(b.def) * float(registry.logistics.builder_crew)
	events.emit("upgrade_started", {"id": b.id, "def": b.def.id, "tier": target, "cost": cost.duplicate()})
	refresh_population()  # an already-delivered (or free) upgrade must let JobSystem allot builders now
	return true


## Called by ConstructionSystem when the upgrade work is done: the building is now its target tier.
func complete_upgrade(b: Building) -> void:
	if not b.upgrading():
		return
	b.tier = b.upgrade_tier
	b.priority = "normal"
	b.upgrade_tier = 0
	b.upgrade_cost.clear()
	b.upgrade_buffer = null
	b.upgrade_work = 0.0
	b.upgrade_work_needed = 0.0
	completion_version += 1
	events.emit("building_upgraded", {"id": b.id, "def": b.def.id, "tier": b.tier, "origin": b.origin})
	refresh_population()


# ---------------------------------------------------------------- storage

## good id -> total amount over every building inventory (gold excluded; see `gold`).
func totals() -> Dictionary:
	var out := {}
	for id in buildings:
		var inv: Inventory = (buildings[id] as Building).inventory
		if inv == null:
			continue
		for g in inv.goods():
			out[g] = out.get(g, 0.0) + inv.amount_of(g)
	return out


## Removes `amount` of `good` from the settlement's storage, all or nothing. Buildings with an inventory are spent
## from in building-id order (the Hearth is normally id 0), so exactly which storehouse pays is deterministic.
## Returns false and removes nothing when the total stock (see `totals`) is short.
func spend_good(good: String, amount: float) -> bool:
	if amount <= 0.0:
		return true
	if float(totals().get(good, 0.0)) + Inventory.EPS < amount:
		return false
	var ids := buildings.keys()
	ids.sort()
	var left := amount
	for id in ids:
		if left <= Inventory.EPS:
			break
		var inv: Inventory = (buildings[id] as Building).inventory
		if inv == null:
			continue
		left -= inv.remove(good, left)
	return true


## Command: restrict a storage building to the given good ids. Empty array = accept all.
func set_storage_filter(building_id: int, goods: Array) -> bool:
	var b: Building = buildings.get(building_id)
	if b == null or b.inventory == null:
		return false
	for g in goods:
		if registry.get_good(str(g)) == null:
			return false
	b.inventory.set_filter(goods)
	events.emit("storage_filter_changed", {"id": building_id, "goods": goods.duplicate()})
	return true


## Nearest storage building that can take at least `amount` (default any room) of `good`, measured as
## Manhattan distance from `from` to the closest footprint tile (ties: lowest id). Null if none.
## Walking distance replaces this in ticket 09.
## `from_layer` is the layer `from` is on; a storage on the other layer is as far as the way through the nearest Sky
## Lift or dock (WalkerSystem.estimate_distance), and skipped when there is none (ticket 40c).
func find_storage_with_room(good: String, from: Vector2i, amount: float = 0.000001,
		from_layer: int = Building.LAYER_GROUND) -> Building:
	var best: Building = null
	var best_d := 0
	var ws: WalkerSystem = null
	for id in buildings:
		var b: Building = buildings[id]
		if b.inventory == null or b.inventory.free_for(good) < amount:
			continue
		var d := 1 << 30
		if b.layer == from_layer:
			for t in b.tiles():
				d = mini(d, absi(t.x - from.x) + absi(t.y - from.y))
		else:
			if ws == null:
				ws = get_system(WalkerSystem) as WalkerSystem
			if ws == null:
				continue
			var gf := MapState.to_global(from, from_layer)
			for t in b.tiles():
				var est := ws.estimate_distance(self, gf, MapState.to_global(t, b.layer))
				if est < INF:
					d = mini(d, int(est))
			if d == 1 << 30:
				continue  # no lift or dock to carry it over
		if best == null or d < best_d or (d == best_d and b.id < best.id):
			best = b
			best_d = d
	return best


## `layer` LAYER_SKY: a road tile on an island (skystone, no sky building on it).
func can_place_road(tile: Vector2i, layer: int = Building.LAYER_GROUND) -> bool:
	if layer == Building.LAYER_SKY:
		return MapState.in_bounds(tile.x, tile.y) and sky_map.terrain_id_at(tile.x, tile.y) == MapState.SKY_STONE \
				and sky_occupancy[MapState.idx(tile.x, tile.y)] < 0
	if not MapState.in_bounds(tile.x, tile.y) or not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return false
	var tid := map.terrain_id_at(tile.x, tile.y)
	var tdef := registry.get_terrain(tid)
	var water := tid == "water"  # a road on water is a bridge (ticket 91): allowed when the dirt bridge cost is in storage
	if tdef != null and not tdef.buildable and not water:
		return false
	var i := MapState.idx(tile.x, tile.y)
	if water and not _can_afford(bridge_cost(tile, ROAD_DIRT)):
		return false
	return occupancy[i] < 0 and channels[i] == CHANNEL_NONE  # a track tile may take a road: a level crossing (ticket 67)


## True when the tile is open water (river). A road here is a bridge, track here a rail bridge (ticket 91).
func is_water_tile(tile: Vector2i) -> bool:
	return MapState.in_bounds(tile.x, tile.y) and map.terrain_id_at(tile.x, tile.y) == "water"


## True when a road or track tile stands on water: the bridge art is drawn there, the water underneath is unchanged.
func is_bridge(tile: Vector2i) -> bool:
	return is_water_tile(tile) and (road_at(tile) != ROAD_NONE or track_at(tile))


## Extra cost of laying road `level` on this tile: RoadDef.bridge_cost on a water tile, {} on land.
func bridge_cost(tile: Vector2i, level: int) -> Dictionary:
	if not is_water_tile(tile):
		return {}
	var rd := registry.get_road_by_level(level)
	return rd.bridge_cost if rd != null else {}


func _can_afford(cost: Dictionary) -> bool:
	var have := totals()
	for g in cost:
		if float(have.get(g, 0.0)) + Inventory.EPS < float(cost[g]):
			return false
	return true


## Pays a whole cost from storage, all or nothing.
func _spend_cost(cost: Dictionary) -> bool:
	if not _can_afford(cost):
		return false
	for g in cost:
		spend_good(g, float(cost[g]))
	return true


## Dirt by default; a higher level on an existing road upgrades it. Returns false when nothing changed.
func place_road(tile: Vector2i, level: int = ROAD_DIRT, layer: int = Building.LAYER_GROUND) -> bool:
	if layer == Building.LAYER_SKY:
		if not can_place_road(tile, layer) or sky_roads[MapState.idx(tile.x, tile.y)] >= level:
			return false
		sky_roads[MapState.idx(tile.x, tile.y)] = level
		grid_version += 1
		structure_version += 1
		_roads_dirty = true
		events.emit("road_changed", {"tile": tile, "level": level, "layer": layer})
		_recompute_connections()
		return true
	if not can_place_road(tile) or roads[MapState.idx(tile.x, tile.y)] >= level:
		return false
	if not _spend_cost(bridge_cost(tile, level)):  # a bridge tile pays RoadDef.bridge_cost for the level laid
		return false
	roads[MapState.idx(tile.x, tile.y)] = level
	grid_version += 1
	structure_version += 1
	_roads_dirty = true
	events.emit("road_changed", {"tile": tile, "level": level})
	_recompute_connections()
	return true


func remove_road(tile: Vector2i, layer: int = Building.LAYER_GROUND) -> bool:
	if layer == Building.LAYER_SKY:
		if not MapState.in_bounds(tile.x, tile.y) or sky_roads[MapState.idx(tile.x, tile.y)] == ROAD_NONE:
			return false
		sky_roads[MapState.idx(tile.x, tile.y)] = ROAD_NONE
		grid_version += 1
		structure_version += 1
		_roads_dirty = true
		events.emit("road_changed", {"tile": tile, "level": ROAD_NONE, "layer": layer})
		_recompute_connections()
		return true
	if not MapState.in_bounds(tile.x, tile.y) or roads[MapState.idx(tile.x, tile.y)] == ROAD_NONE:
		return false
	roads[MapState.idx(tile.x, tile.y)] = ROAD_NONE
	grid_version += 1
	structure_version += 1
	_roads_dirty = true
	events.emit("road_changed", {"tile": tile, "level": ROAD_NONE})
	_recompute_connections()
	return true


# ---------------------------------------------------------------- paved roads (ticket 30b)

## True from the Town era on (design.md section 6): the build bar offers paved roads only then. place_road and
## pave_road themselves gate on the RoadDef's era; this is the same query for views.
func paved_roads_unlocked() -> bool:
	return _road_unlocked(ROAD_PAVED)


## True when the road level's RoadDef names no era or the current era is at least that one.
func _road_unlocked(level: int) -> bool:
	var rd := registry.get_road_by_level(level)
	if rd == null or rd.era == "":
		return true
	var cur := registry.get_era(era_id())
	var req := registry.get_era(rd.era)
	return cur == null or req == null or cur.order >= req.order


## Whole cut stone the next paved tile costs, given the running debt (see _pave_stone_debt).
func _pave_stone_units(cost: Dictionary) -> int:
	return int(floor(_pave_stone_debt + float(cost.get("cut_stone", 0.0)) + Inventory.EPS))


## Why a tile cannot be paved: {"ok": bool, "reason": String}, shaped like can_place_channel. Paving works on a new
## tile or upgrades a dirt road. The cost is the paved RoadDef's `cost` (1 wood + 0.2 cut stone, Town). Cut stone is charged in whole units: each tile adds its 0.2 to a running debt and a whole unit is
## spent as the debt fills, so five tiles cost one stone and storage never holds a fraction of a good.
## On a water tile the paved bridge cost (RoadDef.bridge_cost) is added to the paved cost (ticket 91).
## Reasons: out_of_bounds, locked_region, blocked_terrain, overlap, channel, already_paved, era_locked,
## wood, stone, cut_stone.
func can_pave_road(tile: Vector2i) -> Dictionary:
	if not MapState.in_bounds(tile.x, tile.y):
		return {"ok": false, "reason": "out_of_bounds"}
	if not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return {"ok": false, "reason": "locked_region"}
	var tid := map.terrain_id_at(tile.x, tile.y)
	var tdef := registry.get_terrain(tid)
	if tdef != null and not tdef.buildable and tid != "water":
		return {"ok": false, "reason": "blocked_terrain"}
	var i := MapState.idx(tile.x, tile.y)
	if occupancy[i] >= 0:
		return {"ok": false, "reason": "overlap"}
	if channels[i] != CHANNEL_NONE:
		return {"ok": false, "reason": "channel"}
	if roads[i] >= ROAD_PAVED:
		return {"ok": false, "reason": "already_paved"}
	if not _road_unlocked(ROAD_PAVED):
		return {"ok": false, "reason": "era_locked"}
	var rd := registry.get_road_by_level(ROAD_PAVED)
	var cost: Dictionary = rd.cost if rd != null else {}
	var bridge := bridge_cost(tile, ROAD_PAVED)  # a stone bridge tile pays the paved cost and the bridge cost again
	for g in ["wood", "stone"]:
		if float(totals().get(g, 0.0)) + Inventory.EPS < float(cost.get(g, 0.0)) + float(bridge.get(g, 0.0)):
			return {"ok": false, "reason": g}
	if float(totals().get("cut_stone", 0.0)) + Inventory.EPS < float(_pave_stone_units(cost)):
		return {"ok": false, "reason": "cut_stone"}
	return {"ok": true, "reason": ""}


## Paves one tile, or upgrades a dirt road to paved, paying the paved RoadDef cost from storage at once (wood, stone)
## and in whole cut-stone units as the debt fills. Returns false when can_pave_road says no; nothing is spent then.
## Bumps grid_version and structure_version through place_road, so walker paths re-plan with the faster tiles.
func pave_road(tile: Vector2i) -> bool:
	if not can_pave_road(tile)["ok"]:
		return false
	var rd := registry.get_road_by_level(ROAD_PAVED)
	var cost: Dictionary = rd.cost if rd != null else {}
	var raw := {}
	for g in ["wood", "stone"]:
		if float(cost.get(g, 0.0)) > 0.0:
			raw[g] = float(cost[g])
	var stone_units := _pave_stone_units(cost)
	if not _spend_cost(raw):
		return false
	if stone_units > 0 and not spend_good("cut_stone", float(stone_units)):
		_return_goods(raw, tile)  # can_pave_road checked both already, so this is defensive
		return false
	_pave_stone_debt = _pave_stone_debt + float(cost.get("cut_stone", 0.0)) - float(stone_units)
	place_road(tile, ROAD_PAVED)
	return true


# ---------------------------------------------------------------- rail track (ticket 37)

func track_at(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y):
		return false
	return track[MapState.idx(tile.x, tile.y)] != 0


## Why a rail track tile cannot be laid here: {"ok": bool, "reason": String}, shaped like can_place_channel. Track is
## its own layer, placed like road: on owned, buildable land, never under a building. A track tile and a road tile are
## different overlays and cannot share a tile (reason "road"; the same goes for a channel). The cost is
## LogisticsDef.track_cost_wood + track_cost_stone + track_cost_cut_stone per tile (1 wood, 1 stone, 1 cut stone).
## Reasons: out_of_bounds, locked_region, blocked_terrain, overlap, channel, track, wood, stone, cut_stone.
## Track on a water tile is a rail bridge at LogisticsDef.track_bridge_multiplier (3x) the track cost (ticket 91).
## A road tile takes track too (ticket 67, a level crossing): both layers stay set, and lifting one leaves the other.
func can_place_track(tile: Vector2i) -> Dictionary:
	if not MapState.in_bounds(tile.x, tile.y):
		return {"ok": false, "reason": "out_of_bounds"}
	if not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return {"ok": false, "reason": "locked_region"}
	var tid := map.terrain_id_at(tile.x, tile.y)
	var tdef := registry.get_terrain(tid)
	if tdef != null and not tdef.buildable and tid != "water":
		return {"ok": false, "reason": "blocked_terrain"}
	var i := MapState.idx(tile.x, tile.y)
	if occupancy[i] >= 0:
		return {"ok": false, "reason": "overlap"}
	if channels[i] != CHANNEL_NONE:
		return {"ok": false, "reason": "channel"}
	if track[i] != 0:
		return {"ok": false, "reason": "track"}
	var lg := registry.logistics
	var k := _track_factor(tile)
	if float(totals().get("wood", 0.0)) + Inventory.EPS < lg.track_cost_wood * k:
		return {"ok": false, "reason": "wood"}
	if float(totals().get("stone", 0.0)) + Inventory.EPS < lg.track_cost_stone * k:
		return {"ok": false, "reason": "stone"}
	if float(totals().get("cut_stone", 0.0)) + Inventory.EPS < lg.track_cost_cut_stone * k:
		return {"ok": false, "reason": "cut_stone"}
	return {"ok": true, "reason": ""}


## Lays one track tile, paying the LogisticsDef track cost from storage at once. False (nothing spent) when
## can_place_track says no. Bumps structure_version, so RailSystem rebuilds its links on the next query.
func place_track(tile: Vector2i) -> bool:
	if not can_place_track(tile)["ok"]:
		return false
	var lg := registry.logistics
	var k := _track_factor(tile)
	var raw := {"wood": lg.track_cost_wood * k, "stone": lg.track_cost_stone * k}
	if not _spend_cost(raw):
		return false
	if lg.track_cost_cut_stone > 0.0 and not spend_good("cut_stone", lg.track_cost_cut_stone * k):
		_return_goods(raw, tile)  # defensive: can_place_track checked both
		return false
	track[MapState.idx(tile.x, tile.y)] = 1
	grid_version += 1
	structure_version += 1
	_roads_dirty = true  # a track can join depots, which changes what counts as connected
	events.emit("track_changed", {"tile": tile, "laid": true})
	_recompute_connections()
	return true


## Cost multiplier of a track tile: the rail bridge factor on water, 1 on land.
func _track_factor(tile: Vector2i) -> float:
	return registry.logistics.track_bridge_multiplier if is_water_tile(tile) else 1.0


## True from the Conflux era on: the build bar and the T key offer track only then (place_track itself does not
## check the era, like place_road).
func track_unlocked() -> bool:
	var cur := registry.get_era(era_id())
	var c := registry.get_era("conflux")
	return cur == null or c == null or cur.order >= c.order


## Lifts a track tile, giving back LogisticsDef.demolish_refund of its cost to the nearest storage, like channels.
func remove_track(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or track[MapState.idx(tile.x, tile.y)] == 0:
		return false
	track[MapState.idx(tile.x, tile.y)] = 0
	grid_version += 1
	structure_version += 1
	_roads_dirty = true
	events.emit("track_changed", {"tile": tile, "laid": false})
	var lg := registry.logistics
	if lg != null:
		var refund := {}
		var k := _track_factor(tile)
		var w := lg.track_cost_wood * k * lg.demolish_refund
		var st := lg.track_cost_stone * k * lg.demolish_refund
		var c := lg.track_cost_cut_stone * k * lg.demolish_refund
		if w > Inventory.EPS:
			refund["wood"] = w
		if st > Inventory.EPS:
			refund["stone"] = st
		if c > Inventory.EPS:
			refund["cut_stone"] = c
		if not refund.is_empty():
			_return_goods(refund, tile)
	_recompute_connections()
	return true


# ---------------------------------------------------------------- irrigation channels

## True from the Village era on: the build bar and the C key offer channels only then (place_channel itself does
## not check the era, like place_road).
func channels_unlocked() -> bool:
	var cur := registry.get_era(era_id())
	var v := registry.get_era("village")
	return cur == null or v == null or cur.order >= v.order


func channel_at(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y):
		return false
	return channels[MapState.idx(tile.x, tile.y)] != CHANNEL_NONE


## Why an Irrigation Channel cannot be dug here: {"ok": bool, "reason": String}, shaped like can_place(). Channels
## are dug like roads: on owned, buildable land, never under a building or on a road (a channel and a road are
## different overlays of the same tile; pick one). They do not block walking. The last reason is "stone" when the
## settlement's storage holds less than WaterDef.channel_cost_stone of stone.
func can_place_channel(tile: Vector2i) -> Dictionary:
	if not MapState.in_bounds(tile.x, tile.y):
		return {"ok": false, "reason": "out_of_bounds"}
	if not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return {"ok": false, "reason": "locked_region"}
	var tid := map.terrain_id_at(tile.x, tile.y)
	var tdef := registry.get_terrain(tid)
	if tid == "water":
		return {"ok": false, "reason": "water"}
	if tdef != null and not tdef.buildable:
		return {"ok": false, "reason": "blocked_terrain"}
	var i := MapState.idx(tile.x, tile.y)
	if occupancy[i] >= 0:
		return {"ok": false, "reason": "overlap"}
	if roads[i] != ROAD_NONE:
		return {"ok": false, "reason": "road"}
	if channels[i] != CHANNEL_NONE:
		return {"ok": false, "reason": "channel"}
	if track[i] != 0:
		return {"ok": false, "reason": "track"}
	var def := registry.water
	var cost := def.channel_cost_stone if def != null else 0.0
	if float(totals().get("stone", 0.0)) + Inventory.EPS < cost:
		return {"ok": false, "reason": "stone"}
	return {"ok": true, "reason": ""}


## Digs one Irrigation Channel tile, paying WaterDef.channel_cost_stone from storage at once (1 stone per tile).
## Returns false when the tile is invalid or the stone is short; nothing is spent then.
## Wetness is rebuilt immediately so the player sees the effect without waiting for the day, and the daily pass
## (WaterSystem.on_day) still runs. Whether the channel flows is derived (WaterSystem.flowing_channels).
func place_channel(tile: Vector2i) -> bool:
	if not can_place_channel(tile)["ok"]:
		return false
	var def := registry.water
	var cost := def.channel_cost_stone if def != null else 0.0
	if not spend_good("stone", cost):
		return false
	channels[MapState.idx(tile.x, tile.y)] = CHANNEL_DUG
	grid_version += 1
	structure_version += 1
	events.emit("channel_changed", {"tile": tile, "level": CHANNEL_DUG})
	WaterSystem.recompute(self)
	return true


## Removes a channel, giving back LogisticsDef.demolish_refund of its cost into the nearest storage with room
## (measured from the tile; the Hearth at new game), spilling over to the next nearest, like demolish. The wet map is
## rebuilt immediately.
func remove_channel(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or channels[MapState.idx(tile.x, tile.y)] == CHANNEL_NONE:
		return false
	channels[MapState.idx(tile.x, tile.y)] = CHANNEL_NONE
	grid_version += 1
	structure_version += 1
	events.emit("channel_changed", {"tile": tile, "level": CHANNEL_NONE})
	var def := registry.water
	if def != null and registry.logistics != null:
		var refund := def.channel_cost_stone * registry.logistics.demolish_refund
		if refund > Inventory.EPS:
			_return_goods({"stone": refund}, tile)
	WaterSystem.recompute(self)
	return true


# ---------------------------------------------------------------- clear marks (ticket 100)

## Why a tile cannot be marked for clearing: {"ok": bool, "reason": String}. Marks go on forest, stump and rock tiles
## (terrain with clear hours) of owned regions that no building, road, channel or track covers; no cost.
func can_mark_clear(tile: Vector2i) -> Dictionary:
	if not MapState.in_bounds(tile.x, tile.y):
		return {"ok": false, "reason": "out_of_bounds"}
	if not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return {"ok": false, "reason": "locked_region"}
	var i := MapState.idx(tile.x, tile.y)
	if occupancy[i] >= 0:
		return {"ok": false, "reason": "overlap"}
	if roads[i] != ROAD_NONE or channels[i] != CHANNEL_NONE or track[i] != 0:
		return {"ok": false, "reason": "road"}
	var tdef := registry.get_terrain(map.terrain_id_at(tile.x, tile.y))
	if tdef == null or tdef.clear_hours <= 0.0:
		return {"ok": false, "reason": "not_clearable"}
	if is_plant_marked(tile):
		return {"ok": false, "reason": "plant_marked"}  # a tile carries one mark at most
	if is_clear_marked(tile):
		return {"ok": false, "reason": "marked"}
	return {"ok": true, "reason": ""}


## Command: mark a tile for builders to clear. False (nothing changes) when can_mark_clear refuses.
func mark_clear(tile: Vector2i) -> bool:
	var cs := get_system(ConstructionSystem) as ConstructionSystem
	if cs == null or not can_mark_clear(tile)["ok"]:
		return false
	cs.clear_marks[MapState.idx(tile.x, tile.y)] = 0.0
	cs.note_mark_added(self, MapState.idx(tile.x, tile.y))
	events.emit("clear_marks_changed", {"tile": tile, "marked": true, "cleared": false})
	refresh_population()  # builders' slots open for it
	return true


## Command: take the mark off a tile (work already done on it is lost). False when it was not marked.
func unmark_clear(tile: Vector2i) -> bool:
	var cs := get_system(ConstructionSystem) as ConstructionSystem
	if cs == null or not is_clear_marked(tile):
		return false
	var i := MapState.idx(tile.x, tile.y)
	cs.clear_marks.erase(i)
	cs.clear_far.erase(i)
	cs.note_mark_removed(self, i)
	events.emit("clear_marks_changed", {"tile": tile, "marked": false, "cleared": false})
	refresh_population()
	return true


func is_clear_marked(tile: Vector2i) -> bool:
	var cs := get_system(ConstructionSystem) as ConstructionSystem
	return cs != null and MapState.in_bounds(tile.x, tile.y) and cs.clear_marks.has(MapState.idx(tile.x, tile.y))


## Every marked tile, in tile index order.
func clear_marked_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cs := get_system(ConstructionSystem) as ConstructionSystem
	if cs == null:
		return out
	var idxs: Array = cs.clear_marks.keys()
	idxs.sort()
	for i: int in idxs:
		out.append(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH))
	return out


# ---------------------------------------------------------------- plant marks (ticket 101)

## Why a tile cannot be marked for planting: {"ok": bool, "reason": String}. Marks go on plain grass of owned regions
## with no blight and no building, road, channel or track; a tile with a clear mark is refused (not possible on grass,
## but the rule is the spec's); no cost.
func can_mark_plant(tile: Vector2i) -> Dictionary:
	if not MapState.in_bounds(tile.x, tile.y):
		return {"ok": false, "reason": "out_of_bounds"}
	if not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return {"ok": false, "reason": "locked_region"}
	var i := MapState.idx(tile.x, tile.y)
	if occupancy[i] >= 0:
		return {"ok": false, "reason": "overlap"}
	if roads[i] != ROAD_NONE or channels[i] != CHANNEL_NONE or track[i] != 0:
		return {"ok": false, "reason": "road"}
	if is_clear_marked(tile):
		return {"ok": false, "reason": "clear_marked"}
	if map.terrain_id_at(tile.x, tile.y) != "grass":
		return {"ok": false, "reason": "not_plantable"}
	if map.blight[i] != 0:
		return {"ok": false, "reason": "blighted"}
	if is_plant_marked(tile):
		return {"ok": false, "reason": "marked"}
	return {"ok": true, "reason": ""}


## Command: mark a tile for Foresters to plant. False (nothing changes) when can_mark_plant refuses.
func mark_plant(tile: Vector2i) -> bool:
	var fs := get_system(ForestSystem) as ForestSystem
	if fs == null or not can_mark_plant(tile)["ok"]:
		return false
	fs.plant_marks[MapState.idx(tile.x, tile.y)] = true
	events.emit("plant_marks_changed", {"tile": tile, "marked": true, "planted": false})
	return true


## Command: take the plant mark off a tile. False when it was not marked.
func unmark_plant(tile: Vector2i) -> bool:
	var fs := get_system(ForestSystem) as ForestSystem
	if fs == null or not is_plant_marked(tile):
		return false
	fs.plant_marks.erase(MapState.idx(tile.x, tile.y))
	events.emit("plant_marks_changed", {"tile": tile, "marked": false, "planted": false})
	return true


func is_plant_marked(tile: Vector2i) -> bool:
	var fs := get_system(ForestSystem) as ForestSystem
	return fs != null and MapState.in_bounds(tile.x, tile.y) and fs.plant_marks.has(MapState.idx(tile.x, tile.y))


## True when a plant-marked tile lies outside every Forester's radius (the "no Forester reaches it" hint).
func plant_mark_unreached(tile: Vector2i) -> bool:
	return is_plant_marked(tile) and not ForestSystem.reached(self, tile)


## Every plant-marked tile, in tile index order.
func plant_marked_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var fs := get_system(ForestSystem) as ForestSystem
	if fs == null:
		return out
	var idxs: Array = fs.plant_marks.keys()
	idxs.sort()
	for i: int in idxs:
		out.append(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH))
	return out


# ---------------------------------------------------------------- regions

## Regions bought since the start. The start region is free and not counted, so this indexes RegionsDef.prices.
func regions_bought() -> int:
	var n := 0
	for r in MapState.REGION_COUNT:
		if map.is_region_owned(r):
			n += 1
	return maxi(0, n - 1)


## Gold price of the next region bought: RegionsDef.prices[regions_bought()], then price_after for every further
## region (design.md section 4: 50, 100, 200, 350, 500, then 600 each).
func next_region_price() -> int:
	var rd := registry.regions
	if rd == null:
		return 0
	var i := regions_bought()
	return rd.prices[i] if i < rd.prices.size() else rd.price_after


## Whether region `r` can be bought now: {ok: bool, reason: String}. Reasons: "owned", "not_adjacent" (no owned
## region shares an edge with it), "gold" (treasury short of next_region_price), "unknown" (not a region index).
func can_buy_region(r: int) -> Dictionary:
	if r < 0 or r >= MapState.REGION_COUNT:
		return {"ok": false, "reason": "unknown"}
	if map.is_region_owned(r):
		return {"ok": false, "reason": "owned"}
	var adjacent := false
	for n in MapState.region_neighbours(r):
		if map.is_region_owned(n):
			adjacent = true
			break
	if not adjacent:
		return {"ok": false, "reason": "not_adjacent"}
	if gold + Inventory.EPS < float(next_region_price()):
		return {"ok": false, "reason": "gold"}
	return {"ok": true, "reason": ""}


## Command: buys region `r` (design.md section 4), paying next_region_price from the treasury. False and nothing
## spent when can_buy_region says no. Locked terrain stays visible, just dimmed (MapView reads region_owned), so the
## only version bump is structure_version (views redraw dimming and borders; nothing about walking changed).
func buy_region(r: int) -> bool:
	if not can_buy_region(r)["ok"]:
		return false
	var price := next_region_price()
	gold -= float(price)
	ResourceLedgerSystem.record_used(self, BuildingDef.GOLD, float(price), "region")
	map.set_region_owned(r, true)
	var rs := get_system(RegionSystem) as RegionSystem
	if rs != null:
		rs.apply_rewards(self, r)  # ticket 25b: rich vein, ruins, fertile valley, old forest, spring
	structure_version += 1
	events.emit("region_bought", {"region": r, "price": price, "gold": gold, "reward": map.get_region_reward(r)})
	return true


## Command: a staffed, idle Airship Dock starts a survey flight over locked region `r` (ticket 38); after
## RegionsDef.survey_days days the region's reward is revealed (event region_surveyed). False when no dock can fly it.
## See AirshipSystem.survey_refusal for the reasons.
func survey_region(r: int) -> bool:
	var air := get_system(AirshipSystem) as AirshipSystem
	return air != null and air.start_survey(self, r)


# ---------------------------------------------------------------- road connection

func _ring(b: Building) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := b.footprint()
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	return out


func _set_connected(b: Building, now: bool) -> void:
	if now != b.connected:
		b.connected = now
		events.emit("building_connection_changed", {"id": b.id, "connected": now})


## Sky road tiles reachable from a finished Sky Lift or island Airship Dock whose ground side is connected: roads on the
## sky layer touching the link's footprint ring, then every sky road joined to them. Island still state is ignored on
## purpose (a still island keeps its jobs; WalkerSystem is what refuses to carry anyone then).
func _reach_sky() -> void:
	_sky_reached.clear()
	var queue: Array[Vector2i] = []
	var sources: Array[Building] = []
	var ground_docks: Dictionary = {}  # region -> true, a finished connected ground dock stands there
	for b: Building in buildings.values():
		if b.site:
			continue
		if b.def.sky_lift and b.connected:
			sources.append(b)
		elif b.def.airship_dock and b.layer == Building.LAYER_GROUND and b.connected:
			ground_docks[map.get_region(b.origin.x, b.origin.y)] = true
	for b: Building in buildings.values():
		if not b.site and b.def.airship_dock and b.layer == Building.LAYER_SKY \
				and ground_docks.has(map.get_region(b.origin.x, b.origin.y)):
			sources.append(b)
	for b in sources:
		for t in _ring(b):
			if MapState.in_bounds(t.x, t.y) and sky_roads[MapState.idx(t.x, t.y)] != ROAD_NONE and not _sky_reached.has(t):
				_sky_reached[t] = true
				queue.append(t)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in Placement.DIRS:
			var n := c + d
			if MapState.in_bounds(n.x, n.y) and sky_roads[MapState.idx(n.x, n.y)] != ROAD_NONE and not _sky_reached.has(n):
				_sky_reached[n] = true
				queue.append(n)


## BFS over road tiles from the road tiles touching the Hearth; updates every building's connected flag (or only
## `only`'s when given and no road changed since the last BFS). Ends with refresh_population().
## The BFS result only depends on roads, so it is kept until a road is placed or removed (_roads_dirty).
func _recompute_connections(only: Building = null) -> void:
	if hearth == null:
		return
	var all := only == null
	var _roads_dirty_pass := _roads_dirty
	if _roads_dirty:
		all = true
		_roads_dirty = false
		_reached.clear()
		var queue: Array[Vector2i] = []
		for t in _ring(hearth):
			if road_at(t) != ROAD_NONE and not _reached.has(t):
				_reached[t] = true
				queue.append(t)
		var head := 0
		while head < queue.size():
			var c := queue[head]
			head += 1
			for d in Placement.DIRS:
				var n := c + d
				if not _reached.has(n) and road_at(n) != ROAD_NONE:
					_reached[n] = true
					queue.append(n)
	var rail := get_system(RailSystem) as RailSystem
	if _roads_dirty_pass and rail != null:
		rail.extend_reach(self, _reached)  # roads beside a depot reach every road beside a linked depot (ticket 37)
	var reached := _reached
	var check: Array = buildings.values() if all else [only]
	for b: Building in check:
		var now := b == hearth
		if not now and b.layer == Building.LAYER_GROUND:
			for t in _ring(b):
				if reached.has(t):
					now = true
					break
		if b.layer == Building.LAYER_GROUND:
			_set_connected(b, now)
	# Sky buildings reach the ground only through a Sky Lift or an island Airship Dock whose ground side is connected
	# (ticket 40c): a BFS over the island's sky roads, seeded beside those links, after the ground flags are final.
	if _roads_dirty_pass:
		_reach_sky()
	for b: Building in check:
		if b.layer != Building.LAYER_SKY:
			continue
		var now := false
		for t in _ring(b):
			if _sky_reached.has(t):
				now = true
				break
		_set_connected(b, now)
	refresh_population()
