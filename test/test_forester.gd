extends GutTest
## Ticket 22b: the Forester (design.md sections 9 and 16). Plants plain grass within r5 and halves stump regrowth
## there. Planting rate and radii come from data/forest/forest.tres and the building def.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	# Nothing eats what the settlement produces, so the forest is the only thing that changes.
	s.systems.erase(s.get_system(GrowthSystem))
	h = s.map.hearth_spot
	_strip()


## A cleared, road-connected strip east of the Hearth (the same patch test_hauling and test_village_farm use).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 17):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## A finished Forester beside the road strip (so it is connected and gets its worker), or null.
func _forester() -> Building:
	for dx in range(3, 17):
		var o := Vector2i(h.x + dx, h.y - 1)
		if not s.can_place("forester", o)["ok"]:
			continue
		var id := s.place_building_instant("forester", o)
		if id < 0:
			continue
		var b: Building = s.buildings[id]
		if b.connected:
			return b
		s.demolish(id)
	return null


## Plain grass over the whole circle of radius r around `o`, except under buildings. Existing roads and channels keep
## their overlay (planting never touches them anyway).
func _paint_grass(o: Vector2i, r: int) -> void:
	for y in range(o.y - r, o.y + r + 1):
		for x in range(o.x - r, o.x + r + 1):
			if not MapState.in_bounds(x, y):
				continue
			var t := Vector2i(x, y)
			if (t - o).length_squared() > r * r or s.building_at(t) != null:
				continue
			s.set_terrain(t, "grass")


func _workers(building_id: int) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == building_id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func _forest_count() -> int:
	var fi := s.map.terrain_index("forest")
	return s.map.terrain.count(fi)


## A clear tile more than `min_d` tiles (Euclidean) from `o`, within reach of the painted patch.
func _far_tile(o: Vector2i, min_d: int) -> Vector2i:
	for y in range(o.y - 8, o.y + 9):
		for x in range(o.x - 8, o.x + 9):
			if not MapState.in_bounds(x, y):
				continue
			var t := Vector2i(x, y)
			if s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE:
				continue
			var d := (t - o).length_squared()
			if d > min_d * min_d and d <= 64:
				return t
	return Vector2i(-1, -1)


func test_forester_is_the_design_building() -> void:
	var def := reg.get_building("forester")
	assert_not_null(def)
	assert_eq([def.era, def.size, def.cost, def.worker_slots], ["village", Vector2i(1, 1), {"wood": 20}, 1])
	assert_eq(def.category, "resources")
	assert_true(def.plants_forest)
	assert_eq(def.placement_radius, 5)


# AC1: plants plain grass within r5 only, one tile per worker-day.
func test_forester_plants_one_plain_grass_tile_a_day_within_r5() -> void:
	var b := _forester()
	assert_not_null(b, "a Forester beside the road")
	if b == null:
		return
	var o := b.origin
	_paint_grass(o, 5)
	# The single plain-grass neighbour is (1, 0); every other neighbour is something planting must skip.
	var chosen := o + Vector2i(1, 0)
	s.set_terrain(o + Vector2i(-1, 0), "fertile_soil")
	s.set_terrain(o + Vector2i(0, -1), "water")
	s.set_terrain(o + Vector2i(-1, -1), "stump")
	s.set_terrain(o + Vector2i(1, 1), "forest")
	s.set_terrain(o + Vector2i(1, -1), "grass")
	s.set_blighted(o + Vector2i(1, -1), true)
	# (0, 1) and (-1, 1) lie on the road strip: grass ground, but a road overlay.
	assert_eq(s.road_at(o + Vector2i(0, 1)), Settlement.ROAD_DIRT)
	s.step_hours(1)
	assert_eq(_workers(b.id), 1, "the finished, connected Forester has its worker")
	var before := _forest_count()
	assert_eq(ForestSystem.plant_tile(s, b), chosen, "nearest plain grass, never soil, water, stump or blight")
	s.step_days(1)
	assert_eq(s.map.terrain_id_at(chosen.x, chosen.y), "forest")
	assert_eq(_forest_count(), before + 1, "one tree per worker-day, nowhere else")


# AC1: grass beyond r5 is never planted.
func test_forester_ignores_grass_outside_r5() -> void:
	var b := _forester()
	assert_not_null(b)
	if b == null:
		return
	var o := b.origin
	_paint_grass(o, 15)
	for y in range(o.y - 5, o.y + 6):
		for x in range(o.x - 5, o.x + 6):
			if not MapState.in_bounds(x, y):
				continue
			var t := Vector2i(x, y)
			if (t - o).length_squared() > 25 or s.building_at(t) != null:
				continue
			s.set_terrain(t, "rock")
	assert_eq(ForestSystem.plant_tile(s, b), Vector2i(-1, -1), "nothing plantable inside the radius")
	var before := _forest_count()
	s.step_days(1)
	assert_eq(_forest_count(), before, "the grass ring outside r5 is left alone")


# AC2: regrowth near a staffed Forester takes one season, not two.
func test_regrowth_near_a_staffed_forester_takes_half_as_long() -> void:
	var b := _forester()
	assert_not_null(b)
	if b == null:
		return
	_paint_grass(b.origin, 8)
	s.step_hours(1)
	assert_eq(_workers(b.id), 1, "the Forester is staffed")
	var near := b.origin + Vector2i(2, 0)
	var far := _far_tile(b.origin, 6)
	assert_true(near.x >= 0 and far.x >= 0, "a near and a far stump tile")
	s.set_terrain(near, "stump")
	s.set_terrain(far, "stump")
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(near.x, near.y), "forest", "one season inside r5")
	assert_eq(s.map.terrain_id_at(far.x, far.y), "stump", "two seasons outside r5")
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(far.x, far.y), "forest")
