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
## Entries are "ClassName.field": a field name alone would also skip the same name in an unrelated class (several
## systems have a `_grid` or `_map`). Callable values are not skipped by name at all: the compare already ignores
## them, but it still checks list sizes and dictionary keys, which is what catches a hook list lost on load.
const SKIP := {
	# Settlement
	"Settlement.registry": "the caller hands the same DataRegistry to load; defs are resolved through it",
	"Settlement._system_cache": "script -> system lookup cache, refilled on demand",
	"Settlement._system_cache_size": "script -> system lookup cache, refilled on demand",
	"Settlement._reached": "road BFS cache, rebuilt from roads on load",
	"Settlement._roads_dirty": "road BFS bookkeeping, set by load",
	"Settlement._deferred": "pending day hooks; SaveGame.save flushes them, so a save never holds any",
	"Settlement._deferred_head": "pending day hooks; SaveGame.save flushes them",
	"Settlement._frame_step": "only meaningful inside a step_seconds call",
	# MapState
	"MapState.water_version": "counter of water-terrain changes, not saved; a load rebuilds the water cache",
	"MapState.foul_version": "counter of fouling changes, not saved; a load rebuilds the fouling mask and caches",
	# WaterSystem
	"WaterSystem._base": "wet base from water terrain, a cache rebuilt from the map on the first pass after a load",
	"WaterSystem._base_version": "version the water base was built for, a cache rebuilt on the first pass after a load",
	# FoulingSystem
	"FoulingSystem._tiles": "river tile list, a cache of the map's flow grid",
	"FoulingSystem._only_foul": "wet-only-from-fouled tile mask, a cache rebuilt from map, channels and fouling",
	"FoulingSystem._mask_water_version": "version the fouling mask was built for, rebuilt on demand",
	"FoulingSystem._mask_foul_version": "version the fouling mask was built for, rebuilt on demand",
	"FoulingSystem._mask_structure_version": "version the fouling mask was built for, rebuilt on demand",
	# WalkerSystem
	"WalkerSystem._s": "back-reference to the settlement, set on the first hook after load",
	"WalkerSystem._grid": "AStarGrid2D, rebuilt from the loaded map and buildings",
	"WalkerSystem._speeds": "A* walk speed cache, rebuilt",
	"WalkerSystem._solid": "A* solid tile cache, rebuilt",
	"WalkerSystem._grid_version": "A* cache version, rebuilt",
	"WalkerSystem._max_speed": "A* cache value, rebuilt",
	"WalkerSystem._last_max_speed": "A* cache value, rebuilt",
	"WalkerSystem._structure_version": "A* cache version, rebuilt",
	"WalkerSystem._cache": "path cache, rebuilt",
	"WalkerSystem.path_computations": "diagnostic counter for tests, not simulation state",
	"WalkerSystem._bins": "departure bins are a pure function of the map seed and citizen id, rebuilt",
	"WalkerSystem._bins_seed": "seed the bins cache was built for",
	"WalkerSystem._from_save": "one-shot load handshake, consumed by the first grid refresh",
	"WalkerSystem._handcart_zones": "region handcart cache, rebuilt from the buildings when its key moves",
	"WalkerSystem._zones_key": "cache key for _handcart_zones",
	"Settlement.completion_version": "cache key only, bumped on site completion; caches rebuild after load",
	# JobSystem
	"JobSystem._citizens": "hourly refresh shortcut, a cache of the citizen count",
	"JobSystem._buildings": "hourly refresh shortcut, a cache of the building count",
	"JobSystem._grid": "hourly refresh shortcut, a cache of the structure version",
	# HaulingSystem
	"HaulingSystem._walk_cache": "door walking time cache, rebuilt on a grid change",
	"HaulingSystem._walk_version": "walk cache version",
	"HaulingSystem._layout_version": "layout cache version",
	"HaulingSystem._layout_count": "layout cache version",
	"HaulingSystem._ids": "id-sorted building list cache",
	"HaulingSystem._storages": "storage building list cache",
	# ProductionSystem
	"ProductionSystem._forest_cache": "nearest forest tile cache, rebuilt",
	"ProductionSystem._forest_version": "nearest forest cache version",
	"ProductionSystem._producer_list": "producer list cache, rebuilt",
	"ProductionSystem._producers_version": "producer list cache version",
	"ProductionSystem._producers_count": "producer list cache version",
	"ProductionSystem._first_out": "recipe -> first output id cache, rebuilt",
	# GrowthSystem
	"GrowthSystem._map": "back-reference to the map, set at the start of on_day",
	# MarketSystem
	"MarketSystem._reach_version": "Market reach cache version, rebuilt from the layout",
	"MarketSystem._in_reach": "Market reach per home cache, rebuilt from the layout",
	# CoverageSystem
	"CoverageSystem._version": "covered-home cache version, rebuilt from the layout",
	"CoverageSystem._covered": "covered-home set cache, rebuilt from the layout",
	"CoverageSystem._water": "water-served home set cache, rebuilt from the layout",
	"CoverageSystem._foul_version": "fouling version the water cache was built for, rebuilt on demand",
	# EventBus
	"EventBus._subs": "subscribers are views and UI, attached again after a load",
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


## Places a finished forager (a 1x1 job building) on the first free grass tile a good walk from the Hearth.
## Returns its id, -1 when the map has no such spot. Used as a throwaway destination the test can demolish.
func _place_a_throwaway_job(s: Settlement) -> int:
	var h := s.map.hearth_spot
	for dy in range(-4, 5):
		for dx in range(8, 21):
			var id := s.place_building_instant("forager", h + Vector2i(dx, dy))
			if id >= 0:
				return id
	return -1


## No walker on a tile with speed 0: a walker that cannot move off such a tile is stuck for good. (Doors are solid
## but still have a walk speed, so standing at a door passes.)
func _assert_walkers_on_walkable_tiles(s: Settlement) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	for id in ws.walkers:
		var w: Walker = ws.walkers[id]
		assert_gt(ws.tile_speed(w.tile), 0.0, "walker %d stands on a tile with speed 0" % id)


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


## Skip-list prefix of an object: its global class name, or the script file name for inner classes (Trip), which
## have no global class name.
func _class_key(o: Object) -> String:
	var script := o.get_script() as GDScript
	if script == null:
		return o.get_class()
	var global := str(script.get_global_name())
	if global != "":
		return global
	var path := script.resource_path
	return path.get_file().get_basename() if path != "" else o.get_class()


## Walks two values of the same shape and records every difference. Script variables are compared; named caches are
## skipped (see SKIP, keyed "ClassName.field"). Resources (defs) are compared by identity, because a load resolves
## them through the same registry.
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
			var cls := _class_key(a as Object)
			for p in (a as Object).get_property_list():
				if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
					continue
				var name := str(p["name"])
				if SKIP.has(cls + "." + name):
					continue
				if a is EventBus and name == "log":
					# The saved log keeps only the newest EventBus.SAVED_LOG_LIMIT entries (ticket 19c), so a
					# long-running settlement has a longer in-memory log than a save. Compare the tails both sides
					# keep; the cap itself is tested in test_save_slots.gd.
					_compare_event_log(a as EventBus, b as EventBus, path + "." + name)
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


## Compares what two EventBus logs share: the newest EventBus.SAVED_LOG_LIMIT entries. A loaded settlement's in-memory
## log starts shorter than the live one only when the save dropped its oldest entries; from then on both grow alike.
func _compare_event_log(a: EventBus, b: EventBus, path: String) -> void:
	var tail_a: Array = a.log.slice(maxi(0, a.log.size() - EventBus.SAVED_LOG_LIMIT))
	var tail_b: Array = b.log.slice(maxi(0, b.log.size() - EventBus.SAVED_LOG_LIMIT))
	if tail_a.size() != tail_b.size():
		_diffs.append("%s: log tail size %d != %d" % [path, tail_a.size(), tail_b.size()])
		return
	for i in tail_a.size():
		_compare_state(tail_a[i], tail_b[i], "%s[%d]" % [path, i])


# ---------------------------------------------------------------- tests

func test_save_load_gives_identical_state() -> void:
	var s := _fixture()
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	assert_not_null(loaded.hearth, "the hearth loads")
	assert_same(loaded.hearth, loaded.buildings[loaded.hearth.id])
	assert_eq(loaded.clock.total_hours, s.clock.total_hours)
	assert_eq(loaded.buildings.size(), s.buildings.size())
	assert_eq(loaded.citizens.size(), s.citizens.size())
	for id in s.buildings:
		assert_same(loaded.buildings[id].def, s.buildings[id].def, "defs are resolved through the registry")
	_assert_same(s, loaded, "the loaded settlement differs from the saved one")


func test_layout_change_made_before_a_save_is_re_planned() -> void:
	# A road/building change between the last step and the save bumps the settlement's grid_version but the walker
	# grid never sees it, so the saved paths belong to the old layout. Live, the next step re-plans (or drops) them;
	# a load must do the same instead of trusting the saved paths.
	var s := _fixture()
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var job := _place_a_throwaway_job(s)
	assert_true(job >= 0, "a throwaway job building went down")
	if job < 0:
		return
	# Send a plain (schedule-driven) walker to it and take one frame so the walker is really on the road.
	var walker: Walker = null
	for cid in ws.walkers:
		if (ws.walkers[cid] as Walker).controlled:
			continue
		if ws.walk_to_building(cid, job):
			walker = ws.walkers[cid]
			break
	assert_not_null(walker, "a plain walker was sent to the throwaway building")
	if walker == null:
		return
	s.step_seconds(0.2)
	assert_false(walker.path.is_empty(), "the walker is walking to the throwaway building")
	# Demolish it with no step after: the saved path now points at a building that no longer exists.
	assert_true(s.demolish(job), "the throwaway building was demolished")
	assert_ne(ws._grid_version, s.grid_version, "the walker grid is stale: no step ran after the layout change")
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	_assert_same(s, loaded, "after load")
	# The two sides now step in lockstep: both re-plan the stale paths on the first step.
	for i in 300:
		s.step_seconds(0.2)
		loaded.step_seconds(0.2)
		if i % 25 == 0:
			_assert_same(s, loaded, "the loaded settlement diverges at frame %d" % i)
			_assert_walkers_on_walkable_tiles(s)
			_assert_walkers_on_walkable_tiles(loaded)
	_assert_same(s, loaded, "a layout change made before the save was not re-planned after load")
	_assert_walkers_on_walkable_tiles(loaded)


func test_loaded_settlement_runs_three_days_identically() -> void:
	var s := _fixture()
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	_assert_same(s, loaded, "after load")
	# Frame-sized steps across day boundaries before the coarse days: they exercise the spread day hooks, the
	# production slices and the replan queue drain, which a step_days call runs all at once.
	for i in 2000:
		s.step_seconds(0.2)
		loaded.step_seconds(0.2)
	_assert_same(s, loaded, "frame-sized steps across a day boundary diverge")
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
	assert_eq(SaveGame.CURRENT_VERSION, 2)
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
