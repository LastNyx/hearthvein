extends GutTest
## Ticket 39b: Vein Bore (design.md sections 12, 13, 14 and 17 Conflux). 2x2 on a vein, +16 Lumen per worker-day,
## its own Dimming factor (x0.4, not the vein x0.25), blight r5 every day, planet -0.05 a day. All numbers are data.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "conflux"
	s.planet_health_override = 100.0


func _vein_spot() -> Vector2i:
	var def := reg.get_building("vein_bore")
	for y in MapState.HEIGHT - 1:
		for x in MapState.WIDTH - 1:
			var o := Vector2i(x, y)
			if not s.can_place("vein_bore", o, true)["ok"]:
				continue
			for fy in range(o.y, o.y + def.size.y):
				for fx in range(o.x, o.x + def.size.x):
					if s.map.terrain_id_at(fx, fy) == "lumen_vein":
						return o
	return Vector2i(-1, -1)


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _within(t: Vector2i, b: Building, r: int) -> bool:
	for ft in b.tiles():
		var d := t - ft
		if d.x * d.x + d.y * d.y <= r * r:
			return true
	return false


func test_row_matches_the_conflux_table() -> void:
	var d := reg.get_building("vein_bore")
	assert_eq(d.era, "conflux")
	assert_eq(d.size, Vector2i(2, 2))
	assert_eq(d.cost, {"materials": 200, "gold": 80, "cut_stone": 40, "tools": 20})
	assert_eq(d.worker_slots, 4)
	assert_eq(d.upkeep_lumen, 0.0)
	assert_eq(d.placement_rule, "on_vein")
	assert_true(d.vein_extractor)
	assert_eq(d.recipe.outputs, {"lumen": 16.0}, "+16 L per worker-day")
	assert_eq(d.blight_radius, 5)
	assert_eq(d.blight_period_days, 1)
	assert_almost_eq(d.health_per_day, -0.05, 0.00001)
	assert_almost_eq(d.dimming_vein_factor, 0.4, 0.00001)


# AC1: blights one tile every day inside radius 5.
func test_bore_blights_radius_5_every_day() -> void:
	var o := _vein_spot()
	assert_ne(o, Vector2i(-1, -1), "a 2x2 vein spot on seed 42")
	var id := s.place_building_instant("vein_bore", o)
	assert_gt(id, -1)
	var b: Building = s.buildings[id]
	assert_eq(BlightSystem.count(s), 0)
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 1, "one tile after the first day")
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_blighted(x, y):
				assert_true(_within(Vector2i(x, y), b, 5), "inside radius 5 of the footprint")
	s.step_days(2)
	assert_eq(BlightSystem.count(s), 3, "one more tile every day")


# AC1: a working Bore drains the planet 0.05 a day; unstaffed it drains nothing.
func test_bore_drains_the_planet_005_a_day() -> void:
	var o := _vein_spot()
	var b: Building = s.buildings[s.place_building_instant("vein_bore", o)]
	var ph := s.get_system(PlanetHealthSystem) as PlanetHealthSystem
	var before := ph.daily_breakdown(s)["buildings"] as float
	assert_almost_eq(before, 0.0, 0.00001, "no worker, no drain")
	var c := Citizen.new()
	c.id = 9001
	c.job_id = b.id
	c.job_kind = Citizen.JOB_WORK
	s.citizens[c.id] = c
	assert_almost_eq(ph.daily_breakdown(s)["buildings"] as float, -0.05, 0.00001, "staffed: -0.05 a day")


# AC2: the Bore's own x0.4 in a Dimming, an ordinary extractor stays at the planet's x0.25.
func test_bore_uses_its_own_dimming_multiplier() -> void:
	var bore := Building.new()
	bore.def = reg.get_building("vein_bore")
	var tap := Building.new()
	tap.def = reg.get_building("lumen_tap")
	_to_day(WINTER - 1)
	assert_eq(DimmingSystem.output_modifier(s, bore), 1.0, "no Dimming yet")
	_to_day(WINTER)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, bore), 0.4)
	assert_eq(DimmingSystem.output_modifier(s, tap), 0.25)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	assert_almost_eq(prod.multiplier(s, bore) / prod.multiplier(s, tap), 0.4 / 0.25, 0.0001,
			"same vein factor, same Dimming: the Bore keeps 1.6 times the tap's output")


# +16 L per worker-day: the recipe amount, scaled like any recipe.
func test_bore_makes_16_lumen_per_worker_day() -> void:
	var o := _vein_spot()
	var b: Building = s.buildings[s.place_building_instant("vein_bore", o)]
	assert_eq(b.def.recipe.outputs["lumen"], 16.0)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var vein := PlanetHealthSystem.vein_factor_at(s, 100.0)
	assert_almost_eq(prod.multiplier(s, b), vein, 0.0001, "no Dimming: only the vein factor scales it")
