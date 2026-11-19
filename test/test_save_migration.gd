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


# ---------------------------------------------------------------- ticket 99: materials -> wood and stone

func test_v0_fixture_materials_become_half_wood_half_stone() -> void:
	var s := SaveGame.load(V0_FIXTURE, reg)
	assert_not_null(s)
	if s == null:
		return
	var inv := s.hearth.inventory
	assert_eq([inv.amount_of("wood"), inv.amount_of("stone")], [20.0, 20.0], "the old 40 materials split in half")
	assert_eq(inv.amount_of("materials"), 0.0)


func test_migration_splits_every_materials_amount_and_rebuilds_a_sites_need() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_override = "village"
	var h := s.map.hearth_spot
	var site: Building = null
	for dx in range(4, 20):
		var id := s.place_building("cottage", Vector2i(h.x + dx, h.y + 1))
		if id >= 0:
			site = s.buildings[id]
			break
	assert_not_null(site, "a cottage site was placed")
	if site == null:
		return
	var state := s.to_dict()
	# Rewrite the state the way a version-3 build wrote it: one "materials" good, odd amounts, a trip in flight.
	for pair in state["buildings"]:
		var b: Dictionary = pair[1]
		if int(b["id"]) == site.id:
			b["input_buffer"] = {"mode": "per_good", "cap": 15.0, "accept": [], "amounts": [["materials", 7.0]]}
		elif int(b["id"]) == s.hearth.id:
			b["inventory"]["amounts"] = [["food", 60.0], ["materials", 41.0], ["lumen", 10.0]]
			b["inventory"]["accept"] = ["materials"]
	var hs: Dictionary = state["systems"]["hauling"]
	hs["trips"] = [[7, {"citizen_id": 7, "good": "materials", "src": 1, "src_door": false, "dst": site.id,
			"dst_input": true, "dst_upgrade": false, "planned": 3.0, "carried": 0.0, "picked_up": false}]]
	hs["reserved"] = {"i": {site.id: {"materials": 3.0}}}
	var v3 := SaveGame.migrate_v3_to_v4(state) as Dictionary
	var path := _write_payload({"version": 3, "state": v3})
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded, "a version-3 save loads")
	if loaded == null:
		return
	var inv := loaded.hearth.inventory
	assert_eq([inv.amount_of("wood"), inv.amount_of("stone")], [21.0, 20.0], "41 materials: wood takes the odd unit")
	assert_true(inv.accept.has("wood") and inv.accept.has("stone"), "a filter on materials now lets both through")
	var ls: Building = loaded.buildings[site.id]
	assert_eq([ls.input_buffer.amount_of("wood"), ls.input_buffer.amount_of("stone")], [4.0, 3.0])
	assert_eq(ls.input_buffer.cap, 10.0, "the site's cap is rebuilt from the cottage's 10 wood 5 stone")
	assert_eq(HaulingSystem.need_of(reg, ls), {"wood": 10.0, "stone": 5.0}, "the need comes from the def")
	assert_eq((loaded.get_system(HaulingSystem) as HaulingSystem).trips[7].good, "wood")
	loaded.step_days(1)  # runs on without errors


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
