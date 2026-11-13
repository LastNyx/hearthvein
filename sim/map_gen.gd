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
var _cfg: MapGenDef
var _flip := false
var _flow_exit_x := 0
var _key := PackedInt32Array()       # river tile -> centreline index of the nearest stamp, -1 = not river
var _dist := PackedFloat32Array()
var _river_tiles: Array[Vector2i] = []
var _reach := PackedByteArray()      # land tiles reachable from the Hearth


static func generate(seed: int, registry: DataRegistry) -> MapState:
	var g := MapGen.new()
	return g._run(seed, registry)


func _run(seed: int, registry: DataRegistry) -> MapState:
	var ids := PackedStringArray()
	var keys := registry.terrain.keys()
	keys.sort()
	for k in keys:
		ids.append(k)
	_cfg = registry.mapgen
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
	_carve_lakes()
	_smooth_banks()
	_assign_flow()
	_land_reach()
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

const FLOW_FROM_STEP := {
	Vector2i(0, -1): MapState.FLOW_N,
	Vector2i(1, 0): MapState.FLOW_E,
	Vector2i(0, 1): MapState.FLOW_S,
	Vector2i(-1, 0): MapState.FLOW_W,
}


## River in four steps. 1) A 4-connected walk through jittered waypoints (the centreline, map.river_path).
## 2) A moving average makes it a smooth curve. 3) Discs of a smoothly varying width (cfg river_width_*) are stamped
## along it. 4) Flow is assigned later by _assign_flow (after lakes are added).
func _carve_river() -> void:
	var sr := _s.start_region
	var srow := sr / MapState.REGION_COLS
	var rect := MapState.region_rect(sr)
	var cy := rect.position.y + rect.size.y / 2
	var cx := rect.position.x + rect.size.x / 2
	_flip = _rng.randi() % 2 == 1  # flow east to west
	# Row 1 start: enter in the top row, leave in the bottom row; row 2 start: the reverse.
	var side := 1 if srow == 1 else -1
	var ya := _rng.randi_range(8, 20) if side == 1 else _rng.randi_range(75, 87)
	var yb := _rng.randi_range(75, 87) if side == 1 else _rng.randi_range(8, 20)
	var hu := (W - 1 - cx) if _flip else cx  # progress coordinate of the start region centre
	var ys := cy + _cfg.river_start_offset * side

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

	# Map progress coordinates to real x.
	for i in path.size():
		var p := path[i]
		path[i] = Vector2i(W - 1 - p.x if _flip else p.x, p.y)

	# Smooth centreline (ends pinned: the window shrinks towards them).
	var n := path.size()
	var curve := PackedVector2Array()
	curve.resize(n)
	for i in n:
		var k := mini(_cfg.river_smooth_window, mini(i, n - 1 - i))
		var sum := Vector2.ZERO
		for j in range(i - k, i + k + 1):
			sum += Vector2(path[j])
		curve[i] = sum / float(2 * k + 1)

	# Width: smooth noise along the river, mapped into [min, max]; the epsilon keeps the cross-section in 2..4 tiles.
	var wn := FastNoiseLite.new()
	wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wn.seed = (_s.seed_used + 4) & 0x7FFFFFFF
	wn.frequency = _cfg.river_width_freq
	var lo := _cfg.river_width_min + 0.02
	var hi := _cfg.river_width_max - 0.02
	_key.resize(W * H)
	_key.fill(-1)
	_dist.resize(W * H)
	_dist.fill(1e9)
	_s.river_width.clear()
	_s.river_path.clear()
	for i in n:
		var k := mini(6, mini(i, n - 1 - i))
		var sum := 0.0
		for j in range(i - k, i + k + 1):
			sum += wn.get_noise_1d(j)
		var t := clampf(0.5 + 0.5 * sum / float(2 * k + 1) * 2.6, 0.0, 1.0)
		var w := lerpf(lo, hi, t)
		var tile := Vector2i(curve[i].round())
		if _s.river_path.is_empty() or _s.river_path[_s.river_path.size() - 1] != tile:
			_s.river_path.append(tile)  # centreline: the smoothed curve rounded to tiles, always river water
			_s.river_width.append(w)
		else:
			_s.river_width[_s.river_width.size() - 1] = w
		_stamp_disc(curve[i], w * 0.5, _s.river_path.size() - 1, 0.0, 0.0)
	_flow_exit_x = 0 if _flip else W - 1


## Marks water tiles within `radius` of `c` as river water owned by centreline index `idx`. With wobble > 0 the
## radius varies with the angle (lobed lakes and ponds), using phases `ph`.
func _stamp_disc(c: Vector2, radius: float, idx: int, wobble: float, ph: float, mark_river: bool = true) -> void:
	var r := ceili(radius * (1.0 + wobble) + 1.0)
	for y in range(int(c.y) - r, int(c.y) + r + 1):
		for x in range(int(c.x) - r, int(c.x) + r + 1):
			if not MapState.in_bounds(x, y) or y < BAND or y >= H - BAND:
				continue
			if wobble > 0.0 and MapState.is_edge_band(x, y):
				continue
			var off := Vector2(x, y) - c
			var rr := radius
			if wobble > 0.0:
				var a := off.angle()
				rr = radius * (1.0 + wobble * (0.6 * sin(2.0 * a + ph) + 0.4 * sin(3.0 * a + ph * 1.7)))
			var d := off.length()
			if d >= rr:
				continue
			var i := y * W + x
			_s.terrain[i] = _t_water
			if mark_river:
				if _key[i] == -1:
					_river_tiles.append(Vector2i(x, y))
				if d < _dist[i] or _key[i] == -1:
					_dist[i] = d
					_key[i] = idx


## Bank clean-up: fills one-tile notches (land with 3+ water sides) and drops one-tile spits (water with at most one
## water side), so bends read as round banks instead of stair steps. Ponds are not touched.
func _smooth_banks() -> void:
	for pass_i in 2:
		var changes: Array[Vector3i] = []  # x, y, 1 = fill / 0 = drop
		for y in range(BAND, H - BAND):
			for x in range(1, W - 1):
				var i := y * W + x
				var n := 0
				var nk := -1
				for o in MapState.FLOW_VECTORS.slice(1):
					var k := _key[(y + o.y) * W + x + o.x]
					if k != -1:
						n += 1
						nk = k
				if _key[i] == -1:
					if n >= 3 and _s.terrain[i] != _t_water:
						changes.append(Vector3i(x, y, 1))
				elif n <= 1:
					changes.append(Vector3i(x, y, 0))
		for c in changes:
			var i := c.y * W + c.x
			if c.z == 1:
				var best := -1
				for o in MapState.FLOW_VECTORS.slice(1):
					best = maxi(best, _key[(c.y + o.y) * W + c.x + o.x])
				_key[i] = best
				_s.terrain[i] = _t_water
			elif c.x > 0 and c.x < W - 1:
				_key[i] = -1
				_s.terrain[i] = _t_grass
	_river_tiles.clear()
	for i in W * H:
		if _key[i] != -1:
			_river_tiles.append(Vector2i(i % W, i / W))


## Flow for every river tile (rivers and the lakes on them): breadth-first search from the exit edge column over
## river water, each tile flows to the neighbour one step nearer the exit (so lakes drain along the shortest way to
## the outlet), and among equally near neighbours to the one furthest downstream along the centreline. The exit
## tiles flow off the map. Every tile therefore has a river downstream neighbour or leaves at the map edge.
func _assign_flow() -> void:
	var dist := {}
	var queue: Array[Vector2i] = []
	for p in _river_tiles:
		if p.x == _flow_exit_x:
			dist[p] = 0
			queue.append(p)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for o in MapState.FLOW_VECTORS.slice(1):
			var q: Vector2i = p + o
			if MapState.in_bounds(q.x, q.y) and _key[q.y * W + q.x] != -1 and not dist.has(q):
				dist[q] = dist[p] + 1
				queue.append(q)
	for p in _river_tiles:
		var d: int = dist.get(p, -1)
		var dir := MapState.FLOW_W if _flip else MapState.FLOW_E
		if d > 0:
			var best_key := -2
			for f in range(1, 5):
				var q: Vector2i = p + MapState.FLOW_VECTORS[f]
				if dist.get(q, -1) == d - 1 and _key[q.y * W + q.x] > best_key:
					best_key = _key[q.y * W + q.x]
					dir = f
		_s.set_flow(p.x, p.y, dir)


## Appends jittered waypoints between the last point and `to`, roughly every river_meander_spacing tiles of progress.
func _add_meander(pts: Array[Vector2i], to: Vector2i) -> void:
	var from := pts[pts.size() - 1]
	var j := _cfg.river_meander_jitter
	var n := maxi(1, (to.x - from.x) / _cfg.river_meander_spacing)
	for i in range(1, n):
		var u := from.x + (to.x - from.x) * i / n
		var y := from.y + (to.y - from.y) * i / n + _rng.randi_range(-j, j)
		pts.append(Vector2i(u, clampi(y, 8, H - 9)))


# ---------- lakes and ponds ----------

## Lakes sit on the river (so they carry its flow), ponds stand alone on land with no flow.
func _carve_lakes() -> void:
	var lakes: Array[Vector3] = []  # x, y, radius
	var count := _rng.randi_range(_cfg.lake_count_min, _cfg.lake_count_max)
	var path := _s.river_path
	for l in count:
		for attempt in 60:
			var i := _rng.randi_range(0, path.size() - 1)
			var r := _rng.randf_range(_cfg.lake_radius_min, _cfg.lake_radius_max)
			var c := Vector2(path[i]) + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
			if not _water_site_ok(c, r, lakes, 2.0):
				continue
			lakes.append(Vector3(c.x, c.y, r))
			_stamp_disc(c, r, i, _cfg.shore_wobble, _rng.randf() * TAU)
			break
	var ponds: Array[Vector3] = []
	count = _rng.randi_range(_cfg.pond_count_min, _cfg.pond_count_max)
	for l in count:
		for attempt in 120:
			var r := _rng.randf_range(_cfg.pond_radius_min, _cfg.pond_radius_max)
			var c := Vector2(_rng.randi_range(BAND, W - 1 - BAND), _rng.randi_range(BAND, H - 1 - BAND))
			var reach := r * (1.0 + _cfg.shore_wobble) + _cfg.pond_river_gap
			if _river_distance(Vector2i(c)) < reach + 1.0 or not _water_site_ok(c, r, ponds, _cfg.pond_river_gap):
				continue
			ponds.append(Vector3(c.x, c.y, r))
			_stamp_disc(c, r, -1, _cfg.shore_wobble, _rng.randf() * TAU, false)
			break


func _water_site_ok(c: Vector2, r: float, others: Array[Vector3], gap: float) -> bool:
	var m := r * (1.0 + _cfg.shore_wobble) + 2.0
	if c.x < BAND + m or c.y < BAND + m or c.x > W - 1 - BAND - m or c.y > H - 1 - BAND - m:
		return false
	if c.distance_to(Vector2(_s.hearth_spot)) < _cfg.water_hearth_clear + r:
		return false
	for o in others:
		if c.distance_to(Vector2(o.x, o.y)) < r + o.z + gap + 2.0:
			return false
	return true


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
			if clash or not _blob_ok(c, 2) or _reach[c.y * W + c.x] == 0:
				continue
			_blob(c, 2.2, kind)
			used.append(c)
			placed = true
			break
		if not placed:
			# Fallback: always place a small blob due west/east/north/south of the Hearth.
			for off in [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6)]:
				var c: Vector2i = h + off
				if rect.grow(-2).has_point(c) and _blob_ok(c, 1) and _reach[c.y * W + c.x] == 1:
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
		if _s.get_terrain(p.x, p.y) == _t_water or MapState.is_edge_band(p.x, p.y) or _reach[p.y * W + p.x] == 0:
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


## Distance to the nearest river or lake tile (ponds have no flow and are not counted).
func _river_distance(p: Vector2i) -> float:
	var d := 1e18
	for q in _river_tiles:
		d = minf(d, float((p - q).length_squared()))
	return sqrt(d)


## Flood fill over non-water tiles from the Hearth: the land a walker can reach.
func _land_reach() -> void:
	_reach.resize(W * H)
	_reach.fill(0)
	var h := _s.hearth_spot
	var queue: Array[Vector2i] = [h]
	_reach[h.y * W + h.x] = 1
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for o in MapState.FLOW_VECTORS.slice(1):
			var q: Vector2i = p + o
			if MapState.in_bounds(q.x, q.y) and _reach[q.y * W + q.x] == 0 and _s.get_terrain(q.x, q.y) != _t_water:
				_reach[q.y * W + q.x] = 1
				queue.append(q)


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
