extends GutTest
## Ticket 22: stump regrowth (design.md section 9). Stumps age once a season while planet health is at least 60 and
## the tile is not blighted, and grow back to forest after ForestDef.regrow_seasons healthy seasons.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket22_forest.dat"

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	h = s.map.hearth_spot


## A free, owned tile clear of buildings and roads.
func _free_tile() -> Vector2i:
	for y in range(h.y - 10, h.y + 10):
		for x in range(h.x - 10, h.x + 10):
			var t := Vector2i(x, y)
			if not MapState.in_bounds(x, y) or not s.map.is_region_owned(s.map.get_region(x, y)):
				continue
			if s.building_at(t) == null and s.road_at(t) == Settlement.ROAD_NONE \
					and s.channels[MapState.idx(x, y)] == Settlement.CHANNEL_NONE:
				return t
	return Vector2i(-1, -1)


func test_regrowth_numbers_come_from_data() -> void:
	assert_not_null(reg.forest)
	assert_eq(reg.forest.regrow_seasons, 2)
	assert_eq(reg.forest.regrow_min_health, 60.0)


# AC1: regrows after two seasons at 100% health.
func test_stump_regrows_after_two_healthy_seasons() -> void:
	var t := _free_tile()
	assert_true(t.x >= 0, "a free tile")
	s.set_terrain(t, "stump")
	var gained := s.forest_gain_version
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "stump", "one season is not enough")
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "forest", "two healthy seasons regrow the stump")
	assert_gt(s.forest_gain_version, gained, "woodcutters see the new forest")


# AC1: not at 55% health.
func test_stump_does_not_regrow_at_fifty_five_percent_health() -> void:
	s.planet_health_override = 55.0
	var t := _free_tile()
	s.set_terrain(t, "stump")
	s.step_days(GameClock.DAYS_PER_SEASON * 2)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "stump", "below 60% the stump waits")


# AC2: blighted stumps never regrow, and the blighted seasons do not count towards their age.
func test_blighted_stump_never_regrows() -> void:
	var t := _free_tile()
	s.set_terrain(t, "stump")
	s.set_blighted(t, true)
	s.step_days(GameClock.DAYS_PER_SEASON * 3)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "stump", "blight stops regrowth")
	s.set_blighted(t, false)
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "stump", "the blighted seasons did not age it")
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "forest")


# Ticket 111: regrow_progress is seasons stood over seasons needed, 0 when blighted or not a stump.
func test_regrow_progress_reads_the_stump_timer() -> void:
	var fs := s.get_system(ForestSystem) as ForestSystem
	var t := _free_tile()
	assert_eq(fs.regrow_progress(s, t), 0.0, "not a stump")
	s.set_terrain(t, "stump")
	assert_eq(fs.regrow_progress(s, t), 0.0, "a fresh stump")
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(fs.regrow_progress(s, t), 0.5, "one of two seasons")
	fs.regrow_factors.append(func(_s: Settlement, _t: Vector2i) -> float: return 0.25)
	assert_eq(fs.regrow_progress(s, t), 1.0, "clamped at 1")
	fs.regrow_factors.clear()
	s.set_blighted(t, true)
	assert_eq(fs.regrow_progress(s, t), 0.0, "blighted")


## The stump ages are real state: a save in the middle of regrowth resumes where it was.
func test_stump_age_survives_a_save() -> void:
	var t := _free_tile()
	s.set_terrain(t, "stump")
	s.step_days(GameClock.DAYS_PER_SEASON)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	loaded.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(loaded.map.terrain_id_at(t.x, t.y), "forest", "the loaded stump kept its first season")
