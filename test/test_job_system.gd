extends GutTest
## Ticket 131: beds bump (Tent 3, Cottage 5, tiers keep their step) and fair-share job filling (round-robin inside a
## (rank, priority) group instead of filling building by building).

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


## Puts a building straight into the settlement (placement rules skipped) on free tiles next to the road network.
func _put(s: Settlement, def_id: String, connected: bool) -> Building:
	var def := reg.get_building(def_id)
	var road0: Vector2i = s.map.hearth_spot + Vector2i(2, 0)
	if connected:
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


func _assignments(s: Settlement) -> Dictionary:
	var out := {}
	for id in s.citizens:
		var c: Citizen = s.citizens[id]
		out[id] = [c.job_id, c.job_kind]
	return out


## AC1: with citizens short of slots, the group's buildings share them one at a time (was 2/1/0).
func test_three_sawmills_share_three_citizens_one_each() -> void:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the small-town first hand (ticket 118) would hide the fair share
	var s := _new()
	assert_true(s.set_building_priority(s.hearth.id, "paused"))  # keep its hauler slots out of the three citizens
	var a := _put(s, "sawmill", true)
	var b := _put(s, "sawmill", true)
	var c := _put(s, "sawmill", true)
	assert_not_null(a)
	assert_not_null(b)
	assert_not_null(c)
	_keep_citizens(s, 3)
	s.refresh_population()
	assert_eq([_workers(s, a), _workers(s, b), _workers(s, c)], [1, 1, 1])
	reg.logistics.small_town_pop = small


## AC2: a second refresh with the same inputs keeps every citizen in the slot it already holds.
func test_refresh_with_the_same_inputs_keeps_assignments() -> void:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0
	var s := _new()
	assert_true(s.set_building_priority(s.hearth.id, "paused"))
	assert_not_null(_put(s, "sawmill", true))
	assert_not_null(_put(s, "sawmill", true))
	assert_not_null(_put(s, "sawmill", true))
	_keep_citizens(s, 3)
	s.refresh_population()
	var before := _assignments(s)
	s.refresh_population()
	assert_eq(_assignments(s), before)
	reg.logistics.small_town_pop = small


## AC3: the bed counts come from data, and the tiers keep their step above the base (Hut +1, Lodge +2;
## Cottage II +2, Cottage III +4).
func test_beds_and_tier_steps_from_data() -> void:
	var tent := reg.get_building("tent")
	var cottage := reg.get_building("cottage")
	assert_eq(tent.housing_beds, 3)
	assert_eq(cottage.housing_beds, 5)
	var t := Building.new()
	t.def = tent
	assert_eq(t.effective_beds(reg), 3)
	t.tier = 2
	assert_eq(t.effective_beds(reg), 4, "the Hut keeps its +1")
	t.tier = 3
	assert_eq(t.effective_beds(reg), 5, "the Lodge keeps its +2")
	t.def = cottage
	t.tier = 1
	assert_eq(t.effective_beds(reg), 5)
	t.tier = 2
	assert_eq(t.effective_beds(reg), 7, "Cottage II keeps its +2")
	t.tier = 3
	assert_eq(t.effective_beds(reg), 9, "Cottage III keeps its +4")


## Round-robin runs in building-id order and repeats: 4 citizens over 3 sawmills of 2 slots -> 2/1/1.
func test_extra_citizen_goes_round_to_the_first_building() -> void:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0
	var s := _new()
	assert_true(s.set_building_priority(s.hearth.id, "paused"))
	var a := _put(s, "sawmill", true)
	var b := _put(s, "sawmill", true)
	var c := _put(s, "sawmill", true)
	_keep_citizens(s, 4)
	s.refresh_population()
	assert_eq([_workers(s, a), _workers(s, b), _workers(s, c)], [2, 1, 1])
	reg.logistics.small_town_pop = small


## No churn when a citizen arrives: everyone already in a slot the new share still allots keeps it.
func test_new_citizen_does_not_move_the_others() -> void:
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0
	var s := _new()
	assert_true(s.set_building_priority(s.hearth.id, "paused"))
	_put(s, "sawmill", true)
	_put(s, "sawmill", true)
	_put(s, "sawmill", true)
	_keep_citizens(s, 3)
	s.refresh_population()
	var before := _assignments(s)
	s.add_citizen()
	s.refresh_population()
	var after := _assignments(s)
	for id in before:
		assert_eq(after[id], before[id], "citizen %d stays" % id)
	reg.logistics.small_town_pop = small
