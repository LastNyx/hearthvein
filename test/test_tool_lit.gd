extends GutTest
## Ticket 95: the active tool is lit, Upgrade is a build mode, the irrigation channel is explained and previewed.

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_toollit_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _game(era: String = "town") -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42, false, false)
	await wait_process_frames(2)
	main.settlement.era_override = era
	for r in MapState.REGION_COUNT:
		main.settlement.map.region_owned[r] = 1
	(main.get_node("Hud") as Hud)._rebuild_categories()
	await wait_process_frames(2)
	return main


func _on(b: Button) -> bool:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).border_color == Hud.GOLD


func _open(hud: Hud, cat: String) -> void:
	if hud._open_cat != "":
		hud.open_category(hud._open_cat)
	hud.open_category(cat)
	await wait_process_frames(2)


func _flyout(hud: Hud, name: String) -> Button:
	return hud._fly_box.find_child(name, true, false) as Button


func test_active_tool_is_lit_and_goes_dark_when_the_mode_ends() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var build: BuildController = main.get_node("BuildController")
	var tab := hud.tools_tab
	tab.set_open(true)
	assert_false(_on(tab.button("demolish")))
	assert_false(_on(tab.button("upgrade")))
	tab.button("demolish").pressed.emit()
	assert_true(_on(tab.button("demolish")))
	assert_false(_on(tab.button("upgrade")))
	tab.button("upgrade").pressed.emit()
	assert_eq(build.mode, BuildController.Mode.UPGRADE)
	assert_true(_on(tab.button("upgrade")))
	assert_false(_on(tab.button("demolish")))
	build.cancel()
	assert_false(_on(tab.button("upgrade")))
	await _open(hud, "housing")
	hud.build_button("tent").pressed.emit()
	assert_true(_on(hud.build_button("tent")))
	build.set_build("cottage")
	assert_false(_on(hud.build_button("tent")))
	assert_true(_on(hud.build_button("cottage")))
	build.cancel()
	assert_false(_on(hud.build_button("cottage")))
	await _open(hud, "roads")
	for pair in [["road", BuildController.Mode.ROAD], ["paved", BuildController.Mode.PAVED], ["channel", BuildController.Mode.CHANNEL]]:
		build.set_mode(pair[1])
		assert_true(_on(_flyout(hud, "Tool_" + pair[0])), pair[0])
		build.cancel()
		assert_false(_on(_flyout(hud, "Tool_" + pair[0])), pair[0])
	build.set_mode(BuildController.Mode.DEMOLISH)
	assert_true(_on(_flyout(hud, "Tool_demolish")))


func test_upgrade_mode_upgrades_on_click_stays_on_and_refuses_with_the_reason() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var build: BuildController = main.get_node("BuildController")
	var hud: Hud = main.get_node("Hud")
	var h := s.map.hearth_spot
	var id := -1
	var at := Vector2i.ZERO
	for dx in range(-12, 13):
		for dy in range(-12, 13):
			if id < 0:
				at = h + Vector2i(dx, dy)
				id = s.place_building_instant("tent", at)
	assert_true(id >= 0)
	build._unhandled_input(_key(KEY_U))
	assert_eq(build.mode, BuildController.Mode.UPGRADE)
	build._click(at)
	assert_true(s.buildings[id].upgrading())
	assert_eq(build.mode, BuildController.Mode.UPGRADE, "stays on")
	build._click(at)
	assert_string_contains(build.hint_text(), "Upgrade in progress")
	build._click(h)  # the Hearth cannot be upgraded
	assert_string_contains(build.hint_text(), "Cannot be upgraded")
	assert_eq(build.mode, BuildController.Mode.UPGRADE)
	build.cancel()
	assert_eq(build.mode, BuildController.Mode.NONE)
	assert_not_null(hud)


func test_channel_text_comes_from_data_in_tooltip_hint_and_help() -> void:
	var main: Node = await _game("village")
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var build: BuildController = main.get_node("BuildController")
	await _open(hud, "roads")
	var tip := _flyout(hud, "Tool_channel").tooltip_text
	assert_string_contains(tip, "connected to water")
	assert_string_contains(tip, "50%")
	assert_string_contains(tip, "25%")
	assert_string_contains(tip, "higher farm tiers need wet ground")
	build.set_mode(BuildController.Mode.CHANNEL)
	assert_string_contains(build.hint_text(), "connected to water")
	var w := s.registry.water  # a shared resource: put it back below
	var old_fraction := w.farm_wet_fraction
	var old_bonus := w.farm_wet_bonus
	w.farm_wet_fraction = 0.6
	w.farm_wet_bonus = 1.5
	var tip2 := HudModel.new(s).channel_help_text()
	assert_string_contains(tip2, "60%")
	assert_string_contains(tip2, "50%")
	var body := HelpScreen.resolve((s.registry.help_pages["controls"] as HelpPageDef).body, s.registry)
	assert_string_contains(body, tip2)
	assert_false(body.contains("{"))
	w.farm_wet_fraction = old_fraction
	w.farm_wet_bonus = old_bonus


func test_channel_preview_is_the_tiles_that_would_be_wet() -> void:
	var main: Node = await _game("village")
	var s: Settlement = main.settlement
	var water := s.map.terrain_index("water")
	var shore := Vector2i(-1, -1)
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 2):
			var t := Vector2i(x, y)
			if shore.x < 0 and s.map.get_terrain(x, y) != water and s.map.get_terrain(x + 1, y) == water \
					and s.can_place_channel(t)["ok"]:
				shore = t
	assert_true(shore.x >= 0)
	var want: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			want.append(shore + Vector2i(dx, dy))
	var got := WaterSystem.channel_preview(s, shore)
	got.sort()
	want.sort()
	assert_eq(got, want)
	var old_radius := s.registry.water.wet_radius_channel  # a shared resource: put it back
	s.registry.water.wet_radius_channel = 2
	assert_eq(WaterSystem.channel_preview(s, shore).size(), 25)
	s.registry.water.wet_radius_channel = old_radius
	# A tile beside a flowing channel flows too; one that touches no water or flowing channel stays dry.
	assert_true(s.place_channel(shore))
	var next := shore + Vector2i(-1, 0)
	if s.can_place_channel(next)["ok"]:
		assert_eq(WaterSystem.channel_preview(s, next).size(), 9)
	var far := Vector2i(-1, -1)
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 2):
			if far.x < 0 and absi(x - shore.x) > 6 and absi(y - shore.y) > 6 and WaterSystem.channel_preview(s, Vector2i(x, y)).is_empty():
				far = Vector2i(x, y)
	assert_true(far.x >= 0)


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev
