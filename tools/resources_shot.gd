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
	# A strip cleared for the road, woodcutters north of it with forest planted in their range, a forager, a
	# storehouse and cottages: wood and food are really made.
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var wc_def := s.registry.get_building("woodcutter")
	var grove: Array[Vector2i] = []
	for dx in [4, 9]:
		for dy in [-6, -5, -4, -3]:
			for ox in range(-3, 4):
				grove.append(Vector2i(h.x + dx + ox, h.y + dy))
		s.place_building_instant("woodcutter", Vector2i(h.x + dx, h.y - wc_def.size.y))
	s.place_building_instant("forager", Vector2i(h.x + 7, h.y + 1))
	for dx in [12, 15, 18]:  # room to store ten days of wood (a full storage halts the woodcutters)
		s.place_building_instant("storehouse", Vector2i(h.x + dx, h.y + 1))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y + 1))
	s.hearth.inventory.add("food", 600.0)
	for i in 10 * 24:
		s.step_hours(1)
		if i % 24 == 12:  # a Forester stands in: the grove grows back every day, so the woodcutters never run dry
			for g in grove:
				s.set_terrain(g, "forest")
	print("wood made yesterday: ", (s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem).yesterday("wood"))
	var hud: Hud = main.get_node("Hud")
	hud.resources_page.open_for("wood")
	for i in 6:
		await process_frame
	hud.resources_page.show_breakdown("wood")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_114_resources.png")
	quit()
