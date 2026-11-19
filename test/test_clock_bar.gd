extends GutTest
## Ticket 113: the clock bar "Day 3, 06:40" and the sun/moon dial of the era panel. The sim clock has whole hours only;
## the minutes and the dial position interpolate the fraction already simulated inside the hour (render-side).

var reg: DataRegistry
var d: DayNightDef


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	d = reg.day_night


# AC1: the clock bar reads "Day 3, 06:40" (day from the clock, minutes from the fraction inside the hour).
func test_clock_bar_text_has_day_and_minutes() -> void:
	assert_eq(HudModel.clock_bar_text(3, 6.0), "Day 3, 06:00")
	assert_eq(HudModel.clock_bar_text(3, 6.0 + 40.0 / 60.0), "Day 3, 06:40")
	assert_eq(HudModel.clock_bar_text(4, 0.0), "Day 4, 00:00")
	assert_eq(HudModel.clock_bar_text(4, 23.5), "Day 4, 23:30")


# AC1: the last minute shown is 59; a full turn of the day wraps to midnight.
func test_clock_bar_text_clamps_the_last_minute() -> void:
	assert_eq(HudModel.clock_bar_text(3, 6.9999), "Day 3, 06:59")
	assert_eq(HudModel.clock_bar_text(3, 24.0), "Day 3, 00:00")


# AC2: the driver's status text is the clock bar, fed by the sim clock plus the hour fraction; speed reads separately.
func test_status_text_reads_the_clock_and_the_hour_fraction() -> void:
	var s := Settlement.new_game(42, reg)
	var drv := SimDriver.new()
	drv.settlement = s
	assert_eq(drv.status_text(), "Day 1, 00:00")
	s.step_seconds(GameClock.REAL_SECONDS_PER_HOUR * 0.5)
	assert_eq(drv.status_text(), "Day 1, 00:30")
	assert_eq(drv.speed_text(), "1x")
	drv.set_speed(0)
	assert_eq(drv.speed_text(), "paused")
	drv.set_speed(3)
	assert_eq(drv.speed_text(), "3x")
	drv.free()


# AC3: the sun is up dawn 05 to night 21 and the moon the rest, each halfway across its arc at the middle hour.
func test_dial_night_window_and_arc_progress() -> void:
	assert_true(ClockDial.is_night(22.0, d))
	assert_true(ClockDial.is_night(2.0, d))
	assert_false(ClockDial.is_night(8.0, d))
	assert_false(ClockDial.is_night(12.0, d))
	assert_almost_eq(ClockDial.arc_progress(13.0, d), 0.5, 0.0001, "13:00 is the middle of the sun's 05-21 arc")
	assert_almost_eq(ClockDial.arc_progress(1.0, d), 0.5, 0.0001, "01:00 is the middle of the moon's 21-05 arc")


# AC3: the body sits left at rise, right at set and highest in the middle.
func test_dial_arc_rises_and_sets() -> void:
	var box := Vector2(56, 36)
	var rise := ClockDial.arc_pos(0.0, box)
	var noon := ClockDial.arc_pos(0.5, box)
	var set := ClockDial.arc_pos(1.0, box)
	assert_almost_eq(rise.x, 5.0, 0.001)
	assert_almost_eq(set.x, 51.0, 0.001)
	assert_almost_eq(noon.x, 28.0, 0.001)
	assert_lt(noon.y, rise.y, "the middle of the arc is higher than the rise")
	assert_almost_eq(rise.y, set.y, 0.001, "rise and set both sit on the horizon")


# AC4: the dial sky is dark at night, blue by day and warm through dusk.
func test_dial_sky_is_dark_at_night_and_warm_at_dusk() -> void:
	var day := ClockDial.sky_color(12.0, d)
	var night := ClockDial.sky_color(0.0, d)
	var dusk := ClockDial.sky_color(20.0, d)
	assert_lt(night.v, day.v, "night is darker than noon")
	assert_gt(dusk.r, dusk.b, "dusk is warm")
