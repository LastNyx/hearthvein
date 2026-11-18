class_name WalkerSystem
extends SimSystem
## Citizens walking on the tile grid (design.md section 6).
##
## Pathing: one AStarGrid2D over the whole map, 4-neighbour moves. Cost of entering a tile is
## (fastest speed / that tile's speed), so roads attract paths without making the heuristic inadmissible.
## The sky layer (ticket 40c) has a second AStarGrid2D (_sky_grid, void tiles solid, speeds from sky roads), and walkers
## use ONE global tile space: ground tile (x, y) is Vector2i(x, y), sky tile (x, y) is Vector2i(x, y + MapState.HEIGHT)
## (MapState.to_global / layer_of / local_of). Walker.tile, Walker.path, find_path, door_tile and tile_speed all speak
## global tiles; the renderer decodes by layer. find_path on one layer is that layer's grid. Across layers a path is a
## ground leg to a link, the crossing step, and a sky leg from the link's other end: the links are the finished Sky
## Lifts on the island (ground tile and the sky tile above it) and each finished island Airship Dock paired with the
## ground dock of its region. The crossing step costs LogisticsDef.lift_ride_seconds / dock_ride_seconds. The best link
## (lowest path_seconds) wins; sky to sky across two islands goes down one link and up another. An island that is
## still (40b) offers no links, no link means no path ([]).
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
## Departures are staggered (ticket 55): at a schedule hour every walker that wants to be somewhere else gets a
## seeded offset in [0, DEPART_WINDOW) from the map seed and the citizen id, and leaves when the hour has run that
## far (same offset every day, so saves and tests stay reproducible). Without this, ~600 A* runs landed in one
## tick at 06:00 and 18:00. Spreading them over the hour is also what people do. To keep the work day as long as
## before, the morning window is the hour BEFORE the shift (05:00-06:00, see _schedule_hour), so people arrive
## about when the shift starts; going home spreads over 18:00-19:00. A per-call planning budget bounds the work of
## a frame-sized step; a coarse step (step_hours) is not throttled, so nobody is stranded.
##
## "At work": is_at_work(citizen_id) is true only while the citizen stands at the door of their job building;
## a walking citizen is never at work. Production reads is_at_work / workers_at.

## Stable key this system's state is saved under (ticket 19); see SimSystem.save_key_of.
const SAVE_KEY := "walker"

const WORK_START_HOUR := 6
const WORK_END_HOUR := 18
## Widest seeded departure delay after a schedule hour, in game seconds.
const DEPART_WINDOW := GameClock.REAL_SECONDS_PER_HOUR
## Most path plans one on_seconds call may start; a frame at 1x needs about 4 with 600 citizens.
const PLAN_BUDGET := 8
## A step of at least this many game seconds counts as coarse and is not throttled by PLAN_BUDGET.
const COARSE_STEP := 0.25
## Most moving walkers re-routed per call after a grid change; the rest are queued.
const REPLAN_BUDGET := 12
## Departure bins per game second; the seeded offset is quantized to this so the queue sorts as plain ints.
const DEPART_BINS := 300
## Big towns (ticket 89b): from BAND_MIN_WALKERS walkers a frame-sized step advances one of BAND_COUNT bands of walkers
## per call, each with the game time that passed since its last turn (a walker moves at 20 Hz instead of 60 Hz and
## arrives at most BAND_COUNT - 1 frames late). Smaller settlements and coarse steps move everybody every call.
const BAND_MIN_WALKERS := 300
const BAND_COUNT := 3

var walkers: Dictionary = {}  # citizen id -> Walker, in citizen id order of creation

var _s: Settlement
var _grid: AStarGrid2D
var _speeds := PackedFloat32Array()
var _grid_version: int = -1
var _max_speed: float = 1.0
var _last_max_speed: float = -1.0
var _structure_version: int = -1
var _solid := PackedByteArray()  # per tile: 1 when the A* grid has it solid
var _cache: Dictionary = {}  # int key -> Array[Vector2i] (empty array = no path)
## Sky layer grid (same size as the ground's, indexed by local sky tile), built with the ground grid. Only walked over
## when an island exists; until then every cell stays solid and nothing is rewritten.
var _sky_grid: AStarGrid2D
var _sky_speeds := PackedFloat32Array()
var _sky_solid := PackedByteArray()
var _sky_structure: int = -1
var _sky_max: float = -1.0
var _sky_content: bool = false  # the sky grid has open cells (an island exists or did until the last refresh)
## island id -> Array of links {g: ground global tile, k: sky global tile, ride: seconds}, rebuilt lazily per grid version.
var _links: Dictionary = {}
var _links_ready: bool = false
var path_computations: int = 0  # for tests: how many real A* runs happened
## Departures scheduled for the current hour: citizen ids encoded as (depart_bin << 20 | id), sorted by that int,
## so the sort is the native int sort.
var _queue: Array[int] = []
var _queue_head: int = 0
var _replan_queue: Array[int] = []
var _replan_head: int = 0
var _hour_elapsed: float = 0.0
## Departure bin of each citizen, cached: the offset is a pure function of (map seed, id) and is asked for every
## hour by every walker. Cleared when a different map seed shows up.
var _bins: Dictionary = {}  # citizen id -> int bin
var _bins_seed: int = -1
## Decoded ids need 20 bits; the departure bin stays well below the rest of the int.
const _QUEUE_ID_MASK := 0xfffff
## Set by load_state() when the saved walker paths already match the saved layout: the first grid build must not
## re-plan them (a re-plan would rewrite paths and break the round trip). See load_state for when it is false.
var _from_save: bool = false
## Region -> [carry, paved speed factor] from completed Handcart Sheds, rebuilt at the start of on_seconds only when
## Settlement.structure_version or completion_version moved. Only read in
## _advance, where a hauler in such a region walks paved tiles faster (design.md section 6: 2.5 tiles/s).
var _handcart_zones: Dictionary = {}
## Cache key for _handcart_zones: Settlement (structure_version, completion_version) it was built at.
var _zones_key := Vector2i(-1, -1)
## Banded movement: walkers dealt into BAND_COUNT lists by citizen id, the game seconds each band is owed, whose turn it is.
## Runtime only: save_state() pays every band first.
var _bands: Array = []
var _bands_count: int = -1  # walkers.size() the lists were built for (-1 = rebuild)
var _band_owed := PackedFloat64Array()
var _band_turn: int = 0


func save_state() -> Dictionary:
	_pay_bands()
	var ws := []
	for id in walkers:
		ws.append([id, (walkers[id] as Walker).to_dict()])
	return {
		"walkers": ws,
		"grid_version": _grid_version,
		"hour_elapsed": _hour_elapsed,
		"queue": _queue.duplicate(),
		"queue_head": _queue_head,
		"replan_queue": _replan_queue.duplicate(),
		"replan_head": _replan_head,
	}


func load_state(d: Dictionary, settlement: Settlement) -> void:
	_s = settlement
	walkers.clear()
	for pair in d["walkers"]:
		walkers[int(pair[0])] = Walker.from_dict(pair[1])
	_hour_elapsed = float(d["hour_elapsed"])
	_queue.assign(d["queue"])
	_queue_head = int(d["queue_head"])
	_replan_queue.assign(d["replan_queue"])
	_replan_head = int(d["replan_head"])
	# The saved paths were planned on the grid of the saved `grid_version`. A road, building or terrain change made
	# after the last step bumps the settlement's version but the walker grid never saw it, so those paths are stale
	# and must be re-planned like the live settlement does on its next step. Only when the two agree can the restart
	# skip _replan_all().
	_from_save = int(d["grid_version"]) == settlement.grid_version
	_bands_count = -1
	_band_owed = PackedFloat64Array()


# ---------------------------------------------------------------- hooks

func on_seconds(settlement: Settlement, seconds: float) -> void:
	_s = settlement
	var zk := Vector2i(settlement.structure_version, settlement.completion_version)
	if zk != _zones_key:
		_zones_key = zk
		_handcart_zones = RegionSystem.handcart_zones(settlement)
	if walkers.size() != settlement.citizens.size():
		_sync()
	_refresh_grid()
	_drain_replans()
	_move(seconds)
	_hour_elapsed += seconds
	_dispatch_departures(seconds)


## Moves the walkers `seconds` along, in bands for a big town and a frame-sized step (see BAND_MIN_WALKERS).
func _move(seconds: float) -> void:
	if walkers.size() < BAND_MIN_WALKERS or seconds >= COARSE_STEP:
		_pay_bands()
		for w: Walker in walkers.values():
			if not w.path.is_empty():
				_advance(w, seconds)
		return
	if _bands_count != walkers.size() or _band_owed.size() != BAND_COUNT:
		_pay_bands()
		_bands_count = walkers.size()
		_bands = []
		for b in BAND_COUNT:
			_bands.append([])
		for id in walkers:
			(_bands[id % BAND_COUNT] as Array).append(walkers[id])
		_band_owed.resize(BAND_COUNT)
		_band_owed.fill(0.0)
	for b in BAND_COUNT:
		_band_owed[b] += seconds
	var owed := _band_owed[_band_turn]
	_band_owed[_band_turn] = 0.0
	for w: Walker in _bands[_band_turn]:
		if not w.path.is_empty():
			_advance(w, owed)
	_band_turn = (_band_turn + 1) % BAND_COUNT


## Moves every band by the time it is owed (before anything that needs walkers exactly where the clock says: a coarse
## step, a save, a settlement that shrank below the banding size).
func _pay_bands() -> void:
	if _bands_count < 0:
		return
	for b in mini(_band_owed.size(), _bands.size()):
		var owed := _band_owed[b]
		_band_owed[b] = 0.0
		if owed > 0.0:
			for w: Walker in _bands[b]:
				if not w.path.is_empty():
					_advance(w, owed)
	_bands_count = -1
	_band_turn = 0  # a save and its load both restart the rotation at band 0


func on_hour(settlement: Settlement) -> void:
	_s = settlement
	_pay_bands()  # the band lists are rebuilt from the synced walkers next step
	_sync()  # always: one citizen leaving and another arriving between two syncs keeps the count equal
	_refresh_grid()
	_hour_elapsed = 0.0
	_queue.clear()
	_queue_head = 0
	var hour := _schedule_hour()
	var map_seed := settlement.map.seed_used
	if map_seed != _bins_seed:
		_bins.clear()
		_bins_seed = map_seed
	for id in walkers:
		var w: Walker = walkers[id]
		if w.controlled:
			continue
		var want := _desired_building(settlement.citizens[id], hour)
		if want >= 0 and (w.blocked or w.dest_building != want):
			var bin: int = _bins.get(id, -1)
			if bin < 0:
				bin = _depart_bin(map_seed, id)
				_bins[id] = bin
			_queue.append((bin << 20) | id)
	_queue.sort()


## The hour the schedule is evaluated for. The last hour before the shift already uses the shift's hour: people set
## off for work spread over 05:00-06:00 so they arrive about when the shift starts and the work day keeps its length
## (a stagger after 06:00 would cut an average half hour off every work day). Going home spreads over 18:00-19:00.
func _schedule_hour() -> int:
	var h := _s.clock.hour()
	return WORK_START_HOUR if h == WORK_START_HOUR - 1 else h


## Departure time of a citizen after a schedule hour, as an int bin (1/DEPART_BINS game seconds).
static func _depart_bin(map_seed: int, citizen_id: int) -> int:
	return mini(int(depart_offset(map_seed, citizen_id) * DEPART_BINS), int(DEPART_WINDOW * DEPART_BINS))


## Seeded departure delay of a citizen after a schedule hour, in game seconds. Pure function of the map seed and
## the citizen id, so the same citizens leave at the same time every day and after a load.
static func depart_offset(map_seed: int, citizen_id: int) -> float:
	var h := ((citizen_id * 73856093) ^ (map_seed * 19349663)) & 0x7fffffff
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0x7fffffff
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0x7fffffff
	h ^= h >> 15
	return float(h & 0xffff) / 65536.0 * DEPART_WINDOW


## Start the walks whose departure time has come, at most PLAN_BUDGET per call. Entries whose walker no longer
## wants that building are dropped; the hour's own on_hour rebuilds the queue anyway.
func _dispatch_departures(seconds: float) -> void:
	var planned := 0
	# A coarse step (step_hours) covers many frames at once, so it is not throttled; a frame-sized one is.
	var budget := PLAN_BUDGET if seconds < COARSE_STEP else 1 << 30
	var hour := _schedule_hour()
	while _queue_head < _queue.size() and planned < budget:
		var key: int = _queue[_queue_head]
		if float(key >> 20) / DEPART_BINS > _hour_elapsed + 0.001:
			break
		_queue_head += 1
		var id: int = key & _QUEUE_ID_MASK
		var w: Walker = walkers.get(id)
		var c: Citizen = _s.citizens.get(id)
		if w == null or c == null or w.controlled:
			continue
		var want := _desired_building(c, hour)
		if want < 0 or not _s.buildings.has(want) or not (w.blocked or w.dest_building != want):
			continue
		walk_to_building(id, want)
		planned += 1


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
## Global tile (a sky building's door is on the sky layer, beside sky roads).
func door_tile(b: Building) -> Vector2i:
	var r := b.footprint()
	var roads := _s.roads_for_layer(b.layer)
	for t in b.tiles():
		for d in Placement.DIRS:
			var n: Vector2i = t + d
			if not r.has_point(n) and MapState.in_bounds(n.x, n.y) and roads[MapState.idx(n.x, n.y)] != Settlement.ROAD_NONE:
				return MapState.to_global(t, b.layer)
	return MapState.to_global(Vector2i(r.position.x + r.size.x / 2, r.end.y - 1), b.layer)


## Walking speed in tiles per second on a global tile (0 = impassable).
func tile_speed(tile: Vector2i) -> float:
	_refresh_grid()
	return _spd(tile)


## Seconds at 1x to walk a path as returned by find_path (the first tile is the start and costs nothing). A step
## between layers costs the lift or dock ride time.
func path_seconds(p: Array[Vector2i]) -> float:
	_refresh_grid()
	var t := 0.0
	for i in range(1, p.size()):
		t += _step_seconds(p[i - 1], p[i])
	return t


## Cached path from one global tile to another, start and end included, [] when unreachable. Start and end are
## walkable even when they are building doors. Crosses layers only through a lift or dock link (see class comment).
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_refresh_grid()
	if not MapState.in_bounds_global(from) or not MapState.in_bounds_global(to):
		return []
	var key := _gidx(from) * (MapState.WIDTH * MapState.HEIGHT * 2) + _gidx(to)
	if _cache.has(key):
		return _cache[key]
	var out: Array[Vector2i]
	var lf := MapState.layer_of(from)
	if lf == MapState.layer_of(to) and (lf == Building.LAYER_GROUND or _same_island(from, to)):
		out = _leg(from, to)
	else:
		out = _cross(from, to)
	_cache[key] = out
	return out


## True when two global sky tiles lie on one island (a tile on no island counts as same: its leg is simply blocked).
func _same_island(a: Vector2i, b: Vector2i) -> bool:
	var isys := _s.get_system(IslandSystem) as IslandSystem
	if isys == null:
		return true
	var ia := isys.island_at(MapState.local_of(a))
	return ia == null or ia == isys.island_at(MapState.local_of(b))


## A* on one layer's grid between two global tiles of that layer.
func _leg(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var sky := MapState.layer_of(from) == Building.LAYER_SKY
	var grid := _sky_grid if sky else _grid
	var spd := _sky_speeds if sky else _speeds
	var a := MapState.local_of(from)
	var b := MapState.local_of(to)
	var reopen: Array[Vector2i] = []
	for t in [a, b]:
		if grid.is_point_solid(t) and spd[MapState.idx(t.x, t.y)] > 0.0:
			grid.set_point_solid(t, false)
			reopen.append(t)
	var out: Array[Vector2i] = []
	if not grid.is_point_solid(a) and not grid.is_point_solid(b):
		path_computations += 1
		var ids := grid.get_id_path(a, b)
		if sky:
			for t in ids:
				out.append(MapState.to_global(t, Building.LAYER_SKY))
		else:
			out.assign(ids)
	for t in reopen:
		grid.set_point_solid(t, true)
	return out


## Path between two tiles on different layers (or two islands): the cheapest combination of links.
func _cross(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_ensure_links()
	var from_sky := MapState.layer_of(from) == Building.LAYER_SKY
	var to_sky := MapState.layer_of(to) == Building.LAYER_SKY
	var best: Array[Vector2i] = []
	var best_t := INF
	var from_links: Array = _links_at(from) if from_sky else [null]
	var to_links: Array = _links_at(to) if to_sky else [null]
	for la in from_links:
		for lb in to_links:
			var cand: Array[Vector2i] = []
			if la != null:  # the leg on the start island down to its link
				var down := find_path(from, la["k"])
				if down.is_empty():
					continue
				cand.append_array(down)
			var g_from: Vector2i = la["g"] if la != null else from
			var g_to: Vector2i = lb["g"] if lb != null else to
			var mid := find_path(g_from, g_to)
			if mid.is_empty():
				continue
			cand.append_array(mid)
			if lb != null:  # and the leg up from the link on the target island
				var up := find_path(lb["k"], to)
				if up.is_empty():
					continue
				cand.append_array(up)
			var secs := path_seconds(cand)
			if secs < best_t - 0.000001:
				best_t = secs
				best = cand
	return best


## Links of the island holding a global sky tile (empty when none or the island is still).
func _links_at(sky_tile: Vector2i) -> Array:
	var isys := _s.get_system(IslandSystem) as IslandSystem
	var isl := isys.island_at(MapState.local_of(sky_tile)) if isys != null else null
	return _links.get(isl.id, []) if isl != null else []


## Ride seconds of the step between a ground tile and a sky tile: a Sky Lift stands on the ground tile of a lift link,
## anything else is a dock crossing.
func _ride_seconds(a: Vector2i, b: Vector2i) -> float:
	var g := a if MapState.layer_of(a) == Building.LAYER_GROUND else b
	var occ: int = _s.occupancy[MapState.idx(g.x, g.y)]
	var host: Building = _s.buildings.get(occ) if occ >= 0 else null
	var lg := _s.registry.logistics
	var secs := lg.lift_ride_seconds if host != null and host.def.sky_lift else lg.dock_ride_seconds
	return maxf(secs, 0.001)


func _step_seconds(a: Vector2i, b: Vector2i) -> float:
	if MapState.layer_of(a) != MapState.layer_of(b):
		return _ride_seconds(a, b)
	return 1.0 / _spd(b)


func _ensure_links() -> void:
	if _links_ready:
		return
	_links_ready = true
	_links.clear()
	var isys := _s.get_system(IslandSystem) as IslandSystem
	if isys == null or isys.islands.is_empty():
		return
	var lg := _s.registry.logistics
	var ground_docks := {}  # region -> finished ground dock
	for b: Building in _s.buildings.values():
		if not b.site and b.def.airship_dock and b.layer == Building.LAYER_GROUND:
			ground_docks[_s.map.get_region(b.origin.x, b.origin.y)] = b
	for b: Building in _s.buildings.values():
		if b.site:
			continue
		var isl: Island = null
		var link := {}
		if b.def.sky_lift:
			isl = isys.island_at(b.origin)
			link = {"g": b.origin, "k": MapState.to_global(b.origin, Building.LAYER_SKY), "ride": lg.lift_ride_seconds}
		elif b.def.airship_dock and b.layer == Building.LAYER_SKY:
			isl = isys.island_at(b.origin)
			var gd: Building = ground_docks.get(_s.map.get_region(b.origin.x, b.origin.y))
			if gd != null:
				link = {"g": door_tile(gd), "k": door_tile(b), "ride": lg.dock_ride_seconds}
		if isl == null or link.is_empty() or isl.still_why != "":
			continue  # a still island carries nobody
		if not _links.has(isl.id):
			_links[isl.id] = []
		(_links[isl.id] as Array).append(link)


## Rough tiles between two global tiles for pickers that must not run A*: Manhattan on one layer, and across layers (or
## islands) Manhattan to the nearest link plus the ride (1 tile per second) plus Manhattan from it. INF when no link.
func estimate_distance(s: Settlement, a: Vector2i, b: Vector2i) -> float:
	_s = s
	_refresh_grid()
	var la := MapState.layer_of(a)
	var lb := MapState.layer_of(b)
	if la == lb and (la == Building.LAYER_GROUND or _same_island(a, b)):
		return _manhattan(a, b)
	_ensure_links()
	var best := INF
	var a_links: Array = _links_at(a) if la == Building.LAYER_SKY else [null]
	var b_links: Array = _links_at(b) if lb == Building.LAYER_SKY else [null]
	for x in a_links:
		for y in b_links:
			var d := 0.0
			var at_g := a
			if x != null:
				d += _manhattan(a, x["k"]) + float(x["ride"])
				at_g = x["g"]
			var to_g := b
			if y != null:
				d += _manhattan(y["k"], b) + float(y["ride"])
				to_g = y["g"]
			d += _manhattan(at_g, to_g)
			best = minf(best, d)
	return best


static func _manhattan(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))


static func _gidx(g: Vector2i) -> int:
	return g.y * MapState.WIDTH + g.x


## Speed of a global tile.
func _spd(g: Vector2i) -> float:
	if g.y >= MapState.HEIGHT:
		return _sky_speeds[MapState.idx(g.x, g.y - MapState.HEIGHT)]
	return _speeds[MapState.idx(g.x, g.y)]


## Building id standing on a global tile (a Sky Lift counts on both layers), -1 for none.
func _occ_id(g: Vector2i) -> int:
	if g.y >= MapState.HEIGHT:
		return _s.sky_occupancy[MapState.idx(g.x, g.y - MapState.HEIGHT)]
	return _s.occupancy[MapState.idx(g.x, g.y)]


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
	_links_ready = false
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
	# Only touch the A* cells that changed. A felled tree used to rewrite all 16k cells (ticket 55: ~14 ms, a hitch
	# in the middle of a work day), so a terrain-only change updates just the tiles Settlement listed.
	var force := first or _max_speed != _last_max_speed
	_last_max_speed = _max_speed
	if force:
		_solid.resize(n)
	if force or _structure_version != _s.structure_version:
		_scan_ground(terrain_speed, force)
	else:
		for t in _s.terrain_dirty:
			_update_cell(t.x, t.y, terrain_speed, false)
	_structure_version = _s.structure_version
	_s.terrain_dirty.clear()
	_refresh_sky(first)
	if first and _from_save:
		_from_save = false  # saved walkers already sit on the saved layout; keep their paths as they were
		return
	_replan_all()


## Copies of the settlement's tile arrays as the last scan saw them (a Packed array assignment shares it, so duplicate()).
## A structure change used to rewrite all 12k cells of each grid (about 12 ms each, a hitch at
## every building or island change, ticket 89b); now only the tiles whose terrain, road or occupancy differ from this are
## looked at, and nothing at all when the arrays are the same (an island going still or waking up changes no tile).
var _seen_occ := PackedInt32Array()
var _seen_roads := PackedByteArray()
var _seen_terrain := PackedByteArray()
var _seen_sky_occ := PackedInt32Array()
var _seen_sky_roads := PackedByteArray()
var _seen_sky_terrain := PackedByteArray()


func _scan_ground(terrain_speed: Array[float], force: bool) -> void:
	var occ := _s.occupancy
	var rds := _s.roads
	var ter := _s.map.terrain
	if force or _seen_occ.size() != occ.size():
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				_update_cell(x, y, terrain_speed, force)
	elif occ != _seen_occ or rds != _seen_roads or ter != _seen_terrain:
		for i in occ.size():
			if occ[i] != _seen_occ[i] or rds[i] != _seen_roads[i] or ter[i] != _seen_terrain[i]:
				_update_cell(i % MapState.WIDTH, i / MapState.WIDTH, terrain_speed, false)
	_seen_occ = occ.duplicate()
	_seen_roads = rds.duplicate()
	_seen_terrain = ter.duplicate()


func _scan_sky(stone_speed: float, force: bool) -> void:
	var occ := _s.sky_occupancy
	var rds := _s.sky_roads
	var ter := _s.sky_map.terrain
	if force or _seen_sky_occ.size() != occ.size():
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				_update_sky_cell(x, y, stone_speed, force)
	elif occ != _seen_sky_occ or rds != _seen_sky_roads or ter != _seen_sky_terrain:
		for i in occ.size():
			if occ[i] != _seen_sky_occ[i] or rds[i] != _seen_sky_roads[i] or ter[i] != _seen_sky_terrain[i]:
				_update_sky_cell(i % MapState.WIDTH, i / MapState.WIDTH, stone_speed, false)
	_seen_sky_occ = occ.duplicate()
	_seen_sky_roads = rds.duplicate()
	_seen_sky_terrain = ter.duplicate()


## Sky grid: only touched while an island exists (or just stopped existing); void tiles and buildings are solid.
func _refresh_sky(first: bool) -> void:
	var n := MapState.WIDTH * MapState.HEIGHT
	if first:
		_sky_grid = AStarGrid2D.new()
		_sky_grid.region = Rect2i(0, 0, MapState.WIDTH, MapState.HEIGHT)
		_sky_grid.cell_size = Vector2.ONE
		_sky_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		_sky_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		_sky_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		_sky_grid.update()
		_sky_grid.fill_solid_region(_sky_grid.region, true)
		_sky_speeds.resize(n)
		_sky_solid.resize(n)
		_sky_solid.fill(1)
	var isys := _s.get_system(IslandSystem) as IslandSystem
	var active := isys != null and not isys.islands.is_empty()
	if not active and not _sky_content:
		return
	var force := _sky_max != _max_speed
	if force or _sky_structure != _s.structure_version:
		var stone := _s.registry.get_terrain(MapState.SKY_STONE)
		var stone_speed := stone.walk_speed if stone != null else 1.0
		_scan_sky(stone_speed, force)
	_sky_max = _max_speed
	_sky_structure = _s.structure_version
	_sky_content = active


func _update_sky_cell(x: int, y: int, stone_speed: float, force: bool) -> void:
	var i := MapState.idx(x, y)
	var sp := stone_speed if _s.sky_map.terrain_id_at(x, y) == MapState.SKY_STONE else 0.0
	if sp > 0.0 and _s.sky_roads[i] != Settlement.ROAD_NONE:
		var rd := _s.registry.get_road_by_level(_s.sky_roads[i])
		if rd != null:
			sp = rd.walk_speed
	var solid := 1 if (sp <= 0.0 or _s.sky_occupancy[i] >= 0) else 0
	if not force and _sky_speeds[i] == sp and _sky_solid[i] == solid:
		return
	_sky_speeds[i] = sp
	_sky_solid[i] = solid
	var p := Vector2i(x, y)
	_sky_grid.set_point_solid(p, solid == 1)
	_sky_grid.set_point_weight_scale(p, _max_speed / sp if sp > 0.0 else 1.0)


func _update_cell(x: int, y: int, terrain_speed: Array[float], force: bool) -> void:
	var i := MapState.idx(x, y)
	var sp: float = terrain_speed[_s.map.get_terrain(x, y)]
	var level := _s.roads[i]
	if level != Settlement.ROAD_NONE:
		var rd := _s.registry.get_road_by_level(level)
		if rd != null:
			sp = rd.walk_speed
	var solid := 1 if (sp <= 0.0 or _s.occupancy[i] >= 0) else 0
	if not force and _speeds[i] == sp and _solid[i] == solid:
		return
	_speeds[i] = sp
	_solid[i] = solid
	var p := Vector2i(x, y)
	_grid.set_point_solid(p, solid == 1)
	_grid.set_point_weight_scale(p, _max_speed / sp if sp > 0.0 else 1.0)


## Paved speed multiplier for a walker: a hauler whose job building is in a region with a completed Handcart Shed
## moves 1.25x on paved tiles (design.md section 6: 2.5 tiles/s), everyone else 1.0. _handcart_zones is refreshed at
## the start of each on_seconds call, so the walker's own citizen/job lookup is all that is left per tile.
func _paved_haul_factor(citizen_id: int) -> float:
	var c: Citizen = _s.citizens.get(citizen_id)
	if c == null or c.job_kind != Citizen.JOB_HAUL or c.job_id < 0:
		return 1.0
	var b: Building = _s.buildings.get(c.job_id)
	if b == null:
		return 1.0
	return float(_handcart_zones.get(_s.map.get_region(b.origin.x, b.origin.y), [0.0, 1.0])[1])


func _passable(t: Vector2i) -> bool:
	if not MapState.in_bounds_global(t):
		return false
	var grid := _sky_grid if t.y >= MapState.HEIGHT else _grid
	return _spd(t) > 0.0 and not grid.is_point_solid(MapState.local_of(t))


## Roads, buildings or terrain changed: doors move, standing walkers follow, moving walkers get fresh paths. The
## first REPLAN_BUDGET moving walkers are re-routed at once; the rest wait in a queue that on_seconds drains, so one
## felled tree with 600 citizens on the road is a few cheap frames instead of one 15 ms one (ticket 55). A small
## settlement never reaches the budget and behaves exactly as before.
func _replan_all() -> void:
	_replan_queue.clear()
	_replan_head = 0
	var routed := 0
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
			elif not _passable(w.tile) and _spd(w.tile) > 0.0 and _occ_id(w.tile) >= 0:
				w.tile = _nearest_passable(w.tile)
			continue
		if routed >= REPLAN_BUDGET:
			_replan_queue.append(id)
			continue
		routed += 1
		_replan_walker(w)


func _replan_walker(w: Walker) -> void:
	if w.dest_building >= 0:
		var db: Building = _s.buildings.get(w.dest_building)
		if db == null:
			# Destination is gone: stop here, the schedule picks a new one next hour.
			_stop(w)
			return
		w.dest_tile = door_tile(db)
	_route(w, w.dest_tile, w.dest_building)


## Re-route queued walkers, at most REPLAN_BUDGET per call.
func _drain_replans() -> void:
	var n := 0
	while _replan_head < _replan_queue.size() and n < REPLAN_BUDGET:
		var w: Walker = walkers.get(_replan_queue[_replan_head])
		_replan_head += 1
		if w != null and not w.path.is_empty() and not w.controlled:
			_replan_walker(w)
			n += 1


func _stop(w: Walker) -> void:
	if w.progress >= 0.5 and not w.path.is_empty():
		w.tile = w.path[0]
	w.path.clear()
	w.progress = 0.0
	w.dest_building = -1
	w.at_building = -1


func _nearest_passable(t: Vector2i) -> Vector2i:
	var layer := MapState.layer_of(t)
	var l := MapState.local_of(t)
	for r in range(1, 12):
		for y in range(l.y - r, l.y + r + 1):
			for x in range(l.x - r, l.x + r + 1):
				var c := MapState.to_global(Vector2i(x, y), layer)
				if MapState.in_bounds(x, y) and _passable(c):
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
	return _passable(t) or (MapState.in_bounds_global(t) and _spd(t) > 0.0 and _occ_id(t) >= 0)


func _advance(w: Walker, seconds: float) -> void:
	var budget := seconds
	var h := MapState.HEIGHT
	while not w.path.is_empty():
		var nxt := w.path[0]
		var sp: float
		var sky := nxt.y >= h
		if sky != (w.tile.y >= h):
			sp = 1.0 / _ride_seconds(w.tile, nxt)  # a lift or dock crossing
		else:
			# MapState.layer_of / local_of / idx / roads_for_layer inlined: this runs for every moving walker every frame.
			var li := (nxt.y - h if sky else nxt.y) * MapState.WIDTH + nxt.x
			if sky:
				sp = _sky_speeds[li]
				if _s.sky_roads[li] == Settlement.ROAD_PAVED:
					sp *= _paved_haul_factor(w.citizen_id)
			else:
				sp = _speeds[li]
				if _s.roads[li] == Settlement.ROAD_PAVED:
					sp *= _paved_haul_factor(w.citizen_id)
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
