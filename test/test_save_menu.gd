extends GutTest
## Ticket 19d: menu view-model over SaveSlots, and swapping the running Settlement for a loaded one.

const SEED := 42

var reg: DataRegistry
var dir: String
var slots: SaveSlots
var s: Settlement
var m: SaveMenuModel


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_menu_%d" % OS.get_process_id()
	_wipe()
	DirAccess.make_dir_recursive_absolute(dir)
	slots = SaveSlots.new(dir)
	s = Settlement.new_game(SEED, reg)
	m = SaveMenuModel.new(slots, reg, func() -> Settlement: return s)


func after_each() -> void:
	get_tree().paused = false
	_wipe()


func _wipe() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(dir)


func _row(kind: String, slot: int) -> Dictionary:
	for r in m.rows():
		if r["kind"] == kind and r["slot"] == slot:
			return r
	return {}


func test_rows_list_eight_manual_slots_and_existing_autosaves_with_metadata() -> void:
	var rows := m.rows()
	assert_eq(rows.size(), 8, "fresh dir: 8 empty manual slots, no autosave rows")
	assert_true(_row("manual", 3)["empty"])
	assert_eq(_row("manual", 3)["detail"], "Empty")
	assert_false(_row("manual", 3)["can_load"])
	assert_true(_row("manual", 3)["can_save"])
	s.step_days(2)
	slots.save_slot(2, s)
	slots.autosave(s)
	rows = m.rows()
	assert_eq(rows.size(), 9)
	assert_eq(rows[0]["kind"], "auto", "autosaves first")
	assert_eq(rows[0]["title"], "Autosave 1")
	assert_false(rows[0]["can_save"], "autosaves are not written by hand")
	var r := _row("manual", 2)
	assert_false(r["empty"])
	assert_eq(r["title"], "Slot 3")
	assert_true(r["can_load"] and r["can_delete"])
	assert_string_contains(r["detail"], s.clock.label())
	assert_string_contains(r["detail"], "pop %d" % s.citizens.size())
	assert_string_contains(r["detail"], reg.get_era(s.era_id()).display_name)
	assert_string_contains(r["detail"], "saved ")


func test_save_load_and_delete_go_through_save_slots() -> void:
	s.step_days(3)
	assert_eq(m.save_to(4), OK)
	assert_true(FileAccess.file_exists(dir.path_join("slot_4.dat")))
	assert_eq(m.status, "Saved to Slot 5")
	var back := m.load_row("manual", 4)
	assert_not_null(back)
	assert_eq(back.clock.total_hours, s.clock.total_hours)
	assert_null(m.load_row("manual", 5), "empty slot does not load")
	assert_push_error_count(1)
	assert_ne(m.status, "Loaded")
	assert_eq(m.delete_slot(4), OK)
	assert_true(_row("manual", 4)["empty"])
	assert_eq(m.delete_slot(4), ERR_FILE_NOT_FOUND)


func test_overwrite_and_delete_ask_before_acting() -> void:
	assert_true(m.request_save(1), "empty slot saves at once")
	assert_eq(_row("manual", 1)["confirm"], "")
	s.step_days(2)
	assert_false(m.request_save(1), "filled slot asks")
	assert_eq(_row("manual", 1)["confirm"], "overwrite")
	assert_eq(_row("manual", 0)["confirm"], "")
	m.cancel()
	assert_eq(_row("manual", 1)["confirm"], "")
	assert_eq(slots.load_slot(1, reg).clock.total_hours, 0, "cancel leaves the old save")
	m.request_save(1)
	m.confirm()
	assert_eq(slots.load_slot(1, reg).clock.total_hours, s.clock.total_hours, "yes overwrites")
	assert_eq(_row("manual", 1)["confirm"], "")
	m.request_delete(1)
	assert_eq(_row("manual", 1)["confirm"], "delete")
	assert_false(_row("manual", 1)["empty"], "nothing deleted yet")
	m.cancel()
	assert_false(_row("manual", 1)["empty"])
	m.request_delete(1)
	m.confirm()
	assert_true(_row("manual", 1)["empty"], "yes deletes")


func test_saved_text_is_short() -> void:
	var t := SaveMenuModel.saved_text(1763073300)
	assert_true(t.length() <= 12, t)
	assert_eq(SaveMenuModel.saved_text(0), "unknown")


func test_continue_loads_the_latest_autosave() -> void:
	assert_false(m.has_continue())
	assert_null(m.continue_latest())
	assert_eq(m.status, "No autosave yet")
	s.step_days(1)
	slots.autosave(s)
	s.step_days(5)
	slots.autosave(s)
	assert_true(m.has_continue())
	var back := m.continue_latest()
	assert_eq(back.clock.total_hours, s.clock.total_hours)


func _main(save_dir: String) -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	main.saves_dir = save_dir
	add_child_autofree(main)
	main.start_new_game()
	return main


func test_swap_rebinds_hud_and_notifications_to_the_new_settlement() -> void:
	var main := _main(dir)
	await wait_process_frames(2)
	var old: Settlement = main.settlement
	var old_bus := old.events
	# a distinct settlement: saved after some play, with a different gold value
	var other := Settlement.new_game(7, reg)
	other.step_days(3)
	other.gold = 123.0
	assert_eq(slots.save_slot(0, other), OK)
	var loaded := slots.load_slot(0, reg)
	var old_hud: Node = main.hud
	var old_map: Node = main.map_view
	main.swap_settlement(loaded)
	await wait_process_frames(2)
	assert_same(main.settlement, loaded)
	assert_same(main.hud_model.s, loaded)
	assert_same(main.hud_model.notifications.s, loaded)
	assert_same(main.driver.settlement, loaded)
	assert_same(main.placement.settlement, loaded)
	assert_same(main.overlay.settlement, loaded)
	assert_same(main.walkers.settlement, loaded)
	assert_same(main.map_view.map, loaded.map)
	assert_same(main.hud.model, main.hud_model)
	assert_not_same(main.hud, old_hud)
	assert_true(not is_instance_valid(old_hud) or old_hud.is_queued_for_deletion())
	assert_true(not is_instance_valid(old_map) or old_map.is_queued_for_deletion())
	assert_eq(main.get_children().filter(func(n: Node) -> bool: return n is Hud and not n.is_queued_for_deletion()).size(), 1)
	assert_eq(main.get_children().filter(func(n: Node) -> bool: return n is MapView and not n.is_queued_for_deletion()).size(), 1)
	var gold := 0
	for r in main.hud_model.resources():
		if r["id"] == "gold":
			gold = r["value"]
	assert_eq(gold, 123, "HUD model reads the new settlement's gold")
	assert_string_contains(main.hud_model.era_panel()["title"], reg.get_era(loaded.era_id()).display_name)
	# the map renders the loaded settlement's buildings
	for id in loaded.buildings:
		assert_true(main.placement._nodes.has(id), "building %d drawn" % id)
	# events: the new bus reaches the notification layer, the old one does not
	var before: int = main.hud_model.notifications.items.size()
	old_bus.emit("dimming_forecast", {"start_day": 99, "length": 4})
	assert_eq(main.hud_model.notifications.items.size(), before, "old bus is silent")
	loaded.events.emit("dimming_forecast", {"start_day": 99, "length": 4})
	assert_eq(main.hud_model.notifications.items.size(), before + 1, "new bus reaches the notifications")
	assert_eq(main.hud_model.notifications.items.back()["kind"], "dimming")
	# autosave follows the new settlement
	assert_eq(slots.list().size(), 1)
	loaded.events.emit("season_started", {})
	assert_true(main.slots.latest_auto() >= 0, "autosave attached to the new bus")
	old_bus.emit("season_started", {})
	assert_eq(main.slots.list().filter(func(e: Dictionary) -> bool: return e["kind"] == "auto").size(), 1)


func test_menu_pauses_the_tree_and_load_swaps_through_main() -> void:
	var main := _main(dir)
	await wait_process_frames(2)
	var menu: SaveMenu = main.menu
	menu.open()
	assert_true(menu.is_open())
	assert_true(get_tree().paused, "sim is paused while the menu is open")
	var other := Settlement.new_game(9, reg)
	other.step_days(2)
	slots.save_slot(1, other)
	menu.refresh()
	menu.load_requested.emit(main.menu_model.load_row("manual", 1))
	await wait_process_frames(2)
	assert_false(menu.is_open())
	assert_false(get_tree().paused)
	assert_eq(main.settlement.clock.total_hours, other.clock.total_hours)
	assert_same(main.hud_model.s, main.settlement)


# ---------------------------------------------------------------- ticket 80: the pause menu

func _press(menu: SaveMenu, id: String) -> void:
	var b := menu.find_child(id, true, false) as Button
	assert_not_null(b, id)
	assert_true(b.is_visible_in_tree(), id + " visible")
	b.pressed.emit()


func _slot_buttons(menu: SaveMenu, text: String) -> Array:
	return menu.find_children("*", "Button", true, false).filter(
			func(b: Button) -> bool: return b.text == text and b.name.begins_with("@"))


func test_rows_in_save_mode_skip_autosaves() -> void:
	slots.autosave(s)
	assert_eq(m.rows("save").size(), 8)
	assert_eq(m.rows("load").size(), 9)
	assert_eq(m.rows("load")[0]["kind"], "auto")
	assert_eq(m.rows("save")[0]["kind"], "manual")


func test_pause_menu_buttons_and_slot_lists() -> void:
	var main := _main(dir)
	main.settings_path = dir + ".cfg"
	await wait_process_frames(2)
	var menu: SaveMenu = main.menu
	main.slots.autosave(main.settlement)
	menu.open()
	for id in ["Resume", "Save", "Load", "Settings", "Milestones", "MainMenu", "Quit"]:
		assert_true((menu.find_child(id, true, false) as Button).is_visible_in_tree(), id)
	assert_false((menu.find_child("Help", true, false) as Button).visible, "Help hidden until ticket 85 connects it")
	# Save: manual slots only, no Load buttons
	_press(menu, "Save")
	assert_eq(_slot_buttons(menu, "Save").size(), 8)
	assert_eq(_slot_buttons(menu, "Load").size(), 0)
	_slot_buttons(menu, "Save")[2].pressed.emit()
	assert_true(FileAccess.file_exists(dir.path_join("slot_2.dat")), "Save writes the slot")
	# Back returns to the button column; Load: autosave + 8 slots
	menu.hide_slots()
	_press(menu, "Load")
	assert_eq(_slot_buttons(menu, "Load").size(), 9)
	assert_eq(_slot_buttons(menu, "Save").size(), 0)
	menu.hide_slots()
	_press(menu, "Milestones")
	assert_true(menu.find_child("Count", true, false).is_visible_in_tree())
	menu.hide_milestones()
	_press(menu, "Settings")
	assert_true(menu.settings_panel.is_visible_in_tree())
	menu.hide_settings()
	_press(menu, "Resume")
	assert_false(menu.is_open())
	assert_false(get_tree().paused)


func test_help_button_shows_once_connected_and_emits() -> void:
	var main := _main(dir)
	await wait_process_frames(2)
	var got := [0]
	main.menu.help_requested.connect(func() -> void: got[0] += 1)
	main.menu.open()
	_press(main.menu, "Help")
	assert_eq(got[0], 1)


func test_main_menu_button_autosaves_and_returns_to_title() -> void:
	var main := _main(dir)
	await wait_process_frames(2)
	main.menu.open()
	_press(main.menu, "MainMenu")
	await wait_process_frames(2)
	assert_eq(main.state, main.State.TITLE)
	assert_false(main.menu.is_open())
	assert_false(get_tree().paused)
	assert_eq(SaveSlots.new(dir).latest_auto(), 0, "an autosave was written")


func test_quit_button_autosaves_then_quits() -> void:
	var main := _main(dir)
	await wait_process_frames(2)
	var quit := [0]
	main.quit_fn = func() -> void: quit[0] += 1
	main.menu.open()
	_press(main.menu, "Quit")
	assert_eq(quit[0], 1)
	assert_eq(SaveSlots.new(dir).latest_auto(), 0, "an autosave was written")


func test_title_load_view_lists_autosaves_and_back_closes() -> void:
	var main := _main(dir)
	await wait_process_frames(2)
	main.return_to_title()  # autosaves
	await wait_process_frames(2)
	main.menu.open_view("load")
	assert_true(main.menu.is_open())
	assert_false(get_tree().paused)
	assert_eq(_slot_buttons(main.menu, "Load").size(), 9, "the autosave and 8 slots")
	main.menu.hide_slots()
	assert_false(main.menu.is_open())
