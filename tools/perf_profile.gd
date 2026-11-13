extends SceneTree
## Per-system cost of one in-game day for the 600-citizen fixture: godot --headless --path . -s tools/perf_profile.gd
## Mirrors Settlement.step_seconds (same hooks, timed per system) in 0.1 s frames, as the real game feeds them.

func _init() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var t0 := Time.get_ticks_usec()
	var s := PerfFixture.build(reg, 42, 600)
	print("fixture build %.2f s, buildings %d citizens %d" % [(Time.get_ticks_usec() - t0) / 1e6, s.buildings.size(), s.citizens.size()])
	var jobs := 0
	for c: Citizen in s.citizens.values():
		if c.job_id >= 0:
			jobs += 1
	print("citizens with job %d, homeless %d" % [jobs, s.homeless_count()])
	s.step_hours(5)  # up to 05:00 (clock starts at 0 or day start)
	var cost := {}
	var t1 := Time.get_ticks_usec()
	var frames := 0
	var total_secs := GameClock.REAL_SECONDS_PER_HOUR * GameClock.HOURS_PER_DAY
	var done := 0.0
	var step := 0.1
	while done < total_secs - 0.0001:
		s.step_seconds(step)  # wall total
		done += step
		frames += 1
	var wall := (Time.get_ticks_usec() - t1) / 1e6
	print("one day by step_seconds(0.1): %.3f s (%d calls)" % [wall, frames])
	# Per-system timing: wrap each system's hooks.
	var s2 := PerfFixture.build(reg, 42, 600)
	s2.step_hours(5)
	var timers := {}
	for sys in s2.systems:
		timers[sys.get_script().get_global_name()] = {"sec": 0, "hour": 0, "day": 0}
	var acc := 0.0
	done = 0.0
	var hour_len := GameClock.REAL_SECONDS_PER_HOUR
	while done < total_secs - 0.0001:
		for sys in s2.systems:
			var a := Time.get_ticks_usec()
			sys.on_seconds(s2, step)
			timers[sys.get_script().get_global_name()]["sec"] += Time.get_ticks_usec() - a
		done += step
		acc += step
		if acc >= hour_len - 0.000001:
			acc = 0.0
			s2.clock.total_hours += 1
			s2.events.now_hours = s2.clock.total_hours
			for sys in s2.systems:
				var a := Time.get_ticks_usec()
				sys.on_hour(s2)
				timers[sys.get_script().get_global_name()]["hour"] += Time.get_ticks_usec() - a
			if s2.clock.is_day_start():
				for sys in s2.systems:
					var a := Time.get_ticks_usec()
					sys.on_day(s2)
					timers[sys.get_script().get_global_name()]["day"] += Time.get_ticks_usec() - a
	var rows: Array = []
	for n in timers:
		var t: Dictionary = timers[n]
		rows.append([t["sec"] + t["hour"] + t["day"], n, t])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		print("%-20s total %8.1f ms  (seconds %7.1f, hour %7.1f, day %7.1f)" % [r[1], r[0] / 1000.0, r[2]["sec"] / 1000.0, r[2]["hour"] / 1000.0, r[2]["day"] / 1000.0])
	var a := Time.get_ticks_usec()
	JobSystem.refresh(s2)
	print("JobSystem.refresh once: %.2f ms" % ((Time.get_ticks_usec() - a) / 1000.0))
	var ws := s2.get_system(WalkerSystem) as WalkerSystem
	print("A* runs this day: %d" % ws.path_computations)
	quit()
