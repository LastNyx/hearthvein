extends SceneTree
## Ticket 138: lamp light pools at night. godot --path . -s tools/lamps_night_shot.gd [-- out.png]
## The night_shot village with a Brazier, a Lantern Post and a Lumen Lamp along the road, all fuelled, shot at 22:00 of
## day 2 (Xvfb: xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tools/lamps_night_shot.gd).

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/138-lamps-night.png"
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	for dx in [4, 8, 12]:
		s.place_building_instant("cottage", Vector2i(h.x + dx, h.y - 2))
	s.place_building_instant("storehouse", Vector2i(h.x + 14, h.y + 1))
	s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 2))
	s.hearth.inventory.add("food", 300.0)
	s.hearth.inventory.add("lumen", 100.0)
	var fuels := {1: "wood", 2: "charcoal", 3: "lumen"}
	var at := 0
	for tier in [1, 2, 3]:
		var id := s.place_building_instant("lamp", Vector2i(h.x + 4 + 4 * at, h.y + 1))
		at += 1
		if id < 0:
			continue
		var lamp: Building = s.buildings[id]
		lamp.tier = tier
		lamp.input_buffer.add(fuels[tier], 6.0)
	s.era_override = "town"
	for i in 2 * 24 + 16:  # 22:00 of day 3 (the game starts at 06:00)
		s.step_hours(1)
	for b: Building in s.buildings.values():
		if b.def.lamp:
			b.lit_tonight = true  # the buffers of tiers II and III take no fuel from this fixture: light all three
	s.light_version += 1
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	cam.position = (Vector2(h) + Vector2(10, 1)) * ArtLibrary.TILE
	main.driver.set_speed(0)
	main._update_tint()
	await _shoot(out)
	print("lamps lit: ", s.buildings.values().filter(func(b: Building) -> bool: return b.def.lamp and b.lit_tonight).size())
	quit()
