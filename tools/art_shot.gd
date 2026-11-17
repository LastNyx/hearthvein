extends SceneTree
## Windowed screenshots of the exported art in game: godot --path . -s tools/art_shot.gd
## Writes /tmp/hv_art_z1.png (zoom 1) and /tmp/hv_art_z2.png (zoom 2) around the Hearth.
## Optional seed: godot --path . -s tools/art_shot.gd -- 42

func _find_spot(s: Settlement, id: String, skip: int = 0) -> Vector2i:
	var h := s.map.hearth_spot
	var seen := 0
	for r in range(2, 16):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				var t := Vector2i(x, y)
				if s.can_place(id, t)["ok"]:
					if seen == skip:
						return t
					seen += 1
	return Vector2i(-1, -1)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 10):
		s.place_road(Vector2i(x, h.y))
	for x in range(h.x - 4, h.x):
		s.place_road(Vector2i(x, h.y))
	for y in range(h.y + 1, h.y + 6):
		s.place_road(Vector2i(h.x + 4, y))
	s.place_building_instant("storehouse", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("tent", Vector2i(h.x + 3, h.y - 1))
	s.place_building_instant("tent", Vector2i(h.x + 6, h.y - 1))
	s.place_building_instant("tent", Vector2i(h.x - 3, h.y + 1))
	s.place_building_instant("tent", Vector2i(h.x - 2, h.y - 1))
	var tap := _find_spot(s, "lumen_tap")
	if tap.x >= 0:
		s.place_building_instant("lumen_tap", tap)
	var wc := _find_spot(s, "woodcutter")
	if wc.x >= 0:
		s.place_building_instant("woodcutter", wc)
	var f := _find_spot(s, "forager", 3)
	if f.x >= 0:
		s.place_building_instant("forager", f)
	var cam: CameraController = main.get_node("Camera")
	for pair in [[2, "/tmp/hv_art_z1.png"], [3, "/tmp/hv_art_z2.png"]]:
		cam.set_zoom_step(pair[0])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(pair[1])
	quit()
