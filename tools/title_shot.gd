extends SceneTree
## Windowed shot of the title screen: godot --path . -s tools/title_shot.gd
## Uses temp saves and settings (never user://), writes /tmp/hv_title.png, /tmp/hv_new_game.png (the New game panel open) and, for ticket 92, /tmp/hv_92_title.png (version label) and /tmp/hv_92_whats_new.png (What's new panel open) and, for ticket 94, /tmp/hv_94_title.png (Update button, from test/fixtures/release_latest.json as an AppImage offer) and /tmp/hv_94_update.png (Update panel open). A save is planted so Continue shows.

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
	main.close_new_game_panel()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_92_title.png")
	main.open_whats_new()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_92_whats_new.png")
	main.close_whats_new()
	main.install_kind = "appimage"
	var json := FileAccess.get_file_as_string("res://test/fixtures/release_latest.json")
	main.show_update_offer(UpdateCheck.offer_from_text(json, "1.1.1", "appimage"))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_94_title.png")
	main.open_update_panel()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_94_update.png")
	DirAccess.remove_absolute(DIR.path_join("slot_0.dat"))
	DirAccess.remove_absolute(DIR.path_join("slot_0.meta"))
	DirAccess.remove_absolute(DIR)
	DirAccess.remove_absolute(CFG)
	quit()
