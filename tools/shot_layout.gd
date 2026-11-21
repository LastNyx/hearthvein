extends RefCounted
## Shared layout helpers for the era shot scripts (ticket 65): place buildings on clear ground and link each one to the
## Hearth with dirt road laid tile by tile through the normal Settlement commands, routing around forest and water the
## way a player would. Only place_building_instant is a debug path (no construction time).

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const NONE := Vector2i(-9999, -9999)


static func ring(b: Building) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := b.footprint()
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	return out


## Places `id` on the free spot nearest `near` (within radius) whose door ring can be linked to the Hearth by road,
## then lays that road. Returns the Building or null.
static func build(s: Settlement, id: String, near: Vector2i, radius: int = 10) -> Building:
	var def := s.registry.get_building(id)
	var cands: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			cands.append(near + Vector2i(dx, dy))
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - near).length_squared()
		var db := (b - near).length_squared()
		if da != db:
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for t in cands:
		if not s.can_place(id, t, true)["ok"]:
			continue
		var fp := Rect2i(t, def.size)
		if _path(s, fp).is_empty():
			continue
		var bid := s.place_building_instant(id, t)
		if bid < 0:
			continue
		var b: Building = s.buildings[bid]
		connect_road(s, b)
		if not b.connected:
			print("shot_layout: ", id, " at ", t, " could not be linked by road")
		return b
	print("shot_layout: could not place ", id, " near ", near)
	return null


static func _rect_ring(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	return out


## Road tiles to lay so a building on `fp` touches a road that reaches the Hearth. [] when impossible; one tile
## (already road) when it touches a road at once.
static func _path(s: Settlement, fp: Rect2i) -> Array[Vector2i]:
	var goal_ring := {}
	for t in ring(s.hearth):
		goal_ring[t] = true
	var prev := {}
	var queue: Array[Vector2i] = []
	for t in _rect_ring(fp):
		if s.road_at(t) != Settlement.ROAD_NONE:
			return [t]
		if s.can_place_road(t) and not prev.has(t):
			prev[t] = NONE
			queue.append(t)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if goal_ring.has(c) or _touches_road(s, c):
			var out: Array[Vector2i] = []
			var cur := c
			while cur != NONE:
				out.append(cur)
				cur = prev[cur]
			return out
		for d in DIRS:
			var n := c + d
			if fp.has_point(n):
				continue
			if not prev.has(n) and s.road_at(n) == Settlement.ROAD_NONE and s.can_place_road(n):
				prev[n] = c
				queue.append(n)
	return []


## Lays the road that links a placed building.
static func connect_road(s: Settlement, b: Building) -> bool:
	if b.connected:
		return true
	for t in _path(s, b.footprint()):
		s.place_road(t)
	return b.connected


static func _touches_road(s: Settlement, t: Vector2i) -> bool:
	for d in DIRS:
		if s.road_at(t + d) != Settlement.ROAD_NONE:
			return true
	return false


## Paves every dirt road tile within `dist` (Manhattan) of the Hearth origin.
static func pave_near_hearth(s: Settlement, dist: int) -> void:
	var h := s.hearth.origin
	for y in range(h.y - dist, h.y + dist + 1):
		for x in range(h.x - dist, h.x + dist + 1):
			var t := Vector2i(x, y)
			if absi(x - h.x) + absi(y - h.y) <= dist and s.road_at(t) == Settlement.ROAD_DIRT:
				s.pave_road(t)


## One citizen per free bed, so the jobs fill.
static func populate(s: Settlement) -> void:
	var want := s.beds_total() - s.citizens.size()
	for i in maxi(want, 0):
		s.add_citizen()


## Prints every finished building that is not road-connected or has worker slots but no assigned worker.
static func report(s: Settlement, label: String) -> void:
	var bad := 0
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site:
			continue
		var staffed := 0
		for cid in s.citizens:
			var c: Citizen = s.citizens[cid]
			if c.job_id == bid and c.job_kind == Citizen.JOB_WORK:
				staffed += 1
		var slots := ProductionSystem.worker_slots_for(s, b)
		if not b.connected or (slots > 0 and staffed == 0):
			bad += 1
			print(label, " PROBLEM: ", b.def.id, " at ", b.origin, " connected=", b.connected, " workers=", staffed, "/", slots)
	print(label, ": ", s.buildings.size(), " buildings, ", s.citizens.size(), " citizens, ", bad, " unconnected or unstaffed")


## A track spur of up to 8 tiles off the depot's long side, in whichever direction and row runs longest, with a road
## crossing it (level crossing) a few tiles out.
static func _spur(s: Settlement, depot: Building) -> void:
	var r := depot.footprint()
	var best: Array[Vector2i] = []
	for d in DIRS:
		for start in ring(depot):
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


## The Conflux shot layout (ticket 39d): city set plus Lumen grid, Vein Bore, rail spur and Sky Foundry. Needs era conflux,
## all regions owned and the Hearth stocked first (the shot scripts and tools/frame_probe.gd do that).
static func conflux(s: Settlement) -> void:
	var h := s.map.hearth_spot
	# Vein buildings first: veins are scarce and the other buildings would cover them.
	build(s, "vein_bore", h + Vector2i(14, -4), 16)
	build(s, "lumen_reactor", h + Vector2i(-14, -4), 16)
	var depot := build(s, "rail_depot", h + Vector2i(6, 10), 6)  # early, in open ground, so the spur has room
	build(s, "lumen_nexus", h + Vector2i(8, -6), 10)
	build(s, "lumen_pylon", h + Vector2i(4, -5), 6)
	build(s, "lumen_pylon", h + Vector2i(12, -2), 6)
	build(s, "lumen_pylon", h + Vector2i(-3, -6), 6)
	build(s, "grid_battery", h + Vector2i(1, -5), 6)
	# Housing, water and food
	build(s, "apartment_block", h + Vector2i(-4, 0))
	build(s, "apartment_block", h + Vector2i(-7, 0))
	build(s, "rowhouse", h + Vector2i(-10, 0))
	build(s, "conduit_terraces", h + Vector2i(-6, 5), 8)
	build(s, "water_tower", h + Vector2i(-2, 5), 8)
	build(s, "hydroponic_hall", h + Vector2i(-4, 5), 10)  # wet from the tower's radius
	build(s, "grand_bazaar", h + Vector2i(3, 0))
	build(s, "greenhouse", h + Vector2i(-12, 3))
	build(s, "well", h + Vector2i(2, 7), 12)
	# Logistics and the landmark
	build(s, "handcart_shed", h + Vector2i(8, 3))
	build(s, "airship_dock", h + Vector2i(11, 7), 10)
	build(s, "sky_foundry", h + Vector2i(-12, -8), 12)
	pave_near_hearth(s, 9)
	if depot != null:
		_spur(s, depot)
	populate(s)


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
	for d in DIRS:
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
			prev[t] = NONE
			queue.append(t)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if _lift_ring_ok(s, c):
			var out: Array[Vector2i] = []
			var cur := c
			while cur != NONE:
				out.append(cur)
				cur = prev[cur]
			return out
		for d in DIRS:
			var n := c + d
			if fp.has_point(n) or not rect.has_point(n) or prev.has(n):
				continue
			if s.can_place_road(n, Building.LAYER_SKY):
				prev[n] = c
				queue.append(n)
	return []


## The Skyborne shot layout (ticket 40d). Returns {island, anchor, dock, lift1, lift2} (island null when none raised).
static func sky(s: Settlement) -> Dictionary:
	var h := s.map.hearth_spot
	# Lumen grid first (the island draws from the grid of its Lift Anchor)
	build(s, "lumen_reactor", h + Vector2i(-14, -4), 16)
	build(s, "lumen_nexus", h + Vector2i(8, -6), 10)
	build(s, "lumen_pylon", h + Vector2i(4, -5), 6)
	build(s, "lumen_pylon", h + Vector2i(12, -2), 6)
	build(s, "grid_battery", h + Vector2i(1, -5), 6)
	# Housing, water and food
	build(s, "apartment_block", h + Vector2i(-4, 0))
	build(s, "apartment_block", h + Vector2i(-7, 0))
	build(s, "rowhouse", h + Vector2i(-10, 0))
	build(s, "water_tower", h + Vector2i(-2, 5), 8)
	build(s, "grand_bazaar", h + Vector2i(3, 0))
	build(s, "greenhouse", h + Vector2i(-12, 3))
	build(s, "well", h + Vector2i(2, 7), 12)
	build(s, "handcart_shed", h + Vector2i(8, 3))
	build(s, "airship_dock", h + Vector2i(11, 7), 10)
	build(s, "sky_foundry", h + Vector2i(-12, -8), 12)
	# The anchor and its island (instant placement raises it at once); the anchor is joined to the Hearth by road
	var anchor := build(s, "lift_anchor", h + Vector2i(8, -10), 12)
	var isys := s.get_system(IslandSystem) as IslandSystem
	var isl: Island = isys.island_of_anchor(anchor.id) if anchor != null else null
	if isl == null:
		print("sky_shot: no island raised")
		return {}
	pave_near_hearth(s, 9)
	# Two Sky Lifts on the ground under the island, each road-linked; then sky roads and the island dock
	var c := isl.rect.get_center()
	var lift1 := build(s, "sky_lift", Vector2i(c.x - 4, c.y), 10)
	var lift2 := build(s, "sky_lift", Vector2i(c.x + 4, c.y + 1), 10)
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
	placed["dawn_beacon"] = build(s, "dawn_beacon", anchor.origin + Vector2i(-6, 4), 8)
	for k in placed:
		if placed[k] == null:
			print("sky_shot: NOT PLACED ", k)
	populate(s)
	JobSystem.refresh(s)
	return {"island": isl, "anchor": anchor, "dock": dock, "lift1": lift1, "lift2": lift2}
