extends SceneTree
## Windowed screenshot after some woodcutting: godot --path . -s tools/hauling_shot.gd
## Builds a forager, woodcutter and storehouse by the road, runs a few days and writes /tmp/hv_hauling.png.

func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 2, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building("forager", Vector2i(h.x + 4, h.y - 1))
	s.place_building("storehouse", Vector2i(h.x + 6, h.y - 1))
	s.place_building("woodcutter", Vector2i(h.x + 9, h.y + 1))
	# Forest for the woodcutter to chew on (the seed's own trees are further out).
	for dy in range(2, 5):
		for dx in range(7, 13):
			s.set_terrain(Vector2i(h.x + dx, h.y + dy), "forest")
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(h) + Vector2(10, 2)) * ArtLibrary.TILE
	s.step_days(10)
	s.step_hours(10)  # mid-morning of the next day: people at work, haulers walking
	s.step_seconds(1.0)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_hauling.png")
	quit()
