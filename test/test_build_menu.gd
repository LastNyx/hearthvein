extends GutTest
## Tickets 116 and 117: the build menu is a row of cards (sprite, name, cost icons with numbers; red when something is
## short, greyed with a lock and the unlock reason when the era is not reached) and hovering a card opens the detail panel.

var cfg: String


func before_each() -> void:
	var tmp := OS.get_environment("TMPDIR")
	cfg = (tmp if tmp != "" else "/tmp").path_join("hearthvein_build_menu_%d.cfg" % OS.get_process_id())


func after_each() -> void:
	DirAccess.remove_absolute(cfg)


func _hud(era: String = "town") -> Hud:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.settings_path = cfg
	main.saves_dir = cfg + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42)
	await wait_process_frames(2)
	var s: Settlement = main.settlement
	s.era_override = era
	s.gold = 0.0
	s.hearth.inventory.add("wood", 100.0)
	s.hearth.inventory.add("stone", 100.0)
	return main.get_node("Hud")


func _entry(hud: Hud, cat_id: String, id: String) -> Dictionary:
	for cat in hud.model.build_bar():
		if cat["id"] == cat_id:
			for e: Dictionary in cat["entries"]:
				if e["id"] == id:
					return e
	return {}


func _cost(e: Dictionary, good: String) -> Dictionary:
	for c: Dictionary in e["costs"]:
		if c["good"] == good:
			return c
	return {}


func test_model_marks_affordable_short_and_locked_entries() -> void:
	var hud := await _hud()
	var saw := _entry(hud, "refining", "sawmill")
	assert_false(saw["locked"])
	assert_false(saw["short"], "100 wood and 100 stone pay a Sawmill")
	assert_eq(_cost(saw, "wood")["need"], 14)
	assert_eq(_cost(saw, "stone")["need"], 21)
	assert_true(int(_cost(saw, "wood")["have"]) >= 100)
	var ref := _entry(hud, "refining", "refinery")
	assert_true(ref["short"], "no gold, no planks")
	assert_true(_cost(ref, "gold")["short"])
	assert_false(_cost(ref, "wood")["short"])
	var tool := _entry(hud, "refining", "toolsmith")
	assert_true(tool["locked"], "a City building in the Town era is shown locked")
	assert_eq(tool["unlock"], "Needs City era")
	assert_false(tool["enabled"])


func test_cells_show_state_name_cost_and_lock() -> void:
	var hud := await _hud()
	hud.open_category("refining")
	await wait_process_frames(2)
	var saw: Button = hud.build_button("sawmill")
	var ref: Button = hud.build_button("refinery")
	var tool: Button = hud.build_button("toolsmith")
	assert_eq(saw.get_meta("cell_state"), "ok")
	assert_eq(ref.get_meta("cell_state"), "unaffordable")
	assert_eq(tool.get_meta("cell_state"), "locked")
	assert_eq(saw.get_meta("def_id"), "sawmill", "def_id meta stays for the tutorial and hint cards")
	assert_eq((saw.find_child("CellName", true, false) as Label).text, "Sawmill")
	assert_null(saw.find_child("CellCost", true, false), "an affordable cell shows no cost")
	var short := ref.find_child("CellCost", true, false) as Label
	assert_not_null(short, "a short cell shows its short cost")
	assert_eq(short.get_theme_color("font_color"), Hud.RED, "the short number is red")
	assert_not_null(tool.find_child("Lock", true, false))
	assert_eq(tool.tooltip_text, "Needs City era")
	assert_null(saw.find_child("Lock", true, false))


## The top-level grid keeps its category names and a press opens and closes the pane.
func test_category_cells_keep_names_and_open_close_the_pane() -> void:
	var hud := await _hud("ascendant")
	hud.refresh()  # the era changed after the first build of the grid
	for cell in hud.model.grid(""):
		if str(cell["id"]) == "" or not HudModel.is_grid_category(str(cell["id"])) or str(cell["state"]) == "empty":
			continue  # an empty category is a blank dim cell
		var b := hud._cell_button(str(cell["id"]))
		assert_eq((b.find_child("CellName", true, false) as Label).text, cell["label"], "%s keeps its name" % cell["id"])
	hud._cell_button("housing").pressed.emit()
	assert_eq(hud._grid_page, "housing", "a press opens its category")
	hud._cell_button("back").pressed.emit()
	assert_eq(hud._grid_page, "", "Back closes it")


func test_road_tools_are_cells_and_the_crowded_panes_fit_the_grid() -> void:
	var hud := await _hud("ascendant")
	hud.open_category("roads")
	await wait_process_frames(2)
	assert_true(hud._cell_button("road") is Button)
	for cat in ["housing", "food", "water", "lumen", "logistics", "resources", "refining", "civic", "landmark"]:
		hud.open_category(cat) if hud._grid_page == "" else hud._open_grid_page(cat)
		await wait_process_frames(2)
		assert_lte(hud._cmd_cells.size(), Hud.GRID_COLUMNS * 3, "%s fits the 5x3 grid" % cat)
		assert_lte(hud._cmd_panel.get_global_rect().size.y, Hud.BAND_HEIGHT, "%s keeps the grid inside the band" % cat)
