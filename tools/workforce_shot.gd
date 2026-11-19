extends SceneTree
## Windowed Workforce page screenshot (ticket 115): godot --path . -s tools/workforce_shot.gd
## Writes /tmp/hv_115_workforce.png: a small town with sites, a paused building and the page open (Q).

func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 4, h.y + 6):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.place_building_instant("cottage", Vector2i(h.x + 7, h.y - 2))
	s.place_building_instant("storehouse", Vector2i(h.x + 10, h.y + 1))
	var wc := s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("woodcutter", Vector2i(h.x + 13, h.y + 1))
	s.place_building("storehouse", Vector2i(h.x + 16, h.y - 3))  # a construction site
	s.place_building("forager", Vector2i(h.x + 8, h.y + 4))
	s.place_building_instant("fishing_dock", Vector2i(h.x + 12, h.y + 4))  # food, may stay short of workers
	var q := s.place_building_instant("quarry", Vector2i(h.x + 15, h.y + 4))
	s.place_building_instant("well", Vector2i(h.x + 18, h.y - 3))
	s.hearth.inventory.add("food", 300.0)
	for i in 5 * 24:
		s.step_hours(1)
	s.set_building_priority(wc, "paused")
	if q >= 0:
		s.set_building_priority(q, "paused")
	var hud: Hud = main.get_node("Hud")
	hud.workforce_page.open()
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_115_workforce.png")
	quit()
