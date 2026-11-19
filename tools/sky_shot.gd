extends SceneTree
## Screenshots of the sky layer (ticket 40d): godot --path . -s tools/sky_shot.gd [-- seed [nodraw]]
## A Skyborne settlement: the city set, a finished Sky Foundry, a Lift Anchor with its raised island over the Hearth's
## region, a Lumen grid feeding it (so the island is not still), two Sky Lifts, sky roads, every Skyborne building on the
## island (Skyspire, Cloud Cistern, Sky Garden, Aether Collector, Skyforge, Observatory, island Airship Dock) and the
## Dawn Beacon on the ground near the anchor, and citizens walking (some commute over the lifts). Camera centred on the island.
## Writes .scratch/v1/hv_72_ground_z1.png, hv_72_sky_z1.png, hv_72_ground_z2.png, hv_72_sky_z2.png (the sky ones
## after the Tab toggle, HudModel.toggle_layer). With "nodraw" no image is written: it prints the layout report only.

const L := preload("res://tools/shot_layout.gd")
const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"
## File name prefix of the shots (ticket 72 sky art pass 2; the 71 shots keep their hv_71_ names).
const PREFIX := "hv_72_"


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _count_sky(walkers: Dictionary) -> int:
	var n := 0
	for id in walkers:
		if MapState.layer_of((walkers[id] as Walker).tile) == 1:
			n += 1
	return n


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var draw := not args.has("nodraw")
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	s.era_current = "skyborne"
	(main.get_node("Hud") as Hud)._rebuild_categories()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("wood", 900.0)
	s.hearth.inventory.add("stone", 900.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("food", 900.0)
	s.hearth.inventory.add("lumen", 600.0)
	var lay := L.sky(s)
	if lay.is_empty():
		quit(1)
		return
	var isl: Island = lay["island"]
	var dock: Building = lay["dock"]
	var lift1: Building = lay["lift1"]
	var lift2: Building = lay["lift2"]
	for i in 3 * 24:
		s.step_hours(1)
	L.report(s, "sky")
	if dock != null:
		var n := 0
		for cid in s.citizens:
			if (s.citizens[cid] as Citizen).job_id == dock.id:
				n += 1
		print("sky_shot: dock job holders after 3 days ", n, " site ", dock.site)
	var ids := {}
	for bid in s.buildings:
		var key := "%s@%d" % [s.buildings[bid].def.id, s.buildings[bid].layer]
		ids[key] = ids.get(key, 0) + 1
	print("sky_shot: island ", isl.rect, " still=", isl.still_why, " dock=", dock != null, " ", ids)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var on_sky := _count_sky(ws.walkers)
	var extra := 0
	while on_sky == 0 and extra < 400:  # step on until someone is up on the island, so the sky shot has walkers
		s.step_seconds(2.0)
		extra += 1
		on_sky = _count_sky(ws.walkers)
	if dock != null:
		var w := 0
		for cid in s.citizens:
			var ct: Citizen = s.citizens[cid]
			if ct.job_id == dock.id and ct.job_kind == Citizen.JOB_WORK:
				w += 1
		print("sky_shot: dock workers ", w, " connected ", dock.connected, " hour ", s.clock.total_hours, " lifts ", lift1.connected if lift1 else -1, lift2.connected if lift2 else -1)
	print("sky_shot: ", ws.walkers.size(), " walkers, ", on_sky, " on the sky layer")
	if not draw:
		main.driver.set_speed(0)
		for i in 10:
			await process_frame
		quit()
		return
	main.driver.set_speed(0)  # a frozen frame: walkers stand where they are
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(isl.rect.get_center()) + Vector2(0, 1)) * ArtLibrary.TILE
	var model: HudModel = main.hud_model
	for zoom in [[1, "z1"], [2, "z2"]]:
		cam.set_zoom_step(zoom[0])
		model.set_layer(Building.LAYER_GROUND)
		await _shoot(OUT + PREFIX + "ground_%s.png" % zoom[1])
		model.toggle_layer()  # Tab
		await _shoot(OUT + PREFIX + "sky_%s.png" % zoom[1])
	quit()
