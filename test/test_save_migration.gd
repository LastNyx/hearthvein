extends GutTest
## Ticket 19b: save versions, the migration chain and bad-save handling (design.md section 21).
##
## The version-0 fixture is test/fixtures/save_v0.dat: a fresh deterministic game saved in the v0 shape (gold was
## "coins" and the Spirit system had no saved state). tools/make_v0_fixture.gd regenerates it.

const SEED := 42
const V0_FIXTURE := "res://test/fixtures/save_v0.dat"
const V0_GOLD := 123.5
const SAVE_DIR := "/tmp/nyx-flash"
const TMP_FILE := "hearthvein_ticket19b.dat"

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func after_each() -> void:
	DirAccess.remove_absolute(_tmp_path())


func _tmp_path() -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return SAVE_DIR.path_join(TMP_FILE)


func _write_payload(payload: Variant) -> String:
	var path := _tmp_path()
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	assert_not_null(f, "the temp save opens for writing")
	if f == null:
		return path
	f.store_var(payload, false)
	f.close()
	return path


func _current_state() -> Dictionary:
	return Settlement.new_game(SEED, reg).to_dict()


# ---------------------------------------------------------------- the v0 fixture

func test_v0_fixture_migrates_into_a_playable_settlement() -> void:
	var s := SaveGame.load(V0_FIXTURE, reg)
	assert_not_null(s, "the version-0 fixture loads through the chain")
	if s == null:
		return
	assert_eq(s.gold, V0_GOLD, "the v0 'coins' key was renamed to gold")
	var spirit := s.get_system(SpiritSystem) as SpiritSystem
	assert_not_null(spirit, "the Spirit system was built by add_default_systems")
	if spirit != null:
		assert_eq(spirit.value, -1.0, "the missing Spirit section was filled with its unset sentinel")
	assert_eq(s.spirit(), reg.spirit.start, "an unmigrated Spirit reads as its start value")
	assert_not_null(s.hearth, "the Hearth loaded")
	assert_eq(s.map.terrain.size(), MapState.WIDTH * MapState.HEIGHT)
	assert_eq(s.clock.total_hours, 0)
	# A migrated save is a real, runnable state: a whole day passes (any error pushed here fails the test).
	s.step_days(1)
	assert_eq(s.clock.total_hours, GameClock.HOURS_PER_DAY)
	assert_true(s.spirit() >= 0.0 and s.spirit() <= 100.0, "Spirit stays on its 0-100 meter")


func test_chain_runs_one_step_per_version_in_order() -> void:
	var order: Array[int] = []
	var migrations := {
		0: func(state: Dictionary) -> Dictionary:
			order.append(0)
			return {"step": int(state["step"]) + 1},
		1: func(state: Dictionary) -> Dictionary:
			order.append(1)
			return {"step": int(state["step"]) + 1},
	}
	var out: Variant = SaveGame.migrate_chain(0, {"step": 0}, migrations, 2)
	assert_eq(typeof(out), TYPE_DICTIONARY, "the chain returns the migrated state")
	if typeof(out) != TYPE_DICTIONARY:
		return
	assert_eq(int((out as Dictionary)["step"]), 2, "each step received the previous step's output")
	assert_eq(order, [0, 1], "the steps ran once each, in version order")


func test_a_missing_step_stops_the_chain() -> void:
	var migrations := {0: func(_state: Dictionary) -> Dictionary: return {}}
	assert_null(SaveGame.migrate_chain(0, {}, migrations, 2), "no step from v1 to v2")
	assert_push_error_count(1)


# ---------------------------------------------------------------- bad saves

func test_missing_file_returns_null() -> void:
	assert_null(SaveGame.load(_tmp_path(), reg))
	assert_push_error_count(1)


func test_non_compressed_garbage_returns_null() -> void:
	var path := _tmp_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f)
	f.store_string("this is not a Hearthvein save")
	f.close()
	assert_null(SaveGame.load(path, reg))
	assert_push_error_count(1)


func test_version_newer_than_the_game_returns_null() -> void:
	var path := _write_payload({"version": SaveGame.CURRENT_VERSION + 1, "state": _current_state()})
	assert_null(SaveGame.load(path, reg))
	assert_push_error_count(1)


func test_non_dictionary_state_returns_null() -> void:
	var path := _write_payload({"version": SaveGame.CURRENT_VERSION, "state": "not a dictionary"})
	assert_null(SaveGame.load(path, reg))
	assert_push_error_count(1)


func test_truncated_map_array_returns_null() -> void:
	var state := _current_state()
	var map: Dictionary = state["map"]
	map["terrain"] = (map["terrain"] as PackedByteArray).slice(0, 5)
	var path := _write_payload({"version": SaveGame.CURRENT_VERSION, "state": state})
	assert_null(SaveGame.load(path, reg))
	assert_push_error_count(1)


func test_unknown_building_def_returns_null() -> void:
	var state := _current_state()
	var buildings: Array = state["buildings"]
	assert_gt(buildings.size(), 0, "a new game has buildings")
	(buildings[0][1] as Dictionary)["def"] = "no_such_building"
	var path := _write_payload({"version": SaveGame.CURRENT_VERSION, "state": state})
	assert_null(SaveGame.load(path, reg))
	assert_push_error_count(1)
