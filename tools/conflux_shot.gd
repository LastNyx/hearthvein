extends SceneTree
## Screenshot of a Conflux settlement (ticket 39d): godot --path . -s tools/conflux_shot.gd [-- seed [nodraw]]
## City buildings plus the Conflux set: Lumen Nexus, three Lumen Pylons, a Grid Battery, a Vein Bore on a vein, Conduit
## Terraces beside a Water Tower, a Hydroponic Hall, a Rail Depot with a short track spur crossing a road, an Airship
## Dock and the Sky Foundry, with enough housing and food to run. Every building is road-linked and staffed (see
## shot_layout.gd). With "nodraw" no image is written (headless layout check): it prints the layout report instead.
## Writes .scratch/v1/hv_39d_conflux_z1.png (zoom step 1) and hv_39d_conflux_z2.png (zoom step 2) after two game days.

const L := preload("res://tools/shot_layout.gd")
const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
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
	(main.get_node("Hud") as Hud)._rebuild_categories()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("wood", 900.0)
	s.hearth.inventory.add("stone", 900.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("food", 900.0)
	L.conflux(s)
	for i in 2 * 24:
		s.step_hours(1)
	L.report(s, "conflux")
	var ids := {}
	for bid in s.buildings:
		ids[s.buildings[bid].def.id] = ids.get(s.buildings[bid].def.id, 0) + 1
	print("conflux_shot: ", ids)
	if not draw:
		main.driver.set_speed(0)
		for i in 10:
			await process_frame
		quit()
		return
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(h) + Vector2(0, 1)) * ArtLibrary.TILE
	cam.set_zoom_step(1)
	await _shoot(OUT + "hv_39d_conflux_z1.png")
	cam.set_zoom_step(2)
	await _shoot(OUT + "hv_39d_conflux_z2.png")
	quit()
