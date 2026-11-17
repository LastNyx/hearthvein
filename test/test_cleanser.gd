extends GutTest
## Ticket 30: Cleanser (design.md sections 12, 13 and 16 Town). It clears the nearest blighted tile in r5 every two
## working days and adds its +0.01/day planet health term.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var cs: CleaningSystem
var ph: PlanetHealthSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	h = s.map.hearth_spot
	s.systems.erase(s.get_system(JobSystem))  # keep the hand-assigned crew: the hourly refresh would drop it
	s.hearth.inventory.add("food", 600.0)  # long tests must not starve the assigned worker out of the settlement
	cs = s.get_system(CleaningSystem) as CleaningSystem
	ph = s.get_system(PlanetHealthSystem) as PlanetHealthSystem


## A placeable 2x1 spot near the Hearth.
func _spot() -> Vector2i:
	for r in range(2, 16):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place("cleanser", Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _placed() -> Building:
	var origin := _spot()
	assert_ne(origin, Vector2i(-1, -1), "a Cleanser fits near the Hearth")
	var id := s.place_building_instant("cleanser", origin)
	assert_true(id >= 0, "the Cleanser was placed")
	return s.buildings[id]


func _staff(b: Building, n: int = 1) -> void:
	var i := 0
	for cid in s.citizens:
		if i >= n:
			break
		var c: Citizen = s.citizens[cid]
		c.job_id = b.id
		c.job_kind = Citizen.JOB_WORK
		i += 1


func _unstaff(b: Building) -> void:
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id:
			c.job_id = -1
			c.job_kind = Citizen.JOB_NONE


## Enough Lumen in the input buffer for a long test: the real cap holds two days of upkeep.
func _power(b: Building) -> void:
	b.input_buffer.cap = 1000.0
	b.input_buffer.add("lumen", 1000.0)


func _forest_count() -> int:
	var fi := s.map.terrain_index("forest")
	return s.map.terrain.count(fi) if fi >= 0 else 0


# AC1a: the data row is the Town table's, with the cleaning numbers in data, not code.
func test_data_matches_the_town_row() -> void:
	var d := reg.get_building("cleanser")
	assert_not_null(d, "data/buildings/cleanser.tres exists")
	assert_eq([d.era, d.size, d.cost], ["town", Vector2i(2, 1),
			{"materials": 60, "gold": 20, "lumen": 10}])
	assert_eq([d.worker_slots, d.upkeep_lumen], [2, 2.0])
	assert_eq([d.clean_radius, d.clean_interval_days], [5, 2], "section 12: 1 tile every 2 days in r5")
	assert_almost_eq(d.health_per_day, 0.01, 0.0000001, "section 13: Cleanser +0.01/day")


# AC1b: one tile every two working days, nearest first, through the blight-clear path.
func test_cleanser_clears_the_nearest_tile_every_two_days() -> void:
	var b := _placed()
	_staff(b)
	_power(b)
	var near := b.origin + Vector2i(0, -3)  # squared distance 9 from the closest footprint tile
	var far := b.origin + Vector2i(0, 4)  # 16
	assert_true(s.set_blighted(near, true))
	assert_true(s.set_blighted(far, true))
	assert_eq(BlightSystem.count(s), 2)
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 2, "a Cleanser clears every 2 working days, not every day")
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 1)
	assert_false(s.map.is_blighted(near.x, near.y), "the nearest tile went first")
	assert_true(s.map.is_blighted(far.x, far.y))
	var cleared := s.events.log_of("blight_changed").filter(
			func(e: Dictionary) -> bool: return e["data"]["tile"] == near and not e["data"]["blighted"])
	assert_eq(cleared.size(), 1, "clearing goes through Settlement.set_blighted, so views and fouling hear it")
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 1, "the countdown restarts after a clear")
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 0)


func test_tie_break_is_lower_y_then_lower_x() -> void:
	var b := _placed()
	_staff(b)
	var left := b.origin + Vector2i(-3, 0)  # squared distance 9
	var above := b.origin + Vector2i(0, -3)  # 9, lower y
	var above_right := b.origin + Vector2i(1, -3)  # 9, same y, higher x
	assert_true(s.set_blighted(left, true))
	assert_true(s.set_blighted(above_right, true))
	assert_true(s.set_blighted(above, true))
	assert_eq(cs.next_tile(s, b), above, "equal distance: lower y wins, then lower x")
	_power(b)
	s.step_days(2)
	assert_false(s.map.is_blighted(above.x, above.y), "the chosen tile is the one cleared")
	assert_eq(BlightSystem.count(s), 2)


func test_cleanser_leaves_blight_outside_its_radius() -> void:
	var b := _placed()
	_staff(b)
	_power(b)
	var out := b.origin + Vector2i(7, 0)  # 36 from the right footprint tile, outside r5
	assert_true(s.set_blighted(out, true))
	assert_eq(cs.next_tile(s, b), Vector2i(-1, -1), "nothing is in reach")
	s.step_days(4)
	assert_true(s.map.is_blighted(out.x, out.y), "r5 does not reach 7 tiles out")
	assert_eq(BlightSystem.count(s), 1)


# A staffed but unpaid Cleanser does not clean: it is not working (ticket 27).
func test_cleanser_must_be_staffed_and_powered() -> void:
	var b := _placed()
	var t := b.origin + Vector2i(0, -2)
	assert_true(s.set_blighted(t, true))
	s.step_days(4)
	assert_true(s.map.is_blighted(t.x, t.y), "nobody is assigned: nothing is cleaned")
	_staff(b)
	s.hearth.inventory.remove("lumen", 999.0)
	s.step_days(4)
	assert_false((s.get_system(UpkeepSystem) as UpkeepSystem).is_paid(b.id), "no Lumen anywhere")
	assert_true(s.map.is_blighted(t.x, t.y), "staffed but unpowered: nothing is cleaned")
	_power(b)
	s.step_days(2)
	assert_false(s.map.is_blighted(t.x, t.y), "staffed and powered: it cleans")
	assert_true(s.set_blighted(t, true))
	b.paused = true
	s.step_days(4)
	assert_true(s.map.is_blighted(t.x, t.y), "paused: nothing is cleaned")


# AC2: the Cleanser adds its planet health term while it works.
func test_cleanser_adds_its_planet_health_term() -> void:
	var b := _placed()
	_staff(b)
	_power(b)
	assert_true(PlanetHealthSystem.is_working(s, b))
	assert_almost_eq(float(ph.daily_breakdown(s)["buildings"]), 0.01, 0.0000001,
			"section 13: Cleanser +0.01/day")
	ph.value = 50.0
	s.step_days(1)
	var want := 0.01 + float(_forest_count()) * reg.planet.per_forest_tile
	assert_almost_eq(s.planet_health() - 50.0, want, 0.0000001, "the daily delta carries the Cleanser's term")
	_unstaff(b)
	assert_false(PlanetHealthSystem.is_working(s, b), "unstaffed cleaners do not count")
	assert_eq(float(ph.daily_breakdown(s)["buildings"]), 0.0)


func test_countdown_is_runtime_state_with_a_save_key() -> void:
	var b := _placed()
	_staff(b)
	_power(b)
	assert_true(s.set_blighted(b.origin + Vector2i(0, -2), true))
	s.step_days(1)
	assert_eq(SimSystem.save_key_of(cs), "cleaning")
	assert_eq(int(cs._days.get(b.id, 0)), 1, "one working day counted")
	var state := cs.save_state()
	var loaded := CleaningSystem.new()
	loaded.load_state(state, s)
	assert_eq(loaded.save_state(), state)
	assert_eq(int(loaded._days.get(b.id, 0)), 1, "the day already worked survives a load")
