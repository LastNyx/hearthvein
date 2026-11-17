extends GutTest
## Ticket 46: endless continuation (Dimming base grows with years) and the endless start.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const YEAR := GameClock.DAYS_PER_YEAR

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _new(endless: bool) -> void:
	s = Settlement.new_game(SEED, reg, endless)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "ascendant"
	s.planet_health_override = 100.0


func _camp() -> CampaignSystem:
	return s.get_system(CampaignSystem)


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _spot(def_id: String) -> Vector2i:
	var h := s.map.hearth_spot
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(h.y - 14, h.y + 14):
		for x in range(h.x - 14, h.x + 14):
			var o := Vector2i(x, y)
			if s.can_place(def_id, o, true)["ok"]:
				var d := absi(x - h.x) + absi(y - h.y)
				if d < best_d:
					best_d = d
					best = o
	return best


func _complete_skyheart() -> Building:
	s.gold = 5000.0
	var id := s.place_building("skyheart", _spot("skyheart"))
	assert_true(id >= 0)
	var b: Building = s.buildings[id]
	for i in 4:
		for g in b.effective_cost():
			if g != BuildingDef.GOLD:
				b.input_buffer.add(g, float(b.effective_cost()[g]))
		b.build_work = b.build_work_needed
		s.complete_site(b)
		(s.get_system(SkyheartSystem) as SkyheartSystem).on_hour(s)
	return b


func _grid_heart() -> Building:
	var id := s.place_building_instant("skyheart", _spot("skyheart"))
	assert_true(id >= 0)
	assert_true(s.place_building_instant("lumen_pylon", _spot("lumen_pylon")) >= 0)
	return s.buildings[id]


func test_step_is_data() -> void:
	assert_eq(reg.planet.endless_years_per_day, 2)


func test_base_grows_one_day_per_two_years_after_the_great_dimming() -> void:
	_new(false)
	var base := reg.get_era("village").dimming_base_days
	assert_eq(DimmingSystem.length_for(s, "village", 100.0), base, "era base before endless")
	_to_day(10)
	_camp().on_great_dimming_ended(s, 10, 100.0)
	assert_eq(_camp().endless_began, 10)
	s.clock.total_hours = (10 + 2 * YEAR - 1) * DAY
	assert_eq(DimmingSystem.length_for(s, "village", 100.0), base, "not yet at 2 years minus a day")
	s.clock.total_hours = (10 + 2 * YEAR) * DAY
	assert_eq(DimmingSystem.length_for(s, "village", 100.0), base + 1)
	s.clock.total_hours = (10 + 4 * YEAR) * DAY
	assert_eq(DimmingSystem.length_for(s, "village", 100.0), base + 2)
	s.clock.total_hours = (10 + 40 * YEAR) * DAY
	assert_eq(DimmingSystem.length_for(s, "village", 100.0), base + 20, "no cap")
	assert_eq(DimmingSystem.length_for(s, "village", 50.0), roundi((base + 20) * 1.5), "still times the health factor")


func test_no_win_also_starts_endless() -> void:
	_new(false)
	_to_day(5)
	_camp().on_great_dimming_ended(s, 10, 20.0)
	assert_eq(_camp().outcome, "no_win")
	assert_eq(_camp().endless_began, 5)


func test_endless_start_never_schedules_the_great_dimming() -> void:
	_new(true)
	assert_true(CampaignSystem.is_endless_start(s))
	assert_false(_camp().win_check_enabled)
	_to_day(3)
	_complete_skyheart()
	assert_eq(s.events.log_of("skyheart_finished").size(), 1, "still buildable as a monument")
	assert_false(GreatDimmingSystem.is_pending(s))
	assert_eq(s.events.log_of("great_dimming_forecast").size(), 0)
	_to_day(60)
	assert_eq(s.events.log_of("great_dimming_started").size(), 0)
	for k in ["campaign_won", "campaign_no_win", "great_dimming_ended"]:
		assert_eq(s.events.log_of(k).size(), 0, k)
	assert_eq(_camp().outcome, "")


func test_endless_start_growth_counts_from_ascendant() -> void:
	_new(true)
	_to_day(1)
	var began := _camp().endless_began
	assert_true(began >= 0 and began <= 1, "began the day the era was Ascendant")
	var base := reg.get_era("ascendant").dimming_base_days
	_to_day(began + 2 * YEAR)
	assert_eq(CampaignSystem.endless_years(s), 2)
	assert_eq(DimmingSystem.length_for(s, s.era_id(), 100.0), base + 1)
	var f := s.events.log_of("dimming_forecast")
	assert_true(f.size() >= 1)
	assert_eq(f[0]["data"]["length"], base, "first year: era base only")


func test_endless_start_not_ascendant_does_not_begin() -> void:
	_new(true)
	s.era_override = ""
	_to_day(3)
	assert_eq(_camp().endless_began, -1)
	assert_eq(CampaignSystem.endless_years(s), -1)


func test_reservoir_pours_in_a_regular_dimming_after_the_finale() -> void:
	_new(false)
	var b := _grid_heart()
	var gs := s.get_system(GridSystem) as GridSystem
	var sky := s.get_system(SkyheartSystem) as SkyheartSystem
	var dim := s.get_system(DimmingSystem) as DimmingSystem
	var gid := gs.grid_of(s, b.id)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	sky._charge[b.id] = 500.0
	dim._active = true
	assert_eq(gs.draw(s, gid, 100.0), 0.0, "before the Great Dimming it only fills")
	s.hearth.inventory.add("lumen", 500.0)
	sky.on_hour(s)
	assert_gt(sky.reservoir_charge(b.id), 500.0, "and keeps filling in a regular Dimming")
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	sky._charge[b.id] = 500.0
	(s.get_system(GreatDimmingSystem) as GreatDimmingSystem)._done = true
	assert_almost_eq(gs.draw(s, gid, 100.0), 100.0, 0.001, "after the finale it pours")
	assert_almost_eq(sky.reservoir_charge(b.id), 400.0, 0.001)
	s.hearth.inventory.add("lumen", 500.0)
	sky.on_hour(s)
	assert_almost_eq(sky.reservoir_charge(b.id), 400.0, 0.001, "no filling during the Dimming")
	dim._active = false
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	assert_eq(gs.draw(s, gid, 10.0), 0.0, "closed outside a Dimming")
	s.hearth.inventory.add("lumen", 500.0)
	sky.on_hour(s)
	assert_gt(sky.reservoir_charge(b.id), 400.0, "fills again afterwards")


func test_reservoir_pours_in_endless_start() -> void:
	_new(true)
	var b := _grid_heart()
	var gs := s.get_system(GridSystem) as GridSystem
	var sky := s.get_system(SkyheartSystem) as SkyheartSystem
	var dim := s.get_system(DimmingSystem) as DimmingSystem
	var gid := gs.grid_of(s, b.id)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	sky._charge[b.id] = 500.0
	assert_eq(gs.draw(s, gid, 100.0), 0.0, "no Dimming, no pour")
	dim._active = true
	assert_almost_eq(gs.draw(s, gid, 100.0), 100.0, 0.001)


func test_reservoir_covers_light_in_regular_dimming_after_finale() -> void:
	_new(false)
	var b := _grid_heart()
	var sky := s.get_system(SkyheartSystem) as SkyheartSystem
	var dim := s.get_system(DimmingSystem) as DimmingSystem
	for id in s.buildings:
		var bb: Building = s.buildings[id]
		if bb.inventory != null:
			bb.inventory.remove("lumen", bb.inventory.amount_of("lumen"))
	sky._charge[b.id] = 1000.0
	dim._active = true
	dim._start_day = 0
	dim._length = 5
	dim._light(s)
	assert_true(DimmingSystem.is_dark(s), "campaign run before the finale: no reservoir")
	(s.get_system(GreatDimmingSystem) as GreatDimmingSystem)._done = true
	dim._light(s)
	assert_false(DimmingSystem.is_dark(s))
	assert_gt(float(dim.last_light["drawn_reservoir"]), 0.0)


func test_save_round_trip() -> void:
	_new(true)
	_to_day(2)
	var began := _camp().endless_began
	var r := Settlement.from_dict(s.to_dict(), reg)
	var rc := r.get_system(CampaignSystem) as CampaignSystem
	assert_true(rc.endless_start)
	assert_false(rc.win_check_enabled)
	assert_eq(rc.endless_began, began)
	_new(false)
	_to_day(4)
	_camp().on_great_dimming_ended(s, 5, 90.0)
	var r2 := Settlement.from_dict(s.to_dict(), reg)
	assert_eq((r2.get_system(CampaignSystem) as CampaignSystem).endless_began, 4)
	assert_false((r2.get_system(CampaignSystem) as CampaignSystem).endless_start)
