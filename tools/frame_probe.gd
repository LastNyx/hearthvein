extends SceneTree
## Frame-time probe for the sim (ticket 89): godot --headless --path . -s tools/frame_probe.gd [-- seed [days]]
## Builds the Conflux and Skyborne shot layouts (tools/shot_layout.gd) through Main and the 600-citizen perf fixture, then feeds Settlement.step_seconds
## 60 fps frames (delta * speed, as SimDriver does) at 1x, 2x and 3x for `days` game days each (default 2) and prints
## per-frame sim ms (mean, p99, worst, frames over 4 ms), the slowest frames and how much of them were hour/day ends.
## Then it prints the cost per system of the hour-end hooks (on_hour, on_day), timed one by one the way the sim runs them.
## The machine is shared: the load average is printed with every block, judge numbers with it in mind.
## Ticket 90 (water/smoke shaders) reuses this: add the effect, run the probe, compare worst/p99 at the Conflux layout.

const L := preload("res://tools/shot_layout.gd")
const FPS := 60.0
const BUDGET_MS := 4.0


func _load() -> String:
	var out := []
	OS.execute("cat", ["/proc/loadavg"], out)
	return (out[0] as String).get_slice(" ", 0) if out.size() > 0 else "?"


func _build(main: Node, era: String) -> Settlement:
	main.start_new_game()
	main.driver.set_speed(0)  # this script feeds the sim itself
	var s: Settlement = main.settlement
	s.era_current = era
	(main.get_node("Hud") as Hud)._rebuild_categories()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("materials", 900.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("food", 900.0)
	if era == "skyborne":
		s.hearth.inventory.add("lumen", 600.0)
		L.sky(s)
	else:
		L.conflux(s)
	s.step_hours(3 * 24)
	return s


## The newest logged events that are not walker arrivals, to guess what rebuilt the layout.
func _last_event(s: Settlement) -> String:
	var kinds: Array = []
	var i := s.events.log.size() - 1
	while i >= 0 and kinds.size() < 3:
		var k := str(s.events.log[i].get("kind", "?"))
		if k != "walker_arrived":
			kinds.append(k)
		i -= 1
	return ", ".join(kinds)


func _pct(sorted: Array, p: float) -> float:
	return sorted[mini(int(ceil(p * sorted.size())) - 1, sorted.size() - 1)]


func _frames(s: Settlement, speed: int, days: int, label: String) -> void:
	var frames := int(days * GameClock.REAL_SECONDS_PER_DAY * FPS / speed)
	var step := speed / FPS
	var ms: Array = []
	var shown := 0
	var window := 0  # frames left in the 90 frames that follow a season start
	var seasons := 0
	var was_ss := false
	var season_worst := 0.0
	s.flush_deferred()
	for i in frames:
		var h0 := s.clock.total_hours
		var sv0 := s.structure_version
		var t0 := Time.get_ticks_usec()
		s.step_seconds(step)
		var d := (Time.get_ticks_usec() - t0) / 1000.0
		ms.append(d)
		var ss := s.clock.is_season_start()
		if ss and not was_ss:
			window = 90
			seasons += 1
		was_ss = ss
		if window > 0:
			window -= 1
			season_worst = maxf(season_worst, d)
		if d > BUDGET_MS:
			shown += 1
		if d > BUDGET_MS and shown <= 6:  # the first few, so a heavy layout does not flood the output
			print("PROBE   slow frame %d: %.2f ms, game hour %d (day hour %d)%s" % [i, d, s.clock.total_hours, s.clock.hour(),
					(", an hour ended" if s.clock.total_hours != h0 else "") + (", structure changed (%s)" % _last_event(s) if s.structure_version != sv0 else "")])
	var sum := 0.0
	var over := 0
	for v: float in ms:
		sum += v
		over += 1 if v > BUDGET_MS else 0
	ms.sort()
	if seasons > 0:
		print("PROBE %-8s %dx  season start: worst frame %.3f ms in the 90 frames after it (%d season start(s))" % [label, speed, season_worst, seasons])
	print("PROBE %-8s %dx  frames %5d  mean %6.3f ms  p99 %6.3f ms  worst %6.3f ms  over %.0f ms: %d  (load %s)" % [
			label, speed, frames, sum / frames, _pct(ms, 0.99), ms[ms.size() - 1], BUDGET_MS, over, _load()])


## Per-system cost of on_seconds per frame (ticket 89b): the step_seconds chunk loop replicated with each system timed.
## Hour ends are flushed untimed, so this is the pure every-frame cost. Prints mean, p99 and worst ms per system.
func _per_system(s: Settlement, speed: int, days: int, label: String) -> void:
	var frames := int(days * GameClock.REAL_SECONDS_PER_DAY * FPS / speed)
	var step := speed / FPS
	s.flush_deferred()
	var per := {}
	var total: Array = []
	for i in frames:
		var left := step
		var frame_us := 0
		while left > 0.0:
			var chunk := minf(left, GameClock.REAL_SECONDS_PER_HOUR - s._hour_acc)
			for sys in s.systems:
				var a := Time.get_ticks_usec()
				sys.on_seconds(s, chunk)
				var d := Time.get_ticks_usec() - a
				frame_us += d
				var n: String = sys.get_script().get_global_name()
				if not per.has(n):
					per[n] = []
				var arr: Array = per[n]
				if arr.size() <= i:
					arr.resize(i + 1)
					arr[i] = 0
				arr[i] += d
			left -= chunk
			s._hour_acc += chunk
			if s._hour_acc >= GameClock.REAL_SECONDS_PER_HOUR - 0.000001:
				s._hour_acc = 0.0
				s._frame_step = true
				s._advance_hour()
				s.flush_deferred()
		total.append(frame_us / 1000.0)
	var rows: Array = []
	for n in per:
		var arr: Array = per[n]
		var sum := 0.0
		for v in arr:
			sum += v
		var sorted: Array = arr.map(func(v: int) -> float: return v / 1000.0)
		sorted.sort()
		rows.append([sum / frames / 1000.0, n, _pct(sorted, 0.99), sorted[sorted.size() - 1]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var tsum := 0.0
	for v: float in total:
		tsum += v
	total.sort()
	print("PROBE %s %dx on_seconds per frame: all systems mean %.3f p99 %.3f worst %.3f ms (load %s)" % [
			label, speed, tsum / frames, _pct(total, 0.99), total[total.size() - 1], _load()])
	for r in rows.slice(0, 7):
		print("PROBE   %-24s mean %6.3f ms  p99 %6.3f  worst %6.3f" % [r[1], r[0], r[2], r[3]])


## Per-system cost of the hour-end hooks over `hours` hours, each system timed alone (the order the sim runs them).
func _hour_end(s: Settlement, label: String, hours: int) -> void:
	s.flush_deferred()
	s.step_hours(1)
	var cost := {}
	var worst := {}
	var total_hour := 0.0
	var worst_hour := 0.0
	for i in hours:
		var rest := GameClock.REAL_SECONDS_PER_HOUR
		for sys in s.systems:
			sys.on_seconds(s, rest)
		s.clock.total_hours += 1
		s.events.now_hours = s.clock.total_hours
		var hour_us := 0
		for sys in s.systems:
			var n: String = sys.get_script().get_global_name()
			var a := Time.get_ticks_usec()
			sys.on_hour(s)
			var d := Time.get_ticks_usec() - a
			hour_us += d
			cost[n] = cost.get(n, 0) + d
			worst[n] = maxi(worst.get(n, 0), d)
		total_hour += hour_us
		worst_hour = maxf(worst_hour, hour_us)
		if s.clock.is_day_start():
			s.events.emit("day_started", {"day": s.clock.day(), "season": s.clock.season_name(), "year": s.clock.year()})
			for sys in s.systems:
				var a := Time.get_ticks_usec()
				sys.on_day(s)
				var d := Time.get_ticks_usec() - a
				var n: String = sys.get_script().get_global_name() + " (day)"
				cost[n] = cost.get(n, 0) + d
				worst[n] = maxi(worst.get(n, 0), d)
			if s.clock.is_season_start():
				var e0 := Time.get_ticks_usec()
				s.events.emit("season_started", {"season": s.clock.season_name(), "year": s.clock.year()})
				cost["season_started listeners"] = cost.get("season_started listeners", 0) + Time.get_ticks_usec() - e0
				worst["season_started listeners"] = Time.get_ticks_usec() - e0
				for sys in s.systems:
					var a := Time.get_ticks_usec()
					sys.on_season(s)
					var d := Time.get_ticks_usec() - a
					var n: String = sys.get_script().get_global_name() + " (season)"
					cost[n] = cost.get(n, 0) + d
					worst[n] = maxi(worst.get(n, 0), d)
	print("PROBE %s hour end over %d hours: all on_hour hooks mean %.3f ms, worst %.3f ms (load %s)" % [
			label, hours, total_hour / hours / 1000.0, worst_hour / 1000.0, _load()])
	var rows: Array = []
	for n in cost:
		rows.append([cost[n], n])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r in rows.slice(0, 10):
		print("PROBE   %-28s mean %7.3f ms  worst %7.3f ms" % [r[1], r[0] / hours / 1000.0, worst[r[1]] / 1000.0])


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_arg := int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 42
	var days := int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 2
	var only := args[2] if args.size() > 2 else ""  # optional: run one layout (conflux, skyborne or town600)
	for era in ["conflux", "skyborne", "town600"]:
		if only != "" and only != era:
			continue
		var main: Node = null
		var s: Settlement
		if era == "town600":  # the 600-citizen fixture of test_perf, no scene: a heavy sim without the render listeners
			var reg := DataRegistry.new()
			reg.load_all()
			s = PerfFixture.build(reg, seed_arg, 600)
			s.step_hours(3 * 24)
		else:
			main = load("res://ui/main.tscn").instantiate()
			main.game_seed = seed_arg
			root.add_child(main)
			await process_frame
			s = _build(main, era)
		print("PROBE %s: %d buildings, %d citizens, %d walkers" % [era, s.buildings.size(), s.citizens.size(),
				(s.get_system(WalkerSystem) as WalkerSystem).walkers.size()])
		for speed in [1, 2, 3]:
			_frames(s, speed, days, era)
		if era == "town600" or only != "":  # asked for one layout: its per-system frame cost too
			_per_system(s, 3 if era != "town600" else 1, days, era)
		_hour_end(s, era, 200)
		if main != null:
			main.queue_free()
			await process_frame
	quit()
