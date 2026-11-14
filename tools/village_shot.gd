extends SceneTree
## Windowed screenshot of every Village building around the Hearth: godot --path . -s tools/village_shot.gd [-- seed]
## Writes /tmp/hv_village_z1.png (zoom step 1) and /tmp/hv_village_z2.png (zoom step 2) after two game days of work.

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _try(s: Settlement, id: String, near: Vector2i) -> void:
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := near + Vector2i(dx, dy)
				if s.can_place(id, t)["ok"]:
					s.place_building_instant(id, t)
					return
	print("could not place ", id, " near ", near)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	s.era_current = "village"
	(main.get_node("Hud") as Hud)._rebuild_categories()
	for x in range(h.x - 14, h.x + 18):
		s.place_road(Vector2i(x, h.y + 3))
	for x in range(h.x - 14, h.x + 18, 4):
		s.place_road(Vector2i(x, h.y + 2))
	_try(s, "cottage", h + Vector2i(-4, 0))
	_try(s, "cottage", h + Vector2i(-6, 0))
	_try(s, "farm", h + Vector2i(-10, 4))
	_try(s, "market", h + Vector2i(4, 4))
	_try(s, "shrine", h + Vector2i(-2, 4))
	_try(s, "sawmill", h + Vector2i(8, 0))
	_try(s, "builders_yard", h + Vector2i(11, 4))
	_try(s, "forester", h + Vector2i(14, 0))
	_try(s, "quarry", h + Vector2i(6, -6))
	_try(s, "fishing_dock", h + Vector2i(0, 8))
	_try(s, "bell_tower", h + Vector2i(-12, -3))
	s.hearth.inventory.add("food", 200.0)
	s.hearth.inventory.add("materials", 100.0)
	for i in 2 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(h) + Vector2(0, 1)) * ArtLibrary.TILE
	cam.set_zoom_step(1)
	await _shoot("/tmp/hv_village_z1.png")
	cam.set_zoom_step(2)
	await _shoot("/tmp/hv_village_z2.png")
	quit()
