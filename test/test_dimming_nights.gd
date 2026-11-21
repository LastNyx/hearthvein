extends GutTest
## Ticket 148: long nights in a Dimming (spec .scratch/v1/night-shift-spec.md N8).
##
## One source of truth for tonight's night window: normal shift 20-06 and lamps 19-07; in a Dimming the night runs
## 16-09 for the shift, the lamps, the tint and the walker schedule, and the day shift shrinks to 09-16.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var d: DimmingSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = _new_settlement()
	d = s.get_system(DimmingSystem) as DimmingSystem


## A fresh settlement with the growth system off, a road strip east of the Hearth and clear land around it.
func _new_settlement() -> Settlement:
	var out := Settlement.new_game(SEED, reg)
	out.systems.erase(out.get_system(GrowthSystem))
	var hs := out.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 20):
		for y in range(hs.y - 3, hs.y + 3):
			if out.map.terrain_id_at(x, y) == "forest":
				out.set_terrain(Vector2i(x, y), "grass")
		if out.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			out.place_road(Vector2i(x, hs.y))
	return out


## Places a finished building on the north side of the road strip `dx` tiles east of the Hearth (or `dy` tiles south).
func _put(settlement: Settlement, id: String, dx: int, dy: int = 0) -> Building:
	var def := reg.get_building(id)
	var hs := settlement.map.hearth_spot
	var at := Vector2i(hs.x + dx, hs.y - def.size.y) if dy == 0 else Vector2i(hs.x + dx, hs.y + dy)
	var bid := settlement.place_building_instant(id, at)
	assert_true(bid >= 0, "%s placed at %s" % [id, at])
	return settlement.buildings.get(bid)


## A regular Dimming starting today for `length` days (the fixture the HUD reads; no stepping needed).
func _dimming(settlement: Settlement, length: int = 4) -> void:
	var dsys := settlement.get_system(DimmingSystem) as DimmingSystem
	dsys._start_day = settlement.clock.total_days()
	dsys._length = length
	dsys._active = true


func _keep_citizens(settlement: Settlement, n: int) -> void:
	while settlement.citizens.size() > n:
		settlement.remove_citizen(settlement.citizens.keys().max())


## Citizens in a `kind` job at `b` on the given shift.
func _staff(settlement: Settlement, b: Building, kind: String, night: bool) -> Array:
	var out: Array = []
	for cid in settlement.citizens:
		var c: Citizen = settlement.citizens[cid]
		if c.job_id == b.id and c.job_kind == kind and (c.shift == "night") == night:
			out.append(c)
	return out


## Hours a [start, end) window covers, wrapping midnight.
func _hours(w: Vector2i) -> int:
	return posmod(w.y - w.x, 24)


## Criterion 1: the night window is 20-06 (shift) and 19-07 (lamps) normally, and 16-09 for both in a Dimming; the
## shift, the lamps, the clock tag and the objectives line all read it.
func test_night_window_normal_vs_dimming_and_shift_and_lamps_follow_it() -> void:
	var m := HudModel.new(s)
	assert_eq(s.night_window(), Vector2i(20, 6), "normal night shift 20-06")
	assert_eq(s.lamp_window(), Vector2i(19, 7), "normal lamps 19-07")
	assert_true(s.is_night(20), "the night shift opens at 20:00")
	assert_false(s.is_night(19), "19:00 is still the day shift")
	assert_true(s.is_night(5), "05:00 is the last night hour")
	assert_false(s.is_night(6), "06:00 the night shift is over")
	assert_true(s.is_lamp_hour(19), "the lamps light at 19:00")
	assert_true(s.is_lamp_hour(6), "and stay on until 07:00")
	assert_false(s.is_lamp_hour(7), "dark from 07:00")
	assert_eq(m.dimming_night_tag(), "", "no tag outside a Dimming")

	_dimming(s)
	assert_eq(s.night_window(), Vector2i(16, 9), "a Dimming night shift runs 16-09")
	assert_eq(s.lamp_window(), Vector2i(16, 9), "the lamps follow the same long night")
	assert_true(s.is_night(16), "the night shift opens at 16:00")
	assert_false(s.is_night(15), "15:00 is still day")
	assert_true(s.is_night(8), "08:00 is still night")
	assert_false(s.is_night(9), "the long night ends at 09:00")
	assert_true(s.is_lamp_hour(16), "the lamps light at 16:00")
	assert_false(s.is_lamp_hour(15), "dark lamps before 16:00")
	assert_false(s.is_lamp_hour(9), "the lamps are out at 09:00")
	assert_eq(m.dimming_night_tag(), "Dimming: night 16-09", "the clock row carries the window")
	assert_string_contains(m.objectives_dimming_lines()[1], "Nights run 16-09", "the objectives line names it")

	# A fuelled lamp burns at the Dimming dusk (16) and is out at the Dimming dawn (9), not at 19/7.
	s.hearth.inventory.remove("wood", 1000.0)  # no stock for the haulers to refuel the lamp from
	var lamp := _put(s, "lamp", 5, 1)
	lamp.input_buffer.add("wood", 2.0)
	s.step_hours(16)  # 00:00 -> 16:00
	assert_true(s.is_lit(lamp), "the lamp lit at 16:00")
	assert_almost_eq(lamp.input_buffer.amount_of("wood"), 1.0, 0.001, "one fuel burnt at the Dimming dusk")
	s.step_hours(17)  # 16:00 -> 09:00 the next morning
	assert_false(s.is_lit(lamp), "out at 09:00, like the long night")


## Criterion 2: the day shift is the normal 06-18 (12 hours); in a Dimming it shrinks to 09-16 (7 hours), so a day
## worker is home by 17:00 where a normal day still has them at work.
func test_day_production_hours_are_shorter_in_a_dimming() -> void:
	assert_eq(s.day_window(), Vector2i(6, 18), "the normal day shift 06-18")
	assert_eq(_hours(s.day_window()), 12, "12 day production hours")
	var mill := _put(s, "sawmill", 4)
	_keep_citizens(s, 5)
	mill.input_buffer.add("wood", 20.0)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var day: Citizen = _staff(s, mill, Citizen.JOB_WORK, false)[0]
	s.step_hours(12)  # noon
	assert_true(ws.is_at_work(day.id), "a normal day worker is at work at noon")
	s.step_hours(5)  # 17:00
	assert_true(ws.is_at_work(day.id), "still at work at 17:00 on a normal day")

	var s2 := _new_settlement()
	_dimming(s2)
	assert_eq(s2.day_window(), Vector2i(9, 16), "a Dimming day shrinks to 09-16")
	assert_eq(_hours(s2.day_window()), 7, "7 day production hours, shorter than 12")
	var mill2 := _put(s2, "sawmill", 4)
	_keep_citizens(s2, 5)
	mill2.input_buffer.add("wood", 20.0)
	var ws2 := s2.get_system(WalkerSystem) as WalkerSystem
	var day2: Citizen = _staff(s2, mill2, Citizen.JOB_WORK, false)[0]
	s2.step_hours(12)  # noon
	assert_true(ws2.is_at_work(day2.id), "at work at noon in the Dimming")
	s2.step_hours(5)  # 17:00
	assert_false(ws2.is_at_work(day2.id), "home by 17:00: the Dimming day ended at 16:00")


## Ticket 172: tonight's moon follows the lamp window's end (09:00 in a Dimming), not the normal 07:00.
func test_moon_day_holds_until_the_dimming_night_ends() -> void:
	s.clock.total_hours = 29 * 24 + 23  # evening of cycle day 6, so the next small hours are cycle day 6's night
	_dimming(s)
	var evening := s.moon_days()
	s.clock.total_hours = 30 * 24 + 8
	assert_eq(s.moon_days(), evening, "08:00 still belongs to last evening's night")
	s.clock.total_hours = 30 * 24 + 9
	assert_eq(s.moon_days(), evening + 1, "09:00 the moon moves on")


## Ticket 172: a full-moon lamp keeps its extra radius until the Dimming night ends at 09:00.
func test_full_moon_lamp_keeps_its_radius_until_the_dimming_dawn() -> void:
	var lamp := _put(s, "lamp", 5, 1)
	var base := lamp.lamp_radius(reg)
	var full_day := 5 + 8 * 3  # cycle day 5 (see test_moon._set_clock) is the full moon
	s.clock.total_hours = (full_day - 1) * 24 + 23
	_dimming(s)
	assert_eq(s.lamp_radius(lamp), base + 1, "full moon at 23:00")
	s.clock.total_hours = full_day * 24 + 8
	assert_eq(s.lamp_radius(lamp), base + 1, "still the full-moon night at 08:00")
	s.clock.total_hours = full_day * 24 + 9
	assert_eq(s.lamp_radius(lamp), base, "back to the lamp's own radius at 09:00")


## A lit Tavern with crops and a lamp, 4 citizens, the clock at `hour` of day 0 (a Dimming when `dimming`).
func _tavern_night(settlement: Settlement, hour: int, dimming: bool) -> Building:
	var tavern := _put(settlement, "tavern", 4)
	var lamp := _put(settlement, "lamp", 4, 1)
	lamp.input_buffer.add("wood", 3.0)
	tavern.input_buffer.add("crops", 8.0)
	settlement.hearth.inventory.remove("wood", 1000.0)
	_keep_citizens(settlement, 4)
	settlement.clock.total_hours = hour
	if dimming:
		_dimming(settlement)
	return tavern


## Ticket 173: in a Dimming a lit Tavern with a night worker drinks at 16:00, not 20:00, and is still serving at 07:00.
func test_tavern_drinks_at_the_dimming_dusk_and_serves_until_its_dawn() -> void:
	var tavern := _tavern_night(s, 14, true)
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	s.step_hours(1)  # 15:00
	assert_eq(tavern.input_buffer.amount_of("crops"), 8.0, "nothing drunk by day")
	s.step_hours(1)  # 16:00
	assert_true(s.is_lit(tavern), "the lamp lit at the Dimming dusk")
	assert_almost_eq(tavern.input_buffer.amount_of("crops"), 4.0, 0.001, "drank at 16:00")
	assert_gt(sp.factor_value(s, "tavern"), 0.0, "cheering from 16:00")
	s.step_hours(15)  # 07:00 next morning
	assert_eq(s.clock.hour(), 7)
	assert_gt(sp.factor_value(s, "tavern"), 0.0, "still serving at 07:00")
	assert_almost_eq(tavern.input_buffer.amount_of("crops"), 4.0, 0.001, "no second drink")
	s.step_hours(2)  # 09:00
	assert_eq(sp.factor_value(s, "tavern"), 0.0, "the long night is over")


## Ticket 173: a normal night is unchanged, the Tavern drinks at 20:00 and clears at 06:00.
func test_tavern_normal_night_is_still_20_to_06() -> void:
	var tavern := _tavern_night(s, 18, false)
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	s.step_hours(1)  # 19:00
	assert_eq(tavern.input_buffer.amount_of("crops"), 8.0, "not yet at 19:00")
	s.step_hours(1)  # 20:00
	assert_almost_eq(tavern.input_buffer.amount_of("crops"), 4.0, 0.001, "drank at 20:00")
	s.step_hours(9)  # 05:00
	assert_gt(sp.factor_value(s, "tavern"), 0.0, "serving at 05:00")
	s.step_hours(1)  # 06:00
	assert_eq(sp.save_state()["serving"].size(), 0, "the serving list clears at 06:00")
