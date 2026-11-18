extends GutTest
## Ticket 76: GameSettings (user://settings.cfg store) and the Settings panel.

var path: String


func before_each() -> void:
	path = "/tmp/hv_settings_test_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(path)


func after_each() -> void:
	DirAccess.remove_absolute(path)


func _gs() -> GameSettings:
	var g := GameSettings.new()
	g.path = path
	return g


func test_round_trip_every_key() -> void:
	var a := _gs()
	a.fullscreen = true
	a.ui_scale = 1.5
	a.hints_enabled = false
	a.tutorial_first_run_done = true
	a.seen_hints = ["build_first", "hauler"]
	a.volume_master = 0.1
	a.volume_effects = 0.25
	a.volume_ambience = 0.5
	a.mute_in_background = false
	assert_eq(a.save(), OK)
	var b := _gs()
	b.load_file()
	assert_eq(b.to_dict(), a.to_dict())
	assert_ne(b.to_dict(), _gs().to_dict(), "the values differ from the defaults")


func test_missing_or_corrupt_file_gives_defaults() -> void:
	var d := _gs()
	d.load_file()
	assert_false(d.fullscreen)
	assert_eq(d.ui_scale, 1.0)
	assert_true(d.hints_enabled)
	assert_false(d.tutorial_first_run_done)
	assert_eq(d.seen_hints.size(), 0)
	assert_eq(d.volume_master, 0.8)
	assert_eq(d.volume_effects, 0.8)
	assert_eq(d.volume_ambience, 0.8)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[[[ not a config \u0001\u00ff")
	f.close()
	var c := _gs()
	c.load_file()
	assert_engine_error("ConfigFile parse error")  # the engine logs the bad syntax; load_file itself must not fail
	assert_eq(c.to_dict(), d.to_dict())
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[settings]\nui_scale=\"big\"\nvolume_master=7.0\nfullscreen=3\nseen_hints=5\n")
	f.close()
	var w := _gs()
	w.load_file()
	assert_eq(w.ui_scale, 1.0)
	assert_eq(w.volume_master, 1.0, "clamped to 0-1")
	assert_false(w.fullscreen)
	assert_eq(w.seen_hints.size(), 0)


func test_reset_tutorial_clears_only_seen_hints_and_first_run() -> void:
	var g := _gs()
	g.fullscreen = true
	g.ui_scale = 1.25
	g.hints_enabled = false
	g.volume_effects = 0.3
	g.mute_in_background = false
	g.tutorial_first_run_done = true
	g.seen_hints = ["a", "b"]
	g.reset_tutorial()
	assert_eq(g.seen_hints.size(), 0)
	assert_false(g.tutorial_first_run_done)
	assert_true(g.fullscreen)
	assert_eq(g.ui_scale, 1.25)
	assert_false(g.hints_enabled)
	assert_eq(g.volume_effects, 0.3)
	assert_false(g.mute_in_background)


func test_panel_builds_headless_and_changes_save_at_once() -> void:
	var g := _gs()
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	panel.setup(g)
	await wait_process_frames(1)
	panel.set_hints_enabled(false)
	panel.set_ui_scale(1.25)
	var back := _gs()
	back.load_file()
	assert_false(back.hints_enabled)
	assert_eq(back.ui_scale, 1.25)
	g.apply(get_tree().root)  # no-op-safe headless
	get_tree().root.content_scale_factor = 1.0


func test_main_owns_settings_and_menu_opens_the_panel() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	main.saves_dir = "/tmp/hv_settings_saves_%d" % OS.get_process_id()
	main.settings_path = path
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_true(main.settings is GameSettings)
	assert_eq(main.settings.path, path)
	main.menu.open()
	main.menu.show_settings()
	await wait_process_frames(1)
	assert_true(main.menu.settings_panel.is_visible_in_tree())
	main.menu.close()
