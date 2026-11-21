extends GutTest
## Ticket 159: economy pressure. Food output down (Forager, Farm and Fishing Dock make 4 a worker-day), lean winters
## (those three make x0.5 in winter, the Glowcap Grove does not), Lumen upkeep from the Village era (1 a day per
## Village workplace, none in Camp), and a 3% raw Lumen leak.

const SEED := 42
const WINTER_HOURS := 3 * GameClock.DAYS_PER_SEASON * GameClock.HOURS_PER_DAY

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	s.systems.erase(s.get_system(GrowthSystem))


## A cleared, road-connected strip east of the Hearth, so a building placed beside it gets its crew.
func _strip(st: Settlement) -> void:
	var h := st.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 5):
			if st.map.terrain_id_at(x, y) == "forest":
				st.set_terrain(Vector2i(x, y), "grass")
		st.place_road(Vector2i(x, h.y))


func _put(id: String) -> Building:
	var hs := s.map.hearth_spot
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(MapState.HEIGHT - 3):
		for x in range(MapState.WIDTH - 3):
			var d := (Vector2i(x, y) - hs).length_squared()
			if d < best_d and s.can_place(id, Vector2i(x, y), true)["ok"]:
				best = Vector2i(x, y)
				best_d = d
	assert_true(best.x >= 0, "a spot for %s near %s" % [id, hs])
	return s.buildings[s.place_building_instant(id, best)]


## Criterion 1: base output 4 per work day.
func test_food_producers_make_4_per_work_day_at_base() -> void:
	assert_eq(reg.get_building("forager").recipe.outputs, {"food": 4.0})
	assert_eq(reg.get_building("farm").recipe.outputs, {"crops": 4.0})
	assert_eq(reg.get_building("fishing_dock").recipe.outputs, {"fish": 4.0})


## Criterion 2: winter halves the three food producers, never the Glowcap Grove; the other seasons leave them alone.
func test_winter_halves_food_producers_but_not_glowcap() -> void:
	var forager := _put("forager")
	var grove := _put("glowcap_grove")
	assert_eq(ProductionSystem.winter_modifier(s, forager), 1.0, "spring is not lean")
	s.clock.total_hours = WINTER_HOURS - 1
	assert_eq(s.clock.season_name(), "autumn")
	assert_eq(ProductionSystem.winter_modifier(s, forager), 1.0)
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	var before_f := ps.multiplier(s, forager)
	var before_g := ps.multiplier(s, grove)
	s.clock.total_hours = WINTER_HOURS
	assert_eq(s.clock.season_name(), "winter")
	assert_eq(ProductionSystem.winter_modifier(s, forager), 0.5, "winter: Forager x0.5")
	for id in ["farm", "fishing_dock"]:
		assert_true(reg.get_building(id).lean_winter, "%s is a lean winter producer" % id)
	assert_eq(ProductionSystem.winter_modifier(s, grove), 1.0, "the Glowcap Grove is not lean")
	var dim_ratio := DimmingSystem.output_modifier(s, forager)
	assert_almost_eq(ps.multiplier(s, forager), before_f * 0.5 * dim_ratio, 0.0001,
			"stacks with the Dimming")
	assert_almost_eq(ps.multiplier(s, grove), before_g * DimmingSystem.output_modifier(s, grove), 0.0001)


## Criterion 2 (UI): the hover says so and a toast fires at winter start.
func test_lean_winter_is_shown_on_hover_and_by_a_toast() -> void:
	var forager := _put("forager")
	var hm := HudModel.new(s)  # kept in a var: a freed model stays subscribed
	assert_eq(hm.lean_winter_text(forager), "")
	s.clock.total_hours = WINTER_HOURS
	assert_eq(hm.lean_winter_text(forager), "x0.5 Lean winter")
	assert_string_contains(hm.tooltip_for_building(forager)["text"], "Lean winter")
	var nc := NotificationCenter.new(s)
	s.clock.total_hours = WINTER_HOURS - 1
	s.step_hours(1)  # the first hour of winter starts the season
	var texts: Array[String] = []
	for it in nc.items:
		texts.append(it["text"])
	assert_true(texts.has("Lean winter: food x0.5"), "winter start toast: %s" % [texts])


## Criterion 3: upkeep runs from Village and charges 1 Lumen per Village workplace; Camp pays none.
func test_village_workplaces_pay_1_lumen_and_camp_none() -> void:
	for id in ["farm", "fishing_dock", "forester", "quarry", "sawmill"]:
		assert_eq(reg.get_building(id).upkeep_lumen, 1.0, "%s costs 1 Lumen a day" % id)
	for id in ["forager", "woodcutter", "lumen_tap", "well"]:
		assert_eq(reg.get_building(id).upkeep_lumen, 0.0, "%s (Camp) costs none" % id)
	assert_true(UpkeepSystem.is_on(s), "upkeep is on in the Village")
	var camp := Settlement.new_game(SEED, reg)
	assert_eq(camp.era_id(), "camp")
	assert_false(UpkeepSystem.is_on(camp), "and off in Camp")
	s.systems.erase(s.get_system(HaulingSystem))
	s.systems.erase(s.get_system(StorageSystem))  # no leak blurring the count
	_strip(s)
	var farm: Building = s.buildings[s.place_building_instant("farm", Vector2i(s.map.hearth_spot.x + 4, s.map.hearth_spot.y - 2))]
	assert_eq(HaulingSystem.input_need(reg, farm.def), {}, "nobody hauls the Village upkeep Lumen")
	s.step_days(1)  # the crew is assigned
	var before := float(s.totals().get("lumen", 0.0))
	s.step_days(1)
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us.is_paid(farm.id), "paid out of storage")
	assert_almost_eq(float(s.totals().get("lumen", 0.0)), before - 1.0, 0.001, "one day's Lumen left storage")
	var before2 := float(s.totals().get("lumen", 0.0))
	s.step_days(1)
	assert_true(us.is_paid(farm.id))
	s.hearth.inventory.remove("lumen", 1000.0)
	s.step_days(1)
	assert_false(us.is_paid(farm.id), "with no Lumen in storage the day goes unpaid")
	assert_lt(before2, before, "Lumen kept leaving storage")
	# Only a staffed workplace pays: with every citizen gone the farm costs nothing.
	var idle := Settlement.new_game(SEED, reg)
	idle.era_override = "village"
	idle.systems.erase(idle.get_system(StorageSystem))
	var hs := idle.map.hearth_spot
	_strip(idle)
	idle.place_building_instant("farm", Vector2i(hs.x + 4, hs.y - 2))
	while idle.citizens.size() > 0:
		idle.remove_citizen(idle.citizens.keys().max())
	var stock := float(idle.totals().get("lumen", 0.0))
	idle.step_days(1)
	assert_almost_eq(float(idle.totals().get("lumen", 0.0)), stock, 0.001, "an unstaffed Village workplace pays nothing")
	assert_true(hs.x >= 0)


## Criterion 4: the raw Lumen leak is 3% a day.
func test_lumen_leak_is_three_percent() -> void:
	s.hearth.inventory.add("lumen", 100.0)
	var before := s.hearth.inventory.amount_of("lumen")
	(s.get_system(StorageSystem) as StorageSystem).on_day(s)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), before * 0.97, 0.0001)
