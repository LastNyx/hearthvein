extends GutTest
## Ticket 130: the HUD as a whole. Five parts (goods + clock, objectives, minimap, selection panel, command grid) must
## fit together at every size and UI scale: one bottom band of at most 148 px at the screen bottom, no two panels
## overlapping, everything inside the viewport, no text clipped, and the map hover tip hidden under a full page.

const SEED := 42
## Window size and UI scale pairs whose logical viewport is at least 1280x720 (UI scale divides the window).
const CASES := [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(1920, 1080), 1.25],
		[Vector2i(1920, 1080), 1.5], [Vector2i(2560, 1440), 1.0]]

var dir: String
var cfg: String
var _old_size: Vector2i


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_hud130_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	_old_size = get_window().size


func after_each() -> void:
	get_window().content_scale_factor = 1.0
	get_window().size = _old_size
	get_tree().paused = false
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _game(size: Vector2i = Vector2i(1280, 720), scale: float = 1.0, era: String = "ascendant") -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED, false, false)
	get_window().size = size  # the headless window is tiny
	get_window().content_scale_factor = scale
	await wait_process_frames(2)
	var s: Settlement = main.settlement
	s.era_override = era
	s.hearth.inventory.add("wood", 100.0)
	s.hearth.inventory.add("stone", 100.0)
	await wait_process_frames(3)
	return main


func _panels(hud: Hud) -> Dictionary:
	return {"objectives": hud.objectives_panel, "goods": hud.goods_panel, "clock": hud.clock_panel,
			"minimap": hud.minimap, "selection": hud._sel_panel, "grid": hud._cmd_panel}


func _labels(node: Node, out: Array[Label]) -> void:
	if node is Control and not (node as Control).visible:
		return
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels(c, out)


## Every panel inside the viewport, none overlapping, the bottom band one 148 px strip hugging the bottom edge.
func _check_layout(hud: Hud, tag: String) -> void:
	var vp := hud.get_viewport().get_visible_rect()
	var panels := _panels(hud)
	var names: Array = panels.keys()
	for n in names:
		var c: Control = panels[n]
		if not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		assert_true(vp.grow(0.5).encloses(r), "%s: %s inside the viewport (%s in %s)" % [tag, n, r, vp])
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Control = panels[names[i]]
			var b: Control = panels[names[j]]
			if a.is_visible_in_tree() and b.is_visible_in_tree():
				assert_false(a.get_global_rect().intersects(b.get_global_rect()), "%s: %s overlaps %s (%s, %s)" % [
						tag, names[i], names[j], a.get_global_rect(), b.get_global_rect()])
	var band := hud.find_child("BottomBand", true, false) as Control
	var br := band.get_global_rect()
	assert_lte(br.size.y, Hud.BAND_HEIGHT + 0.5, "%s: the bottom band is at most 148 px high" % tag)
	assert_gte(br.end.y, vp.end.y - 8.0, "%s: the band hugs the bottom edge" % tag)
	assert_lte(br.end.y, vp.end.y + 0.5)
	for n in ["minimap", "selection", "grid"]:
		var r := (panels[n] as Control).get_global_rect()
		assert_true(br.grow(0.5).encloses(r), "%s: %s sits in the band (%s in %s)" % [tag, n, r, br])
		assert_lte(r.size.y, Hud.BAND_HEIGHT + 0.5, "%s: %s fits 148 px" % [tag, n])
	# The notices stack above the selection panel, not over it.
	var notes := hud._notes_box.get_global_rect()
	if hud._notes_box.get_child_count() > 0:
		assert_lte(notes.end.y, hud._sel_panel.get_global_rect().position.y + 0.5, "%s: notices above the selection panel" % tag)


## No text clipped: a plain label is as wide as it needs and lies inside its panel; the panel is as big as its content.
func _check_text(hud: Hud, tag: String) -> void:
	var panels := _panels(hud)
	for n in panels:
		var p: Control = panels[n]
		if not p.is_visible_in_tree():
			continue
		var pr := p.get_global_rect()
		var need := p.get_combined_minimum_size()
		assert_lte(need.x, p.size.x + 0.5, "%s: %s is wide enough for its content (%s)" % [tag, n, need])
		assert_lte(need.y, p.size.y + 0.5, "%s: %s is tall enough for its content (%s)" % [tag, n, need])
		var labels: Array[Label] = []
		_labels(p, labels)
		for l in labels:
			if l.text == "" or _in_scroll(l):
				continue
			var lr := l.get_global_rect()
			assert_true(pr.grow(0.5).encloses(lr), "%s: label '%s' inside %s (%s in %s)" % [tag, l.text, n, lr, pr])
			if l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not l.clip_text:
				assert_lte(l.get_minimum_size().x, l.size.x + 0.5, "%s: label '%s' not clipped" % [tag, l.text])
				assert_lte(l.get_minimum_size().y, l.size.y + 0.5, "%s: label '%s' tall enough" % [tag, l.text])
			else:
				var font := l.get_theme_font("font")
				var fs := l.get_theme_font_size("font_size")
				var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w > l.size.x + 0.5 and not [&"TownHint", &"CellName", &"CellKey", &"CellCost"].has(l.name):
					assert_true(l.tooltip_text.contains(l.text) or l.autowrap_mode != TextServer.AUTOWRAP_OFF,
							"%s: trimmed label '%s' keeps its full text in a tooltip" % [tag, l.text])


## Lines inside the selection panel's scroll box are reachable by scrolling; the box itself is checked as a panel part.
func _in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _check_cells(hud: Hud, tag: String) -> void:
	for b in hud._cmd_cells:
		var br := b.get_global_rect()
		var name_l := b.find_child("CellName", true, false) as Label
		var key_l := b.find_child("CellKey", true, false) as Label
		var pic := b.find_children("*", "Control", true, false).filter(func(c: Node) -> bool:
				return c.get_parent() is HBoxContainer and c.get_parent().get_parent() is VBoxContainer and not c is Label)
		assert_true(br.grow(0.5).encloses(name_l.get_global_rect()), "%s: cell name '%s' inside its cell" % [tag, name_l.text])
		for c: Control in pic:
			if c.custom_minimum_size.x >= Hud.CELL_PIC:
				assert_false(c.get_global_rect().intersects(name_l.get_global_rect()), "%s: icon and label of '%s' do not overlap" % [tag, name_l.text])
		if str(b.get_meta("cell_state")) == "empty":
			assert_eq(key_l.text, "", "%s: an empty cell shows no hotkey" % tag)
			assert_eq(name_l.text, "")


func test_layout_at_every_size_and_scale() -> void:
	for case in CASES:
		var main: Node = await _game(case[0], case[1])
		var hud: Hud = main.get_node("Hud")
		var tag := "%s x%s" % [case[0], case[1]]
		var vp := hud.get_viewport().get_visible_rect().size
		assert_gte(vp.x, 1280.0 - 1.0, "%s: the logical viewport stays 1280 wide or more" % tag)
		assert_eq(vp, Vector2(case[0]) / float(case[1]), "%s: scale divides the window" % tag)
		_check_layout(hud, tag)
		_check_text(hud, tag)
		_check_cells(hud, tag)
		# The minimap image draws, bottom-left, inside its panel.
		var mm := hud.minimap
		assert_not_null(mm.texture)
		var mr := mm.map_area.get_global_rect()
		assert_eq(mr.size, Minimap.MAP_SIZE, "%s: the map is drawn at full size" % tag)
		assert_true(mm.get_global_rect().encloses(mr))
		assert_lt(mm.get_global_rect().position.x, vp.x * 0.25, "%s: minimap at the left" % tag)
		assert_gt(mm.get_global_rect().position.y, vp.y * 0.6, "%s: minimap at the bottom" % tag)
		main.queue_free()
		await wait_process_frames(2)


func test_every_grid_page_fits_cells_and_labels() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var pages: Array[String] = [""]
	for c in HudModel.GRID_TOP:
		if HudModel.is_grid_category(str(c[0])):
			pages.append(str(c[0]))
	for page in pages:
		hud._set_grid_page(page)
		await wait_process_frames(2)
		var tag := "page '%s'" % page
		_check_layout(hud, tag)
		_check_text(hud, tag)
		_check_cells(hud, tag)
		assert_eq(hud._cmd_cells.size(), 15, tag)


func _spot_for(s: Settlement, id: String) -> int:
	var h := s.map.hearth_spot
	for r in range(3, 30):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var bid := s.place_building_instant(id, h + Vector2i(dx, dy))
				if bid >= 0:
					return bid
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				var bid := s.place_building_instant(id, h + Vector2i(dx, dy))
				if bid >= 0:
					return bid
	return -1


func test_selection_panel_fits_longest_name_and_longest_halt_reason() -> void:
	for case in [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.5]]:
		var main: Node = await _game(case[0], case[1])
		var s: Settlement = main.settlement
		var hud: Hud = main.get_node("Hud")
		var m: HudModel = main.hud_model
		var tag := "%s x%s" % [case[0], case[1]]
		var limit := Hud.BAND_HEIGHT - Hud.MARGIN
		# The longest building names first, until one can be placed (sky buildings need an island).
		var defs: Array = s.registry.buildings.values()
		defs.sort_custom(func(x: BuildingDef, y: BuildingDef) -> bool: return x.display_name.length() > y.display_name.length())
		var bid := -1
		for def: BuildingDef in defs:
			if def.id == "hearth":
				continue
			bid = _spot_for(s, def.id)
			if bid >= 0:
				break
		assert_true(bid >= 0, "%s: placed a building with a long name" % tag)
		if bid >= 0:
			var b: Building = s.buildings[bid]
			m.select(bid)
			hud.refresh()
			await wait_process_frames(3)
			assert_eq(hud._sel_title.text, b.display_name(s.registry))
			assert_gte(b.display_name(s.registry).length(), 13, "a long name")
			_check_layout(hud, tag + " long name")
			_check_text(hud, tag + " long name")
			assert_lte(hud._sel_panel.size.y, limit + 0.5, "%s: selection panel within the band" % tag)
			assert_lte(hud._sel_title.get_minimum_size().x, hud._sel_title.size.x + 0.5, "%s: title not clipped" % tag)
		# Every halt reason (the longest with its advice line) on a working building.
		var wid := _spot_for(s, "woodcutter")
		assert_true(wid >= 0)
		var w: Building = s.buildings[wid]
		for halt in ["door_full", "no_input", "no_forest", "island_still", "planet_too_sick", "dry", "too_far"]:
			w.halt = halt
			m.select(wid)
			hud.refresh()
			await wait_process_frames(2)
			var t := "%s halt %s" % [tag, halt]
			assert_true(hud._sel_halt.visible, t)
			assert_lte(hud._sel_panel.size.y, limit + 0.5, "%s: selection panel within the band (%s)" % [t, hud._sel_panel.size])
			_check_layout(hud, t)
			_check_text(hud, t)
		# A construction site and a house with residents carry the most lines.
		for id in ["tent", "cottage", "storehouse", "refinery"]:
			var xid := _spot_for(s, id)
			if xid < 0:
				continue
			m.select(xid)
			hud.refresh()
			await wait_process_frames(2)
			assert_lte(hud._sel_panel.size.y, limit + 0.5, "%s: %s fits the band" % [tag, id])
			_check_text(hud, "%s %s" % [tag, id])
		m.clear_selection()
		hud.refresh()
		await wait_process_frames(2)
		_check_layout(hud, tag + " town summary")
		_check_text(hud, tag + " town summary")
		main.queue_free()
		await wait_process_frames(2)


# AC (130b): the selection sprite is drawn at the largest integer scale that fits its box, and the tier badge sits
# beside the name, never on the sprite.
func test_selection_sprite_largest_integer_scale_and_badge_beside_the_name() -> void:
	var main: Node = await _game(Vector2i(1280, 720), 1.0)
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var bid := _spot_for(s, "sawmill")
	assert_true(bid >= 0, "a sawmill")
	main.hud_model.select(bid)
	hud.refresh()
	await wait_process_frames(3)
	var entry: Dictionary = ArtLibrary.manifest()["buildings"][str(s.buildings[bid].def.id)]
	var tex := Vector2(float(entry["w"]), float(entry["h"]))
	var size := hud._sel_sprite.custom_minimum_size
	var k := size.x / tex.x
	assert_almost_eq(size.y, tex.y * k, 0.01, "one whole-number scale on both axes")
	assert_gt(k, 1.0, "the sprite is drawn larger than its art")
	assert_lte(size.x, Hud.SEL_PIC.x + 0.5, "the sprite fits its box across")
	assert_lte(size.y, Hud.SEL_PIC.y + 0.5, "the sprite fits its box down")
	assert_true(tex.x * (k + 1.0) > Hud.SEL_PIC.x + 0.5 or tex.y * (k + 1.0) > Hud.SEL_PIC.y + 0.5,
			"no larger whole-number scale fits")
	assert_true(hud._sel_pic.get_global_rect().encloses(hud._sel_sprite.get_global_rect()),
			"the sprite is inside the picture box")
	var badge := hud._sel_panel.find_child("TierBadge", true, false) as Control
	assert_not_null(badge, "the tier badge")
	assert_false(badge.get_global_rect().intersects(hud._sel_sprite.get_global_rect()),
			"the badge does not overlap the sprite")


# AC (130b): every building name shows whole in its command-grid cell at 1280x720.
func test_no_grid_label_truncated_for_any_building() -> void:
	var main: Node = await _game(Vector2i(1280, 720), 1.0)
	var hud: Hud = main.get_node("Hud")
	var pages: Array[String] = [""]
	for c in HudModel.GRID_TOP:
		if HudModel.is_grid_category(str(c[0])):
			pages.append(str(c[0]))
	var checked := 0
	for page in pages:
		var p := page
		for no in range(1, 4):
			if no > 1:
				p = "%s:%d" % [page, no]
			hud._set_grid_page(p)
			await wait_process_frames(2)
			for b in hud._cmd_cells:
				var nm := b.find_child("CellName", true, false) as Label
				if nm == null or nm.text == "":
					continue
				var w := nm.get_theme_font("font").get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
						nm.get_theme_font_size("font_size")).x
				assert_lte(w, nm.size.x + 0.5, "the full name '%s' shows" % nm.text)
				checked += 1
			var cells := hud.model.grid(p)
			if cells.size() < 15 or str(cells[14]["id"]) != "more":
				break
	assert_gt(checked, 0, "labels were checked")


## Every page the grid can show: the top level, each category's first page and any More pages past it.
func _grid_pages(hud: Hud) -> Array[String]:
	var out: Array[String] = [""]
	for c in HudModel.GRID_TOP:
		if not HudModel.is_grid_category(str(c[0])):
			continue
		for no in range(1, 4):
			var p := str(c[0]) if no == 1 else "%s:%d" % [c[0], no]
			out.append(p)
			var cells := hud.model.grid(p)
			if cells.size() < 15 or str(cells[14]["id"]) != "more":
				break
	return out


## The parts a cell draws, by name: hotkey, short cost, icon (with the art or glyph inside it), name and lock.
func _cell_parts(b: Button) -> Array[Control]:
	var out: Array[Control] = []
	for n in ["CellKey", "CellCost", "CellName", "Lock"]:
		var c := b.find_child(n, true, false) as Control
		if c != null:
			out.append(c)
	var icon := b.find_child("CellIcon", true, false) as Control
	if icon != null:
		out.append(icon)
		for c in icon.get_children():
			if c is Control:
				out.append(c)
	return out


## AC (130c): every cell child (key, cost, icon, label, lock) lies inside its cell rect at 1280x720, for every
## building page and the top-level grid; the hotkey and the short cost sit 3 px inside the border, never on it.
func test_every_grid_cell_child_lies_inside_its_cell() -> void:
	var main: Node = await _game(Vector2i(1280, 720), 1.0)
	var hud: Hud = main.get_node("Hud")
	for p in _grid_pages(hud):
		hud._set_grid_page(p)
		await wait_process_frames(2)
		for b in hud._cmd_cells:
			var cell := b.get_global_rect()
			var inside := cell.grow(-2.0)  # the cell's border: no part of the cell may sit on it
			for part in _cell_parts(b):
				var r := part.get_global_rect()
				assert_true(inside.grow(0.5).encloses(r),
						"page '%s': %s of cell '%s' lies inside the cell (%s in %s)" % [p, part.name, b.name, r, cell])
			var key := b.find_child("CellKey", true, false) as Control
			var cost := b.find_child("CellCost", true, false) as Control
			if key != null:
				assert_gte(key.get_global_rect().position.x, cell.position.x + 5.0 - 0.5,
						"page '%s': the hotkey is 3 px inside the border" % p)
			if cost != null:
				assert_lte(cost.get_global_rect().end.x, cell.end.x - 5.0 + 0.5,
						"page '%s': the short cost is 3 px inside the border" % p)


## AC (130c): every grid name is at least the readable minimum size (12), and a lock sits on the icon, never on the
## name.
func test_grid_names_are_readable_and_locks_clear_of_the_name() -> void:
	var main: Node = await _game(Vector2i(1280, 720), 1.0)
	var hud: Hud = main.get_node("Hud")
	var locks := 0
	for p in _grid_pages(hud):
		hud._set_grid_page(p)
		await wait_process_frames(2)
		for b in hud._cmd_cells:
			var nm := b.find_child("CellName", true, false) as Label
			assert_gte(nm.get_theme_font_size("font_size"), 12,
					"page '%s': name '%s' is at least the readable size" % [p, nm.text])
			var lock := b.find_child("Lock", true, false) as Control
			if lock == null:
				continue
			locks += 1
			assert_false(lock.get_global_rect().intersects(nm.get_global_rect()),
					"page '%s': the lock does not cover '%s'" % [p, nm.text])
	assert_gt(locks, 0, "locked cells were checked")


func test_map_hover_tip_hides_under_a_full_page() -> void:
	var main: Node = await _game(Vector2i(1280, 720), 1.0, "village")
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var tile := s.hearth.origin
	hud.hover_tick(1.0, tile)
	assert_true(hud.tooltip_visible(), "the hearth tip shows with no page open")
	var pages := {"resources": hud.resources_page, "workforce": hud.workforce_page, "region map": hud._region_map}
	for n in pages:
		var page: Control = pages[n]
		page.call("open")
		await wait_process_frames(2)
		assert_true(page.visible, n)
		assert_true(hud.page_open(), n)
		hud.hover_tick(1.0, tile)
		hud.hover_tick(1.0, tile)
		assert_false(hud.tooltip_visible(), "no map tip over the %s page" % n)
		page.call("close")
		await wait_process_frames(2)
		hud.hover_tick(1.0, tile)
		assert_true(hud.tooltip_visible(), "the tip is back once the %s page closes" % n)


func test_speed_and_pause_live_in_the_clock_row() -> void:
	var main: Node = await _game()
	var hud: Hud = main.get_node("Hud")
	var drv: SimDriver = main.driver
	for i in [1, 2, 3]:
		hud._speed_buttons[i - 1].pressed.emit()
		assert_eq(drv.speed, i)
		hud.refresh()
		assert_eq((hud._speed_buttons[i - 1].get_theme_stylebox("normal") as StyleBoxFlat).border_color, Hud.GOLD)
	hud._pause_button.pressed.emit()
	assert_eq(drv.speed, 0)
	hud.refresh()
	assert_eq((hud._pause_button.get_theme_stylebox("normal") as StyleBoxFlat).border_color, Hud.GOLD)
	assert_null(hud.find_child("ToolsTab", true, false), "the old tools column is gone")
