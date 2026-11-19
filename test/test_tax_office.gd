extends GutTest
## Ticket 27d: Tax Office (design.md sections 11 and 16 Town).
## The data row, +0.2 gold per citizen per day through the day hook, and the Spirit -5 while one stands.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var sp: SpiritSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	sp = s.get_system(SpiritSystem)
	h = s.map.hearth_spot


## A cleared, road-connected strip east of the Hearth (the same patch test_sawmill uses).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## Places a finished building north of the road, `dx` tiles east of the Hearth.
func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(h.x + dx, h.y - def.size.y)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	var b: Building = s.buildings.get(bid)
	assert_true(b.connected, "%s is connected to the Hearth by road" % id)
	return b


func _workers(building_id: int) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == building_id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


# AC1a: the data row is the Town table's: 1x1, 40M, 1 worker, no upkeep, +0.2 gold per citizen per day.
func test_data_matches_the_town_table() -> void:
	var def := reg.get_building("tax_office")
	assert_not_null(def)
	assert_eq([def.era, def.category], ["town", "gold"])
	assert_eq([def.size, def.cost, def.worker_slots], [Vector2i(1, 1), {"wood": 16, "stone": 24}, 1])
	assert_eq([def.upkeep_lumen, def.housing_beds], [0.0, 0])
	assert_eq(def.gold_per_citizen_day, 0.2)
	assert_null(def.recipe, "gold is a counter, not a recipe output")


# AC1b: one finished office with its collector assigned adds 0.2 gold for every citizen on the day hook.
func test_pays_02_gold_per_citizen_per_day() -> void:
	s.systems.erase(s.get_system(GrowthSystem))  # a fixed population, so the expected gold is exact
	_strip()
	var office := _put("tax_office", 4)
	s.refresh_population()
	assert_gt(_workers(office.id), 0, "a collector is assigned to the office")
	var before := s.gold
	s.step_days(1)
	var want := 0.2 * float(s.citizens.size())
	assert_almost_eq(s.gold - before, want, 0.001, "0.2 gold x %d citizens" % s.citizens.size())


# AC1c: each office pays its own rate, so two offices give 0.4 per citizen (not one, not 0.2).
func test_two_offices_stack() -> void:
	s.systems.erase(s.get_system(GrowthSystem))
	_strip()
	_put("tax_office", 4)
	_put("tax_office", 6)
	s.refresh_population()
	var before := s.gold
	s.step_days(1)
	var want := 0.4 * float(s.citizens.size())
	assert_almost_eq(s.gold - before, want, 0.001, "two offices x 0.2 gold x %d citizens" % s.citizens.size())


# AC1d: the office needs its collector: with the worker taken off the job it pays nothing.
func test_pays_nothing_without_its_worker() -> void:
	_strip()
	var office := _put("tax_office", 4)
	s.refresh_population()
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == office.id:
			c.job_id = -1
			c.job_kind = Citizen.JOB_NONE
	var before := s.gold
	(s.get_system(MarketSystem) as MarketSystem).on_day(s)
	assert_almost_eq(s.gold, before, 0.0001, "no assigned worker, no tax")


# AC1e: a paused office stands idle and pays nothing either.
func test_paused_office_pays_nothing() -> void:
	s.systems.erase(s.get_system(GrowthSystem))
	_strip()
	var office := _put("tax_office", 4)
	office.paused = true
	s.refresh_population()
	var before := s.gold
	s.step_days(1)
	assert_almost_eq(s.gold, before, 0.0001)


# AC2: one Tax Office gives Spirit -5.
func test_spirit_drops_five() -> void:
	assert_eq(_factor("tax_office"), 0.0, "no office, no penalty")
	_strip()
	_put("tax_office", 4)
	assert_eq(_factor("tax_office"), -5.0)


# AC2b: design.md gives one number for "if a Tax Office exists": two offices still cost -5 in total.
func test_two_offices_still_cost_five() -> void:
	_strip()
	_put("tax_office", 4)
	_put("tax_office", 6)
	assert_eq(_factor("tax_office"), -5.0, "one or more offices: -5 total, not per office")
