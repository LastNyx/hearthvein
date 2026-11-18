extends GutTest
## Ticket 85: the F1 help screen (D59c): data pages, hint More, F1 pause/restore, Esc order, Controls page keys.

var dir: String
var cfg: String
var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_help_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _game() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42)
	await wait_process_frames(2)
	return main


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _body(main: Node) -> String:
	return (main.help.find_child("HelpBody", true, false) as Label).text


func test_every_hint_row_points_at_an_existing_page_and_every_page_is_filled_in() -> void:
	assert_eq(reg.errors.size(), 0)
	for id in HintDef.HELP_PAGES:
		assert_true(reg.help_pages.has(id), "page %s exists" % id)
	assert_eq(reg.help_pages.size(), HintDef.HELP_PAGES.size())
	for h in reg.hints_in_order():
		assert_true(reg.help_pages.has(h.help_page), "hint %s -> %s" % [h.id, h.help_page])
	for p in reg.help_pages_in_order():
		var t := HelpScreen.resolve(p.body, reg)
		assert_false(t.contains("{"), "%s has an unresolved token" % p.id)
		assert_false(t.contains("?"), "%s has a bad token" % p.id)


func test_f1_opens_and_closes_pauses_and_restores_the_speed() -> void:
	var main: Node = await _game()
	main.driver.set_speed(3)
	assert_false(main.help.is_open())
	main.help._input(_key(KEY_F1))
	assert_true(main.help.is_open())
	assert_eq(main.driver.speed, 0)
	main.help._input(_key(KEY_F1))
	assert_false(main.help.is_open())
	assert_eq(main.driver.speed, 3)
	# Esc closes the help first and does not open the pause menu
	main.help._input(_key(KEY_F1))
	main._input(_key(KEY_ESCAPE))
	assert_false(main.help.is_open())
	assert_false(main.menu.is_open())
	assert_eq(main.driver.speed, 3)
	main._input(_key(KEY_ESCAPE))
	assert_true(main.menu.is_open())


func test_pages_list_on_the_left_show_data_numbers_and_the_hint_more_and_pause_menu_open_it() -> void:
	var main: Node = await _game()
	main.help.open_page("")
	for id in HintDef.HELP_PAGES:
		assert_not_null(main.help.find_child("Page_" + id, true, false), id)
	(main.help.find_child("Page_eras_gates", true, false) as Button).pressed.emit()
	assert_eq(main.help.current_page(), "eras_gates")
	assert_string_contains(_body(main), str(reg.get_era("town").gate_gold))
	assert_string_contains(_body(main), str(reg.get_era("ascendant").gate_pop))
	main.help.close()
	var hud: Hud = main.get_node("Hud")
	hud.hint_cards.help_page_requested.emit("dimming")
	assert_true(main.help.is_open())
	assert_eq(main.help.current_page(), "dimming")
	assert_string_contains(_body(main), str(reg.get_era("village").dimming_base_days))
	assert_string_contains(_body(main), str(reg.planet.light_per_citizen))
	main.help.close()
	main.menu.open()
	var b := main.menu.find_child("Help", true, false) as Button
	assert_true(b.visible)
	b.pressed.emit()
	assert_true(main.help.is_open())


func test_controls_page_lists_only_keys_that_are_bound_in_code() -> void:
	var page := reg.help_pages["controls"] as HelpPageDef
	var src := ""
	for f in ["res://ui/hud.gd", "res://ui/build_controller.gd", "res://render/camera_controller.gd",
			"res://render/sim_driver.gd", "res://ui/help_screen.gd", "res://ui/main.gd"]:
		src += FileAccess.get_file_as_string(f)
	assert_gt(page.keys.size(), 20)
	var labels := {"SPACE": "Space", "TAB": "Tab", "ESCAPE": "Esc"}
	for k in page.keys:
		assert_true(src.contains("KEY_" + k), "KEY_%s is used in code" % k)
		assert_string_contains(page.body, labels.get(k, k))
	for k in ["V", "G", "T", "H", "L", "M", "B", "R", "X", "U", "W", "A", "S", "D", "F1", "ESCAPE"]:
		assert_true(page.keys.has(k), k)
