extends GutTest
## Ticket 16: eras, gates and the Meeting Hall.

const SEED := 42

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	# no Village building exists as data yet: inject one (this registry is private to the test)
	var d := BuildingDef.new()
	d.id = "test_village_hut"
	d.display_name = "Village hut"
	d.era = "village"
	d.category = "housing"
	d.size = Vector2i(2, 2)
	d.placement_rule = "any"
	reg.buildings[d.id] = d


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)


func _free_spot(def_id: String) -> Vector2i:
	for y in range(0, MapState.HEIGHT - 3):
		for x in range(0, MapState.WIDTH - 3):
			if s.can_place(def_id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _grow_to(n: int) -> void:
	while s.citizens.size() < n:
		s.add_citizen()


func test_village_building_locked_in_camp() -> void:
	var o := _free_spot("test_village_hut")
	assert_eq(s.era_id(), "camp")
	var r := s.can_place("test_village_hut", o)
	assert_false(r["ok"])
	assert_eq(r["reason"], "era_locked")
	assert_eq(s.place_building("test_village_hut", o), -1)
	assert_false(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "test_village_hut"))
	# the debug path may bypass the lock
	assert_gt(s.place_building_instant("test_village_hut", o), -1)
	s.era_current = "village"
	assert_true(s.can_place("test_village_hut", _free_spot("test_village_hut"))["ok"])


func test_meeting_hall_pop_gold_advances_to_village() -> void:
	var o := _free_spot("meeting_hall")
	var id := s.place_building_instant("meeting_hall", o)
	assert_gt(id, -1)
	_grow_to(15)
	s.gold = 30.0
	s.step_hours(1)
	assert_eq(s.era_id(), "village")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "camp", "to": "village"})
	assert_eq(s.gold, 30.0)
	assert_true(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "test_village_hut"))


func test_each_gate_part_is_required() -> void:
	var id := s.place_building_instant("meeting_hall", _free_spot("meeting_hall"))
	_grow_to(14)
	s.gold = 30.0
	s.step_hours(1)
	assert_eq(s.era_id(), "camp", "pop 14")
	_grow_to(15)
	s.gold = 29.0
	s.step_hours(1)
	assert_eq(s.era_id(), "camp", "gold 29")
	s.gold = 30.0
	s.buildings[id].site = true  # an unfinished landmark does not count
	s.step_hours(1)
	assert_eq(s.era_id(), "camp", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "village")


func test_gate_numbers_come_from_data_rows() -> void:
	var row := reg.get_era("village")
	var old_pop := row.gate_pop
	var old_gold := row.gate_gold
	row.gate_pop = 3
	row.gate_gold = 7
	s.place_building_instant("meeting_hall", _free_spot("meeting_hall"))
	_grow_to(3)
	s.gold = 7.0
	var g := s.era_gate()
	assert_eq(g["pop_need"], 3)
	assert_eq(g["gold_need"], 7)
	s.step_hours(1)
	row.gate_pop = old_pop
	row.gate_gold = old_gold
	assert_eq(s.era_id(), "village")


func test_era_override_still_pins() -> void:
	s.era_override = "town"
	assert_eq(s.era_id(), "town")
	assert_eq(s.era_current, "camp")
