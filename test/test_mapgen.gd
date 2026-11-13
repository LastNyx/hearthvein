extends GutTest

const SEEDS := [1, 2, 3, 42, 1234, 99999, 7777777, 31337]

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
		assert_eq(count, s.river_path.size())
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
