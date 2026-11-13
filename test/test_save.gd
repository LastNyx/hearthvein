extends GutTest
## Ticket 19: save and load round trip (design.md section 21).
##
## The state compare is reflective on purpose: it walks every script variable of the settlement, its systems,
## buildings, citizens, walkers, inventories, the clock and the map. Comparing to_dict() on both sides would agree
## even if a field were missing from the save, because both sides build that dict the same way.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket19_save.dat"

var reg: DataRegistry
var _diffs: Array[String] = []

## Fields that are not part of a save: caches rebuilt from saved state, back-references, Callable wiring attached
## after a load (views and later-ticket hooks) and bookkeeping that only means something inside a step call.
const SKIP := {
	# Settlement
	"registry": "the caller hands the same DataRegistry to load; defs are resolved through it",
	"_system_cache": "script -> system lookup cache, refilled on demand",
	"_system_cache_size": "script -> system lookup cache, refilled on demand",
	"_reached": "road BFS cache, rebuilt from roads on load",
	"_roads_dirty": "road BFS bookkeeping, set by load",
	"_deferred": "pending day hooks; SaveGame.save flushes them, so a save never holds any",
	"_deferred_head": "pending day hooks; SaveGame.save flushes them",
	"_frame_step": "only meaningful inside a step_seconds call",
	# WalkerSystem
	"_s": "back-reference to the settlement, set on the first hook after load",
	"_grid": "AStarGrid2D, rebuilt from the loaded map and buildings",
	"_speeds": "A* walk speed cache, rebuilt",
	"_solid": "A* solid tile cache, rebuilt",
	"_grid_version": "A* cache version, rebuilt",
	"_max_speed": "A* cache value, rebuilt",
	"_last_max_speed": "A* cache value, rebuilt",
	"_structure_version": "A* cache version, rebuilt",
	"_cache": "path cache, rebuilt",
	"path_computations": "diagnostic counter for tests, not simulation state",
	"_bins": "departure bins are a pure function of the map seed and citizen id, rebuilt",
	"_bins_seed": "seed the bins cache was built for",
	"_from_save": "one-shot load handshake, consumed by the first grid refresh",
	# JobSystem
	"_citizens": "hourly refresh shortcut, a cache of the citizen count",
	"_buildings": "hourly refresh shortcut, a cache of the building count",
	# HaulingSystem
	"_walk_cache": "door walking time cache, rebuilt on a grid change",
	"_walk_version": "walk cache version",
	"_layout_version": "layout cache version",
	"_layout_count": "layout cache version",
	"_ids": "id-sorted building list cache",
	"_storages": "storage building list cache",
	# ProductionSystem
	"modifiers": "Callable list wired in add_default_systems, identical on both sides",
	"_forest_cache": "nearest forest tile cache, rebuilt",
	"_forest_version": "nearest forest cache version",
	"_producer_list": "producer list cache, rebuilt",
	"_producers_version": "producer list cache version",
	"_producers_count": "producer list cache version",
	"_first_out": "recipe -> first output id cache, rebuilt",
	# GrowthSystem
	"_map": "back-reference to the map, set at the start of on_day",
	# BlightSystem
	"blockers": "Callable list filled by later tickets",
	# PlanetHealthSystem
	"extra_sources": "Callable list filled by later tickets",
	# SpiritSystem
	"_hooks": "factor Callables wired in add_default_systems",
	# EventBus
	"_subs": "subscribers are views and UI, attached again after a load",
}


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func after_each() -> void:
	DirAccess.remove_absolute(_save_path())


func _save_path() -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return SAVE_DIR.path_join(SAVE_FILE)


# ---------------------------------------------------------------- fixture

## A small played settlement: roads, an instant forager and storehouse, a tent and a meeting hall as sites, and
## plenty of materials so the haulers deliver and the builders start. Two days later the hall is half built; a
## second hall site and fresh materials are then put down and the clock moved to the 06:00 shift, where a few small
## frame-sized steps leave haulers mid-trip (and therefore walking), production batches partly collected and
## _hour_acc non-zero.
func _fixture() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	assert_true(s.place_building_instant("forager", Vector2i(h.x + 4, h.y - 1)) >= 0, "forager placed")
	assert_true(s.place_building_instant("storehouse", Vector2i(h.x + 6, h.y - 1)) >= 0, "storehouse placed")
	assert_true(s.place_building("tent", Vector2i(h.x + 9, h.y - 1)) >= 0, "tent site placed")
	assert_true(s.place_building("meeting_hall", Vector2i(h.x + 11, h.y - 2)) >= 0, "hall site placed")
	s.hearth.inventory.add("materials", 200.0)  # the hall alone takes 60; enough for all three sites
	s.step_days(2)
	# A second hall is placed just before the save point so haulers are still delivering it at 06:00.
	assert_true(s.place_building("meeting_hall", Vector2i(h.x + 14, h.y - 2)) >= 0, "second hall site placed")
	s.hearth.inventory.add("materials", 200.0)
	s.step_hours(6)
	for i in 40:
		s.step_seconds(0.2)
		if _moving_walkers(s) > 0 and (s.get_system(HaulingSystem) as HaulingSystem).trips.size() > 0:
			break

	# The fixture is only useful if the interesting state is really mid-flight at the save point.
	assert_gt(s._hour_acc, 0.0, "the save point is inside an hour")
	assert_gt(_moving_walkers(s), 0, "walkers are on the road at the save point")
	assert_gt((s.get_system(HaulingSystem) as HaulingSystem).trips.size(), 0, "a hauler is mid-trip")
	var building := 0
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.site and b.build_work > 0.0:
			building += 1
	assert_gt(building, 0, "a construction site is half built")
	return s


func _moving_walkers(s: Settlement) -> int:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var n := 0
	for id in ws.walkers:
		if not (ws.walkers[id] as Walker).path.is_empty():
			n += 1
	return n


# ---------------------------------------------------------------- reflective compare

func _assert_same(a: Variant, b: Variant, label: String) -> void:
	_diffs.clear()
	_compare_state(a, b, "settlement")
	var msg := label
	for i in mini(_diffs.size(), 25):
		msg += "\n  " + _diffs[i]
	if _diffs.size() > 25:
		msg += "\n  ... %d more" % (_diffs.size() - 25)
	assert_eq(_diffs.size(), 0, msg)


## Walks two values of the same shape and records every difference. Script variables are compared; named caches are
## skipped (see SKIP). Resources (defs) are compared by identity, because a load resolves them through the same
## registry.
func _compare_state(a: Variant, b: Variant, path: String) -> void:
	if typeof(a) != typeof(b):
		_diffs.append("%s: type %s != %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
		return
	match typeof(a):
		TYPE_OBJECT:
			if a is Resource:
				if a != b:
					_diffs.append("%s: different resource %s vs %s" % [path, a, b])
				return
			for p in (a as Object).get_property_list():
				if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
					continue
				var name := str(p["name"])
				if SKIP.has(name):
					continue
				_compare_state((a as Object).get(name), (b as Object).get(name), path + "." + name)
		TYPE_ARRAY:
			if a.size() != b.size():
				_diffs.append("%s: array size %d != %d" % [path, a.size(), b.size()])
				return
			for i in a.size():
				_compare_state(a[i], b[i], "%s[%d]" % [path, i])
		TYPE_DICTIONARY:
			var ka: Array = a.keys()
			var kb: Array = b.keys()
			if ka.size() != kb.size():
				_diffs.append("%s: dict size %d != %d" % [path, ka.size(), kb.size()])
				return
			for i in ka.size():
				if typeof(ka[i]) != typeof(kb[i]) or ka[i] != kb[i]:
					_diffs.append("%s: key %d %s != %s" % [path, i, ka[i], kb[i]])
					continue
				_compare_state(a[ka[i]], b[ka[i]], "%s[%s]" % [path, ka[i]])
		TYPE_CALLABLE:
			return  # callables are not state; kept out by name in SKIP where a class holds them
		_:
			if a != b:
				_diffs.append("%s: %s != %s" % [path, a, b])


# ---------------------------------------------------------------- tests

func test_save_load_gives_identical_state() -> void:
	var s := _fixture()
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	assert_eq(loaded.clock.total_hours, s.clock.total_hours)
	assert_eq(loaded.buildings.size(), s.buildings.size())
	assert_eq(loaded.citizens.size(), s.citizens.size())
	for id in s.buildings:
		assert_same(loaded.buildings[id].def, s.buildings[id].def, "defs are resolved through the registry")
	_assert_same(s, loaded, "the loaded settlement differs from the saved one")


func test_loaded_settlement_runs_three_days_identically() -> void:
	var s := _fixture()
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	_assert_same(s, loaded, "after load")
	for day in 3:
		s.step_days(1)
		loaded.step_days(1)
		_assert_same(s, loaded, "the loaded run differs on day %d" % (day + 1))
	# And one more save round trip at the end: what the loaded half produced is itself saveable and reloads.
	assert_eq(SaveGame.save(loaded, path), OK)
	var again := SaveGame.load(path, reg)
	assert_not_null(again)
	_assert_same(loaded, again, "a save of the loaded settlement does not round trip")


func test_save_file_is_compressed_and_carries_a_version() -> void:
	var s := _fixture()
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var on_disk := FileAccess.get_file_as_bytes(path)
	assert_gt(on_disk.size(), 0)
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert_not_null(f, "the file opens as a compressed FileAccess")
	var payload: Variant = f.get_var(false)
	f.close()
	assert_eq(typeof(payload), TYPE_DICTIONARY)
	assert_eq(int((payload as Dictionary)["version"]), SaveGame.CURRENT_VERSION)
	assert_eq(SaveGame.CURRENT_VERSION, 1)
	assert_true((payload as Dictionary).has("state"))
	# The data on disk is smaller than the payload it decodes to, and the file does not start with the raw Variant
	# bytes: it is a compressed container around them (a plain FileAccess.get_var cannot parse it).
	var uncompressed := var_to_bytes(payload)
	assert_lt(on_disk.size(), uncompressed.size(),
			"on disk %d bytes for a %d byte payload" % [on_disk.size(), uncompressed.size()])
	assert_ne(on_disk.slice(0, 8), uncompressed.slice(0, 8), "the file is wrapped, not raw variant bytes")


func test_save_flushes_pending_day_hooks() -> void:
	# A frame-sized step leaves the day's hooks queued (ticket 57c). A save runs them first, so neither the file nor
	# the settlement is left between the day change and its hooks.
	var s := Settlement.new_game(SEED, reg)
	s.step_hours(GameClock.HOURS_PER_DAY - 1)
	while s.clock.total_hours < GameClock.HOURS_PER_DAY:
		s.step_seconds(0.2)
	assert_gt(s._deferred.size(), 0, "a frame-sized step leaves day hooks queued")
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	assert_eq(s._deferred.size(), 0, "save ran the pending day hooks")
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	_assert_same(s, loaded, "a save taken across a day boundary does not round trip")
