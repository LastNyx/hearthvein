extends SceneTree
## HUD screenshots (ticket 130), always under Xvfb, never a visible window:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tools/hud_shot.gd [-- out_dir [width height [seed]]]
## Builds a Town (like tools/town_shot.gd) and writes out_dir/130-<name>.png (default .scratch/v1/shots): sawmill
## selected, a category open, nothing selected (town summary), the same at night. A width/height other than the
## project's 1280x720 resizes the window first (run Xvfb with at least that screen).

const L := preload("res://tools/shot_layout.gd")


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("wrote ", path, " ", root.size)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else ".scratch/v1/shots"
	var suffix := ""
	if args.size() > 2:
		DisplayServer.window_set_size(Vector2i(int(args[1]), int(args[2])))
		root.size = Vector2i(int(args[1]), int(args[2]))
		await process_frame
		await process_frame
		if int(args[1]) != 1280:
			suffix = "-%d" % int(args[1])
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[3]) if args.size() > 3 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var hud: Hud = main.get_node("Hud")
	var h := s.map.hearth_spot
	s.era_current = "town"
	s.hearth.inventory.add("wood", 300.0)
	s.hearth.inventory.add("stone", 300.0)
	s.hearth.inventory.add("cut_stone", 40.0)
	s.hearth.inventory.add("food", 200.0)
	L.build(s, "lumen_pump", h + Vector2i(14, -4), 14)
	L.build(s, "rowhouse", h + Vector2i(-4, 0))
	L.build(s, "rowhouse", h + Vector2i(-6, 0))
	L.build(s, "greenhouse", h + Vector2i(-9, 0))
	var saw := L.build(s, "sawmill", h + Vector2i(4, -2))
	L.build(s, "mason", h + Vector2i(7, -5))
	L.build(s, "kitchen", h + Vector2i(2, 0))
	L.build(s, "well", h + Vector2i(2, 7), 12)
	L.pave_near_hearth(s, 9)
	L.populate(s)
	for i in 2 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(h) + Vector2(0, 1)) * ArtLibrary.TILE
	cam.set_zoom_step(2)
	root.warp_mouse(Vector2(2, 2))  # keep the map hover tip away
	m.clear_selection()
	hud.refresh()
	await _shoot("%s/130-nothing-selected%s.png" % [out, suffix])
	if saw != null:
		m.select(saw.id)
	await _shoot("%s/130-sawmill-selected%s.png" % [out, suffix])
	m.clear_selection()
	hud.open_category("housing")
	await _shoot("%s/130-category-open%s.png" % [out, suffix])
	hud.open_category("housing")
	var guard := 0
	while s.clock.hour() != 23 and guard < 48:
		s.step_hours(1)
		guard += 1
	if saw != null:
		m.select(saw.id)
	await _shoot("%s/130-night%s.png" % [out, suffix])
	quit()
