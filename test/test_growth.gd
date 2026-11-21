extends GutTest
## Ticket 12: eating, growth bar, starvation, homelessness, immigration, soft cap.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var g: GrowthSystem
var _hearth_beds: int


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	_hearth_beds = reg.get_building("hearth").housing_beds


func after_each() -> void:
	reg.get_building("hearth").housing_beds = _hearth_beds


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	h = s.map.hearth_spot
	g = s.get_system(GrowthSystem)
	s.spirit_override = 39.0  # below the immigration threshold (40): only the growth bar adds people unless a test says otherwise
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")


func _tent(dx: int) -> void:
	assert_true(s.place_building_instant("tent", Vector2i(h.x + dx, h.y - 2)) >= 0)


func _food() -> float:
	return s.hearth.inventory.amount_of("food")


## One day so the system records its food stock, then the test adds food as surplus.
func _prime() -> void:
	s.step_days(1)


func test_surplus_fills_bar_and_spawns_citizen_only_with_free_bed() -> void:
	_prime()
	assert_eq(s.citizens.size(), 8)
	# No free bed: the bar fills to its size and waits.
	s.hearth.inventory.add("food", 40.0)
	s.step_days(1)
	assert_eq(s.citizens.size(), 8, "no free bed, no citizen")
	assert_almost_eq(g.bar, GrowthSystem.bar_size(reg, 8), 0.001, "bar full and waiting")
	# A tent gives three beds: the full bar turns into one citizen the next day.
	_tent(4)
	s.step_days(1)
	assert_eq(s.citizens.size(), 9)
	assert_eq(s.homeless_count(), 0)
	assert_eq(g.last_day["grown"], 1)
	assert_true(g.bar < GrowthSystem.bar_size(reg, 9), "bar was spent")


func test_bar_size_is_3_plus_pop_over_6() -> void:
	assert_almost_eq(GrowthSystem.bar_size(reg, 8), 3.0 + 8.0 / 6.0, 0.0001)
	assert_almost_eq(GrowthSystem.bar_size(reg, 60), 13.0, 0.0001)


func test_new_citizen_appears_at_the_hearth() -> void:
	_tent(4)
	_prime()
	s.hearth.inventory.add("food", 40.0)
	s.step_days(1)
	assert_eq(s.citizens.size(), 9)
	s.step_seconds(0.001)  # walkers sync on the next movement tick
	var walkers := s.get_system(WalkerSystem) as WalkerSystem
	var newest: int = s.citizens.keys().max()
	var w := walkers.walker_of(newest)
	assert_not_null(w)
	assert_eq(w.at_building, s.hearth.id, "newcomer starts at the Hearth")


func test_no_growth_while_homeless() -> void:
	_prime()
	s.add_citizen()  # 9 people, 8 beds
	assert_eq(s.homeless_count(), 1)
	_tent(4)
	s.demolish(s.building_at(Vector2i(h.x + 4, h.y - 2)).id)
	assert_eq(s.homeless_count(), 1)
	s.hearth.inventory.add("food", 100.0)
	s.step_days(3)
	assert_true(s.citizens.size() <= 9, "homeless blocks growth")
	assert_eq(s.citizens.size(), 9)


func test_food_zero_with_deficit_one_leaves_per_day() -> void:
	s.hearth.inventory.remove("food", 1000.0)
	s.step_days(1)
	assert_eq(s.citizens.size(), 7)
	s.step_days(1)
	assert_eq(s.citizens.size(), 6)
	s.step_days(2)
	assert_eq(s.citizens.size(), 4)
	# Food comes back and balances: nobody else leaves.
	s.hearth.inventory.add("food", 50.0)
	s.step_days(2)
	assert_true(s.citizens.size() >= 4, "nobody leaves while food lasts")
	assert_eq(g.last_day["left"], 0)


func test_eating_takes_one_food_each() -> void:
	s.step_days(1)
	assert_almost_eq(_food(), 52.0, 0.001)


func test_every_food_good_is_eaten_food_first() -> void:
	s.hearth.inventory.remove("food", 1000.0)
	s.hearth.inventory.add("meals", 20.0)
	s.hearth.inventory.add("food", 3.0)
	s.step_days(1)
	assert_eq(s.citizens.size(), 8, "3 food + 5 meals feed eight")
	assert_almost_eq(_food(), 0.0, 0.001, "food goes first")
	assert_almost_eq(s.hearth.inventory.amount_of("meals"), 15.0, 0.001)


func test_citizens_cannot_eat_from_another_region() -> void:
	var hr := s.map.get_region(h.x, h.y)
	var other := -1
	var spot := Vector2i(-1, -1)
	for r in MapState.REGION_COUNT:
		if r == hr:
			continue
		var rect := MapState.region_rect(r)
		s.map.set_region_owned(r, true)
		for y in range(rect.position.y + 4, rect.end.y - 4):
			for x in range(rect.position.x + 4, rect.end.x - 4):
				if spot.x < 0 and s.can_place("storehouse", Vector2i(x, y))["ok"]:
					spot = Vector2i(x, y)
		if spot.x >= 0:
			other = r
			break
		s.map.set_region_owned(r, false)
	assert_true(other >= 0, "found a storehouse spot in another region")
	var id := s.place_building_instant("storehouse", spot)
	assert_true(id >= 0)
	(s.buildings[id] as Building).inventory.add("food", 300.0)
	s.hearth.inventory.remove("food", 1000.0)
	s.step_days(1)
	assert_eq(s.citizens.size(), 7, "a full storehouse in another region does not feed the Hearth's people")
	assert_almost_eq((s.buildings[id] as Building).inventory.amount_of("food"), 300.0, 0.001)
	# Same region: the nearest storehouse with food feeds them.
	var near := s.place_building_instant("storehouse", Vector2i(h.x + 6, h.y + 3))
	if near >= 0:
		(s.buildings[near] as Building).inventory.add("food", 50.0)
		s.step_days(1)
		assert_eq(s.citizens.size(), 7)
		assert_almost_eq((s.buildings[near] as Building).inventory.amount_of("food"), 43.0, 0.001)


func test_immigration_every_day_at_spirit_40_with_free_beds() -> void:
	_tent(4)
	s.hearth.inventory.add("food", 90.0)
	s.spirit_override = 60.0
	s.step_days(1)
	assert_eq(s.citizens.size(), 9, "one newcomer on day 1")
	s.step_days(1)
	assert_eq(s.citizens.size(), 10, "and one more on day 2")
	s.step_days(2)
	assert_eq(s.citizens.size(), 11, "11 beds (Hearth 8 + Tent 3): one more, then no free bed")


func test_no_immigration_below_spirit_40() -> void:
	_tent(4)
	s.hearth.inventory.add("food", 90.0)
	s.spirit_override = 39.0
	s.step_days(1)
	s.step_days(8)
	assert_eq(s.citizens.size(), 8)
	assert_eq(s.spirit(), 39.0)


func test_bar_multiplier_above_600_and_no_immigration() -> void:
	assert_almost_eq(GrowthSystem.bar_size(reg, 600), 103.0, 0.0001, "no multiplier at the cap")
	assert_almost_eq(GrowthSystem.bar_size(reg, 700), (3.0 + 700.0 / 6.0) * 2.0, 0.0001, "x2 at 700")
	assert_almost_eq(GrowthSystem.bar_size(reg, 650), (3.0 + 650.0 / 6.0) * 1.5, 0.0001, "x1.5 at 650")
	reg.get_building("hearth").housing_beds = 2000
	s.hearth.inventory.cap = 1000000.0
	s.hearth.inventory.add("food", 1000000.0)
	s.spirit_override = 90.0
	for i in 592:
		s.add_citizen()
	assert_eq(s.citizens.size(), 600)
	s.step_days(3)
	assert_eq(s.citizens.size(), 601, "immigration still works at 600")
	s.step_days(6)
	assert_eq(s.citizens.size(), 601, "none above 600")
