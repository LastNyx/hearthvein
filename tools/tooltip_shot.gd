extends SceneTree
## Windowed tooltip screenshots: godot --path . -s tools/tooltip_shot.gd
## Writes /tmp/hv_tooltip_bar.png (hovering the Forager build button) and /tmp/hv_tooltip_map.png (hovering a placed Woodcutter).

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
	var hud: Hud = main.get_node("Hud")
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	var wc_tile := Vector2i(h.x + 5, h.y + 1)
	s.place_building_instant("woodcutter", wc_tile)
	for i in 3 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(5, 1)) * ArtLibrary.TILE
	hud.open_category("food")
	for i in 3:
		await process_frame
	var b := hud.build_button("forager")
	b.mouse_entered.emit()
	hud.hover_tick(1.0)
	await _shoot("/tmp/hv_tooltip_bar.png")
	b.mouse_exited.emit()
	hud.open_category("food")
	hud.set_process(false)  # _process re-ticks hover from the real (absent) mouse and would hide the map tip
	hud.hover_tick(0.0)
	hud.hover_tick(1.0, wc_tile)
	await process_frame  # wrapped labels size after one layout pass; the game re-places the tip every frame
	hud.hover_tick(0.0, wc_tile)
	await _shoot("/tmp/hv_tooltip_map.png")
	print("tooltip: ", hud.tooltip_text())
	quit()
