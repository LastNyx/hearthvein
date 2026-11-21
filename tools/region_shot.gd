extends SceneTree
## Windowed screenshots of the region map: godot --path . -s tools/region_shot.gd [-- seed]
## Writes /tmp/hv_region_bar.png (main view, Village build bar with every category showing, 1280x720) and
## /tmp/hv_region_map.png (the region map open on M, gold for one region).

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var hud := main.get_node("Hud") as Hud
	s.era_override = "village"
	hud.refresh()
	s.gold = 60.0
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	hud.open_category("civic")
	await _shoot("/tmp/hv_region_bar.png")
	hud.open_category("civic")
	hud.toggle_region_map()
	await _shoot("/tmp/hv_region_map.png")
	print("categories: ", main.hud_model.build_bar().size(), " buyable rows: ",
			main.hud_model.region_rows().filter(func(r: Dictionary) -> bool: return r["state"] == "buyable").size())
	quit()
