extends GutTest
## Ticket 115: the Workforce page (key Q). Model rows, grouping and counts; the priority and Pause buttons call the
## Settlement command; rows without jobs have no buttons; Q and Esc toggle it.

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_wf_%d" % OS.get_process_id()
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


func _key(hud: Hud, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	hud._unhandled_input(e)


func _row(m: HudModel, id: int) -> Dictionary:
	for g: Dictionary in m.workforce()["groups"]:
		for r: Dictionary in g["rows"]:
			if r["id"] == id:
				return r
	return {}


func test_model_groups_counts_and_notes() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	var site := s.place_building("tent", _free_spot(s, "tent", 8))
	assert_true(wc >= 0 and site >= 0)
	var wf := m.workforce()
	var groups: Array = wf["groups"]
	assert_eq(groups[0]["id"], "sites", "sites come first")
	assert_eq(groups[0]["rows"][0]["name"], "Tent (site)")
	var ids: Array = groups.map(func(g: Dictionary) -> String: return g["id"])
	assert_true(ids.find("resources") > 0, "buildings by category after the sites")
	assert_true(ids.find("housing") < ids.find("resources"), "build bar order")
	var n_idle := 0
	var n_work := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.is_idle():
			n_idle += 1
		elif c.job_kind == Citizen.JOB_WORK:
			n_work += 1
	assert_eq(wf["header"]["idle"], n_idle)
	assert_eq(wf["header"]["workers"], n_work)
	var row := _row(m, wc)
	var slots: int = s.buildings[wc].effective_worker_slots(s.registry)
	assert_eq(row["slots"], slots)
	assert_eq(row["count_text"], "%d/%d" % [row["filled"], slots])
	assert_eq(row["short"], slots - int(row["filled"]))
	assert_false(s.buildings[wc].connected, "no road was laid to it")
	assert_eq(row["note"], "no road")
	s.set_building_priority(wc, "paused")
	assert_eq(_row(m, wc)["note"], "paused", "paused rows keep their text")


func test_unconnected_row_says_no_road_and_skips_the_short_total() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	assert_true(wc >= 0)
	assert_false(s.buildings[wc].connected, "no road was laid to it")
	var row := _row(m, wc)
	assert_gt(int(row["short"]), 0, "the row is short of hands")
	assert_eq(row["note"], "no road")
	var wf := m.workforce()
	var others := 0
	for g: Dictionary in wf["groups"]:
		for r: Dictionary in g["rows"]:
			if r["id"] != wc:
				others += int(r["short"])
	assert_eq(int(wf["header"]["short"]), others, "an unconnected row adds nothing to the short total")
	var hud: Hud = main.get_node("Hud")
	hud.workforce_page.open()
	var node := hud.workforce_page.row_node(wc)
	var note := node.get_child(node.get_child_count() - 1) as Label
	assert_eq(note.text, "no road", "the page's short column says it")
	assert_eq(note.get_theme_color("font_color"), Hud.GOLD, "in the warning colour")


func test_connected_short_row_says_n_short() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var wc := s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	assert_true(wc >= 0)
	assert_true(s.buildings[wc].connected, "the road reaches it")
	for cid in s.citizens.keys():
		s.remove_citizen(cid)
	var row := _row(m, wc)
	assert_gt(int(row["short"]), 0, "nobody is left to take the jobs")
	assert_eq(row["note"], "%d short" % row["short"])
	var wf := m.workforce()
	var all := 0
	for g: Dictionary in wf["groups"]:
		for r: Dictionary in g["rows"]:
			all += int(r["short"])
	assert_eq(int(wf["header"]["short"]), all, "a connected short row counts")


func test_buttons_call_the_settlement_command() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 4))
	hud.workforce_page.open()
	var row := hud.workforce_page.row_node(wc)
	assert_not_null(row)
	(row.find_child("Prio_high", true, false) as Button).pressed.emit()
	assert_eq(s.buildings[wc].priority, "high")
	row = hud.workforce_page.row_node(wc)
	(row.find_child("Prio_low", true, false) as Button).pressed.emit()
	assert_eq(s.buildings[wc].priority, "low")
	row = hud.workforce_page.row_node(wc)
	(row.find_child("Pause", true, false) as Button).pressed.emit()
	assert_true(s.buildings[wc].paused)
	row = hud.workforce_page.row_node(wc)
	assert_eq((row.find_child("Pause", true, false) as Button).text, "Resume")
	(row.find_child("Pause", true, false) as Button).pressed.emit()
	assert_false(s.buildings[wc].paused)
	assert_eq(s.buildings[wc].priority, "low", "resume keeps the priority")


func test_job_less_rows_have_no_buttons() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var s: Settlement = main.settlement
	var tent := s.place_building_instant("tent", _free_spot(s, "tent", 4))
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 5, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
	var well := s.place_building_instant("park", Vector2i(h.x + 12, h.y - 4))
	var wc := s.place_building_instant("woodcutter", _free_spot(s, "woodcutter", 8))
	assert_true(tent >= 0 and well >= 0)
	assert_eq(_row(main.hud_model, tent), {}, "houses have no row")
	assert_false(_row(main.hud_model, well)["has_jobs"])
	hud.workforce_page.open()
	var row := hud.workforce_page.row_node(well)
	assert_not_null(row, "the row is there")
	assert_null(row.find_child("Prio_low", true, false))
	assert_null(row.find_child("Pause", true, false))
	assert_not_null(hud.workforce_page.row_node(wc).find_child("Pause", true, false))


func test_q_toggles_and_esc_closes() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	assert_false(hud.workforce_page.visible)
	_key(hud, KEY_Q)
	assert_true(hud.workforce_page.visible)
	_key(hud, KEY_Q)
	assert_false(hud.workforce_page.visible)
	_key(hud, KEY_Q)
	assert_true(hud.has_cancelable(), "Esc belongs to the page, not the menu")
	_key(hud, KEY_ESCAPE)
	assert_false(hud.workforce_page.visible)


func test_header_matches_rows_and_people_tooltip() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("woodcutter", Vector2i(h.x + 9, h.y + 1))
	s.hearth.inventory.add("food", 300.0)
	for i in 3 * 24:
		s.step_hours(1)
	var wf := m.workforce()
	var work := 0
	for g: Dictionary in wf["groups"]:
		for r: Dictionary in g["rows"]:
			if not r["site"]:
				work += int(r["work"])
	assert_gt(work, 0, "somebody works")
	assert_eq(wf["header"]["workers"], work, "header workers = filled worker slots over the rows")
	var rx := RegEx.create_from_string("(\\d+) idle")
	var hit := rx.search(m.people_text())
	assert_eq(wf["header"]["idle"], int(hit.get_string(1)) if hit != null else 0, "idle matches the people tooltip")
