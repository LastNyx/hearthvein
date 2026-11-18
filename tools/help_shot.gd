extends SceneTree
## Windowed screenshots: godot --path . -s tools/help_shot.gd
## Writes /tmp/hv_help_core_loop.png, /tmp/hv_help_dimming.png and /tmp/hv_help_controls.png (the help screen on that page).


func _shoot(path: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.settings_path = "/tmp/hv_help_settings.cfg"
	root.add_child(main)
	await process_frame
	main.start_new_game(42)
	await process_frame
	for page in ["core_loop", "dimming", "controls"]:
		main.help.open_page(page)
		await _shoot("/tmp/hv_help_%s.png" % page)
	main.help.close()
	quit()
