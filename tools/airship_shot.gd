extends SceneTree
## Windowed screenshots of the airship and the region map survey UI (ticket 68):
##   godot --path . -s tools/airship_shot.gd [-- seed [nodraw]]
## A Conflux settlement with two owned regions side by side, each with a staffed Airship Dock. The left region holds a
## storehouse full of food, the right region a tent of homes that need it, so the docks ship food by air. The sim is
## stepped until an airship leaves, then to about half way, and frozen; the camera frames the airship.
## Then only the two dock regions stay owned: a buyable unrevealed region (Buy + Survey), a surveyed locked one and an
## unsurveyed locked one show on the region map (M), which is opened. With "nodraw" no image is written (headless layout check): the shipment is printed instead.
## Writes .scratch/v1/hv_68_air_z1.png, hv_68_air_z2.png and hv_68_region_map.png.

const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _region_of(b: Building) -> int:
	return MapState.region_at(b.origin.x, b.origin.y)


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
	var hud := main.get_node("Hud") as Hud
	hud._rebuild_categories()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("materials", 900.0)
	s.hearth.inventory.add("cut_stone", 200.0)
	# The sim runs only through our own stepping; jobs are set by hand, so the job and growth systems stay out.
	s.systems.erase(s.get_system(GrowthSystem))
	s.systems.erase(s.get_system(JobSystem))
	var r1 := MapState.region_at(h.x, h.y)
	var left := (r1 / MapState.REGION_COLS) * MapState.REGION_COLS + mini(r1 % MapState.REGION_COLS, 1)
	var rect := MapState.region_rect(left)
	var bx := rect.end.x
	var y0 := h.y + 8 if h.y + 8 < rect.end.y - 8 else h.y - 8
	for x in range(bx - 14, bx + 50):
		for y in range(y0 - 3, y0 + 8):
			s.set_terrain(Vector2i(x, y), "grass")
	var dock_a := s.place_building_instant("airship_dock", Vector2i(bx - 6, y0))
	var dock_b := s.place_building_instant("airship_dock", Vector2i(bx + 3, y0))
	var store_a := s.buildings[s.place_building_instant("storehouse", Vector2i(bx - 13, y0 + 2))] as Building
	var store_b := s.buildings[s.place_building_instant("storehouse", Vector2i(bx + 10, y0 + 2))] as Building
	var tent := s.buildings[s.place_building_instant("tent", Vector2i(bx + 12, y0 - 3))] as Building
	if dock_a < 0 or dock_b < 0 or store_a == null or store_b == null or tent == null:
		print("airship_shot: placement failed")
		quit(1)
		return
	while s.citizens.size() < 14:
		s.add_citizen()
	for g in s.hearth.inventory.goods():
		if g != "materials" and g != "cut_stone":
			s.hearth.inventory.remove(g, 1000000.0)
	store_a.inventory.add("food", 300.0)
	var ids: Array = s.citizens.keys()
	ids.sort()
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.job_id = -1
		c.job_kind = Citizen.JOB_NONE
		c.home_id = -1
		if i < 2:
			c.job_id = dock_a if i == 0 else dock_b
			c.job_kind = Citizen.JOB_WORK
		else:
			c.home_id = tent.id
	main.driver.set_speed(0)
	var air := s.get_system(AirshipSystem) as AirshipSystem
	var guard := 0
	while air.ship_count() == 0 and guard < 72:
		s.step_hours(1)
		guard += 1
	if air.ship_count() == 0:
		print("airship_shot: no shipment after ", guard, " hours")
		quit(1)
		return
	var ship: Dictionary = air.shipments(s)[0]
	var span: float = float(ship["arrive_hour"]) - float(ship["depart_hour"])
	var now := float(s.clock.total_hours) + s._hour_acc / GameClock.REAL_SECONDS_PER_HOUR
	var want := float(ship["depart_hour"]) + span * 0.5 - now
	if want > 0.0:
		s.step_seconds(want * GameClock.REAL_SECONDS_PER_HOUR)
	ship = air.shipments(s)[0]
	print("airship_shot: shipment ", ship["goods"], " from ", ship["from_pos"], " to ", ship["to_pos"], " progress ",
			snappedf(ship["progress"], 0.01), " after ", guard, " hours")
	main.driver.set_speed(0)
	# Own only the two dock regions, so neighbours are buyable and the far regions locked. Wanted on the map: a buyable
	# unrevealed region (Buy + Survey), a locked one that gets surveyed (detail shown), a locked unrevealed one (Survey).
	var keep := {_region_of(s.buildings[dock_a]): true, _region_of(s.buildings[dock_b]): true}
	var buyable := -1
	var far: Array[int] = []
	var near_ring := {}
	for r in MapState.REGION_COUNT:
		if not keep.has(r):
			for k in keep:
				var dc: int = absi(r % MapState.REGION_COLS - int(k) % MapState.REGION_COLS)
				var dr: int = absi(r / MapState.REGION_COLS - int(k) / MapState.REGION_COLS)
				if dc + dr == 1:
					near_ring[r] = true
	for r in MapState.REGION_COUNT:
		if keep.has(r) or s.map.get_region_reward(r) == "":
			continue
		if near_ring.has(r):
			if buyable < 0:
				buyable = r
		elif far.size() < 2:
			far.append(r)
	var locked: Array[int] = far.duplicate()
	if not draw:
		for i in 10:  # lets AirshipView draw once
			await process_frame
		print("airship_shot: buyable ", buyable, " locked reward regions ", locked)
		quit()
		return
	var cam: CameraController = main.get_node("Camera")
	var at := Vector2(ship["pos"]) * float(ArtLibrary.TILE) + Vector2(0, -AirshipView.ALTITUDE)
	cam.position = at
	cam.set_zoom_step(1)
	await _shoot(OUT + "hv_68_air_z1.png")
	cam.set_zoom_step(2)
	cam.position = at
	await _shoot(OUT + "hv_68_air_z2.png")
	# Region map: own only the dock regions, survey the first far region to its end, leave the others unsurveyed.
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, keep.has(r))
	s.gold = maxf(s.gold, 5000.0)
	if locked.size() > 0:
		s.survey_region(locked[0])
		s.step_hours(s.registry.regions.survey_days * 24 + 1)
		print("airship_shot: surveyed ", locked[0], " revealed ", air.is_revealed(s, locked[0]), "; buyable ", buyable,
				" unsurveyed locked ", locked[1] if locked.size() > 1 else -1)
	main.driver.set_speed(0)
	hud.toggle_region_map()
	await _shoot(OUT + "hv_68_region_map.png")
	quit()
