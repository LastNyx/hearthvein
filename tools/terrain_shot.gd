extends SceneTree
## Windowed terrain screenshots: godot --path . -s tools/terrain_shot.gd [-- seed]
## Writes /tmp/hv_terrain_z1.png and /tmp/hv_terrain_z2.png around the Hearth, /tmp/hv_terrain_river.png at the river, /tmp/hv_terrain_lake.png at a lake
## and /tmp/hv_terrain_stumps.png (a felled clearing in a forest).

func _shot(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


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
	s.place_building_instant("tent", Vector2i(h.x + 3, h.y - 1))
	s.place_building_instant("tent", Vector2i(h.x - 3, h.y + 1))
	var cam: CameraController = main.get_node("Camera")
	for pair in [[2, "/tmp/hv_terrain_z1.png"], [3, "/tmp/hv_terrain_z2.png"]]:
		cam.set_zoom_step(pair[0])
		await _shot(pair[1])
	# River bend close-up.
	var path := s.map.river_path
	# The bend with the strongest turn within 45 tiles of the Hearth (chord vs. path over +-10 steps).
	var best := path[path.size() / 2]
	var best_turn := -1.0
	for i in range(10, path.size() - 10):
		if absi(path[i].x - h.x) > 45:
			continue
		var a: Vector2 = path[i - 10]
		var b: Vector2 = path[i + 10]
		var turn := (Vector2(path[i]) - (a + b) / 2.0).length()
		if turn > best_turn:
			best_turn = turn
			best = path[i]
	cam.set_zoom_step(3)
	cam.position = (Vector2(best) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	await _shot("/tmp/hv_terrain_river.png")
	# The roundest, widest water within 50 tiles of the Hearth (a lake on the river).
	var lake := best
	var lake_n := -1
	for y in range(h.y - 30, h.y + 30):
		for x in range(h.x - 50, h.x + 50):
			if not s.map.is_river(x, y):
				continue
			var n := 0
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					if MapState.in_bounds(x + dx, y + dy) and s.map.terrain_id_at(x + dx, y + dy) == "water":
						n += 1
			if n > lake_n:
				lake_n = n
				lake = Vector2i(x, y)
	cam.position = (Vector2(lake) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	await _shot("/tmp/hv_terrain_lake.png")
	# Clear a forest patch through the terrain_changed hook and shoot it.
	var spot := Vector2i(-1, -1)
	for y in range(h.y - 20, h.y + 20):
		for x in range(h.x - 20, h.x + 20):
			if spot.x < 0 and s.map.terrain_id_at(x, y) == "forest" and s.map.terrain_id_at(x + 3, y + 2) == "forest":
				spot = Vector2i(x, y)
	if spot.x >= 0:
		for dy in 3:
			for dx in 4:
				if (dx + dy) % 3 != 2:
					s.set_terrain(spot + Vector2i(dx, dy), "stump")
		cam.position = (Vector2(spot) + Vector2(2, 1.5)) * ArtLibrary.TILE
		await _shot("/tmp/hv_terrain_stumps.png")
	quit()
