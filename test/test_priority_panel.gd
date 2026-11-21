extends GutTest
## Ticket 104 and 103: the selected-building panel on the real Hud. Build priority on a site, work priority on a building
## with jobs, no priority or Pause buttons on a finished house; the people tooltip of the top bar.

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_prio_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	DirAccess.remove_absolute(cfg)
	DirAccess.remove_absolute(dir)


func _game() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42)
	await wait_process_frames(2)
	return main


func _free_spot(s: Settlement, id: String, from: int) -> Vector2i:
	var h := s.map.hearth_spot
	for x in range(h.x + from, h.x + 30):
		for y in range(h.y - 8, h.y + 8):
			if s.can_place(id, Vector2i(x, y))["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_priority_buttons_follow_site_and_jobs() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var site := s.place_building("tent", _free_spot(s, "tent", 4))
	assert_true(site >= 0)
	m.select(site)
	hud.refresh()
	assert_true(hud._prio_row.visible, "a site keeps its buttons")
	assert_eq(hud._sel_prio_title.text, "Priority")
	assert_eq(hud._sel_prio_title.tooltip_text, "Build priority")
	s.complete_site(s.buildings[site])
	hud.refresh()
	assert_false(hud._prio_row.visible, "a finished Tent has no job")
	assert_false(hud._sel_prio_title.visible)
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	assert_true(wc >= 0)
	m.select(wc)
	hud.refresh()
	assert_true(hud._prio_row.visible)
	assert_eq(hud._sel_prio_title.tooltip_text, "Work priority. High: staffed before Normal buildings of every kind")


func test_top_bar_people_tooltip_and_halt_advice_show() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	hud.refresh()
	assert_eq(hud._pop_box.tooltip_text, m.people_text())
	assert_string_contains(hud._pop_box.tooltip_text, "8 people: ")
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	s.buildings[wc].halt = "door_full"
	m.select(wc)
	hud.refresh()
	assert_eq(hud._sel_halt.text, "Output full: no hauler has picked it up")
	assert_string_contains(hud._sel_halt.tooltip_text, "Output full: no hauler has picked it up\n", "the advice rides on the tooltip")


## Ticket 128: the priority and Pause buttons of the fixed selection panel still steer the selected building.
func test_priority_and_pause_buttons_still_work() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	assert_true(wc >= 0)
	m.select(wc)
	hud.refresh()
	(hud._prio_buttons["high"] as Button).pressed.emit()
	assert_eq(m.selection()["priority"], "high")
	(hud._prio_buttons["paused"] as Button).pressed.emit()
	assert_true(m.selection()["paused"])
	(hud._prio_buttons["low"] as Button).pressed.emit()
	assert_false(m.selection()["paused"], "picking a priority unpauses")
	assert_eq(m.selection()["priority"], "low")


## Ticket 128: the notices stack above the fixed bottom-centre panel and overlap neither it, the minimap nor the grid
## at 1280x720.
func test_notices_anchor_above_the_panel_clear_of_map_and_grid() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var old := get_window().size
	get_window().size = Vector2i(1280, 720)
	await wait_process_frames(3)
	assert_eq(hud.get_viewport().get_visible_rect().size, Vector2(1280, 720))
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	assert_true(wc >= 0)
	m.select(wc)
	s.events.emit("production_halted", {"id": wc, "why": "door_full"})
	hud.refresh()
	await wait_process_frames(3)
	var notes := hud._notes_box.get_global_rect()
	var panel := hud._sel_panel.get_global_rect()
	var mini := hud.minimap.get_global_rect()
	var grid := hud._cmd_panel.get_global_rect()
	assert_true(notes.size.y > 0.0, "the notice is drawn")
	assert_true(notes.end.y <= panel.position.y + 0.5, "notices sit above the panel: %s vs %s" % [notes, panel])
	assert_false(notes.intersects(panel), "notices clear of the panel")
	assert_false(notes.intersects(mini), "notices clear of the minimap")
	assert_false(notes.intersects(grid), "notices clear of the grid")
	assert_false(panel.intersects(mini), "the panel clears the minimap")
	assert_false(panel.intersects(grid), "the panel clears the grid")
	m.clear_selection()
	hud.refresh()
	await wait_process_frames(2)
	assert_true(hud._town_panel.visible, "nothing selected shows the town summary")
	assert_false(hud._sel_content.visible)
	assert_eq(hud._town_name.text, "Hearthvein")
	assert_eq(hud._town_people.text, "8")
	get_window().size = old
