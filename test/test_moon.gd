extends GutTest
## Ticket 145: moon phases (spec .scratch/v1/night-shift-spec.md N9). An 8-day cycle, phase = day % 8: day 1 new moon,
## day 5 full moon. Full moon: lamps +1 radius and Spirit +2 that night. New moon: Glowcap Grove +25%. Others neutral.
## The clock dial's model returns the phase.

const SEED := 42

var reg: DataRegistry
var dn: DayNightDef


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	dn = reg.day_night


## A fresh settlement with the growth system off and a road strip east of the Hearth with clear land around it.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 24):
		for y in range(hs.y - 4, hs.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Moves the clock to cycle day `day` (1..8) at `hour`.
func _set_clock(s: Settlement, day: int, hour: int) -> void:
	s.clock.total_hours = ((day - 1) + 8 * 3) * 24 + hour


func _lamp(s: Settlement, dx: int) -> Building:
	var hs := s.map.hearth_spot
	var bid := s.place_building_instant("lamp", Vector2i(hs.x + dx, hs.y + 1))
	assert_true(bid >= 0, "lamp placed")
	var lamp: Building = s.buildings.get(bid)
	lamp.input_buffer.add("wood", 5.0)
	return lamp


func test_data_numbers() -> void:
	assert_eq([dn.moon_cycle_days, dn.moon_new_day, dn.moon_full_day], [8, 1, 5])
	assert_eq([dn.moon_full_lamp_bonus, dn.moon_full_spirit, dn.moon_new_glowcap], [1, 2.0, 1.25])
	assert_eq(reg.errors, [] as Array[String])


func test_phase_by_day() -> void:
	for day in range(1, 9):
		var total := day - 1 + 8 * 5
		assert_eq(Moon.cycle_day(total, dn), day, "cycle day %d" % day)
		assert_eq(Moon.is_new(total, dn), day == 1)
		assert_eq(Moon.is_full(total, dn), day == 5)
		assert_eq(Moon.phase(total, dn), day - 1, "phase counts from the new moon")
	assert_eq(Moon.phase_name(0, dn), "New moon")
	assert_eq(Moon.phase_name(4, dn), "Full moon")
	assert_eq(Moon.cycle_day(8, dn), 1, "the cycle repeats every 8 days")
	assert_almost_eq(Moon.lit_fraction(0, dn), 0.0, 0.001)
	assert_almost_eq(Moon.lit_fraction(4, dn), 1.0, 0.001)


func test_full_moon_lamp_radius_plus_one() -> void:
	var s := _new_settlement()
	var lamp := _lamp(s, 6)
	var base := lamp.lamp_radius(reg)
	_set_clock(s, 3, 12)
	s.step_hours(7)  # 19:00 on an ordinary day
	assert_eq(s.lamp_radius(lamp), base, "neutral night: the lamp's own radius")
	var edge := Vector2i(lamp.origin.x + base + 1, lamp.origin.y)
	assert_false(s.is_tile_lit(edge), "one tile past the radius is dark")
	_set_clock(s, 5, 12)
	s.step_hours(7)
	assert_true(s.is_lamp_hour())
	assert_eq(s.lamp_radius(lamp), base + 1, "full moon: radius +1")
	assert_true(s.is_tile_lit(edge), "the lit-tile cache follows the moon")
	s.step_hours(11)  # 06:00 the next morning: still the same night
	assert_eq(s.lamp_radius(lamp), base + 1, "small hours still belong to the full-moon night")
	assert_eq(NightRenderModel.pools(s)[0]["radius"], base + 1, "the lamp pool is drawn one wider")


func test_full_moon_spirit_plus_two_that_night_only() -> void:
	var s := _new_settlement()
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	_set_clock(s, 3, 22)
	assert_almost_eq(sp.factor_value(s, "moon"), 0.0, 0.001, "ordinary night")
	var t0 := sp.target(s)
	_set_clock(s, 5, 22)
	assert_almost_eq(sp.factor_value(s, "moon"), 2.0, 0.001, "full moon night")
	assert_almost_eq(sp.target(s) - t0, 2.0, 0.001, "target +2")
	assert_eq(sp.breakdown(s)["factors"].has("moon"), true)
	_set_clock(s, 5, 12)
	assert_almost_eq(sp.factor_value(s, "moon"), 0.0, 0.001, "not by day")


func test_new_moon_glowcap_plus_25_percent() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var origin := Vector2i(hs.x + 8, hs.y - 2)
	s.set_terrain(Vector2i(origin.x - 1, origin.y), "forest")
	s.set_terrain(Vector2i(origin.x - 1, origin.y + 1), "forest")  # shade for the Grove
	var bid := s.place_building_instant("glowcap_grove", origin)
	assert_true(bid >= 0, "grove placed")
	var grove: Building = s.buildings[bid]
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	_set_clock(s, 2, 23)
	var base := prod.multiplier(s, grove)
	_set_clock(s, 1, 23)
	assert_almost_eq(prod.multiplier(s, grove), base * 1.25, 0.0001, "new moon: Glowcap +25%")
	_set_clock(s, 5, 23)
	assert_almost_eq(prod.multiplier(s, grove), base, 0.0001, "full moon: Glowcap neutral")
	var mill := s.place_building_instant("sawmill", Vector2i(hs.x + 14, hs.y - 3))
	_set_clock(s, 1, 23)
	var m_new := prod.multiplier(s, s.buildings[mill])
	_set_clock(s, 2, 23)
	assert_almost_eq(prod.multiplier(s, s.buildings[mill]), m_new, 0.0001, "other buildings ignore the moon")


# The new-moon bonus is a BuildingDef flag (new_moon_boost), not a test of the Grove's id.
func test_new_moon_bonus_follows_the_def_flag() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var mill_id := s.place_building_instant("sawmill", Vector2i(hs.x + 14, hs.y - 3))
	var mill: Building = s.buildings[mill_id]
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	assert_true(s.registry.get_building("glowcap_grove").new_moon_boost, "the Grove carries the flag in data")
	assert_false(mill.def.new_moon_boost, "the Sawmill does not")
	_set_clock(s, 2, 23)
	var base := prod.multiplier(s, mill)
	_set_clock(s, 1, 23)
	assert_almost_eq(prod.multiplier(s, mill), base, 0.0001, "no flag, no bonus")
	mill.def.new_moon_boost = true
	assert_almost_eq(prod.multiplier(s, mill), base * 1.25, 0.0001, "the flag alone gives the new-moon bonus")
	mill.def.new_moon_boost = false


func test_dial_model_returns_the_phase() -> void:
	for day in range(1, 9):
		var m := ClockDial.moon_model(day - 1 + 16, dn)
		assert_eq(m["phase"], day - 1)
		assert_eq(m["full"], day == 5)
		assert_eq(m["new"], day == 1)
	assert_eq(ClockDial.moon_model(0, dn)["name"], "New moon")
	assert_eq(ClockDial.moon_model(4, dn)["name"], "Full moon")
	assert_true(ClockDial.moon_model(1, dn)["waxing"])
	assert_false(ClockDial.moon_model(5, dn)["waxing"])


func test_dial_pixels_follow_the_phase() -> void:
	var lit_new := 0
	var lit_full := 0
	var disc := 0
	for py in range(-ClockDial.MOON_PX, ClockDial.MOON_PX + 1):
		for px in range(-ClockDial.MOON_PX, ClockDial.MOON_PX + 1):
			if ClockDial.moon_pixel(px, py, 0, 8) >= 0:
				disc += 1
			if ClockDial.moon_pixel(px, py, 0, 8) == 1:
				lit_new += 1
			if ClockDial.moon_pixel(px, py, 4, 8) == 1:
				lit_full += 1
	assert_eq(lit_new, 0, "new moon: no lit pixels")
	assert_eq(lit_full, disc, "full moon: the whole disc is lit")
	assert_eq(ClockDial.moon_pixel(3, 0, 2, 8), 1, "first quarter lights the right side")
	assert_eq(ClockDial.moon_pixel(-3, 0, 2, 8), 0)
	assert_eq(ClockDial.moon_pixel(-3, 0, 6, 8), 1, "last quarter lights the left side")


func test_hud_model_tags_the_full_moon_night() -> void:
	var s := _new_settlement()
	var model := HudModel.new(s)
	_set_clock(s, 5, 23)
	assert_eq(model.moon_tag(), " - Full moon")
	assert_true(model.moon_tooltip().contains("Full moon"))
	_set_clock(s, 5, 12)
	assert_eq(model.moon_tag(), "", "no tag by day")
	_set_clock(s, 4, 23)
	assert_eq(model.moon_tag(), "")
	assert_true(model.moon_tooltip().contains("Waxing gibbous"))
