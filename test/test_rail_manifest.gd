extends GutTest
## Ticket 37b: rail manifests. Linked, staffed Rail Depots move surplus goods to regions in need once a day; trains take
## track-length time; haulers never cross regions on foot because of rail.

const SEED := 42
const SAVE_PATH := "user://test_rail_manifest.save"

var reg: DataRegistry
var s: Settlement
var man: RailManifestSystem
var h: Vector2i
var y0: int
var bx: int
var depot_a: int
var depot_b: int
var store_a: Building
var store_b: Building
var tent_b: Building


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## Region A (left of boundary bx) holds 300 food and no homes; region B has a tent with 10 citizens and no food.
## Depot A ends at bx-3, depot B starts at bx+2+gap, track fills the gap between them. Both depots are staffed by hand.
func _setup(gap: int = 0, staff_a: bool = true, staff_b: bool = true) -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.systems.erase(s.get_system(JobSystem))  # jobs are set by hand below
	s.era_override = "conflux"
	man = s.get_system(RailManifestSystem)
	h = s.map.hearth_spot
	var r1 := MapState.region_at(h.x, h.y)
	var left := (r1 / MapState.REGION_COLS) * MapState.REGION_COLS + mini(r1 % MapState.REGION_COLS, 1)
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var rect := MapState.region_rect(left)
	bx = rect.end.x
	y0 = h.y + 8 if h.y + 8 < rect.end.y - 6 else h.y - 8
	for x in range(bx - 14, bx + 30):
		for y in range(y0 - 3, y0 + 5):
			s.set_terrain(Vector2i(x, y), "grass")
	s.hearth.inventory.add("wood", 500.0)
	s.hearth.inventory.add("stone", 500.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	depot_a = s.place_building_instant("rail_depot", Vector2i(bx - 5, y0))
	depot_b = s.place_building_instant("rail_depot", Vector2i(bx + 2 + gap, y0))
	assert_true(depot_a >= 0 and depot_b >= 0, "depots placed")
	for x in range(bx - 2, bx + 2 + gap):
		assert_true(s.place_track(Vector2i(x, y0)), "track at x=%d" % x)
	store_a = s.buildings[s.place_building_instant("storehouse", Vector2i(bx - 13, y0 + 2))]
	store_b = s.buildings[s.place_building_instant("storehouse", Vector2i(bx + 10, y0 + 2))]
	tent_b = s.buildings[s.place_building_instant("tent", Vector2i(bx + 12, y0 - 3))]
	for i in 12:
		s.add_citizen()
	# The Hearth's own stock must not take part: empty it of everything but the building materials.
	for g in s.hearth.inventory.goods():
		if g != "wood" and g != "stone" and g != "cut_stone":
			s.hearth.inventory.remove(g, 1000000.0)
	store_a.inventory.add("food", 300.0)
	_staff(staff_a, staff_b)


## Sets every citizen's job and home by hand: the first staffs depot A, the second depot B, the rest live in the tent.
## Track and building changes re-run job assignment, so a test that edits track calls this again.
func _staff(staff_a: bool = true, staff_b: bool = true) -> void:
	var ids: Array = s.citizens.keys()
	ids.sort()
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.job_id = -1
		c.job_kind = Citizen.JOB_NONE
		c.home_id = -1
		if i == 0 and staff_a:
			c.job_id = depot_a
			c.job_kind = Citizen.JOB_HAUL
		elif i == 1 and staff_b:
			c.job_id = depot_b
			c.job_kind = Citizen.JOB_HAUL
		elif i >= 2:
			c.home_id = tent_b.id


func _region_of(b: Building) -> int:
	return s.map.get_region(b.origin.x, b.origin.y)


## Units of a good in every storage of the region of `ref`.
func _in_region(ref: Building, good: String) -> float:
	var sum := 0.0
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.inventory != null and not b.site and _region_of(b) == _region_of(ref):
			sum += b.inventory.amount_of(good)
	return sum


func _depot_b_food() -> float:
	return (s.buildings[depot_b] as Building).inventory.amount_of("food")


func test_goods_move_between_linked_regions_without_haulers_crossing() -> void:
	_setup()
	assert_ne(_region_of(store_a), _region_of(store_b), "the stores are in different regions")
	assert_eq(_in_region(store_b, "food"), 0.0, "region B starts with no food")
	s.step_days(2)
	var got := _in_region(store_b, "food")
	assert_gt(got, 25.0, "food reached region B by rail (%f)" % got)
	assert_lt(_in_region(store_a, "food"), 300.0, "and left region A")
	assert_almost_eq(_in_region(store_a, "food") + got + man.in_transit("food"), 300.0, 0.01, "nothing was lost")
	for e in s.events.log_of("haul_delivered"):
		var from: Building = s.buildings[int(e["data"]["from"])]
		var to: Building = s.buildings[int(e["data"]["to"])]
		assert_eq(_region_of(from), _region_of(to), "no hauler trip spans regions")


func test_surplus_flows_toward_the_shortage() -> void:
	_setup()
	store_a.inventory.add("cut_stone", 100.0)  # nobody demands cut stone: it must stay put
	s.step_days(1)
	s.step_hours(2)
	var sent := s.events.log_of("shipment_sent")
	assert_false(sent.is_empty(), "a train left")
	for e in sent:
		assert_eq(int(e["data"]["from"]), depot_a, "from the region with food")
		assert_eq(int(e["data"]["to"]), depot_b, "to the region short of it")
		assert_false((e["data"]["goods"] as Dictionary).has("cut_stone"), "undemanded goods stay")
	# Target is the citizens homed in B x 1 food x 3 days (every citizen but the two depot staff).
	var target := float(s.citizens.size() - 2) * 3.0
	assert_almost_eq(_in_region(store_b, "food"), target, 0.01, "the shortage is filled to its target, no more")
	assert_lt(target, 60.0, "the target fits one train")
	assert_eq(_in_region(store_a, "cut_stone"), 100.0 + (s.hearth.inventory.amount_of("cut_stone") if _region_of(s.hearth) == _region_of(store_a) else 0.0))
	s.step_days(3)
	assert_almost_eq(_in_region(store_b, "food"), target, 0.01, "a filled region gets nothing more")


func test_unstaffed_depot_sends_nothing() -> void:
	_setup(0, false, true)
	s.step_days(2)
	assert_true(s.events.log_of("shipment_sent").is_empty(), "unstaffed source sends nothing")
	assert_eq(_in_region(store_b, "food"), 0.0)
	_setup(0, true, false)
	s.step_days(2)
	assert_true(s.events.log_of("shipment_sent").is_empty(), "unstaffed destination receives nothing")
	assert_eq(_in_region(store_b, "food"), 0.0)
	assert_eq(_in_region(store_a, "food"), 300.0)


func test_broken_link_stops_shipments() -> void:
	_setup()
	assert_true(s.remove_track(Vector2i(bx, y0)), "lift a track tile")
	_staff()
	assert_false((s.get_system(RailSystem) as RailSystem).linked(s, depot_a, depot_b), "the depots are no longer linked")
	s.step_days(3)
	assert_true(s.events.log_of("shipment_sent").is_empty(), "no train without a link")
	assert_eq(_in_region(store_b, "food"), 0.0)
	assert_true(s.place_track(Vector2i(bx, y0)), "mend it")
	_staff()
	s.step_days(1)
	s.step_hours(2)
	assert_false(s.events.log_of("shipment_sent").is_empty(), "the train runs again")
	assert_gt(_in_region(store_b, "food"), 0.0)


func test_transit_time_scales_with_track_length() -> void:
	var speed := reg.logistics.train_speed
	_setup(0)
	s.step_hours(24)
	var short := man.shipments(s)
	assert_eq(short.size(), 1, "one train in flight right after the day hook")
	var sp: Array[Vector2i] = short[0]["path"]
	assert_eq(sp.size(), 4, "path is the 4 track tiles")
	assert_almost_eq(float(short[0]["arrive_hour"]) - float(short[0]["depart_hour"]), 4.0 / speed, 0.0001)
	assert_almost_eq(float(short[0]["progress"]), 0.0, 0.0001)
	s.step_hours(1)
	assert_true(man.shipments(s).is_empty(), "a short run is home within the hour")
	_setup(20)
	s.step_hours(24)
	var long := man.shipments(s)
	var lp: Array[Vector2i] = long[0]["path"]
	assert_eq(lp.size(), 24)
	assert_almost_eq(float(long[0]["arrive_hour"]) - float(long[0]["depart_hour"]), 24.0 / speed, 0.0001)
	assert_gt(float(long[0]["arrive_hour"]) - float(long[0]["depart_hour"]), 4.0 / speed * 5.0, "longer track, longer trip")
	assert_eq(lp[0].y, y0)
	s.step_hours(1)
	assert_eq(man.shipments(s).size(), 1, "still on the way after an hour")
	assert_eq(_depot_b_food(), 0.0, "nothing delivered yet")
	assert_between(float(man.shipments(s)[0]["progress"]), 0.3, 0.6)
	s.step_hours(2)
	assert_true(man.shipments(s).is_empty(), "arrived after 2.4 hours")
	assert_gt(_in_region(store_b, "food"), 0.0, "and delivered")


func test_save_round_trip_mid_transit() -> void:
	_setup(20)
	s.step_hours(25)
	var before := man.shipments(s)
	assert_eq(before.size(), 1, "a train is in flight at the save point")
	assert_eq(SaveGame.save(s, SAVE_PATH), OK)
	var loaded := SaveGame.load(SAVE_PATH, reg)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	var m2 := loaded.get_system(RailManifestSystem) as RailManifestSystem
	var after := m2.shipments(loaded)
	assert_eq(after.size(), 1, "the train is still in flight after loading")
	assert_eq(after[0]["goods"], before[0]["goods"])
	assert_eq(after[0]["path"], before[0]["path"])
	assert_almost_eq(float(after[0]["progress"]), float(before[0]["progress"]), 0.0001)
	var cargo := m2.in_transit("food")
	assert_gt(cargo, 0.0)
	loaded.step_hours(3)
	assert_true(m2.shipments(loaded).is_empty(), "it arrives in the loaded game")
	var got := 0.0
	for id in loaded.buildings:
		var b: Building = loaded.buildings[id]
		if b.inventory != null and loaded.map.get_region(b.origin.x, b.origin.y) == _region_of(store_b):
			got += b.inventory.amount_of("food")
	assert_almost_eq(got, cargo, 0.01, "the whole cargo landed in region B")
