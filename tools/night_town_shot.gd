extends SceneTree
## Ticket 147: a Town at night with the night-life buildings. godot --path . -s tools/night_town_shot.gd [-- out.png]
## Braziers, Night Watch, Tavern, Bakery, Charcoal Kiln, Moonmoth Loft and a Night Market with the caravan wagon parked
## beside it, shot at 22:00 of day 3 (Xvfb: xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver
## opengl3 -s tools/night_town_shot.gd -- .scratch/v1/shots/147-night-town.png).

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/147-night-town.png"
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x - 2, h.x + 22):
		for y in range(h.y - 6, h.y + 7):
			if s.map.terrain_id_at(x, y) == "forest" or s.map.terrain_id_at(x, y) == "rock":
				s.set_terrain(Vector2i(x, y), "grass")
	for x in range(h.x + 2, h.x + 22):
		s.place_road(Vector2i(x, h.y))
	for x in [h.x + 6, h.x + 13]:
		for y in range(h.y - 4, h.y):
			s.place_road(Vector2i(x, y))
	s.era_override = "town"
	var ids := {}
	# north of the road: homes, the Tavern, the Bakery; south: kiln, loft, Night Market, Watch
	for spec in [["cottage", 3, -2], ["cottage", 9, -2], ["tavern", 7, -2], ["bakery", 11, -2], ["cottage", 16, -2],
			["night_watch", 5, 1], ["charcoal_kiln", 7, 1], ["moonmoth_loft", 10, 1], ["night_market", 13, 1],
			["storehouse", 18, 1], ["woodcutter", 3, 2]]:
		var id := s.place_building_instant(spec[0], Vector2i(h.x + int(spec[1]), h.y + int(spec[2])))
		if id < 0:
			print("could not place ", spec[0])
		else:
			ids[spec[0]] = id
	for lamp_at in [Vector2i(5, -1), Vector2i(9, 0), Vector2i(12, -1), Vector2i(15, 0), Vector2i(8, 3)]:
		var lid := s.place_building_instant("lamp", h + lamp_at)
		if lid >= 0:
			s.buildings[lid].input_buffer.add("wood", 6.0)
	s.hearth.inventory.add("food", 300.0)
	s.hearth.inventory.add("crops", 100.0)
	s.hearth.inventory.add("charcoal", 20.0)
	s.hearth.inventory.add("wood", 100.0)
	for i in 30:
		s.add_citizen()
	if ids.has("night_watch"):
		s.buildings[ids["night_watch"]].input_buffer.add("charcoal", 4.0)
	for i in 2 * 24 + 16:  # 22:00 of day 3 (the game starts at 06:00)
		s.step_hours(1)
	var cv := s.get_system(CaravanSystem) as CaravanSystem
	if ids.has("night_market") and not cv.visiting():
		cv.start_visit(s, s.buildings[ids["night_market"]])
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(h) + Vector2(11, 1.0)) * ArtLibrary.TILE
	main.driver.set_speed(0)
	main._update_tint()
	await _shoot(out)
	print("lit buildings: ", s.buildings.values().filter(func(b: Building) -> bool: return b.def.night_only and s.is_lit(b)).size(),
			" caravan: ", cv.visiting(), " ", cv.notice_text(s))
	quit()
