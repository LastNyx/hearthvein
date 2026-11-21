extends GutTest
## Ticket 144: the Moonmoth Loft and silk (was test_night_life.gd on its branch; renamed at merge beside the Bakery tests).
##
## The loft works at night only, inside a lamp's light with at least three lit tiles within two (the moths come to
## the light), and makes one silk a night. Silk is a luxury good the Market sells for gold above a keep level.

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


## A fresh settlement with the growth system off and a road strip east of the Hearth with clear land north of it.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 20):
		for y in range(hs.y - 3, hs.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places a building on the north side of the road strip, `dx` tiles east of the Hearth, and returns it.
func _put(s: Settlement, id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var hs := s.map.hearth_spot
	var bid := s.place_building_instant(id, Vector2i(hs.x + dx, hs.y - def.size.y))
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings.get(bid)


## A fuelled Brazier south of the road, `dx` tiles east of the Hearth.
func _lamp(s: Settlement, dx: int) -> void:
	var hs := s.map.hearth_spot
	var bid := s.place_building_instant("lamp", Vector2i(hs.x + dx, hs.y + 1))
	assert_true(bid >= 0, "lamp placed")
	var lamp: Building = s.buildings.get(bid)
	lamp.input_buffer.add("wood", 3.0)


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Criterion 1: silk at night with lit tiles near, nothing in the dark and nothing by day.
func test_loft_makes_silk_only_at_night_with_lit_tiles_near() -> void:
	var s := _new_settlement()
	var loft := _put(s, "moonmoth_loft", 4)
	assert_true(loft.def.night_only, "the loft works at night only")
	assert_eq([loft.def.size, loft.def.category, loft.def.night_worker_slots], [Vector2i(1, 1), "refining", 2])
	_lamp(s, 3)
	_keep_citizens(s, 4)  # two Hearth day haulers, then the loft's two night slots
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	s.step_hours(19)
	assert_true(s.is_lit(loft), "the Brazier's light reaches the loft")
	var ls := s.get_system(LightingSystem) as LightingSystem
	assert_gte(ls.lit_tiles_near(s, loft, 2), 3, "at least three lit tiles within two")
	s.step_hours(2)  # 19:00 -> 21:00, the night workers walk to the door
	assert_true(s.is_night(), "21:00 is the night shift")
	var made := ps.produced_total
	s.step_hours(6)  # 21:00 -> 03:00, inside the night shift
	# 2 workers for 6 h of a 12 h work day at the night rate (0.667 silk per worker per day): 2 * 6/12 * 0.667.
	assert_almost_eq(ps.produced_total - made, 0.667, 0.02, "the loft made silk in the light")
	s.step_hours(6)  # 03:00 -> 09:00: the 20:00-06:00 night shift ends, 9 h on site (the first hour is the walk)
	assert_almost_eq(ps.produced_total - made, 1.0, 0.02, "a full staffed night in light makes 1.0 silk")
	var at_dawn := ps.produced_total
	s.step_hours(10)  # 09:00 -> 19:00, the day
	assert_almost_eq(ps.produced_total, at_dawn, 0.001, "nothing by day")
	# The same loft with no lamp in reach stays dark and closed all night.
	var dark := _new_settlement()
	var dark_loft := _put(dark, "moonmoth_loft", 4)
	_keep_citizens(dark, 4)
	dark.step_hours(21)
	assert_false(dark.is_lit(dark_loft), "no lamp, no light")
	assert_eq(dark_loft.halt, "unlit", "the loft stays closed in the dark")
	assert_eq((dark.get_system(ProductionSystem) as ProductionSystem).produced_total, 0.0, "no silk in the dark")


## Criterion 2: the Market sells silk above its keep level for gold.
func test_silk_sells_for_gold_at_the_market() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var id := s.place_building_instant("market", Vector2i(hs.x + 4, hs.y - 2))
	assert_true(id >= 0, "market placed beside the road")
	assert_true(s.buildings[id].connected, "the market is road-connected")
	s.hearth.inventory.add("silk", 20.0)
	assert_eq(s.gold, 0.0)
	s.step_days(1)
	# Two Market workers bring 3 gold; the 10 silk above the keep level of 10 sell at 8 gold each.
	assert_almost_eq(s.gold, 3.0 + 10.0 * 8.0, 0.001, "the surplus silk sold for gold")
	assert_almost_eq(float(s.totals().get("silk", 0.0)), 10.0, 0.001, "the keep level stays in store")
