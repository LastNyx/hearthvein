extends GutTest
## Ticket 140: the Bakery and bread. The Bakery bakes bread at night from crops and charcoal (nothing by day, nothing
## without inputs); bread counts as food and is eaten before plain food. Bread has its own row in the ledger and on the
## Resources page, with its own icon.

const SEED := 42

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the night fill, not the small-town first-hand rule, is under test


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


## A fresh settlement with the growth system off and a road strip east of the Hearth with clear land north of it.
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


## A fuelled Brazier south of the road, `dx` tiles east of the Hearth: night slots open only inside a lamp's light.
func _lamp(s: Settlement, dx: int) -> Building:
	var hs := s.map.hearth_spot
	var bid := s.place_building_instant("lamp", Vector2i(hs.x + dx, hs.y + 1))
	assert_true(bid >= 0, "lamp placed")
	var lamp: Building = s.buildings.get(bid)
	lamp.input_buffer.add("wood", 3.0)
	return lamp


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


## Criterion 1: the Bakery bakes bread at night only, from its crops and charcoal; citizens eat bread before plain food.
func test_bakery_bakes_bread_at_night_from_inputs_and_bread_is_eaten_first() -> void:
	var s := _new_settlement()
	var bakery := _put(s, "bakery", 4)
	assert_true(bakery.def.night_only, "the Bakery is a night-only building")
	_lamp(s, 5)
	_keep_citizens(s, 4)  # two Hearth day haulers, then the Bakery's two night slots
	s.step_hours(19)
	assert_true(s.is_lit(bakery), "the Brazier lights the Bakery")
	assert_eq(_staff(s, bakery, Citizen.JOB_WORK, false).size(), 0, "no day slots in a night-only building")
	assert_eq(_staff(s, bakery, Citizen.JOB_WORK, true).size(), 2, "two night slots")
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	s.step_hours(2)
	assert_true(s.is_night(), "21:00 is the night shift")
	assert_eq(_staff(s, bakery, Citizen.JOB_WORK, true).size(), 2, "the night workers are on")
	var made_total := prod.produced_total
	s.step_hours(1)  # an empty input buffer: the ovens have nothing to bake
	assert_almost_eq(prod.produced_total, made_total, 0.001, "no crops and charcoal, no bread")
	(bakery.input_buffer as Inventory).add("crops", 16.0)
	(bakery.input_buffer as Inventory).add("charcoal", 16.0)
	var crops_before := bakery.input_buffer.amount_of("crops")
	var charcoal_before := bakery.input_buffer.amount_of("charcoal")
	s.step_hours(6)  # 22:00 -> 04:00, inside the night shift
	# 2 workers for 6 h of a 12 h work day (4 crops + 2 charcoal -> 3 bread): 2 * 6/12 * 3 = 3 bread.
	assert_almost_eq(prod.produced_total - made_total, 3.0, 0.02, "the Bakery baked bread at night")
	assert_almost_eq(bakery.input_buffer.amount_of("crops"), crops_before - 4.0, 0.02, "the bread took its crops")
	assert_almost_eq(bakery.input_buffer.amount_of("charcoal"), charcoal_before - 2.0, 0.02,
			"the bread took its charcoal")
	# The night crosses midnight, so the ledger's today and yesterday together hold the whole night's bread.
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	var made_bread := float(ledger.today("bread")["made"]) + float(ledger.yesterday("bread")["made"])
	assert_almost_eq(made_bread, 3.0, 0.02, "the ledger records the bread")
	s.step_hours(2)  # 04:00 -> 06:00, the rest of the night
	var at_dawn := prod.produced_total
	s.step_hours(13)  # 06:00 -> 19:00, the whole day
	assert_almost_eq(prod.produced_total, at_dawn, 0.001, "nothing by day")

	# Eating order: stores holding bread and plain food; across the day boundary the bread goes first.
	var e := Settlement.new_game(SEED, reg)
	e.hearth.inventory.add("bread", 10.0)
	e.step_days(1)
	assert_almost_eq(e.hearth.inventory.amount_of("bread"), 2.0, 0.01, "the 8 citizens ate bread before plain food")
	assert_almost_eq(e.hearth.inventory.amount_of("food"), 60.0, 0.01, "the plain food was not touched")


## Criterion 2: bread is a ledger good with a row on the Resources page and its own icon.
func test_bread_is_in_the_ledger_and_the_resources_page() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var m: HudModel = main.hud_model
	var s: Settlement = main.settlement
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	ledger.made_yesterday = {"bread": 3.0}
	ledger.used_yesterday = {"bread": 8.0}
	var row := _row(m, "bread")
	assert_false(row.is_empty(), "the Resources page has a bread row")
	assert_eq([row["name"], row["made"], row["used"]], ["Bread", 3, 8], "made and used come from the ledger")
	assert_not_null((hud._res_icons["bread"] as TextureRect).texture, "bread has its own icon")
	hud.resources_page.open()
	assert_not_null(hud.resources_page.row_node("bread"), "the page draws the bread row")
	assert_eq((hud.resources_page.row_node("bread").find_child("Made", true, false) as Label).text, "3")


func _game() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	var tmp := OS.get_environment("TMPDIR")
	main.settings_path = (tmp if tmp != "" else "/tmp").path_join("hearthvein_bread140_%d.cfg" % OS.get_process_id())
	main.saves_dir = main.settings_path + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	return main


func _row(m: HudModel, id: String) -> Dictionary:
	for r in m.resource_rows():
		if r["id"] == id:
			return r
	return {}


# ---------------------------------------------------------------- ticket 142: Observatory at City, star charts

## A settlement with one staffed Airship Dock and a finished Observatory, jobs set by hand. Returns the Observatory.
## `crew` night workers go to the Observatory (the full crew is its two night slots).
func _survey_town(crew: int) -> Array:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.systems.erase(s.get_system(JobSystem))
	s.era_override = "conflux"
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var hs := s.map.hearth_spot
	for x in range(hs.x + 3, hs.x + 20):
		for y in range(hs.y - 6, hs.y + 6):
			s.set_terrain(Vector2i(x, y), "grass")
	var dock := s.place_building_instant("airship_dock", Vector2i(hs.x + 4, hs.y + 1))
	var obs := s.place_building_instant("observatory", Vector2i(hs.x + 10, hs.y - 4))
	assert_true(dock >= 0 and obs >= 0, "dock and Observatory placed")
	while s.citizens.size() < 5:
		s.add_citizen()
	var ids: Array = s.citizens.keys()
	ids.sort()
	for cid in ids:
		var c: Citizen = s.citizens[cid]
		c.job_id = -1
		c.job_kind = Citizen.JOB_NONE
	var dock_worker: Citizen = s.citizens[ids[0]]
	dock_worker.job_id = dock
	dock_worker.job_kind = Citizen.JOB_WORK
	for i in crew:
		var c: Citizen = s.citizens[ids[1 + i]]
		c.job_id = obs
		c.job_kind = Citizen.JOB_WORK
		c.shift = Citizen.SHIFT_NIGHT
	return [s, s.buildings[obs]]


## A locked region with a reward that is neither the Hearth's nor the one the dock stands in.
func _locked_reward_region(s: Settlement) -> int:
	for r in MapState.REGION_COUNT:
		if s.map.get_region_reward(r) != "" and r != s.map.start_region:
			s.map.set_region_owned(r, false)
			return r
	return -1


## Criterion 1: the Observatory unlocks at City (not before), and its Dimming early warning still works.
func test_observatory_unlocks_at_city_and_still_warns() -> void:
	assert_eq(reg.get_building("observatory").era, "city")
	var t: Array = _survey_town(1)
	var s: Settlement = t[0]
	var hs := s.map.hearth_spot
	s.era_override = "town"
	assert_false(s.can_place("observatory", Vector2i(hs.x + 14, hs.y - 4))["ok"], "locked in Town")
	s.era_override = "city"
	assert_true(s.can_place("observatory", Vector2i(hs.x + 14, hs.y - 4))["ok"], "open at City")
	assert_eq(DimmingSystem.forecast_lead(s), 2, "a staffed Observatory warns two seasons ahead")
	var bare := Settlement.new_game(SEED, reg)
	assert_eq(DimmingSystem.forecast_lead(bare), reg.planet.dimming_forecast_seasons, "no Observatory, the default lead")


## Criterion 2: a survey flight lands sooner (25%, data) while an Observatory has its full night crew, at the normal
## time without one.
func test_survey_is_faster_with_a_full_night_crew_and_normal_without() -> void:
	var days := reg.regions.survey_days
	assert_almost_eq(reg.get_building("observatory").survey_speed_bonus, 0.25, 0.0001, "25% faster, from data")
	var results := {}
	for crew in [0, 1, 2]:
		var t: Array = _survey_town(crew)
		var s: Settlement = t[0]
		var air := s.get_system(AirshipSystem) as AirshipSystem
		var r := _locked_reward_region(s)
		assert_gte(r, 0, "a locked region with a reward")
		assert_true(air.start_survey(s, r), "the staffed dock flies it")
		var hours := 0
		while not air.is_revealed(s, r) and hours < days * 24 + 5:
			s.step_hours(1)
			hours += 1
		results[crew] = hours
	assert_eq(results[0], days * 24, "no crew: the normal time")
	assert_eq(results[1], days * 24, "half a crew does not count")
	assert_eq(results[2], ceili(days * 24 / 1.25), "a full crew: 25% faster")
