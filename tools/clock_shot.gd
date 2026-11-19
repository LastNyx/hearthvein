extends SceneTree
## Windowed clock bar screenshots (ticket 113, the approved variant A): godot --path . -s tools/clock_shot.gd
## Shoots the era panel's dial and date line at 06:40, 12:00, 18:30, 21:00 and 02:00 of day 3 to
## /tmp/hv_113_<hhmm>.png. Parse-check only in the sandbox; the planner takes it.

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	main.driver.set_speed(0)
	var day := 2 * 24
	for t in [[6, 40], [12, 0], [18, 30], [21, 0], [2, 0]]:
		s.clock.total_hours = day + int(t[0])
		s._hour_acc = GameClock.REAL_SECONDS_PER_HOUR * float(t[1]) / 60.0
		main.hud.refresh()
		await _shoot("/tmp/hv_113_%02d%02d.png" % [t[0], t[1]])
	quit()
