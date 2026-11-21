extends GutTest
## Ticket 129: the 5x3 command grid at the bottom-right replaces the category bar. Top-level categories and actions,
## category panes with positional keys and More/Back, locked and unaffordable cells, and modal key routing.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var m: HudModel


func before_each() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	s = Settlement.new_game(SEED, reg)
	m = HudModel.new(s)


func _hud(era: String = "camp") -> Hud:
	var tmp := OS.get_environment("TMPDIR")
	var cfg := (tmp if tmp != "" else "/tmp").path_join("hearthvein_cmd_grid_%d.cfg" % OS.get_process_id())
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.settings_path = cfg
	main.saves_dir = cfg + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	var hud: Hud = main.get_node("Hud")
	hud.model.s.era_override = era
	await wait_process_frames(1)
	return hud


func _cell(cells: Array[Dictionary], id: String) -> Dictionary:
	for c in cells:
		if c["id"] == id:
			return c
	return {}


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _cell_text(b: Button, node: String) -> String:
	return (b.find_child(node, true, false) as Label).text


## Criterion 1: 15 top-level cells with their keys; Gold buildings under Civic, Sky under Logistics; an empty cell when
## a category has nothing unlocked.
func test_top_level_grid_cells_keys_and_groupings() -> void:
	var top := m.grid("")
	assert_eq(top.size(), 15)
	assert_eq(top.map(func(c: Dictionary) -> String: return c["id"]),
			["roads", "housing", "food", "water", "lumen", "logistics", "resources", "refining",
			"civic", "landmark", "demolish", "upgrade", "clear", "plant", "region"])
	assert_eq(top.map(func(c: Dictionary) -> String: return c["key"]),
			["R", "N", "F", "W", "I", "K", "S", "D", "A", "O", "X", "U", "Z", "Y", "M"])
	assert_eq(str(_cell(m.grid("civic"), "market")["id"]), "market", "the Gold market sits under Civic")
	s.era_override = "ascendant"
	assert_eq(str(_cell(m.grid("logistics"), "sky_lift")["id"]), "sky_lift", "the Sky Lift sits under Logistics")
	s.era_override = "camp"
	assert_eq(str(_cell(m.grid(""), "water")["state"]), "empty", "nothing water is unlocked in Camp")
	# the same cells the screen draws
	var hud := await _hud()
	assert_eq(hud._cmd_cells.size(), 15)
	assert_eq(_cell_text(hud._cmd_cells[0], "CellName"), "Roads")
	assert_eq(_cell_text(hud._cmd_cells[0], "CellKey"), "R")
	assert_eq(str(hud._cell_button("water").get_meta("cell_state")), "empty")


## Criterion 2: a pane's cells, its positional keys, More on the last cell past 14 entries, and Back on the last page.
func test_pane_cells_positional_keys_more_paging_and_back() -> void:
	var hud := await _hud()
	for i in 15:  # push the Resources pane past one page
		var d := BuildingDef.new()
		d.id = "test_cmd_grid_%02d" % i
		d.display_name = "Test %d" % i
		d.era = "camp"
		d.category = "resources"
		d.size = Vector2i(1, 1)
		hud.model.s.registry.buildings[d.id] = d
	hud.open_category("resources")
	await wait_process_frames(2)
	assert_eq(hud._cmd_cells.size(), 15)
	assert_eq(_cell_text(hud._cmd_cells[0], "CellKey"), "Q")
	assert_eq(_cell_text(hud._cmd_cells[4], "CellKey"), "T")
	assert_eq(_cell_text(hud._cmd_cells[5], "CellKey"), "A")
	assert_eq(_cell_text(hud._cmd_cells[13], "CellKey"), "V")
	assert_eq(_cell_text(hud._cmd_cells[14], "CellName"), "More")
	assert_eq(_cell_text(hud._cmd_cells[14], "CellKey"), "B")
	var page2 := hud.model.grid("resources:2")
	assert_eq(str(page2[0]["key"]), "Q", "page two starts at the first positional key again")
	assert_eq(str(page2[14]["id"]), "back")
	assert_eq(str(page2[14]["key"]), "Esc")
	hud._activate_cell(14)  # More
	await wait_process_frames(2)
	assert_eq(hud._grid_page, "resources:2")
	assert_eq(_cell_text(hud._cmd_cells[14], "CellName"), "Back")
	assert_eq(_cell_text(hud._cmd_cells[14], "CellKey"), "Esc")
	hud._activate_cell(14)  # Back
	await wait_process_frames(2)
	assert_eq(hud._grid_page, "", "Back returns to the top level")


## Criterion 3: a locked cell carries the unlock reason and a lock glyph; an unaffordable cell carries its short good.
func test_locked_and_unaffordable_states_with_reasons() -> void:
	var hud := await _hud()
	hud.model.s.hearth.inventory.remove("wood", 1000.0)  # a Tent costs 5 Wood
	hud.open_category("housing")
	await wait_process_frames(2)
	var tent := hud.build_button("tent")
	assert_eq(str(tent.get_meta("cell_state")), "unaffordable")
	assert_string_contains(tent.tooltip_text, "Wood")
	var cost := tent.find_child("CellCost", true, false) as Label
	assert_not_null(cost, "the short cost is drawn in the cell")
	assert_eq(cost.text, "5")
	assert_eq(cost.get_theme_color("font_color"), Hud.RED, "the short cost is red")
	var cottage := hud.build_button("cottage")
	assert_eq(str(cottage.get_meta("cell_state")), "locked")
	assert_not_null(cottage.find_child("Lock", true, false), "a locked cell draws the lock glyph")
	assert_string_contains(cottage.tooltip_text, "Village")
	var pane := hud.model.grid("housing")
	assert_eq(str(_cell(pane, "tent")["state"]), "unaffordable")
	assert_eq(str(_cell(pane, "tent")["reason"]), "Not enough Wood")
	assert_eq(str(_cell(pane, "cottage")["state"]), "locked")
	assert_eq(str(_cell(pane, "cottage")["reason"]), "Needs Village era")


## Criterion 4: with a pane open its positional letters pick cells (E picks a cell, not the Resources page); at the top
## level E opens Resources and Z/Y/X/U/M route to their actions; R picks the road tool and opens Roads.
func test_key_routing_is_modal_and_top_level_actions() -> void:
	var hud := await _hud("town")
	var build: BuildController = hud.get_node("../BuildController")
	hud._unhandled_input(_key(KEY_E))
	assert_true(hud.resources_page.visible, "top level: E opens the Resources page")
	hud.resources_page.close()
	hud._unhandled_input(_key(KEY_S))
	assert_eq(hud._grid_page, "resources", "top level: S opens the Resources pane")
	hud._unhandled_input(_key(KEY_E))
	assert_false(hud.resources_page.visible, "pane open: E picks a cell, it does not open the page")
	assert_eq(build.mode, BuildController.Mode.BUILD)
	assert_eq(build.def_id, "quarry", "the third Resources cell")
	hud._unhandled_input(_key(KEY_ESCAPE))
	assert_eq(hud._grid_page, "", "Esc goes back to the top level")
	hud._unhandled_input(_key(KEY_Z))
	assert_eq(build.mode, BuildController.Mode.CLEAR, "Z is Clear")
	hud._unhandled_input(_key(KEY_Y))
	assert_eq(build.mode, BuildController.Mode.PLANT, "Y is Plant")
	hud._unhandled_input(_key(KEY_X))
	assert_eq(build.mode, BuildController.Mode.DEMOLISH, "X is Demolish")
	hud._unhandled_input(_key(KEY_U))
	assert_eq(build.mode, BuildController.Mode.UPGRADE, "U is Upgrade")
	hud._unhandled_input(_key(KEY_M))
	assert_true(hud._region_map.visible, "M opens the region map")
	hud._unhandled_input(_key(KEY_R))
	assert_eq(build.mode, BuildController.Mode.ROAD, "R picks the road tool")
	assert_eq(hud._grid_page, "roads", "and opens the Roads pane")
