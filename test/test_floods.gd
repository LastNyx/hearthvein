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
