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


## Ticket 169: only the first 500 raw Lumen of the whole stock leaks, so a big reserve loses at most 15 a day.
func test_lumen_leak_is_capped() -> void:
	_strip(s)
	s.hearth.inventory.add("lumen", 2000.0)
	_put("storehouse").inventory.add("lumen", 400.0)
	_put("storehouse").inventory.add("lumen", 400.0)
	var before: float = s.totals().get("lumen", 0.0)
	assert_gt(before, 900.0, "a reserve well over the cap")
	(s.get_system(StorageSystem) as StorageSystem).on_day(s)
	assert_almost_eq(before - float(s.totals().get("lumen", 0.0)), 15.0, 0.0001)


## Ticket 171: a site no road reaches wants stone but no storehouse can serve it; that must not hide the stored stone from
## the Mason beside the road (the plan once cached "no stone source" per good and every Mason stood empty for years).
func test_unreachable_site_does_not_starve_a_masons_stone() -> void:
	_strip(s)
	var store := _put("storehouse")
	store.inventory.add("stone", 80.0)
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var h := s.map.hearth_spot
	for x in range(h.x + 7, h.x + 13):
		for y in range(h.y + 7, h.y + 13):
			var ring := x == h.x + 7 or x == h.x + 12 or y == h.y + 7 or y == h.y + 12
			s.set_terrain(Vector2i(x, y), "water" if ring else "grass")  # a grass islet in a ring of water: nobody can walk there
	var site_id := s.place_building("builders_yard", Vector2i(h.x + 8, h.y + 9))
	assert_true(site_id >= 0, "a Builders Yard site off every road")
	var mason := _put("mason")
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_not_null(t, "a trip is planned")
	if t != null:
		assert_eq(t.good, "stone")
		assert_eq(t.dst, mason.id, "the stone goes to the Mason")


## Ticket 171: a refill goes to a High priority building before an older one, so the newest buildings' Lumen upkeep is
## not left for last when every older building asks for a refill too.
func test_high_priority_consumer_is_refilled_first() -> void:
	_strip(s)
	var store := _put("storehouse")
	store.inventory.add("stone", 80.0)
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var older := _put("mason")
	var newer := _put("mason")
	assert_lt(older.id, newer.id)
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_not_null(t)
	if t != null:
		assert_eq(t.dst, older.id, "normal priority: the older Mason first")
	s.set_building_priority(newer.id, "high")
	t = hs._plan(s, ws, -1)
	assert_not_null(t)
	if t != null:
		assert_eq(t.dst, newer.id, "High priority: the newer Mason first")


## Ticket 171: an upgrade that is a fraction short of a good (0.4 of a cut stone) still gets that last delivery; with the
## floor at min_pickup the upgrade, and the home it raises, stood open for years and held back every other upgrade.
func test_upgrade_last_delivery_may_be_below_min_pickup() -> void:
	_strip(s)
	var store := _put("storehouse")
	store.inventory.add("cut_stone", 50.0)
	store.inventory.add("planks", 50.0)
	var home := _put("tent")
	s.era_override = "town"
	assert_true(s.upgrade(home.id), "the tent upgrade started")
	var cost := home.upgrade_cost
	assert_true(cost.has("cut_stone"), "a tent upgrade costs cut stone")
	for g in cost:
		home.upgrade_buffer.add(g, float(cost[g]) - (0.4 if g == "cut_stone" else 0.0))
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_not_null(t, "a trip for the last 0.4 units")
	if t != null:
		assert_eq(t.dst, home.id)
		assert_almost_eq(t.planned, 0.4, 0.001)
