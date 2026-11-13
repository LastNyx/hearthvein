class_name Settlement
extends RefCounted
## The central simulation object. Holds registry, map, clock, event bus and a list of systems.
## Features are added as SimSystem subclasses, not by growing this class.

var registry: DataRegistry
var map: MapState
var clock := GameClock.new()
var events := EventBus.new()
var systems: Array[SimSystem] = []

const ROAD_NONE := 0
const ROAD_DIRT := 1
const ROAD_PAVED := 2  # stored only for now; the paving tool comes in Town

## Building instances by id, plus an occupancy grid (building id per tile, -1 free) and a road grid.
var buildings: Dictionary = {}  # int -> Building
var occupancy := PackedInt32Array()
var roads := PackedByteArray()
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
## Game seconds already spent inside the current hour (only non-zero between step_seconds calls).
var _hour_acc: float = 0.0


static func new_game(seed: int, reg: DataRegistry) -> Settlement:
	var s := Settlement.new()
	s.registry = reg
	s.map = MapGen.generate(seed, reg)
	s.occupancy.resize(MapState.WIDTH * MapState.HEIGHT)
	s.occupancy.fill(-1)
	s.roads.resize(MapState.WIDTH * MapState.HEIGHT)
	var hdef := reg.get_building("hearth")
	if hdef != null and s.map.hearth_spot.x >= 0:
		s.hearth = s._insert_building(hdef, s.map.hearth_spot, false)
		for g in START_STOCK:
			s.hearth.inventory.add(g, START_STOCK[g])
		s.place_road(s.map.hearth_spot + Vector2i(hdef.size.x, 0))
		for i in START_CITIZENS:
			s.add_citizen()
	s.add_default_systems()
	return s


## Every game system a real game runs, in hook order. Each feature ticket appends its system here.
func add_default_systems() -> void:
	add_system(StorageSystem.new())
	add_system(JobSystem.new())
	add_system(WalkerSystem.new())
	add_system(ProductionSystem.new())
	add_system(HaulingSystem.new())
	add_system(ConstructionSystem.new())
	add_system(GrowthSystem.new())


func add_system(system: SimSystem) -> void:
	systems.append(system)


## Deterministic advance, one hour at a time. Per hour: on_seconds hooks get the hour's game seconds, the clock
## moves, then on_hour hooks run; when the new hour starts a day, day_started is emitted and on_day hooks run;
## likewise season_started / on_season.
func step_hours(n: int) -> void:
	for i in n:
		var rest := GameClock.REAL_SECONDS_PER_HOUR - _hour_acc
		_hour_acc = 0.0
		for sys in systems:
			sys.on_seconds(self, rest)
		_advance_hour()


## Finer seam for movement: advance `seconds` of game time (1x seconds). on_seconds hooks see the time in pieces that
## never cross an hour boundary; every completed hour runs exactly the hooks step_hours(1) would.
func step_seconds(seconds: float) -> void:
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


func _advance_hour() -> void:
	clock.total_hours += 1
	events.now_hours = clock.total_hours
	for sys in systems:
		sys.on_hour(self)
	if clock.is_day_start():
		events.emit("day_started", {"day": clock.day(), "season": clock.season_name(), "year": clock.year()})
		for sys in systems:
			sys.on_day(self)
		if clock.is_season_start():
			events.emit("season_started", {"season": clock.season_name(), "year": clock.year()})
			for sys in systems:
				sys.on_season(self)


## The registered system of a class, or null.
func get_system(script: GDScript) -> SimSystem:
	for sys in systems:
		if is_instance_of(sys, script):
			return sys
	return null


func step_days(n: int) -> void:
	step_hours(n * GameClock.HOURS_PER_DAY)


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
func can_place(def_id: String, origin: Vector2i) -> Dictionary:
	var def := registry.get_building(def_id)
	if def == null:
		return {"ok": false, "reason": "unknown_building"}
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
func place_building_instant(def_id: String, origin: Vector2i) -> int:
	if not can_place(def_id, origin)["ok"]:
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
	for t in b.tiles():
		occupancy[MapState.idx(t.x, t.y)] = b.id
	_recompute_connections()
	refresh_population()
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
	var refund := _refund_for(b)
	_return_goods(refund, b.origin)
	events.emit("building_demolished", {"id": id, "def": b.def.id, "origin": b.origin, "site": b.site, "refund": refund})
	_recompute_connections()
	refresh_population()
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
	events.emit("terrain_changed", {"tile": tile, "from": from, "to": terrain_id})
	return true


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


## SPIRIT SEAM for ticket 13. Spirit (0-100, D18) is owned by ticket 13; everything else reads it only through this
## function. Until then it returns `spirit_override` when set (tests, debug), else GrowthDef.default_spirit.
## Ticket 13: change the body to return the real meter and keep the signature.
var spirit_override: float = -1.0


func spirit() -> float:
	if spirit_override >= 0.0:
		return spirit_override
	return registry.growth.default_spirit


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
	return occupancy[MapState.idx(tile.x, tile.y)] < 0


## Dirt by default; a higher level on an existing road upgrades it. Returns false when nothing changed.
func place_road(tile: Vector2i, level: int = ROAD_DIRT) -> bool:
	if not can_place_road(tile) or roads[MapState.idx(tile.x, tile.y)] >= level:
		return false
	roads[MapState.idx(tile.x, tile.y)] = level
	grid_version += 1
	events.emit("road_changed", {"tile": tile, "level": level})
	_recompute_connections()
	return true


func remove_road(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or roads[MapState.idx(tile.x, tile.y)] == ROAD_NONE:
		return false
	roads[MapState.idx(tile.x, tile.y)] = ROAD_NONE
	grid_version += 1
	events.emit("road_changed", {"tile": tile, "level": ROAD_NONE})
	_recompute_connections()
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


## BFS over road tiles from the road tiles touching the Hearth; updates every building's connected flag.
func _recompute_connections() -> void:
	if hearth == null:
		return
	var reached := {}
	var queue: Array[Vector2i] = []
	for t in _ring(hearth):
		if road_at(t) != ROAD_NONE and not reached.has(t):
			reached[t] = true
			queue.append(t)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in Placement.DIRS:
			var n := c + d
			if not reached.has(n) and road_at(n) != ROAD_NONE:
				reached[n] = true
				queue.append(n)
	for id in buildings:
		var b: Building = buildings[id]
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
