extends SceneTree
## Windowed screenshot of the 1.1.6 icon set in use (ticket 112): the top bar with every good's icon and value/delta,
## and a construction site's wait line, which draws each missing good's icon before its numbers.
## godot --path . -s tools/icon_shot.gd  ->  /tmp/hv_112_icons.png

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
	var hud: Hud = main.get_node("Hud")
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	# some stock in every good, so the bar shows all nine goods plus people next to their icons
	for g in ["food", "wood", "stone", "planks", "cut_stone", "tools", "lumen", "lumen_cells"]:
		s.hearth.inventory.add(g, 12.0)
	s.gold = 51.0
	var site := s.place_building("storehouse", Vector2i(h.x + 5, h.y - 1))
	var b: Building = s.buildings[site]
	for g in b.effective_cost():
		if g != BuildingDef.GOLD:
			b.input_buffer.add(g, 1.0)  # short of the rest: the wait line names every good still missing
	m.select(site)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(5, 0)) * ArtLibrary.TILE
	hud.refresh()
	print("icon shot wait line: ", m.wait_text(b))
	await _shoot("/tmp/hv_112_icons.png")
	quit()
