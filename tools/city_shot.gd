extends SceneTree
## Windowed screenshot of a City settlement: godot --path . -s tools/city_shot.gd [-- seed]
## City buildings (apartment blocks, grand bazaar, lumen reactor, purifier tower, park, toolsmith, lumen nexus) next to
## some Town ones, dirt roads with a paved stretch.
## Writes /tmp/hv_city_z1.png (zoom step 1) and /tmp/hv_city_z2.png (zoom step 2) after two game days of work.

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


const L := preload("res://tools/shot_layout.gd")


func _try(s: Settlement, id: String, near: Vector2i, radius: int = 10) -> void:
	L.build(s, id, near, radius)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	s.era_current = "city"
	(main.get_node("Hud") as Hud).refresh()
	s.hearth.inventory.add("wood", 900.0)
	s.hearth.inventory.add("stone", 900.0)
	s.hearth.inventory.add("cut_stone", 40.0)
	s.hearth.inventory.add("food", 900.0)
	# Town buildings around the Hearth; wells need a wet tile and pumps need a vein, so their searches are wider.
	# Vein buildings first: veins are scarce and the other buildings would cover them.
	_try(s, "lumen_reactor", h + Vector2i(14, -4), 14)
	_try(s, "apartment_block", h + Vector2i(-4, 0))
	_try(s, "apartment_block", h + Vector2i(-7, 0))
	_try(s, "rowhouse", h + Vector2i(-10, 0))
	_try(s, "grand_bazaar", h + Vector2i(3, 0))
	_try(s, "park", h + Vector2i(-3, -4))
	_try(s, "purifier_tower", h + Vector2i(1, -3))
	_try(s, "toolsmith", h + Vector2i(5, -3))
	_try(s, "refinery", h + Vector2i(7, -6))
	_try(s, "greenhouse", h + Vector2i(-12, 0))
	_try(s, "well", h + Vector2i(2, 7), 12)
	_try(s, "handcart_shed", h + Vector2i(12, 3))
	_try(s, "lumen_spire", h + Vector2i(-8, -5), 10)
	_try(s, "lumen_nexus", h + Vector2i(12, 0), 10)
	L.pave_near_hearth(s, 9)
	L.populate(s)
	for i in 2 * 24:
		s.step_hours(1)
	L.report(s, "city")
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(h) + Vector2(0, 1)) * ArtLibrary.TILE
	cam.set_zoom_step(1)
	await _shoot("/tmp/hv_city_z1.png")
	cam.set_zoom_step(2)
	await _shoot("/tmp/hv_city_z2.png")
	quit()
