extends GutTest
## Ticket 38: Airship Dock freight and survey flights. Staffed docks move surplus goods between their regions without
## track (rail first when both exist); a survey flight reveals a locked region's reward detail.

const SEED := 42
const SAVE_PATH := "user://test_airship.save"

var reg: DataRegistry
var s: Settlement
var air: AirshipSystem
var h: Vector2i
var y0: int
var bx: int
var dock_a: int
var dock_b: int
var depot_a: int = -1
var depot_b: int = -1
var store_a: Building
var store_b: Building
var tent_b: Building
var locked: int = -1


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## Region A (left of boundary bx) holds 300 food; region B has a tent with `homes` citizens. A dock in each region.
## With rail = true both regions also get a Rail Depot joined by track. Jobs are set by hand (see _staff).
func _setup(staff_a: bool = true, staff_b: bool = true, rail: bool = false, homes: int = 10) -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.systems.erase(s.get_system(JobSystem))
	s.era_override = "conflux"
	air = s.get_system(AirshipSystem)
	h = s.map.hearth_spot
	var r1 := MapState.region_at(h.x, h.y)
	var left := (r1 / MapState.REGION_COLS) * MapState.REGION_COLS + mini(r1 % MapState.REGION_COLS, 1)
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var rect := MapState.region_rect(left)
	bx = rect.end.x
	y0 = h.y + 8 if h.y + 8 < rect.end.y - 8 else h.y - 8
	for x in range(bx - 14, bx + 50):
		for y in range(y0 - 3, y0 + 6):
			s.set_terrain(Vector2i(x, y), "grass")
	s.hearth.inventory.add("materials", 500.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	dock_a = s.place_building_instant("airship_dock", Vector2i(bx - 6, y0))
	dock_b = s.place_building_instant("airship_dock", Vector2i(bx + 3, y0))
	assert_true(dock_a >= 0 and dock_b >= 0, "docks placed")
	if rail:
		depot_a = s.place_building_instant("rail_depot", Vector2i(bx - 5, y0 + 4))
		depot_b = s.place_building_instant("rail_depot", Vector2i(bx + 2, y0 + 4))
		assert_true(depot_a >= 0 and depot_b >= 0, "depots placed")
		for x in range(bx - 2, bx + 2):
			assert_true(s.place_track(Vector2i(x, y0 + 4)), "track")
	store_a = s.buildings[s.place_building_instant("storehouse", Vector2i(bx - 13, y0 + 2))]
	store_b = s.buildings[s.place_building_instant("storehouse", Vector2i(bx + 10, y0 + 2))]
	tent_b = s.buildings[s.place_building_instant("tent", Vector2i(bx + 12, y0 - 3))]
	while s.citizens.size() < homes + 4:
		s.add_citizen()
	assert_eq(s.citizens.size(), homes + 4, "exactly the planned citizens")
	for g in s.hearth.inventory.goods():
		if g != "materials" and g != "cut_stone":
			s.hearth.inventory.remove(g, 1000000.0)
	store_a.inventory.add("food", 300.0)
	_staff(staff_a, staff_b, rail)


## Citizens 0 and 1 work the docks (A, B); with rail, 2 and 3 haul the depots; everyone else lives in the tent.
func _staff(staff_a: bool = true, staff_b: bool = true, rail: bool = false) -> void:
	var ids: Array = s.citizens.keys()
	ids.sort()
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.job_id = -1
		c.job_kind = Citizen.JOB_NONE
		c.home_id = -1
		if i == 0 and staff_a:
			c.job_id = dock_a
			c.job_kind = Citizen.JOB_WORK
		elif i == 1 and staff_b:
			c.job_id = dock_b
			c.job_kind = Citizen.JOB_WORK
		elif i == 2 and rail:
			c.job_id = depot_a
			c.job_kind = Citizen.JOB_HAUL
		elif i == 3 and rail:
			c.job_id = depot_b
			c.job_kind = Citizen.JOB_HAUL
		elif i >= 4:
			c.home_id = tent_b.id


func _region_of(b: Building) -> int:
	return s.map.get_region(b.origin.x, b.origin.y)


func _in_region(ref: Building, good: String) -> float:
	var sum := 0.0
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.inventory != null and not b.site and _region_of(b) == _region_of(ref):
			sum += b.inventory.amount_of(good)
	return sum


func _sum_goods(e: Dictionary) -> float:
	var t := 0.0
	for g in e["data"]["goods"]:
		t += float(e["data"]["goods"][g])
	return t


## Locks a region that has a reward and holds no building; returns its index.
func _lock_a_reward_region() -> int:
	for r in MapState.REGION_COUNT:
		if s.map.get_region_reward(r) != "" and r != _region_of(store_a) and r != _region_of(store_b) \
				and r != s.map.start_region:
			s.map.set_region_owned(r, false)
			return r
	return -1


# ---------------------------------------------------------------- the dock

func test_dock_data() -> void:
	var def := reg.get_building("airship_dock")
	assert_not_null(def)
	assert_eq(def.era, "conflux")
	assert_eq(def.size, Vector2i(3, 3))
	assert_eq(def.cost, {"materials": 200, "gold": 120, "planks": 40, "tools": 20})
	assert_eq(def.worker_slots, 3)
	assert_eq(def.upkeep_lumen, 4.0)
	assert_true(def.airship_dock)
	assert_gt(def.storage_cap, 0, "a small storage like the Rail Depot")
	_setup()
	assert_eq(s.can_place("airship_dock", Vector2i(bx - 12, y0 + 4))["reason"], "region_dock", "one dock per region")


# ---------------------------------------------------------------- freight

func test_freight_moves_between_docked_regions_without_track() -> void:
	_setup()
	assert_ne(_region_of(store_a), _region_of(store_b))
	assert_eq(_in_region(store_b, "food"), 0.0)
	s.step_days(2)
	var got := _in_region(store_b, "food")
	assert_gt(got, 25.0, "food reached region B by air (%f)" % got)
	assert_almost_eq(_in_region(store_a, "food") + got + air.in_transit("food"), 300.0, 0.01, "nothing lost")
	assert_false(s.events.log_of("airship_sent").is_empty(), "an airship left")
	assert_false(s.events.log_of("airship_arrived").is_empty(), "and landed")
	assert_true(s.events.log_of("shipment_sent").is_empty(), "no train was involved")
	for e in s.events.log_of("airship_sent"):
		assert_eq(int(e["data"]["from"]), dock_a)
		assert_eq(int(e["data"]["to"]), dock_b)
	# the target is the homed citizens x 1 food x 3 days, no more
	assert_almost_eq(_in_region(store_b, "food"), 10.0 * 3.0, 0.01)


func test_trip_time_is_distance_over_speed_and_positions_move() -> void:
	_setup()
	s.step_hours(24)
	var fl := air.shipments(s)
	assert_eq(fl.size(), 1, "one airship in flight right after the day hook")
	var a := Vector2(s.buildings[dock_a].origin) + Vector2(1.5, 1.5)
	var b := Vector2(s.buildings[dock_b].origin) + Vector2(1.5, 1.5)
	assert_eq(fl[0]["from_pos"], a)
	assert_eq(fl[0]["to_pos"], b)
	assert_eq(fl[0]["from_dock"], dock_a)
	assert_eq(fl[0]["to_dock"], dock_b)
	var hours := a.distance_to(b) / reg.logistics.airship_speed
	assert_almost_eq(float(fl[0]["arrive_hour"]) - float(fl[0]["depart_hour"]), hours, 0.0001)
	assert_almost_eq(float(fl[0]["progress"]), 0.0, 0.0001)
	assert_eq(fl[0]["pos"], a)
	s.step_hours(1)
	var mid := air.shipments(s)
	assert_eq(mid.size(), 1, "still flying after an hour (trip %.2f h)" % hours)
	assert_gt(float(mid[0]["progress"]), 0.0)
	assert_lt(float(mid[0]["progress"]), 1.0)
	assert_true((mid[0]["pos"] as Vector2).x > a.x, "moved toward B")
	assert_eq(_in_region(store_b, "food"), 0.0, "nothing delivered yet")
	s.step_hours(int(ceil(hours)))
	assert_true(air.shipments(s).is_empty(), "landed")
	assert_gt(_in_region(store_b, "food"), 0.0)


func test_capacity_per_dock_per_day() -> void:
	_setup(true, true, false, 40)  # need 120 > the dock's 40 a day
	s.step_hours(24)
	var sent := s.events.log_of("airship_sent")
	assert_eq(sent.size(), 1)
	assert_almost_eq(_sum_goods(sent[0]), reg.logistics.airship_capacity, 0.01, "one day's load is capped")


func test_unstaffed_dock_does_nothing() -> void:
	_setup(false, true)
	s.step_days(2)
	assert_true(s.events.log_of("airship_sent").is_empty(), "unstaffed source sends nothing")
	assert_eq(_in_region(store_b, "food"), 0.0)
	_setup(true, false)
	s.step_days(2)
	assert_true(s.events.log_of("airship_sent").is_empty(), "unstaffed destination receives nothing")
	assert_eq(_in_region(store_b, "food"), 0.0)
	assert_eq(_in_region(store_a, "food"), 300.0)


func test_no_dock_no_delivery() -> void:
	_setup()
	# a third region with homes and no dock stays short of food
	var tent_c: Building = s.buildings[s.place_building_instant("tent", Vector2i(bx + 40, y0 - 3))]
	var ids: Array = s.citizens.keys()
	ids.sort()
	for i in range(ids.size() - 6, ids.size()):
		(s.citizens[ids[i]] as Citizen).home_id = tent_c.id
	assert_ne(_region_of(tent_c), _region_of(tent_b))
	s.step_days(3)
	assert_eq(_in_region(tent_c, "food"), 0.0, "airships never serve a region without a dock")
	for e in s.events.log_of("airship_sent"):
		assert_eq(int(e["data"]["to"]), dock_b)


func test_rail_goes_first_air_moves_the_rest() -> void:
	_setup(true, true, true, 25)  # need 75: more than a train's 60, less than train + airship
	assert_true((s.get_system(RailSystem) as RailSystem).linked(s, depot_a, depot_b), "depots linked")
	_staff(true, true, true)
	s.step_hours(24)
	var trains := s.events.log_of("shipment_sent")
	var ships := s.events.log_of("airship_sent")
	assert_eq(trains.size(), 1, "the train goes")
	assert_almost_eq(_sum_goods(trains[0]), reg.logistics.train_capacity, 0.01, "carrying a full load")
	assert_eq(ships.size(), 1, "the airship takes what is left")
	assert_almost_eq(_sum_goods(ships[0]), 25.0 * 3.0 - reg.logistics.train_capacity, 0.01, "only the remaining need")
	s.step_days(2)
	assert_almost_eq(_in_region(store_b, "food"), 75.0, 0.01, "no over-delivery")


# ---------------------------------------------------------------- survey

func test_survey_reveals_a_locked_regions_reward() -> void:
	_setup()
	locked = _lock_a_reward_region()
	assert_gte(locked, 0, "a locked region with a reward")
	var m := HudModel.new(s)
	var row: Dictionary = m.region_rows()[locked]
	assert_ne(row["reward"], "", "the marker is always shown (design.md section 4)")
	assert_false(row["revealed"])
	assert_eq(row["reward_detail"], "", "no detail before a survey")
	assert_true(row["can_survey"], "a staffed dock can fly it")
	assert_true(m.survey_region(locked))
	assert_false(air.is_revealed(s, locked))
	assert_false(s.events.log_of("survey_started").is_empty())
	row = m.region_rows()[locked]
	assert_true(row["surveying"])
	assert_false(row["can_survey"], "already out")
	var days := reg.regions.survey_days
	s.step_hours(days * 24 - 1)
	assert_false(air.is_revealed(s, locked), "not yet")
	assert_between(float(m.region_rows()[locked]["survey_days_left"]), 0.0, 0.1)
	s.step_hours(1)
	assert_true(air.is_revealed(s, locked), "revealed after %d days" % days)
	var done := s.events.log_of("region_surveyed")
	assert_eq(done.size(), 1)
	assert_eq(int(done[0]["data"]["region"]), locked)
	row = m.region_rows()[locked]
	assert_true(row["revealed"])
	assert_ne(row["reward_detail"], "", "the exact detail is known now")
	assert_false(row["surveying"])
	assert_eq(row["survey_reason"], "revealed")


func test_survey_allows_a_buyable_region() -> void:
	_setup()
	locked = _lock_a_reward_region()  # the other regions stay owned, so this one is next to owned land
	var m := HudModel.new(s)
	var row: Dictionary = m.region_rows()[locked]
	assert_eq(row["state"], "buyable", "next to owned land")
	assert_eq(air.survey_refusal(s, locked), "", "surveying before buying is allowed")
	assert_true(row["can_survey"])
	assert_true(m.survey_region(locked))
	assert_true(m.region_rows()[locked]["surveying"])


func test_survey_one_at_a_time_per_dock() -> void:
	_setup(true, false)  # only dock A is staffed
	locked = _lock_a_reward_region()
	var other := -1
	for r in MapState.REGION_COUNT:
		if r != locked and s.map.get_region_reward(r) != "" and r != _region_of(store_a) and r != _region_of(store_b) \
				and r != s.map.start_region:
			other = r
			s.map.set_region_owned(r, false)
			break
	assert_gte(other, 0, "a second locked reward region")
	assert_true(s.survey_region(locked))
	assert_false(s.survey_region(other), "the only dock is out")
	assert_eq(air.survey_refusal(s, other), "busy")
	assert_false(s.survey_region(locked), "and nobody flies the same region twice")
	_staff(true, true)  # dock B gets a crew
	assert_true(s.survey_region(other), "a second staffed dock can fly the second one")


func test_survey_needs_a_staffed_dock() -> void:
	_setup(false, false)
	locked = _lock_a_reward_region()
	assert_false(s.survey_region(locked))
	assert_eq(air.survey_refusal(s, locked), "no_dock")
	var row: Dictionary = HudModel.new(s).region_rows()[locked]
	assert_false(row["can_survey"])


func test_survey_rejected_for_owned_or_revealed_regions() -> void:
	_setup()
	assert_false(s.survey_region(_region_of(store_b)), "owned region")
	assert_eq(air.survey_refusal(s, _region_of(store_b)), "owned")
	assert_false(s.survey_region(-1))
	locked = _lock_a_reward_region()
	assert_true(s.survey_region(locked))
	s.step_days(reg.regions.survey_days)
	assert_true(air.is_revealed(s, locked))
	assert_false(s.survey_region(locked), "already revealed")
	assert_eq(air.survey_refusal(s, locked), "revealed")
	assert_eq(s.events.log_of("survey_started").size(), 1)
	# buying a region reveals it too
	var other := -1
	for r in MapState.REGION_COUNT:
		if r != locked and s.map.get_region_reward(r) != "" and s.map.is_region_owned(r):
			other = r
			break
	assert_gte(other, 0)
	assert_true(air.is_revealed(s, other), "owned regions are revealed")


# ---------------------------------------------------------------- save

func test_save_round_trip_mid_flight_and_mid_survey() -> void:
	_setup()
	locked = _lock_a_reward_region()
	assert_true(s.survey_region(locked))
	s.step_hours(25)  # one day plus an hour: the airship is up, the survey has a day to go
	var before := air.shipments(s)
	assert_eq(before.size(), 1, "an airship is in flight at the save point")
	assert_eq(SaveGame.save(s, SAVE_PATH), OK)
	var loaded := SaveGame.load(SAVE_PATH, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	var a2 := loaded.get_system(AirshipSystem) as AirshipSystem
	var after := a2.shipments(loaded)
	assert_eq(after.size(), 1)
	assert_eq(after[0]["goods"], before[0]["goods"])
	assert_eq(after[0]["from_pos"], before[0]["from_pos"])
	assert_almost_eq(float(after[0]["progress"]), float(before[0]["progress"]), 0.0001)
	assert_false(a2.is_revealed(loaded, locked), "survey still out")
	assert_eq(a2.surveys().size(), 1, "the flight survived the save")
	loaded.step_hours(24)
	assert_true(a2.is_revealed(loaded, locked), "it completes in the loaded game")
	assert_true(a2.shipments(loaded).is_empty(), "and the airship lands")
	s.step_hours(24)
	assert_true(air.is_revealed(s, locked), "same as the live game")
	assert_true(a2.is_revealed(loaded, locked) and a2.surveys().is_empty())
