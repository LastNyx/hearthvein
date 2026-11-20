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


func test_cards_show_state_icons_and_numbers() -> void:
	var hud := await _hud()
	hud.open_category("refining")
	await wait_process_frames(2)
	var saw: Button = hud.build_button("sawmill")
	var ref: Button = hud.build_button("refinery")
	var tool: Button = hud.build_button("toolsmith")
	assert_eq(saw.get_meta("card"), "ok")
	assert_eq(ref.get_meta("card"), "short")
	assert_eq(tool.get_meta("card"), "locked")
	assert_eq(saw.get_meta("def_id"), "sawmill", "def_id meta stays for the tutorial and hint cards")
	assert_true(saw.has_meta("reason"))
	assert_true(tool.disabled)
	assert_false(ref.disabled, "a short card still places a site")
	assert_eq((saw.find_child("CardName", true, false) as Label).text, "Sawmill")
	var wood: Control = saw.find_child("Cost_wood", true, false)
	assert_not_null(wood)
	assert_eq((wood.find_child("Num", true, false) as Label).text, "14")
	assert_not_null(wood.find_child("Icon", true, false), "a cost draws the good's icon")
	var gold: Control = ref.find_child("Cost_gold", true, false)
	assert_eq((gold.find_child("Num", true, false) as Label).get_theme_color("font_color"), Hud.RED, "the short number is red")
	var wood2: Control = ref.find_child("Cost_wood", true, false)
	assert_ne((wood2.find_child("Num", true, false) as Label).get_theme_color("font_color"), Hud.RED)
	assert_not_null(tool.find_child("Lock", true, false))
	assert_eq((tool.find_child("UnlockReason", true, false) as Label).text, "Needs City era")
	assert_null(saw.find_child("Lock", true, false))


## Ticket 122: with every era unlocked all 12 categories share one row that fits inside 1280 px at UI scale 1.0.
func test_twelve_categories_fit_on_one_row_at_1280() -> void:
	var hud := await _hud("ascendant")
	hud._rebuild_categories()
	var old := get_window().size
	get_window().size = Vector2i(1280, 720)  # the headless window is tiny
	await wait_process_frames(3)
	var bar := hud.model.build_bar()
	assert_eq(bar.size(), 12, "every category is unlocked in the Ascendant era")
	var panel := hud._cat_box.get_parent() as Control
	var r := panel.get_global_rect()
	assert_gte(r.position.x, 0.0, "the bar starts inside 1280: %s" % r)
	assert_lte(r.end.x, 1280.0, "the bar ends inside 1280: %s" % r)
	var row_y := -1.0
	for cat in bar:
		var br := (hud._cat_buttons[cat["id"]] as Button).get_global_rect()
		if row_y < 0.0:
			row_y = br.position.y
		assert_almost_eq(br.position.y, row_y, 0.5, "%s sits on the one row" % cat["id"])
	get_window().size = old


## Ticket 122: the category buttons keep their labels and their pressed signal (tests and the tutorial find them by name).
func test_category_names_and_pressed_signals_stay() -> void:
	var hud := await _hud("ascendant")
	hud._rebuild_categories()
	for cat in hud.model.build_bar():
		var b: Button = hud._cat_buttons[cat["id"]]
		assert_eq(b.text, cat["label"], "%s keeps its name" % cat["id"])
	var housing: Button = hud._cat_buttons["housing"]
	housing.pressed.emit()
	assert_eq(hud._open_cat, "housing", "a press opens its category")
	housing.pressed.emit()
	assert_eq(hud._open_cat, "", "a second press closes it")


func test_road_tools_stay_buttons_and_the_flyout_fits() -> void:
	var hud := await _hud("ascendant")
	hud.open_category("roads")
	await wait_process_frames(2)
	var road := hud._fly_box.find_child("Tool_road", true, false)
	assert_true(road is Button)
	var biggest := ""
	var most := 0
	for cat in hud.model.build_bar():
		if cat["id"] != "roads" and (cat["entries"] as Array).size() > most:
			most = (cat["entries"] as Array).size()
			biggest = cat["id"]
	hud.open_category(biggest)
	await wait_process_frames(3)
	var r := hud._fly_panel.get_global_rect()
	assert_gte(most, 6, "the test needs a crowded category")
	assert_lte(r.end.x, 930.0, "the cards leave the right-hand panel its width at 1280")
	assert_lte(r.size.y, 520.0, "two rows of cards at most, the rest scrolls")
	assert_lte(r.end.y, 720.0, "above the bottom bar, inside 720")

