extends GutTest

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ws: WalkerSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	ws = s.get_system(WalkerSystem)
	s.step_seconds(0.01)  # creates the walkers
	ws.walker_of(0).controlled = true  # keep the hour schedule off the walker the tests drive


## A free horizontal strip of `len` tiles on grass, east of the Hearth, away from buildings.
func _strip(len: int) -> Vector2i:
	for y in range(s.map.hearth_spot.y - 12, s.map.hearth_spot.y + 12):
		for x in range(s.map.hearth_spot.x - 24, s.map.hearth_spot.x + 24):
			var ok := true
			for i in range(-1, len + 2):
				var p := Vector2i(x + i, y)
				for dy in [-1, 0, 1]:
					var q := Vector2i(p.x, p.y + dy)
					if not MapState.in_bounds(q.x, q.y) or not reg.get_terrain(s.map.terrain_id_at(q.x, q.y)).buildable \
							or s.building_at(q) != null or s.road_at(q) != 0 or not s.map.is_region_owned(s.map.get_region(q.x, q.y)):
						ok = false
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _walk_time(from: Vector2i, to: Vector2i) -> float:
	ws.place_walker(0, from)
	assert_true(ws.walk_to_tile(0, to))
	var w := ws.walker_of(0)
	var t := 0.0
	while w.is_walking() and t < 100.0:
		s.step_seconds(0.01)
		t += 0.01
	return t


func test_default_systems_registered_once() -> void:
	assert_not_null(ws)
	var n := 0
	for sys in s.systems:
		if sys is WalkerSystem:
			n += 1
	assert_eq(n, 1)
	assert_eq(ws.walkers.size(), s.citizens.size())


func test_walk_time_dirt_and_grass() -> void:
	var o := _strip(10)
	assert_ne(o, Vector2i(-1, -1))
	var end := o + Vector2i(10, 0)
	assert_almost_eq(_walk_time(o, end), 10.0, 0.05, "grass 1.0 tiles/s")
	for i in range(0, 11):
		assert_true(s.place_road(o + Vector2i(i, 0)))
	assert_almost_eq(_walk_time(o, end), 6.67, 0.05, "dirt 1.5 tiles/s")
	for i in range(0, 11):
		s.place_road(o + Vector2i(i, 0), Settlement.ROAD_PAVED)
	assert_almost_eq(_walk_time(o, end), 5.0, 0.05, "paved 2.0 tiles/s")


func test_speeds_come_from_data() -> void:
	assert_eq(reg.get_road("dirt").walk_speed, 1.5)
	assert_eq(reg.get_road("paved").walk_speed, 2.0)
	assert_eq(reg.get_terrain("grass").walk_speed, 1.0)
	assert_eq(reg.get_terrain("water").walk_speed, 0.0)


func test_step_hours_moves_walkers() -> void:
	var o := _strip(10)
	ws.place_walker(0, o)
	ws.walk_to_tile(0, o + Vector2i(10, 0))
	s.step_hours(1)  # 2.5 s
	var w := ws.walker_of(0)
	assert_almost_eq(w.position().x - (o.x + 0.5), 2.5, 0.02)
	s.step_hours(4)
	assert_false(w.is_walking())


func test_worker_not_at_work_while_walking() -> void:
	var tent := s.place_building_instant("tent", _tent_spot())
	var wc := s.place_building_instant("woodcutter", _free_spot("woodcutter"))
	assert_true(tent >= 0 and wc >= 0, "setup")
	# Connect the woodcutter so it takes workers.
	_connect(s.buildings[wc])
	s.refresh_population()
	var worker: Citizen = null
	for id in s.citizens:
		if s.citizens[id].job_id == wc:
			worker = s.citizens[id]
	assert_not_null(worker, "someone works at the woodcutter")
	s.step_hours(3)  # hour 3: everybody is at home or the Hearth
	assert_false(ws.is_at_work(worker.id))
	var walking_seen := false
	var at_work_seen := false
	var bad := false
	for i in 400:  # hours 3.. 3+ 400*0.5 s
		s.step_seconds(0.5)
		var w := ws.walker_of(worker.id)
		if w.is_walking():
			walking_seen = true
			if ws.is_at_work(worker.id):
				bad = true
		elif ws.is_at_work(worker.id):
			at_work_seen = true
	assert_true(walking_seen)
	assert_true(at_work_seen, "arrives at work during work hours")
	assert_false(bad, "walking is never at work")
	assert_eq(ws.workers_at(wc).size() > 0, ws.is_at_work(worker.id))


func _free_spot(def_id: String) -> Vector2i:
	var h := s.map.hearth_spot
	for r in range(4, 20):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place(def_id, Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _tent_spot() -> Vector2i:
	return _free_spot("tent")


func _connect(b: Building) -> void:
	var h := s.map.hearth_spot
	var from := Vector2i(h.x + s.hearth.def.size.x, h.y)
	var target := b.origin + Vector2i(0, b.def.size.y)  # tile south of the building
	var p := Vector2i(from)
	while p.x != target.x:
		p.x += signi(target.x - p.x)
		s.place_road(p)
	while p.y != target.y:
		p.y += signi(target.y - p.y)
		s.place_road(p)
	# also the tile west/east side in case the target is blocked
	s.place_road(target)
	s.refresh_population()


func test_path_replans_after_road_removed() -> void:
	var o := _strip(10)
	var end := o + Vector2i(10, 0)
	for i in range(0, 11):
		s.place_road(o + Vector2i(i, 0))
	var before := ws.find_path(o, end)
	assert_almost_eq(ws.path_seconds(before), 6.67, 0.02)
	var cached := ws.find_path(o, end)
	var runs := ws.path_computations
	ws.find_path(o, end)
	assert_eq(ws.path_computations, runs, "second lookup is cached")
	ws.place_walker(0, o)
	ws.walk_to_tile(0, end)
	s.step_seconds(2.0)
	assert_true(s.remove_road(o + Vector2i(6, 0)))
	var w := ws.walker_of(0)
	var after := ws.find_path(o, end)
	assert_gt(ws.path_computations, runs, "cache dropped by the road change")
	assert_almost_eq(ws.path_seconds(after), 9.0 / 1.5 + 1.0, 0.02)
	var t := 0.0
	while w.is_walking() and t < 100.0:
		s.step_seconds(0.05)
		t += 0.05
	assert_almost_eq(t + 2.0, 9.0 / 1.5 + 1.0, 0.1, "walker used the re-planned path, grass tile now costs 1 s")
	assert_eq(w.tile, end)


func test_path_avoids_new_building_and_walks_around() -> void:
	var o := _strip(10)
	var end := o + Vector2i(10, 0)
	var p0 := ws.find_path(o, end)
	assert_eq(p0.size(), 11)
	var blocker := o + Vector2i(5, 0)
	var spot_ok: bool = s.can_place("tent", blocker)["ok"]
	assert_true(spot_ok)
	assert_gt(s.place_building_instant("tent", blocker), -1)
	var p1 := ws.find_path(o, end)
	assert_false(p1.has(blocker))
	assert_eq(p1.size(), 13)


func test_door_is_only_way_into_building() -> void:
	var spot := _free_spot("tent")
	var id := s.place_building_instant("tent", spot)
	var b: Building = s.buildings[id]
	var door := ws.door_tile(b)
	assert_eq(door, spot)
	ws.place_walker(0, spot + Vector2i(0, 3))
	assert_true(ws.walk_to_building(0, id))
	s.step_hours(2)
	assert_eq(ws.walker_of(0).at_building, id)
	assert_eq(ws.walker_of(0).tile, door)
	# Other buildings still block: path through the Hearth footprint is not allowed.
	var hb := s.hearth.footprint()
	var through := ws.find_path(Vector2i(hb.position.x - 1, hb.position.y + 1), Vector2i(hb.end.x, hb.position.y + 1))
	for t in through:
		assert_false(hb.has_point(t) and t != ws.door_tile(s.hearth) and t != through[0] and t != through[-1])


func test_citizens_commute_home_work() -> void:
	# Explicit layout (independent of the generated map): a grass block east of the Hearth with one forest tile.
	var h := s.map.hearth_spot
	for y in range(h.y - 2, h.y + 6):
		for x in range(h.x + 3, h.x + 12):
			s.set_terrain(Vector2i(x, y), "grass")
	s.set_terrain(Vector2i(h.x + 9, h.y + 1), "forest")
	var wc := s.place_building_instant("woodcutter", Vector2i(h.x + 7, h.y + 1))
	assert_gt(wc, 0, "woodcutter placed")
	_connect(s.buildings[wc])
	for i in 3:
		s.place_building_instant("tent", _free_spot("tent"))
	s.refresh_population()
	var worker: Citizen = null
	for id in s.citizens:
		if s.citizens[id].job_id == wc:
			worker = s.citizens[id]
	assert_not_null(worker)
	s.step_hours(5)
	var ww := ws.walker_of(worker.id)
	assert_eq(ww.at_building, worker.home_id, "home at night")
	s.step_hours(5)  # hour 10, the walk from 6 is done
	assert_true(ws.is_at_work(worker.id))
	s.step_hours(12)  # hour 22, home again
	assert_false(ws.is_at_work(worker.id))
	assert_eq(ws.walker_of(worker.id).at_building, worker.home_id)


func test_hour_tick_survives_one_citizen_leaving_as_another_arrives() -> void:
	var gone: int = s.citizens.keys().back()
	assert_true(s.remove_citizen(gone))
	var fresh := s.add_citizen()  # same head count, different ids
	assert_eq(ws.walkers.size(), s.citizens.size())
	ws.on_hour(s)
	assert_false(ws.walkers.has(gone), "the departed walker is dropped")
	assert_true(ws.walkers.has(fresh), "the newcomer has a walker")
