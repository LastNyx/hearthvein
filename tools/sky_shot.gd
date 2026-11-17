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


func _try(s: Settlement, id: String, near: Vector2i, radius: int = 10) -> Building:
	return L.build(s, id, near, radius)


## Sky tiles around a footprint that are free skystone (the door ring on the island).
static func _sky_ring(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	return out


## Places an island building near `near` on the sky layer and lays the sky road that joins it to a Sky Lift (or to a sky
## road already joined). Returns the Building or null.
static func sky_build(s: Settlement, id: String, near: Vector2i, rect: Rect2i, radius: int = 8) -> Building:
	var def := s.registry.get_building(id)
	var cands: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			cands.append(near + Vector2i(dx, dy))
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - near).length_squared() < (b - near).length_squared())
	for t in cands:
		if not s.can_place(id, t, true, Building.LAYER_SKY)["ok"]:
			continue
		var fp := Rect2i(t, def.size)
		var path := _sky_path(s, fp, rect)
		if path.is_empty():
			continue
		var bid := s.place_building_instant(id, t, Building.LAYER_SKY)
		if bid < 0:
			continue
		for rt in path:
			s.place_road(rt, Settlement.ROAD_DIRT, Building.LAYER_SKY)
		return s.buildings[bid]
	print("sky_shot: could not place ", id, " on the island near ", near)
	return null


static func _lift_ring_ok(s: Settlement, t: Vector2i) -> bool:
	for d in L.DIRS:
		var b := s.building_at(t + d, Building.LAYER_SKY)
		if b != null and b.def.sky_lift:
			return true
		if s.sky_roads[MapState.idx(t.x + d.x, t.y + d.y)] != 0 if MapState.in_bounds(t.x + d.x, t.y + d.y) else false:
			return true
	return false


## Sky road tiles to lay from the footprint's ring to a tile touching a lift or an existing sky road ([] if none).
static func _sky_path(s: Settlement, fp: Rect2i, rect: Rect2i) -> Array[Vector2i]:
	var prev := {}
	var queue: Array[Vector2i] = []
	for t in _sky_ring(fp):
		if rect.has_point(t) and s.can_place_road(t, Building.LAYER_SKY):
			if s.sky_roads[MapState.idx(t.x, t.y)] != 0:
				return []  # already road: reachable, nothing to lay (handled as an empty path below)
			prev[t] = L.NONE
			queue.append(t)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if _lift_ring_ok(s, c):
			var out: Array[Vector2i] = []
			var cur := c
			while cur != L.NONE:
				out.append(cur)
				cur = prev[cur]
			return out
		for d in L.DIRS:
			var n := c + d
			if fp.has_point(n) or not rect.has_point(n) or prev.has(n):
				continue
			if s.can_place_road(n, Building.LAYER_SKY):
				prev[n] = c
				queue.append(n)
	return []


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
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	s.era_current = "skyborne"
	(main.get_node("Hud") as Hud)._rebuild_categories()
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("materials", 900.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("food", 900.0)
	s.hearth.inventory.add("lumen", 600.0)
	# Lumen grid first (the island draws from the grid of its Lift Anchor)
	_try(s, "lumen_reactor", h + Vector2i(-14, -4), 16)
	_try(s, "lumen_nexus", h + Vector2i(8, -6), 10)
	_try(s, "lumen_pylon", h + Vector2i(4, -5), 6)
	_try(s, "lumen_pylon", h + Vector2i(12, -2), 6)
	_try(s, "grid_battery", h + Vector2i(1, -5), 6)
	# Housing, water and food
	_try(s, "apartment_block", h + Vector2i(-4, 0))
	_try(s, "apartment_block", h + Vector2i(-7, 0))
	_try(s, "rowhouse", h + Vector2i(-10, 0))
	_try(s, "water_tower", h + Vector2i(-2, 5), 8)
	_try(s, "grand_bazaar", h + Vector2i(3, 0))
	_try(s, "greenhouse", h + Vector2i(-12, 3))
	_try(s, "well", h + Vector2i(2, 7), 12)
	_try(s, "handcart_shed", h + Vector2i(8, 3))
	_try(s, "airship_dock", h + Vector2i(11, 7), 10)
	_try(s, "sky_foundry", h + Vector2i(-12, -8), 12)
	# The anchor and its island (instant placement raises it at once); the anchor is joined to the Hearth by road
	var anchor := _try(s, "lift_anchor", h + Vector2i(8, -10), 12)
	var isys := s.get_system(IslandSystem) as IslandSystem
	var isl: Island = isys.island_of_anchor(anchor.id) if anchor != null else null
	if isl == null:
		print("sky_shot: no island raised")
		quit(1)
		return
	L.pave_near_hearth(s, 9)
	# Two Sky Lifts on the ground under the island, each road-linked; then sky roads and the island dock
	var c := isl.rect.get_center()
	var lift1 := _try(s, "sky_lift", Vector2i(c.x - 4, c.y), 10)
	var lift2 := _try(s, "sky_lift", Vector2i(c.x + 4, c.y + 1), 10)
	for lift in [lift1, lift2]:
		if lift == null:
			continue
		var o: Vector2i = lift.origin
		# a short sky road spur beside the lift
		for d in range(1, 4):
			s.place_road(o + Vector2i(0, -d), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	if lift1 != null and lift2 != null:  # the two lifts joined by a sky road along the island's middle row
		var a := lift1.origin
		var b := lift2.origin
		for x in range(a.x, b.x + 1):
			s.place_road(Vector2i(x, a.y - 1), Settlement.ROAD_DIRT, Building.LAYER_SKY)
		for y in range(mini(a.y, b.y) - 1, maxi(a.y, b.y) + 1):
			s.place_road(Vector2i(b.x, y), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	# Every Skyborne building on the island, each joined to the lift spine by a sky road (targets are island-relative)
	var p := isl.rect.position
	var placed := {}
	for spec: Array in [["skyspire", Vector2i(1, 2)], ["cloud_cistern", Vector2i(4, 3)], ["sky_garden", Vector2i(7, 2)],
			["aether_collector", Vector2i(11, 2)], ["skyforge", Vector2i(1, 8)], ["observatory", Vector2i(5, 8)]]:
		placed[spec[0]] = sky_build(s, spec[0], p + (spec[1] as Vector2i), isl.rect, 3)
	var dock := sky_build(s, "airship_dock", p + Vector2i(8, 8), isl.rect, 3)
	placed["airship_dock"] = dock
	placed["dawn_beacon"] = _try(s, "dawn_beacon", anchor.origin + Vector2i(-6, 4), 8)
	for k in placed:
		if placed[k] == null:
			print("sky_shot: NOT PLACED ", k)
	L.populate(s)
	JobSystem.refresh(s)
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
