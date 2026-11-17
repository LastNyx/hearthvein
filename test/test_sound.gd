extends GutTest
## Ticket 86: sound credits, volumes onto the buses, event -> sound mapping, rate limit, ambience crossfade.

const AUDIO_DIR := "res://assets/audio"

var reg: DataRegistry
var cfg: String
var dir: String


class FakeSound:
	extends SoundPlayer
	var started: Array[String] = []

	func _start(kind: String) -> void:
		started.append(kind)


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	cfg = "/tmp/hv_sound_test_%d.cfg" % OS.get_process_id()
	dir = "/tmp/hv_sound_test_saves_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	DirAccess.remove_absolute(cfg)
	DirAccess.remove_absolute(dir)


func _files(path: String, rel: String = "") -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(path)
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var r := rel + f
		if d.current_is_dir():
			out.append_array(_files(path.path_join(f), r + "/"))
		elif f.ends_with(".ogg") or f.ends_with(".wav"):
			out.append(r)
		f = d.get_next()
	return out


func _fake() -> FakeSound:
	var s := FakeSound.new()
	var t := [0.0]
	s.clock = func() -> float: return t[0]
	s.set_meta("t", t)
	add_child_autofree(s)
	return s


func _advance(s: Node, secs: float) -> void:
	(s.get_meta("t") as Array)[0] += secs


func test_credits_list_every_file_as_cc0() -> void:
	var text := FileAccess.get_file_as_string(AUDIO_DIR + "/CREDITS.md")
	var listed: Dictionary = {}
	for line in text.split("\n"):
		var cols := line.split("|")
		if cols.size() >= 6 and cols[1].strip_edges().ends_with(".ogg"):
			var licence := cols[4].strip_edges()
			assert_true(licence == "CC0" or licence == "generated, CC0", "licence of %s: %s" % [cols[1], licence])
			assert_false(cols[2].strip_edges().is_empty() or cols[3].strip_edges().is_empty() or cols[5].strip_edges().is_empty())
			listed[cols[1].strip_edges()] = true
	var files := _files(AUDIO_DIR)
	assert_gt(files.size(), 8)
	for f in files:
		assert_true(listed.has(f), "%s is in CREDITS.md" % f)
	assert_eq(listed.size(), files.size(), "CREDITS lists nothing that is not there")


func test_every_sound_file_the_player_uses_exists() -> void:
	for kind: String in SoundPlayer.FILES:
		assert_true(ResourceLoader.exists(SoundPlayer.FILES[kind]), kind)
	assert_true(ResourceLoader.exists(SoundPlayer.DAY_FILE))
	assert_true(ResourceLoader.exists(SoundPlayer.DRONE_FILE))


func test_volume_settings_reach_the_buses() -> void:
	var s := _fake()
	var g := GameSettings.new()
	g.path = cfg
	g.volume_master = 0.5
	g.volume_effects = 0.25
	g.volume_ambience = 0.1
	s.setup(g)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(0.5), 0.01)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")), linear_to_db(0.25), 0.01)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")), linear_to_db(0.1), 0.01)
	# the panel's slider applies at once
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	panel.setup(g)
	panel.set_volume("volume_effects", 0.75)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")), linear_to_db(0.75), 0.01)
	panel.set_volume("volume_master", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	panel.set_volume("volume_master", 0.8)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))


func test_mute_in_background_follows_focus() -> void:
	var s := _fake()
	var g := GameSettings.new()
	g.path = cfg
	s.setup(g)
	var master := AudioServer.get_bus_index("Master")
	s.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(AudioServer.is_bus_mute(master))
	s.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_false(AudioServer.is_bus_mute(master))
	g.mute_in_background = false
	s.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(AudioServer.is_bus_mute(master))
	s.notification(NOTIFICATION_APPLICATION_FOCUS_IN)


func test_events_map_to_sounds() -> void:
	var s := _fake()
	var st := Settlement.new_game(1, reg)
	s.bind(st)
	var expect := {
		"building_placed": "place", "building_demolished": "demolish", "building_completed": "completed",
		"era_changed": "era", "milestone": "milestone", "dimming_forecast": "forecast",
	}
	for ev: String in expect:
		s.started.clear()
		_advance(s, 1.0)
		st.events.emit(ev, {})
		assert_eq(s.started, [expect[ev]] as Array[String], ev)
	s.started.clear()
	_advance(s, 1.0)
	st.events.emit("walker_arrived", {})
	assert_eq(s.started.size(), 0, "other events are silent")


func test_one_sound_of_a_kind_per_015_seconds() -> void:
	var s := _fake()
	assert_true(s.play("click"))
	_advance(s, 0.1)
	assert_false(s.play("click"))
	assert_true(s.play("place"), "another kind is not limited")
	_advance(s, 0.06)
	assert_true(s.play("click"))
	assert_eq(s.started, ["click", "place", "click"] as Array[String])


func test_buttons_click() -> void:
	var s := _fake()
	var b := Button.new()
	add_child_autofree(b)
	b.pressed.emit()
	assert_eq(s.started, ["click"] as Array[String])


func test_ambience_crossfades_on_dimming_events_and_is_right_after_a_load() -> void:
	var s := _fake()
	s.fade_seconds = 0.1
	var st := Settlement.new_game(1, reg)
	assert_eq(s.ambience_mode, "title")
	assert_lt(s.layer_gain("day"), 0.5, "quiet on the title")
	s.bind(st)
	assert_eq(s.ambience_mode, "day")
	assert_eq(s.layer_gain("day"), 1.0)
	st.events.emit("dimming_started", {})
	assert_eq(s.ambience_mode, "drone")
	await get_tree().create_timer(0.3).timeout
	assert_eq(s.layer_gain("drone"), 1.0)
	assert_eq(s.layer_gain("day"), 0.0)
	st.events.emit("dimming_ended", {})
	await get_tree().create_timer(0.3).timeout
	assert_eq(s.ambience_mode, "day")
	assert_eq(s.layer_gain("day"), 1.0)
	assert_eq(s.layer_gain("drone"), 0.0)
	# a save loaded mid-Dimming starts on the drone
	(st.get_system(DimmingSystem) as DimmingSystem)._active = true
	var s2 := _fake()
	s2.bind(st)
	assert_eq(s2.ambience_mode, "drone")
	assert_eq(s2.layer_gain("drone"), 1.0)
	s2.set_title()
	assert_eq(s2.ambience_mode, "title")


func test_main_owns_a_sound_player_that_follows_its_settlements() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await get_tree().process_frame
	var snd: SoundPlayer = main.sound
	assert_not_null(snd)
	assert_eq(snd.ambience_mode, "title")
	main.start_new_game(1)
	assert_eq(snd.ambience_mode, "day")
	var first: Settlement = main.settlement
	main.start_new_game(2)
	first.events.emit("era_changed", {})  # a swapped-out bus is silent
	snd.clock = func() -> float: return 99.0
	main.settlement.events.emit("dimming_started", {})
	assert_eq(snd.ambience_mode, "drone")
	main.return_to_title()
	assert_eq(snd.ambience_mode, "title")
	assert_eq(snd.get_parent(), main)
