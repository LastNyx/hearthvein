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

## Placement is instant and free until ticket 11 (costs and construction) replaces _commit_placement.
var instant_build: bool = true
## Building instances by id, plus an occupancy grid (building id per tile, -1 free) and a road grid.
var buildings: Dictionary = {}  # int -> Building
var occupancy := PackedInt32Array()
var roads := PackedByteArray()
var hearth: Building = null
## Global gold counter. Gold is never stored in inventories.
var gold: float = 0.0
## New-game stock (design.md section 5), put in the Hearth.
const START_STOCK := {"food": 60.0, "materials": 40.0, "lumen": 10.0}
var _next_building_id: int = 0


static func new_game(seed: int, reg: DataRegistry) -> Settlement:
	var s := Settlement.new()
	s.registry = reg
	s.map = MapGen.generate(seed, reg)
	s.occupancy.resize(MapState.WIDTH * MapState.HEIGHT)
	s.occupancy.fill(-1)
	s.roads.resize(MapState.WIDTH * MapState.HEIGHT)
	var hdef := reg.get_building("hearth")
	if hdef != null and s.map.hearth_spot.x >= 0:
		s.hearth = s._insert_building(hdef, s.map.hearth_spot)
		for g in START_STOCK:
			s.hearth.inventory.add(g, START_STOCK[g])
		s.place_road(s.map.hearth_spot + Vector2i(hdef.size.x, 0))
	return s


func add_system(system: SimSystem) -> void:
	systems.append(system)


## Deterministic advance, one hour at a time. Per hour: clock moves, then on_hour hooks run; when the new
## hour starts a day, day_started is emitted and on_day hooks run; likewise season_started / on_season.
func step_hours(n: int) -> void:
	for i in n:
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


## Returns the new building id, or -1 when invalid.
func place_building(def_id: String, origin: Vector2i) -> int:
	if not can_place(def_id, origin)["ok"]:
		return -1
	var b := _commit_placement(registry.get_building(def_id), origin)
	return b.id if b != null else -1


## The single hook for ticket 11: charge the cost / create a construction site instead of an instant building.
func _commit_placement(def: BuildingDef, origin: Vector2i) -> Building:
	if not instant_build:
		return null
	var b := _insert_building(def, origin)
	events.emit("building_placed", {"id": b.id, "def": def.id, "origin": origin})
	return b


func _insert_building(def: BuildingDef, origin: Vector2i) -> Building:
	var b := Building.new()
	b.id = _next_building_id
	_next_building_id += 1
	b.def = def
	b.origin = origin
	if def.storage_mode != "none":
		b.inventory = Inventory.new(def.storage_mode, float(def.storage_cap))
	buildings[b.id] = b
	for t in b.tiles():
		occupancy[MapState.idx(t.x, t.y)] = b.id
	_recompute_connections()
	return b


func demolish(id: int) -> bool:
	var b: Building = buildings.get(id)
	if b == null or b == hearth:
		return false
	for t in b.tiles():
		occupancy[MapState.idx(t.x, t.y)] = -1
	# Contents of a demolished storehouse are lost for now; ticket 11 may refund.
	buildings.erase(id)
	events.emit("building_demolished", {"id": id, "def": b.def.id, "origin": b.origin})
	_recompute_connections()
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
	events.emit("road_changed", {"tile": tile, "level": level})
	_recompute_connections()
	return true


func remove_road(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y) or roads[MapState.idx(tile.x, tile.y)] == ROAD_NONE:
		return false
	roads[MapState.idx(tile.x, tile.y)] = ROAD_NONE
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
