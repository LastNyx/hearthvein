extends GutTest

const SEEDS := [1, 2, 3, 42, 1234, 99999, 7777777, 31337]
const SEEDS20 := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 42, 77, 123, 1234, 4242, 31337, 99999, 123456, 7777777, 20261113]

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _tid(s: MapState, id: String) -> int:
	return s.terrain_index(id)


func _tiles_of(s: MapState, id: String, rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t := _tid(s, id)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if s.get_terrain(x, y) == t:
				out.append(Vector2i(x, y))
	return out


func _nearest(tiles: Array[Vector2i], p: Vector2i) -> float:
	var d := 1e9
	for t in tiles:
		d = minf(d, t.distance_to(p))
	return d


# AC1
func test_same_seed_identical_different_seeds_differ() -> void:
	var a := MapGen.generate(5, reg)
	var b := MapGen.generate(5, reg)
	var c := MapGen.generate(6, reg)
	assert_eq(a.terrain, b.terrain)
	assert_eq(a.river_flow, b.river_flow)
	assert_eq(a.fertility, b.fertility)
	assert_eq(a.region_reward, b.region_reward)
	assert_eq(a.start_region, b.start_region)
	assert_eq(a.hearth_spot, b.hearth_spot)
	assert_ne(a.terrain, c.terrain)


# AC2
func test_start_region_guarantees() -> void:
	for seed in SEEDS:
		var s := MapGen.generate(seed, reg)
		assert_true(s.start_region in [5, 6, 9, 10], "seed %d start region central" % seed)
		var rect := MapState.region_rect(s.start_region)
		assert_true(rect.has_point(s.hearth_spot), "seed %d hearth in start region" % seed)
		var ht := _tid(s, "grass")
		var here := s.get_terrain(s.hearth_spot.x, s.hearth_spot.y)
		assert_true(here == ht or here == _tid(s, "fertile_soil"), "seed %d hearth on buildable land" % seed)
		var rivers := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if s.is_river(x, y):
					rivers += 1
		assert_gt(rivers, 0, "seed %d river in start region" % seed)
		var veins := _tiles_of(s, "lumen_vein", rect)
		assert_between(veins.size(), 3, 5, "seed %d vein count" % seed)
		var near := Rect2i(s.hearth_spot - Vector2i(8, 8), Vector2i(17, 17))
		assert_lte(_nearest(_tiles_of(s, "forest", near), s.hearth_spot), 8.0, "seed %d forest near" % seed)
		assert_lte(_nearest(_tiles_of(s, "rock", near), s.hearth_spot), 8.0, "seed %d rock near" % seed)


# AC3
func test_river_crosses_regions_and_flows_downstream() -> void:
	for seed in SEEDS:
		var s := MapGen.generate(seed, reg)
		var regions := {}
		var count := 0
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if not s.is_river(x, y):
					continue
				count += 1
				regions[s.get_region(x, y)] = true
				assert_eq(s.terrain_id_at(x, y), "water")
				var d := s.downstream(x, y)
				if MapState.in_bounds(d.x, d.y):
					assert_true(s.is_river(d.x, d.y), "seed %d river tile %s has downstream" % [seed, Vector2i(x, y)])
				else:
					assert_true(x == 0 or y == 0 or x == MapState.WIDTH - 1 or y == MapState.HEIGHT - 1, "ends at edge")
		assert_gte(regions.size(), 6, "seed %d river regions" % seed)
		assert_gte(count, s.river_path.size() * 2, "seed %d river is wider than its centreline" % seed)
		# Outside the left/right edge columns the river never enters the band.
		for p in s.river_path:
			if p.x >= MapState.EDGE_BAND and p.x < MapState.WIDTH - MapState.EDGE_BAND:
				assert_true(p.y >= MapState.EDGE_BAND and p.y < MapState.HEIGHT - MapState.EDGE_BAND, "river inside band at %s" % p)


# AC4
func test_edge_band_is_plain_land() -> void:
	var grass := "grass"
	var fertile := "fertile_soil"
	for seed in SEEDS:
		var s := MapGen.generate(seed, reg)
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if not MapState.is_edge_band(x, y) or s.is_river(x, y):
					continue
				var id := s.terrain_id_at(x, y)
				if id != grass and id != fertile:
					fail_test("seed %d non-plain %s at %s" % [seed, id, Vector2i(x, y)])
					return
	pass_test("band plain")


# AC5
func test_fertility_initialised() -> void:
	var s := MapGen.generate(11, reg)
	var seen := {}
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var id := s.terrain_id_at(x, y)
			var want := 100 if id == "fertile_soil" else (60 if id == "grass" else 0)
			assert_eq(s.get_fertility(x, y), want, "%s at %s" % [id, Vector2i(x, y)])
			seen[id] = true
	assert_true(seen.has("fertile_soil") and seen.has("grass") and seen.has("forest") and seen.has("rock"))


# Rewards and state fields
func test_rewards_and_state_fields() -> void:
	for seed in SEEDS:
		var s := MapGen.generate(seed, reg)
		var n := 0
		for r in MapState.REGION_COUNT:
			var rw := s.get_region_reward(r)
			if rw != "":
				n += 1
				assert_true(rw in MapState.REWARD_TYPES)
				assert_ne(r, s.start_region)
				assert_true(MapState.region_rect(r).has_point(s.region_reward_pos[r]))
		assert_between(n, 4, 6, "seed %d reward count" % seed)
		assert_true(s.is_region_owned(s.start_region))
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if MapState.is_edge_band(x, y) and s.get_terrain(x, y) == _tid(s, "lumen_vein"):
					fail_test("vein in band")
					return
				assert_false(s.is_blighted(x, y) or s.is_fouled(x, y))
	assert_true(MapState.in_bounds(0, 0) and not MapState.in_bounds(128, 0) and not MapState.in_bounds(0, -1))


func _land_flood(s: MapState, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var q: Array[Vector2i] = [from]
	var head := 0
	while head < q.size():
		var p := q[head]
		head += 1
		for o in MapState.FLOW_VECTORS.slice(1):
			var n: Vector2i = p + o
			if MapState.in_bounds(n.x, n.y) and not seen.has(n) and s.terrain_id_at(n.x, n.y) != "water":
				seen[n] = true
				q.append(n)
	return seen


func _run(s: MapState, x: int, y: int, dx: int, dy: int) -> int:
	var n := 1
	var p := Vector2i(x, y)
	for sign in [1, -1]:
		var c: Vector2i = p + Vector2i(dx, dy) * int(sign)
		while MapState.in_bounds(c.x, c.y) and s.is_river(c.x, c.y):
			n += 1
			c += Vector2i(dx, dy) * int(sign)
	return n


func _no_lakes_registry() -> DataRegistry:
	var r := DataRegistry.new()
	r.load_all()
	r.mapgen = r.mapgen.duplicate()
	r.mapgen.lake_count_min = 0
	r.mapgen.lake_count_max = 0
	r.mapgen.pond_count_min = 0
	r.mapgen.pond_count_max = 0
	return r


# 52 AC1: width 2-4, smooth
func test_river_width_two_to_four_and_smooth() -> void:
	var plain := _no_lakes_registry()
	for seed in SEEDS20:
		var s := MapGen.generate(seed, plain)
		assert_eq(s.river_width.size(), s.river_path.size())
		var widest := 0.0
		var narrowest := 99.0
		for i in s.river_width.size():
			var w: float = s.river_width[i]
			widest = maxf(widest, w)
			narrowest = minf(narrowest, w)
			assert_between(w, 2.0, 4.0, "seed %d width" % seed)
			if i > 0:
				assert_lt(absf(w - s.river_width[i - 1]), 0.25, "seed %d width changes smoothly" % seed)
		assert_gt(widest - narrowest, 0.8, "seed %d width varies" % seed)
		# Cross-section through every centreline tile: the narrower axis run is 2..7 tiles (diagonals read wider).
		for i in range(8, s.river_path.size() - 8):
			var p := s.river_path[i]
			var run := mini(_run(s, p.x, p.y, 1, 0), _run(s, p.x, p.y, 0, 1))
			if run < 2 or run > 7:
				fail_test("seed %d cross-section %d at %s" % [seed, run, p])
				return
	pass_test("widths ok")


# 52 AC1: every river tile flows, chains reach the map edge without loops (also through lakes)
func test_flow_on_every_tile_reaches_the_edge() -> void:
	for seed in SEEDS20:
		var s := MapGen.generate(seed, reg)
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if not s.is_river(x, y):
					continue
				var p := Vector2i(x, y)
				var steps := 0
				while MapState.in_bounds(p.x, p.y):
					assert_true(s.is_river(p.x, p.y), "seed %d flow stays in water at %s" % [seed, p])
					if not s.is_river(p.x, p.y):
						return
					p = s.downstream(p.x, p.y)
					steps += 1
					if steps > 2000:
						fail_test("seed %d flow loop from %s" % [seed, Vector2i(x, y)])
						return
				assert_true(p.x == -1 or p.x == MapState.WIDTH, "seed %d leaves through a side edge" % seed)


# 52 AC2: lakes and ponds
func test_lakes_and_ponds_exist_and_are_deterministic() -> void:
	var m := reg.mapgen
	for seed in SEEDS20:
		var s := MapGen.generate(seed, reg)
		var plain := MapGen.generate(seed, _no_lakes_registry())
		var extra_river := 0
		var ponds := 0
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				var water := s.terrain_id_at(x, y) == "water"
				if s.is_river(x, y) and not plain.is_river(x, y):
					extra_river += 1
				if water and not s.is_river(x, y):
					ponds += 1
					assert_eq(s.get_flow(x, y), MapState.FLOW_NONE)
		assert_gt(extra_river, 20, "seed %d lake tiles on the river" % seed)
		assert_gt(ponds, 4, "seed %d pond tiles (springs excluded by count)" % seed)
	assert_gt(m.lake_count_max, 0)
	var a := MapGen.generate(77, reg)
	var b := MapGen.generate(77, reg)
	assert_eq(a.terrain, b.terrain)
	assert_eq(a.river_flow, b.river_flow)


# 52 AC3: guarantees over 20 seeds, and the Hearth reaches its resources by land
func test_start_region_guarantees_and_land_connection_20_seeds() -> void:
	for seed in SEEDS20:
		var s := MapGen.generate(seed, reg)
		var rect := MapState.region_rect(s.start_region)
		var h := s.hearth_spot
		assert_true(rect.has_point(h), "seed %d hearth placed" % seed)
		assert_between(_tiles_of(s, "lumen_vein", rect).size(), 3, 5, "seed %d vein count" % seed)
		var near := Rect2i(h - Vector2i(8, 8), Vector2i(17, 17))
		assert_lte(_nearest(_tiles_of(s, "forest", near), h), 8.0, "seed %d forest near" % seed)
		assert_lte(_nearest(_tiles_of(s, "rock", near), h), 8.0, "seed %d rock near" % seed)
		var river := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if s.is_river(x, y):
					river += 1
		assert_gt(river, 10, "seed %d river in start region" % seed)
		var land := _land_flood(s, h)
		for kind in ["lumen_vein", "forest", "rock"]:
			var reach := 1e9
			for t in _tiles_of(s, kind, near if kind != "lumen_vein" else rect):
				if land.has(t):
					reach = minf(reach, t.distance_to(h))
			var limit := 10.0 if kind == "lumen_vein" else 8.0
			assert_lte(reach, limit, "seed %d %s reachable by land" % [seed, kind])
		var veins_reached := 0
		for t in _tiles_of(s, "lumen_vein", rect):
			if land.has(t):
				veins_reached += 1
		assert_gte(veins_reached, 3, "seed %d veins reachable" % seed)
		var regions := {}
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if s.is_river(x, y):
					regions[s.get_region(x, y)] = true
		assert_gte(regions.size(), 6, "seed %d river regions" % seed)
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if MapState.is_edge_band(x, y) and not s.is_river(x, y) and s.terrain_id_at(x, y) in ["water", "rock", "forest", "lumen_vein"]:
					fail_test("seed %d band tile %s not plain" % [seed, Vector2i(x, y)])
					return
