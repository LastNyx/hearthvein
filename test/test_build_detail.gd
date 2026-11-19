extends GutTest
## Ticket 117: hovering a build card opens the detail panel (big sprite, purpose, cost per good with have N, workers, size,
## input -> output per day, unlock) and leaving closes it.

var cfg: String


func before_each() -> void:
	cfg = "/tmp/hearthvein_build_menu_%d.cfg" % OS.get_process_id()


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


func test_detail_for_a_def_has_everything_the_panel_shows() -> void:
	var hud := await _hud()
	var d := hud.model.detail_for("sawmill")
	var def := hud.model.s.registry.get_building("sawmill")
	assert_eq(d["title"], "Sawmill")
	assert_eq(d["kind"], "Refining, Village era")
	assert_eq(d["description"], def.description)
	assert_eq(_cost(d, "wood")["need"], 14)
	assert_true(int(_cost(d, "wood")["have"]) >= 100, "have N is the stock")
	assert_eq(d["workers"], 2)
	assert_eq(d["size"], "%d x %d tiles" % [def.size.x, def.size.y])
	assert_eq(d["inputs"][0]["good"], "wood")
	assert_eq(d["inputs"][0]["amount"], "6")
	assert_eq(d["outputs"][0]["good"], "planks")
	assert_eq(d["outputs"][0]["amount"], "3")
	assert_eq(d["unlock"], "Village era (unlocked)")
	assert_false(d["locked"])
	var tool := hud.model.detail_for("toolsmith")
	assert_eq(tool["unlock"], "Needs City era")
	assert_true(tool["locked"])
	assert_eq(hud.model.detail_for("no_such_building"), {})


func test_hovering_a_card_opens_the_detail_panel_and_leaving_closes_it() -> void:
	var hud := await _hud()
	hud.open_category("refining")
	await wait_process_frames(2)
	assert_false(hud.detail_visible())
	var b: Button = hud.build_button("sawmill")
	b.mouse_entered.emit()
	hud.hover_tick(0.0)
	assert_true(hud.detail_visible(), "no delay: the panel follows the card")
	assert_eq(hud.detail_title(), "Sawmill")
	assert_false(hud.tooltip_visible(), "the build button no longer opens the small tooltip")
	var cost: Control = hud._detail.find_child("DetailCost_wood", true, false)
	assert_not_null(cost)
	assert_string_contains((cost.find_child("Have", true, false) as Label).text, "have")
	assert_not_null(hud._detail.find_child("DetailCost_wood", true, false).find_child("Icon", true, false))
	var other: Button = hud.build_button("refinery")
	b.mouse_exited.emit()
	other.mouse_entered.emit()
	hud.hover_tick(0.0)
	assert_eq(hud.detail_title(), "Refinery")
	var gold: Control = hud._detail.find_child("DetailCost_gold", true, false)
	assert_eq((gold.find_child("Have", true, false) as Label).get_theme_color("font_color"), Hud.RED, "a short good is red")
	other.mouse_exited.emit()
	hud.hover_tick(0.0)
	assert_false(hud.detail_visible())
