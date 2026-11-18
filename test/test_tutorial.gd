extends GutTest
## Ticket 82: TutorialSystem, the ten guided goals (D59a, D66, D69).

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const AUTUMN := 2 * GameClock.DAYS_PER_SEASON
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement
var t: TutorialSystem
var _completed: Array[String] = []
var _finished: Array[Dictionary] = []


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_new(true)


func _new(tutorial: bool) -> void:
	s = Settlement.new_game(SEED, reg, false, tutorial)
	s.planet_health_override = 100.0
	t = s.get_system(TutorialSystem)
	_completed.clear()
	_finished.clear()
	s.events.subscribe("tutorial_goal_completed", func(e: Dictionary) -> void: _completed.append(e["data"]["id"]))
	s.events.subscribe("tutorial_finished", func(e: Dictionary) -> void: _finished.append(e["data"]))


func _current_id() -> String:
	var g := t.current_goal()
	return g.id if g != null else ""


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


## First valid origin for a def around the Hearth (ring by ring), or (-1, -1).
func _spot(def_id: String, near: Vector2i) -> Vector2i:
	for r in range(1, 20):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var o := near + Vector2i(dx, dy)
				if s.can_place(def_id, o)["ok"]:
					return o
	return Vector2i(-1, -1)


## A finished building through the placement command and the construction hand-over (emits building_completed).
func _build(def_id: String, origin: Vector2i) -> Building:
	var id := s.place_building(def_id, origin)
	assert_ne(id, -1, "%s placed" % def_id)
	var b: Building = s.buildings[id]
	s.complete_site(b)
	return b


func _road_out() -> void:
	var start := s.map.hearth_spot + Vector2i(s.hearth.def.size.x, 0)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.place_road(start + d):
			return
	fail_test("no road tile next to the starting road")


func _forager_on_road() -> Building:
	for r in range(1, 12):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var o: Vector2i = s.map.hearth_spot + Vector2i(dx, dy)
				if s.can_place("forager", o)["ok"]:
					var b := _build("forager", o)
					if b.connected:
						return b
					s.demolish(b.id)
	return null


func _vein_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.can_place("lumen_tap", Vector2i(x, y))["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_scripted_run_completes_all_ten_goals_in_order() -> void:
	var ids: Array[String] = []
	for g in reg.tutorial_goals_in_order():
		ids.append(g.id)
	assert_eq(ids.size(), 10)
	assert_true(t.is_active())
	assert_eq(_current_id(), ids[0])
	s.step_hours(3)
	assert_eq(_current_id(), ids[0], "waiting does not complete the camera goal")
	s.report_camera_moved()
	assert_eq(_current_id(), ids[1])
	_road_out()
	assert_eq(_current_id(), ids[2], "a second road tile joined to the Hearth")
	var home := _spot("tent", s.map.hearth_spot)
	_build("tent", home)
	assert_eq(_current_id(), ids[2], "one tent is not two")
	_build("tent", _spot("tent", s.map.hearth_spot))
	assert_eq(_current_id(), ids[3])
	assert_not_null(_forager_on_road(), "a forager beside the road")
	assert_eq(_current_id(), ids[4])
	_build("woodcutter", _spot("woodcutter", s.map.hearth_spot))
	assert_eq(_current_id(), ids[5])
	_build("lumen_tap", _vein_spot())
	assert_eq(_current_id(), ids[6])
	_build("market", _spot("market", s.map.hearth_spot))
	assert_eq(_current_id(), ids[7])
	while s.citizens.size() < 12:
		s.add_citizen()
	assert_eq(_current_id(), ids[8])
	# the forecast arrives with too little Lumen for 12 citizens over the whole Dimming
	_to_day(AUTUMN)
	s.step_hours(1)
	assert_eq(s.events.log_of("dimming_forecast").size(), 1)
	assert_eq(_current_id(), ids[8], "forecast seen but the stock is short")
	var need := t.stock_targets(s)
	assert_eq(need["length"], 2)
	assert_almost_eq(float(need["lumen_target"]), 12.0 * 0.5 * 2.0, 0.001)
	assert_almost_eq(float(need["food_target"]), 12.0 * 1.0 * 2.0, 0.001)
	assert_true(bool(need["ready"]))
	assert_false(bool(need["enough"]))
	s.hearth.inventory.add("lumen", 30.0)
	s.step_hours(1)
	assert_eq(_current_id(), ids[9])
	_to_day(WINTER + 2)
	assert_eq(s.events.log_of("dimming_ended").size(), 1)
	assert_eq(_completed, ids, "all ten, in order")
	assert_eq(_finished.size(), 1)
	assert_true(t.is_finished())
	assert_false(t.is_active())


func test_goal_already_met_completes_when_it_becomes_current() -> void:
	_build("tent", _spot("tent", s.map.hearth_spot))
	_build("tent", _spot("tent", s.map.hearth_spot))
	_road_out()
	_forager_on_road()
	_build("woodcutter", _spot("woodcutter", s.map.hearth_spot))
	_build("lumen_tap", _vein_spot())
	_build("market", _spot("market", s.map.hearth_spot))
	while s.citizens.size() < 12:
		s.add_citizen()
	s.step_hours(2)
	assert_eq(_current_id(), "camera_moved", "the goals still go in order")
	assert_eq(_completed.size(), 0)
	s.report_camera_moved()
	assert_eq(_completed.size(), 8, "everything already done completes at once")
	assert_eq(_current_id(), reg.tutorial_goals_in_order()[8].id)


func test_skip_finishes_and_inactive_never_emits() -> void:
	s.skip_tutorial()
	assert_true(t.is_finished())
	assert_false(t.is_active())
	assert_eq(_finished.size(), 1)
	assert_eq(_completed.size(), 0)
	s.report_camera_moved()
	_road_out()
	s.step_hours(2)
	assert_eq(_completed.size(), 0, "a skipped tutorial completes nothing")
	_new(false)
	assert_false(t.is_active())
	s.report_camera_moved()
	_road_out()
	_build("tent", _spot("tent", s.map.hearth_spot))
	s.step_hours(2)
	assert_eq(_completed.size(), 0)
	assert_eq(_finished.size(), 0)
	s.skip_tutorial()
	assert_eq(_finished.size(), 0, "skipping an inactive tutorial emits nothing")


func test_save_round_trip_mid_tutorial() -> void:
	s.report_camera_moved()
	_road_out()
	_build("tent", _spot("tent", s.map.hearth_spot))
	var back := Settlement.from_dict(s.to_dict(), reg)
	var bt := back.get_system(TutorialSystem) as TutorialSystem
	assert_true(bt.is_active())
	assert_eq(bt.current_goal().id, t.current_goal().id)
	assert_eq(bt.goal_index(), t.goal_index())
	assert_eq(bt.save_state(), t.save_state())
	# and it carries on: the second tent finishes goal 3 in the loaded game
	var o := _spot("tent", s.map.hearth_spot)
	var id := back.place_building("tent", o)
	back.complete_site(back.buildings[id])
	assert_eq(bt.current_goal().id, reg.tutorial_goals_in_order()[3].id)


func test_old_save_loads_with_tutorial_finished() -> void:
	var old := Settlement.new_game(SEED, reg).to_dict()
	(old["systems"] as Dictionary).erase("tutorial")
	var path := "/tmp/nyx-flash/hearthvein_ticket82.dat"
	DirAccess.make_dir_recursive_absolute("/tmp/nyx-flash")
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var({"version": 2, "state": old}, false)
	f.close()
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded)
	var lt := loaded.get_system(TutorialSystem) as TutorialSystem
	assert_true(lt.is_finished())
	assert_false(lt.is_active())
	assert_eq(SaveGame.CURRENT_VERSION, 3)
	var v0 := SaveGame.load("res://test/fixtures/save_v0.dat", reg)
	assert_true((v0.get_system(TutorialSystem) as TutorialSystem).is_finished(), "the oldest save too")
