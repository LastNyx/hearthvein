extends GutTest
## Ticket 39c: Hydroponic Hall (design.md sections 9, 12, 14 and 17 Conflux). 3x2, +4 food (the "greenhouse" food
## type), no soil, needs water (a wet tile under the footprint, or a Well / Water Tower in reach), Dimming- and
## blight-proof.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "conflux"
	s.planet_health_override = 100.0
	h = s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## A hall on the road row, its tiles made plain grass with no fertility at all.
func _hall() -> Building:
	var o := Vector2i(h.x + 4, h.y - 2)
	for t in [o, o + Vector2i(1, 0), o + Vector2i(2, 0), o + Vector2i(0, 1), o + Vector2i(1, 1), o + Vector2i(2, 1)]:
		s.set_terrain(t, "grass")
		s.map.set_fertility(t.x, t.y, 0)
	var bid := s.place_building_instant("hydroponic_hall", o)
	assert_true(bid >= 0, "hall placed")
	s.hearth.inventory.add("lumen", 200.0)
	return s.buildings[bid]


func _wet(b: Building) -> void:
	s.set_terrain(b.origin + Vector2i(-1, 0), "water")
	WaterSystem.recompute(s)


func _dry(b: Building) -> void:
	# Make sure no water is near: turn any water tile within 6 tiles to grass.
	for y in range(b.origin.y - 6, b.origin.y + 8):
		for x in range(b.origin.x - 6, b.origin.x + 9):
			if MapState.in_bounds(x, y) and s.map.terrain_id_at(x, y) == "water":
				s.set_terrain(Vector2i(x, y), "grass")
	WaterSystem.recompute(s)


func _day() -> void:
	s.hearth.inventory.add("food", 30.0)
	s.hearth.inventory.add("lumen", 10.0)
	s.step_hours(DAY)


func _made(days: int) -> float:
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	var before := ps.produced_total
	for i in days:
		_day()
	return ps.produced_total - before


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func test_row_matches_the_conflux_table() -> void:
	var d := reg.get_building("hydroponic_hall")
	assert_eq(d.era, "conflux")
	assert_eq(d.size, Vector2i(3, 2))
	assert_eq(d.cost, {"materials": 150, "gold": 50, "planks": 30, "tools": 20})
	assert_eq(d.worker_slots, 4)
	assert_eq(d.upkeep_lumen, 3.0)
	assert_eq(d.recipe.outputs, {"greenhouse": 4.0})
	assert_true(d.work_needs_water)
	assert_false(d.fertility_output, "no soil")
	assert_eq(d.blight_reach, 0, "blight does not touch it")
	assert_eq(d.dimming_factor, 1.0, "the Dimming does not touch it")


# AC1: it runs on ground with no fertility as long as water is there.
func test_runs_on_infertile_ground_with_water() -> void:
	var b := _hall()
	_wet(b)
	assert_true(WaterSystem.has_water(s, b))
	assert_eq(s.map.get_fertility(b.origin.x, b.origin.y), 0, "no fertility under it")
	_day()
	_day()
	assert_gt(_made(3), 0.0, "it produces")
	assert_eq(b.halt, "", "and is not halted")


# AC1: without water it halts with "dry" and makes nothing.
func test_halts_without_water() -> void:
	var b := _hall()
	_dry(b)
	assert_false(WaterSystem.has_water(s, b))
	assert_almost_eq(_made(3), 0.0, 0.0001, "no water, no food")
	assert_eq(b.halt, "dry")
	_wet(b)
	_day()
	assert_ne(b.halt, "dry", "water lets it run again")


# A Water Tower in reach is water too, with no wet tile under the hall.
func test_drinking_water_source_in_reach_counts() -> void:
	var b := _hall()
	_dry(b)
	assert_false(WaterSystem.has_water(s, b))
	var tower := Building.new()
	tower.id = 9100
	tower.def = reg.get_building("water_tower")
	tower.origin = b.origin + Vector2i(8, 0)
	s.buildings[tower.id] = tower
	s.structure_version += 1
	assert_true(WaterSystem.has_water(s, b), "tower within 16 tiles")
	assert_eq(WaterSystem.dry_halt(s, b), "")


# AC2: a Dimming does not touch its output.
func test_same_output_in_a_dimming() -> void:
	var b := _hall()
	_wet(b)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	_to_day(WINTER - 1)
	assert_false(DimmingSystem.is_active(s))
	var outside := prod.multiplier(s, b)
	_to_day(WINTER)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, b), 1.0)
	assert_almost_eq(prod.multiplier(s, b), outside, 0.00001, "same multiplier inside the Dimming")
	var farm := Building.new()
	farm.def = reg.get_building("farm")
	assert_lt(DimmingSystem.output_modifier(s, farm), 1.0, "a plain farm is cut")


# AC2: blight around it neither halts nor reduces it.
func test_same_output_with_blight_around() -> void:
	var b := _hall()
	_wet(b)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var clean := prod.multiplier(s, b)
	for t in b.tiles():
		s.set_blighted(t, true)
	s.set_blighted(b.origin + Vector2i(-1, 0), true)
	assert_true(BlightSystem.near_blight(s, b))
	assert_false(BlightSystem.blight_hits(s, b))
	assert_almost_eq(prod.multiplier(s, b), clean, 0.00001, "blight does not cut it")
	_day()
	assert_ne(b.halt, "dry")
	assert_ne(b.halt, "blight")
	assert_gt(_made(3), 0.0, "still produces")
