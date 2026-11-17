extends GutTest

var reg: DataRegistry


func before_each() -> void:
	reg = DataRegistry.new()


func _load_real() -> void:
	var errs := reg.load_all()
	assert_eq(errs, [] as Array[String], "real data loads without errors")


func _has_error(fragment: String) -> bool:
	for e in reg.errors:
		if e.contains(fragment):
			return true
	return false


# AC1: registry loads all data and fails loudly on a missing reference.
func test_real_data_loads_clean() -> void:
	_load_real()
	assert_eq(reg.goods.size(), 14)
	assert_eq(reg.terrain.size(), 8)
	assert_eq(reg.eras.size(), 7)
	assert_eq(reg.buildings.size(), 62)


func test_broken_fixture_reports_errors() -> void:
	var errs := reg.load_all("res://test/fixtures/data_broken")
	assert_gt(errs.size(), 0)
	assert_true(_has_error("duplicate good id 'wood'"))
	assert_true(_has_error("unknown good 'unobtainium'"))
	assert_true(_has_error("unknown placement rule 'on_moon'"))
	assert_true(_has_error("unknown era 'atlantis'"))
	assert_true(_has_error("gate landmark 'no_such_hall' does not exist"))
	assert_push_error_count(errs.size())


func test_missing_root_is_an_error() -> void:
	var errs := reg.load_all("res://does_not_exist")
	assert_eq(errs.size(), 1)
	assert_push_error_count(1)


# Gate landmark rule: pending only while the landmark's own era has no buildings.
func test_pending_gate_landmarks_allowed() -> void:
	_load_real()
	# Skyborne has buildings since ticket 40 (Lift Anchor), so its landmark row exists (its effect is ticket 42).
	assert_not_null(reg.get_building("dawn_beacon"), "Skyborne landmark authored")
	assert_false(reg.buildings_of_era("skyborne").is_empty())
	assert_eq(reg.get_era("ascendant").gate_landmark, "dawn_beacon")
	assert_eq(reg.errors.size(), 0)


func test_gate_landmark_required_once_its_era_has_buildings() -> void:
	_load_real()
	reg.buildings.erase("meeting_hall")
	reg.errors.clear()
	reg._validate()
	assert_true(_has_error("gate landmark 'meeting_hall' does not exist"))


# AC2: Camp buildings match design.md section 16.
func test_camp_buildings_match_design() -> void:
	_load_real()
	assert_eq(reg.buildings_of_era("camp").size(), 7)
	var hearth := reg.get_building("hearth")
	assert_eq(hearth.size, Vector2i(2, 2))
	assert_eq([hearth.hauler_slots, hearth.builder_slots, hearth.housing_beds], [2, 4, 8])
	assert_eq([hearth.storage_mode, hearth.storage_cap], ["per_good", 150])
	var tent := reg.get_building("tent")
	assert_eq(tent.cost, {"materials": 5})
	assert_eq(tent.housing_beds, 2)
	assert_true(tent.upgradable)
	assert_eq([tent.tiers[0].display_name, tent.tiers[1].display_name], ["Hut", "Lodge"])
	assert_eq(tent.housing_beds * tent.tiers[0].multiplier, 3.0)
	assert_eq(tent.housing_beds * tent.tiers[1].multiplier, 4.0)
	var forager := reg.get_building("forager")
	assert_eq([forager.cost, forager.worker_slots], [{"materials": 10}, 2])
	assert_eq(forager.recipe.outputs, {"food": 1.5})
	var wc := reg.get_building("woodcutter")
	assert_eq([wc.cost, wc.worker_slots], [{"materials": 10}, 2])
	assert_eq(wc.recipe.outputs, {"materials": 1})
	var sh := reg.get_building("storehouse")
	assert_eq(sh.size, Vector2i(2, 1))
	assert_eq(sh.cost, {"materials": 25})
	assert_eq([sh.hauler_slots, sh.storage_mode, sh.storage_cap], [2, "total", 400])
	var tap := reg.get_building("lumen_tap")
	assert_eq([tap.cost, tap.worker_slots, tap.placement_rule], [{"materials": 20}, 2, "on_vein"])
	assert_eq(tap.recipe.outputs, {"lumen": 4.5})
	var mh := reg.get_building("meeting_hall")
	assert_eq(mh.size, Vector2i(2, 2))
	assert_eq(mh.cost, {"materials": 60, "lumen": 10})
	assert_eq(mh.category, "landmark")
	assert_false(mh.upgradable)


func test_default_tier_costs_follow_design() -> void:
	_load_real()
	var tap := reg.get_building("lumen_tap")  # base 20 materials
	assert_eq(tap.tiers[0].cost, {"planks": 10, "cut_stone": 5})
	assert_eq(tap.tiers[0].extra_worker_slots, 1)
	assert_eq(tap.tiers[1].cost, {"tools": 4, "lumen_cells": 2, "cut_stone": 5})
	assert_eq(tap.tiers[1].extra_worker_slots, 2)


# AC3: seven eras with gates and Dimming base 2..8.
func test_seven_eras() -> void:
	_load_real()
	var eras := reg.eras_in_order()
	assert_eq(eras.size(), 7)
	var ids: Array = eras.map(func(e: EraDef) -> String: return e.id)
	assert_eq(ids, ["camp", "village", "town", "city", "conflux", "skyborne", "ascendant"])
	var days: Array = eras.map(func(e: EraDef) -> int: return e.dimming_base_days)
	assert_eq(days, [2, 3, 4, 5, 6, 7, 8])
	var camp := eras[0]
	assert_eq([camp.gate_pop, camp.gate_gold, camp.gate_landmark], [0, 0, ""])
	var village := eras[1]
	assert_eq([village.gate_pop, village.gate_gold, village.gate_landmark], [15, 30, "meeting_hall"])
	var asc := eras[6]
	assert_eq([asc.gate_pop, asc.gate_gold, asc.gate_landmark], [450, 4000, "dawn_beacon"])


# AC4: a recipe expresses inputs -> outputs per worker per day.
func test_recipe_inputs_to_outputs() -> void:
	var r := RecipeDef.new()
	r.inputs = {"materials": 2}
	r.outputs = {"planks": 1}
	assert_eq(r.inputs["materials"], 2)
	assert_eq(r.outputs["planks"], 1)
	_load_real()
	assert_eq(reg.get_building("forager").recipe.inputs, {})
	assert_eq(reg.get_building("forager").recipe.outputs, {"food": 1.5})


func test_terrain_and_goods_present() -> void:
	_load_real()
	for id in ["grass", "fertile_soil", "forest", "rock", "water", "lumen_vein", "stump", "skystone"]:
		assert_not_null(reg.get_terrain(id), id)
	for id in ["food", "crops", "fish", "materials", "lumen", "gold", "planks", "cut_stone", "lumen_cells", "meals", "tools"]:
		assert_not_null(reg.get_good(id), id)
	assert_eq(reg.get_good("planks").kind, "refined")
	assert_eq(reg.get_good("food").kind, "base")
