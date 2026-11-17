extends SceneTree
## Windowed screenshot of blighted ground: godot --path . -s tools/blight_shot.gd [-- seed]
## Writes /tmp/hv_blight.png: a Lumen Tap on a vein with its radius blighted, near the Hearth.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			var d := (t - s.map.hearth_spot).length_squared()
			if d < best_d and s.map.terrain_id_at(x, y) == "lumen_vein" and s.can_place("lumen_tap", t)["ok"]:
				best = t
				best_d = d
	s.place_building_instant("lumen_tap", best)
	var tap: Building = s.building_at(best)
	var bs := s.get_system(BlightSystem) as BlightSystem
	for i in 11:  # the whole radius-2 disc, nearest first, as 66 days of the Tap would do
		s.set_blighted(bs.next_tile(s, tap), true)
	for t in [Vector2i(3, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(-3, -2), Vector2i(-4, -2), Vector2i(-4, -3)]:
		s.set_blighted(best + t, true)  # a few strays so the patch looks irregular
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(best) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_blight.png")
	quit()
