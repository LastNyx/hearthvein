extends SceneTree
## Windowed Resources page screenshot (ticket 114): godot --path . -s tools/resources_shot.gd
## Writes /tmp/hv_114_resources.png: a small town run for ~10 days so the chart has data, wood selected, the made
## breakdown of wood showing, the page open (E).

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
	s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("woodcutter", Vector2i(h.x + 13, h.y + 1))
	s.place_building_instant("forager", Vector2i(h.x + 8, h.y + 4))
	s.place_building_instant("quarry", Vector2i(h.x + 15, h.y + 4))
	s.hearth.inventory.add("food", 300.0)
	for i in 10 * 24:
		s.step_hours(1)
	var hud: Hud = main.get_node("Hud")
	hud.resources_page.open_for("wood")
	for i in 6:
		await process_frame
	hud.resources_page.show_breakdown("wood")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_114_resources.png")
	quit()
