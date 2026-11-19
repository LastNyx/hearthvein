extends SceneTree
## Windowed build menu screenshot (tickets 116, 117): godot --path . -s tools/build_menu_shot.gd [-- seed]
## Writes /tmp/hv_116_build_menu.png: a Village-era town with little stone, the Refining flyout open (a red card, a
## locked card with its unlock reason) and the detail panel of one card on the right. Prints the card states.

const L := preload("res://tools/shot_layout.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var h := s.map.hearth_spot
	s.era_current = "village"
	var spots := {"cottage": Vector2i(-4, 0), "farm": Vector2i(-10, 4), "market": Vector2i(4, 4),
			"shrine": Vector2i(-2, 4), "sawmill": Vector2i(8, 0), "forester": Vector2i(14, 0)}
	for id: String in spots:
		L.build(s, id, h + (spots[id] as Vector2i), 10)
	s.hearth.inventory.remove("stone", s.hearth.inventory.amount_of("stone"))
	s.hearth.inventory.add("stone", 10.0)  # a Sawmill (21 stone) is short: its card is red
	s.hearth.inventory.add("wood", 60.0)
	hud._rebuild_categories()
	hud.open_category("refining")
	for i in 4:
		await process_frame
	for cat in hud.model.build_bar():
		if cat["id"] == "refining":
			for e: Dictionary in cat["entries"]:
				print("card ", e["id"], ": ", "locked" if e["locked"] else ("short" if e["short"] else "ok"), " ", e["unlock"])
	var b := hud.build_button("sawmill")
	if b != null:
		b.mouse_entered.emit()
		hud.hover_tick(1.0)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_116_build_menu.png")
	quit()
