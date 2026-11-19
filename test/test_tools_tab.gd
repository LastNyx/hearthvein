extends GutTest
## Ticket 88: the bottom-left tools tab (speed control, demolish, upgrade, region map, help).

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_tools_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _game() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42, false, false)
	await wait_process_frames(2)
	return main


func _tab(main: Node) -> ToolsTab:
	return (main.get_node("Hud") as Hud).tools_tab


func _key(main: Node, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	main.driver._unhandled_input(ev)


func _styled_on(b: Button) -> bool:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).border_color == Hud.GOLD


func test_speed_buttons_set_speed_and_label_and_highlight_follow_keys_and_cards() -> void:
	var main: Node = await _game()
	var tab := _tab(main)
	var drv: SimDriver = main.driver
	tab.set_open(true)
	for i in [1, 2, 3]:
		tab.button("speed%d" % i).pressed.emit()
		assert_eq(drv.speed, i)
		assert_eq(tab.button("tab").text, "%dx" % i)
		assert_true(_styled_on(tab.button("speed%d" % i)))
	tab.button("pause").pressed.emit()
	assert_eq(drv.speed, 0)
	assert_eq(tab.button("tab").text, "||")
	assert_true(_styled_on(tab.button("pause")))
	assert_false(_styled_on(tab.button("speed3")))
	tab.button("pause").pressed.emit()
	assert_eq(drv.speed, 3)
	_key(main, KEY_2)
	assert_eq(tab.button("tab").text, "2x")
	assert_true(_styled_on(tab.button("speed2")))
	_key(main, KEY_SPACE)
	assert_eq(tab.button("tab").text, "||")
	_key(main, KEY_SPACE)
	var s: Settlement = main.settlement
	s.era_current = "village"
	s.events.emit("era_changed", {"from": "camp", "to": "village"})
	assert_eq(drv.speed, 0)
	assert_eq(tab.button("tab").text, "||")
	assert_true(_styled_on(tab.button("pause")))
	for k in ["pause", "speed1", "speed2", "speed3", "demolish", "upgrade", "regionmap", "help"]:
		assert_true(tab.button(k).tooltip_text != "", k)
	assert_string_contains(tab.button("demolish").tooltip_text, "X")
	assert_string_contains(tab.button("regionmap").tooltip_text, "M")


func test_demolish_upgrade_region_map_and_help_buttons_do_what_their_keys_do() -> void:
	var main: Node = await _game()
	var tab := _tab(main)
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	tab.set_open(true)
	tab.button("demolish").pressed.emit()
	assert_eq(main.get_node("BuildController").mode, BuildController.Mode.DEMOLISH)
	var region: Control = hud._region_map
	assert_false(region.visible)
	tab.button("regionmap").pressed.emit()
	assert_true(region.visible)
	tab.button("regionmap").pressed.emit()
	assert_false(region.visible)
	s.era_override = "town"
	var id := -1
	var h := s.map.hearth_spot
	for dx in range(-12, 13):
		for dy in range(-12, 13):
			if id < 0:
				id = s.place_building_instant("tent", h + Vector2i(dx, dy))
	assert_true(id >= 0)
	hud.model.select(id)
	tab.button("upgrade").pressed.emit()
	assert_true(hud.model.selection()["upgrading"])
	main.driver.set_speed(2)
	tab.button("help").pressed.emit()
	assert_true(main.help.is_open())
	assert_eq(main.driver.speed, 0)
	assert_eq(tab.button("tab").text, "||")
	main.help.close()
	assert_eq(main.driver.speed, 2)
	assert_eq(tab.button("tab").text, "2x")


func test_collapse_state_persists_through_game_settings() -> void:
	var main: Node = await _game()
	var tab := _tab(main)
	assert_true(tab.is_open())
	assert_true(tab.button("pause").is_visible_in_tree())
	tab.button("tab").pressed.emit()
	assert_false(tab.is_open())
	assert_false(tab.button("pause").is_visible_in_tree())
	var gs := GameSettings.new()
	gs.path = cfg
	gs.load_file()
	assert_false(gs.tools_open)
	var main2: Node = await _game()
	assert_false(_tab(main2).is_open())
	_tab(main2).button("tab").pressed.emit()
	assert_true(_tab(main2).is_open())
	gs.load_file()
	assert_true(gs.tools_open)
