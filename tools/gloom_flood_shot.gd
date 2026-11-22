extends SceneTree
## Ticket 155: a Dimming night with gloom, and a spring flood held back by a levee.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tools/gloom_flood_shot.gd -- gloom out.png
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tools/gloom_flood_shot.gd -- flood out.png
## gloom: forest edge east of the Hearth with a lit cottage cluster (two Braziers) and an unlit farm, at 01:00 of a
## Dimming's first night (gloom crept 7 rings). flood: a river row cut through grass, cottages on both banks and the
## rows behind them, a levee along the east half of the bank, shot on the flood's first day.

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "gloom"
	var out := args[1] if args.size() > 1 else "/tmp/155-%s.png" % mode
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	if mode == "flood":
		await _flood(main, out)
	else:
		await _gloom(main, out)
	quit()


func _gloom(main: Node, out: String) -> void:
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 12):
		for y in range(h.y - 3, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest" or s.map.terrain_id_at(x, y) == "rock":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.era_override = "town"
	for spec in [["cottage", 3, -2], ["cottage", 5, -2], ["storehouse", 8, 1], ["farm", 10, -3], ["cottage", 7, -2]]:
		s.place_building_instant(spec[0], Vector2i(h.x + int(spec[1]), h.y + int(spec[2])))
	for lamp_at in [Vector2i(4, -1), Vector2i(8, 0)]:
		var lid := s.place_building_instant("lamp", h + lamp_at)
		if lid >= 0:
			s.buildings[lid].input_buffer.add("wood", 8.0)
	s.hearth.inventory.add("food", 300.0)
	s.hearth.inventory.add("lumen", 60.0)
	for i in 12:
		s.add_citizen()
	var d := s.get_system(DimmingSystem) as DimmingSystem
	d._start_day = s.clock.total_days()
	d._length = 4
	d._active = true
	for i in 19:  # 06:00 -> 01:00
		s.step_hours(1)
	var g := s.get_system(GloomSystem) as GloomSystem
	print("hour ", s.clock.hour(), " gloom tiles ", g.tiles.size(), " depth ", g.max_depth())
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(h) + Vector2(8, 0.0)) * ArtLibrary.TILE
	main.driver.set_speed(0)
	main._update_tint()
	await _shoot(out)


func _flood(main: Node, out: String) -> void:
	var s: Settlement = main.settlement
	var fs := s.get_system(FloodSystem) as FloodSystem
	# a clear 16x9 block, a river row through it, regions owned
	var bx := 0
	var by := 0
	var found := false
	for y in range(6, MapState.HEIGHT - 12):
		for x in range(6, MapState.WIDTH - 22):
			var ok := true
			for yy in range(y - 3, y + 12):
				for xx in range(x - 3, x + 19):
					if s.map.terrain_id_at(xx, yy) == "water" or s.map.is_river(xx, yy) or s.occupancy[MapState.idx(xx, yy)] >= 0:
						ok = false
						break
				if not ok:
					break
			if ok:
				bx = x
				by = y
				found = true
				break
		if found:
			break
	var ry := by + 4
	for y in range(by, by + 9):
		for x in range(bx, bx + 16):
			s.set_terrain(Vector2i(x, y), "grass")
			s.map.set_region_owned(s.map.get_region(x, y), true)
	for x in range(bx, bx + 16):
		s.set_terrain(Vector2i(x, ry), "water")
		s.map.set_flow(x, ry, MapState.FLOW_E)
	s.era_override = "town"
	# west half open, east half behind a levee on the north bank (x 8..15); homes on the bank row, the next row and the south
	for x in range(bx + 8, bx + 16):
		s.place_building_instant("levee", Vector2i(x, ry - 1))
	for x in [bx + 2, bx + 5, bx + 9, bx + 12]:
		s.place_building_instant("cottage", Vector2i(x, ry - 2))
	for x in [bx + 3, bx + 10]:
		s.place_building_instant("cottage", Vector2i(x, ry + 2))
	s.place_building_instant("storehouse", Vector2i(bx + 6, ry - 4))
	s.hearth.inventory.add("food", 200.0)
	# step to the flood's first day (no Dimming), a little after midnight
	var start := fs.flood_start_day(s, 1)
	while s.clock.total_days() < start:
		s.step_hours(1)
	s.step_hours(10)
	print("flood active ", fs.active, " tiles ", fs.flooded_tiles().size(), " start ", start, " day ", s.clock.total_days())
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(bx + 8, ry) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	main.driver.set_speed(0)
	main._update_tint()
	await _shoot(out)
