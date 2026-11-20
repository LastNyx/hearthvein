extends GutTest

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


class CountSys extends SimSystem:
	var hours := 0
	var days := 0
	var seasons := 0
	func on_hour(_s: Settlement) -> void: hours += 1
	func on_day(_s: Settlement) -> void: days += 1
	func on_season(_s: Settlement) -> void: seasons += 1


func test_start_state() -> void:
	var s := Settlement.new_game(1, reg)
	assert_eq(s.clock.total_hours, 0)
	assert_eq(s.clock.year(), 1)
	assert_eq(s.clock.season_name(), "spring")
	assert_eq(s.clock.day(), 1)
	assert_eq(s.clock.hour(), 0)


func test_calendar_units() -> void:
	var s := Settlement.new_game(1, reg)
	s.step_hours(23)
	assert_eq(s.clock.day(), 1)
	s.step_hours(1)
	assert_eq(s.clock.day(), 2)
	s.step_hours(24 * 7)
	assert_eq(s.clock.season_name(), "summer")
	assert_eq(s.clock.day(), 1)
	s.step_days(8 * 3)
	assert_eq(s.clock.year(), 2)
	assert_eq(s.clock.season_name(), "spring")
	assert_eq(s.clock.total_hours, 24 * 32)


func test_hooks_fire_once_per_boundary() -> void:
	var s := Settlement.new_game(1, reg)
	var c := CountSys.new()
	s.add_system(c)
	s.step_hours(24 * 8 - 1)
	assert_eq(c.days, 7)
	assert_eq(c.seasons, 0)
	s.step_hours(1)
	assert_eq(c.days, 8)
	assert_eq(c.seasons, 1)
	s.step_days(32 - 8)
	assert_eq(c.hours, 24 * 32)
	assert_eq(c.days, 32)
	assert_eq(c.seasons, 4)


func test_events_emitted() -> void:
	var s := Settlement.new_game(1, reg)
	var got: Array = []
	s.events.subscribe("season_started", func(e: Dictionary) -> void: got.append(e["data"]["season"]))
	s.step_days(32)
	assert_eq(s.events.log_of("day_started").size(), 32)
	assert_eq(got, ["summer", "autumn", "winter", "spring"])
	assert_eq(s.events.log_of("season_started")[0]["hour"], 24 * 8)


func test_driver_speeds() -> void:
	var results: Dictionary = {}
	for sp in [0, 1, 2, 3]:
		var d := SimDriver.new()
		d.settlement = Settlement.new_game(1, reg)
		d.set_speed(sp)
		for i in 240:
			d.advance(0.5)  # 120 real seconds, one day at 1x
		results[sp] = d.settlement.clock.total_hours
		d.free()
	assert_eq(results[0], 0)
	assert_eq(results[1], 24)
	assert_eq(results[2], 48)
	assert_eq(results[3], 72)


# 119: a day is 120 real seconds at 1x, so one game hour is 5 s.
func test_an_hour_is_five_seconds_at_1x() -> void:
	assert_eq(GameClock.REAL_SECONDS_PER_DAY, 120.0)
	assert_eq(GameClock.REAL_SECONDS_PER_HOUR, 5.0)
	var d := SimDriver.new()
	d.settlement = Settlement.new_game(1, reg)
	d.set_speed(1)
	for i in 9:
		d.advance(0.5)
	assert_eq(d.settlement.clock.total_hours, 0, "4.5 s is not yet an hour")
	d.advance(0.5)
	assert_eq(d.settlement.clock.total_hours, 1)
	d.free()


func test_driver_pause_toggle() -> void:
	var d := SimDriver.new()
	d.settlement = Settlement.new_game(1, reg)
	d.set_speed(2)
	d.toggle_pause()
	assert_eq(d.speed, 0)
	d.toggle_pause()
	assert_eq(d.speed, 2)
	d.free()


func test_determinism() -> void:
	var a := Settlement.new_game(4242, reg)
	var b := Settlement.new_game(4242, reg)
	a.step_days(50)
	b.step_days(50)
	assert_eq(a.clock.total_hours, b.clock.total_hours)
	assert_eq(a.map.terrain, b.map.terrain)
	assert_eq(a.map.blight, b.map.blight)
	assert_eq(a.map.fertility, b.map.fertility)
	assert_eq(a.map.wet, b.map.wet)
	assert_eq(a.map.river_flow, b.map.river_flow)
	assert_eq(a.events.log.size(), b.events.log.size())
