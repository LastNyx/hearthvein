extends SceneTree
## Windowed screenshot of walkers in game: godot --path . -s tools/walker_shot.gd
## Builds a small camp, lets the day run to the morning commute and writes /tmp/hv_walkers_z1.png and _z2.png.

func _free_spot(s: Settlement, id: String, skip: int = 0) -> Vector2i:
	var h := s.map.hearth_spot
	var seen := 0
	for r in range(2, 16):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place(id, Vector2i(x, y))["ok"]:
					if seen == skip:
						return Vector2i(x, y)
					seen += 1
	return Vector2i(-1, -1)


## Places a building anywhere near the Hearth where it touches the road network (so it gets workers).
func _place_connected(s: Settlement, id: String) -> void:
	var h := s.map.hearth_spot
	for r in range(2, 20):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				var bid := s.place_building(id, Vector2i(x, y))
				if bid >= 0:
					if s.buildings[bid].connected:
						return
					s.demolish(bid)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 12):
		s.place_road(Vector2i(x, h.y))
	for x in range(h.x - 5, h.x):
		s.place_road(Vector2i(x, h.y))
	for y in range(h.y + 1, h.y + 6):
		s.place_road(Vector2i(h.x + 4, y))
	s.place_building("storehouse", Vector2i(h.x + 5, h.y + 1))
	for t in [Vector2i(h.x + 3, h.y - 1), Vector2i(h.x + 7, h.y - 1), Vector2i(h.x - 4, h.y + 1), Vector2i(h.x - 2, h.y - 1)]:
		s.place_building("tent", t)
	for id in ["lumen_tap", "woodcutter", "forager", "forager"]:
		_place_connected(s, id)
	for i in 4:
		s.add_citizen()
	var cam: CameraController = main.get_node("Camera")
	# Evening to the next morning at the sim level, then real frames around the 6:00 departure.
	s.step_hours(6)
	s.step_seconds(0.8)
	for pair in [[2, "/tmp/hv_walkers_z1.png"], [3, "/tmp/hv_walkers_z2.png"]]:
		cam.set_zoom_step(pair[0])
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(pair[1])
	quit()
