extends GutTest
## Ticket 30b: Paved roads (design.md sections 6 and 8). Town-only, 1 wood + 0.2 cut stone per tile, walkers
## at 2.0 tiles/s. Cut stone is charged in whole units through a running debt, so five tiles cost one stone.

const SEED := 42

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	s.hearth.inventory.add("wood", 100.0)
	s.hearth.inventory.add("stone", 100.0)
	s.hearth.inventory.add("cut_stone", 10.0)


## Buildable owned tiles with no road or building yet, left to right, top to bottom.
func _free_tiles(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if out.size() >= n:
				return out
			var t := Vector2i(x, y)
			if s.road_at(t) == Settlement.ROAD_NONE and s.can_place_road(t):
				out.append(t)
	return out


# AC1a: the numbers are the design's table row, not code constants.
func test_paved_row_matches_design() -> void:
	var paved := reg.get_road("paved")
	assert_not_null(paved)
	assert_eq([paved.level, paved.walk_speed], [2, 2.0])
	assert_eq(paved.era, "town")
	assert_eq(paved.cost, {"wood": 1.0, "cut_stone": 0.2})
	var dirt := reg.get_road("dirt")
	assert_eq([dirt.level, dirt.walk_speed, dirt.era, dirt.cost], [1, 1.5, "", {}])


# AC1b: Town on. A Village settlement refuses to pave and spends nothing.
func test_paving_needs_town() -> void:
	s.era_override = "village"
	var t := _free_tiles(1)[0]
	assert_false(s.paved_roads_unlocked())
	assert_eq(s.can_pave_road(t)["reason"], "era_locked")
	var m: float = s.totals().get("wood", 0.0)
	assert_false(s.pave_road(t))
	assert_eq(s.road_at(t), Settlement.ROAD_NONE, "nothing was laid")
	assert_eq(s.totals().get("wood", 0.0), m, "nothing was spent")
	s.era_override = "town"
	assert_true(s.paved_roads_unlocked())
	assert_true(s.can_pave_road(t)["ok"])
	assert_true(s.pave_road(t))
	assert_eq(s.road_at(t), Settlement.ROAD_PAVED)


# AC1c: one wood per tile; five tiles use one whole cut stone (0.2 each, charged as the debt fills).
func test_five_tiles_cost_five_wood_and_one_cut_stone() -> void:
	var tiles := _free_tiles(5)
	assert_eq(tiles.size(), 5, "the map has five free tiles")
	var m0: float = s.totals().get("wood", 0.0)
	var st0: float = s.totals().get("cut_stone", 0.0)
	for t in tiles:
		assert_true(s.pave_road(t), "paved %s" % t)
	assert_almost_eq(m0 - s.totals().get("wood", 0.0), 5.0, 0.0001)
	assert_almost_eq(st0 - s.totals().get("cut_stone", 0.0), 1.0, 0.0001, "five tiles x 0.2 = one stone")
	for t in tiles:
		assert_eq(s.road_at(t), Settlement.ROAD_PAVED)


# AC1d: paving upgrades a dirt road in place and is refused once paved.
func test_paving_upgrades_dirt() -> void:
	var t := _free_tiles(1)[0]
	assert_true(s.place_road(t))  # dirt, free
	assert_eq(s.road_at(t), Settlement.ROAD_DIRT)
	assert_true(s.can_pave_road(t)["ok"])
	var gv := s.grid_version
	assert_true(s.pave_road(t))
	assert_eq(s.road_at(t), Settlement.ROAD_PAVED)
	assert_gt(s.grid_version, gv, "grid_version bumps so path caches drop")
	assert_eq(s.can_pave_road(t)["reason"], "already_paved")
	assert_false(s.pave_road(t))


# AC1e: the command refuses, and spends nothing, when the wood or the owed stone are short.
func test_short_goods_refuse_the_tile() -> void:
	var tiles := _free_tiles(6)
	s.spend_good("cut_stone", 10.0)  # no stone at all
	for i in 4:
		assert_true(s.pave_road(tiles[i]), "the first four tiles cost no whole stone")
	assert_almost_eq(s._pave_stone_debt, 0.8, 0.000001, "four tiles owe 0.8 of a stone")
	assert_eq(s.can_pave_road(tiles[4])["reason"], "cut_stone")
	assert_false(s.pave_road(tiles[4]))
	s.hearth.inventory.add("cut_stone", 2.0)
	assert_true(s.pave_road(tiles[4]), "the fifth tile pays the whole stone")
	s.spend_good("wood", s.totals().get("wood", 0.0))
	assert_eq(s.can_pave_road(tiles[5])["reason"], "wood")
	assert_false(s.pave_road(tiles[5]))


## A free horizontal strip of `len` tiles, away from buildings and existing roads (the same search test_walkers
## uses).
func _strip(len: int) -> Vector2i:
	for y in range(s.map.hearth_spot.y - 12, s.map.hearth_spot.y + 12):
		for x in range(s.map.hearth_spot.x - 24, s.map.hearth_spot.x + 24):
			var ok := true
			for i in range(-1, len + 2):
				var p := Vector2i(x + i, y)
				for dy in [-1, 0, 1]:
					var q := Vector2i(p.x, p.y + dy)
					if not MapState.in_bounds(q.x, q.y) or not reg.get_terrain(s.map.terrain_id_at(q.x, q.y)).buildable \
							or s.building_at(q) != null or s.road_at(q) != 0 \
							or not s.map.is_region_owned(s.map.get_region(q.x, q.y)):
						ok = false
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# AC2: a paved road walks at 2.0 tiles/s, and the A* weights it below dirt.
func test_paved_tiles_are_faster_for_walkers() -> void:
	var o := _strip(10)
	assert_ne(o, Vector2i(-1, -1), "found a free strip")
	var end := o + Vector2i(10, 0)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	s.step_seconds(0.01)  # creates the walkers
	ws.walker_of(0).controlled = true
	for i in range(0, 11):
		assert_true(s.pave_road(o + Vector2i(i, 0)))
	assert_almost_eq(ws.tile_speed(o), 2.0, 0.0001, "paved tiles are 2.0 tiles/s")
	var dirt := Vector2i(o.x, o.y + 1)  # untouched grass: 1.0 tiles/s, so the weights must rank paved below it
	var paved_weight := ws._grid.get_point_weight_scale(o)
	var grass_weight := ws._grid.get_point_weight_scale(dirt)
	assert_lt(paved_weight, grass_weight, "paved costs less to enter than grass")

	ws.place_walker(0, o)
	assert_true(ws.walk_to_tile(0, end))
	var w := ws.walker_of(0)
	var t := 0.0
	while w.is_walking() and t < 30.0:
		s.step_seconds(0.01)
		t += 0.01
	assert_almost_eq(t, 5.0, 0.05, "10 paved tiles at 2.0 tiles/s")


# Ticket 61: forest is not buildable, so a road can never sit on a tree tile; the trees seen over a road are
# neighbouring forest canopy. Clearing the tile (woodcutter) makes it placeable.
func test_roads_refuse_forest_until_cleared() -> void:
	var t := _free_tiles(1)[0]
	s.set_terrain(t, "forest")
	assert_false(s.can_place_road(t))
	assert_false(s.place_road(t))
	assert_false(s.can_pave_road(t)["ok"])
	s.set_terrain(t, "grass")
	assert_true(s.place_road(t))
