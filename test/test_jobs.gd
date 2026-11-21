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
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the small-town first hand (118) has its own test below
	var s := _new()
	var wood := _put(s, "woodcutter", true)
	var food := _put(s, "forager", true)
	var lumen := _put(s, "lumen_tap", true)
	assert_not_null(wood)
	assert_not_null(food)
	assert_not_null(lumen)
	_keep_citizens(s, 4)
	s.refresh_population()
	# 4 citizens: the hauler reserve (min_hauler_share 0.3, 1 hand) goes first, then food 2, lumen 1; resources get nobody.
	assert_eq(_workers(s, food), 2)
	assert_eq(_workers(s, lumen), 1)
	assert_eq(_workers(s, wood), 0)
	_keep_citizens(s, 3)
	assert_eq(_workers(s, food), 2)
	assert_eq(_workers(s, lumen), 1)
	reg.logistics.small_town_pop = small


func test_priority_high_beats_normal_and_paused_gets_none() -> void:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the small-town first hand (118) has its own test below
	var s := _new()
	var a := _put(s, "forager", true)
	var b := _put(s, "forager", true)
	_keep_citizens(s, 2)
	s.refresh_population()
	assert_eq([_workers(s, a), _workers(s, b)], [1, 1], "equal priority: the two share the two citizens")
	assert_true(s.set_building_priority(b.id, "high"))
	assert_eq(_workers(s, b), 2)
	assert_eq(_workers(s, a), 0)
	assert_true(s.set_building_priority(b.id, "paused"))
	assert_eq(_workers(s, b), 0)
	assert_eq(_workers(s, a), 2)
	assert_false(s.set_building_priority(b.id, "bogus"))
	assert_true(s.set_building_priority(b.id, "low"))
	assert_false(b.paused)
	reg.logistics.small_town_pop = small


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
	# Food slots (8) outrank hauling, but min_hauler_share 0.3 of 10 citizens (3, the Hearth has 2 hauler slots) keeps 2 hands on the carts.
	assert_eq(_haulers(s), 2)
	var fed := 0
	for b: Building in s.buildings.values():
		if b.def.id == "forager":
			fed += _workers(s, b)
	assert_eq(fed, 8)


func _woodcutter_hands(s: Settlement, pop: int) -> int:
	var wood := _put(s, "woodcutter", true)
	for i in 10:
		assert_not_null(_put(s, "forager", true))
	while s.citizens.size() < pop:
		s.add_citizen()
	s.refresh_population()
	return _workers(s, wood)


# 118: a small town (under small_town_pop people) gives a raw-goods workplace its first hand before the food slots
# take everyone; from small_town_pop up the usual order holds.
func test_small_town_gives_the_woodcutter_a_first_hand() -> void:
	assert_eq(reg.logistics.small_town_pop, 20)
	assert_eq(_woodcutter_hands(_new(), 19), 1, "19 people: hauler reserve, one woodcutter hand, then food")
	assert_eq(_woodcutter_hands(_new(), 20), 0, "20 people: food slots outrank the woodcutter")


# 118: in a small town the builders of a ready site get their crew before the food slots take second hands.
func test_small_town_builders_come_before_second_hands() -> void:
	var s := _new()
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		s.place_road(Vector2i(x, h.y))
	for i in 4:
		assert_not_null(_put(s, "forager", true))
	var bid := -1
	for x in range(h.x + 3, h.x + 16):
		bid = s.place_building("tent", Vector2i(x, h.y + 1))
		if bid >= 0:
			break
	assert_true(bid >= 0)
	var site: Building = s.buildings[bid]
	site.input_buffer.add("wood", 5.0)
	s.add_citizen()  # 9 people
	s.refresh_population()
	var builders := 0
	for id in s.citizens:
		if (s.citizens[id] as Citizen).job_kind == Citizen.JOB_BUILD:
			builders += 1
	assert_eq(builders, 2, "2 haulers, 4 first hands, then the one ready site gets its crew of 2")


## Ticket 169: with one hand short, a Normal healer is staffed before a Normal Quarry, and a Normal Market before a
## Normal Sawmill; the Cleanser's build menu category stays civic.
func _one_hand_first(first_id: String, second_id: String) -> Array:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0
	var s := _new()
	assert_true(s.set_building_priority(s.hearth.id, "paused"))  # keep its hauler slots out of the count
	var first := _put(s, first_id, true)
	var second := _put(s, second_id, true)
	assert_not_null(first)
	assert_not_null(second)
	_keep_citizens(s, 1)
	s.refresh_population()
	reg.logistics.small_town_pop = small
	return [_workers(s, first), _workers(s, second)]


func test_healer_is_staffed_before_quarry() -> void:
	assert_eq(_one_hand_first("cleanser", "quarry"), [1, 0])


func test_market_is_staffed_before_sawmill() -> void:
	assert_eq(_one_hand_first("market", "sawmill"), [1, 0])


func test_high_quarry_still_beats_normal_healer() -> void:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0
	var s := _new()
	assert_true(s.set_building_priority(s.hearth.id, "paused"))
	var healer := _put(s, "cleanser", true)
	var quarry := _put(s, "quarry", true)
	_keep_citizens(s, 1)
	assert_true(s.set_building_priority(quarry.id, "high"))
	s.refresh_population()
	assert_eq([_workers(s, healer), _workers(s, quarry)], [0, 1])
	reg.logistics.small_town_pop = small


func test_cleanser_category_is_still_civic() -> void:
	assert_eq(reg.get_building("cleanser").category, "civic")
