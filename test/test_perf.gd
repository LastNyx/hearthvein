extends GutTest
## Ticket 18: 600 citizens stay cheap (design.md section 21, D46).

const SEED := 42

var s: Settlement


func before_all() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	s = PerfFixture.build(reg, SEED, 600)


func test_fixture_has_600_housed_working_citizens() -> void:
	assert_eq(s.citizens.size(), 600)
	assert_eq(s.homeless_count(), 0)
	assert_eq(s.idle_citizens().size(), 0, "every citizen has a job")


func test_one_day_of_600_citizens_under_two_seconds() -> void:
	s.step_hours(5)  # up to 05:00 so the day below holds both commutes
	var t0 := Time.get_ticks_usec()
	s.step_hours(GameClock.HOURS_PER_DAY)
	var sec := (Time.get_ticks_usec() - t0) / 1e6
	print("PERF one in-game day, 600 citizens, step_hours(24): %.3f s" % sec)
	assert_lt(sec, 2.0, "one in-game day of 600 citizens steps in under 2 s")


func test_frame_sized_steps_stay_cheap_over_the_morning_commute() -> void:
	var guard := 0
	while s.clock.hour() != 5 and guard < 48:
		s.step_hours(1)
		guard += 1
	var frames := 150  # one game hour at 1x in 1/60 s frames
	var t0 := Time.get_ticks_usec()
	for i in frames:
		s.step_seconds(GameClock.REAL_SECONDS_PER_HOUR / frames)
	s.step_hours(1)
	var per_call_ms := (Time.get_ticks_usec() - t0) / 1000.0 / (frames + 1)
	print("PERF commute hour 05-07, %d frame steps: %.2f ms per step_seconds call" % [frames + 1, per_call_ms])
	assert_lt(per_call_ms, 12.0, "a sim step must fit well inside a 16 ms frame")


func test_walkers_hidden_only_at_the_farthest_zoom() -> void:
	assert_false(WalkerView.shown_at_zoom(CameraController.ZOOM_STEPS[0]), "farthest step hides walkers")
	for i in range(1, CameraController.ZOOM_STEPS.size()):
		assert_true(WalkerView.shown_at_zoom(CameraController.ZOOM_STEPS[i]), "step %d shows walkers" % i)
	assert_true(CameraController.is_farthest_zoom(CameraController.ZOOM_STEPS[0]))
	assert_false(CameraController.is_farthest_zoom(CameraController.ZOOM_STEPS[1]))
