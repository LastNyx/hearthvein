extends GutTest
## Ticket 15: Dimming schedule, forecast, output multipliers, light and darkness.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const AUTUMN := 2 * GameClock.DAYS_PER_SEASON  # total day of autumn day 1
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement
var d: DimmingSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	d = s.get_system(DimmingSystem)
	s.planet_health_override = 100.0


func _to_day(day: int) -> void:
	# keep everyone fed so the population (and light need) stays put
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func test_forecast_one_season_before_with_length() -> void:
	_to_day(AUTUMN - 1)
	assert_eq(s.events.log_of("dimming_forecast").size(), 0)
	_to_day(AUTUMN)
	var f := s.events.log_of("dimming_forecast")
	assert_eq(f.size(), 1)
	assert_eq(f[0]["data"]["start_day"], WINTER)
	assert_eq(f[0]["data"]["length"], 2)
	assert_eq(f[0]["hour"], AUTUMN * DAY)
	assert_eq(d.status(s)["state"], "forecast")
	assert_eq(d.status(s)["days_until"], 8)
	# length is fixed at forecast time
	s.planet_health_override = 0.0
	_to_day(WINTER)
	assert_eq(d.status(s)["length"], 2)


func test_length_by_health() -> void:
	assert_eq(DimmingSystem.length_for(s, "camp", 100.0), 2)
	assert_eq(DimmingSystem.length_for(s, "camp", 50.0), 3)
	assert_eq(DimmingSystem.length_for(s, "village", 100.0), 3)
	s.planet_health_override = 50.0
	_to_day(AUTUMN)
	assert_eq(s.events.log_of("dimming_forecast")[0]["data"]["length"], 3)


func test_multipliers_only_during_dimming() -> void:
	var tap := s.place_building_instant("lumen_tap", Vector2i(-1, -1))
	assert_eq(tap, -1)
	var vein := Building.new()
	vein.def = reg.get_building("lumen_tap")
	var forager := Building.new()
	forager.def = reg.get_building("forager")
	var tent := Building.new()
	tent.def = reg.get_building("tent")
	_to_day(WINTER - 1)
	assert_eq(DimmingSystem.output_modifier(s, vein), 1.0)
	_to_day(WINTER)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, vein), 0.25)
	assert_eq(DimmingSystem.output_modifier(s, forager), 0.5)
	assert_eq(DimmingSystem.output_modifier(s, tent), 1.0)
	assert_eq(s.events.log_of("dimming_started").size(), 1)
	_to_day(WINTER + 2)
	assert_false(DimmingSystem.is_active(s))
	assert_eq(s.events.log_of("dimming_ended").size(), 1)
	assert_eq(DimmingSystem.output_modifier(s, vein), 1.0)
	assert_eq(DimmingSystem.output_modifier(s, forager), 1.0)
	assert_true(s.get_system(ProductionSystem).modifiers.has(DimmingSystem.output_modifier))


func test_light_drawn_raw_then_cells_and_darkness_blocks_growth() -> void:
	var pop := s.citizens.size()
	var need := 0.5 * pop
	# plenty of raw Lumen: no darkness
	_to_day(WINTER - 1)
	s.hearth.inventory.add("lumen", 100.0)
	_to_day(WINTER)
	assert_false(DimmingSystem.is_dark(s))
	assert_almost_eq(d.last_light["drawn_lumen"], need, 0.001)
	assert_eq(d.last_light["drawn_cells"], 0.0)
	# raw runs out: cells cover the rest
	s.hearth.inventory.remove("lumen", 1000.0)
	s.hearth.inventory.add("lumen", 1.0)  # leaks 3% before the day's draw: 0.97 left
	s.hearth.inventory.add("lumen_cells", 10.0)
	_to_day(WINTER + 1)
	assert_false(DimmingSystem.is_dark(s))
	assert_almost_eq(d.last_light["drawn_cells"], (need - 0.97) / 5.0, 0.001)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen_cells"), 10.0 - (need - 0.97) / 5.0, 0.001)


func test_light_shortfall_sets_darkness_and_blocks_growth() -> void:
	s.hearth.inventory.remove("lumen", 1000.0)
	s.spirit_override = 100.0
	var g := s.get_system(GrowthSystem) as GrowthSystem
	g.bar = g.bar_size_now(s)  # a full bar would produce a citizen
	s.hearth.inventory.add("food", 500.0)
	var hook_before := (s.get_system(SpiritSystem) as SpiritSystem).factor_value(s, "darkness")
	assert_eq(hook_before, 0.0)
	_to_day(WINTER - 1)
	var pop := s.citizens.size()
	_to_day(WINTER)
	assert_true(DimmingSystem.is_dark(s))
	assert_eq(s.events.log_of("darkness_started").size(), 1)
	assert_eq((s.get_system(SpiritSystem) as SpiritSystem).factor_value(s, "darkness"), -20.0)
	assert_eq(s.citizens.size(), pop)
	assert_eq(g.last_day["grown"], 0)
	assert_eq(g.last_day["immigrated"], 0)
	# beds for growth exist (tents), still none arrives; after the Dimming it is lifted
	_to_day(WINTER + 2)
	assert_false(DimmingSystem.is_dark(s))
	assert_eq(s.events.log_of("darkness_ended").size(), 1)
	assert_eq((s.get_system(SpiritSystem) as SpiritSystem).factor_value(s, "darkness"), 0.0)
