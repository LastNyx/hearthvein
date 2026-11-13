extends SceneTree
## Windowed frame-rate check with 600 walkers: godot --path . -s tools/perf_shot.gd
## Runs the real main scene at 1x on the commute hours for ~20 s at zoom 1.0 and ~20 s at the farthest zoom
## (walkers hidden there, D46) and prints average and minimum FPS. Vsync is off so headroom shows.

const SECONDS := 20.0
const WARMUP_FRAMES := 30


func _run(main: Node, cam: CameraController, step: int, start_hour: int, label: String) -> void:
	var s: Settlement = main.settlement
	var guard := 0
	while s.clock.hour() != start_hour and guard < 48:
		s.step_hours(1)
		guard += 1
	cam.set_zoom_step(step)
	var t := 0.0
	var frames := 0
	var worst := 0.0
	var sum := 0.0
	var walking := 0
	var calls_sum := 0.0
	var calls_max := 0.0
	var last := Time.get_ticks_usec()
	while t < SECONDS:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		frames += 1
		if frames <= WARMUP_FRAMES:
			continue
		t += dt
		sum += dt
		worst = maxf(worst, dt)
		var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		calls_sum += calls
		calls_max = maxf(calls_max, calls)
		walking = 0
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	for w: Walker in ws.walkers.values():
		if w.is_walking():
			walking += 1
	var n := frames - WARMUP_FRAMES
	print("%s: zoom %.2f, avg %.1f FPS (%.2f ms), min %.1f FPS (worst frame %.1f ms), %d frames, walking now %d of %d, clock %s" % [
		label, CameraController.ZOOM_STEPS[step], n / sum, sum / n * 1000.0, 1.0 / worst, worst * 1000.0, n, walking,
		ws.walkers.size(), s.clock.label()])
	print("%s: draw calls per frame avg %.0f, max %.0f (Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)" % [label, calls_sum / n, calls_max])


func _init() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	PerfFixture.populate(s, 600)
	var driver: SimDriver = null
	for c in main.get_children():
		if c is SimDriver:
			driver = c
	driver.set_speed(1)
	var cam: CameraController = main.get_node("Camera")
	var hs := s.map.hearth_spot
	cam.position = Vector2(hs) * float(ArtLibrary.TILE)
	print("fixture: %d citizens, %d buildings, window %s" % [s.citizens.size(), s.buildings.size(), root.size])
	await _run(main, cam, 2, 5, "zoom 1")
	await _run(main, cam, 0, 17, "farthest zoom")
	quit()
