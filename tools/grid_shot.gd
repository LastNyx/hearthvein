extends SceneTree
## Windowed screenshot of the Lumen grid overlay (tickets 36c, 66): godot --path . -s tools/grid_shot.gd [-- seed]
## A Conflux settlement with a Lumen Nexus, a chain of three linked pylons, one pylon out of link range (its own grid, no
## supply), a Lumen Reactor and a part-charged Grid Battery on the main grid, Lumen-upkeep buildings inside the feed range
## (fed) and two outside every range (unfed). The grid overlay (key L) is switched on.
## Writes .scratch/v1/hv_66_grid_z1.png (zoom step 1) and hv_66_grid_z2.png (zoom step 2).

const L := preload("res://tools/shot_layout.gd")
const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"


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
	var h := s.map.hearth_spot
	s.era_current = "conflux"
	(main.get_node("Hud") as Hud).refresh()
	s.hearth.inventory.add("wood", 900.0)
	s.hearth.inventory.add("stone", 900.0)
	s.hearth.inventory.add("cut_stone", 40.0)
	s.hearth.inventory.add("food", 900.0)
	# The Hearth region is 32 x 24 tiles; positions are relative to its corner so the chain fits inside it.
	var r := MapState.region_rect(s.map.start_region).position
	L.build(s, "apartment_block", h + Vector2i(-4, 0))
	L.build(s, "rowhouse", h + Vector2i(-8, 0))
	L.build(s, "market", h + Vector2i(3, 0))
	# Main grid: Nexus, a chain of two pylons (each link within 12 tiles), Reactor and Battery, Lumen-upkeep buildings.
	L.build(s, "lumen_nexus", r + Vector2i(2, 3), 4)
	L.build(s, "lumen_pylon", r + Vector2i(14, 3), 4)
	L.build(s, "lumen_pylon", r + Vector2i(26, 3), 4)
	L.build(s, "lumen_reactor", r + Vector2i(21, 11), 3)  # needs a Lumen vein tile
	L.build(s, "grid_battery", r + Vector2i(18, 6), 4)
	L.build(s, "workshop", r + Vector2i(8, 7), 4)
	L.build(s, "toolsmith", r + Vector2i(11, 9), 4)
	L.build(s, "greenhouse", r + Vector2i(21, 10), 4)
	# A pylon on the far bank of the river, out of link range of the chain: a grid of its own with no Lumen, so its
	# workshop is unfed. Placed straight (no road: the river is in the way).
	s.place_building_instant("lumen_pylon", r + Vector2i(6, 22))
	s.place_building_instant("workshop", r + Vector2i(8, 22))
	# A Handcart Shed outside every feed radius.
	L.build(s, "handcart_shed", r + Vector2i(28, 14), 3)
	L.pave_near_hearth(s, 9)
	L.populate(s)
	for i in 2 * 24:
		s.step_hours(1)
	var gs := s.get_system(GridSystem) as GridSystem
	for b: Dictionary in (main.get_node("Hud") as Hud).model.grid_batteries():
		gs._charge[b["id"]] = float(b["capacity"]) * 0.4
	L.report(s, "grid")
	var model: HudModel = (main.get_node("Hud") as Hud).model
	print("grid: ", model.grid_ranges().size(), " grids, ", model.grid_links().size(), " links, ", model.grid_consumers().size(),
			" Lumen consumers, ", model.grid_consumers().filter(func(c: Dictionary) -> bool: return c["fed"]).size(), " fed")
	model.overlays["grid"] = true
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(r) + Vector2(16, 12)) * ArtLibrary.TILE
	cam.set_zoom_step(1)
	await _shoot(OUT + "hv_66_grid_z1.png")
	cam.set_zoom_step(2)
	await _shoot(OUT + "hv_66_grid_z2.png")
	quit()
