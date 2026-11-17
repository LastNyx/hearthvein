extends GutTest
## Ticket 30c: the Handcart Shed (design.md sections 8 and 16 Town). A completed shed raises every hauler in its
## region to 15 units carried and gives those haulers 1.25x speed on paved tiles (2.5 tiles/s).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ws: WalkerSystem
var hs: HaulingSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	ws = s.get_system(WalkerSystem) as WalkerSystem
	hs = s.get_system(HaulingSystem) as HaulingSystem
	h = s.map.hearth_spot
	# The same cleared strip test_hauling uses: forest east of the Hearth cleared and a road laid.
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 2, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.hearth.inventory.add("cut_stone", 2.0)  # paving a tile in the speed test


func _put(id: String, dx: int, side: int = -1) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(h.x + dx, h.y - def.size.y if side < 0 else h.y + 1)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	return s.buildings.get(bid)


# AC1a: the data row is the Town table's.
func test_data_matches_the_town_table() -> void:
	var d := reg.get_building("handcart_shed")
	assert_not_null(d)
	assert_eq([d.era, d.category], ["town", "logistics"])
	assert_eq([d.size, d.cost], [Vector2i(2, 1), {"materials": 40, "planks": 20}])
	assert_eq([d.worker_slots, d.upkeep_lumen], [0, 1.0])
	assert_eq([d.region_haul_load, d.paved_haul_speed_factor], [15.0, 1.25])
	assert_false(d.upgradable)


func test_handcart_shed_is_a_town_unlock() -> void:
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("handcart_shed"))
	s.era_override = "village"
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("handcart_shed"), "Town set only")


# AC1b: the carry rises in the shed's region only.
func test_load_is_raised_only_in_the_shed_region() -> void:
	var shed := _put("handcart_shed", 9)
	var r := s.map.get_region(shed.origin.x, shed.origin.y)
	var other := -1
	for i in MapState.REGION_COUNT:
		if i != r:
			other = i
			break
	assert_gt(other, -1, "the map has another region")
	assert_almost_eq(RegionSystem.haul_load_in(s, r), 15.0, 0.0001, "its region carries 15")
	assert_almost_eq(RegionSystem.haul_load_in(s, other), 10.0, 0.0001, "other regions stay at 10")


# AC1c: a shed still being built gives nothing; it counts once completed.
func test_only_completed_sheds_count() -> void:
	var bid := s.place_building("handcart_shed", Vector2i(h.x + 9, h.y - 1))
	assert_gt(bid, -1, "site placed")
	var b: Building = s.buildings[bid]
	assert_true(b.site)
	var r := s.map.get_region(b.origin.x, b.origin.y)
	assert_almost_eq(RegionSystem.haul_load_in(s, r), 10.0, 0.0001, "a site gives nothing")
	s.complete_site(b)
	assert_false(b.site)
	assert_almost_eq(RegionSystem.haul_load_in(s, r), 15.0, 0.0001, "completed: 15")


# AC1d: end to end, a hauler in the shed region plans a 15-unit trip (not the foot load of 5).
func test_hauler_plans_fifteen_unit_trips() -> void:
	var f := _put("forager", 4)
	_put("storehouse", 6)
	_put("handcart_shed", 9)
	f.door_buffer.add("food", 20.0)
	s.set_building_priority(f.id, "paused")  # no new production, only the 20 units to carry
	s.step_hours(6)  # the shift starts and a hauler takes the trip
	var biggest := 0.0
	for i in 120:
		s.step_seconds(0.5)
		for cid in hs.trips:
			biggest = maxf(biggest, (hs.trips[cid] as HaulingSystem.Trip).planned)
	assert_almost_eq(biggest, 15.0, 0.001, "one trip carries 15, the rest of the 20 follows")


## A free horizontal strip of `len` tiles, away from buildings and roads (test_walkers' search).
func _strip(len: int) -> Vector2i:
	for y in range(h.y - 12, h.y + 12):
		for x in range(h.x - 24, h.x + 24):
			var ok := true
			for i in range(-1, len + 2):
				var p := Vector2i(x + i, y)
				for dy in [-1, 0, 1]:
					var q := Vector2i(p.x, p.y + dy)
					if not MapState.in_bounds(q.x, q.y) or not reg.get_terrain(s.map.terrain_id_at(q.x, q.y)).buildable \
							or s.building_at(q) != null or s.road_at(q) != 0 \
							or not s.map.is_region_owned(s.map.get_region(q.x, q.y)):
						ok = false
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A walker standing at `from` starting into `to`; true once the entry is complete.
func _cross(from: Vector2i, to: Vector2i, cid: int) -> bool:
	var w := ws.walker_of(cid)
	ws.place_walker(cid, from)
	w.controlled = true
	w.path = [to] as Array[Vector2i]
	w.progress = 0.0
	return w.tile == to


# AC2: a handcart hauler crosses a paved tile in 1/2.5 s; other walkers take 1/2.0 s.
func test_handcart_haulers_move_faster_on_paved() -> void:
	_put("handcart_shed", 9)  # before the strip search, so it is not chosen as the walk row
	var o := _strip(10)
	assert_ne(o, Vector2i(-1, -1), "found a free strip")
	var from := o
	var paved := o + Vector2i(1, 0)
	assert_true(s.pave_road(paved), "the second tile is paved")
	s.step_seconds(0.01)  # creates the walkers
	ws.tile_speed(paved)  # build the A* grid before the manual paths, so no re-plan overwrites them
	var haul_id := 0
	var work_id := 1
	var hc: Citizen = s.citizens[haul_id]
	hc.job_kind = Citizen.JOB_HAUL
	hc.job_id = s.hearth.id
	var wc: Citizen = s.citizens[work_id]
	wc.job_kind = Citizen.JOB_WORK
	wc.job_id = -1

	# Handcart hauler: 1 / 2.5 = 0.4 s across the paved tile.
	assert_false(_cross(from, paved, haul_id))
	ws.on_seconds(s, 0.39)
	assert_eq(ws.walker_of(haul_id).tile, from, "not across at 0.39 s")
	ws.on_seconds(s, 0.02)
	assert_eq(ws.walker_of(haul_id).tile, paved, "across at 0.41 s (2.5 tiles/s)")

	# An ordinary walker on the same tile: 1 / 2.0 = 0.5 s.
	assert_false(_cross(from, paved, work_id))
	ws.on_seconds(s, 0.48)
	assert_eq(ws.walker_of(work_id).tile, from, "not across at 0.48 s")
	ws.on_seconds(s, 0.03)
	assert_eq(ws.walker_of(work_id).tile, paved, "across at 0.51 s (2.0 tiles/s)")
