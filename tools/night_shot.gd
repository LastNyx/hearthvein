extends SceneTree
## Windowed day and night screenshots (ticket 107): godot --path . -s tools/night_shot.gd
## Shoots the hud_shot-like village at 12:00, 20:00, 00:00 and 06:00 of day 2 to /tmp/hv_107_12.png,
## /tmp/hv_107_20.png, /tmp/hv_107_0.png and /tmp/hv_107_6.png. Parse-check only in the sandbox; the planner takes it.

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
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.place_building_instant("cottage", Vector2i(h.x + 7, h.y - 2))
	s.place_building_instant("storehouse", Vector2i(h.x + 10, h.y + 1))
	s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y + 6))
	s.hearth.inventory.add("food", 300.0)
	for i in 17 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(7, 1)) * ArtLibrary.TILE
	main.driver.set_speed(0)
	var day := 2 * 24
	for hour in [12, 20, 0, 6]:
		s.clock.total_hours = day + hour
		main._update_tint()
		await _shoot("/tmp/hv_107_%d.png" % hour)
	quit()
