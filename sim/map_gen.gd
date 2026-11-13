class_name MapGen
extends RefCounted
## Deterministic seeded map generation. All randomness comes from one RandomNumberGenerator
## and FastNoiseLite instances seeded from the given seed; never global randf.

const W := MapState.WIDTH
const H := MapState.HEIGHT
const BAND := MapState.EDGE_BAND

var _s: MapState
var _rng: RandomNumberGenerator
var _t_grass: int
var _t_fertile: int
var _t_forest: int
var _t_rock: int
var _t_water: int
var _t_vein: int


static func generate(seed: int, registry: DataRegistry) -> MapState:
	var g := MapGen.new()
	return g._run(seed, registry)


func _run(seed: int, registry: DataRegistry) -> MapState:
	var ids := PackedStringArray()
	var keys := registry.terrain.keys()
	keys.sort()
	for k in keys:
		ids.append(k)
	_s = MapState.new(ids)
	_s.seed_used = seed
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	_t_grass = _s.terrain_index("grass")
	_t_fertile = _s.terrain_index("fertile_soil")
	_t_forest = _s.terrain_index("forest")
	_t_rock = _s.terrain_index("rock")
	_t_water = _s.terrain_index("water")
	_t_vein = _s.terrain_index("lumen_vein")

	_s.start_region = [5, 6, 9, 10][_rng.randi_range(0, 3)]
	_base_terrain(seed)
	_carve_river()
	_place_hearth()
	_start_guarantees()
	_scatter_veins()
	_place_rewards()
	_init_fertility(registry)
	_s.set_region_owned(_s.start_region, true)
	return _s


# ---------- terrain ----------

func _noise(seed: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed & 0x7FFFFFFF
	n.frequency = freq
	return n


func _base_terrain(seed: int) -> void:
	var nf := _noise(seed + 1, 0.045)
	var nw := _noise(seed + 2, 0.06)
	var nr := _noise(seed + 3, 0.07)
	for y in H:
		for x in W:
			var t := _t_grass
			if not MapState.is_edge_band(x, y):
				if nr.get_noise_2d(x, y) > 0.42:
					t = _t_rock
				elif nw.get_noise_2d(x, y) > 0.22:
					t = _t_forest
				elif nf.get_noise_2d(x, y) > 0.2:
					t = _t_fertile
			elif nf.get_noise_2d(x, y) > 0.2:
				t = _t_fertile
			_s.set_terrain(x, y, t)


# ---------- river ----------

func _carve_river() -> void:
	var sr := _s.start_region
	var srow := sr / MapState.REGION_COLS
	var rect := MapState.region_rect(sr)
	var cy := rect.position.y + rect.size.y / 2
	var cx := rect.position.x + rect.size.x / 2
	var flip := _rng.randi() % 2 == 1  # flow east to west
	# Row 1 start: enter in the top row, leave in the bottom row; row 2 start: the reverse.
	var side := 1 if srow == 1 else -1
	var ya := _rng.randi_range(8, 20) if side == 1 else _rng.randi_range(75, 87)
	var yb := _rng.randi_range(75, 87) if side == 1 else _rng.randi_range(8, 20)
	var hu := (W - 1 - cx) if flip else cx  # progress coordinate of the start region centre
	var ys := cy + 7 * side

	var pts: Array[Vector2i] = [Vector2i(0, ya), Vector2i(7, ya)]
	_add_meander(pts, Vector2i(hu - 12, ys))
	pts.append(Vector2i(hu - 12, ys))
	pts.append(Vector2i(hu + 12, ys))
	_add_meander(pts, Vector2i(W - 8, yb))
	pts.append(Vector2i(W - 8, yb))
	pts.append(Vector2i(W - 1, yb))

	# 4-connected monotone-in-u walk through the waypoints.
	var visited := {}
	var path: Array[Vector2i] = [pts[0]]
	visited[pts[0]] = true
	var cur := pts[0]
	for i in range(1, pts.size()):
		var target := pts[i]
		while cur != target:
			var dx := target.x - cur.x
			var dy := target.y - cur.y
			var vertical := false
			if dx == 0:
				vertical = true
			elif dy != 0:
				vertical = _rng.randf() < float(absi(dy)) / float(absi(dx) + absi(dy))
			var nxt := cur + (Vector2i(0, signi(dy)) if vertical else Vector2i(1, 0))
			if vertical and visited.has(nxt):
				nxt = cur + Vector2i(1, 0)
			cur = nxt
			visited[cur] = true
			path.append(cur)

	# Map progress coordinates to real x and set flow directions.
	for i in path.size():
		var p := path[i]
		var real := Vector2i(W - 1 - p.x if flip else p.x, p.y)
		path[i] = real
	for i in path.size():
		var p := path[i]
		var d: int
		if i + 1 < path.size():
			var step := path[i + 1] - p
			d = FLOW_FROM_STEP[step]
		else:
			d = MapState.FLOW_W if flip else MapState.FLOW_E
		_s.set_terrain(p.x, p.y, _t_water)
		_s.set_flow(p.x, p.y, d)
	_s.river_path = path


const FLOW_FROM_STEP := {
	Vector2i(0, -1): MapState.FLOW_N,
	Vector2i(1, 0): MapState.FLOW_E,
	Vector2i(0, 1): MapState.FLOW_S,
	Vector2i(-1, 0): MapState.FLOW_W,
}


## Appends jittered waypoints between the last point and `to`, roughly every 12 tiles of progress.
func _add_meander(pts: Array[Vector2i], to: Vector2i) -> void:
	var from := pts[pts.size() - 1]
	var n := maxi(1, (to.x - from.x) / 12)
	for i in range(1, n):
		var u := from.x + (to.x - from.x) * i / n
		var y := from.y + (to.y - from.y) * i / n + _rng.randi_range(-4, 4)
		pts.append(Vector2i(u, clampi(y, 8, H - 9)))


# ---------- start region ----------

func _place_hearth() -> void:
	var rect := MapState.region_rect(_s.start_region)
	var centre := rect.position + rect.size / 2
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(rect.position.y + 6, rect.end.y - 6):
		for x in range(rect.position.x + 6, rect.end.x - 6):
			var d := (x - centre.x) * (x - centre.x) + (y - centre.y) * (y - centre.y)
			if d < best_d and _no_water_around(x, y, 3):
				best_d = d
				best = Vector2i(x, y)
	_s.hearth_spot = best
	# Clear a plain 7x7 patch for the Hearth and its first buildings.
	for y in range(best.y - 3, best.y + 4):
		for x in range(best.x - 3, best.x + 4):
			if _s.get_terrain(x, y) != _t_fertile:
				_s.set_terrain(x, y, _t_grass)


func _no_water_around(cx: int, cy: int, r: int) -> bool:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if _s.get_terrain(x, y) == _t_water:
				return false
	return true


func _start_guarantees() -> void:
	var rect := MapState.region_rect(_s.start_region)
	var h := _s.hearth_spot
	var used: Array[Vector2i] = []
	# Forest and rock blobs 5-6 tiles from the Hearth, in different directions.
	for kind in [_t_forest, _t_rock]:
		var placed := false
		for attempt in 60:
			var ang := _rng.randf() * TAU
			var dist := _rng.randf_range(5.0, 6.0)
			var c := h + Vector2i(roundi(cos(ang) * dist), roundi(sin(ang) * dist))
			if not rect.grow(-3).has_point(c):
				continue
			var clash := false
			for u in used:
				if u.distance_to(c) < 5.0:
					clash = true
			if clash or not _blob_ok(c, 2):
				continue
			_blob(c, 2.2, kind)
			used.append(c)
			placed = true
			break
		if not placed:
			# Fallback: always place a small blob due west/east/north/south of the Hearth.
			for off in [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6)]:
				var c: Vector2i = h + off
				if rect.grow(-2).has_point(c) and _blob_ok(c, 1):
					_blob(c, 1.6, kind)
					used.append(c)
					break
	# 3-5 vein tiles in the start region, 5-10 tiles from the Hearth.
	var count := _rng.randi_range(3, 5)
	var veins: Array[Vector2i] = []
	var tries := 0
	while veins.size() < count and tries < 2000:
		tries += 1
		var p := Vector2i(_rng.randi_range(rect.position.x + 2, rect.end.x - 3), _rng.randi_range(rect.position.y + 2, rect.end.y - 3))
		var d := p.distance_to(h)
		if d < 5.0 or d > 10.0:
			continue
		if _s.get_terrain(p.x, p.y) == _t_water or MapState.is_edge_band(p.x, p.y):
			continue
		_s.set_terrain(p.x, p.y, _t_vein)
		veins.append(p)


func _blob_ok(c: Vector2i, r: int) -> bool:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if not MapState.in_bounds(x, y) or _s.get_terrain(x, y) == _t_water:
				return false
	# Keep the Hearth's 7x7 clear patch free.
	return absi(c.x - _s.hearth_spot.x) > 3 + r or absi(c.y - _s.hearth_spot.y) > 3 + r


## Stamps a filled disc of `terrain_t`, skipping water and the edge band.
func _blob(c: Vector2i, radius: float, terrain_t: int) -> void:
	var r := ceili(radius)
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if not MapState.in_bounds(x, y) or MapState.is_edge_band(x, y):
				continue
			if Vector2(x - c.x, y - c.y).length() > radius:
				continue
			if _s.get_terrain(x, y) == _t_water:
				continue
			_s.set_terrain(x, y, terrain_t)


# ---------- veins elsewhere ----------

func _scatter_veins() -> void:
	for r in MapState.REGION_COUNT:
		if r == _s.start_region:
			continue
		var rect := MapState.region_rect(r)
		for i in _rng.randi_range(1, 3):
			for attempt in 30:
				var p := Vector2i(_rng.randi_range(rect.position.x, rect.end.x - 1), _rng.randi_range(rect.position.y, rect.end.y - 1))
				if MapState.is_edge_band(p.x, p.y) or _s.get_terrain(p.x, p.y) == _t_water:
					continue
				_s.set_terrain(p.x, p.y, _t_vein)
				break


# ---------- rewards ----------

func _place_rewards() -> void:
	var others: Array[int] = []
	for r in MapState.REGION_COUNT:
		if r != _s.start_region:
			others.append(r)
	_shuffle(others)
	var count := _rng.randi_range(4, 6)
	var types: Array[String] = MapState.REWARD_TYPES.duplicate()
	_shuffle(types)
	if count == 6:
		types.append(MapState.REWARD_TYPES[_rng.randi_range(0, 4)])
	for i in count:
		var r := others[i]
		var type := types[i]
		var pos := _reward_pos(r)
		_s.region_reward[r] = type
		_s.region_reward_pos[r] = pos
		match type:
			MapState.REWARD_RICH_VEIN:
				var placed := 0
				var tries := 0
				while placed < 7 and tries < 200:
					tries += 1
					var p := pos + Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
					if _free_land(p) and _s.get_terrain(p.x, p.y) != _t_vein:
						_s.set_terrain(p.x, p.y, _t_vein)
						placed += 1
			MapState.REWARD_FERTILE_VALLEY:
				_blob(pos, 5.0, _t_fertile)
			MapState.REWARD_OLD_FOREST:
				_blob(pos, 5.0, _t_forest)
			MapState.REWARD_SPRING:
				for dy in 2:
					for dx in 2:
						_s.set_terrain(pos.x + dx, pos.y + dy, _t_water)
			MapState.REWARD_RUINS:
				pass  # marker only; the reward itself is data for a later ticket


func _free_land(p: Vector2i) -> bool:
	return MapState.in_bounds(p.x, p.y) and not MapState.is_edge_band(p.x, p.y) and _s.get_terrain(p.x, p.y) != _t_water


## Marker tile for a region's reward: inside the region and 3+ tiles clear of the edge band,
## and for springs at least 6 tiles from any river tile.
func _reward_pos(r: int) -> Vector2i:
	var rect := MapState.region_rect(r)
	var inner := rect.intersection(Rect2i(BAND + 3, BAND + 3, W - 2 * (BAND + 3), H - 2 * (BAND + 3))).grow(-3)
	var best := inner.get_center()
	for attempt in 40:
		var p := Vector2i(_rng.randi_range(inner.position.x, inner.end.x - 1), _rng.randi_range(inner.position.y, inner.end.y - 1))
		if _river_distance(p) >= 7.0:
			return p
		if attempt == 0:
			best = p
	return best


func _river_distance(p: Vector2i) -> float:
	var d := 1e9
	for q in _s.river_path:
		d = minf(d, p.distance_to(q))
	return d


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


# ---------- fertility ----------

func _init_fertility(registry: DataRegistry) -> void:
	var start: PackedInt32Array = PackedInt32Array()
	for id in _s.terrain_ids:
		start.append(roundi(registry.terrain[id].fertility_start * 100.0))
	for i in W * H:
		_s.fertility[i] = start[_s.terrain[i]]
