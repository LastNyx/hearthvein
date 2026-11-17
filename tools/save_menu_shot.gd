extends SceneTree
## Windowed shot of the pause/save menu: godot --path . -s tools/save_menu_shot.gd
## Fills a temp saves dir with an autosave pair and a few manual slots, opens the menu, writes /tmp/hv_save_menu.png.

const DIR := "/tmp/hv_save_menu_saves"


func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(DIR.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(DIR)


func _init() -> void:
	_clean()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	main.saves_dir = DIR
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var slots: SaveSlots = main.slots
	slots.autosave(s)
	for i in 6 * 24:
		s.step_hours(1)
	slots.save_slot(0, s)
	slots.autosave(s)
	for i in 20 * 24:
		s.step_hours(1)
	slots.save_slot(1, s)
	slots.save_slot(4, s)
	main.menu.open()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_save_menu.png")
	main.menu_model.request_save(1)
	main.menu.refresh()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_save_menu_confirm.png")
	main.menu.close()
	_clean()
	quit()
