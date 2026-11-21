extends SceneTree
## Windowed screenshots of the coverage overlay: godot --path . -s tools/coverage_shot.gd [-- seed]
## Writes /tmp/hv_coverage_off.png and /tmp/hv_coverage_on.png: Village era, a Shrine (r6), a Market (r12 reach), homes
## inside and outside the Shrine's radius, the build bar (gold category included) open on civic.

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
	var m: HudModel = main.hud_model
	var h := s.map.hearth_spot
	s.era_override = "village"
	(main.get_node("Hud") as Hud).refresh()
	for y in range(h.y - 10, h.y + 11):
		for x in range(h.x - 12, h.x + 30):
			if MapState.in_bounds(x, y) and s.map.terrain_id_at(x, y) in ["forest", "stump"]:
				s.set_terrain(Vector2i(x, y), "grass")
	for x in range(h.x + 2, h.x + 26):
		s.place_road(Vector2i(x, h.y))
	var shrine := h + Vector2i(8, -2)
	s.place_building_instant("shrine", shrine)
	s.place_building_instant("market", h + Vector2i(18, 1))
	# Inside the Shrine's r6 (gap <= 6) ...
	s.place_building_instant("tent", h + Vector2i(5, -4))
	s.place_building_instant("cottage", h + Vector2i(11, 2))
	s.place_building_instant("tent", h + Vector2i(13, -6))
	# ... and outside it (gap > 6).
	s.place_building_instant("cottage", h + Vector2i(20, -4))
	s.place_building_instant("tent", h + Vector2i(16, 6))
	s.place_building_instant("cottage", h + Vector2i(-6, 2))
	s.hearth.inventory.add("food", 200.0)
	for i in 3 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(9, 1)) * ArtLibrary.TILE
	(main.get_node("Hud") as Hud).open_category("gold")
	await _shoot("/tmp/hv_coverage_off.png")
	m.toggle_overlay("coverage")
	await _shoot("/tmp/hv_coverage_on.png")
	print(s.clock.label(), " covered homes: ", (s.get_system(CoverageSystem) as CoverageSystem).covered_homes(s))
	quit()
