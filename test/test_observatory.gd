extends GutTest
## Ticket 41d: Observatory (design.md sections 14 and 17 Skyborne). Settlement API plus step_hours.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const SUMMER := 1 * GameClock.DAYS_PER_SEASON
const AUTUMN := 2 * GameClock.DAYS_PER_SEASON
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var isl: Island


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "skyborne"
	s.planet_health_override = 100.0
	h = s.map.hearth_spot
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 5, h.y + 6):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if x >= h.x + 2:
			s.place_road(Vector2i(x, h.y))
	s.place_building_instant("lumen_pylon", Vector2i(h.x + 3, h.y - 1))
	var aid := s.place_building_instant("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	assert_true(aid >= 0, "anchor placed")
	isl = (s.get_system(IslandSystem) as IslandSystem).island_of_anchor(aid)
	assert_not_null(isl)
	s.hearth.inventory.add("lumen", 400.0)
	s.step_seconds(0.01)
	while s.citizens.size() < 8:
		s.add_citizen()
	JobSystem.refresh(s)


func _cov() -> CoverageSystem:
	return s.get_system(CoverageSystem) as CoverageSystem


func _at(dx: int, dy: int) -> Vector2i:
	return isl.rect.position + Vector2i(dx, dy)


func _sky(def_id: String, dx: int, dy: int) -> Building:
	var id := s.place_building_instant(def_id, _at(dx, dy), Building.LAYER_SKY)
	assert_true(id >= 0, "%s placed on the island" % def_id)
	return s.buildings[id]


## A finished Observatory on the ground beside the road, staffed after a day.
func _ground_observatory() -> Building:
	var id := s.place_building_instant("observatory", Vector2i(h.x + 8, h.y + 1))
	assert_true(id >= 0, "ground observatory placed")
	return s.buildings[id]


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("lumen", 50.0)
		s.hearth.inventory.add("food", 50.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _staffed(b: Building) -> bool:
	for c: Citizen in s.citizens.values():
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			return true
	return false


func test_data_row() -> void:
	var d := reg.get_building("observatory")
	assert_eq([d.era, d.size, d.layers], ["skyborne", Vector2i(2, 2), "either"])
	assert_eq(d.cost, {"wood": 48, "stone": 72, "gold": 80, "cut_stone": 30, "tools": 10})
	assert_eq([d.worker_slots, d.upkeep_lumen, d.coverage_radius, d.forecast_lead_seasons], [1, 1.0, 8, 2])
	assert_eq(reg.planet.dimming_forecast_seasons, 1, "default lead unchanged")


# AC1: lead is two seasons with a staffed Observatory, the default without one or while it is unstaffed.
func test_forecast_lead_two_seasons() -> void:
	assert_eq(DimmingSystem.forecast_lead(s), 1)
	var o := _ground_observatory()
	assert_true(_staffed(o), "staffed")
	var crew: Array[Citizen] = []
	for c: Citizen in s.citizens.values():
		if c.job_id == o.id:
			crew.append(c)
			c.job_id = -1
	assert_false(_staffed(o))
	assert_eq(DimmingSystem.forecast_lead(s), 1, "unstaffed")
	for c in crew:
		c.job_id = o.id
	assert_eq(DimmingSystem.forecast_lead(s), 2)
	o.paused = true
	assert_eq(DimmingSystem.forecast_lead(s), 1, "paused")
	o.paused = false
	s.demolish(o.id)
	assert_eq(DimmingSystem.forecast_lead(s), 1, "gone")


# AC1: the forecast really fires a season early (summer) with an Observatory, in autumn without one.
func test_forecast_fires_in_summer_with_observatory() -> void:
	var o := _ground_observatory()
	s.step_days(1)
	assert_true(_staffed(o))
	_to_day(SUMMER)
	var f := s.events.log_of("dimming_forecast")
	assert_eq(f.size(), 1, "forecast in summer")
	assert_eq(f[0]["data"]["start_day"], WINTER)
	assert_eq((s.get_system(DimmingSystem) as DimmingSystem).status(s)["state"], "forecast")


func test_forecast_in_autumn_without_observatory() -> void:
	_to_day(SUMMER)
	assert_eq(s.events.log_of("dimming_forecast").size(), 0)
	_to_day(AUTUMN)
	assert_eq(s.events.log_of("dimming_forecast").size(), 1)


# AC2: coverage r8 (the home at gap 8 is covered, gap 9 is not), on the island.
func test_observatory_coverage_r8_on_the_island() -> void:
	var o := _sky("observatory", 0, 0)  # x0..1, y0..1
	var near := _sky("skyspire", 9, 0)  # gap 8
	var far := _sky("skyspire", 10, 4)  # gap 9
	assert_eq(Building.footprint_gap(o, near), 8)
	assert_eq(Building.footprint_gap(o, far), 9)
	assert_true(_cov().home_covered(s, near.id), "r8 covered")
	assert_false(_cov().home_covered(s, far.id), "r9 not covered")


# The layer rule: a ground Observatory does not cover a sky home, and a sky one does not cover the ground.
func test_layer_rule() -> void:
	var home := _sky("skyspire", 2, 0)
	var g := _ground_observatory()
	var sky_o := _sky("observatory", 6, 0)
	assert_true(_cov().home_covered(s, home.id), "the sky Observatory covers it")
	s.demolish(sky_o.id)
	assert_false(_cov().home_covered(s, home.id), "a ground Observatory does not cover a sky home")
	var gh := s.place_building_instant("skyspire", Vector2i(h.x + 8, h.y + 4))
	assert_true(gh >= 0, "ground home")
	assert_true(_cov().home_covered(s, gh), "same layer ground coverage still works")
	sky_o = _sky("observatory", 6, 0)
	assert_false(CoverageSystem.coverage_reaches(s, sky_o, s.buildings[gh]), "sky source, ground home")
	assert_not_null(g)
