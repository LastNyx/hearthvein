extends GutTest
## Ticket 19c: autosave rotation, manual slots, atomic writes and the cap on the saved event log.

const SEED := 42

var reg: DataRegistry
var dir: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_slots_%d" % OS.get_process_id()
	_wipe()
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(dir):
		OS.execute("chmod", ["0700", dir])  # a failed-save test may have left it read-only
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if not d.current_is_dir():
				DirAccess.remove_absolute(dir.path_join(name))
			name = d.get_next()
		d.list_dir_end()
	DirAccess.remove_absolute(dir)


func _auto_files() -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.begins_with("auto_") and name.ends_with(".dat"):
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	return out


# ---------------------------------------------------------------- autosave

func test_autosave_rotates_three_files_across_four_seasons() -> void:
	var s := Settlement.new_game(SEED, reg)
	var slots := SaveSlots.new(dir)
	slots.attach(s)
	# A season start only fires when the clock advances into it; the first is the start of summer at 8 days.
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.clock.total_hours, 8 * GameClock.HOURS_PER_DAY)
	assert_eq(_auto_files().size(), 1, "the first season start writes one autosave")
	# A frame-sized step spreads the season hooks over frames (ticket 57c); the autosave still fires once, after them.
	s.step_hours(8 * GameClock.HOURS_PER_DAY - 1)
	while s.clock.total_hours < 16 * GameClock.HOURS_PER_DAY:
		s.step_seconds(0.1)
	for i in 40:
		if s._deferred.is_empty():
			break
		s.step_seconds(0.0)  # runs the next deferred hook without advancing the clock
	assert_eq(s.clock.total_hours, 16 * GameClock.HOURS_PER_DAY, "the frame-stepped season boundary landed")
	assert_eq(_auto_files().size(), 2, "the frame-stepped season start writes the second autosave")
	s.step_days(8)  # third
	s.step_days(8)  # fourth: every rotation index is taken, the oldest (summer, year 1) is overwritten
	assert_eq(_auto_files().size(), SaveSlots.AUTO_SLOTS, "never more than three autosaves on disk")
	var hours := []
	for entry in slots.list():
		if entry["kind"] != "auto":
			continue
		var loaded := slots.load_auto(int(entry["slot"]), reg)
		assert_not_null(loaded, "autosave %d loads back" % int(entry["slot"]))
		if loaded != null:
			hours.append(loaded.clock.total_hours)
	hours.sort()
	assert_eq(hours, [384, 576, 768], "the fourth season overwrote the oldest autosave (192)")
	# latest_auto() is what 19d's continue button loads.
	var latest := slots.load_auto(slots.latest_auto(), reg)
	assert_not_null(latest)
	if latest != null:
		assert_eq(latest.clock.total_hours, 768, "the newest autosave is the one just written")
	# detach() drops the subscription, so the next season writes nothing (19d swaps settlements).
	slots.detach()
	var before := slots.list()
	s.step_days(8)
	assert_eq(slots.list(), before, "detached: no autosave on the next season")


# ---------------------------------------------------------------- manual slots

func test_manual_slots_save_list_load_delete_and_the_ninth_is_refused() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.step_days(1)
	var slots := SaveSlots.new(dir)
	for i in SaveSlots.MANUAL_SLOTS:
		assert_eq(slots.save_slot(i, s), OK, "manual slot %d saves" % i)
	var manual: Array = []
	for entry in slots.list():
		if entry["kind"] == "manual":
			manual.append(entry)
	assert_eq(manual.size(), SaveSlots.MANUAL_SLOTS, "list describes all eight manual slots")
	for i in SaveSlots.MANUAL_SLOTS:
		var entry: Dictionary = manual[i]
		assert_eq(int(entry["slot"]), i)
		assert_eq(entry["kind"], "manual")
		assert_eq(entry["era"], s.era_id())
		assert_eq(entry["date"], s.clock.label())
		assert_eq(int(entry["population"]), s.citizens.size())
		assert_gt(int(entry["saved_at"]), 0, "saved_at is unix time")
	var loaded := slots.load_slot(3, reg)
	assert_not_null(loaded, "slot 3 loads")
	if loaded != null:
		assert_eq(loaded.era_id(), s.era_id())
		assert_eq(loaded.citizens.size(), s.citizens.size())
		assert_eq(loaded.clock.total_hours, s.clock.total_hours)
	assert_eq(slots.delete_slot(2), OK)
	assert_false(FileAccess.file_exists(dir.path_join("slot_2.dat")), "the deleted slot's file is gone")
	var left := 0
	for entry in slots.list():
		if entry["kind"] == "manual":
			left += 1
	assert_eq(left, SaveSlots.MANUAL_SLOTS - 1)
	# A ninth slot (index 8, or below 0) is refused.
	assert_eq(slots.save_slot(8, s), ERR_PARAMETER_RANGE_ERROR)
	assert_eq(slots.save_slot(-1, s), ERR_PARAMETER_RANGE_ERROR)
	assert_null(slots.load_slot(8, reg))
	assert_eq(slots.delete_slot(8), ERR_PARAMETER_RANGE_ERROR)
	assert_false(FileAccess.file_exists(dir.path_join("slot_8.dat")))
	assert_push_error_count(4)


# ---------------------------------------------------------------- atomic write

func test_failed_save_keeps_the_old_file_and_leaves_no_tmp() -> void:
	var s := Settlement.new_game(SEED, reg)
	var slots := SaveSlots.new(dir)
	assert_eq(slots.save_slot(0, s), OK)
	var path := dir.path_join("slot_0.dat")
	var before := FileAccess.get_file_as_bytes(path)
	# The write itself cannot start: the directory is read-only, so the temp file cannot be created.
	s.step_days(1)
	assert_eq(OS.execute("chmod", ["0500", dir]), 0)
	assert_ne(slots.save_slot(0, s), OK, "saving into a read-only directory fails")
	assert_eq(OS.execute("chmod", ["0700", dir]), 0)
	assert_push_error_count(2)  # SaveGame.save and SaveSlots.save_slot each name the failure
	assert_eq(FileAccess.get_file_as_bytes(path), before, "the previous save survived the failed write")
	assert_false(FileAccess.file_exists(path + ".tmp"), "no temp file is left behind")
	var loaded := slots.load_slot(0, reg)
	assert_not_null(loaded)
	if loaded != null:
		assert_eq(loaded.clock.total_hours, 0, "the slot still holds the old save, not the new state")


# ---------------------------------------------------------------- log cap

func test_saved_event_log_is_bounded_over_a_long_run() -> void:
	var s := Settlement.new_game(SEED, reg)
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var jobs := 0
	for dx in range(4, 20):
		for dy in range(-3, 4):
			if jobs >= 5:
				break
			if s.place_building_instant("forager", h + Vector2i(dx, dy)) >= 0:
				jobs += 1
	assert_gte(jobs, 4, "some foragers went down, so citizens commute and walker_arrived is logged")
	s.step_days(40)
	assert_gt(s.events.log.size(), EventBus.SAVED_LOG_LIMIT,
			"the long run logged more than the cap (%d entries)" % s.events.log.size())
	var slots := SaveSlots.new(dir)
	assert_eq(slots.save_slot(0, s), OK)
	var f := FileAccess.open_compressed(dir.path_join("slot_0.dat"), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert_not_null(f)
	var payload: Variant = f.get_var(false)
	f.close()
	var saved_log: Array = (payload as Dictionary)["state"]["events"]["log"]
	assert_eq(saved_log.size(), EventBus.SAVED_LOG_LIMIT, "the save keeps exactly the newest entries")
	assert_eq(saved_log.back(), s.events.log.back(), "the newest entry is the last one saved")
	var loaded := slots.load_slot(0, reg)
	assert_not_null(loaded)
	if loaded != null:
		assert_eq(loaded.events.log.size(), EventBus.SAVED_LOG_LIMIT)
		assert_eq(loaded.clock.total_hours, s.clock.total_hours)
