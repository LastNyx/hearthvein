extends SceneTree
## Windowed HUD screenshots: godot --path . -s tools/hud_shot.gd
## Writes /tmp/hv_hud.png (building selected) and /tmp/hv_hud_overlay.png (blight + road overlays on).

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
	var m: HudModel = main.hud_model
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.place_building_instant("cottage", Vector2i(h.x + 7, h.y - 2))
	s.place_building_instant("storehouse", Vector2i(h.x + 10, h.y + 1))
	var wc := s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y + 6))  # no road: red overlay and icon
	for t in [Vector2i(h.x + 8, h.y + 5), Vector2i(h.x + 9, h.y + 5), Vector2i(h.x + 8, h.y + 6), Vector2i(h.x + 9, h.y + 6),
			Vector2i(h.x + 10, h.y + 5)]:
		s.set_blighted(t, true)
	s.place_building("storehouse", Vector2i(h.x + 12, h.y - 3))
	s.hearth.inventory.add("food", 300.0)
	for i in 17 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(7, 1)) * ArtLibrary.TILE
	m.select(wc)
	(main.get_node("Hud") as Hud).open_category("housing")
	await _shoot("/tmp/hv_hud.png")
	m.toggle_overlay("blight")
	m.toggle_overlay("roads")
	await _shoot("/tmp/hv_hud_overlay.png")
	print(s.clock.label(), " notices: ", m.notifications.items.map(func(i: Dictionary) -> String: return i["text"]))
	quit()
