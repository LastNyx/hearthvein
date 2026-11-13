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
	add_system(JobSystem.new())
	add_system(WalkerSystem.new())
	add_system(WaterSystem.new())  # before Production: the day's wet grid feeds the farm modifier
	add_system(FertilitySystem.new())  # before Production: supplies the farm fertility modifier
	add_system(ProductionSystem.new())
	add_system(HaulingSystem.new())
	add_system(ConstructionSystem.new())
	add_system(DimmingSystem.new())  # before Growth: darkness blocks the day's growth
	add_system(GrowthSystem.new())
	add_system(BlightSystem.new())  # blight first, so the day's health sees it
	add_system(PlanetHealthSystem.new())
	add_system(SpiritSystem.new())  # after Growth: reads its hunger and food-type report; after Planet: grief
	var prod := get_system(ProductionSystem) as ProductionSystem
	prod.modifiers.append(FertilitySystem.output_modifier)
	prod.modifiers.append(SpiritSystem.work_modifier)
	prod.modifiers.append(PlanetHealthSystem.vein_modifier)
	prod.modifiers.append(DimmingSystem.output_modifier)
	var sp := get_system(SpiritSystem) as SpiritSystem
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
		"buildings": bl,
		"citizens": cl,
		"hearth": hearth.id if hearth != null else -1,
		"gold": gold,
		"next_building_id": _next_building_id,
		"next_citizen_id": _next_citizen_id,
		"grid_version": grid_version,
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
	events.emit("building_completed", {"id": b.id, "def": b.def.id, "origin": b.origin})
	refresh_population()


func _init_buffers(b: Building) -> void:
	var def := b.def
	if def.storage_mode != "none":
		b.inventory = Inventory.new(def.storage_mode, float(def.storage_cap))
	if def.recipe != null and registry.logistics != null:
		b.door_buffer = Inventory.new("total", registry.logistics.door_buffer_cap)
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
	refresh_population()  # removing a building changes no road, so no connection can change
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
	return out


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
			n += b.def.housing_beds
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
	return occupancy[i] < 0 and channels[i] == CHANNEL_NONE


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
