extends GutTest
## Ticket 83: the tutorial goal panel, the highlight on the build bar, the camera goal and the closing card.

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_tp_%d" % OS.get_process_id()
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


## A Main in a running game; the tutorial one by default.
func _game(tutorial: bool = true) -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(-1 if tutorial else 42, false, tutorial)
	await wait_process_frames(2)
	return main


func _road_out(s: Settlement) -> void:
	var start := s.map.hearth_spot + Vector2i(s.hearth.def.size.x, 0)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.place_road(start + d):
			return
	fail_test("no road tile next to the starting road")


func _panel(main: Node) -> TutorialPanel:
	return (main.get_node("Hud") as Hud).tutorial_panel


func _label_texts(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out


func test_panel_shows_the_goal_follows_state_and_survives_a_load() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var p := _panel(main)
	assert_true(p.visible)
	var texts := _label_texts(p)
	assert_string_contains(texts, "Tutorial 1/10")
	assert_string_contains(texts, "Drag with the right mouse button")
	assert_string_contains(texts, "Get a feel for the land")
	s.report_camera_moved()
	p.refresh()
	assert_string_contains(_label_texts(p), "Tutorial 2/10")
	assert_true(p.check_visible(), "check flashes when a goal completes")
	var path := dir + "/tp.save"
	assert_eq(SaveGame.save(s, path), OK)
	main.swap_settlement(SaveGame.load(path, main.registry))
	await wait_process_frames(2)
	var p2 := _panel(main)
	assert_true(p2.visible)
	assert_string_contains(_label_texts(p2), "Tutorial 2/10")
	assert_string_contains(_label_texts(p2), "Draw a road")


func test_panel_hidden_when_inactive_and_after_skip() -> void:
	var off: Node = await _game(false)
	assert_false(_panel(off).visible, "no tutorial")
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var p := _panel(main)
	assert_true(p.visible)
	s.skip_tutorial()
	p.refresh()
	assert_false(p.visible, "skipped")


func test_skip_asks_to_confirm() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var p := _panel(main)
	var tut := s.get_system(TutorialSystem) as TutorialSystem
	(p.find_child("Skip", true, false) as Button).pressed.emit()
	assert_true((p.find_child("SkipConfirm", true, false) as Control).visible)
	assert_true(tut.is_active(), "not skipped yet")
	(p.find_child("SkipNo", true, false) as Button).pressed.emit()
	assert_false((p.find_child("SkipConfirm", true, false) as Control).visible)
	assert_true(tut.is_active())
	(p.find_child("Skip", true, false) as Button).pressed.emit()
	(p.find_child("SkipYes", true, false) as Button).pressed.emit()
	assert_false(tut.is_active())


func test_highlight_follows_the_goal_and_is_gone_after_skip() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	assert_null(hud.highlight_button(), "camera goal has no button")
	s.report_camera_moved()
	hud.refresh()
	assert_eq(hud.highlight_button(), hud._cat_buttons["roads"], "road goal: the Roads category")
	hud.open_category("roads")
	assert_eq(hud.highlight_button().name, &"Tool_road", "flyout open: the road tool")
	hud.update_highlight(0.3)
	assert_ne(hud.highlight_button().self_modulate, Color.WHITE, "pulsing")
	_road_out(s)
	hud.refresh()  # goal 3: two tents
	var tent: BuildingDef = main.registry.get_building("tent")
	assert_eq(hud._open_cat, "roads")
	assert_eq(hud.highlight_button(), hud._cat_buttons[tent.category], "category closed: its tab pulses")
	hud.open_category(tent.category)
	assert_eq(hud.highlight_button(), hud.build_button("tent"), "category open: the Tent button pulses")
	var btn := hud.highlight_button()
	hud.update_highlight(0.3)
	assert_ne(btn.self_modulate, Color.WHITE)
	s.skip_tutorial()
	hud.refresh()
	assert_null(hud.highlight_button())
	assert_eq(btn.self_modulate, Color.WHITE, "pulse cleared")


func test_pan_and_zoom_send_the_camera_command() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var cam: CameraController = main.get_node("Camera")
	var tut := s.get_system(TutorialSystem) as TutorialSystem
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	cam._unhandled_input(down)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(30, 10)
	cam._unhandled_input(move)
	assert_eq(tut.current_goal().id, "camera_moved", "a pan alone is not enough")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	cam._unhandled_input(wheel)
	assert_eq(tut.current_goal().id, "road_to_hearth", "pan plus zoom completes goal 1")


func test_live_numbers() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var p := _panel(main)
	var tut := s.get_system(TutorialSystem) as TutorialSystem
	s.report_camera_moved()
	_road_out(s)
	assert_eq(tut.current_goal().id, "two_tents")
	p.refresh()
	assert_string_contains(_label_texts(p), "Built: 0/2")
	var o := Vector2i(-1, -1)
	for r in range(2, 12):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c: Vector2i = s.map.hearth_spot + Vector2i(dx, dy)
				if o.x < 0 and s.can_place("tent", c)["ok"]:
					o = c
	s.complete_site(s.buildings[s.place_building("tent", o)])
	p.refresh()
	assert_string_contains(_label_texts(p), "Built: 1/2")


func test_closing_card_after_finish_not_after_skip() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var p := _panel(main)
	assert_false(p.card.visible)
	s.skip_tutorial()
	assert_false(p.card.visible, "skipped: no card")
	s.events.emit("tutorial_finished", {"skipped": false})
	assert_true(p.card.visible)
	assert_false(p.visible, "goal panel hidden while the card is open")
	var old := get_window().size
	get_window().size = Vector2i(1280, 720)  # the headless window is tiny
	await wait_process_frames(3)
	var vp := Rect2(Vector2.ZERO, p.get_viewport().get_visible_rect().size)
	assert_true(vp.encloses(p.card.get_global_rect()), "card inside the viewport: %s" % p.card.get_global_rect())
	assert_almost_eq(p.card.get_global_rect().get_center().x, vp.get_center().x, 2.0, "centred")
	assert_almost_eq(p.card.get_global_rect().get_center().y, vp.get_center().y, 2.0, "centred")
	get_window().size = old
	var texts := _label_texts(p.card)
	assert_string_contains(texts, "Meeting Hall")
	assert_string_contains(texts, "15 citizens")
	assert_string_contains(texts, "30 gold")
	assert_string_contains(texts, "F1")
	(p.card.find_child("TutorialOk", true, false) as Button).pressed.emit()
	assert_false(p.card.visible)


func test_covers_hint_is_the_current_goals() -> void:
	var main: Node = await _game()
	var tut := main.settlement.get_system(TutorialSystem) as TutorialSystem
	assert_false(tut.covers_hint("first_blight"))
	var reg: DataRegistry = main.registry
	for g in reg.tutorial_goals_in_order():
		if g.covers_hints.size() > 0:
			tut._index = g.order - 1
			assert_true(tut.covers_hint(g.covers_hints[0]), g.id)
	tut.skip(main.settlement)
	assert_false(tut.covers_hint("first_blight"), "inactive")
