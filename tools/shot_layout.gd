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
		var slots := b.effective_worker_slots(s.registry)
		if not b.connected or (slots > 0 and staffed == 0):
			bad += 1
			print(label, " PROBLEM: ", b.def.id, " at ", b.origin, " connected=", b.connected, " workers=", staffed, "/", slots)
	print(label, ": ", s.buildings.size(), " buildings, ", s.citizens.size(), " citizens, ", bad, " unconnected or unstaffed")
