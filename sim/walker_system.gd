class_name WalkerSystem
extends SimSystem
## Citizens walking on the tile grid (design.md section 6).
##
## Pathing: one AStarGrid2D over the whole map, 4-neighbour moves. Cost of entering a tile is
## (fastest speed / that tile's speed), so roads attract paths without making the heuristic inadmissible.
## Speed comes from data: RoadDef.walk_speed on a road tile, else TerrainDef.walk_speed (0 = impassable).
## Time: speeds are tiles per game second at 1x; one game hour is GameClock.REAL_SECONDS_PER_HOUR (2.5) seconds.
## Entering a tile takes 1 / speed(entered tile) seconds.
##
## Buildings: every footprint tile is solid except the building's door, which is only opened for the walks that
## start or end there (so nobody cuts through a building). A building's door is the footprint tile that touches a
## road (first in tile order) or, with no road beside it, the south-centre footprint tile; it moves with roads.
##
## Caching: paths are cached by (from, to) and the whole cache plus the grid is dropped when
## Settlement.grid_version changes (any road or building change). Walkers in motion are re-planned then.
##
## Schedule (not a design number, so it lives here): citizens with a job walk to it at WORK_START_HOUR and
## everybody goes home at WORK_END_HOUR. Homeless citizens stay at the Hearth. Walkers with `controlled` set
## are skipped; ticket 10 haulers use walk_to_building / walk_to_tile and set it.
##
## "At work": is_at_work(citizen_id) is true only while the citizen stands at the door of their job building;
## a walking citizen is never at work. Production reads is_at_work / workers_at.

const WORK_START_HOUR := 6
const WORK_END_HOUR := 18

var walkers: Dictionary = {}  # citizen id -> Walker, in citizen id order of creation

var _s: Settlement
var _grid: AStarGrid2D
var _speeds := PackedFloat32Array()
var _grid_version: int = -1
var _max_speed: float = 1.0
var _cache: Dictionary = {}  # int key -> Array[Vector2i] (empty array = no path)
var path_computations: int = 0  # for tests: how many real A* runs happened


# ---------------------------------------------------------------- hooks

func on_seconds(settlement: Settlement, seconds: float) -> void:
	_s = settlement
	if walkers.size() != settlement.citizens.size():
		_sync()
	_refresh_grid()
	for id in walkers:
		var w: Walker = walkers[id]
		if not w.path.is_empty():
			_advance(w, seconds)


func on_hour(settlement: Settlement) -> void:
	_s = settlement
	_sync()
	_refresh_grid()
	var hour := settlement.clock.hour()
	for id in walkers:
		var w: Walker = walkers[id]
		if w.controlled:
			continue
		var want := _desired_building(settlement.citizens[id], hour)
		if want >= 0 and (w.blocked or w.dest_building != want):
			walk_to_building(id, want)


## Building id the schedule wants this citizen at, -1 for none.
func _desired_building(c: Citizen, hour: int) -> int:
	if c.job_id >= 0 and hour >= WORK_START_HOUR and hour < WORK_END_HOUR and _s.buildings.has(c.job_id):
		return c.job_id
	if c.home_id >= 0 and _s.buildings.has(c.home_id):
		return c.home_id
	return _s.hearth.id if _s.hearth != null else -1


# ---------------------------------------------------------------- queries

func walker_of(citizen_id: int) -> Walker:
	return walkers.get(citizen_id)


## True only while the citizen stands at their job building and is not walking.
func is_at_work(citizen_id: int) -> bool:
	var w: Walker = walkers.get(citizen_id)
	var c: Citizen = _s.citizens.get(citizen_id) if _s != null else null
	return w != null and c != null and c.job_id >= 0 and w.path.is_empty() and w.at_building == c.job_id


## Citizens currently at work in a building (all job kinds); ticket 10 scales output by this.
func workers_at(building_id: int) -> Array:
	var out: Array = []
	for id in walkers:
		var c: Citizen = _s.citizens.get(id)
		if c != null and c.job_id == building_id and is_at_work(id):
			out.append(id)
	return out


## One pass over all walkers: building id -> number of JOB_WORK citizens at work there right now. Same answer as
## counting workers_at per building, without scanning every walker once per building.
func work_counts() -> Dictionary:
	var out := {}
	for id in walkers:
		var w: Walker = walkers[id]
		if w.at_building < 0 or not w.path.is_empty():
			continue
		var c: Citizen = _s.citizens.get(id)
		if c != null and c.job_kind == Citizen.JOB_WORK and c.job_id == w.at_building:
			out[c.job_id] = out.get(c.job_id, 0) + 1
	return out


## The door tile of a building (see class comment).
func door_tile(b: Building) -> Vector2i:
	var r := b.footprint()
	for t in b.tiles():
		for d in Placement.DIRS:
			var n: Vector2i = t + d
			if not r.has_point(n) and _s.road_at(n) != Settlement.ROAD_NONE:
				return t
	return Vector2i(r.position.x + r.size.x / 2, r.end.y - 1)


## Walking speed in tiles per second on a tile (0 = impassable).
func tile_speed(tile: Vector2i) -> float:
	_refresh_grid()
	return _speeds[MapState.idx(tile.x, tile.y)]


## Seconds at 1x to walk a path as returned by find_path (the first tile is the start and costs nothing).
func path_seconds(p: Array[Vector2i]) -> float:
	_refresh_grid()
	var t := 0.0
	for i in range(1, p.size()):
		t += 1.0 / _speeds[MapState.idx(p[i].x, p[i].y)]
	return t


## Cached path from one tile to another, start and end included, [] when unreachable. Start and end are
## walkable even when they are building doors.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_refresh_grid()
	if not MapState.in_bounds(from.x, from.y) or not MapState.in_bounds(to.x, to.y):
		return []
	var key := MapState.idx(from.x, from.y) * MapState.WIDTH * MapState.HEIGHT + MapState.idx(to.x, to.y)
	if _cache.has(key):
		return _cache[key]
	var reopen: Array[Vector2i] = []
	for t in [from, to]:
		if _grid.is_point_solid(t) and _speeds[MapState.idx(t.x, t.y)] > 0.0:
			_grid.set_point_solid(t, false)
			reopen.append(t)
	var out: Array[Vector2i] = []
	if not _grid.is_point_solid(from) and not _grid.is_point_solid(to):
		path_computations += 1
		out.assign(_grid.get_id_path(from, to))
	for t in reopen:
		_grid.set_point_solid(t, true)
	_cache[key] = out
	return out


# ---------------------------------------------------------------- commands

## Send a citizen to a building door. False when the building is unknown or unreachable.
func walk_to_building(citizen_id: int, building_id: int) -> bool:
	var b: Building = _s.buildings.get(building_id)
	if b == null:
		return false
	_refresh_grid()
	return _route(walkers.get(citizen_id), door_tile(b), building_id)


## Send a citizen to any walkable tile.
func walk_to_tile(citizen_id: int, tile: Vector2i) -> bool:
	_refresh_grid()
	return _route(walkers.get(citizen_id), tile, -1)


## Put a walker on a tile at once (no walking). For setup and tests.
func place_walker(citizen_id: int, tile: Vector2i) -> void:
	var w: Walker = walkers.get(citizen_id)
	if w == null:
		return
	w.tile = tile
	w.path.clear()
	w.progress = 0.0
	w.at_building = -1
	w.dest_building = -1
	w.dest_tile = tile
	w.blocked = false


# ---------------------------------------------------------------- internals

## One walker per citizen. New ones appear at the Hearth door.
func _sync() -> void:
	for id in walkers.keys():
		if not _s.citizens.has(id):
			walkers.erase(id)
	var ids: Array = _s.citizens.keys()
	ids.sort()
	for id in ids:
		if not walkers.has(id):
			var w := Walker.new()
			w.citizen_id = id
			if _s.hearth != null:
				w.tile = door_tile(_s.hearth)
				w.at_building = _s.hearth.id
				w.dest_building = _s.hearth.id
				w.dest_tile = w.tile
			walkers[id] = w


func _refresh_grid() -> void:
	if _grid != null and _grid_version == _s.grid_version:
		return
	var first := _grid == null
	_grid_version = _s.grid_version
	_cache.clear()
	var n := MapState.WIDTH * MapState.HEIGHT
	if first:
		_grid = AStarGrid2D.new()
		_grid.region = Rect2i(0, 0, MapState.WIDTH, MapState.HEIGHT)
		_grid.cell_size = Vector2.ONE
		_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		_grid.update()
		_speeds.resize(n)
	_max_speed = 0.0
	for road: RoadDef in _s.registry.roads.values():
		_max_speed = maxf(_max_speed, road.walk_speed)
	var terrain_speed: Array[float] = []
	for id in _s.map.terrain_ids:
		var def := _s.registry.get_terrain(id)
		var sp := def.walk_speed if def != null else 1.0
		terrain_speed.append(sp)
		_max_speed = maxf(_max_speed, sp)
	if _max_speed <= 0.0:
		_max_speed = 1.0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var i := MapState.idx(x, y)
			var sp: float = terrain_speed[_s.map.get_terrain(x, y)]
			var level := _s.roads[i]
			if level != Settlement.ROAD_NONE:
				var rd := _s.registry.get_road_by_level(level)
				if rd != null:
					sp = rd.walk_speed
			_speeds[i] = sp
			var p := Vector2i(x, y)
			_grid.set_point_solid(p, sp <= 0.0 or _s.occupancy[i] >= 0)
			_grid.set_point_weight_scale(p, _max_speed / sp if sp > 0.0 else 1.0)
	_replan_all()


func _passable(t: Vector2i) -> bool:
	return MapState.in_bounds(t.x, t.y) and _speeds[MapState.idx(t.x, t.y)] > 0.0 and not _grid.is_point_solid(t)


## Roads or buildings changed: doors move, standing walkers follow, moving walkers get fresh paths.
func _replan_all() -> void:
	for id in walkers:
		var w: Walker = walkers[id]
		if w.path.is_empty():
			if w.at_building >= 0:
				var b: Building = _s.buildings.get(w.at_building)
				if b == null:
					w.at_building = -1
					w.dest_building = -1
				else:
					w.tile = door_tile(b)
					w.dest_tile = w.tile
			elif not _passable(w.tile) and _speeds[MapState.idx(w.tile.x, w.tile.y)] > 0.0 and _s.occupancy[MapState.idx(w.tile.x, w.tile.y)] >= 0:
				w.tile = _nearest_passable(w.tile)
			continue
		if w.dest_building >= 0:
			var db: Building = _s.buildings.get(w.dest_building)
			if db == null:
				# Destination is gone: stop here, the schedule picks a new one next hour.
				_stop(w)
				continue
			w.dest_tile = door_tile(db)
		_route(w, w.dest_tile, w.dest_building)


func _stop(w: Walker) -> void:
	if w.progress >= 0.5 and not w.path.is_empty():
		w.tile = w.path[0]
	w.path.clear()
	w.progress = 0.0
	w.dest_building = -1
	w.at_building = -1


func _nearest_passable(t: Vector2i) -> Vector2i:
	for r in range(1, 12):
		for y in range(t.y - r, t.y + r + 1):
			for x in range(t.x - r, t.x + r + 1):
				var c := Vector2i(x, y)
				if _passable(c):
					return c
	return t


## Plan from the walker's current position to `dest` and start walking. Returns false (and marks the walker
## blocked) when there is no path. A walker part-way along a step finishes that step first.
func _route(w: Walker, dest: Vector2i, building_id: int) -> bool:
	if w == null:
		return false
	w.dest_tile = dest
	w.dest_building = building_id
	var from := w.tile
	var keep_progress := false
	if not w.path.is_empty() and w.progress > 0.0 and _passable_or_door(w.path[0]):
		from = w.path[0]
		keep_progress = true
	var p := find_path(from, dest)
	if p.is_empty() and keep_progress:
		from = w.tile
		keep_progress = false
		p = find_path(from, dest)
	if p.is_empty():
		w.blocked = true
		w.path.clear()
		w.progress = 0.0
		return false
	w.blocked = false
	var nodes: Array[Vector2i] = []
	if keep_progress:
		nodes.assign(p)  # p[0] is the tile already being entered
	else:
		nodes.assign(p.slice(1))
		w.progress = 0.0
	w.path = nodes
	if not nodes.is_empty():
		w.at_building = -1
	else:
		_arrive(w)
	return true


func _passable_or_door(t: Vector2i) -> bool:
	return _passable(t) or (MapState.in_bounds(t.x, t.y) and _speeds[MapState.idx(t.x, t.y)] > 0.0
			and _s.occupancy[MapState.idx(t.x, t.y)] >= 0)


func _advance(w: Walker, seconds: float) -> void:
	var budget := seconds
	while not w.path.is_empty():
		var nxt := w.path[0]
		var sp := _speeds[MapState.idx(nxt.x, nxt.y)]
		var need := (1.0 - w.progress) / sp
		if budget >= need:
			budget -= need
			w.tile = nxt
			w.progress = 0.0
			w.path.remove_at(0)
		else:
			w.progress += budget * sp
			return
	_arrive(w)


func _arrive(w: Walker) -> void:
	w.progress = 0.0
	if w.dest_building >= 0:
		w.at_building = w.dest_building
		_s.events.emit("walker_arrived", {"id": w.citizen_id, "building": w.dest_building})
	else:
		w.at_building = -1
