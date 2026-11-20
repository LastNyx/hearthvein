extends SceneTree
## Build menu screenshot (tickets 116, 122): godot --path . -s tools/build_menu_shot.gd [-- seed]
## Writes .scratch/v1/shots/122-bar.png with every era unlocked, so the category bar shows all 12 categories on one
## row and the open category (Refining) stays lit. Prints the bar's rect.

const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/shots/"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	s.era_override = "ascendant"
	hud._rebuild_categories()
	hud.open_category("refining")
	for i in 4:
		await process_frame
	var bar := hud.model.build_bar()
	var r := (hud._cat_box.get_parent() as Control).get_global_rect()
	print("bar: ", bar.size(), " categories, rect ", r, ", one row inside 1280: ",
			r.position.x >= 0.0 and r.end.x <= 1280.0)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := OUT + "122-bar.png"
	print("shot: ", path, " written: ", root.get_texture().get_image().save_png(path) == OK)
	quit()
