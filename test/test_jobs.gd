extends GutTest

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _new() -> Settlement:
	return Settlement.new_game(SEED, reg)


func _footprint_free(s: Settlement, def: BuildingDef, o: Vector2i) -> bool:
	for y in range(o.y, o.y + def.size.y):
		for x in range(o.x, o.x + def.size.x):
			if not MapState.in_bounds(x, y) or s.occupancy[MapState.idx(x, y)] >= 0 or s.road_at(Vector2i(x, y)) != 0:
				return false
			if s.map.terrain_id_at(x, y) == "water" or not s.map.is_region_owned(s.map.get_region(x, y)):
				return false
	return true


## Puts a building straight into the settlement (placement rules skipped) on free tiles. When `connected`, the
## footprint touches the Hearth road network; otherwise no road is anywhere near it.
func _put(s: Settlement, def_id: String, connected: bool) -> Building:
	var def := reg.get_building(def_id)
	var road0: Vector2i = s.map.hearth_spot + Vector2i(2, 0)
	if connected:
		# Lay a straight road east of the Hearth road so several buildings can line its north side.
		for i in range(1, 12):
			s.place_road(road0 + Vector2i(i, 0))
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var o := Vector2i(x, y)
			if not _footprint_free(s, def, o):
				continue
			if connected:
				var b := s._insert_building(def, o)
				if b.connected:
					return b
				s.demolish(b.id)
			elif not _road_within(s, o, 3):
				return s._insert_building(def, o)
	return null


func _road_within(s: Settlement, o: Vector2i, r: int) -> bool:
	for y in range(o.y - r, o.y + r + 2):
		for x in range(o.x - r, o.x + r + 3):
			if s.road_at(Vector2i(x, y)) != 0:
				return true
	return false


func _tiles(def: BuildingDef, o: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in def.size.y:
		for x in def.size.x:
			out.append(o + Vector2i(x, y))
	return out


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


func _workers(s: Settlement, b: Building) -> int:
	var n := 0
	for id in s.citizens:
		var c: Citizen = s.citizens[id]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func test_start_hearth_houses_8_citizens() -> void:
	var s := _new()
	assert_eq(s.citizens.size(), 8)
	for id in s.citizens:
		assert_eq((s.citizens[id] as Citizen).home_id, s.hearth.id)


func test_higher_category_fills_first_when_short() -> void:
	var s := _new()
	var wood := _put(s, "woodcutter", true)
	var food := _put(s, "forager", true)
	var lumen := _put(s, "lumen_tap", true)
	assert_not_null(wood)
	assert_not_null(food)
	assert_not_null(lumen)
	_keep_citizens(s, 4)
	s.refresh_population()
	# 4 citizens: food 2, lumen 2; hauling (hearth) and resources get nobody.
	assert_eq(_workers(s, food), 2)
	assert_eq(_workers(s, lumen), 2)
	assert_eq(_workers(s, wood), 0)
	_keep_citizens(s, 3)
	assert_eq(_workers(s, food), 2)
	assert_eq(_workers(s, lumen), 1)


func test_priority_high_beats_normal_and_paused_gets_none() -> void:
	var s := _new()
	var a := _put(s, "forager", true)
	var b := _put(s, "forager", true)
	_keep_citizens(s, 2)
	s.refresh_population()
	assert_eq(_workers(s, a), 2, "equal priority: lower id first")
	assert_true(s.set_building_priority(b.id, "high"))
	assert_eq(_workers(s, b), 2)
	assert_eq(_workers(s, a), 0)
	assert_true(s.set_building_priority(b.id, "paused"))
	assert_eq(_workers(s, b), 0)
	assert_eq(_workers(s, a), 2)
	assert_false(s.set_building_priority(b.id, "bogus"))
	assert_true(s.set_building_priority(b.id, "low"))
	assert_false(b.paused)


func test_disconnected_building_gets_no_workers() -> void:
	var s := _new()
	var far := _put(s, "forager", false)
	assert_not_null(far)
	assert_false(far.connected)
	assert_eq(_workers(s, far), 0)
	var near := _put(s, "forager", true)
	assert_eq(_workers(s, near), 2)
	# Cutting the road frees the workers.
	var cut: Vector2i = s.map.hearth_spot + Vector2i(2, 0)
	s.remove_road(cut)
	assert_false(near.connected)
	assert_eq(_workers(s, near), 0)


func test_demolish_frees_workers_and_homes() -> void:
	var s := _new()
	var f := _put(s, "forager", true)
	assert_eq(_workers(s, f), 2)
	s.demolish(f.id)
	for id in s.citizens:
		assert_ne((s.citizens[id] as Citizen).job_id, f.id)
	var tent := _put(s, "tent", true)
	s.add_citizen()
	s.add_citizen()
	assert_eq(s.citizens.size(), 10)
	var in_tent := 0
	for id in s.citizens:
		if (s.citizens[id] as Citizen).home_id == tent.id:
			in_tent += 1
	assert_eq(in_tent, 2)
	s.demolish(tent.id)
	assert_eq(s.citizens.size(), 10, "citizens are never deleted")
	var homeless := 0
	for id in s.citizens:
		if (s.citizens[id] as Citizen).is_homeless():
			homeless += 1
	assert_eq(homeless, 2)


func _haulers(s: Settlement) -> int:
	var n := 0
	for id in s.citizens:
		if (s.citizens[id] as Citizen).job_kind == Citizen.JOB_HAUL:
			n += 1
	return n


func test_hauler_reserve_is_filled_before_food_slots() -> void:
	var s := _new()
	for i in 4:
		assert_not_null(_put(s, "forager", true))
	s.add_citizen()
	s.add_citizen()
	assert_eq(s.citizens.size(), 10)
	s.refresh_population()
	# Food slots (8) outrank hauling, but min_hauler_share 0.2 of 10 citizens keeps 2 hands on the carts.
	assert_eq(_haulers(s), 2)
	var fed := 0
	for b: Building in s.buildings.values():
		if b.def.id == "forager":
			fed += _workers(s, b)
	assert_eq(fed, 8)
