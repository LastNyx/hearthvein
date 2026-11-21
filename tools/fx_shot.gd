extends SceneTree
## Moving water and chimney smoke (ticket 90): godot --path . -s tools/fx_shot.gd [-- seed [nodraw]]
## The Conflux layout of tools/shot_layout.gd after two game days, the sim paused (water and smoke are ambience and
## keep moving), the camera between the hearth and the nearest river tile. Writes two frames 0.5 s apart:
## .scratch/v1/hv_90_a.png and hv_90_b.png. The water ripples and the smoke puffs must differ between them.
## With "nodraw" no image is written (headless check): prints how many chimneys are lit.

const L := preload("res://tools/shot_layout.gd")
const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var draw := not args.has("nodraw")
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	s.era_current = "conflux"
	(main.get_node("Hud") as Hud).refresh()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("wood", 900.0)
	s.hearth.inventory.add("stone", 900.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("food", 900.0)
	L.conflux(s)
	for i in 2 * 24:
		s.step_hours(1)
	main.driver.set_speed(0)  # paused: only the shaders move
	var pv: PlacementView = main.placement
	pv.refresh_smoke()
	var lit := 0
	for id in pv._smoke:
		lit += 1 if (pv._smoke[id] as Sprite2D).visible else 0
	var river := Vector2(h)
	var best := 1e9
	for p: Vector2i in s.map.river_path:
		var d := Vector2(p).distance_to(Vector2(h))
		if d < best:
			best = d
			river = Vector2(p)
	print("fx_shot: %d chimneys, %d lit, nearest river tile %s (%.1f tiles from the hearth)" % [pv._smoke.size(), lit, river, best])
	if not draw:
		for i in 10:
			await process_frame
		quit()
		return
	var cam: CameraController = main.get_node("Camera")
	cam.position = ((Vector2(h) + river) / 2.0 + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	cam.set_zoom_step(2)
	for i in 6:
		await process_frame
	await _shoot(OUT + "hv_90_a.png")
	await create_timer(0.5).timeout
	await _shoot(OUT + "hv_90_b.png")
	quit()
