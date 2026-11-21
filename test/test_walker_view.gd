extends GutTest
## Ticket 156: builders at work stand on land beside the site or clear tile, face the work and swing while the shift runs.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ws: WalkerSystem
var cs: ConstructionSystem
var h: Vector2i
var view: WalkerView


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	h = s.map.hearth_spot
	ws = s.get_system(WalkerSystem)
	cs = s.get_system(ConstructionSystem)
	s.step_seconds(0.01)  # creates the walkers
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 6, h.y + 6):
			s.set_terrain(Vector2i(x, y), "grass")
	view = WalkerView.new()
	add_child_autofree(view)
	view.setup(s)


func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / ArtLibrary.TILE), floori(p.y / ArtLibrary.TILE))


## A Meeting Hall site with road on its north side and a river along its south side, `n` walkers on its crew.
func _river_site(n: int) -> Array:
	var def := reg.get_building("meeting_hall")
	var o := Vector2i(h.x + 6, h.y)
	for x in range(o.x - 3, o.x + def.size.x + 3):
		s.place_road(Vector2i(x, o.y - 1))
		for y in range(o.y + def.size.y, o.y + def.size.y + 3):
			s.set_terrain(Vector2i(x, y), "water")
	var bid := s.place_building("meeting_hall", o)
	assert_true(bid >= 0, "site placed")
	var out: Array = []
	for cid in ws.walkers.keys().slice(0, n):
		var w: Walker = ws.walkers[cid]
		w.controlled = true
		w.path.clear()
		w.at_building = bid
		cs.crews[cid] = bid
		out.append(w)
	return out


func _at_hour(hour: int) -> void:
	s.clock.total_hours = 24 + hour  # the clock only; no sim step, so the crews are left as set up


func test_site_crew_stands_on_land_outside_the_footprint() -> void:
	var crew := _river_site(8)
	var b: Building = s.buildings[crew[0].at_building]
	var seen := {}
	for w in crew:
		var pose: Dictionary = view.crew_pose(w)
		assert_false(pose.is_empty(), "a site crew member has a pose")
		var t := _tile_of(pose["p"])
		seen[t] = true
		assert_false(b.footprint().has_point(t), "%s outside the footprint" % t)
		assert_false(s.is_water_tile(t), "%s is not water" % t)
		assert_true(ws.tile_speed(t) > 0.0, "%s is walkable" % t)
		assert_eq(s.building_at(t), null, "%s is free of buildings" % t)
	assert_true(seen.size() > 1, "the crew spreads over several tiles")


func test_clear_crew_stands_beside_the_tile_facing_it() -> void:
	var tile := Vector2i(h.x + 8, h.y)
	s.set_terrain(tile, "forest")
	var cid: int = ws.walkers.keys()[0]
	var w: Walker = ws.walkers[cid]
	w.controlled = true
	ws.place_walker(cid, tile)
	cs.crews[cid] = ConstructionSystem.clear_work_id(MapState.idx(tile.x, tile.y))
	var pose: Dictionary = view.crew_pose(w)
	assert_false(pose.is_empty())
	var t := _tile_of(pose["p"])
	assert_ne(t, tile, "not on the tile being cleared")
	assert_eq(maxi(absi(t.x - tile.x), absi(t.y - tile.y)), 1, "on a neighbour")
	var d := Vector2(tile - t)
	assert_eq(pose["dir"], ArtLibrary.facing_for(d), "faces the clear tile")


func test_swing_runs_in_shift_and_not_at_night() -> void:
	var crew := _river_site(1)
	_at_hour(12)
	var frames := {}
	for i in 20:
		var pose: Dictionary = view.crew_pose(crew[0], 0.1 * i)
		assert_true(pose["working"])
		frames[pose["frame"]] = true
	assert_true(frames.size() > 1, "frames change over time during the shift")
	_at_hour(22)
	frames.clear()
	for i in 20:
		var pose: Dictionary = view.crew_pose(crew[0], 0.1 * i)
		assert_false(pose["working"])
		frames[pose["frame"]] = true
	assert_eq(frames.size(), 1, "at night the crew stands")


func test_spots_are_stable_per_citizen() -> void:
	var crew := _river_site(4)
	var first: Array = []
	for w in crew:
		first.append(view.crew_pose(w)["p"])
	for i in crew.size():
		assert_eq(view.crew_pose(crew[i], 5.0)["p"], first[i], "same place later")
	var v2 := WalkerView.new()
	add_child_autofree(v2)
	v2.setup(s)
	for i in crew.size():
		assert_eq(v2.crew_pose(crew[i])["p"], first[i], "same place in a fresh view")
