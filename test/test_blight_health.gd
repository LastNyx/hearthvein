extends GutTest
## Ticket 14: Lumen Tap blight, planet health, vein yield, forest dieback, Spirit hooks.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var ph: PlanetHealthSystem
var _tent_health: float


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	_tent_health = reg.get_building("tent").health_per_day


func after_each() -> void:
	reg.get_building("tent").health_per_day = _tent_health


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	h = s.map.hearth_spot
	ph = s.get_system(PlanetHealthSystem)


func _tap() -> int:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if s.map.terrain_id_at(x, y) == "lumen_vein" and s.can_place("lumen_tap", t)["ok"]:
				var id := s.place_building_instant("lumen_tap", t)
				if id >= 0:
					return id
	return -1


## Hand-assign a worker (the tap is not road-connected, so JobSystem would give it nobody).
func _staff(id: int) -> void:
	var c: Citizen = s.citizens[s.citizens.keys()[0]]
	c.job_id = id
	c.job_kind = Citizen.JOB_WORK


func _forest() -> int:
	var n := 0
	for v in s.map.terrain:
		if v == s.map.terrain_index("forest"):
			n += 1
	return n


func test_tap_blights_one_tile_per_6_days_within_r2_and_stops_when_removed() -> void:
	var id := _tap()
	assert_true(id >= 0)
	var tap: Building = s.buildings[id]
	assert_eq(BlightSystem.count(s), 0)
	s.step_days(5)
	assert_eq(BlightSystem.count(s), 0, "nothing before the 6th day")
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 1)
	s.step_days(12)
	assert_eq(BlightSystem.count(s), 3)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_blighted(x, y):
				var d := Vector2i(x, y) - tap.origin
				assert_true(d.x * d.x + d.y * d.y <= 4, "inside radius 2")
				assert_true(d != Vector2i.ZERO and s.map.terrain_id_at(x, y) != "water")
	assert_true(s.demolish(id))
	s.step_days(24)
	assert_eq(BlightSystem.count(s), 3, "removed: no more spread, old blight stays")


func test_blight_picks_nearest_first_and_event() -> void:
	var id := _tap()
	var tap: Building = s.buildings[id]
	s.step_days(6)
	assert_eq(s.events.log_of("blight_changed").size(), 1)
	var first := Vector2i(-1, -1)
	for y in range(tap.origin.y - 2, tap.origin.y + 3):
		for x in range(tap.origin.x - 2, tap.origin.x + 3):
			if s.map.is_blighted(x, y):
				first = Vector2i(x, y)
	assert_eq((first - tap.origin).length_squared(), 1, "a direct neighbour comes first")


func test_blocker_hook_protects_tiles() -> void:
	var id := _tap()
	var bs := s.get_system(BlightSystem) as BlightSystem
	bs.blockers.append(func(_s, _t): return true)
	s.step_days(12)
	assert_eq(BlightSystem.count(s), 0)
	assert_eq(bs.next_tile(s, s.buildings[id]), Vector2i(-1, -1))


func test_planet_health_daily_delta_matches_table() -> void:
	assert_eq(s.planet_health(), 100.0)
	var id := _tap()
	reg.get_building("tent").health_per_day = 0.01  # stands in for a worker-less cleaner (Park-like)
	s.place_building_instant("tent", Vector2i(h.x + 3, h.y - 2))
	_staff(id)
	assert_true(PlanetHealthSystem.is_working(s, s.buildings[id]), "tap has a worker")
	for i in 100:
		s.set_blighted(Vector2i(10 + i % 10, 10 + i / 10), true)
	ph.value = 50.0
	var want := 100.0 * -0.0006 + float(_forest()) * 0.00005 + -0.005 + 0.01
	assert_almost_eq(ph.daily_delta(s), want, 0.0000001)
	ph.on_day(s)  # called directly: an hourly job refresh would drop the hand-made assignment
	assert_almost_eq(s.planet_health(), 50.0 + want, 0.0000001)
	var bd := ph.daily_breakdown(s)
	assert_almost_eq(float(bd["buildings"]), 0.005, 0.0000001)
	assert_almost_eq(float(bd["blight"]), -0.06, 0.0000001)


func test_paused_or_site_buildings_do_not_count() -> void:
	var id := _tap()
	_staff(id)
	assert_true(PlanetHealthSystem.is_working(s, s.buildings[id]))
	s.buildings[id].paused = true
	assert_false(PlanetHealthSystem.is_working(s, s.buildings[id]))


func test_yearly_trend() -> void:
	ph.value = 70.0
	s.step_days(3)
	var t0 := ph.trend(s)
	assert_almost_eq(t0, s.planet_health() - 70.0, 0.0000001)
	s.step_days(40)
	assert_almost_eq(ph.trend(s), s.planet_health() - ph._history[0], 0.0000001)
	assert_eq(ph._history.size(), 32)


func test_vein_yield_is_half_plus_health_over_200() -> void:
	var id := _tap()
	var tap: Building = s.buildings[id]
	assert_almost_eq(PlanetHealthSystem.vein_factor_at(s, 100.0), 1.0, 0.000001)
	assert_almost_eq(PlanetHealthSystem.vein_factor_at(s, 50.0), 0.75, 0.000001)
	assert_almost_eq(PlanetHealthSystem.vein_factor_at(s, 0.0), 0.5, 0.000001)
	s.planet_health_override = 100.0
	var full := (s.get_system(ProductionSystem) as ProductionSystem).multiplier(s, tap)
	s.planet_health_override = 40.0
	var sick := (s.get_system(ProductionSystem) as ProductionSystem).multiplier(s, tap)
	assert_almost_eq(sick / full, 0.7, 0.000001)
	var forager: Building = s.buildings[s.place_building_instant("forager", _forager_spot())]
	assert_eq(PlanetHealthSystem.vein_modifier(s, forager), 1.0, "only vein extractors thin out")


func _forager_spot() -> Vector2i:
	for r in range(2, 20):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place("forager", Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_dieback_removes_share_of_forest_per_season() -> void:
	var f0 := _forest()
	ph.value = 70.0
	ph.on_season(s)
	assert_eq(_forest(), f0, "no dieback at or above 60%")
	ph.value = 40.0  # (60 - 40) / 10 = 2 percent
	ph.on_season(s)
	var gone := roundi(float(f0) * 0.02)
	assert_eq(_forest(), f0 - gone)
	# Deterministic: the same seed picks the same tiles.
	var s2 := Settlement.new_game(SEED, reg)
	(s2.get_system(PlanetHealthSystem) as PlanetHealthSystem).value = 40.0
	(s2.get_system(PlanetHealthSystem) as PlanetHealthSystem).on_season(s2)
	assert_eq(s2.map.terrain, s.map.terrain)


func test_dieback_runs_on_season_start() -> void:
	var f0 := _forest()
	ph.value = 30.0
	s.step_days(8)  # reaches the next season start; health only moves a hair meanwhile
	assert_true(_forest() < f0)


func test_spirit_hooks_blight_and_grief() -> void:
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	var tent := s.place_building_instant("tent", Vector2i(h.x + 3, h.y - 2))
	var other := s.place_building_instant("tent", Vector2i(h.x + 6, h.y - 2))
	assert_true(tent >= 0 and other >= 0)
	assert_eq(sp.breakdown(s)["factors"]["blight"], 0.0)
	# Homes: the Hearth (beds) and two tents; blight within 2 tiles of one of three is a third of -15.
	var homes := 0
	for id in s.buildings:
		if s.buildings[id].def.housing_beds > 0:
			homes += 1
	s.set_blighted(Vector2i(h.x + 3, h.y - 4), true)  # 2 tiles above the first tent
	assert_almost_eq(float(sp.breakdown(s)["factors"]["blight"]), -15.0 / float(homes), 0.0001)
	for y in range(h.y - 6, h.y + 6):
		for x in range(h.x - 6, h.x + 12):
			s.set_blighted(Vector2i(x, y), true)
	assert_eq(sp.breakdown(s)["factors"]["blight"], -15.0, "capped at -15 when every home is touched")
	s.planet_health_override = 60.0
	assert_eq(sp.breakdown(s)["factors"]["planet_grief"], 0.0)
	s.planet_health_override = 30.0
	assert_almost_eq(float(sp.breakdown(s)["factors"]["planet_grief"]), -5.0, 0.0001)
	s.planet_health_override = 0.0
	assert_eq(sp.breakdown(s)["factors"]["planet_grief"], -10.0, "capped at 10")
