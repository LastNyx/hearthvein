extends GutTest
## Ticket 45b: the Great Dimming (schedule, length, multipliers, light, planet health, reservoir pours, save).

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const SEASON := GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement
var gd: GreatDimmingSystem
var dim: DimmingSystem
var sky: SkyheartSystem
var gs: GridSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "ascendant"
	gd = s.get_system(GreatDimmingSystem)
	dim = s.get_system(DimmingSystem)
	sky = s.get_system(SkyheartSystem)
	gs = s.get_system(GridSystem)
	h = s.map.hearth_spot


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _spot(def_id: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(h.y - 14, h.y + 14):
		for x in range(h.x - 14, h.x + 14):
			var o := Vector2i(x, y)
			if not s.can_place(def_id, o, true)["ok"]:
				continue
			var d := absi(x - h.x) + absi(y - h.y)
			if d < best_d:
				best_d = d
				best = o
	return best


## Runs the real completion path: a Skyheart site finished stage by stage.
func _complete_skyheart() -> void:
	s.gold = 5000.0
	var id := s.place_building("skyheart", _spot("skyheart"))
	assert_true(id >= 0)
	var b: Building = s.buildings[id]
	for i in 4:
		var cost := b.effective_cost()
		for g in cost:
			if g != BuildingDef.GOLD:
				b.input_buffer.add(g, float(cost[g]))
		b.build_work = b.build_work_needed
		s.complete_site(b)
		sky.on_hour(s)  # pays the Crown's gold


func _grid_heart() -> Building:
	var id := s.place_building_instant("skyheart", _spot("skyheart"))
	assert_true(id >= 0)
	assert_true(s.place_building_instant("lumen_pylon", _spot("lumen_pylon")) >= 0)
	assert_true(GridSystem.on_grid(s, s.buildings[id]))
	return s.buildings[id]


func _bld(def_id: String) -> Building:
	var b := Building.new()
	b.def = reg.get_building(def_id)
	return b


func test_numbers_are_data() -> void:
	var pd := reg.planet
	assert_eq([pd.great_dimming_days, pd.great_dimming_vein_factor, pd.great_dimming_food_factor,
			pd.great_dimming_light, pd.great_dimming_day], [16, 0.1, 0.5, 0.75, -0.5])


func test_completion_mid_season_starts_the_season_after_next_season() -> void:
	_to_day(3)  # spring, day 4
	_complete_skyheart()
	var f := s.events.log_of("great_dimming_forecast")
	assert_eq(f.size(), 1)
	assert_eq(f[0]["data"]["start_day"], 2 * SEASON, "day 1 of summer's successor: 1 to 2 seasons of warning")
	_to_day(2 * SEASON - 1)
	assert_false(DimmingSystem.is_active(s))
	assert_eq(s.events.log_of("great_dimming_started").size(), 0)
	_to_day(2 * SEASON)
	assert_true(GreatDimmingSystem.is_active(s))
	assert_true(DimmingSystem.is_active(s), "the regular Dimming query is true too")
	assert_eq(s.events.log_of("great_dimming_started").size(), 1)


func test_completion_on_a_seasons_first_day_starts_next_season() -> void:
	_to_day(SEASON)
	_complete_skyheart()
	assert_eq(s.events.log_of("great_dimming_forecast")[0]["data"]["start_day"], 2 * SEASON)
	assert_eq(GreatDimmingSystem.start_for(0), SEASON)
	assert_eq(GreatDimmingSystem.start_for(1), 2 * SEASON)
	assert_eq(GreatDimmingSystem.start_for(SEASON - 1), 2 * SEASON)
	assert_eq(GreatDimmingSystem.start_for(SEASON), 2 * SEASON)


func test_lasts_sixteen_days_whatever_the_health_and_happens_once() -> void:
	s.planet_health_override = 5.0
	gd.schedule(s)
	var start := gd.start_day()
	_to_day(start)
	assert_true(GreatDimmingSystem.is_active(s))
	_to_day(start + 15)
	assert_true(GreatDimmingSystem.is_active(s), "day 16 of 16")
	_to_day(start + 16)
	assert_false(GreatDimmingSystem.is_active(s))
	assert_false(DimmingSystem.is_active(s))
	var e := s.events.log_of("great_dimming_ended")
	assert_eq(e.size(), 1)
	assert_eq(e[0]["data"]["population"], s.citizens.size())
	assert_eq(e[0]["data"]["planet_health"], 5.0)
	assert_eq(e[0]["hour"], (start + 16) * DAY)
	assert_true(GreatDimmingSystem.is_done(s))
	gd.schedule(s)
	assert_false(GreatDimmingSystem.is_pending(s), "only once per run")
	assert_eq(s.events.log_of("great_dimming_forecast").size(), 1)


func test_multipliers() -> void:
	gd.schedule(s)
	var vein := _bld("lumen_tap")
	var bore := _bld("vein_bore")
	var farm := _bld("farm")
	var gh := _bld("greenhouse")
	var forager := _bld("forager")
	var dock := _bld("fishing_dock")
	var aether := _bld("aether_collector")
	var tent := _bld("tent")
	assert_eq(DimmingSystem.output_modifier(s, vein), 1.0, "nothing before it starts")
	_to_day(gd.start_day())
	assert_eq(DimmingSystem.output_modifier(s, vein), 0.1)
	assert_eq(DimmingSystem.output_modifier(s, bore), 0.1, "the Bore's own 0.4 does not apply")
	assert_eq(DimmingSystem.output_modifier(s, farm), 0.5)
	assert_eq(DimmingSystem.output_modifier(s, gh), 0.5, "a greenhouse is no longer unaffected")
	assert_eq(DimmingSystem.output_modifier(s, forager), 0.5)
	assert_eq(DimmingSystem.output_modifier(s, dock), 1.0)
	assert_eq(DimmingSystem.output_modifier(s, aether), 0.5)
	assert_eq(DimmingSystem.output_modifier(s, tent), 1.0)
	for id in ["hydroponic_hall", "sky_garden", "bloom_orchard"]:
		assert_eq(DimmingSystem.output_modifier(s, _bld(id)), 0.5, id)


func test_light_need_is_three_quarters_even_with_a_beacon() -> void:
	assert_gt(s.place_building_instant("dawn_beacon", _spot("dawn_beacon")), -1)
	assert_eq(DimmingSystem.light_per_citizen(s), 0.35)
	gd.schedule(s)
	_to_day(gd.start_day())
	assert_eq(DimmingSystem.light_per_citizen(s), 0.75)
	assert_almost_eq(float(dim.last_light["need"]), 0.75 * s.citizens.size(), 0.001)


func test_planet_loses_half_a_point_a_day_in_the_breakdown() -> void:
	var ph := s.get_system(PlanetHealthSystem) as PlanetHealthSystem
	gd.schedule(s)
	var start := gd.start_day()
	_to_day(start - 1)
	assert_eq(ph.daily_breakdown(s)["extra"], 0.0)
	_to_day(start)
	assert_eq(ph.daily_breakdown(s)["extra"], -0.5)
	var before := ph.current(s)
	var total_before := ph.daily_breakdown(s)["total"] as float
	_to_day(start + 1)
	assert_almost_eq(ph.current(s) - before, total_before, 0.0001)
	_to_day(start + 16)
	assert_eq(ph.daily_breakdown(s)["extra"], 0.0)


func test_reservoir_feeds_grid_draw_only_during_it() -> void:
	var b := _grid_heart()
	var gid := gs.grid_of(s, b.id)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	sky._charge[b.id] = 500.0
	assert_eq(gs.draw(s, gid, 100.0), 0.0, "not before the Great Dimming")
	assert_eq(sky.reservoir_charge(b.id), 500.0)
	gd.schedule(s)
	_to_day(gd.start_day())
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	sky._charge[b.id] = 500.0
	s.hearth.inventory.add("lumen", 30.0)
	assert_almost_eq(gs.draw(s, gid, 100.0), 100.0, 0.001, "30 from the store, 70 from the reservoir")
	assert_almost_eq(sky.reservoir_charge(b.id), 430.0, 0.001, "last resort, after the stores")
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 0.0, 0.001)
	assert_almost_eq(gs.draw(s, gid, 1000.0), 430.0, 0.001, "never more than it holds")
	_to_day(gd.start_day() + 16)
	sky._charge[b.id] = 50.0
	assert_eq(gs.draw(s, gid, 10.0), 0.0, "closed again")


func test_reservoir_does_not_fill_while_it_is_on() -> void:
	var b := _grid_heart()
	var gid := gs.grid_of(s, b.id)
	s.hearth.inventory.add("lumen", 500.0)
	sky.on_hour(s)
	assert_almost_eq(sky.reservoir_charge(b.id), 40.0, 0.001, "fills normally before")
	gd.schedule(s)
	_to_day(gd.start_day())
	s.hearth.inventory.add("lumen", 500.0)
	var held := sky.reservoir_charge(b.id)
	sky.on_hour(s)
	assert_eq(sky.reservoir_charge(b.id), held)
	assert_gt(gs.supply(s, gid), 0.0)


func test_reservoir_covers_the_light_shortfall() -> void:
	var b := _grid_heart()
	for id in s.buildings:  # no Lumen anywhere
		var bb: Building = s.buildings[id]
		if bb.inventory != null:
			bb.inventory.remove("lumen", bb.inventory.amount_of("lumen"))
	sky._charge[b.id] = 1000.0
	gd.schedule(s)
	_to_day(gd.start_day() - 1)
	assert_false(DimmingSystem.is_dark(s))
	_to_day(gd.start_day())
	var need := 0.75 * s.citizens.size()
	assert_almost_eq(float(dim.last_light["drawn_reservoir"]), need, 0.001)
	assert_eq(dim.last_light["short"], 0.0)
	assert_false(DimmingSystem.is_dark(s), "the reservoir kept the lights on")
	assert_almost_eq(sky.reservoir_charge(b.id), 1000.0 - need, 0.01)
	# empty reservoir: darkness
	sky._charge[b.id] = 0.0
	_to_day(gd.start_day() + 1)
	assert_true(DimmingSystem.is_dark(s))
	assert_gt(float(dim.last_light["short"]), 0.0)


func test_no_regular_dimming_overlaps() -> void:
	# completion on day 3 -> starts day 16 (autumn), which swallows the winter Dimming (day 24).
	_to_day(3)
	gd.schedule(s)
	_to_day(2 * SEASON)
	assert_eq(s.events.log_of("dimming_forecast").size(), 0, "no regular forecast inside the window")
	_to_day(3 * SEASON + 2)
	assert_eq(s.events.log_of("dimming_started").size(), 0)
	assert_true(GreatDimmingSystem.is_active(s))
	assert_eq(dim.status(s)["great"], true)


func test_a_running_regular_dimming_ends_when_it_starts() -> void:
	_to_day(2 * SEASON)
	assert_eq(dim.status(s)["state"], "forecast")
	dim._length = 60  # a long regular one, to overlap
	_to_day(3 * SEASON)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(s.events.log_of("dimming_started").size(), 1)
	gd.schedule(s)  # on day 24: starts day 32
	assert_eq(gd.start_day(), 4 * SEASON)
	_to_day(4 * SEASON)
	assert_eq(s.events.log_of("dimming_ended").size(), 1, "the regular one yields")
	assert_true(DimmingSystem.is_active(s))
	assert_true(GreatDimmingSystem.is_active(s))
	_to_day(4 * SEASON + 20)
	assert_eq(s.events.log_of("dimming_started").size(), 1, "none starts during it")


func test_hud_text() -> void:
	var hud := HudModel.new(s)
	assert_eq(hud.dimming_text(), "No Dimming expected")
	gd.schedule(s)
	assert_true(hud.dimming_text().begins_with("Great Dimming in"), hud.dimming_text())
	assert_true(hud.dimming_text().ends_with("lasts 16"), hud.dimming_text())
	_to_day(gd.start_day() + 2)
	assert_true(hud.dimming_text().begins_with("GREAT DIMMING - day 3 of 16"), hud.dimming_text())
	assert_eq(hud.dimming_state(), "active")


func test_toast() -> void:
	var nc := NotificationCenter.new(s)
	_to_day(1)
	gd.schedule(s)
	assert_true(nc.items.any(func(i: Dictionary) -> bool: return str(i["text"]).begins_with("The Great Dimming is coming")))
	_to_day(gd.start_day())
	assert_true(nc.is_active("great_dimming:started"))


func test_save_round_trip_mid_great_dimming() -> void:
	gd.schedule(s)
	_to_day(gd.start_day() + 5)
	var r := Settlement.from_dict(s.to_dict(), reg)
	assert_true(GreatDimmingSystem.is_active(r))
	var rg := r.get_system(GreatDimmingSystem) as GreatDimmingSystem
	assert_eq(rg.start_day(), gd.start_day())
	assert_eq((r.get_system(DimmingSystem) as DimmingSystem).status(r)["days_left"], 11)
	assert_eq(GreatDimmingSystem.planet_source(r), -0.5)
	r.step_hours(11 * DAY)
	assert_false(GreatDimmingSystem.is_active(r))
	assert_true(GreatDimmingSystem.is_done(r))
	var r2 := Settlement.from_dict(r.to_dict(), reg)
	assert_true(GreatDimmingSystem.is_done(r2))
	assert_false(GreatDimmingSystem.is_pending(r2))
