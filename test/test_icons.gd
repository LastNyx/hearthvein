extends GutTest
## Ticket 112: the 1.1.6 icon set is exported for every good and the HUD draws it in the top bar and before the numbers
## of every goods line (a build tooltip's cost, a construction site's wait line).

const SEED := 42
const KINDS: Array[String] = ["food", "wood", "stone", "planks", "cut_stone", "tools", "lumen", "cells", "gold", "pop",
		"spirit", "moon", "planet"]

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_icons_%d" % OS.get_process_id()
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
	main.start_new_game(SEED)
	await wait_process_frames(2)
	return main


func _free_spot(s: Settlement, id: String, from: int) -> Vector2i:
	var h := s.map.hearth_spot
	for x in range(h.x + from, h.x + 30):
		for y in range(h.y - 8, h.y + 8):
			if s.can_place(id, Vector2i(x, y))["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Number of icon TextureRects under `node`, in order.
func _icons(node: Node) -> Array[TextureRect]:
	var out: Array[TextureRect] = []
	for c in node.get_children():
		if c is TextureRect:
			out.append(c)
		out.append_array(_icons(c))
	return out


## The HBox line that starts with `prefix` under `node`, or null.
func _line_row(node: Node, prefix: String) -> HBoxContainer:
	for c in node.get_children():
		if c is HBoxContainer:
			for l in c.get_children():
				if l is Label and (l as Label).text.begins_with(prefix):
					return c
		var found := _line_row(c, prefix)
		if found != null:
			return found
	return null


func test_every_hud_icon_is_exported() -> void:
	var icons: Dictionary = ArtLibrary.manifest()["icons"]
	for k in KINDS:
		assert_true(icons.has(k), "%s is in the manifest" % k)
		var t := ArtLibrary.texture(str(icons[k]))
		assert_not_null(t, "%s texture loads" % k)
		assert_eq(t.get_size(), Vector2(14, 14), "%s is a 12x12 icon plus its outline" % k)


func test_top_bar_shows_the_nine_goods_with_icons() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var m: HudModel = main.hud_model
	assert_eq(hud._res_icons.keys(), HudModel.RESOURCES, "one icon per good, in the build_menu order")
	assert_eq((hud._res_labels["planks"] as Label).text, m.resources().filter(
			func(r: Dictionary) -> bool: return r["id"] == "planks")[0]["value_text"])
	for k in HudModel.RESOURCES:
		assert_not_null((hud._res_icons[k] as TextureRect).texture, "%s icon" % k)
	assert_eq((hud._res_deltas["wood"] as Label).text.substr(0, 1), "+", "the delta sits under the value")


func test_site_wait_line_draws_good_icons() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var m: HudModel = main.hud_model
	var site := s.place_building("tent", _free_spot(s, "tent", 4))
	assert_true(site >= 0)
	m.select(site)
	hud.refresh()
	assert_string_contains(m.wait_text(s.buildings[site]), "Waiting for materials")
	var row := _line_row(hud._sel_body, "Waiting for materials")
	assert_not_null(row, "the wait line is drawn as its own row")
	var icons := _icons(row)
	assert_eq(icons.size(), 1, "the Tent needs wood only")
	assert_same(icons[0].texture, ArtLibrary.texture(ArtLibrary.manifest()["icons"]["wood"]))


func test_build_tooltip_cost_line_draws_good_icons() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	hud.open_category("food")
	await wait_process_frames(2)
	var b: Button = hud.build_button("forager")
	assert_not_null(b)
	b.mouse_entered.emit()
	hud.hover_tick(0.5)
	assert_true(hud.tooltip_visible())
	var row := _line_row(hud._tip_box, "Cost: ")
	assert_not_null(row, "the cost line is drawn as its own row")
	var icons := _icons(row)
	assert_eq(icons.size(), 1, "a Forager costs wood only")
	assert_same(icons[0].texture, ArtLibrary.texture(ArtLibrary.manifest()["icons"]["wood"]))
