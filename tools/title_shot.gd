extends SceneTree
## Windowed shot of the title screen: godot --path . -s tools/title_shot.gd
## Uses temp saves and settings (never user://), writes /tmp/hv_title.png and /tmp/hv_new_game.png (the New game panel open). A save is planted so Continue shows.

const DIR := "/tmp/hv_title_shot_saves"
const CFG := "/tmp/hv_title_shot.cfg"


func _init() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var slots := SaveSlots.new(DIR)
	slots.save_slot(0, Settlement.new_game(42, reg))
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = DIR
	main.settings_path = CFG
	root.add_child(main)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_title.png")
	main.open_new_game_panel()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_new_game.png")
	DirAccess.remove_absolute(DIR.path_join("slot_0.dat"))
	DirAccess.remove_absolute(DIR.path_join("slot_0.meta"))
	DirAccess.remove_absolute(DIR)
	DirAccess.remove_absolute(CFG)
	quit()
