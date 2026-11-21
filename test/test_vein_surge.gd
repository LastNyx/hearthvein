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
