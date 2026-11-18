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


func _try(s: Settlement, id: String, near: Vector2i, radius: int = 10) -> Building:
	return L.build(s, id, near, radius)


## A track spur of up to 8 tiles off the depot's long side, in whichever direction and row runs longest, with a road
## crossing it (level crossing) a few tiles out.
func _spur(s: Settlement, depot: Building) -> void:
	var r := depot.footprint()
	var best: Array[Vector2i] = []
	for d in L.DIRS:
		for start in L.ring(depot):
			if not r.has_point(start - d):
				continue  # the run must start right against the depot and head away from it
			var run: Array[Vector2i] = []
			var t := start
			while run.size() < 8 and s.can_place_track(t)["ok"]:
				run.append(t)
				t += d
			if run.size() > best.size():
				best = run
	for t in best:
		s.place_track(t)
	if best.size() < 4:
		print("conflux_shot: track spur only ", best.size(), " tiles")
		return
	var c := best[3]
	for yy in range(c.y - 3, c.y + 4):
		s.place_road(Vector2i(c.x, yy))
	print("conflux_shot: track spur ", best.size(), " tiles, crossing at ", c, " road ", s.road_at(c), " track ", s.track_at(c))


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
	s.hearth.inventory.add("materials", 900.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("food", 900.0)
	# Vein buildings first: veins are scarce and the other buildings would cover them.
	_try(s, "vein_bore", h + Vector2i(14, -4), 16)
	_try(s, "lumen_reactor", h + Vector2i(-14, -4), 16)
	var depot := _try(s, "rail_depot", h + Vector2i(6, 10), 6)  # early, in open ground, so the spur has room
	_try(s, "lumen_nexus", h + Vector2i(8, -6), 10)
	_try(s, "lumen_pylon", h + Vector2i(4, -5), 6)
	_try(s, "lumen_pylon", h + Vector2i(12, -2), 6)
	_try(s, "lumen_pylon", h + Vector2i(-3, -6), 6)
	_try(s, "grid_battery", h + Vector2i(1, -5), 6)
	# Housing, water and food
	_try(s, "apartment_block", h + Vector2i(-4, 0))
	_try(s, "apartment_block", h + Vector2i(-7, 0))
	_try(s, "rowhouse", h + Vector2i(-10, 0))
	_try(s, "conduit_terraces", h + Vector2i(-6, 5), 8)
	_try(s, "water_tower", h + Vector2i(-2, 5), 8)
	_try(s, "hydroponic_hall", h + Vector2i(-4, 5), 10)  # wet from the tower's radius
	_try(s, "grand_bazaar", h + Vector2i(3, 0))
	_try(s, "greenhouse", h + Vector2i(-12, 3))
	_try(s, "well", h + Vector2i(2, 7), 12)
	# Logistics and the landmark
	_try(s, "handcart_shed", h + Vector2i(8, 3))
	_try(s, "airship_dock", h + Vector2i(11, 7), 10)
	_try(s, "sky_foundry", h + Vector2i(-12, -8), 12)
	L.pave_near_hearth(s, 9)
	if depot != null:
		_spur(s, depot)
	L.populate(s)
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
