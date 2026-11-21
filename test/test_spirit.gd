extends GutTest
## Ticket 13: Spirit meter, target factors, drift, effects, leaving.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var sp: SpiritSystem
var gs: GrowthSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	sp = s.get_system(SpiritSystem)
	gs = s.get_system(GrowthSystem)


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


func test_starts_at_60_and_data_driven() -> void:
	assert_eq(s.spirit(), 60.0)
	assert_eq(reg.spirit.start, 60.0)


func test_target_food_types_hunger_homeless() -> void:
	assert_eq(sp.target(s), 50.0, "base only")
	assert_eq(SpiritSystem.food_type_factor(reg.spirit, 1), 0.0, "first food type gives nothing")
	assert_eq(SpiritSystem.food_type_factor(reg.spirit, 3), 10.0)
	assert_eq(SpiritSystem.food_type_factor(reg.spirit, 9), 20.0, "capped at +20")
	gs.last_day = {"types": 1, "hungry": 0}
	assert_eq(sp.target(s), 50.0)
	gs.last_day = {"types": 1, "hungry": 2}
	assert_eq(_factor("hunger"), -15.0)
	assert_eq(sp.target(s), 35.0)
	# Homeless: more citizens than beds.
	for i in 12:
		s.add_citizen()
	assert_true(s.homeless_count() > 0)
	assert_eq(_factor("homeless"), -10.0)
	assert_eq(sp.target(s), 25.0)


## Variety is market-gated (ticket 23): eating several types with no Market in reach of any home gives no bonus.
func test_food_types_counted_only_through_a_market() -> void:
	s.hearth.inventory.remove("food", 57.0)  # 3 food left, the other 5 citizens eat meals
	s.hearth.inventory.add("meals", 20.0)
	s.step_days(1)
	assert_eq(gs.last_day["types"], 2, "food and meals were eaten")
	assert_eq(_factor("food_types"), 0.0, "no Market, no variety")


func test_target_hook_factors() -> void:
	var names: Array = sp.breakdown(s)["factors"].keys()
	assert_eq(names, ["base", "food_types", "coverage", "hunger", "homeless", "blight", "water", "darkness",
			"tax_office", "planet_grief", "light", "tavern", "moon"])
	for id in ["coverage", "blight", "water", "darkness", "planet_grief"]:
		assert_eq(_factor(id), 0.0, id + " is a hook returning 0")
	assert_true(sp.set_hook("coverage", func(_s): return 10.0))
	assert_true(sp.set_hook("blight", func(_s): return -7.5))
	assert_true(sp.set_hook("water", func(_s): return -4.0))
	assert_true(sp.set_hook("darkness", func(_s): return -20.0))
	assert_true(sp.set_hook("planet_grief", func(_s): return -5.0))
	assert_eq(sp.target(s), 50.0 + 10.0 - 7.5 - 4.0 - 20.0 - 5.0)
	assert_false(sp.set_hook("nonsense", func(_s): return 1.0))
	var b := sp.breakdown(s)
	assert_eq(b["current"], 60.0)
	assert_eq(b["target"], sp.target(s))


func test_target_tax_office() -> void:
	var h := s.map.hearth_spot
	var def := reg.get_building("tent")
	var fake := Building.new()
	fake.id = 999
	fake.def = BuildingDef.new()
	fake.def.id = "tax_office"
	s.buildings[999] = fake
	assert_eq(_factor("tax_office"), -5.0)
	assert_eq(sp.target(s), 45.0)
	assert_not_null(def)
	assert_ne(h, Vector2i(-1, -1))


func test_moves_two_points_a_day_toward_target() -> void:
	gs.last_day = {"types": 1, "hungry": 0}
	s.systems.erase(gs)  # keep the report fixed
	sp.on_day(s)
	assert_eq(s.spirit(), 58.0, "60 -> target 50, two points down")
	sp.on_day(s)
	assert_eq(s.spirit(), 56.0)
	sp.value = 49.0
	sp.on_day(s)
	assert_eq(s.spirit(), 50.0, "does not overshoot")
	sp.set_hook("coverage", func(_s): return 10.0)
	sp.on_day(s)
	assert_eq(s.spirit(), 52.0, "up towards 60")


func test_work_speed_effect() -> void:
	var m := SpiritSystem.work_multiplier(s)
	assert_eq(m, 1.0)
	sp.value = 70.0
	assert_almost_eq(SpiritSystem.work_multiplier(s), 1.15, 0.0001)
	sp.value = 69.9
	assert_eq(SpiritSystem.work_multiplier(s), 1.0)
	sp.value = 30.0
	assert_almost_eq(SpiritSystem.work_multiplier(s), 0.8, 0.0001)
	sp.value = 30.1
	assert_eq(SpiritSystem.work_multiplier(s), 1.0)
	# Wired into production.
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	sp.value = 75.0
	assert_almost_eq(prod.multiplier(s, s.hearth), 1.15, 0.0001)
	sp.value = 20.0
	assert_almost_eq(prod.multiplier(s, s.hearth), 0.8, 0.0001)


func test_high_spirit_grows_faster() -> void:
	sp.value = 75.0
	assert_almost_eq(SpiritSystem.growth_multiplier(s), 1.2, 0.0001)
	sp.value = 50.0
	assert_eq(SpiritSystem.growth_multiplier(s), 1.0)


func test_spirit_override_still_pins() -> void:
	s.spirit_override = 90.0
	assert_eq(s.spirit(), 90.0)
	assert_almost_eq(SpiritSystem.work_multiplier(s), 1.15, 0.0001)


func test_below_20_for_5_days_one_leaves_every_2_days() -> void:
	s.systems.erase(gs)
	sp.set_hook("darkness", func(_s): return -50.0)  # target 0
	sp.value = 15.0
	var pop := s.citizens.size()
	for d in 4:
		sp.on_day(s)
	assert_eq(s.citizens.size(), pop, "4 low days: nobody leaves yet")
	sp.on_day(s)
	assert_eq(s.citizens.size(), pop - 1, "5th low day: the first leaves")
	sp.on_day(s)
	assert_eq(s.citizens.size(), pop - 1)
	sp.on_day(s)
	assert_eq(s.citizens.size(), pop - 2, "then one every 2 days")
	# Recovering resets the count.
	sp.set_hook("darkness", func(_s): return 0.0)
	sp.value = 25.0
	sp.on_day(s)
	assert_eq(sp.low_days, 0)
	sp.set_hook("darkness", func(_s): return -50.0)
	sp.value = 15.0
	for d in 4:
		sp.on_day(s)
	assert_eq(s.citizens.size(), pop - 2, "the 5-day count starts over")
