extends GutTest
## Ticket 150: vein surge after a Dimming (spec .scratch/v1/night-shift-spec.md N8).
##
## When a Dimming ends, every Lumen producer on a vein (vein_extractor) makes PlanetDef.vein_surge_factor of its
## output for PlanetDef.vein_surge_days days; the timer is saved.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY

var reg: DataRegistry
var s: Settlement
var d: DimmingSystem
var vein: Building
var farm: Building


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	d = s.get_system(DimmingSystem) as DimmingSystem
	# Keep every other output modifier at 1.0 so the surge factor is the only difference: full planet health gives
	# the vein yield 1.0, and a middling Spirit gives no work bonus.
	s.planet_health_override = 100.0
	s.spirit_override = 60.0
	s.hearth.inventory.add("food", 500.0)
	s.hearth.inventory.add("lumen", 500.0)
	vein = _bld("lumen_tap")
	farm = _bld("forager")


func _bld(id: String) -> Building:
	var b := Building.new()
	b.def = reg.get_building(id)
	return b


## A regular Dimming that ends at the start of tomorrow (today is day 0).
func _dimming_ending_tomorrow() -> void:
	d._start_day = s.clock.total_days()
	d._length = 1
	d._active = true


func _mult(settlement: Settlement, b: Building) -> float:
	return (settlement.get_system(ProductionSystem) as ProductionSystem).multiplier(settlement, b)


## Criterion: x1.5 for exactly 2 days after a Dimming, then normal; the timer is saved.
func test_lumen_veins_make_1_5_for_exactly_two_days_then_normal() -> void:
	assert_almost_eq(_mult(s, vein), 1.0, 0.0001, "no surge before a Dimming")
	_dimming_ending_tomorrow()
	s.step_hours(DAY)  # the Dimming ends as day 1 starts
	assert_false(DimmingSystem.is_active(s))
	assert_true(DimmingSystem.vein_surge(s), "the surge starts the day the Dimming ends")
	assert_eq(DimmingSystem.vein_surge_day(s), 1)
	assert_almost_eq(_mult(s, vein), 1.5, 0.0001, "a vein extractor makes x1.5")
	assert_almost_eq(_mult(s, farm), 1.0, 0.0001, "a building off the veins is untouched")
	s.step_hours(DAY)  # day 2
	assert_eq(DimmingSystem.vein_surge_day(s), 2)
	assert_almost_eq(_mult(s, vein), 1.5, 0.0001, "still surging")
	s.step_hours(DAY - 1)  # 23:00 on day 2
	assert_almost_eq(_mult(s, vein), 1.5, 0.0001, "the last hour of day 2 still surges")
	s.step_hours(1)  # day 3 starts
	assert_false(DimmingSystem.vein_surge(s))
	assert_almost_eq(_mult(s, vein), 1.0, 0.0001, "normal again after two days")
	assert_true(s.get_system(ProductionSystem).modifiers.has(DimmingSystem.vein_surge_modifier),
			"the surge is a production modifier")


## Criterion: the surge timer is saved, so a load finishes the two days instead of restarting them or losing them.
func test_the_surge_timer_survives_a_save_and_load() -> void:
	_dimming_ending_tomorrow()
	s.step_hours(DAY)  # surge day 1
	var r := Settlement.from_dict(s.to_dict(), reg)
	assert_true(DimmingSystem.vein_surge(r), "the loaded save is still surging")
	assert_eq(DimmingSystem.vein_surge_day(r), 1)
	assert_almost_eq(_mult(r, _bld("lumen_tap")), 1.5, 0.0001)
	r.step_hours(DAY)  # day 2
	assert_true(DimmingSystem.vein_surge(r), "the loaded timer keeps the second day")
	r.step_hours(DAY)  # day 3
	assert_false(DimmingSystem.vein_surge(r), "the loaded timer still ends after two days")
	assert_almost_eq(_mult(r, _bld("lumen_tap")), 1.0, 0.0001)


## Ticket 176: the surge factor and length come from PlanetDef.
func test_the_surge_factor_and_length_come_from_data() -> void:
	reg.planet.vein_surge_factor = 2.0
	reg.planet.vein_surge_days = 3
	_dimming_ending_tomorrow()
	s.step_hours(DAY)
	var m_start := _mult(s, vein)
	var len_start := DimmingSystem.vein_surge_days(s)
	s.step_hours(DAY * 2)  # day 3: the third surge day
	var third := DimmingSystem.vein_surge(s)
	s.step_hours(DAY)  # day 4
	var after := DimmingSystem.vein_surge(s)
	reg.planet.vein_surge_factor = 1.5
	reg.planet.vein_surge_days = 2
	assert_almost_eq(m_start, 2.0, 0.0001, "the data factor")
	assert_eq(len_start, 3)
	assert_true(third, "a 3 day surge still runs on its third day")
	assert_false(after, "and ends after it")


# ---------------------------------------------------------------- ticket 178

## Steps `days` whole days, topping the food up so nobody starves.
func _days(settlement: Settlement, days: int) -> void:
	for i in days:
		settlement.hearth.inventory.add("food", 50.0)
		settlement.step_hours(DAY)


## The Great Dimming running from today for its whole length.
func _great_from_today() -> GreatDimmingSystem:
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	g._start_day = s.clock.total_days()
	g._active = true
	return g


## Criterion: the Great Dimming's end starts a 2 day surge.
func test_the_great_dimming_ending_starts_a_two_day_surge() -> void:
	_great_from_today()
	_days(s, reg.planet.great_dimming_days - 1)
	assert_true(GreatDimmingSystem.is_active(s), "the Great Dimming is on")
	assert_false(DimmingSystem.vein_surge(s), "no surge while it runs")
	_days(s, 1)
	assert_false(GreatDimmingSystem.is_active(s), "the Great Dimming has ended")
	assert_true(DimmingSystem.vein_surge(s), "its end starts the surge")
	assert_eq(DimmingSystem.vein_surge_day(s), 1)
	assert_almost_eq(_mult(s, vein), 1.5, 0.0001)
	_days(s, 2)
	assert_false(DimmingSystem.vein_surge(s), "two days later it is over")


## Criterion: a regular Dimming that yields to the Great one starts none (an active one, and a forecast one).
func test_a_dimming_swallowed_by_the_great_one_starts_no_surge() -> void:
	_dimming_ending_tomorrow()
	d._length = 5  # would run on
	_great_from_today()
	s.step_hours(DAY)  # the day hook: the regular Dimming yields
	assert_eq(s.events.log_of("dimming_ended").size(), 1, "the regular Dimming ended")
	assert_false(DimmingSystem.vein_surge(s), "yielding to the Great Dimming is no reward")
	assert_eq(s.events.log_of("vein_surge_started").size(), 0)
	# A forecast regular Dimming inside the Great one's window is dropped, also with no surge.
	var s2 := Settlement.new_game(SEED, reg)
	var d2 := s2.get_system(DimmingSystem) as DimmingSystem
	var g2 := s2.get_system(GreatDimmingSystem) as GreatDimmingSystem
	g2._start_day = 1
	d2._start_day = 2
	d2._length = 2
	s2.hearth.inventory.add("food", 500.0)
	s2.step_hours(DAY * 4)
	assert_false(DimmingSystem.vein_surge(s2))
	assert_eq(s2.events.log_of("vein_surge_started").size(), 0)


## Criterion: the notice, the objectives line and the selection line.
func test_the_notice_the_objectives_line_and_the_selection_line() -> void:
	var nc := NotificationCenter.new(s)
	var hud := HudModel.new(s)
	assert_eq(hud.vein_surge_text(vein), "", "no line outside a surge")
	assert_false(hud.objectives_dimming_lines().any(func(l: String) -> bool: return l.begins_with("Vein surge")))
	_dimming_ending_tomorrow()
	s.step_hours(DAY)
	assert_true(nc.items.any(func(i: Dictionary) -> bool: return i["text"] == "Vein surge: Lumen +50% for 2 days"),
			"the notice")
	assert_true(nc.is_active("vein_surge"))
	assert_has(hud.objectives_dimming_lines(), "Vein surge: day 1 of 2")
	assert_eq(hud.vein_surge_text(vein), "Vein surge: +50% for 2 days (was 16)", "nominal output 8 x 2 workers")
	assert_eq(hud.vein_surge_text(farm), "", "none on a building off the veins")
	s.step_hours(DAY)
	assert_has(hud.objectives_dimming_lines(), "Vein surge: day 2 of 2")
	s.step_hours(DAY)
	assert_false(nc.is_active("vein_surge"), "the notice clears when the surge ends")
	assert_eq(hud.vein_surge_text(vein), "")
	assert_false(hud.objectives_dimming_lines().any(func(l: String) -> bool: return l.begins_with("Vein surge")))
