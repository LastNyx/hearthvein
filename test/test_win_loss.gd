extends GutTest
## Ticket 45c: win at the Great Dimming's end with pop > 0 and health >= 50, no_win below, loss at pop 0.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY

var reg: DataRegistry
var s: Settlement
var gd: GreatDimmingSystem
var cs: CampaignSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	gd = s.get_system(GreatDimmingSystem)
	cs = s.get_system(CampaignSystem)


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _kinds() -> Array:
	var out: Array = []
	for e in s.events.log:
		if str(e["kind"]).begins_with("campaign_"):
			out.append(e["kind"])
	return out


## Runs a whole Great Dimming at a pinned planet health and returns the end day.
func _run_great(health: float) -> int:
	s.planet_health_override = health
	gd.schedule(s)
	var end := gd.start_day() + s.registry.planet.great_dimming_days
	_to_day(end)
	return end


func test_win_at_exactly_fifty() -> void:
	assert_eq(cs.outcome, "")
	_run_great(50.0)
	assert_eq(cs.outcome, "won")
	assert_true(cs.is_won())
	assert_eq(_kinds(), ["campaign_won"])
	var d: Dictionary = s.events.log_of("campaign_won")[0]["data"]
	assert_eq(d["population"], s.citizens.size())
	assert_eq(d["planet_health"], 50.0)


func test_below_fifty_is_no_win_and_the_win_can_not_come_later() -> void:
	var end := _run_great(49.9)
	assert_eq(cs.outcome, "no_win")
	assert_eq(_kinds(), ["campaign_no_win"])
	s.planet_health_override = 100.0
	cs.on_great_dimming_ended(s, 10, 100.0)
	assert_eq(cs.outcome, "no_win", "nothing sets won afterwards")
	_to_day(end + 40)
	assert_eq(cs.outcome, "no_win")
	assert_eq(s.events.log_of("campaign_won").size(), 0)
	assert_eq(s.events.log_of("campaign_lost").size(), 0, "the run simply continues")
	assert_gt(s.citizens.size(), 0)


func test_no_result_before_the_great_dimming_ends() -> void:
	s.planet_health_override = 100.0
	gd.schedule(s)
	_to_day(gd.start_day() + 15)
	assert_eq(cs.outcome, "")
	_to_day(gd.start_day() + 16)
	assert_eq(cs.outcome, "won")


func test_zero_population_loses_any_time_and_only_once() -> void:
	s.step_hours(1)
	s.citizens.clear()
	s.step_hours(1)
	assert_eq(cs.outcome, "lost")
	assert_true(cs.is_lost())
	assert_eq(_kinds(), ["campaign_lost"])
	s.step_hours(30)
	assert_eq(s.events.log_of("campaign_lost").size(), 1)
	# the Great Dimming's end does not turn a lost run into a win
	s.planet_health_override = 100.0
	gd.schedule(s)
	_to_day(gd.start_day() + 16)
	assert_eq(cs.outcome, "lost")
	assert_eq(_kinds(), ["campaign_lost"])


func test_zero_population_loses_after_the_great_dimming_too() -> void:
	var end := _run_great(80.0)
	assert_eq(cs.outcome, "won")
	s.citizens.clear()
	s.step_hours(1)
	assert_eq(cs.outcome, "lost")
	assert_eq(s.events.log_of("campaign_won").size(), 1)
	assert_eq(s.events.log_of("campaign_lost").size(), 1)
	_to_day(end + 3)
	assert_eq(s.events.log_of("campaign_lost").size(), 1)


func test_an_empty_fixture_does_not_lose_at_once() -> void:
	var t := Settlement.new_game(SEED, reg)
	t.citizens.clear()
	t.step_hours(5)
	assert_eq((t.get_system(CampaignSystem) as CampaignSystem).outcome, "")


func test_disabled_win_check_gives_no_win_events_but_loss_still_applies() -> void:
	cs.win_check_enabled = false
	_run_great(100.0)
	assert_eq(cs.outcome, "")
	assert_eq(_kinds(), [])
	s.citizens.clear()
	s.step_hours(1)
	assert_eq(cs.outcome, "lost")
	assert_eq(_kinds(), ["campaign_lost"])


func test_default_win_check_is_on() -> void:
	assert_true(cs.win_check_enabled)
	assert_eq(reg.planet.win_health, 50.0)


func test_save_round_trip_of_the_outcome() -> void:
	_run_great(49.9)
	var r := Settlement.from_dict(s.to_dict(), reg)
	var rc := r.get_system(CampaignSystem) as CampaignSystem
	assert_eq(rc.outcome, "no_win")
	rc.on_great_dimming_ended(r, 5, 100.0)
	assert_eq(rc.outcome, "no_win", "the closed win stays closed after a load")
	var t := Settlement.new_game(SEED, reg)
	var tc := t.get_system(CampaignSystem) as CampaignSystem
	tc.win_check_enabled = false
	t.step_hours(1)
	var r2 := Settlement.from_dict(t.to_dict(), reg)
	assert_false((r2.get_system(CampaignSystem) as CampaignSystem).win_check_enabled)
	r2.citizens.clear()
	r2.step_hours(1)
	assert_eq((r2.get_system(CampaignSystem) as CampaignSystem).outcome, "lost", "had_citizens survived the save")
