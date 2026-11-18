extends SceneTree
## Windowed shot of the Settings panel: godot --path . -s tools/settings_shot.gd
## Uses a temp settings file (never user://settings.cfg), opens Settings from the Esc menu, writes /tmp/hv_settings.png.

const CFG := "/tmp/hv_settings_shot.cfg"
const DIR := "/tmp/hv_settings_shot_saves"


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	main.saves_dir = DIR
	main.settings_path = CFG
	root.add_child(main)
	await process_frame
	main.start_new_game()
	main.menu.open()
	main.menu.show_settings()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_settings.png")
	main.menu.close()
	DirAccess.remove_absolute(CFG)
	quit()
