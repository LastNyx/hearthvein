extends GutTest
## Ticket 114: the Resources page (key E). Rows from the ledger, row selection, the chart series from the history,
## E / Esc / a top-bar click open and close it, the made-by hover, and the two new ledger hooks (Clear yields, gold
## paid for a region).

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_rp_%d" % OS.get_process_id()
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


func _key(hud: Hud, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	hud._unhandled_input(e)


func _click(c: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	c.gui_input.emit(e)


func _ledger(s: Settlement) -> ResourceLedgerSystem:
	return s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem


func _row(m: HudModel, id: String) -> Dictionary:
	for r in m.resource_rows():
		if r["id"] == id:
			return r
	return {}


# Rows come from a ledger fixture: one per top-bar good, made and used are yesterday's numbers.
func test_rows_come_from_the_ledger() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var ledger := _ledger(s)
	ledger.made_yesterday = {"wood": 48.0, "lumen_cells": 2.0}
	ledger.used_yesterday = {"wood": 44.0}
	ledger.made_by_yesterday = {"wood": {"woodcutter": 30.0, "clear_forest": 12.0, "forester": 6.0}}
	var rows := m.resource_rows()
	assert_eq(rows.size(), HudModel.RESOURCES.size())
	var w := _row(m, "wood")
	assert_eq([w["name"], w["made"], w["used"]], ["Wood", 48, 44])
	assert_eq(w["stock"], floori(s.totals().get("wood", 0.0)))
	assert_eq(_row(m, "cells")["made"], 2, "the cells row reads the lumen_cells ledger")
	assert_eq(_row(m, "stone")["made"], 0)
	var hud: Hud = main.get_node("Hud")
	hud.resources_page.open()
	var row := hud.resources_page.row_node("wood")
	assert_not_null(row)
	assert_eq((row.find_child("Made", true, false) as Label).text, "48")


# Clicking a row selects it; the chart follows.
func test_clicking_a_row_selects_it() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	hud.resources_page.open()
	assert_eq(hud.resources_page.selected, "food")
	_click(hud.resources_page.row_node("stone"))
	assert_eq(hud.resources_page.selected, "stone")
	assert_not_null(hud.resources_page.row_node("stone"), "rows are rebuilt with the new selection")


# The chart series is the history plus today's stock, today at the right edge.
func test_chart_points_come_from_the_history() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var ledger := _ledger(s)
	ledger._history["wood"] = [10.0, 20.0, 40.0]
	s.hearth.inventory.add("wood", 30.0)
	var m: HudModel = main.hud_model
	var series := m.resource_history("wood")
	assert_eq(series.size(), 4)
	assert_eq(series.slice(0, 3), [10.0, 20.0, 40.0])
	assert_eq(series[3], float(floori(s.totals()["wood"])), "today's stock last")
	var plot := Rect2(0, 0, 300, 100)
	var vals: Array[float] = [0.0, 50.0, 100.0]
	assert_eq(ResourcesPage.Chart.nice_max(88.0), 100.0)
	var pts := ResourcesPage.Chart.points_for(vals, plot, 100.0)
	assert_eq([pts[0], pts[1], pts[2]], [Vector2(0, 100), Vector2(150, 50), Vector2(300, 0)])
	hud.resources_page.select("wood")
	hud.resources_page.open()
	assert_eq(hud.resources_page.chart().values.size(), 4)
	assert_eq(hud.resources_page.chart().points().size(), 4)
	var long: Array = []
	for i in 70:
		long.append(1.0)
	ledger._history["wood"] = long
	assert_eq(m.resource_history("wood").size(), 60, "at most 60 days")


# E toggles, Esc closes (and belongs to the page, not the menu), a top-bar click opens with that good selected.
func test_e_esc_and_top_bar_click() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	assert_false(hud.resources_page.visible)
	_key(hud, KEY_E)
	assert_true(hud.resources_page.visible)
	_key(hud, KEY_E)
	assert_false(hud.resources_page.visible)
	_key(hud, KEY_E)
	assert_true(hud.has_cancelable())
	_key(hud, KEY_ESCAPE)
	assert_false(hud.resources_page.visible)
	var box := hud._res_icons["stone"].get_parent() as Control
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	box.gui_input.emit(e)
	assert_true(hud.resources_page.visible)
	assert_eq(hud.resources_page.selected, "stone")
	main.settlement.step_hours(2)
	assert_true(hud.resources_page.visible, "the sim keeps running with the page open")


# Hovering a made number lists the made-by breakdown, biggest first, with building counts and the Clear tool.
func test_hovering_made_shows_the_breakdown() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
	assert_true(s.place_building_instant("woodcutter", Vector2i(h.x + 4, h.y - 3)) >= 0)
	assert_true(s.place_building_instant("woodcutter", Vector2i(h.x + 8, h.y - 3)) >= 0)
	_ledger(s).made_yesterday = {"wood": 48.0}
	_ledger(s).made_by_yesterday = {"wood": {"woodcutter": 36.0, "clear_forest": 12.0}}
	hud.resources_page.open()
	assert_eq(hud.resources_page.breakdown_lines(), [], "nothing before the hover")
	(hud.resources_page.row_node("wood").find_child("Made", true, false) as Label).mouse_entered.emit()
	assert_eq(hud.resources_page.breakdown_lines(), [["Woodcutter x2", "36"], ["Clearing forest", "12"]])
	(hud.resources_page.row_node("wood").find_child("Made", true, false) as Label).mouse_exited.emit()
	assert_eq(hud.resources_page.breakdown_lines(), [])


# Ledger gap 1: a Clear-tool yield is made wood, attributed to the clearing.
func test_a_cleared_tile_is_made_by_clearing() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	s.spirit_override = 50.0
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		s.place_road(Vector2i(x, h.y))
	var t := Vector2i(h.x + 6, h.y + 1)
	s.set_terrain(t, "forest")
	assert_true(s.mark_clear(t))
	while s.clock.hour() != 6:
		s.step_hours(1)
	for i in 3 * 24:
		if not s.is_clear_marked(t):
			break
		s.step_hours(1)
	assert_false(s.is_clear_marked(t), "cleared")
	assert_almost_eq(float(_ledger(s).today("wood")["made_by"].get("clear_forest", 0.0)), 4.0, 0.001)


# Ledger gap 2: gold paid for a region is used gold. (There is no per-building gold upkeep in the game.)
func test_buying_a_region_is_used_gold() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var price := s.next_region_price()
	s.gold = float(price) + 100.0
	var region := -1
	for r in MapState.REGION_COUNT:
		if s.can_buy_region(r)["ok"]:
			region = r
			break
	assert_true(region >= 0)
	var before := float(_ledger(s).today("gold")["used"])
	assert_true(s.buy_region(region))
	assert_almost_eq(float(_ledger(s).today("gold")["used"]), before + float(price), 0.001)
