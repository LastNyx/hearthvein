extends GutTest
## Ticket 81: every building has a plain description; HudModel builds tooltip text from data; the HUD shows it after a
## hover delay on a build button and over a placed building (not while a build tool is active or the camera drags).

var reg: DataRegistry
var s: Settlement
var m: HudModel
var cfg: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(42, reg)
	m = HudModel.new(s)
	cfg = "/tmp/nyx-flash/hearthvein_tooltips_%d.cfg" % OS.get_process_id()


func after_each() -> void:
	DirAccess.remove_absolute(cfg)


func test_every_building_has_a_description() -> void:
	for id in reg.buildings:
		var d: BuildingDef = reg.buildings[id]
		if id.begins_with("test_"):
			continue
		assert_ne(d.description.strip_edges(), "", "%s has a description" % id)


func test_tooltip_text_carries_the_numbers_from_data() -> void:
	var f: Dictionary = m.tooltip_for("forager")
	assert_eq(f["title"], "Forager")
	assert_eq(f["description"], reg.get_building("forager").description)
	var t: String = f["text"]
	assert_string_contains(t, "10 Wood")
	assert_string_contains(t, "Workers 2")
	assert_string_contains(t, "8 Food")
	var tap := m.tooltip_for("lumen_tap")["text"] as String
	assert_string_contains(tap, "8 Lumen")
	var saw := m.tooltip_for("sawmill")["text"] as String
	assert_string_contains(saw, "14 Wood")
	assert_string_contains(saw, "6 Wood")
	assert_string_contains(saw, "3 Planks")
	var store := m.tooltip_for("storehouse")["text"] as String
	assert_string_contains(store, "Haulers 2")
	assert_string_contains(store, "400")
	assert_string_contains(m.tooltip_for("shrine")["text"] as String, "6 tiles")
	assert_string_contains(m.tooltip_for("cottage")["text"] as String, "Beds")


func test_placed_building_tooltip_shows_halt_reason_and_workers() -> void:
	var h := s.map.hearth_spot
	var id := -1
	for y in range(h.y - 8, h.y + 8):
		for x in range(h.x + 4, h.x + 20):
			if id < 0 and s.can_place("woodcutter", Vector2i(x, y))["ok"]:
				id = s.place_building_instant("woodcutter", Vector2i(x, y))
	assert_gt(id, 0)
	var b: Building = s.buildings[id]
	b.halt = "no_forest"
	var t: Dictionary = m.tooltip_for_building(b)
	assert_string_contains(t["text"], "Halted: no forest in range")
	assert_string_contains(t["text"], "Workers 0/2")
	assert_eq(t["title"], "Woodcutter")
	b.halt = ""
	assert_false((m.tooltip_for_building(b)["text"] as String).contains("Halted"))


func _hud() -> Array:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.settings_path = cfg
	main.saves_dir = cfg + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42)
	await wait_process_frames(2)
	return [main, main.hud]


func test_build_button_hover_opens_the_detail_panel_not_the_tooltip() -> void:
	var r := await _hud()
	var hud: Hud = r[1]
	hud.open_category("food")
	await wait_process_frames(2)
	var b: Button = hud.build_button("forager")
	assert_not_null(b)
	assert_false(hud.detail_visible())
	b.mouse_entered.emit()
	hud.hover_tick(0.0)
	assert_true(hud.detail_visible())
	assert_eq(hud.detail_title(), "Forager")
	assert_false(hud.tooltip_visible())
	b.mouse_exited.emit()
	hud.hover_tick(0.0)
	assert_false(hud.detail_visible())


func test_map_tooltip_over_a_building_but_not_while_placing_or_dragging() -> void:
	var r := await _hud()
	var main: Node = r[0]
	var hud: Hud = r[1]
	var s2: Settlement = main.settlement
	var tile := s2.hearth.origin
	hud.hover_tick(0.5, tile)
	assert_true(hud.tooltip_visible())
	assert_string_contains(hud.tooltip_text(), "Hearth")
	hud.hover_tick(0.5, tile + Vector2i(30, 30))
	assert_false(hud.tooltip_visible(), "empty ground shows nothing")
	main.get_node("BuildController").set_build("tent")
	hud.hover_tick(0.5, tile)
	assert_false(hud.tooltip_visible(), "not while a build tool is active")
	main.get_node("BuildController").cancel()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	hud._unhandled_input(ev)
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(50, 0)
	hud._unhandled_input(mv)
	hud.hover_tick(0.5, tile)
	assert_false(hud.tooltip_visible(), "not while dragging the camera")
