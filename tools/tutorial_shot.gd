extends SceneTree
## Windowed tutorial screenshots: godot --path . -s tools/tutorial_shot.gd
## Writes /tmp/hv_tutorial.png (a tutorial game at goal 4, the Forager, with its Food category pulsing) and
## /tmp/hv_tutorial_done.png (the closing card).

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.settings_path = "/tmp/hv_tutorial_settings.cfg"
	main.start_new_game(-1, false, true)
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var tut: TutorialSystem = s.get_system(TutorialSystem)
	s.report_camera_moved()
	var h := s.map.hearth_spot
	var start := h + Vector2i(s.hearth.def.size.x, 0)
	for i in 8:
		s.place_road(start + Vector2i(i, 0))
	var placed := 0
	for dy in [-2, 1]:
		for dx in range(1, 12):
			if placed < 2 and s.can_place("tent", start + Vector2i(dx, dy))["ok"]:
				s.complete_site(s.buildings[s.place_building("tent", start + Vector2i(dx, dy))])
				placed += 1
	print("goal: ", tut.current_goal().id if tut.current_goal() != null else "none")
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(start) + Vector2(4, 0)) * ArtLibrary.TILE
	hud.set_process(false)  # _process would re-pulse from the clock; the shot sets the phase
	hud.refresh()
	hud.update_highlight(0.26)
	await _shoot("/tmp/hv_tutorial.png")
	s.events.emit("tutorial_finished", {"skipped": false})
	await _shoot("/tmp/hv_tutorial_done.png")
	quit()
