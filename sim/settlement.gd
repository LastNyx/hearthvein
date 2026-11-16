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
var hearth: Building = null
## Global gold counter. Gold is never stored in inventories.
var gold: float = 0.0
## Citizens by id (plain sim objects, see Citizen). Housing and jobs are kept current by JobSystem.
var citizens: Dictionary = {}  # int -> Citizen
var _next_citizen_id: int = 0
## New-game stock (design.md section 5), put in the Hearth.
const START_STOCK := {"food": 60.0, "materials": 40.0, "lumen": 10.0}
const START_CITIZENS := 8
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
var terrain_dirty: Array[Vector2i] = []
## Bumped when a tile becomes forest (the only change that can bring a forest tile nearer to a woodcutter).
var forest_gain_version: int = 0
## Road reachability from the Hearth (see _recompute_connections).
var _reached := {}
var _roads_dirty := true
## Game seconds already spent inside the current hour (only non-zero between step_seconds calls).
var _hour_acc: float = 0.0


static func new_game(seed: int, reg: DataRegistry) -> Settlement:
	var s := Settlement.new()
	s.registry = reg
	s.map = MapGen.generate(seed, reg)
	s.occupancy.resize(MapState.WIDTH * MapState.HEIGHT)
	s.occupancy.fill(-1)
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
	WaterSystem.recompute(s)  # the map starts dry; a new game's first day should not wait for the day hook
	return s


## Every game system a real game runs, in hook order. Each feature ticket appends its system here.
func add_default_systems() -> void:
	add_system(EraSystem.new())
	add_system(StorageSystem.new())
	add_system(GridSystem.new())  # Lumen grid membership cache (ticket 36); no hooks, queried by Upkeep, Production, Hauling
	add_system(RailSystem.new())  # rail network cache (ticket 37); no hooks, queried by connections and 37b manifests
	add_system(JobSystem.new())
	add_system(WalkerSystem.new())
	add_system(WaterSystem.new())  # before Production: the day's wet grid feeds the farm modifier
	add_system(FoulingSystem.new())  # hourly river fouling; its modifier feeds Production (ticket 29c)
	add_system(FertilitySystem.new())  # before Production: supplies the farm fertility modifier
	add_system(ProductionSystem.new())
	add_system(UpkeepSystem.new())  # spends the day's Lumen before Production and Market gold read the flag
	add_system(HaulingSystem.new())
	add_system(ConstructionSystem.new())
	add_system(DimmingSystem.new())  # before Growth: darkness blocks the day's growth
	add_system(GrowthSystem.new())
	add_system(BlightSystem.new())  # blight first, so the day's health sees it
	add_system(CleaningSystem.new())  # cleaners clear after the spread, before the day's health is counted
	add_system(PlanetHealthSystem.new())
	add_system(ForestSystem.new())  # reads the day's planet health; stumps regrow and Foresters plant here
	add_system(MarketSystem.new())  # pays gold and caches Market reach; Spirit reads the reach for food variety
	add_system(CoverageSystem.new())  # caches covered homes (Shrine r6); Spirit reads it for the coverage factor
	add_system(RegionSystem.new())  # region rewards: modifier hooks, the spring wet pass and the one-time ruins claim
	add_system(SpiritSystem.new())  # after Growth: reads its hunger report; after Planet: grief
	var prod := get_system(ProductionSystem) as ProductionSystem
	prod.modifiers.append(FertilitySystem.output_modifier)
	prod.modifiers.append(SpiritSystem.work_modifier)
	prod.modifiers.append(PlanetHealthSystem.vein_modifier)
	prod.modifiers.append(DimmingSystem.output_modifier)
	prod.modifiers.append(RegionSystem.rich_vein_modifier)
	prod.modifiers.append(UpkeepSystem.output_modifier)
	prod.modifiers.append(FoulingSystem.output_modifier)
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


func add_system(system: SimSystem) -> void:
	systems.append(system)
	_system_cache.clear()


## Deterministic advance, one hour at a time. Per hour: on_seconds hooks get the hour's game seconds, the clock
## moves, then on_hour hooks run; when the new hour starts a day, day_started is emitted and on_day hooks run;
## likewise season_started / on_season.
func step_hours(n: int) -> void:
	_frame_step = false
	_run_deferred(true)
	for i in n:
		var rest := GameClock.REAL_SECONDS_PER_HOUR - _hour_acc
		_hour_acc = 0.0
		for sys in systems:
			sys.on_seconds(self, rest)
		_advance_hour()


## Finer seam for movement: advance `seconds` of game time (1x seconds). on_seconds hooks see the time in pieces that
## never cross an hour boundary; every completed hour runs exactly the hooks step_hours(1) would.
func step_seconds(seconds: float) -> void:
	# Day and season hooks of a frame-sized step run one system per following step (ticket 57c), a coarse step runs
	# them all at once.
	_frame_step = seconds < DEFER_BELOW_SECONDS
	_run_deferred(not _frame_step)
	var left := seconds
	while left > 0.0:
		var chunk := minf(left, GameClock.REAL_SECONDS_PER_HOUR - _hour_acc)
		for sys in systems:
			sys.on_seconds(self, chunk)
		left -= chunk
		_hour_acc += chunk
		if _hour_acc >= GameClock.REAL_SECONDS_PER_HOUR - 0.000001:
			_hour_acc = 0.0
			_advance_hour()


## Steps shorter than this (game seconds, 0.25 s = a frame at 15 fps and 1x) spread the day hooks over several steps.
const DEFER_BELOW_SECONDS := GameClock.REAL_SECONDS_PER_HOUR / 10.0

## Pending day/season work of the hour end that a frame-sized step spread out, in the order it runs (Callables).
## Runtime only: ticket 19 calls flush_deferred() before saving so nothing is pending in a save file.
var _deferred: Array[Callable] = []
var _deferred_head: int = 0
var _frame_step: bool = false  # inside a step_seconds call short enough to spread the day work


## Runs the next pending day/season item, or all of them.
func _run_deferred(all: bool) -> void:
	while _deferred_head < _deferred.size():
		var d: Callable = _deferred[_deferred_head]
		_deferred_head += 1
		d.call()
		if not all:
			break
	if _deferred_head >= _deferred.size():
		_deferred.clear()
		_deferred_head = 0


## Runs every pending day and season hook now (a save, or code that reads the sim right after a day change).
func flush_deferred() -> void:
	_run_deferred(true)


func _advance_hour() -> void:
	_run_deferred(true)  # a hook still pending from the last day must not run after this hour's
	clock.total_hours += 1
	events.now_hours = clock.total_hours
	for sys in systems:
		sys.on_hour(self)
	if clock.is_day_start():
		events.emit("day_started", {"day": clock.day(), "season": clock.season_name(), "year": clock.year()})
		for sys in systems:
			_deferred.append(sys.on_day.bind(self))
		if clock.is_season_start():
			_deferred.append(func() -> void:
				events.emit("season_started", {"season": clock.season_name(), "year": clock.year()}))
			for sys in systems:
				_deferred.append(sys.on_season.bind(self))
		if not _frame_step:
			_run_deferred(true)


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
	var bl := []
	for id in buildings:
		bl.append([id, (buildings[id] as Building).to_dict()])
	var cl := []
	for id in citizens:
		cl.append([id, (citizens[id] as Citizen).to_dict()])
	var sys_state := {}
	for sys in systems:
		var key := SimSystem.save_key_of(sys)
		if key != "":
			sys_state[key] = sys.save_state()
	var dirty := []
	for t in terrain_dirty:
		dirty.append(t)
	return {
		"map": map.to_dict(),
		"occupancy": occupancy,
		"roads": roads,
		"channels": channels,
		"track": track,
		"buildings": bl,
		"citizens": cl,
		"hearth": hearth.id if hearth != null else -1,
		"gold": gold,
		"next_building_id": _next_building_id,
		"next_citizen_id": _next_citizen_id,
		"grid_version": grid_version,
		"pave_stone_debt": _pave_stone_debt,
		"structure_version": structure_version,
		"forest_gain_version": forest_gain_version,
		"terrain_dirty": dirty,
		"hour_acc": _hour_acc,
		"clock": clock.to_dict(),
		"events": events.to_dict(),
		"era_current": era_current,
		"era_override": era_override,
		"planet_health_override": planet_health_override,
		"spirit_override": spirit_override,
		"systems": sys_state,
	}


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
	if d.has("track"):
		s.track = d["track"]
	else:  # a save from before rail track
		s.track.resize(MapState.WIDTH * MapState.HEIGHT)
	for pair in d["buildings"]:
		var b := Building.from_dict(pair[1], registry)
		if b == null:
			return null
		s.buildings[b.id] = b
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

func building_at(tile: Vector2i) -> Building:
	if not MapState.in_bounds(tile.x, tile.y):
		return null
	var id := occupancy[MapState.idx(tile.x, tile.y)]
	return buildings.get(id) if id >= 0 else null


func road_at(tile: Vector2i) -> int:
	if not MapState.in_bounds(tile.x, tile.y):
		return ROAD_NONE
	return roads[MapState.idx(tile.x, tile.y)]


## Returns {ok: bool, reason: String}. Reason is "" when ok.
## Reason "era_locked" when the building's era is later than era_id() (ticket 16); ignore_era skips only that check
## (used by place_building_instant, the debug/test path).
func can_place(def_id: String, origin: Vector2i, ignore_era: bool = false) -> Dictionary:
	var def := registry.get_building(def_id)
	if def == null:
		return {"ok": false, "reason": "unknown_building"}
	if not ignore_era and not is_unlocked(def):
		return {"ok": false, "reason": "era_locked"}
	if def_id == "hearth" and hearth != null:
		return {"ok": false, "reason": "unique"}
	if def.rail_depot and MapState.in_bounds(origin.x, origin.y):
		var region := map.get_region(origin.x, origin.y)
		for other: Building in buildings.values():
			if other.def.rail_depot and map.get_region(other.origin.x, other.origin.y) == region:
				return {"ok": false, "reason": "region_depot"}  # one Rail Depot per region, sites count
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			if not MapState.in_bounds(x, y):
				return {"ok": false, "reason": "out_of_bounds"}
			if not map.is_region_owned(map.get_region(x, y)):
				return {"ok": false, "reason": "locked_region"}
			var tid := map.terrain_id_at(x, y)
			if tid == "water":
				return {"ok": false, "reason": "water"}
			var tdef := registry.get_terrain(tid)
			if tdef != null and not tdef.buildable:
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
	return {"ok": true, "reason": ""}


## Normal play (D48): places a construction site and returns its building id, or -1 when invalid (see can_place) or
## when the gold part of the cost is not in the treasury. Gold is paid now; every other good is hauled to the site
## (HaulingSystem), then builders build it (ConstructionSystem). Priority via set_building_priority.
func place_building(def_id: String, origin: Vector2i) -> int:
	if not can_place(def_id, origin)["ok"]:
		return -1
	var def := registry.get_building(def_id)
	var g := float(def.cost.get(BuildingDef.GOLD, 0))
	if g > gold + Inventory.EPS:
		return -1
	gold -= g
	var b := _insert_building(def, origin, true)
	events.emit("building_placed", {"id": b.id, "def": def.id, "origin": origin, "site": true})
	refresh_population()
	return b.id


## Debug and test path: a finished building at once, free, no site. Never used by normal play (the build UI calls
## place_building). Same validity rules as place_building. Returns the building id, or -1.
## Bypasses the era lock (tests and tools may place later-era buildings).
func place_building_instant(def_id: String, origin: Vector2i) -> int:
	if not can_place(def_id, origin, true)["ok"]:
		return -1
	var def := registry.get_building(def_id)
	var b := _insert_building(def, origin, false)
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
	b.site = false
	b.input_buffer = null
	_init_buffers(b)
	completion_version += 1
	if b.def.rail_depot:
		_roads_dirty = true  # a finished depot can join road networks; refresh_population runs below
		_recompute_connections()
	events.emit("building_completed", {"id": b.id, "def": b.def.id, "origin": b.origin})
	refresh_population()


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


func _insert_building(def: BuildingDef, origin: Vector2i, as_site: bool = false) -> Building:
	var b := Building.new()
	b.id = _next_building_id
	_next_building_id += 1
	b.def = def
	b.origin = origin
	if as_site:
		b.site = true
		var cap := 0.0
		for g in def.cost:
			if g != BuildingDef.GOLD:
				cap = maxf(cap, float(def.cost[g]))
		b.input_buffer = Inventory.new("per_good", cap)
		b.build_work_needed = build_days(def) * float(registry.logistics.builder_crew)
	else:
		_init_buffers(b)
	buildings[b.id] = b
	grid_version += 1
	structure_version += 1
	for t in b.tiles():
		occupancy[MapState.idx(t.x, t.y)] = b.id
	if def.rail_depot and not as_site:
		_roads_dirty = true
	_recompute_connections(b)
	if hearth == null:
		refresh_population()  # the Hearth itself: no connection pass yet
	return b


func demolish(id: int) -> bool:
	var b: Building = buildings.get(id)
	if b == null or b == hearth:
		return false
	for t in b.tiles():
		occupancy[MapState.idx(t.x, t.y)] = -1
	# Contents of a demolished storehouse are lost.
	buildings.erase(id)
	grid_version += 1
	structure_version += 1
	var refund := _refund_for(b)
	_return_goods(refund, b.origin)
	events.emit("building_demolished", {"id": id, "def": b.def.id, "origin": b.origin, "site": b.site, "refund": refund})
	if b.def.rail_depot:
		_roads_dirty = true  # losing a depot can cut a rail link, and with it connections
		_recompute_connections()
	refresh_population()  # otherwise removing a building changes no road, so no connection can change
	return true


## What a demolish gives back (LogisticsDef.demolish_refund, 50%): of the full cost for a finished building, of the
## goods already delivered for a site (design.md is silent on sites, ticket 11 decided; the gold paid counts too).
## Goods in transit are not part of it: a hauler whose destination vanishes puts its load back at the source.
func _refund_for(b: Building) -> Dictionary:
	var share := registry.logistics.demolish_refund
	var out := {}
	for g in b.def.cost:
		var have := float(b.def.cost[g])
		if b.site and g != BuildingDef.GOLD:
			have = b.input_buffer.amount_of(g) if b.input_buffer != null else 0.0
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
func _return_goods(goods: Dictionary, from: Vector2i) -> void:
	for g in goods:
		var left: float = goods[g]
		if g == BuildingDef.GOLD:
			gold += left
			continue
		while left > Inventory.EPS:
			var st := find_storage_with_room(g, from)
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
	var built := false
	for b: Building in buildings.values():
		if not b.site and b.def.id == nxt.gate_landmark:
			built = true
			break
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
## Reasons: unknown_building, site (still under construction), category (not housing/food/materials/lumen),
## not_upgradable (the def carries no tiers), in_progress, max_tier, era_locked (tier II needs Town, tier III City;
## the eras live in data/tiers/tiers.tres), needs_wet (the target tier only works on wet ground and the footprint
## is not half wet, e.g. the Irrigated Farm).
func can_upgrade(building_id: int) -> Dictionary:
	var b: Building = buildings.get(building_id)
	if b == null:
		return {"ok": false, "reason": "unknown_building"}
	if b.site:
		return {"ok": false, "reason": "site"}
	if not BuildingDef.UPGRADABLE_CATEGORIES.has(b.def.category):
		return {"ok": false, "reason": "category"}
	if not b.def.upgradable or b.def.tiers.is_empty():
		return {"ok": false, "reason": "not_upgradable"}
	if b.upgrading():
		return {"ok": false, "reason": "in_progress"}
	if b.tier >= 1 + b.def.tiers.size():
		return {"ok": false, "reason": "max_tier"}
	if not tier_unlocked(b.tier + 1):
		return {"ok": false, "reason": "era_locked"}
	var target := b.tier_def(registry, b.tier + 1)
	if target != null and target.needs_wet and not WaterSystem.footprint_wet(self, b):
		return {"ok": false, "reason": "needs_wet"}
	return {"ok": true, "reason": ""}


## True when the era required by a tier (TierRuleDef.eras) is the current one or an earlier one.
func tier_unlocked(tier: int) -> bool:
	var rule := registry.tiers
	if rule == null:
		return true
	var req_id := rule.era_for(tier)
	if req_id == "":
		return true
	var cur := registry.get_era(era_id())
	var req := registry.get_era(req_id)
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
func find_storage_with_room(good: String, from: Vector2i, amount: float = 0.000001) -> Building:
	var best: Building = null
	var best_d := 0
	for id in buildings:
		var b: Building = buildings[id]
		if b.inventory == null or b.inventory.free_for(good) < amount:
			continue
		var d := 1 << 30
		for t in b.tiles():
			d = mini(d, absi(t.x - from.x) + absi(t.y - from.y))
		if best == null or d < best_d or (d == best_d and b.id < best.id):
			best = b
			best_d = d
	return best


func can_place_road(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or not map.is_region_owned(map.get_region(tile.x, tile.y)):
		return false
	var tid := map.terrain_id_at(tile.x, tile.y)
	var tdef := registry.get_terrain(tid)
	if tid == "water" or (tdef != null and not tdef.buildable):
		return false
	var i := MapState.idx(tile.x, tile.y)
	return occupancy[i] < 0 and channels[i] == CHANNEL_NONE and track[i] == 0


## Dirt by default; a higher level on an existing road upgrades it. Returns false when nothing changed.
func place_road(tile: Vector2i, level: int = ROAD_DIRT) -> bool:
	if not can_place_road(tile) or roads[MapState.idx(tile.x, tile.y)] >= level:
		return false
	roads[MapState.idx(tile.x, tile.y)] = level
	grid_version += 1
	structure_version += 1
	_roads_dirty = true
	events.emit("road_changed", {"tile": tile, "level": level})
	_recompute_connections()
	return true


func remove_road(tile: Vector2i) -> bool:
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
## tile or upgrades a dirt road. The cost is the paved RoadDef's `cost` (design.md section 6: 1 materials + 0.2 cut
## stone, Town). Cut stone is charged in whole units: each tile adds its 0.2 to a running debt and a whole unit is
## spent as the debt fills, so five tiles cost one stone and storage never holds a fraction of a good.
## Reasons: out_of_bounds, locked_region, water, blocked_terrain, overlap, channel, already_paved, era_locked,
## materials, cut_stone.
func can_pave_road(tile: Vector2i) -> Dictionary:
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
	if channels[i] != CHANNEL_NONE:
		return {"ok": false, "reason": "channel"}
	if track[i] != 0:
		return {"ok": false, "reason": "track"}
	if roads[i] >= ROAD_PAVED:
		return {"ok": false, "reason": "already_paved"}
	if not _road_unlocked(ROAD_PAVED):
		return {"ok": false, "reason": "era_locked"}
	var rd := registry.get_road_by_level(ROAD_PAVED)
	var cost: Dictionary = rd.cost if rd != null else {}
	if float(totals().get("materials", 0.0)) + Inventory.EPS < float(cost.get("materials", 0.0)):
		return {"ok": false, "reason": "materials"}
	if float(totals().get("cut_stone", 0.0)) + Inventory.EPS < float(_pave_stone_units(cost)):
		return {"ok": false, "reason": "cut_stone"}
	return {"ok": true, "reason": ""}


## Paves one tile, or upgrades a dirt road to paved, paying the paved RoadDef cost from storage at once (materials)
## and in whole cut-stone units as the debt fills. Returns false when can_pave_road says no; nothing is spent then.
## Bumps grid_version and structure_version through place_road, so walker paths re-plan with the faster tiles.
func pave_road(tile: Vector2i) -> bool:
	if not can_pave_road(tile)["ok"]:
		return false
	var rd := registry.get_road_by_level(ROAD_PAVED)
	var cost: Dictionary = rd.cost if rd != null else {}
	var materials := float(cost.get("materials", 0.0))
	var stone_units := _pave_stone_units(cost)
	if not spend_good("materials", materials):
		return false
	if stone_units > 0 and not spend_good("cut_stone", float(stone_units)):
		_return_goods({"materials": materials}, tile)  # can_pave_road checked both already, so this is defensive
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
## LogisticsDef.track_cost_materials + track_cost_cut_stone per tile (design.md section 8: 2 materials + 1 cut stone).
## Reasons: out_of_bounds, locked_region, water, blocked_terrain, overlap, road, channel, track, materials, cut_stone.
func can_place_track(tile: Vector2i) -> Dictionary:
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
	var lg := registry.logistics
	if float(totals().get("materials", 0.0)) + Inventory.EPS < lg.track_cost_materials:
		return {"ok": false, "reason": "materials"}
	if float(totals().get("cut_stone", 0.0)) + Inventory.EPS < lg.track_cost_cut_stone:
		return {"ok": false, "reason": "cut_stone"}
	return {"ok": true, "reason": ""}


## Lays one track tile, paying the LogisticsDef track cost from storage at once. False (nothing spent) when
## can_place_track says no. Bumps structure_version, so RailSystem rebuilds its links on the next query.
func place_track(tile: Vector2i) -> bool:
	if not can_place_track(tile)["ok"]:
		return false
	var lg := registry.logistics
	if not spend_good("materials", lg.track_cost_materials):
		return false
	if lg.track_cost_cut_stone > 0.0 and not spend_good("cut_stone", lg.track_cost_cut_stone):
		_return_goods({"materials": lg.track_cost_materials}, tile)  # defensive: can_place_track checked both
		return false
	track[MapState.idx(tile.x, tile.y)] = 1
	grid_version += 1
	structure_version += 1
	_roads_dirty = true  # a track can join depots, which changes what counts as connected
	events.emit("track_changed", {"tile": tile, "laid": true})
	_recompute_connections()
	return true


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
		var m := lg.track_cost_materials * lg.demolish_refund
		var c := lg.track_cost_cut_stone * lg.demolish_refund
		if m > Inventory.EPS:
			refund["materials"] = m
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
## different overlays of the same tile; pick one). They do not block walking. The last reason is "materials" when the
## settlement's storage holds less than WaterDef.channel_cost_materials of materials.
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
	var cost := def.channel_cost_materials if def != null else 0.0
	if float(totals().get("materials", 0.0)) + Inventory.EPS < cost:
		return {"ok": false, "reason": "materials"}
	return {"ok": true, "reason": ""}


## Digs one Irrigation Channel tile, paying WaterDef.channel_cost_materials from storage at once (design.md section 9:
## 1 materials per tile). Returns false when the tile is invalid or the materials are short; nothing is spent then.
## Wetness is rebuilt immediately so the player sees the effect without waiting for the day, and the daily pass
## (WaterSystem.on_day) still runs. Whether the channel flows is derived (WaterSystem.flowing_channels).
func place_channel(tile: Vector2i) -> bool:
	if not can_place_channel(tile)["ok"]:
		return false
	var def := registry.water
	var cost := def.channel_cost_materials if def != null else 0.0
	if not spend_good("materials", cost):
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
		var refund := def.channel_cost_materials * registry.logistics.demolish_refund
		if refund > Inventory.EPS:
			_return_goods({"materials": refund}, tile)
	WaterSystem.recompute(self)
	return true


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
	map.set_region_owned(r, true)
	var rs := get_system(RegionSystem) as RegionSystem
	if rs != null:
		rs.apply_rewards(self, r)  # ticket 25b: rich vein, ruins, fertile valley, old forest, spring
	structure_version += 1
	events.emit("region_bought", {"region": r, "price": price, "gold": gold, "reward": map.get_region_reward(r)})
	return true


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
		if not now:
			for t in _ring(b):
				if reached.has(t):
					now = true
					break
		if now != b.connected:
			b.connected = now
			events.emit("building_connection_changed", {"id": b.id, "connected": now})
	refresh_population()
