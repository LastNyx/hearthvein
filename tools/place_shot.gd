extends SceneTree
## Windowed screenshot of placed buildings: godot --path . -s tools/place_shot.gd  -> /tmp/hv_place.png

func _find_spot(s: Settlement, id: String, skip: int = 0) -> Vector2i:
	var h := s.map.hearth_spot
	var seen := 0
	for r in range(2, 14):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				var t := Vector2i(x, y)
				if s.can_place(id, t)["ok"]:
					if seen == skip:
						return t
					seen += 1
	return Vector2i(-1, -1)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	# A road east of the hearth with buildings along it, one building left disconnected.
	for x in range(h.x + 2, h.x + 9):
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("storehouse", Vector2i(h.x + 3, h.y + 1))
	s.place_building_instant("tent", Vector2i(h.x + 6, h.y + 1))
	s.place_building_instant("tent", Vector2i(h.x + 3, h.y - 1))
	for x in range(h.x - 3, h.x):
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("tent", Vector2i(h.x - 2, h.y + 1))
	var tap := _find_spot(s, "lumen_tap")
	if tap.x >= 0:
		s.place_building_instant("lumen_tap", tap)
	var f := _find_spot(s, "forager", 3)
	s.place_building_instant("forager", f)
	s.place_building_instant("tent", Vector2i(h.x - 3, h.y + 3))  # disconnected
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_place.png")
	quit()
