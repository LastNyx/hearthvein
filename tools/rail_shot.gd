extends SceneTree
## Windowed screenshot of rail track and a train (tickets 37c, 67): godot --path . -s tools/rail_shot.gd [-- seed [nodraw]]
## A Conflux settlement with two regions side by side: the Hearth region holds a road-connected, staffed Rail Depot and
## a stock of food; the next region holds a second depot (road stub beside it, so it is staffed over the rail link) and
## homes that need food. Rail track with two corners joins the depots. The sim is stepped until a shipment leaves, then
## to about half way, so a train stands on the track. The sim is then frozen and the camera frames the train.
## With "nodraw" no image is written (headless layout check): it prints the shipment instead.
## Writes .scratch/v1/hv_67_rail_z1.png (zoom step 1) and hv_67_rail_z2.png (zoom step 2).

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
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	s.era_current = "conflux"
	(main.get_node("Hud") as Hud)._rebuild_categories()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("materials", 900.0)
	s.hearth.inventory.add("cut_stone", 200.0)
	s.hearth.inventory.add("food", 600.0)
	# Two neighbouring regions: the Hearth's own, and the one to its right (or left at the map edge).
	var r1 := MapState.region_at(h.x, h.y)
	var sign := 1 if r1 % MapState.REGION_COLS < MapState.REGION_COLS - 1 else -1
	var rect := MapState.region_rect(r1)
	var bx := rect.end.x if sign > 0 else rect.position.x
	var y0 := h.y + 8 if h.y + 8 < rect.end.y - 8 else h.y - 8
	for x in range(bx - 18, bx + 18):
		for y in range(y0 - 3, y0 + 8):
			s.set_terrain(Vector2i(x, y), "grass")
	# Depot A (Hearth region, road-linked to the Hearth), depot B across the boundary and one row down.
	var a_origin := Vector2i(bx - 5, y0) if sign > 0 else Vector2i(bx + 3, y0)
	var b_origin := Vector2i(bx + 6, y0 + 4) if sign > 0 else Vector2i(bx - 9, y0 + 4)
	var ax := bx - 2 if sign > 0 else bx + 2  # track tile beside depot A
	var cx := bx + 5 if sign > 0 else bx - 6  # corner column, beside depot B
	var depot_a := s.place_building_instant("rail_depot", a_origin)
	var depot_b := s.place_building_instant("rail_depot", b_origin)
	L.connect_road(s, s.buildings[depot_a])
	for t in [b_origin + Vector2i(1, -1), b_origin + Vector2i(2, -1), b_origin + Vector2i(1, 1)]:
		s.place_road(t)
	# The dead-end stub road above depot B must not touch the track row.
	var x := ax
	while x != cx:
		s.place_track(Vector2i(x, y0))
		x += sign
	for y in range(y0, y0 + 5):
		s.place_track(Vector2i(cx, y))
	# A road crosses the track row between the corners (level crossing, ticket 67), north-south through the track.
	var crossx := (ax + cx) / 2
	for y in range(y0 - 3, y0 + 4):
		s.place_road(Vector2i(crossx, y))  # the row y0 tile is laid over the track
	print("rail_shot: crossing at ", Vector2i(crossx, y0), " road ", s.road_at(Vector2i(crossx, y0)), " track ", s.track_at(Vector2i(crossx, y0)))
	# Homes in region B that need food, homes in region A for the staff.
	var homes := [b_origin + Vector2i(5 * sign, -3), b_origin + Vector2i(5 * sign, 2), b_origin + Vector2i(5 * sign, 5)]
	for t in homes:
		L.connect_road(s, s.buildings[s.place_building_instant("tent", t)])
	L.build(s, "tent", h + Vector2i(-4, 0))
	L.build(s, "tent", h + Vector2i(4, 0))
	L.populate(s)
	for i in 3:
		s.add_citizen()
	L.report(s, "rail")
	# Step hour by hour until a train leaves.
	var man := s.get_system(RailManifestSystem) as RailManifestSystem
	var guard := 0
	while man.ship_count() == 0 and guard < 72:
		s.step_hours(1)
		guard += 1
	if man.ship_count() == 0:
		print("rail_shot: no shipment after ", guard, " hours")
		quit(1)
		return
	var ship: Dictionary = man.shipments(s)[0]
	var span: float = float(ship["arrive_hour"]) - float(ship["depart_hour"])
	var now := float(s.clock.total_hours) + s._hour_acc / GameClock.REAL_SECONDS_PER_HOUR
	var want := float(ship["depart_hour"]) + span * 0.5 - now
	if want > 0.0:
		s.step_seconds(want * GameClock.REAL_SECONDS_PER_HOUR)
	ship = man.shipments(s)[0]
	print("rail_shot: shipment ", ship["goods"], " path ", (ship["path"] as Array).size(), " tiles, progress ",
			snappedf(ship["progress"], 0.01), " after ", guard, " hours")
	if not draw:
		main.driver.set_speed(0)
		for i in 10:  # lets TrainView and PlacementView draw once
			await process_frame
		quit()
		return
	main.driver.set_speed(0)
	# Frame the train: the path tile at the head position.
	var path: Array = ship["path"]
	var mid: Vector2i = path[clampi(int(float(ship["progress"]) * (path.size() - 1)), 0, path.size() - 1)]
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(mid) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	cam.set_zoom_step(1)
	await _shoot(OUT + "hv_67_rail_z1.png")
	cam.set_zoom_step(2)
	cam.position = (Vector2(mid) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	await _shoot(OUT + "hv_67_rail_z2.png")
	quit()
