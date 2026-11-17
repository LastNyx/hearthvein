extends GutTest
## Ticket 46b: milestones fire once per run (also across a save round trip) and fill the lifetime list.

const SEED := 42
const LIFETIME := "/tmp/hearthvein_test_milestones.json"

var reg: DataRegistry
var s: Settlement
var ms: MilestoneSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	MilestoneSystem.lifetime_path = ""
	_new()


func after_all() -> void:
	MilestoneSystem.lifetime_path = ""
	if FileAccess.file_exists(LIFETIME):
		DirAccess.remove_absolute(LIFETIME)


func _new() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.planet_health_override = 100.0
	ms = s.get_system(MilestoneSystem)


func _reload() -> void:
	s = Settlement.from_dict(s.to_dict(), reg)
	ms = s.get_system(MilestoneSystem)


func _fired(id: String) -> int:
	var n := 0
	for e in s.events.log_of("milestone"):
		if e["data"]["id"] == id:
			n += 1
	return n


## Fires once when `trigger` runs, not again on a second check or after a save/load round trip.
func _once(id: String, trigger: Callable) -> void:
	assert_eq(_fired(id), 0, "%s not yet" % id)
	trigger.call()
	assert_eq(_fired(id), 1, "%s fires" % id)
	assert_true(ms.has(id))
	ms.on_day(s)
	_reload()
	ms.on_day(s)
	assert_eq(_fired(id), 1, "%s only once" % id)
	assert_true(ms.has(id), "%s kept through the save" % id)


func test_fifteen_plus_bonus_in_order() -> void:
	var list := reg.milestones_in_order()
	assert_eq(list.size(), 16)
	assert_eq(list[0].display_name, "First Dimming survived")
	assert_eq(list[15].kind, "dimming_streak_no_dark")


func test_population_thresholds() -> void:
	while s.citizens.size() < 99:
		s.add_citizen()
	ms.on_day(s)
	assert_eq(_fired("citizens_100"), 0, "99 is not enough")
	s.add_citizen()
	ms.on_day(s)
	assert_eq(_fired("citizens_100"), 1)
	assert_eq(_fired("citizens_300"), 0)
	while s.citizens.size() < 300:
		s.add_citizen()
	ms.on_day(s)
	assert_eq(_fired("citizens_300"), 1)
	while s.citizens.size() < 600:
		s.add_citizen()
	ms.on_day(s)
	assert_eq(_fired("citizens_600"), 1)
	ms.on_day(s)
	assert_eq(_fired("citizens_100"), 1)


func test_era_milestones() -> void:
	for pair in [["village", "village"], ["city", "city"], ["conflux", "conflux"], ["ascendant", "ascendant"]]:
		s.era_override = pair[0]
		_once(pair[1], func() -> void: ms.on_day(s))


func test_tier3() -> void:
	_once("tier3", func() -> void:
		s.hearth.tier = 3
		ms.on_day(s))


func test_regions_owned() -> void:
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, r < 3)
	ms.on_day(s)
	assert_eq(_fired("regions_4"), 0, "three is not enough")
	_once("regions_4", func() -> void:
		s.map.set_region_owned(3, true)
		ms.on_day(s))


func test_rail_links_three_regions() -> void:
	var h := s.map.hearth_spot
	var row := h.y + 8
	var cols := [MapState.region_at(h.x, h.y) % MapState.REGION_COLS]
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.era_override = "conflux"
	s.hearth.inventory.add("materials", 900.0)
	s.hearth.inventory.add("cut_stone", 300.0)
	var r0 := MapState.region_at(h.x, h.y)
	var base := (r0 / MapState.REGION_COLS) * MapState.REGION_COLS
	var xs: Array[int] = []
	for c in 3:
		var rect := MapState.region_rect(base + c)
		xs.append(rect.position.x + 4)
		row = clampi(row, rect.position.y + 4, rect.end.y - 6)
	row = clampi(h.y + 8, MapState.region_rect(base).position.y + 4, MapState.region_rect(base).end.y - 6)
	for x in range(xs[0] - 2, xs[2] + 8):
		for y in range(row - 2, row + 4):
			s.set_terrain(Vector2i(x, y), "grass")
	for c in 3:
		assert_gt(s.place_building_instant("rail_depot", Vector2i(xs[c], row)), -1, "depot %d" % c)
	for x in range(xs[0] + 3, xs[1] + 1):
		s.place_track(Vector2i(x, row))
	ms.on_day(s)
	assert_eq(_fired("rail_3"), 0, "two regions linked, not three")
	_once("rail_3", func() -> void:
		for x in range(xs[1] + 3, xs[2] + 1):
			s.place_track(Vector2i(x, row))
		ms.on_day(s))


func test_first_island() -> void:
	var isl: IslandSystem = s.get_system(IslandSystem)
	ms.on_day(s)
	assert_eq(_fired("first_island"), 0)
	_once("first_island", func() -> void:
		isl.islands.append(Island.new())
		ms.on_day(s))


func test_dimming_survived_needs_citizens() -> void:
	_once("first_dimming", func() -> void: s.events.emit("dimming_ended", {}))


func test_dimming_with_no_citizens_is_not_survived() -> void:
	s.citizens.clear()
	s.events.emit("dimming_ended", {})
	assert_eq(_fired("first_dimming"), 0)


func test_planet_recovery_needs_the_dip_first() -> void:
	s.planet_health_override = 90.0
	ms.on_day(s)
	assert_eq(_fired("planet_recovered"), 0, "never fell below 50")
	s.planet_health_override = 60.0
	ms.on_day(s)
	s.planet_health_override = 90.0
	ms.on_day(s)
	assert_eq(_fired("planet_recovered"), 0, "dipped only to 60")
	s.planet_health_override = 40.0
	ms.on_day(s)
	s.planet_health_override = 75.0
	ms.on_day(s)
	assert_eq(_fired("planet_recovered"), 0, "not above 80 yet")
	_reload()  # the dip is saved
	_once("planet_recovered", func() -> void:
		s.planet_health_override = 81.0
		ms.on_day(s))


func test_skyheart_and_win_events() -> void:
	_once("skyheart", func() -> void: s.events.emit("skyheart_finished", {"id": 1}))
	_once("great_dimming_won", func() -> void: s.events.emit("campaign_won", {}))


func _dimming(dark: bool) -> void:
	if dark:
		(s.get_system(DimmingSystem) as DimmingSystem)._dark = true
		ms.on_day(s)
		(s.get_system(DimmingSystem) as DimmingSystem)._dark = false
	s.events.emit("dimming_ended", {})


func test_streak_of_ten_and_a_dark_day_resets() -> void:
	for i in 9:
		_dimming(false)
	assert_eq(ms.streak(), 9)
	_dimming(true)
	assert_eq(ms.streak(), 0, "a dark day resets")
	for i in 9:
		_dimming(false)
	assert_eq(_fired("streak_10"), 0)
	_reload()
	assert_eq(ms.streak(), 9, "streak is saved")
	_once("streak_10", func() -> void: _dimming(false))


func test_lifetime_list_accumulates_across_runs() -> void:
	MilestoneSystem.lifetime_path = LIFETIME
	if FileAccess.file_exists(LIFETIME):
		DirAccess.remove_absolute(LIFETIME)
	s.events.emit("skyheart_finished", {"id": 1})
	var life := MilestoneSystem.lifetime()
	assert_true(life.has("skyheart"))
	assert_eq(int(life["skyheart"]["seed"]), SEED)
	assert_true(str(life["skyheart"]["date"]).begins_with("Year"))
	_new()  # a second run
	s.events.emit("campaign_won", {})
	s.events.emit("skyheart_finished", {"id": 1})
	life = MilestoneSystem.lifetime()
	assert_true(life.has("skyheart"), "the first run's entry stays")
	assert_true(life.has("great_dimming_won"), "the second run adds its own")
	_reload()
	assert_eq(MilestoneSystem.lifetime().size(), 2, "loading a run removes nothing")
