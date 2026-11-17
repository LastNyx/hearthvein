extends SceneTree
## Windowed screenshots of a Storehouse construction site: godot --path . -s tools/site_shot.gd
## Writes /tmp/hv_site.png (mid-build) and /tmp/hv_site_done.png (finished).

func _shoot(path: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 12):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var id := s.place_building("storehouse", Vector2i(h.x + 5, h.y - 1))
	var b: Building = s.buildings[id]
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(4)
	cam.position = (Vector2(h) + Vector2(5, 0)) * ArtLibrary.TILE
	var guard := 0
	while b.site and b.build_progress() < 0.55 and guard < 400:
		s.step_seconds(1.0)
		guard += 1
	print("site progress ", b.build_progress(), " at ", s.clock.label())
	await _shoot("/tmp/hv_site.png")
	guard = 0
	while b.site and guard < 2000:
		s.step_seconds(1.0)
		guard += 1
	print("done ", not b.site, " at ", s.clock.label())
	await _shoot("/tmp/hv_site_done.png")
	quit()
