extends GutTest
## Ticket 154: spring floods and the Levee (spec N10).
##
## Each spring the river floods the low land beside it for WaterDef.flood_days days; buildings there pause ("flooded")
## and the drained tiles gain WaterDef.flood_silt_fertility soil. A Levee on the bank holds the water back. The flood
## day is a pure function of the map seed and the year, and the flood state is part of a save.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket154_flood.dat"

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


## A dry, empty 11x5 block with no river or water within 3 tiles, so the test's own river is the only flood source.
## The block is levelled to grass and its regions are owned, then a straight river is cut through the middle row.
## Returns {bx, by, ry, bank_y, back_y}.
func _plot(s: Settlement) -> Dictionary:
	for by in range(3, MapState.HEIGHT - 8):
		for bx in range(3, MapState.WIDTH - 14):
			if not _clear_block(s, bx, by):
				continue
			return _build_plot(s, bx, by)
	fail_test("no clear plot for the test river")
	return {}


func _clear_block(s: Settlement, bx: int, by: int) -> bool:
	for y in range(by - 3, by + 8):
		for x in range(bx - 3, bx + 14):
			if not MapState.in_bounds(x, y):
				return false
			if s.map.terrain_id_at(x, y) == "water" or s.map.is_river(x, y):
				return false
	for y in range(by, by + 5):
		for x in range(bx, bx + 11):
			var i := MapState.idx(x, y)
			if s.occupancy[i] >= 0 or s.roads[i] != Settlement.ROAD_NONE \
					or s.channels[i] != Settlement.CHANNEL_NONE or s.track[i] != 0:
				return false
	return true


func _build_plot(s: Settlement, bx: int, by: int) -> Dictionary:
	var ry := by + 2
	for y in range(by, by + 5):
		for x in range(bx, bx + 11):
			s.set_terrain(Vector2i(x, y), "grass")
			s.map.set_region_owned(s.map.get_region(x, y), true)
	for x in range(bx + 2, bx + 9):  # seven river tiles in the middle row
		s.set_terrain(Vector2i(x, ry), "water")
		s.map.set_flow(x, ry, MapState.FLOW_E)
	return {"bx": bx, "by": by, "ry": ry, "bank_y": ry - 1, "back_y": ry - 2}


func _fertility(s: Settlement, tile: Vector2i) -> float:
	var fs := s.get_system(FertilitySystem) as FertilitySystem
	return fs.fertility_at(s, tile)


# AC1: the river floods the low bank tiles, buildings there pause, the flood drains and leaves silt, and a Levee on
# the bank keeps the tiles behind it dry.
func test_flood_pauses_buildings_drains_silts_and_a_levee_protects() -> void:
	var s := Settlement.new_game(SEED, reg)
	var p := _plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	assert_not_null(fs, "a new game registers the FloodSystem")
	var days := s.registry.water.flood_days
	var bank := Vector2i(p.bx + 5, p.bank_y)
	var back := Vector2i(p.bx + 5, p.back_y)
	s.map.set_fertility(bank.x, bank.y, 50)
	var bid := s.place_building_instant("forager", bank)
	assert_true(bid >= 0, "a forager stands on the bank")
	var f: Building = s.buildings[bid]
	var start := fs.flood_start_day(s, 1)
	s.step_hours(start * GameClock.HOURS_PER_DAY + 1)  # the day hook starts the flood; one hour for production to see it
	assert_true(fs.is_flooded(bank), "the bank tile floods")
	assert_true(fs.is_flooded(back), "the low row behind floods when no levee stands")
	assert_eq(f.halt, "flooded", "the building on the flooded tile pauses")
	s.step_hours(days * GameClock.HOURS_PER_DAY + 1)
	assert_false(fs.is_flooded(bank), "the flood drains")
	assert_ne(f.halt, "flooded", "the building works again")
	assert_almost_eq(_fertility(s, bank), 60.0, 0.001, "the drained tile gained its silt")

	# The same flood against a continuous levee along the bank: the row behind stays dry.
	var s2 := Settlement.new_game(SEED, reg)
	var p2 := _plot(s2)
	var fs2 := s2.get_system(FloodSystem) as FloodSystem
	var bank2 := Vector2i(p2.bx + 5, p2.bank_y)
	var back2 := Vector2i(p2.bx + 5, p2.back_y)
	for x in range(p2.bx + 2, p2.bx + 9):
		assert_true(s2.place_building_instant("levee", Vector2i(x, p2.bank_y)) >= 0, "a levee on the bank at x %d" % x)
	var bid2 := s2.place_building_instant("forager", back2)
	assert_true(bid2 >= 0, "a forager stands behind the levee")
	var f2: Building = s2.buildings[bid2]
	s2.step_hours(fs2.flood_start_day(s2, 1) * GameClock.HOURS_PER_DAY)
	assert_false(fs2.is_flooded(back2), "the levee keeps the row behind it dry")
	assert_false(fs2.is_flooded(bank2), "the levee tile itself does not flood")
	assert_ne(f2.halt, "flooded", "the building behind the levee keeps working")


# AC2: two settlements from the same seed flood alike, and a save taken mid-flood loads with the flood still running.
func test_save_load_mid_flood_and_same_seed_are_deterministic() -> void:
	var a := Settlement.new_game(SEED, reg)
	var b := Settlement.new_game(SEED, reg)
	_plot(a)
	_plot(b)
	var fa := a.get_system(FloodSystem) as FloodSystem
	var fb := b.get_system(FloodSystem) as FloodSystem
	assert_eq(fa.flood_start_day(a, 1), fb.flood_start_day(b, 1), "the same seed picks the same day")
	var mid := fa.flood_start_day(a, 1) * GameClock.HOURS_PER_DAY + GameClock.HOURS_PER_DAY / 2
	a.step_hours(mid)
	b.step_hours(mid)
	assert_gt(fa.flooded_tiles().size(), 0, "the flood is running mid-spring")
	assert_eq(fa.flooded_tiles(), fb.flooded_tiles(), "same seed, same flooded tiles")
	var running := fa.flooded_tiles()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	assert_eq(SaveGame.save(a, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded, "the mid-flood save loads")
	if loaded == null:
		return
	var fl := loaded.get_system(FloodSystem) as FloodSystem
	assert_not_null(fl, "the loaded game has the FloodSystem")
	assert_eq(fl.flooded_tiles(), running, "the flood is still running after the load")


# ---------------------------------------------------------------- ticket 180: the gaps in 154's tests

## Day numbers of every flood_forecast event the settlement emits.
func _watch_forecasts(s: Settlement) -> Array[int]:
	var days: Array[int] = []
	s.events.subscribe("flood_forecast", func(_e: Dictionary) -> void: days.append(s.clock.total_days()))
	return days


## Steps to hour `h` of absolute day `day` (never backwards).
func _step_to(s: Settlement, day: int, h: int = 0) -> void:
	s.step_hours(day * GameClock.HOURS_PER_DAY + h - s.clock.total_hours)


# The forecast fires on the day before the start day, once, and raises a notice that names the days; other days are quiet.
func test_forecast_fires_the_day_before_once_and_raises_a_notice() -> void:
	var s := Settlement.new_game(SEED, reg)
	_plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	var model := HudModel.new(s)  # kept in a var: the notices live on it
	var seen := _watch_forecasts(s)
	var start := fs.flood_start_day(s, 1)
	_step_to(s, start - 2, GameClock.HOURS_PER_DAY - 1)
	assert_eq(seen.size(), 0, "no forecast before the day ahead of the start")
	_step_to(s, start - 1, 1)
	assert_eq(seen, [start - 1] as Array[int], "the forecast fires on the day before the start day")
	var notes: Array[Dictionary] = []
	for it in model.notifications.items:
		if it["kind"] == "flood":
			notes.append(it)
	assert_eq(notes.size(), 1, "a flood notice is raised")
	if notes.size() == 1:
		assert_string_contains(notes[0]["text"], str(s.registry.water.flood_days), "the notice names the days")
		assert_eq(model.notifications.recent(48).size(), 1, "and it is in the list the HUD shows")
	_step_to(s, GameClock.DAYS_PER_YEAR)
	assert_eq(seen.size(), 1, "exactly once in the year")


# The flood runs from the first hour of the start day to the last hour of its last day; for several seeds and years the
# start is in spring with a day of warning and the whole flood ends inside spring.
func test_flood_day_boundaries_and_the_start_day_fits_spring() -> void:
	var days := reg.water.flood_days
	for seed_i: int in [1, 7, 42, 99, 1234]:
		var s := Settlement.new_game(seed_i, reg)
		var fs := s.get_system(FloodSystem) as FloodSystem
		for year: int in [1, 2, 3]:
			var base := (year - 1) * GameClock.DAYS_PER_YEAR
			var start := fs.flood_start_day(s, year)
			assert_gte(start - base, 1, "seed %d year %d: a day of warning inside the year" % [seed_i, year])
			assert_lt(start + days - 1 - base, GameClock.DAYS_PER_SEASON, "seed %d year %d: floods end inside spring" % [seed_i, year])
	var s := Settlement.new_game(SEED, reg)
	_plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	var start := fs.flood_start_day(s, 1)
	_step_to(s, start - 1, GameClock.HOURS_PER_DAY - 1)
	assert_false(fs.active, "not active the hour before the start day")
	assert_eq(fs.flooded_tiles().size(), 0)
	_step_to(s, start, 0)
	assert_true(fs.active, "active at the start day")
	assert_gt(fs.flooded_tiles().size(), 0)
	_step_to(s, start + days - 1, GameClock.HOURS_PER_DAY - 1)
	assert_true(fs.active, "still active the last hour of the last flood day")
	_step_to(s, start + days, 0)
	assert_false(fs.active, "drained on start + flood_days")
	assert_eq(fs.flooded_tiles().size(), 0)


# While flooded a walker's path around the water never crosses a flooded road tile; after the drain it is open again.
func test_walkers_avoid_flooded_road_tiles_until_the_drain() -> void:
	var s := Settlement.new_game(SEED, reg)
	var p := _plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var from := Vector2i(p.bx, p.bank_y)
	var to := Vector2i(p.bx + 10, p.bank_y)
	var wet := Vector2i(p.bx + 5, p.bank_y)
	for x in range(p.bx, p.bx + 11):
		s.place_road(Vector2i(x, p.bank_y))
	s.step_seconds(0.01)  # binds the walker system to the settlement
	var open := ws.find_path(from, to)
	assert_true(open.has(wet), "dry: the road along the bank is the way")
	var start := fs.flood_start_day(s, 1)
	_step_to(s, start, 1)
	assert_true(fs.is_flooded(wet), "the bank road floods")
	for t in ws.find_path(from, to):
		assert_false(fs.is_flooded(t), "a path never crosses flood water (%s)" % str(t))
	_step_to(s, start + s.registry.water.flood_days, 1)
	assert_false(fs.is_flooded(wet))
	assert_true(ws.find_path(from, to).has(wet), "after the drain the road is open again")


# The drained tiles carry the silt marker, the levee-protected ones do not, the next spring's flood clears the marker
# and a second year floods again on its own day.
func test_silt_marker_levee_protection_and_the_next_years_flood() -> void:
	var s := Settlement.new_game(SEED, reg)
	var p := _plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	var days := s.registry.water.flood_days
	var wet := Vector2i(p.bx + 2, p.bank_y)
	var dry := Vector2i(p.bx + 5, p.back_y)  # behind the levee: only reachable through the bank tile under it
	for x in range(p.bx + 4, p.bx + 7):
		assert_true(s.place_building_instant("levee", Vector2i(x, p.bank_y)) >= 0)
	var start := fs.flood_start_day(s, 1)
	_step_to(s, start, 1)
	assert_true(fs.is_flooded(wet))
	assert_false(fs.is_silted(wet), "no silt marker while the water stands")
	_step_to(s, start + days, 1)
	assert_true(fs.is_silted(wet), "the flooded tile is marked silted")
	assert_false(fs.is_silted(dry), "the tile behind the levee is not")
	var start2 := fs.flood_start_day(s, 2)
	assert_gt(start2, start + days, "year 2 has its own later day")
	_step_to(s, start2 - 1, GameClock.HOURS_PER_DAY - 1)
	assert_false(fs.active, "no flood before year 2's day")
	assert_true(fs.is_silted(wet), "the marker stays until the next flood")
	_step_to(s, start2, 1)
	assert_true(fs.active, "year 2 floods on its own day")
	assert_eq(fs.start_day, start2)
	assert_false(fs.is_silted(wet), "the new flood clears the old marker")
	_step_to(s, start2 + days, 1)
	assert_true(fs.is_silted(wet), "and marks the drained tiles again")
	assert_false(fs.is_silted(dry))


# The silt marker and the drained state survive a save taken after the drain; a load mid-flood still drains on its day.
func test_save_after_the_drain_and_mid_flood_load_drains_on_time() -> void:
	var s := Settlement.new_game(SEED, reg)
	var p := _plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	var days := s.registry.water.flood_days
	var wet := Vector2i(p.bx + 2, p.bank_y)
	var start := fs.flood_start_day(s, 1)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	_step_to(s, start, 1)  # the first flood day, whatever flood_days is
	assert_eq(SaveGame.save(s, path), OK)
	var mid := SaveGame.load(path, reg)
	_step_to(s, start + days, 1)
	assert_eq(SaveGame.save(s, path), OK)
	var after := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(mid)
	assert_not_null(after)
	if mid == null or after == null:
		return
	var fa := after.get_system(FloodSystem) as FloodSystem
	assert_false(fa.active, "a save after the drain loads drained")
	assert_eq(fa.flooded_tiles().size(), 0)
	assert_true(fa.is_silted(wet), "the silt marker survives the load")
	assert_eq(fa.start_day, start)
	var fm := mid.get_system(FloodSystem) as FloodSystem
	assert_true(fm.active and fm.is_flooded(wet), "the mid-flood save is still flooded")
	_step_to(mid, start + days - 1, GameClock.HOURS_PER_DAY - 1)
	assert_true(fm.active, "the loaded flood runs to its last day")
	_step_to(mid, start + days, 1)
	assert_false(fm.active, "and drains on start + flood_days")
	assert_true(fm.is_silted(wet), "leaving silt")


# The Levee needs a bank tile, costs stone 6 + cut stone 2, and a one-tile gap lets the water through to the tiles behind it.
func test_levee_needs_a_bank_costs_and_a_gap_leaks() -> void:
	var s := Settlement.new_game(SEED, reg)
	var p := _plot(s)
	var fs := s.get_system(FloodSystem) as FloodSystem
	var away := Vector2i(p.bx + 5, p.by)  # two rows from the river
	var refused := s.can_place("levee", away, true)
	assert_false(refused["ok"], "a tile away from the river is refused")
	assert_eq(refused["reason"], "needs_river_bank")
	assert_true(s.can_place("levee", Vector2i(p.bx + 5, p.bank_y), true)["ok"], "a bank tile is fine")
	var cost := s.registry.get_building("levee").entry_cost()
	assert_eq(cost.size(), 2)
	assert_eq(float(cost.get("stone", 0)), 6.0, "stone 6")
	assert_eq(float(cost.get("cut_stone", 0)), 2.0, "cut stone 2")
	var gap: int = p.bx + 5
	for x in range(p.bx + 2, p.bx + 9):
		if x != gap:
			assert_true(s.place_building_instant("levee", Vector2i(x, p.bank_y)) >= 0)
	_step_to(s, fs.flood_start_day(s, 1), 1)
	assert_true(fs.is_flooded(Vector2i(gap, p.bank_y)), "the gap floods")
	assert_true(fs.is_flooded(Vector2i(gap, p.back_y)), "the water reaches the tile behind the gap")
	assert_false(fs.is_flooded(Vector2i(gap - 1, p.back_y)), "but not the tiles behind the levee")
	assert_false(fs.is_flooded(Vector2i(gap + 1, p.back_y)))


# The Levee is placed like a road: click-drag lays a gap-free line of sites along the bank, the hint shows the cost a tile.
func test_levee_drags_like_a_road() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_override = "town"
	var p := _plot(s)
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var ghost := GhostView.new()
	layer.add_child(ghost)
	var build := BuildController.new()
	add_child_autofree(build)
	build.setup(s, ghost, layer)
	build.set_build("levee")
	assert_string_contains(build.hint_text(), "click-drag")
	assert_string_contains(build.hint_text(), "6 Stone")
	assert_string_contains(build.hint_text(), "2 Cut stone")
	build._click(Vector2i(p.bx + 3, p.bank_y))
	build._paint_to(Vector2i(p.bx + 7, p.bank_y))
	for x in range(p.bx + 3, p.bx + 8):
		var b := s.building_at(Vector2i(x, p.bank_y))
		assert_not_null(b, "a levee site at x %d" % x)
		if b != null:
			assert_eq(b.def.id, "levee")
	build._painting = false
	build.set_build("forager")
	build._click(Vector2i(p.bx + 9, p.bank_y))
	assert_false(build._painting, "other buildings still place one click at a time")
