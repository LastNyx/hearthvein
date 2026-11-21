extends GutTest
## Ticket 84: first-time hint cards (D59b, D68) and era cards (D70).

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_hint_%d" % OS.get_process_id()
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


func _game(tutorial: bool = false) -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(-1 if tutorial else 42, false, tutorial)
	await wait_process_frames(2)
	return main


func _cards(main: Node) -> HintCards:
	return (main.get_node("Hud") as Hud).hint_cards


func _halt(main: Node) -> void:
	main.settlement.events.emit("production_halted", {"id": 1, "why": "door_full"})


func _texts(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "Label", true, false):
		out += (c as Label).text + "\n"
	return out


func test_each_hint_fires_once_ever_survives_a_restart_and_not_when_off() -> void:
	var main: Node = await _game()
	var cards := _cards(main)
	assert_eq(cards.current_id(), "")
	_halt(main)
	assert_eq(cards.current_id(), "buffer_full")
	assert_true(cards.visible_card())
	assert_string_contains(_texts(cards), "Output buffer full")
	cards.close()
	assert_false(cards.visible_card())
	_halt(main)
	assert_eq(cards.current_id(), "", "once ever")
	# a restart reads the same settings file
	var main2: Node = await _game()
	_halt(main2)
	assert_eq(_cards(main2).current_id(), "", "seen hints survive a restart")
	# hints off: nothing shows, and the hint stays unseen
	var gs := GameSettings.new()
	gs.path = cfg
	gs.load_file()
	assert_true(gs.seen_hints.has("buffer_full"))
	gs.seen_hints = []
	gs.hints_enabled = false
	gs.save()
	var main3: Node = await _game()
	_halt(main3)
	assert_eq(_cards(main3).current_id(), "", "hints off")
	var cards3 := _cards(main3)
	assert_false((main3.settings as GameSettings).seen_hints.has("buffer_full"))
	(main3.settings as GameSettings).hints_enabled = true
	_halt(main3)
	assert_eq(cards3.current_id(), "buffer_full")


func test_one_at_a_time_queue_click_and_timeout_close() -> void:
	var main: Node = await _game()
	var cards := _cards(main)
	_halt(main)
	main.settlement.events.emit("darkness_started", {})
	assert_eq(cards.current_id(), "buffer_full")
	assert_eq(cards.queued_ids(), ["darkness"])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	cards.card_node().gui_input.emit(click)
	assert_eq(cards.current_id(), "darkness", "a click closes the card and the next one shows")
	cards.tick(19.0)
	assert_eq(cards.current_id(), "darkness")
	cards.tick(1.5)
	assert_eq(cards.current_id(), "", "closes after 20 s")


func test_more_button_asks_for_the_help_page() -> void:
	var main: Node = await _game()
	var cards := _cards(main)
	_halt(main)
	assert_true(cards.more_button().visible, "Main wires the help screen (ticket 85)")
	cards.close()
	var asked: Array[String] = []
	cards.help_page_requested.connect(func(p: String) -> void: asked.append(p))
	main.settlement.events.emit("darkness_started", {})
	assert_true(cards.more_button().visible)
	cards.more_button().pressed.emit()
	assert_eq(asked, ["dimming"])
	assert_eq(cards.current_id(), "")


func test_hints_without_an_event_are_checked_on_day_start() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var cards := _cards(main)
	s.gold = 5000.0
	s.events.emit("day_started", {"day": 1, "season": "spring", "year": 1})
	assert_eq(cards.current_id(), "region_buy")
	cards.close()
	var origin := Vector2i(-1, -1)
	for dx in range(-12, 12):
		for dy in range(-12, 12):
			var o := s.map.hearth_spot + Vector2i(dx, dy)
			if origin.x < 0 and s.can_place("market", o)["ok"]:
				origin = o
	assert_ne(s.place_building_instant("market", origin), -1)
	s.events.emit("day_started", {"day": 2, "season": "spring", "year": 1})
	assert_eq(cards.current_id(), "no_workers")
	cards.close()
	(s.citizens.values()[0] as Citizen).home_id = -1
	s.events.emit("day_started", {"day": 3, "season": "spring", "year": 1})
	assert_eq(cards.current_id(), "homeless")


func test_hint_covered_by_the_tutorial_goal_is_suppressed() -> void:
	var main: Node = await _game(true)
	var s: Settlement = main.settlement
	var cards := _cards(main)
	var tut := s.get_system(TutorialSystem) as TutorialSystem
	tut._index = 5  # goal 6, Lumen Tap: covers first_blight
	assert_true(tut.covers_hint("first_blight"))
	s.events.emit("blight_changed", {"tile": Vector2i(1, 1), "blighted": true})
	assert_eq(cards.current_id(), "")
	_halt(main)
	assert_eq(cards.current_id(), "buffer_full", "a hint the goal does not cover still shows")


func test_era_card_pauses_lists_the_eras_buildings_and_resumes() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var drv: SimDriver = main.driver
	drv.set_speed(2)
	s.era_current = "village"
	s.events.emit("era_changed", {"from": "camp", "to": "village"})
	var card := hud.era_card
	assert_true(card.is_open())
	assert_eq(drv.speed, 0)
	var text := _texts(card)
	assert_string_contains(text, "Village")
	for d in s.registry.buildings_of_era("village"):
		assert_string_contains(text, d.display_name)
	assert_string_contains(text, s.registry.get_era("village").new_pressure)
	var town := s.registry.get_era("town")
	assert_string_contains(text, "%d" % town.gate_pop)
	assert_string_contains(text, "%d" % town.gate_gold)
	assert_string_contains(text, s.registry.get_building(town.gate_landmark).display_name)
	card.close()
	assert_false(card.is_open())
	assert_eq(drv.speed, 2, "speed restored")


func test_hint_and_era_rows_are_in_data() -> void:
	var reg := DataRegistry.new()
	assert_eq(reg.load_all(), [] as Array[String])
	for id in ["dimming_forecast", "buffer_full", "no_workers", "first_blight", "upkeep_building", "darkness",
			"citizen_left", "homeless", "island_still", "great_dimming", "region_buy", "night_arrival_blocked"]:
		assert_true(reg.hints.has(id), id)
	for e in reg.eras_in_order():
		assert_ne(e.new_pressure, "", e.id)
