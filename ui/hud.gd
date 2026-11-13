class_name Hud
extends CanvasLayer
## The in-game HUD (design.md section 20, docs/mockups/scene_village.png): top bar with resources, pop/beds, Spirit and
## planet health; era + Dimming panel; selected-building panel; bottom build bar by category; notices; overlay buttons.
## Thin: every number and string comes from HudModel, every command goes through HudModel or BuildController.

const FONT_PATH := "res://assets/ui/PixelifySans.ttf"  # headings; OFL 1.1, see PixelifySans-OFL.txt
const BODY_FONT_PATH := "res://assets/ui/Tiny5.ttf"  # body text; OFL 1.1, see Tiny5-OFL.txt
const INK := Color("ece2ce")
const GOLD := Color("f2d27a")
const DIM := Color("aaa096")
const CYAN := Color("7fe0f0")
const PURPLE := Color("b496d2")
const RED := Color("e86a5a")
const PANEL_BG := Color(0.094, 0.078, 0.071, 0.92)
const PANEL_EDGE := Color(0.353, 0.314, 0.275)
const OVERLAYS := [["blight", "Blight", "V"], ["roads", "Roads", "G"], ["water", "Water", "T"],
		["coverage", "Coverage", "H"]]  # id, label, key

var model: HudModel
var build: BuildController
var camera: Camera2D
var driver: SimDriver
var _font: FontFile
var _body_font: FontFile
var _res_labels: Dictionary = {}
var _pop_label: Label
var _growth_bar: ProgressBar
var _float: Control
var _spirit_bar: ProgressBar
var _spirit_label: Label
var _spirit_box: Control
var _planet_label: Label
var _overlay_buttons: Dictionary = {}
var _overlay_toggle: Button
var _overlay_panel: PanelContainer
var _era_title: Label
var _era_dimming: Label
var _era_gate: Label
var _era_date: Label
var _era_panel: PanelContainer
var _moon: TextureRect
var _notes_box: VBoxContainer
var _notes_key := ""
var _sel_panel: PanelContainer
var _sel_title: Label
var _sel_body: Label
var _sel_halt: Label
var _sel_warn: Label
var _sel_up_cost: Label
var _sel_up_reason: Label
var _sel_up_btn: Button
var _prio_buttons: Dictionary = {}
var _cat_box: GridContainer
var _region_map: RegionMap
var _cat_buttons: Dictionary = {}
var _fly_panel: PanelContainer
var _fly_box: HBoxContainer
var _open_cat := ""
var _acc := 0.0


func setup(m: HudModel, b: BuildController, cam: Camera2D, d: SimDriver) -> void:
	model = m
	build = b
	camera = cam
	driver = d
	layer = 10
	_font = _pixel_font(FONT_PATH)
	_body_font = _pixel_font(BODY_FONT_PATH)
	var root := MarginContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 6)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	_build_top_bar(col)
	var mid := HBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	mid.add_child(left)
	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(right)
	_build_overlay_menu(right)
	_build_era_panel(right)
	_build_notes(center)
	_float = Control.new()
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float)
	_float.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_selection_panel(_float)
	_region_map = RegionMap.new()
	_float.add_child(_region_map)
	_region_map.setup(self, model)
	_region_map.resized.connect(_center_region_map)
	_build_bar(col)
	model.s.events.subscribe("era_changed", func(_e: Dictionary) -> void: _rebuild_categories())
	refresh()


# ---------------------------------------------------------------- building blocks

func _style(bg: Color = PANEL_BG, edge: Color = PANEL_EDGE, radius: int = 6, border: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style())
	parent.add_child(p)
	return p


## Pixel fonts stay crisp only at whole multiples of their grid: Pixelify Sans (7 px caps, ~11 px per pixel row
## step) at 22 for headings and the resource bar, Tiny5 (5 px caps, 8 px per step) at 16 for everything else.
## Both are drawn at 2x, matching the art's pixel scale.
static func _px_size(size: int) -> int:
	return 22 if size >= 17 else 16


func _px_font(size: int) -> FontFile:
	return _font if size >= 17 else _body_font


static func _pixel_font(path: String) -> FontFile:
	var f := FontFile.new()
	f.data = FileAccess.get_file_as_bytes(path)
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE  # crisp pixel edges
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


func _label(parent: Node, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _px_font(size))
	l.add_theme_font_size_override("font_size", _px_size(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _icon(parent: Node, kind: String, px: int = 28) -> TextureRect:
	var t := TextureRect.new()
	t.texture = ArtLibrary.texture(ArtLibrary.manifest()["icons"][kind])
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _button(parent: Node, text: String, size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _px_font(size))
	b.add_theme_font_size_override("font_size", _px_size(size))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK)
	_style_button(b, false)
	parent.add_child(b)
	return b


func _style_button(b: Button, on: bool) -> void:
	var edge := GOLD if on else Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", _style(Color(0.275, 0.235, 0.2) if on else Color(0.173, 0.149, 0.133), edge, 5, 2))
	b.add_theme_stylebox_override("hover", _style(Color(0.33, 0.28, 0.23), GOLD if on else PANEL_EDGE, 5, 2))
	b.add_theme_stylebox_override("pressed", _style(Color(0.33, 0.28, 0.23), GOLD, 5, 2))


# ---------------------------------------------------------------- top bar

func _build_top_bar(parent: Node) -> void:
	var p := _panel(parent)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	p.add_child(row)
	for k in HudModel.RESOURCES:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		row.add_child(box)
		_icon(box, k)
		_res_labels[k] = _label(box, 17)
	var pop := HBoxContainer.new()
	pop.add_theme_constant_override("separation", 6)
	row.add_child(pop)
	_icon(pop, "pop")
	_pop_label = _label(pop, 17)
	_growth_bar = ProgressBar.new()  # fills toward the next citizen
	_growth_bar.custom_minimum_size = Vector2(46, 8)
	_growth_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_growth_bar.show_percentage = false
	_growth_bar.max_value = 1.0
	_growth_bar.add_theme_stylebox_override("background", _style(Color(0.235, 0.196, 0.196), Color(0, 0, 0, 0.6), 2, 1))
	_growth_bar.add_theme_stylebox_override("fill", _style(Color("78be5a"), Color(0, 0, 0, 0), 2, 0))
	_growth_bar.tooltip_text = "Growth toward the next citizen"
	pop.add_child(_growth_bar)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 6)
	sp.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(sp)
	_spirit_box = sp
	_icon(sp, "spirit")
	_spirit_bar = ProgressBar.new()
	_spirit_bar.custom_minimum_size = Vector2(130, 16)
	_spirit_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spirit_bar.show_percentage = false
	_spirit_bar.max_value = 100.0
	_spirit_bar.add_theme_stylebox_override("background", _style(Color(0.235, 0.196, 0.196), Color(0, 0, 0, 0.6), 2, 1))
	sp.add_child(_spirit_bar)
	_spirit_label = _label(sp, 15)
	var pl := HBoxContainer.new()
	pl.add_theme_constant_override("separation", 6)
	row.add_child(pl)
	_icon(pl, "planet")
	_planet_label = _label(pl, 15)
	pl.tooltip_text = "Planet health and its change over the last year"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_overlay_toggle = _button(row, "Overlays", 14)
	_overlay_toggle.pressed.connect(toggle_overlay_menu)


## One compact flyout under the top bar holds every overlay toggle (room for more); keys work with it closed.
func _build_overlay_menu(parent: Node) -> void:
	_overlay_panel = _panel(parent)
	_overlay_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_overlay_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_overlay_panel.add_child(v)
	for pair in OVERLAYS:
		var b := _button(v, "%s (%s)" % [pair[1], pair[2]], 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_overlay.bind(pair[0]))
		_overlay_buttons[pair[0]] = b
	_overlay_panel.visible = false


func toggle_overlay_menu() -> void:
	_overlay_panel.visible = not _overlay_panel.visible
	_refresh_overlay_buttons()


func _on_overlay(id: String) -> void:
	model.toggle_overlay(id)
	_refresh_overlay_buttons()


func _refresh_overlay_buttons() -> void:
	var any := false
	for id in _overlay_buttons:
		_style_button(_overlay_buttons[id], model.overlay_on(id))
		any = any or model.overlay_on(id)
	_style_button(_overlay_toggle, any or _overlay_panel.visible)


# ---------------------------------------------------------------- era and Dimming panel

func _build_era_panel(parent: Node) -> void:
	_era_panel = _panel(parent)
	_era_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_era_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_era_panel.custom_minimum_size = Vector2(360, 0)
	var v := VBoxContainer.new()
	_era_panel.add_child(v)
	_era_title = _label(v, 18, GOLD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	_moon = _icon(row, "moon", 24)
	_era_dimming = _label(row, 17, Color("c8d2f0"))
	_era_gate = _label(v, 12, DIM)
	_era_gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_era_gate.custom_minimum_size = Vector2(336, 0)
	_era_date = _label(v, 13, DIM)


# ---------------------------------------------------------------- notices

func _build_notes(parent: Node) -> void:
	_notes_box = VBoxContainer.new()
	_notes_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_notes_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_notes_box)


func _refresh_notes() -> void:
	var recent := model.notifications.recent(48)
	var key := "|".join(recent.map(func(it: Dictionary) -> String: return str(it["text"]) + str(it["hour"])))
	if key == _notes_key:
		return
	_notes_key = key
	for c in _notes_box.get_children():
		c.queue_free()
	for it in recent.slice(maxi(0, recent.size() - 4)):
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := PANEL_EDGE
		match it["kind"]:
			"dimming": col = CYAN
			"halt", "workers": col = Color("e8a33a")
			"planet": col = RED
			"milestone": col = GOLD
		p.add_theme_stylebox_override("panel", _style(PANEL_BG, col, 6, 2))
		_notes_box.add_child(p)
		_label(p, 14, INK).text = it["text"]


# ---------------------------------------------------------------- selected building

func _build_selection_panel(parent: Node) -> void:
	_sel_panel = _panel(parent)
	_sel_panel.custom_minimum_size = Vector2(290, 0)
	var v := VBoxContainer.new()
	_sel_panel.add_child(v)
	_sel_title = _label(v, 18, CYAN)
	_sel_body = _label(v, 14, INK)
	_sel_halt = _label(v, 14, PURPLE)
	_sel_warn = _label(v, 14, RED)
	_sel_up_cost = _label(v, 14, GOLD)
	_sel_up_btn = _button(v, "Upgrade (U)", 13)
	_sel_up_btn.pressed.connect(func() -> void: model.upgrade())
	_sel_up_reason = _label(v, 14, DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	for p in ["low", "normal", "high"]:
		var b := _button(row, HudModel.PRIORITY_LABELS[p], 13)
		b.pressed.connect(func() -> void: model.set_priority(p))
		_prio_buttons[p] = b
	var pause := _button(row, "Pause", 13)
	pause.pressed.connect(func() -> void: model.toggle_pause())
	_prio_buttons["paused"] = pause
	_sel_panel.visible = false


func _refresh_selection() -> void:
	var sel := model.selection()
	_sel_panel.visible = not sel.is_empty()
	if sel.is_empty():
		return
	_place_selection_panel()
	_sel_title.text = sel["title"]
	_sel_body.text = "\n".join(sel["lines"])
	_sel_halt.text = sel["halt"]
	_sel_halt.visible = sel["halt"] != ""
	_sel_warn.text = sel["warn"]
	_sel_warn.visible = sel["warn"] != ""
	var show_up: bool = sel["show_upgrade"]
	_sel_up_cost.visible = show_up
	_sel_up_btn.visible = show_up
	_sel_up_reason.visible = show_up and not sel["can_upgrade"]
	if show_up:
		_sel_up_cost.text = "Upgrade to %s: %s" % [sel["next_name"], sel["next_cost"]]
		_sel_up_btn.text = "Upgrade to %s (U)" % sel["next_name"]
		_sel_up_btn.disabled = not sel["can_upgrade"]
		_sel_up_reason.text = sel["upgrade_reason"]
	for p in _prio_buttons:
		var on: bool = sel["paused"] if p == "paused" else (sel["priority"] == p and not sel["paused"])
		_style_button(_prio_buttons[p], on)


## Float the panel beside the selected building (right of it, left when there is no room), clamped to the screen.
func _place_selection_panel() -> void:
	var b := model.selected()
	if b == null or camera == null:
		return
	var xf := camera.get_viewport().get_canvas_transform()
	var tl: Vector2 = xf * (Vector2(b.origin) * ArtLibrary.TILE)
	var br: Vector2 = xf * (Vector2(b.origin + b.def.size) * ArtLibrary.TILE)
	var vp := camera.get_viewport().get_visible_rect().size
	var sz := _sel_panel.get_combined_minimum_size()
	_sel_panel.size = sz
	var pos := Vector2(br.x + 14.0, tl.y - 20.0)
	if pos.x + sz.x > vp.x - 6.0:
		pos.x = tl.x - sz.x - 14.0
	pos.x = clampf(pos.x, 6.0, maxf(6.0, vp.x - sz.x - 6.0))
	pos.y = clampf(pos.y, 60.0, maxf(60.0, vp.y - sz.y - 70.0))
	_sel_panel.position = pos


# ---------------------------------------------------------------- build bar

func _build_bar(parent: Node) -> void:
	_fly_panel = _panel(parent)
	_fly_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fly_box = HBoxContainer.new()
	_fly_box.add_theme_constant_override("separation", 6)
	_fly_panel.add_child(_fly_box)
	_fly_panel.visible = false
	var p := _panel(parent)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cat_box = GridContainer.new()
	_cat_box.add_theme_constant_override("h_separation", 4)
	_cat_box.add_theme_constant_override("v_separation", 4)
	p.add_child(_cat_box)
	_rebuild_categories()


func _rebuild_categories() -> void:
	for c in _cat_box.get_children():
		c.queue_free()
	_cat_buttons.clear()
	var cats := model.build_bar()
	# Up to 8 categories share one row; more wrap into two so 10-12 fit at 1280 px.
	_cat_box.columns = cats.size() if cats.size() <= 8 else ceili(cats.size() / 2.0)
	for cat in cats:
		var b := _button(_cat_box, cat["label"], 16)
		b.custom_minimum_size = Vector2(96, 34)
		b.pressed.connect(open_category.bind(cat["id"]))
		_cat_buttons[cat["id"]] = b
	_show_flyout()


func open_category(id: String) -> void:
	_open_cat = "" if _open_cat == id else id
	_show_flyout()


func _show_flyout() -> void:
	for c in _fly_box.get_children():
		c.queue_free()
	for id in _cat_buttons:
		_style_button(_cat_buttons[id], id == _open_cat)
	_fly_panel.visible = false
	for cat in model.build_bar():
		if cat["id"] != _open_cat:
			continue
		_fly_panel.visible = true
		for e: Dictionary in cat["entries"]:
			var text: String = e["label"]
			if e["cost"] != "":
				text += "  %s  (%s)" % [e["size"], e["cost"]]
			var b := _button(_fly_box, text, 14)
			b.pressed.connect(_pick.bind(e["kind"], e["id"]))


func _pick(kind: String, id: String) -> void:
	match kind:
		"building": build.set_build(id)
		"road": build.set_mode(BuildController.Mode.ROAD)
		"channel": build.set_mode(BuildController.Mode.CHANNEL)
		"paved": build.set_mode(BuildController.Mode.PAVED)
		"demolish": build.set_mode(BuildController.Mode.DEMOLISH)


# ---------------------------------------------------------------- refresh and input

func refresh() -> void:
	for r in model.resources():
		(_res_labels[r["id"]] as Label).text = r["text"]
	var pop := model.population()
	_pop_label.text = pop["text"]
	_pop_label.add_theme_color_override("font_color", RED if pop["homeless"] > 0 else INK)
	_growth_bar.value = pop["growth"]
	var sp := model.spirit()
	_spirit_bar.value = sp["value"]
	var fill: Color = {"good": Color("78be5a"), "ok": Color("d2a03c"), "bad": Color("d2503c")}[sp["state"]]
	_spirit_bar.add_theme_stylebox_override("fill", _style(fill, Color(0, 0, 0, 0), 2, 0))
	_spirit_label.text = sp["text"]
	_spirit_box.tooltip_text = sp["tooltip"]
	_spirit_bar.tooltip_text = sp["tooltip"]
	_planet_label.text = model.planet()["text"]
	var ep := model.era_panel()
	_era_title.text = ep["title"]
	_era_dimming.text = ep["dimming"]
	_era_gate.text = ep["gate"]
	_era_date.text = driver.status_text() if driver != null else model.clock_text()
	var active: bool = ep["dimming_state"] == "active"
	_era_panel.add_theme_stylebox_override("panel", _style(PANEL_BG, CYAN if active else PANEL_EDGE))
	_moon.visible = ep["dimming_state"] != "none"
	_refresh_overlay_buttons()
	_refresh_selection()
	_refresh_notes()
	_region_map.refresh()


func toggle_region_map() -> void:
	_region_map.toggle()


func _center_region_map() -> void:
	var vp := get_viewport().get_visible_rect().size
	_region_map.position = ((vp - _region_map.size) / 2.0).floor()


func _process(delta: float) -> void:
	if _sel_panel.visible:
		_place_selection_panel()
	if _region_map.visible:
		_center_region_map()
	_acc += delta
	if _acc >= 0.2:
		_acc = 0.0
		refresh()


## True when Esc would still cancel something (build tool, selection, open build flyout): then it is not the menu's.
func has_cancelable() -> bool:
	return _region_map.visible or (build != null and build.mode != BuildController.Mode.NONE) or model.selected_id >= 0 or _open_cat != ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_V: _on_overlay("blight")
			KEY_G: _on_overlay("roads")
			KEY_T: _on_overlay("water")
			KEY_H: _on_overlay("coverage")
			KEY_M: _region_map.toggle()
			KEY_U:
				if model.upgrade():
					refresh()
			KEY_B: open_category("housing" if _open_cat == "" else _open_cat)
			KEY_ESCAPE:
				_region_map.close()
				model.clear_selection()
				_open_cat = ""
				_show_flyout()
				refresh()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if build != null and build.mode == BuildController.Mode.NONE and camera != null:
			var p := camera.get_global_mouse_position()
			model.select_at(Vector2i(floori(p.x / ArtLibrary.TILE), floori(p.y / ArtLibrary.TILE)))
			refresh()
