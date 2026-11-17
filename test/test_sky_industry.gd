extends GutTest
## Ticket 41b: Sky Garden and Skyforge (design.md section 17 Skyborne). Settlement API plus step_hours.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var anchor: Building
var isl: Island
var lift: Building


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "skyborne"
	h = s.map.hearth_spot
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 5, h.y + 6):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if x >= h.x + 2:
			s.place_road(Vector2i(x, h.y))
	s.place_building_instant("lumen_pylon", Vector2i(h.x + 3, h.y - 1))
	var aid := s.place_building_instant("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	assert_true(aid >= 0, "anchor placed")
	anchor = s.buildings[aid]
	isl = _isl().island_of_anchor(aid)
	assert_not_null(isl)
	s.hearth.inventory.add("lumen", 400.0)
	s.step_seconds(0.01)
	while s.citizens.size() < 24:
		s.add_citizen()
	JobSystem.refresh(s)


func _isl() -> IslandSystem:
	return s.get_system(IslandSystem) as IslandSystem


func _lift() -> Building:
	for x in range(h.x + 2, h.x + 5):
		var t := Vector2i(x, h.y + 1)
		if isl.rect.has_point(t) and isl.rect.has_point(t + Vector2i(5, 4)) and s.can_place("sky_lift", t, true)["ok"]:
			var id := s.place_building_instant("sky_lift", t)
			assert_true(id >= 0, "lift placed")
			return s.buildings[id]
	fail_test("no lift spot")
	return null


## A lift, a sky road beside it and `def_id` two tiles east of the lift on the island.
func _sky_next_to_lift(def_id: String) -> Building:
	lift = _lift()
	s.place_road(lift.origin + Vector2i(1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	var id := s.place_building_instant(def_id, lift.origin + Vector2i(2, 0), Building.LAYER_SKY)
	assert_true(id >= 0, "%s placed" % def_id)
	return s.buildings[id]


func _cistern_near(b: Building) -> Building:
	var id := s.place_building_instant("cloud_cistern", b.origin + Vector2i(0, 3), Building.LAYER_SKY)
	assert_true(id >= 0, "cistern placed %s" % [s.can_place("cloud_cistern", b.origin + Vector2i(0, 3), true, Building.LAYER_SKY)])
	return s.buildings[id]


func _staffed(b: Building) -> int:
	var n := 0
	for c: Citizen in s.citizens.values():
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func test_data_rows() -> void:
	var g := reg.get_building("sky_garden")
	assert_eq([g.era, g.size, g.layers, g.category], ["skyborne", Vector2i(3, 2), "island", "food"])
	assert_eq(g.cost, {"materials": 120, "gold": 40, "planks": 30, "tools": 10})
	assert_eq([g.worker_slots, g.upkeep_lumen, g.dimming_factor], [3, 1.0, 1.0])
	assert_true(g.work_needs_wet)
	assert_eq(g.recipe.outputs, {"sky_produce": 3.5})
	var p := reg.get_good("sky_produce")
	assert_eq([p.food_type, p.display_name], ["sky", "Sky produce"])
	assert_true(GrowthSystem.food_goods(reg).has("sky_produce"))
	assert_true(reg.get_building("kitchen").recipe.any_input_goods.has("sky_produce"))
	var f := reg.get_building("skyforge")
	assert_eq([f.era, f.size, f.layers, f.category], ["skyborne", Vector2i(2, 2), "island", "refining"])
	assert_eq(f.cost, {"materials": 140, "gold": 60, "cut_stone": 40})
	assert_eq([f.worker_slots, f.upkeep_lumen], [3, 2.0])
	assert_eq(f.recipe.inputs, {"planks": 3.0, "lumen_cells": 3.0})
	assert_eq(f.recipe.outputs, {"tools": 3.0})


# AC1: both are island-only.
func test_both_island_only() -> void:
	var g := Vector2i(h.x + 8, h.y + 3)
	for id in ["sky_garden", "skyforge"]:
		assert_eq(s.can_place(id, g, true)["reason"], "wrong_layer", id)
		assert_eq(s.place_building_instant(id, g), -1, id)
		assert_true(s.can_place(id, isl.rect.position + Vector2i(1, 1), true, Building.LAYER_SKY)["ok"], id)


# AC2: dry without a cistern, produces once a cistern wets the footprint, and eating it adds the sky food type.
func test_sky_garden_needs_wet_and_adds_food_type() -> void:
	var gd := _sky_next_to_lift("sky_garden")
	s.step_days(1)
	assert_eq(_staffed(gd), 3)
	assert_eq(gd.halt, "dry")
	assert_eq(gd.door_buffer.amount_of("sky_produce"), 0.0)
	var types0 := MarketSystem.stored_food_types(s).size()
	assert_false(MarketSystem.stored_food_types(s).has("sky"))
	_cistern_near(gd)
	WaterSystem.recompute(s)
	s.step_days(4)
	var made := s.hearth.inventory.amount_of("sky_produce") + gd.door_buffer.amount_of("sky_produce")
	assert_gt(made, 0.0, "produced once wet")
	assert_ne(gd.halt, "dry")
	assert_true(MarketSystem.stored_food_types(s).has("sky"), "sky food type")
	assert_eq(MarketSystem.stored_food_types(s).size(), types0 + 1)


func test_sky_produce_is_eaten_and_counts_as_food() -> void:
	s = Settlement.new_game(SEED, reg)  # with the growth system, which does the eating
	s.hearth.inventory.add("sky_produce", 20.0)
	assert_true(GrowthSystem.food_goods(reg).has("sky_produce"))
	assert_eq(GrowthSystem.food_type_of(reg, "sky_produce"), "sky")
	s.hearth.inventory.remove("food", s.hearth.inventory.amount_of("food"))
	var before := s.hearth.inventory.amount_of("sky_produce")
	s.step_days(2)
	assert_lt(s.hearth.inventory.amount_of("sky_produce"), before, "citizens ate it")


# AC3: 1 plank + 1 cell -> 1 tool at 3 per worker per day (9 a day with three workers).
func test_skyforge_rate() -> void:
	var f := _sky_next_to_lift("skyforge")
	s.hearth.inventory.add("planks", 200.0)
	s.hearth.inventory.add("lumen_cells", 200.0)
	s.step_days(1)
	assert_eq(_staffed(f), 3)
	var p0 := s.hearth.inventory.amount_of("planks") + f.input_buffer.amount_of("planks")
	var c0 := s.hearth.inventory.amount_of("lumen_cells") + f.input_buffer.amount_of("lumen_cells")
	var t0 := s.hearth.inventory.amount_of("tools") + f.door_buffer.amount_of("tools")
	var added := 0.0
	var added_c := 0.0
	for hour in 4 * 24:  # keep the buffer stocked so the hauling trip does not limit the rate
		added += f.input_buffer.add("planks", 1.0)
		added_c += f.input_buffer.add("lumen_cells", 1.0)
		s.step_hours(1)
	var tools := s.hearth.inventory.amount_of("tools") + f.door_buffer.amount_of("tools") - t0
	assert_between(tools / 4.0, 6.5, 9.3, "three workers x 3 tools a day")
	var p1 := s.hearth.inventory.amount_of("planks") + f.input_buffer.amount_of("planks")
	var c1 := s.hearth.inventory.amount_of("lumen_cells") + f.input_buffer.amount_of("lumen_cells")
	assert_between((p0 + added - p1) / tools, 0.95, 1.05, "1 plank per tool")
	assert_between((c0 + added_c - c1) / tools, 0.95, 1.05, "1 cell per tool")


func test_still_island_halts_both() -> void:
	var gd := _sky_next_to_lift("sky_garden")
	var f_id := -1
	for y in range(isl.rect.position.y, isl.rect.end.y - 1):
		for x in range(isl.rect.position.x, isl.rect.end.x - 1):
			if f_id < 0 and s.can_place("skyforge", Vector2i(x, y), true, Building.LAYER_SKY)["ok"]:
				f_id = s.place_building_instant("skyforge", Vector2i(x, y), Building.LAYER_SKY)
	assert_true(f_id >= 0, "forge placed")
	var f: Building = s.buildings[f_id]
	_cistern_near(gd)
	WaterSystem.recompute(s)
	isl.still_why = "short_lumen"
	s.structure_version += 1
	s.hearth.inventory.add("lumen", 0.0)
	var halted := {}
	for i in 6:
		s.step_hours(1)
		isl.still_why = "short_lumen"
		halted[gd.halt] = true
		halted[f.halt] = true
	assert_eq(gd.halt, "island_still")
	assert_eq(f.halt, "island_still")


func test_sky_home_needs_connected_ground_home_does_not() -> void:
	var sid := s.place_building_instant("skyspire", isl.rect.position + Vector2i(6, 6), Building.LAYER_SKY)
	assert_true(sid >= 0)
	var sp: Building = s.buildings[sid]
	assert_false(sp.connected, "no lift: no route")
	s.add_citizen()
	while s.citizens.size() < s.hearth.def.housing_beds + 10:
		s.add_citizen()
	s.step_hours(2)
	JobSystem.refresh(s)
	for c: Citizen in s.citizens.values():
		assert_ne(c.home_id, sp.id, "nobody lives on an unconnected island")
	# A ground Skyspire (also unconnected, no road) still takes residents.
	var gid := s.place_building_instant("skyspire", Vector2i(h.x - 6, h.y + 4))
	assert_true(gid >= 0)
	s.step_hours(2)
	JobSystem.refresh(s)
	var living := 0
	for c: Citizen in s.citizens.values():
		if c.home_id == gid:
			living += 1
	assert_gt(living, 0, "ground homes keep today's behaviour")
	# A lift and a road to the island home connect it, and then it takes residents.
	lift = _lift()
	s.place_road(lift.origin + Vector2i(1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	var sid2 := s.place_building_instant("skyspire", lift.origin + Vector2i(2, 0), Building.LAYER_SKY)
	assert_true(sid2 >= 0)
	assert_true(s.buildings[sid2].connected)
	s.demolish(gid)
	s.step_hours(2)
	JobSystem.refresh(s)
	var up := 0
	for c: Citizen in s.citizens.values():
		if c.home_id == sid2:
			up += 1
	assert_gt(up, 0, "a connected sky home takes residents")
