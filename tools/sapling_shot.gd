extends SceneTree
## Two stump stages side by side at zoom 2 (ticket 111): a bare stump and one past half way (the sapling).
## godot --path . -s tools/sapling_shot.gd   (writes /tmp/hv_111_sapling_shot.png)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	var young := h + Vector2i(-6, 8)
	var bare := h + Vector2i(-4, 8)
	s.set_terrain(young, "stump")
	s.set_terrain(bare, "stump")
	s.step_days(GameClock.DAYS_PER_SEASON)  # one of two seasons: both stumps are at 0.5 ...
	var fs := s.get_system(ForestSystem) as ForestSystem
	s.set_blighted(bare, true)  # ... but a blighted one stays a bare stump
	main.map_view.refresh_stumps()
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(h) + Vector2(-5, 8.5)) * ArtLibrary.TILE
	print("progress young ", fs.regrow_progress(s, young), " bare ", fs.regrow_progress(s, bare))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_111_sapling_shot.png")
	quit()
