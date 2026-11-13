extends SceneTree
## Windowed overview shots for the polish pass: godot --path . -s tools/polish_shot.gd [-- seed]
## Hearth, roads, walkers mid-commute, a blighted patch, water (river/lake) and a construction site.
## Writes /tmp/hv_polish_z1.png and /tmp/hv_polish_z2.png.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x - 6, h.x + 12):
		for y in range(h.y - 3, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	for y in range(h.y + 1, h.y + 7):
		s.place_road(Vector2i(h.x + 4, y))
	for t in [Vector2i(h.x + 3, h.y - 2), Vector2i(h.x - 4, h.y + 1), Vector2i(h.x - 2, h.y - 2), Vector2i(h.x + 7, h.y - 2)]:
		s.place_building_instant("tent", t)
	s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("storehouse", Vector2i(h.x + 8, h.y + 1))
	for i in 5:
		s.add_citizen()
	# blighted patch south-east, beside the road
	for dy in range(2, 6):
		for dx in range(7, 12):
			if (dx * 3 + dy * 5) % 7 != 0 and s.map.terrain_id_at(h.x + dx, h.y + dy) != "water":
				s.set_blighted(Vector2i(h.x + dx, h.y + dy), true)
	s.place_building("storehouse", Vector2i(h.x - 8, h.y - 2))  # construction site
	for x in range(h.x - 10, h.x - 5):
		s.place_road(Vector2i(x, h.y))
	var guard := 0
	while guard < 60:
		s.step_seconds(1.0)
		guard += 1
	s.step_hours(6)
	s.step_seconds(0.8)
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(h) + Vector2(2, 3)) * ArtLibrary.TILE
	for pair in [[2, "/tmp/hv_polish_z1.png"], [3, "/tmp/hv_polish_z2.png"]]:
		cam.set_zoom_step(pair[0])
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(pair[1])
	quit()
