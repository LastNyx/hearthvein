extends GutTest
## Ticket 132: the night shift (spec .scratch/v1/night-shift-spec.md N1, N7).
##
## Night slots fill after the day slots of their rank and carry their own people (Citizen.shift), a night worker
## produces at night at the day's hourly rate, the schedule sends night workers in for 20-06, and a save keeps both.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket132.dat"

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the same-rank ordering is what these tests check, not the first-hand rule


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop
	DirAccess.remove_absolute(_save_path())


## A fresh settlement with the growth system off (the citizen count stays what a test sets) and a road strip east of
## the Hearth with clear land north of it.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 20):
		for y in range(hs.y - 3, hs.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places a building on the north side of the road strip, `dx` tiles east of the Hearth, and returns it.
func _put(s: Settlement, id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var hs := s.map.hearth_spot
	var bid := s.place_building_instant(id, Vector2i(hs.x + dx, hs.y - def.size.y))
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings.get(bid)


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Citizens in a `kind` job at `b`, split by shift.
func _staff(s: Settlement, b: Building, kind: String, night: bool) -> Array:
	var out: Array = []
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == kind and (c.shift == "night") == night:
			out.append(c)
	return out


func _save_path() -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return SAVE_DIR.path_join(SAVE_FILE)


## Criterion 1: night slots fill after every day slot of the same rank, and the citizen learns its shift.
func test_night_slots_fill_after_day_slots_and_set_the_shift() -> void:
	var s := _new_settlement()
	var store := _put(s, "storehouse", 6)
	_keep_citizens(s, 4)
	s.refresh_population()
	# The Hearth's two hauler slots and the Storehouse's two day hauler slots take all four people.
	assert_eq(_staff(s, s.hearth, Citizen.JOB_HAUL, false).size(), 2)
	assert_eq(_staff(s, store, Citizen.JOB_HAUL, false).size(), 2)
	assert_eq(_staff(s, store, Citizen.JOB_HAUL, true).size(), 0, "nobody is left for the night slot")
	s.add_citizen()  # a fifth: enough for the Storehouse's night slot (half its day hauler slots, rounded down)
	var night := _staff(s, store, Citizen.JOB_HAUL, true)
	assert_eq(night.size(), 1, "the night slot fills only after the day slots of the rank")
	assert_eq((night[0] as Citizen).shift, "night")
	for c in _staff(s, store, Citizen.JOB_HAUL, false):
		assert_eq((c as Citizen).shift, "day")


## Criterion 2: a sawmill with a night worker makes goods through the night at the day's hourly rate; one without
## a night worker makes nothing at night.
func test_sawmill_with_a_night_worker_makes_goods_at_night() -> void:
	var s := _new_settlement()
	var a := _put(s, "sawmill", 4)
	var b := _put(s, "sawmill", 10)
	_keep_citizens(s, 7)
	s.refresh_population()
	for mill in [a, b]:
		(mill.input_buffer as Inventory).add("wood", 20.0)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	s.step_hours(12)
	assert_eq(_staff(s, b, Citizen.JOB_WORK, false).size(), 2, "the second sawmill works days")
	assert_true(ws.is_at_work((_staff(s, b, Citizen.JOB_WORK, false)[0] as Citizen).id))
	s.step_hours(9)  # 21:00
	assert_eq(_staff(s, a, Citizen.JOB_WORK, true).size(), 1, "the first sawmill got the one night slot")
	assert_eq(_staff(s, b, Citizen.JOB_WORK, true).size(), 0)
	var night: Citizen = _staff(s, a, Citizen.JOB_WORK, true)[0]
	assert_true(ws.is_at_work(night.id), "the night worker is at the door by 21:00")
	var a0: float = a.door_buffer.amount_of("planks")
	var b0: float = b.door_buffer.amount_of("planks")
	s.step_hours(8)  # 21:00 -> 05:00, the middle of the shift
	# One worker for 8 hours at 3 planks per 12-hour work day: 8/12 of a worker-day.
	assert_almost_eq(a.door_buffer.amount_of("planks") - a0, 2.0, 0.02,
			"one night worker at the day rate (3 planks / 12 h)")
	assert_almost_eq(b.door_buffer.amount_of("planks"), b0, 0.001, "no night worker: nothing at night")


## Criterion 3: a night worker is at work at 21:00 and asleep at home at noon; the day worker keeps its own hours.
func test_night_worker_schedule_and_the_day_worker_keeps_its_own() -> void:
	var s := _new_settlement()
	var mill := _put(s, "sawmill", 4)
	_keep_citizens(s, 5)
	s.refresh_population()
	assert_eq(_staff(s, mill, Citizen.JOB_WORK, true).size(), 1)
	assert_eq(_staff(s, mill, Citizen.JOB_WORK, false).size(), 2)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var night: Citizen = _staff(s, mill, Citizen.JOB_WORK, true)[0]
	var day: Citizen = _staff(s, mill, Citizen.JOB_WORK, false)[0]
	s.step_hours(21)
	assert_true(ws.is_at_work(night.id), "at work at 21:00")
	assert_false(ws.is_at_work(day.id), "the day worker is home at 21:00")
	assert_eq(ws.walker_of(day.id).at_building, day.home_id)
	s.step_hours(15)  # noon the next day
	assert_false(ws.is_at_work(night.id), "asleep at noon")
	assert_eq(ws.walker_of(night.id).at_building, night.home_id)
	assert_true(ws.is_at_work(day.id), "the day worker is at work at noon, unchanged")
	s.step_hours(10)  # 22:00
	assert_true(ws.is_at_work(night.id))
	assert_false(ws.is_at_work(day.id))
	assert_eq(ws.walker_of(day.id).at_building, day.home_id)


## Criterion 4: a save keeps the shifts and the night slot fill; a save from before the shifts loads all days.
func test_save_keeps_shifts_and_an_old_save_loads_everyone_on_days() -> void:
	var s := _new_settlement()
	var mill := _put(s, "sawmill", 4)
	_keep_citizens(s, 5)
	s.refresh_population()
	var night: Citizen = _staff(s, mill, Citizen.JOB_WORK, true)[0]
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	var kept: Citizen = loaded.citizens[night.id]
	assert_eq(kept.shift, "night")
	assert_eq(kept.job_id, mill.id, "the night slot fill survives the load")
	assert_eq(kept.job_kind, Citizen.JOB_WORK)
	# A save from before ticket 132 has no shift field: everyone worked days. (No night-slot building here, so the
	# job refresh a load runs cannot hand anyone a night slot.)
	var old_src := _new_settlement()
	_put(old_src, "forager", 4)
	_keep_citizens(old_src, 3)
	old_src.refresh_population()
	var state := old_src.to_dict()
	for pair in state["citizens"]:
		(pair[1] as Dictionary).erase("shift")
	assert_eq(SaveGame.write_payload({"version": 5, "state": state}, path), OK)
	var old := SaveGame.load(path, reg)
	assert_not_null(old, "a v5 save migrates to the current version")
	assert_eq(old.citizens.size(), 3)
	for id in old.citizens:
		assert_eq((old.citizens[id] as Citizen).shift, "day")
