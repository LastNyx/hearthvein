extends SceneTree
## Resources page used-by screenshot (ticket 124): godot --path . -s tools/used_by_shot.gd [-- seed]
## Writes .scratch/v1/shots/124-used-by.png: a small town run for ~10 days (woodcutters, a sawmill, a tent site under
## construction), wood selected and its breakdown open, so "Used yesterday" lists what ate the wood.

const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/shots/"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	# A cleared strip for the road, woodcutters north of it with forest planted in their range, a sawmill eating their
	# wood, a forager, storehouses and cottages: wood is made and used, food is eaten.
	for x in range(h.x + 2, h.x + 24):
		for y in range(h.y - 4, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var wc_def := s.registry.get_building("woodcutter")
	var grove: Array[Vector2i] = []
	for dx in [4, 9]:
		for dy in [-6, -5, -4, -3]:
			for ox in range(-3, 4):
				grove.append(Vector2i(h.x + dx + ox, h.y + dy))
		s.place_building_instant("woodcutter", Vector2i(h.x + dx, h.y - wc_def.size.y))
	s.place_building_instant("sawmill", Vector2i(h.x + 13, h.y - 1))
	s.place_building_instant("forager", Vector2i(h.x + 7, h.y + 1))
	for dx in [16, 19]:  # room for the wood and the sawmill's planks (a full storage halts the woodcutters)
		s.place_building_instant("storehouse", Vector2i(h.x + dx, h.y + 1))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y + 1))
	s.hearth.inventory.add("food", 600.0)
	for i in 9 * 24:
		s.step_hours(1)
		if i % 24 == 12:  # a Forester stands in: the grove grows back every day, so the woodcutters never run dry
			for g in grove:
				s.set_terrain(g, "forest")
	# A site placed for the last day, so its hauled wood is the construction use of "yesterday".
	s.place_building("tent", Vector2i(h.x + 11, h.y - 1))
	for i in 24:
		s.step_hours(1)
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	print("wood used yesterday: ", ledger.used_breakdown("wood"))
	var hud: Hud = main.get_node("Hud")
	hud.resources_page.open_for("wood")
	for i in 6:
		await process_frame
	hud.resources_page.show_breakdown("wood")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := OUT + "124-used-by.png"
	print("shot: ", path, " written: ", root.get_texture().get_image().save_png(path) == OK)
	quit()
