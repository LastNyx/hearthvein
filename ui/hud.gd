class_name Hud
extends CanvasLayer
## The in-game HUD (hud-rts-spec): top-right goods and clock row; objectives top-left; bottom band (148 px) with
## the minimap, the selection panel (or town summary) and the command grid; notices above the selection panel.
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
const DONE := Color("78be5a")  # a met objective (ticket 126)
## The five overlay keys, the one table both the input and the minimap's labels read (ticket 130b, spec H4).
const OVERLAY_KEYS := {"blight": KEY_V, "roads": KEY_G, "water": KEY_T, "coverage": KEY_H, "grid": KEY_L}

## The Help button of the tools tab (Main opens the help screen).
signal help_requested

var model: HudModel
var build: BuildController
var camera: Camera2D
var _right := RightDrag.new()
var driver: SimDriver
var _font: FontFile
var _body_font: FontFile
## Tightened name fonts for the command grid, by pixel step (ticket 130c).
var _tight_fonts: Dictionary = {}
var _res_labels: Dictionary = {}
var _res_deltas: Dictionary = {}
var _res_icons: Dictionary = {}
## The top-right cluster (ticket 125): the goods panel, its pinned-good row, and the clock row under it.
var goods_panel: PanelContainer
var clock_panel: PanelContainer
var _goods_boxes: Dictionary = {}
var _goods_hold: Control
var _pin_row: HBoxContainer
var _pin_key := "<none>"
var _idle_label: Label
var _clock_date: Label
var _clock_season: Label
var _row_dial: ClockDial
var _pause_button: Button
var _speed_buttons: Array[Button] = []
var _help_button: Button
var _pop_label: Label
var _pop_box: HBoxContainer
var _growth_bar: ProgressBar
var _float: Control
var _spirit_bar: ProgressBar
var _spirit_label: Label
var _spirit_box: Control
var _planet_label: Label
## The bottom-band minimap (ticket 127): the map image, the camera rectangle and the layer/overlay toggles.
var minimap: Minimap
## Top-left objectives panel (ticket 126): the title, the collapsing body, and the one-line collapsed form.
var objectives_panel: PanelContainer
var _objectives_body: VBoxContainer
var _objectives_toggle: Button
var _obj_header: Label
var _obj_collapsed_line: Label
var _obj_rows: Array[HBoxContainer] = []
var _obj_icons: Array[TextureRect] = []
var _obj_labels: Array[Label] = []
var _obj_bars: Array[ProgressBar] = []
var _obj_values: Array[Label] = []
var _obj_dimming: Label
var _obj_light: Label
var _notes_box: VBoxContainer
var _notes_key := ""
## The fixed bottom-centre panel (ticket 128): the selected building or, with nothing selected, the town summary.
var _sel_panel: PanelContainer
var _sel_content: HBoxContainer
var _sel_title: Label
var _sel_tier: Label
var _sel_sub: Label
var _sel_sprite: TextureRect
var _sel_pic: PanelContainer
var _sel_makes: Label
var _sel_uses: Label
var _sel_workers_title: Label
var _sel_pips: HBoxContainer
var _sel_workers_text: Label
var _sel_night_row: HBoxContainer
var _sel_night_pips: HBoxContainer
var _sel_night_text: Label
var _sel_in_bar: ProgressBar
var _sel_in_text: Label
var _sel_in_row: HBoxContainer
var _sel_out_bar: ProgressBar
var _sel_out_text: Label
var _sel_out_row: HBoxContainer
var _sel_workers_row: HBoxContainer
var _sel_sprite_key := ""
var _sel_body: VBoxContainer
var _sel_scroll: ScrollContainer
var _sel_body_key := ""
var _sel_halt: Label
var _sel_warn: Label
var _sel_up_cost: HBoxContainer
var _sel_up_row: VBoxContainer
var _sel_up_key := ""
var _sel_up_reason: Label
var _sel_up_btn: Button
var _prio_buttons: Dictionary = {}
var _sel_prio_title: Label
var _prio_row: HBoxContainer
var _town_panel: HBoxContainer
var _town_name: Label
var _town_sub: Label
var _town_people: Label
var _town_beds: Label
var _town_idle: Label
var _town_nights: Label
var _town_planet_trend: Label
var _town_hint: Label
var _planet_bar: ProgressBar
var _region_map: RegionMap
## The command grid (ticket 129, hud-rts-spec H2-H4): 5x3 cells at the bottom-right, top level or a category pane.
var _cmd_panel: PanelContainer
var _cmd_title: Label
var _cmd_grid: GridContainer
var _cmd_cells: Array[Button] = []
var _grid_page := ""
var _grid_key := ""
var _grid_focus_id := ""
var workforce_page: WorkforcePage
var resources_page: ResourcesPage
var tutorial_panel: TutorialPanel
var hint_cards: HintCards
var era_card: EraCard
var _right_col: VBoxContainer
var _pulsed: Button
var _pulse_t := 0.0
var _acc := 0.0
## Hover tooltips (ticket 81): a build button or a placed building under the mouse, shown after TIP_DELAY seconds.
## Gap between HUD panels and the screen edge.
const MARGIN := 6.0
const TIP_DELAY := 0.4
const TIP_WIDTH := 320.0
const NO_TILE := Vector2i(-99999, -99999)
var _tip_panel: PanelContainer
var _tip_box: VBoxContainer
var _tip_btn: Button
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _detail_key := ""
var _detail_title := ""
var _tip_key := ""
var _tip_text := ""
var _tip_t := 0.0
var _mid_down := false


func setup(m: HudModel, b: BuildController, cam: Camera2D, d: SimDriver) -> void:
	model = m
	build = b
	if build != null:
		build.mode_changed.connect(_refresh_active_tool)
	camera = cam
	driver = d
	if driver != null:
		driver.speed_changed.connect(func(_s: int) -> void: _refresh_clock_buttons())
	layer = 10
	_font = _pixel_font(FONT_PATH)
	_body_font = _pixel_font(BODY_FONT_PATH)
	var root := Control.new()
	root.name = "HudRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_objectives_panel(root)
	_build_top_bar(root)
	_build_bar(root)
	_float = Control.new()
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float)
	_float.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_notes(_float)
	_region_map = RegionMap.new()
	_float.add_child(_region_map)
	_region_map.setup(self, model)
	_region_map.resized.connect(_center_region_map)
	workforce_page = WorkforcePage.new()
	_float.add_child(workforce_page)
	workforce_page.setup(self, model)
	resources_page = ResourcesPage.new()
	_float.add_child(resources_page)
	resources_page.setup(self, model)
	_build_tooltip()
	_build_detail()
	tutorial_panel = TutorialPanel.new()
	_right_col.add_child(tutorial_panel)
	tutorial_panel.setup(self, model.s, _float)
	model.s.events.subscribe("era_changed", func(_e: Dictionary) -> void:
		_grid_key = ""
		refresh())
	model.layer_changed.connect(func(_l: int) -> void:
		_grid_key = ""
		refresh())
	refresh()


## The hint cards (right edge, under the era and tutorial panels) and the era card (centred); Main adds them once it has
## the settings. Tests and shot scripts that build a Hud without settings simply have neither.
func add_cards(settings: GameSettings) -> void:
	hint_cards = HintCards.new()
	_right_col.add_child(hint_cards)
	hint_cards.setup(self, model.s, settings)
	era_card = EraCard.new()
	_float.add_child(era_card)
	era_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	era_card.setup(self, model.s, driver)


# ---------------------------------------------------------------- building blocks

func _style(bg: Color = PANEL_BG, edge: Color = PANEL_EDGE, radius: int = 6, border: int = 2,
		pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
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
	# load(), not the raw .ttf bytes: exports pack only the imported font, so reading the file gave the default font
	# in every exported build up to 1.1.2.
	var f := (load(path) as FontFile).duplicate() as FontFile
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


## One HUD line. A line that is all goods ("Cost: 14 Wood, 21 Stone", "Waiting for materials: 0/10 lumen") draws the
## good's icon before each number (ticket 112); anything else stays one label, wrapped to `wrap_width` when given.
func _hud_line(parent: Node, text: String, color: Color, size: int = 14, wrap_width: float = 0.0) -> Control:
	var segs := model.line_segments(text)
	if segs.is_empty():
		var l := _label(parent, size, color)
		l.text = text
		if wrap_width > 0.0:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(wrap_width, 0)
		return l
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	for seg: Dictionary in segs:
		if seg.has("good") and model.icon_id(str(seg["good"])) != "":
			_icon(row, model.icon_id(str(seg["good"])), size + 6)
		var l := _label(row, size, color)
		l.text = str(seg["text"])
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


## Rebuilds a container as one HUD line (used for lines that change while the panel stays open).
func _set_hud_line(box: Container, text: String, color: Color, size: int = 14) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	_hud_line(box, text, color, size)


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


func _style_button(b: Button, on: bool, pad: int = 12) -> void:
	var edge := GOLD if on else Color(0, 0, 0, 0)
	var boxes: Array[StyleBoxFlat] = [
		_style(Color(0.275, 0.235, 0.2) if on else Color(0.173, 0.149, 0.133), edge, 5, 2, pad),
		_style(Color(0.33, 0.28, 0.23), GOLD if on else PANEL_EDGE, 5, 2, pad),
		_style(Color(0.33, 0.28, 0.23), GOLD, 5, 2, pad)]
	if b.has_meta("compact"):
		for sb in boxes:
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
		b.add_theme_stylebox_override("disabled", boxes[0])
	b.add_theme_stylebox_override("normal", boxes[0])
	b.add_theme_stylebox_override("hover", boxes[1])
	b.add_theme_stylebox_override("pressed", boxes[2])


# ---------------------------------------------------------------- top bar

## Ticket 125 (hud-rts-spec H5): the old full-width bar is gone. A compact cluster sits at the top-right: people,
## food, wood, stone, Lumen, gold, the pinned goods and a Goods button, with the clock row in its own panel under it.
func _build_top_bar(parent: Node) -> void:
	var stack := VBoxContainer.new()
	stack.name = "TopRight"
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stack)
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stack.offset_right = -MARGIN
	stack.offset_top = MARGIN
	_right_col = stack
	_build_goods_panel(stack)
	_build_clock_panel(stack)


func _build_goods_panel(parent: Node) -> void:
	goods_panel = _panel(parent)
	goods_panel.name = "TopGoods"
	goods_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	goods_panel.add_child(row)
	var pop := HBoxContainer.new()
	pop.add_theme_constant_override("separation", 6)
	pop.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(pop)
	_pop_box = pop
	_icon(pop, "pop")
	var people := VBoxContainer.new()
	people.add_theme_constant_override("separation", 0)
	people.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pop.add_child(people)
	_pop_label = _label(people, 17)
	_idle_label = _label(people, 12, DIM)
	_growth_bar = ProgressBar.new()  # fills toward the next citizen
	_growth_bar.custom_minimum_size = Vector2(46, 8)
	_growth_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_growth_bar.show_percentage = false
	_growth_bar.max_value = 1.0
	_growth_bar.add_theme_stylebox_override("background", _style(Color(0.235, 0.196, 0.196), Color(0, 0, 0, 0.6), 2, 1))
	_growth_bar.add_theme_stylebox_override("fill", _style(Color("78be5a"), Color(0, 0, 0, 0), 2, 0))
	_growth_bar.tooltip_text = "Growth toward the next citizen"
	pop.add_child(_growth_bar)
	# One widget per top-bar good (ticket 112 icons, value over delta). The five core goods stay in the row; the four
	# others wait hidden until the Resources page pins them (ticket 125).
	for k in HudModel.RESOURCES:
		_goods_boxes[k] = _goods_box(row, k)
	_goods_hold = Control.new()
	_goods_hold.visible = false
	goods_panel.add_child(_goods_hold)
	_pin_row = HBoxContainer.new()
	_pin_row.add_theme_constant_override("separation", 12)
	row.add_child(_pin_row)
	var goods_btn := _button(row, "Goods (E)", 13)
	goods_btn.name = "GoodsButton"
	goods_btn.tooltip_text = "Open the Resources page (E)"
	goods_btn.pressed.connect(func() -> void: resources_page.toggle())
	_refresh_pins()


func _goods_box(parent: Node, k: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	var ic := _icon(box, k, 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_res_icons[k] = ic
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(col)
	_res_labels[k] = _label(col, 17)
	_res_deltas[k] = _label(col, 12, DIM)
	var gd := model.s.registry.get_good("lumen_cells" if k == "cells" else k)
	box.tooltip_text = "%s stock and its change over the last day (click for the Resources page)" % (gd.display_name if gd != null else k)
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			box.accept_event()
			resources_page.open_for(k))
	return box


## Puts the pinned goods in the pin row, oldest first; the rest wait hidden (ticket 125).
func _refresh_pins() -> void:
	var key := ",".join(model.pinned())
	if key == _pin_key:
		return
	_pin_key = key
	var keep := model.pinned()
	for k in _goods_boxes:
		if HudModel.CORE_TOP.has(k):
			continue
		var box: Control = _goods_boxes[k]
		if keep.has(k):
			if box.get_parent() != _pin_row:
				box.reparent(_pin_row)
			box.visible = true
		else:
			if box.get_parent() != _goods_hold:
				box.reparent(_goods_hold)
			box.visible = false
	for id in keep:  # oldest first, so the row reads in pin order
		_pin_row.move_child(_goods_boxes[id], -1)
	_pin_row.visible = not keep.is_empty()


## Clock row (ticket 125, H5): dial, "Day N, HH:MM" over "Year N, Season", pause, 1x/2x/3x (current lit), "?" (F1).
## Spirit and planet health moved to the town summary of the bottom band (ticket 128).
func _build_clock_panel(parent: Node) -> void:
	clock_panel = _panel(parent)
	clock_panel.name = "TopClock"
	clock_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	clock_panel.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_row_dial = ClockDial.new()
	_row_dial.custom_minimum_size = Vector2(56, 36)
	_row_dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row_dial.tooltip_text = "The sun is up 05-21, the moon 21-05"
	row.add_child(_row_dial)
	var dates := VBoxContainer.new()
	dates.add_theme_constant_override("separation", 0)
	dates.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dates)
	_clock_date = _label(dates, 17)
	_clock_season = _label(dates, 12, DIM)
	_pause_button = _button(row, "Pause", 13)
	_pause_button.tooltip_text = "Pause (Space)"
	_pause_button.pressed.connect(func() -> void:
		if driver != null:
			driver.toggle_pause())
	for i in range(1, 4):
		var speed := i
		var b := _button(row, "%dx" % speed, 13)
		b.tooltip_text = "Speed %dx (%d)" % [speed, speed]
		b.pressed.connect(func() -> void:
			if driver != null:
				driver.set_speed(speed))
		_speed_buttons.append(b)
	_help_button = _button(row, "?", 16)
	_help_button.name = "HelpButton"
	_help_button.tooltip_text = "Help (F1)"
	_help_button.pressed.connect(func() -> void: help_requested.emit())
	# Ticket 128 moved Spirit and planet health from this row to the town summary in the bottom band.


## An overlay key (V G T H L) toggles the same state as the minimap's buttons.
func _on_overlay(id: String) -> void:
	model.toggle_overlay(id)
	minimap.refresh_toggles()


# ---------------------------------------------------------------- objectives panel (ticket 126)

## The top-left panel of spec H6: "Objectives" with a collapse button, then a row per gate part (icon, label, bar,
## progress) or, at the last era, the win objectives, and the Dimming lines under them. Collapsed it is one line.
func _build_objectives_panel(parent: Node) -> void:
	objectives_panel = _panel(parent)
	objectives_panel.name = "Objectives"
	objectives_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	objectives_panel.offset_left = MARGIN
	objectives_panel.offset_top = MARGIN
	objectives_panel.custom_minimum_size = Vector2(340, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	objectives_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label(head, 18, GOLD)
	title.text = "Objectives"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_objectives_toggle = _button(head, "-", 15)
	_objectives_toggle.name = "ObjectivesCollapse"
	_objectives_toggle.tooltip_text = "Collapse or expand the objectives"
	_objectives_toggle.pressed.connect(func() -> void:
		model.toggle_objectives_collapsed()
		_refresh_objectives())
	_obj_collapsed_line = _label(v, 13)
	_obj_collapsed_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objectives_body = VBoxContainer.new()
	_objectives_body.add_theme_constant_override("separation", 4)
	v.add_child(_objectives_body)
	_obj_header = _label(_objectives_body, 12, CYAN)
	_obj_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in 3:  # three gate parts, three win objectives
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_objectives_body.add_child(row)
		_obj_rows.append(row)
		_obj_icons.append(_icon(row, "pop", 20))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(col)
		_obj_labels.append(_label(col, 13))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 8)
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.add_theme_stylebox_override("background", _style(Color(0.235, 0.196, 0.196), Color(0, 0, 0, 0.6), 2, 1))
		bar.add_theme_stylebox_override("fill", _style(DONE, Color(0, 0, 0, 0), 2, 0))
		col.add_child(bar)
		_obj_bars.append(bar)
		var value := _label(row, 13)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(96, 0)
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_obj_values.append(value)
	_obj_dimming = _label(_objectives_body, 13, CYAN)
	_obj_dimming.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_light = _label(_objectives_body, 12, DIM)
	_obj_light.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Copies the objectives rows and Dimming lines onto the panel, or shows the one-line collapsed form.
func _refresh_objectives() -> void:
	var collapsed := model.objectives_collapsed()
	_objectives_toggle.text = "+" if collapsed else "-"
	_obj_collapsed_line.visible = collapsed
	_obj_collapsed_line.text = model.objectives_collapsed_text()
	_objectives_body.visible = not collapsed
	if collapsed:
		return
	_obj_header.text = model.objectives_header()
	var rows := model.objectives()
	for i in _obj_rows.size():
		var row := _obj_rows[i]
		if i >= rows.size():
			row.visible = false
			continue
		row.visible = true
		var r: Dictionary = rows[i]
		var done := bool(r["done"])
		var col := DONE if done else INK
		_obj_icons[i].texture = ArtLibrary.texture(ArtLibrary.manifest()["icons"][_objective_icon(str(r["kind"]))])
		_obj_labels[i].text = str(r["label"])
		_obj_labels[i].add_theme_color_override("font_color", col)
		_obj_bars[i].max_value = maxf(1.0, float(r["max"]))
		_obj_bars[i].value = clampf(float(r["value"]), 0.0, float(r["max"]))
		_obj_bars[i].add_theme_stylebox_override("fill", _style(col, Color(0, 0, 0, 0), 2, 0))
		_obj_values[i].text = _objective_value_text(r)
		var value_col := col
		if str(r["kind"]) == "landmark" and not done:
			value_col = RED
		_obj_values[i].add_theme_color_override("font_color", value_col)
	var lines := model.objectives_dimming_lines()
	var active := model.dimming_state() == "active"
	_obj_dimming.text = lines[0] if lines.size() > 0 else ""
	_obj_dimming.visible = _obj_dimming.text != ""
	_obj_dimming.add_theme_color_override("font_color", RED if active else CYAN)
	_obj_light.text = lines[1] if lines.size() > 1 else ""
	_obj_light.visible = _obj_light.text != ""
	_obj_light.add_theme_color_override("font_color", RED if active else DIM)


func _objective_icon(kind: String) -> String:
	match kind:
		"gold": return "gold"
		"landmark", "skyheart": return "lumen"
		"great_dimming": return "moon"
		"planet": return "planet"
	return "pop"


func _objective_value_text(r: Dictionary) -> String:
	match str(r["kind"]):
		"landmark":
			return "built" if bool(r["done"]) else "not built"
		"great_dimming":
			return "survived" if bool(r["done"]) else "not yet"
		"planet":
			return "%d%% / %d%%" % [int(r["value"]), int(r["max"])]
	return "%d / %d" % [int(r["value"]), int(r["max"])]


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
		var note := _label(p, 14, INK)
		note.text = it["text"]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(440, 0)
	_place_notes()


## Stacks the notices just above the bottom-centre panel, newest at the bottom (ticket 128).
func _place_notes() -> void:
	if _notes_box == null or _sel_panel == null or not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := _notes_box.get_combined_minimum_size()
	_notes_box.size = sz
	var panel := _sel_panel.get_global_rect()
	var pos := Vector2(panel.get_center().x - sz.x * 0.5, panel.position.y - 6.0 - sz.y)
	pos.x = clampf(pos.x, 6.0, maxf(6.0, vp.x - sz.x - 6.0))
	_notes_box.position = pos


# ---------------------------------------------------------------- selected building

## The fixed bottom-centre panel of spec H7 (mockups hud_town_day / hud_nothing_selected): a big sprite beside the
## selected building's rows, or the town summary when nothing is selected. It never moves; the notes stack above it.
func _build_selection_panel(parent: Node) -> void:
	_sel_panel = _panel(parent)
	_sel_panel.name = "SelectionPanel"
	_sel_panel.custom_minimum_size = Vector2(0, BAND_HEIGHT - MARGIN)
	_sel_panel.add_theme_stylebox_override("panel", _style(PANEL_BG, PANEL_EDGE, 6, 2, 10))
	_sel_content = HBoxContainer.new()
	_sel_content.add_theme_constant_override("separation", 10)
	_sel_panel.add_child(_sel_content)
	var row := _sel_content
	_sel_pic = PanelContainer.new()
	_sel_pic.name = "SelectionPic"
	_sel_pic.custom_minimum_size = SEL_PIC
	# No inner margins: the sprite's box is exactly SEL_PIC, so the largest whole scale uses all of it (130b).
	var pic_sb := _style(Color(0.16, 0.21, 0.14), Color(0, 0, 0, 0), 4, 0)
	pic_sb.content_margin_left = 0.0
	pic_sb.content_margin_right = 0.0
	pic_sb.content_margin_top = 0.0
	pic_sb.content_margin_bottom = 0.0
	_sel_pic.add_theme_stylebox_override("panel", pic_sb)
	_sel_pic.clip_contents = true
	_sel_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel_pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_sel_pic)
	_sel_sprite = TextureRect.new()
	_sel_sprite.name = "SelectionSprite"
	_sel_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sel_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sel_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sel_sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sel_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel_pic.add_child(stack)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.add_child(_sel_sprite)
	# Left column: name, tier, kind, workers, status. Right column: makes, buffers, priority, upgrade.
	var info := VBoxContainer.new()
	info.name = "SelectionLeft"
	info.add_theme_constant_override("separation", 0)
	info.custom_minimum_size = Vector2(SEL_LEFT_W, 0)
	row.add_child(info)
	# The name row: the name and, beside it as in the mockup, the tier badge (ticket 130b).
	var title_row := HBoxContainer.new()
	title_row.name = "SelectionTitleRow"
	title_row.add_theme_constant_override("separation", 6)
	info.add_child(title_row)
	# The title keeps its full width so the badge sits right after the name, as in the mockup; the font drops to
	# the body size first, so it fits its column.
	_sel_title = _label(title_row, 22, CYAN)
	var badge := PanelContainer.new()
	badge.name = "TierBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _style(Color(0.09, 0.075, 0.07, 0.9), GOLD, 4, 1, 4))
	title_row.add_child(badge)
	_sel_tier = _label(badge, 13, GOLD)
	_sel_sub = _label(info, 14, DIM)
	_sel_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_workers_row = HBoxContainer.new()
	_sel_workers_row.name = "ShiftDay"
	_sel_workers_row.add_theme_constant_override("separation", 6)
	info.add_child(_sel_workers_row)
	_sel_workers_title = _label(_sel_workers_row, 14, DIM)
	_sel_workers_title.text = "Day"
	_sel_pips = HBoxContainer.new()
	_sel_pips.add_theme_constant_override("separation", 2)
	_sel_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sel_workers_row.add_child(_sel_pips)
	_sel_workers_text = _label(_sel_workers_row, 14, INK)
	# The night row (ticket 136): only buildings with night worker slots show it, moon icon first as in the mockup.
	_sel_night_row = HBoxContainer.new()
	_sel_night_row.name = "ShiftNight"
	_sel_night_row.add_theme_constant_override("separation", 6)
	_sel_night_row.visible = false
	info.add_child(_sel_night_row)
	_icon(_sel_night_row, "moon", 14)
	var night_title := _label(_sel_night_row, 14, DIM)
	night_title.text = "Night"
	_sel_night_pips = HBoxContainer.new()
	_sel_night_pips.add_theme_constant_override("separation", 2)
	_sel_night_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sel_night_row.add_child(_sel_night_pips)
	_sel_night_text = _label(_sel_night_row, 14, INK)
	_sel_halt = _label(info, 14, PURPLE)
	_sel_halt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_halt.max_lines_visible = 2
	_sel_halt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_halt.custom_minimum_size = Vector2(SEL_LEFT_W, 0)
	_sel_warn = _label(info, 14, RED)
	_sel_warn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_warn.custom_minimum_size = Vector2(SEL_LEFT_W, 0)
	# The remaining lines (advice, residents, stored goods, site progress) take what height is left and scroll.
	_sel_scroll = ScrollContainer.new()
	_sel_scroll.name = "SelectionLines"
	_sel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sel_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_sel_scroll.custom_minimum_size = Vector2(SEL_LEFT_W, 18)
	info.add_child(_sel_scroll)
	_sel_body = VBoxContainer.new()
	_sel_body.add_theme_constant_override("separation", 0)
	_sel_scroll.add_child(_sel_body)
	var right := VBoxContainer.new()
	right.name = "SelectionRight"
	right.add_theme_constant_override("separation", 2)
	right.custom_minimum_size = Vector2(SEL_RIGHT_W, 0)
	row.add_child(right)
	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 10)
	flow.custom_minimum_size = Vector2(SEL_RIGHT_W, 0)
	right.add_child(flow)
	_sel_makes = _label(flow, 14, INK)
	_sel_uses = _label(flow, 14, DIM)
	_sel_uses.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_uses.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_in_row = _bar_row(right, "In")
	_sel_in_bar = _sel_in_row.get_meta("bar")
	_sel_in_text = _sel_in_row.get_meta("value")
	_sel_out_row = _bar_row(right, "Out")
	_sel_out_bar = _sel_out_row.get_meta("bar")
	_sel_out_text = _sel_out_row.get_meta("value")
	# The priority title rides above its buttons: the label + four buttons on one line would widen the panel past
	# what the bottom band leaves for the bigger selection sprite (ticket 130b).
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 1)
	right.add_child(pcol)
	_sel_prio_title = _label(pcol, 13, DIM)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 3)
	pcol.add_child(prow)
	_prio_row = prow
	for p in ["low", "normal", "high"]:
		var b := _compact_button(prow, HudModel.PRIORITY_LABELS[p])
		b.pressed.connect(func() -> void: model.set_priority(p))
		_prio_buttons[p] = b
	var pause := _compact_button(prow, "Pause")
	pause.pressed.connect(func() -> void: model.toggle_pause())
	_prio_buttons["paused"] = pause
	# Cost under the button, not beside it: the pair on one line is the widest thing in the right column and the
	# bigger picture needs the room (ticket 130b).
	var urow := VBoxContainer.new()
	urow.name = "UpgradeRow"
	urow.add_theme_constant_override("separation", 1)
	right.add_child(urow)
	_sel_up_row = urow
	_sel_up_btn = _compact_button(urow, "Upgrade (U)")
	_sel_up_btn.pressed.connect(func() -> void: model.upgrade())
	_sel_up_cost = HBoxContainer.new()
	_sel_up_cost.add_theme_constant_override("separation", 3)
	_sel_up_cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	urow.add_child(_sel_up_cost)
	_sel_up_reason = _label(info, 14, DIM)
	_sel_up_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_up_reason.custom_minimum_size = Vector2(SEL_LEFT_W, 0)
	_build_town_summary()
	_sel_panel.visible = true


## A short button for the crowded bottom band: little vertical padding (kept by _style_button through the meta).
func _compact_button(parent: Node, text: String) -> Button:
	var b := _button(parent, text, 13)
	b.set_meta("compact", true)
	_style_button(b, false, 6)
	return b


## One "In [bar] 22 / 40" row of the selection panel; the bar and value ride on the row's meta for refresh.
func _bar_row(parent: Container, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var l := _label(row, 12, DIM)
	l.text = title
	l.custom_minimum_size = Vector2(26, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(60, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("background", _style(Color(0.235, 0.196, 0.196), Color(0, 0, 0, 0.6), 2, 1))
	bar.add_theme_stylebox_override("fill", _style(GOLD, Color(0, 0, 0, 0), 2, 0))
	row.add_child(bar)
	var value := _label(row, 12, INK)
	value.custom_minimum_size = Vector2(64, 0)
	row.set_meta("bar", bar)
	row.set_meta("value", value)
	return row


## The town summary half of the panel: name, era and date, the big population numbers, Spirit and planet health.
func _build_town_summary() -> void:
	_town_panel = HBoxContainer.new()
	_town_panel.name = "TownSummary"
	_town_panel.add_theme_constant_override("separation", 16)
	_sel_panel.add_child(_town_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	_town_panel.add_child(left)
	_town_name = _label(left, 22, CYAN)
	_town_name.name = "TownName"
	_town_sub = _label(left, 14, DIM)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 22)
	left.add_child(nums)
	_town_people = _number_block(nums, "pop", "People")
	_town_beds = _number_block(nums, "pop", "Beds")
	_town_idle = _number_block(nums, "pop", "Idle")
	_town_nights = _label(left, 12, DIM)
	_town_nights.name = "TownNights"
	_town_hint = _label(left, 12, DIM)
	_town_hint.name = "TownHint"
	_town_hint.clip_text = true
	_town_hint.custom_minimum_size = Vector2(TOWN_LEFT_W, 0)
	var meters := VBoxContainer.new()
	meters.add_theme_constant_override("separation", 4)
	meters.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_town_panel.add_child(meters)
	_spirit_box = _meter_block(meters, "spirit", "Spirit")
	_spirit_bar = _spirit_box.get_meta("bar")
	_spirit_label = _spirit_box.get_meta("value")
	_spirit_box.tooltip_text = ""  # filled from the model each refresh
	_planet_bar = _meter_block(meters, "planet", "Planet").get_meta("bar")
	var planet_block := _planet_bar.get_parent().get_parent()
	_planet_label = planet_block.get_meta("value")
	_town_planet_trend = _label(_planet_bar.get_parent(), 12, DIM)
	planet_block.tooltip_text = "Planet health and its change over the last year"
	_town_panel.visible = false


## A big number with its caption under it ("62" over "People"), an icon on the left like the mockup.
func _number_block(parent: Node, icon: String, caption: String) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	_icon(box, icon, 26)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)
	var n := _label(col, 22, INK)
	var c := _label(col, 12, DIM)
	c.text = caption
	return n


## An icon and label over a bar, with the value text on the right ("74 / 100"). The bar and value sit in the block's
## meta so the town summary can refresh them.
func _meter_block(parent: Node, icon: String, caption: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	_icon(box, icon, 22)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(col)
	var l := _label(col, 12, DIM)
	l.text = caption
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(80, 12)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.add_theme_stylebox_override("background", _style(Color(0.235, 0.196, 0.196), Color(0, 0, 0, 0.6), 2, 1))
	col.add_child(bar)
	var value := _label(box, 13, INK)
	value.custom_minimum_size = Vector2(64, 0)
	box.set_meta("bar", bar)
	box.set_meta("value", value)
	return box


func _refresh_selection() -> void:
	var sel := model.selection()
	var has := not sel.is_empty()
	_sel_content.visible = has
	_town_panel.visible = not has
	if not has:
		_refresh_town()
		return
	var b := model.selected()
	if b == null:
		return
	var art := b.tier_art_id(model.s.registry)
	var entry: Variant = ArtLibrary.manifest()["buildings"].get(art if art != "" else str(b.def.id))
	if entry == null:
		entry = ArtLibrary.manifest()["buildings"].get(str(b.def.id))
	var sprite_key := "%s:%d" % [b.def.id, b.tier]
	if entry != null and sprite_key != _sel_sprite_key:
		_sel_sprite_key = sprite_key
		var tex_size := Vector2(float(entry["w"]), float(entry["h"]))
		var scale := detail_scale(tex_size, SEL_PIC)
		_sel_sprite.texture = ArtLibrary.texture(str(entry["file"]))
		_sel_sprite.custom_minimum_size = tex_size * scale
	_sel_title.text = sel["title"]
	_sel_title.tooltip_text = sel["title"]
	# A long name drops to the small font before it would be trimmed; the tier badge shares its row (ticket 130b).
	var big_w := _font.get_string_size(_sel_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px_size(22)).x
	var long_name := big_w > SEL_LEFT_W - SEL_BADGE_W
	_sel_title.add_theme_font_override("font", _px_font(16 if long_name else 22))
	_sel_title.add_theme_font_size_override("font_size", _px_size(16 if long_name else 22))
	_sel_tier.text = sel["tier_text"]
	_sel_sub.text = sel["subtitle"]
	_sel_makes.text = "Makes %s" % sel["makes"] if sel["makes"] != "" else ""
	_sel_makes.visible = sel["makes"] != ""
	_sel_makes.tooltip_text = _sel_makes.text  # the row may trim at the narrow right column
	_sel_uses.text = sel["uses"]
	_sel_uses.visible = sel["uses"] != ""
	_sel_uses.tooltip_text = sel["uses"]
	_sel_workers_row.visible = bool(sel["show_workers"])
	_sel_workers_text.text = sel["workers_text"]
	_fill_pips(_sel_pips, int(sel["workers_filled"]), int(sel["workers_slots"]))
	_sel_night_row.visible = bool(sel["show_night"])
	_sel_night_text.text = sel["night_text"]
	_fill_pips(_sel_night_pips, int(sel["night_filled"]), int(sel["night_slots"]))
	_sel_in_row.visible = sel["in_text"] != ""
	if sel["in_text"] != "":
		_sel_in_bar.max_value = maxf(0.001, float(sel["in_max"]))
		_sel_in_bar.value = float(sel["in_value"])
		_sel_in_text.text = sel["in_text"]
	_sel_out_row.visible = sel["out_text"] != ""
	if sel["out_text"] != "":
		_sel_out_bar.max_value = maxf(0.001, float(sel["out_max"]))
		_sel_out_bar.value = float(sel["out_value"])
		_sel_out_text.text = sel["out_text"]
	var status: String = sel["status"]
	var advice: String = sel["advice"] if sel["halt"] != "" else ""
	_sel_halt.text = sel["halt"] if sel["halt"] != "" else status
	_sel_halt.tooltip_text = _sel_halt.text if advice == "" else "%s\n%s" % [_sel_halt.text, advice]
	_sel_halt.visible = _sel_halt.text != ""
	_sel_halt.add_theme_color_override("font_color", DONE if status == "Working" else PURPLE)
	var body: Array = (sel["extra"] if not sel["site"] else sel["lines"]).duplicate()
	if advice != "":
		body.push_front(advice)
	var body_key := "\n".join(body.map(func(l: String) -> String: return l))
	if body_key != _sel_body_key:
		_sel_body_key = body_key
		for c in _sel_body.get_children():
			_sel_body.remove_child(c)
			c.queue_free()
		for l: String in body:
			_hud_line(_sel_body, l, INK, 14)
	_sel_prio_title.text = "Priority"
	_sel_prio_title.tooltip_text = sel["priority_label"]  # "Work priority" or "Build priority"
	_sel_prio_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_sel_prio_title.visible = sel["show_priority"]
	_prio_row.visible = sel["show_priority"]
	_sel_warn.text = sel["warn"]
	_sel_warn.tooltip_text = sel["warn"]
	_sel_warn.visible = sel["warn"] != ""
	_fit_selection_lines(sel)
	var show_up: bool = sel["show_upgrade"]
	_sel_up_row.visible = show_up
	_sel_up_reason.visible = show_up and not sel["can_upgrade"]
	if show_up:
		var up_text := "%s: %s" % [sel["next_name"], sel["next_cost"]]
		if up_text != _sel_up_key:
			_sel_up_key = up_text
			_set_hud_line(_sel_up_cost, up_text, GOLD, 14)
		_sel_up_btn.tooltip_text = "Upgrade to %s (U)" % sel["next_name"]
		_sel_up_btn.disabled = not sel["can_upgrade"]
		_sel_up_reason.text = sel["upgrade_reason"]
	for p in _prio_buttons:
		var on: bool = sel["paused"] if p == "paused" else (sel["priority"] == p and not sel["paused"])
		_style_button(_prio_buttons[p], on)


## The scrolling line box gets the height the left column has left (title, kind, workers, status and warning first).
func _fit_selection_lines(sel: Dictionary) -> void:
	var line := 18.0
	var used := 32.0 + line  # title + kind
	if _sel_workers_row.visible:
		used += line
	if _sel_night_row.visible:
		used += line
	if _sel_halt.visible:
		var w := _sel_halt.get_theme_font("font").get_string_size(_sel_halt.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				_sel_halt.get_theme_font_size("font_size")).x
		used += line * minf(2.0, ceilf(w / SEL_LEFT_W))
	if _sel_warn.visible:
		used += line
	var room := BAND_HEIGHT - MARGIN - SEL_PAD - used
	_sel_scroll.visible = room >= line  # no room: the halt tooltip and the panel lines are on hover
	_sel_scroll.custom_minimum_size = Vector2(SEL_LEFT_W, maxf(line, floorf(room / line) * line))
	_sel_scroll.tooltip_text = "\n".join(_sel_body_key.split("\n")) if _sel_body_key != "" else ""


## A shift's worker pips: one filled square per worker, empty ones for the free slots (day and night rows alike).
func _fill_pips(into: HBoxContainer, filled: int, slots: int) -> void:
	for c in into.get_children():
		into.remove_child(c)
		c.queue_free()
	for i in slots:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(8, 12)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", _style(DONE if i < filled else Color(0.25, 0.22, 0.2),
				Color(0, 0, 0, 0), 2, 0, 0))
		into.add_child(p)


## The town summary values when nothing is selected (ticket 128).
func _refresh_town() -> void:
	var t := model.town_summary()
	_town_name.text = t["name"]
	_town_sub.text = "%s era, %s" % [t["era"], t["date"]]
	_town_people.text = str(t["people"])
	_town_beds.text = str(t["beds"])
	_town_idle.text = str(t["idle"])
	_town_nights.text = t["nights_text"]
	_spirit_bar.value = float(t["spirit"])
	var fill: Color = {"good": DONE, "ok": Color("d2a03c"), "bad": Color("d2503c")}[t["spirit_state"]]
	_spirit_bar.add_theme_stylebox_override("fill", _style(fill, Color(0, 0, 0, 0), 2, 0))
	_spirit_label.text = t["spirit_text"]
	_spirit_box.tooltip_text = t["spirit_tooltip"]
	_planet_bar.value = float(t["planet"])
	_planet_bar.add_theme_stylebox_override("fill", _style(DONE if int(t["planet"]) >= 50 else RED,
			Color(0, 0, 0, 0), 2, 0))
	_planet_label.text = t["planet_text"]
	_town_planet_trend.text = t["planet_trend"]
	_town_hint.text = t["hint"]
	_town_hint.tooltip_text = t["hint"]


# ---------------------------------------------------------------- command grid (ticket 129)

## The bottom band of hud-rts-spec H7: the minimap on the left, the selection panel (or town summary) centred, and the
## command grid on the right.
const BAND_HEIGHT := 148.0
const SEL_PIC := Vector2(128, 128)
const SEL_LEFT_W := 190.0
## Room the tier badge needs beside the name before the title drops to the body font (ticket 130b).
const SEL_BADGE_W := 66.0
const SEL_RIGHT_W := 254.0
const TOWN_LEFT_W := 340.0
## Panel border and margins that eat into BAND_HEIGHT - MARGIN.
const SEL_PAD := 18.0
const CELL_SIZE := Vector2(80, 39)
const CELL_GAP := 1
const CELL_PIC := 18
## The cell's own border: no part of a cell may sit on it (ticket 130c).
const CELL_BORDER := 2
## The hotkey and the short cost sit this far inside the border, off the cell's edge (ticket 130c).
const CELL_INSET := 3
## Grid names: Tiny5 at 14 is readable, 12 is the smallest allowed; a name too long for the cell steps down to 12
## and, if still too long, has its glyph spacing tightened rather than shrunk further (ticket 130c).
const CELL_NAME_SIZE := 14
const CELL_NAME_MIN := 12
const CELL_KEY_SIZE := 12
const GRID_COLUMNS := 5


func _build_bar(parent: Node) -> void:
	var band := HBoxContainer.new()
	band.name = "BottomBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_constant_override("separation", 6)
	parent.add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.grow_vertical = Control.GROW_DIRECTION_BEGIN
	band.offset_left = MARGIN
	band.offset_right = -MARGIN
	band.offset_bottom = -MARGIN
	band.offset_top = -BAND_HEIGHT
	minimap = Minimap.new()
	band.add_child(minimap)
	minimap.setup(self, model, camera)
	var mid := CenterContainer.new()
	mid.name = "BottomMid"
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band.add_child(mid)
	_build_selection_panel(mid)
	_build_command_grid(band)


func _build_command_grid(parent: Node) -> void:
	_cmd_panel = PanelContainer.new()
	_cmd_panel.name = "CommandGrid"
	var sb := _style(PANEL_BG, PANEL_EDGE, 6, CELL_BORDER, 2)
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_cmd_panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(_cmd_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	_cmd_panel.add_child(v)
	_cmd_title = _label(v, 14, GOLD)
	_cmd_title.name = "GridTitle"
	_cmd_grid = GridContainer.new()
	_cmd_grid.name = "GridCells"
	_cmd_grid.columns = GRID_COLUMNS
	_cmd_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_cmd_grid.add_theme_constant_override("v_separation", CELL_GAP)
	v.add_child(_cmd_grid)
	_rebuild_command_grid()


## Rebuilds the cells for the current page when what they show changes (page, era, stock). The HUD refresh calls this
## every tick.
func _refresh_command_grid() -> void:
	var key := _command_grid_key()
	if key == _grid_key:
		return
	_grid_key = key
	_rebuild_command_grid()


func _command_grid_key() -> String:
	var parts: Array[String] = [model.s.era_id(), _grid_page]
	for c: Dictionary in model.grid(_grid_page):
		parts.append("%s:%s:%s" % [c["id"], c["state"], c["label"]])
	return "|".join(parts)


func _rebuild_command_grid() -> void:
	for c in _cmd_grid.get_children():
		_cmd_grid.remove_child(c)
		c.queue_free()
	_cmd_cells.clear()
	var cells := model.grid(_grid_page)
	_cmd_title.text = model.grid_title(_grid_page)
	for i in cells.size():
		_cmd_cells.append(_grid_cell_button(cells[i], i))
	_refresh_active_tool()


## One cell: building art or category icon, its name, and its key (the pane's positional letter, or Esc/More).
func _grid_cell_button(cell: Dictionary, index: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CELL_SIZE
	b.clip_contents = true
	b.name = "Cell_" + (str(cell["id"]) if str(cell["id"]) != "" else "empty%d" % index)
	b.set_meta("cell_id", str(cell["id"]))
	b.set_meta("cell_state", str(cell["state"]))
	_style_cell(b, cell, false)
	_cmd_grid.add_child(b)
	b.pressed.connect(_activate_cell.bind(index))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	b.add_child(v)
	# The content sits inside the cell's own border, so nothing lands on the edge (ticket 130c).
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = CELL_BORDER
	v.offset_top = CELL_BORDER
	v.offset_right = -CELL_BORDER
	v.offset_bottom = -CELL_BORDER
	var empty := str(cell["state"]) == "empty"
	var id := str(cell["id"])
	var entry: Variant = ArtLibrary.manifest()["buildings"].get(id)
	var locked := str(cell["state"]) == "locked"
	# Top line: hotkey inset at the left, the picture in the middle, the short cost inset at the right. Name under it.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 0)
	v.add_child(top)
	var gutter := Control.new()
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gutter.custom_minimum_size = Vector2(CELL_INSET, 0)
	top.add_child(gutter)
	var key := _cell_label(top, CELL_KEY_SIZE, DIM)
	key.name = "CellKey"
	key.text = "" if empty else str(cell["key"])
	key.custom_minimum_size = Vector2(21, 0)  # "Esc" fits; the same width as the cost keeps the icon centred
	var lead := Control.new()
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lead)
	var pic := Control.new()
	pic.name = "CellIcon"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.custom_minimum_size = Vector2(CELL_PIC, CELL_PIC)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pic)
	var trail := Control.new()
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(trail)
	var cost_slot := Control.new()
	cost_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_slot.custom_minimum_size = Vector2(21, 0)
	top.add_child(cost_slot)
	var end_gutter := Control.new()
	end_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_gutter.custom_minimum_size = Vector2(CELL_INSET, 0)
	top.add_child(end_gutter)
	if empty:
		pass  # a dim blank cell: no picture, name or hotkey
	elif entry != null:
		var t := TextureRect.new()
		t.texture = ArtLibrary.texture(entry["file"])
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.modulate = Color(0.45, 0.45, 0.45, 1) if locked else Color.WHITE
		pic.add_child(t)
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var icon := str(cell.get("icon", ""))
		if icon == "obelisk":  # the Landmark category; the moon belongs to the night-building badge (ticket 130b)
			var obelisk := ObeliskGlyph.new()
			pic.add_child(obelisk)
			obelisk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		elif icon == "water":  # the Water category has no art; its drop glyph stands in for one (ticket 130c)
			var drop := WaterDropGlyph.new()
			pic.add_child(drop)
			drop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		elif icon != "":
			var ir := _icon(pic, icon, CELL_PIC)
			ir.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if locked and not empty:
		# A small padlock on the icon's top-right corner, clear of the name (ticket 130c).
		var lock := LockGlyph.new()
		lock.name = "Lock"
		pic.add_child(lock)
		lock.position = Vector2(CELL_PIC - LockGlyph.SIZE.x, 0)
		lock.size = LockGlyph.SIZE
	# Unaffordable: the short cost in red (the hover card lists every cost with its have N).
	if str(cell["state"]) == "unaffordable":
		var def := model.s.registry.get_building(id)
		if def != null:
			for c: Dictionary in model.cost_rows(def):
				if bool(c["short"]):
					var cost := _cell_label(cost_slot, CELL_KEY_SIZE, RED)
					cost.name = "CellCost"
					cost.text = str(c["need"])
					cost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					break
	var name_row := MarginContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("margin_left", CELL_INSET)
	name_row.add_theme_constant_override("margin_right", CELL_INSET)
	v.add_child(name_row)
	var nm := _cell_label(name_row, CELL_NAME_SIZE, DIM if locked else INK)
	nm.name = "CellName"
	nm.text = "" if empty else str(cell["label"])
	_fit_cell_name(nm)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if entry != null:
		b.set_meta("def_id", id)
		b.mouse_entered.connect(func() -> void:
			_grid_focus_id = ""
			_tip_btn = b)
		b.mouse_exited.connect(func() -> void:
			if _tip_btn == b:
				_tip_btn = null)
	b.tooltip_text = str(cell["reason"])
	if b.tooltip_text == "":
		b.tooltip_text = str(cell.get("tip", TOOL_TIPS.get(id, "")))
	return b


## Cell look by state: red edge when unaffordable, grey and dim when locked, nearly blank when empty; gold edge when
## it is the active tool.
func _style_cell(b: Button, cell: Dictionary, on: bool) -> void:
	var state := str(cell["state"])
	var bg := Color(0.11, 0.094, 0.086)
	var edge := PANEL_EDGE
	var hover := Color(0.17, 0.145, 0.125)
	match state:
		"unaffordable":
			bg = Color(0.37, 0.09, 0.08)
			edge = RED
			hover = Color(0.45, 0.11, 0.09)
		"locked":
			bg = Color(0.09, 0.09, 0.09)
			edge = Color(0.22, 0.22, 0.22)
			hover = bg
		"empty":
			bg = Color(0.075, 0.07, 0.065)
			edge = Color(0.16, 0.15, 0.14)
			hover = bg
	b.add_theme_stylebox_override("normal", _style(bg, GOLD if on else edge, 4, CELL_BORDER, 0))
	b.add_theme_stylebox_override("hover", _style(hover, GOLD if on or state != "locked" else edge, 4, CELL_BORDER, 0))
	b.add_theme_stylebox_override("pressed", _style(hover, GOLD, 4, CELL_BORDER, 0))
	b.add_theme_stylebox_override("disabled", _style(bg, edge, 4, CELL_BORDER, 0))
	b.disabled = state == "empty"


## A cell's text line: Tiny5 drawn at `size` itself, not the HUD's 2x body step (ticket 130c).
func _cell_label(parent: Node, size: int, color: Color) -> Label:
	var l := _label(parent, size, color)
	l.add_theme_font_size_override("font_size", size)
	return l


## Fits a cell's name in the cell: the readable size when it fits, the minimum when it does not, and only then
## tightened glyph spacing, so the whole name shows and the size never drops below CELL_NAME_MIN (ticket 130c).
func _fit_cell_name(l: Label) -> void:
	var width := CELL_SIZE.x - 2.0 * (CELL_BORDER + CELL_INSET)
	for size in [CELL_NAME_SIZE, CELL_NAME_MIN]:
		if _body_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			l.add_theme_font_size_override("font_size", size)
			return
	l.add_theme_font_size_override("font_size", CELL_NAME_MIN)
	var tight := _tight_name_font(1)
	if tight.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, CELL_NAME_MIN).x > width:
		tight = _tight_name_font(2)
	l.add_theme_font_override("font", tight)


## Tiny5 with `px` fewer pixels between glyphs (a FontVariation, so the size stays readable).
func _tight_name_font(px: int) -> FontVariation:
	if not _tight_fonts.has(px):
		var f := FontVariation.new()
		f.base_font = _body_font
		f.spacing_glyph = -px
		_tight_fonts[px] = f
	return _tight_fonts[px]


## Presses cell `index` on the current page: opens a category, pages on, goes back, picks a building or tool, or runs a
## top-level action. Locked cells only open their hover card; empty cells do nothing.
func _activate_cell(index: int) -> void:
	var cells := model.grid(_grid_page)
	if index < 0 or index >= cells.size():
		return
	var c: Dictionary = cells[index]
	var id := str(c["id"])
	var state := str(c["state"])
	if state == "empty":
		return
	_grid_focus_id = id if state == "locked" or model.s.registry.get_building(id) != null else ""
	match id:
		"back":
			_set_grid_page("")
			return
		"more":
			var bits := _grid_page.split(":")
			_set_grid_page("%s:%d" % [bits[0], int(bits[1]) + 1 if bits.size() > 1 else 2])
			return
		"demolish": build.set_mode(BuildController.Mode.DEMOLISH)
		"upgrade": build.set_mode(BuildController.Mode.UPGRADE)
		"clear": build.set_mode(BuildController.Mode.CLEAR)
		"plant": build.set_mode(BuildController.Mode.PLANT)
		"region": toggle_region_map()
		_:
			if state == "locked":
				return
			if _grid_page == "":
				if HudModel.is_grid_category(id):
					_open_grid_page(id)
			else:
				_pick(id)
	refresh()


func _open_grid_page(page: String) -> void:
	_grid_focus_id = ""
	_grid_page = page
	_grid_key = ""
	_refresh_command_grid()
	refresh()


## Opens a category pane, or closes it when it is already open (tests and the tutorial call this).
func open_category(id: String) -> void:
	_set_grid_page("" if _grid_page == id else id)


func _set_grid_page(page: String) -> void:
	_open_grid_page(page)


## The cell button carrying `id` on the current page, or null.
func _cell_button(id: String) -> Button:
	for b in _cmd_cells:
		if str(b.get_meta("cell_id", "")) == id:
			return b
	return null


## Builds `def_id` (the pane cell with that id), or null: the tutorial highlight finds it this way.
func build_button(def_id: String) -> Button:
	return _cell_button(def_id)


## A small padlock for a locked cell, drawn on the icon's top-right corner (ticket 130c: it used to sit on the name).
class LockGlyph extends Control:
	const SIZE := Vector2(9, 11)

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gold := Color("f2d27a")
		var w := size.x
		var h := size.y
		draw_arc(Vector2(w * 0.5, h * 0.42), w * 0.26, PI, TAU, 10, gold, 1.5)
		draw_line(Vector2(w * 0.24, h * 0.42), Vector2(w * 0.24, h * 0.5), gold, 1.5)
		draw_line(Vector2(w * 0.76, h * 0.42), Vector2(w * 0.76, h * 0.5), gold, 1.5)
		draw_rect(Rect2(w * 0.08, h * 0.48, w * 0.84, h * 0.48), gold)
		draw_rect(Rect2(w * 0.42, h * 0.66, maxf(1.0, w * 0.16), maxf(2.0, h * 0.2)), Color("3a2e18"))


## A small water drop for the Water category cell, which has no building art of its own (ticket 130c).
class WaterDropGlyph extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(Hud.CELL_PIC, Hud.CELL_PIC)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cx := w * 0.5
		var water := Color("9adcf2")
		draw_colored_polygon(PackedVector2Array([Vector2(cx, h * 0.1), Vector2(cx - w * 0.28, h * 0.62),
				Vector2(cx + w * 0.28, h * 0.62)]), water)
		draw_circle(Vector2(cx, h * 0.62), w * 0.28, water)
		draw_arc(Vector2(cx, h * 0.62), w * 0.28, 0.0, PI, 12, Color("3f8fb4"), 1.0)
		draw_rect(Rect2(cx - w * 0.18, h * 0.52, maxf(1.0, w * 0.1), maxf(1.0, h * 0.14)), Color(1, 1, 1, 0.6))


## A small pixel obelisk for the Landmark category cell (ticket 130b). The moon is the night-building badge's.
class ObeliskGlyph extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(Hud.CELL_PIC, Hud.CELL_PIC)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var stone := Color("cfc8b4")
		var shade := Color("8a8578")
		var dark := Color("57534a")
		var gold := Color("f2d27a")
		draw_rect(Rect2(roundf(w * 0.16), h * 0.84, roundf(w * 0.68), maxf(1.0, h * 0.08)), shade)
		draw_rect(Rect2(roundf(w * 0.10), h * 0.92, roundf(w * 0.80), maxf(1.0, h * 0.06)), dark)
		draw_rect(Rect2(roundf(w * 0.38), h * 0.20, roundf(w * 0.24), h * 0.64), stone)
		draw_rect(Rect2(roundf(w * 0.38), h * 0.20, maxf(2.0, roundf(w * 0.06)), h * 0.64), shade)
		draw_rect(Rect2(roundf(w * 0.45), h * 0.32, maxf(2.0, roundf(w * 0.06)), h * 0.38), Color("6fd8e8"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(roundf(w * 0.38), h * 0.20), Vector2(w * 0.5, h * 0.06),
			Vector2(roundf(w * 0.62), h * 0.20)]), gold)


## Hover text of the top-level tool cells (the old tools column's tooltips).
const TOOL_TIPS := {
	"demolish": "Demolish (X): click buildings and roads to take them down",
	"upgrade": "Upgrade mode (U): click buildings to upgrade them",
	"clear": "Clear (Z): click-drag forest, stumps and rock to have builders clear them for wood and stone. Cleared rock is no longer a quarry spot.",
	"plant": "Plant (Y): click-drag grass to mark it; Foresters in reach plant marked tiles before any other grass.",
	"region": "Region map (M)",
}
const TOOL_MODES := {"road": BuildController.Mode.ROAD, "channel": BuildController.Mode.CHANNEL,
		"paved": BuildController.Mode.PAVED, "track": BuildController.Mode.TRACK, "demolish": BuildController.Mode.DEMOLISH}


## Lights the cell of the building being placed or the active road tool.
func _refresh_active_tool() -> void:
	if build == null:
		return
	for b in _cmd_cells:
		if not is_instance_valid(b):
			continue
		var id := str(b.get_meta("cell_id", ""))
		_style_cell(b, {"state": b.get_meta("cell_state", "ok")}, _cell_active(id))


## Whether the cell `id` is the tool in use: an action cell for its mode at the top level, a building or road tool in a
## pane.
func _cell_active(id: String) -> bool:
	if _grid_page == "":
		match id:
			"demolish": return build.mode == BuildController.Mode.DEMOLISH
			"upgrade": return build.mode == BuildController.Mode.UPGRADE
			"clear": return build.mode == BuildController.Mode.CLEAR
			"plant": return build.mode == BuildController.Mode.PLANT
			"roads": return build.mode == BuildController.Mode.ROAD
		return false
	if build.mode == BuildController.Mode.BUILD and id == build.def_id:
		return true
	return TOOL_MODES.get(id, -1) == build.mode


## Picks the pane cell with `id`: a building def starts placing it, a road tool sets its mode.
func _pick(id: String) -> void:
	if model.s.registry.get_building(id) != null:
		build.set_build(id)
		return
	match id:
		"road": build.set_mode(BuildController.Mode.ROAD)
		"channel": build.set_mode(BuildController.Mode.CHANNEL)
		"paved": build.set_mode(BuildController.Mode.PAVED)
		"track": build.set_mode(BuildController.Mode.TRACK)


# ---------------------------------------------------------------- refresh and input

func refresh() -> void:
	for r in model.resources():
		(_res_labels[r["id"]] as Label).text = r["value_text"]
		(_res_deltas[r["id"]] as Label).text = r["delta_text"]
	var pop := model.population()
	_pop_label.text = pop["text"]
	_idle_label.text = "%d idle" % pop["idle"]
	_pop_box.tooltip_text = pop["tooltip"]
	_pop_label.add_theme_color_override("font_color", RED if pop["homeless"] > 0 else INK)
	_growth_bar.value = pop["growth"]
	_refresh_objectives()
	var hours_f := float(model.s.clock.hour())
	if driver != null:
		hours_f += driver.hour_fraction()
	_row_dial.set_time(hours_f, model.s.registry.day_night)
	_clock_date.text = driver.status_text() if driver != null else HudModel.clock_bar_text(model.s.clock.day(), hours_f)
	_clock_season.text = model.date_text()
	_refresh_clock_buttons()
	_refresh_pins()
	var active: bool = model.dimming_state() == "active"
	objectives_panel.add_theme_stylebox_override("panel", _style(PANEL_BG, CYAN if active else PANEL_EDGE))
	model.sync_layer()
	minimap.refresh_toggles()
	_refresh_command_grid()
	_refresh_selection()
	_refresh_notes()
	_region_map.refresh()
	workforce_page.refresh()
	resources_page.refresh()
	tutorial_panel.refresh()
	update_highlight()


## Lights the clock row's current speed (pause or 1x/2x/3x), like the tools tab (ticket 125).
func _refresh_clock_buttons() -> void:
	var speed: int = driver.speed if driver != null else 1
	_style_button(_pause_button, speed == 0)
	for i in _speed_buttons.size():
		_style_button(_speed_buttons[i], speed == i + 1)


## True while a full page (Region map, Workforce, Resources) is open; the map hover tip stays hidden then.
func page_open() -> bool:
	return _region_map.visible or workforce_page.visible or resources_page.visible


func toggle_region_map() -> void:
	_region_map.toggle()


func _center_region_map() -> void:
	var vp := get_viewport().get_visible_rect().size
	_region_map.position = ((vp - _region_map.size) / 2.0).floor()


func _process(delta: float) -> void:
	hover_tick(delta)
	_pulse_t += delta
	update_highlight(_pulse_t)
	_place_notes()
	if _region_map.visible:
		_center_region_map()
	if workforce_page.visible:
		workforce_page.position = ((get_viewport().get_visible_rect().size - workforce_page.size) / 2.0).floor()
	if resources_page.visible:
		resources_page.position = ((get_viewport().get_visible_rect().size - resources_page.size) / 2.0).floor()
	_acc += delta
	if _acc >= 0.2:
		_acc = 0.0
		refresh()


## True when Esc would still cancel something (build tool, selection, open pane): then it is not the menu's.
func has_cancelable() -> bool:
	return page_open() or (build != null and build.mode != BuildController.Mode.NONE) or model.selected_id >= 0 or _grid_page != ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		_mid_down = (event as InputEventMouseButton).pressed
	if _right.feed(event) and (build == null or build.mode == BuildController.Mode.NONE) and model.selected_id >= 0:
		model.clear_selection()  # right click (not a drag) deselects; with a build tool active it cancels that instead
		refresh()
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		# Modal keys (ticket 129): with a pane open its positional letters pick cells and override the global keys,
		# and Esc goes back to the top level (a second Esc is today's Esc).
		if _grid_page != "":
			var at := _grid_key_index(kc)
			if at >= 0:
				_activate_cell(at)
				get_viewport().set_input_as_handled()
				return
			if kc == KEY_ESCAPE:
				_set_grid_page("")
				get_viewport().set_input_as_handled()
				return
		for id in OVERLAY_KEYS:
			if kc == OVERLAY_KEYS[id]:
				_on_overlay(id)
				return
		match kc:
			KEY_M: toggle_region_map()
			KEY_Q: workforce_page.toggle()
			KEY_E: resources_page.toggle()
			KEY_F1: help_requested.emit()
			KEY_TAB:
				if model.layer_tag_visible():  # no island yet: Tab is not ours (98)
					model.toggle_layer()
					refresh()
					get_viewport().set_input_as_handled()
			# The command grid's own keys. R picks the road tool and opens the Roads pane; C P J stay with
			# BuildController as the global road-type keys.
			KEY_R:
				_pick("road")
				_open_grid_page("roads")
				get_viewport().set_input_as_handled()
			KEY_N: _open_grid_page("housing")
			KEY_F: _open_grid_page("food")
			KEY_W: _open_grid_page("water")
			KEY_I: _open_grid_page("lumen")
			KEY_K: _open_grid_page("logistics")
			KEY_S: _open_grid_page("resources")
			KEY_D: _open_grid_page("refining")
			KEY_A: _open_grid_page("civic")
			KEY_O: _open_grid_page("landmark")
			KEY_X:
				build.set_mode(BuildController.Mode.DEMOLISH)
				get_viewport().set_input_as_handled()
			KEY_U:
				build.set_mode(BuildController.Mode.UPGRADE)
				get_viewport().set_input_as_handled()
			KEY_Z:
				build.set_mode(BuildController.Mode.CLEAR)
				get_viewport().set_input_as_handled()
			KEY_Y:
				build.set_mode(BuildController.Mode.PLANT)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_region_map.close()
				workforce_page.close()
				resources_page.close()
				model.clear_selection()
				refresh()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if build != null and build.mode == BuildController.Mode.NONE and camera != null:
			var p := camera.get_global_mouse_position()
			model.select_at(Vector2i(floori(p.x / ArtLibrary.TILE), floori(p.y / ArtLibrary.TILE)))
			refresh()


## The cell of the open pane that key `kc` picks (its positional letter, B for More), -1 when it picks none.
func _grid_key_index(kc: Key) -> int:
	var name := OS.get_keycode_string(kc)
	if name == "" or name == "Escape":
		return -1
	var cells := model.grid(_grid_page)
	for i in cells.size():
		if str(cells[i]["key"]) == name:
			return i
	return -1


# ---------------------------------------------------------------- tutorial highlight (ticket 83)

## The button the current tutorial goal points at, or null: the goal's cell when its category pane is open, else that
## category's top-level cell; the Roads cell / road tool for the road goal; the minimap's overlay button for an overlay
## goal. Null when the tutorial is not active.
func highlight_button() -> Button:
	var g := (model.s.get_system(TutorialSystem) as TutorialSystem).current_goal()
	if g == null or g.highlight == "":
		return null
	var ov := minimap.overlay_button(g.highlight)
	if ov != null:
		return ov
	var cat := ""
	var entry := ""
	if g.highlight == "road":
		cat = "roads"
		entry = "road"
	else:
		var def := model.s.registry.get_building(g.highlight)
		if def == null:
			return null
		cat = HudModel.grid_group(def.category)
		entry = def.id
	if _grid_page == cat:
		return _cell_button(entry)
	if _grid_page == "":
		return _cell_button(cat)
	return _cell_button("back")  # another pane is open: Back is the way to it


## Pulses the highlighted button (self_modulate, so a disabled button's fade is kept) and clears the previous one.
func update_highlight(t: float = 0.0) -> void:
	var target := highlight_button()
	if _pulsed != null and is_instance_valid(_pulsed) and _pulsed != target:
		_pulsed.self_modulate = Color.WHITE
	_pulsed = target
	if target != null:
		target.self_modulate = Color.WHITE.lerp(GOLD * 1.4, 0.5 + 0.5 * sin(t * 6.0))


# ---------------------------------------------------------------- build detail panel (ticket 117)

const DETAIL_W := 350.0
## The preview box of the detail panel (width = DETAIL_W minus the panel margins).
const DETAIL_BOX := Vector2(326, 190)


## The largest whole-number factor that fits a sprite of `sprite` pixels in `box` (at least 1), so the pixels stay crisp.
static func detail_scale(sprite: Vector2, box: Vector2) -> int:
	return maxi(1, floori(minf(box.x / sprite.x, box.y / sprite.y)))
const GREEN := Color("90c870")


func _build_detail() -> void:
	_detail = PanelContainer.new()
	_detail.name = "BuildDetail"
	_detail.add_theme_stylebox_override("panel", _style(PANEL_BG, GOLD, 8, 2))
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	_detail.visible = false
	_detail_box = VBoxContainer.new()
	_detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_box.add_theme_constant_override("separation", 6)
	_detail.add_child(_detail_box)
	_float.add_child(_detail)


func detail_visible() -> bool:
	return _detail.visible


## The title the detail panel shows, "" when it is closed.
func detail_title() -> String:
	return _detail_title if _detail.visible else ""


## Opens the panel for the hovered build card (`def_id`), closes it for "". Rebuilt only when its data changes.
func _set_detail(def_id: String) -> void:
	var d := model.detail_for(def_id) if def_id != "" else {}
	if d.is_empty():
		_detail.visible = false
		_detail_key = ""
		_detail_title = ""
		return
	var key := str(d)
	if key != _detail_key:
		_detail_key = key
		_detail_title = str(d["title"])
		_fill_detail(d)
	_detail.visible = true
	_place_detail()


## Bottom right, just above the command grid.
func _place_detail() -> void:
	var vp := get_viewport().get_visible_rect().size
	var sz := _detail.get_combined_minimum_size()
	_detail.size = sz
	var bottom := vp.y - 6.0
	if _cmd_panel != null and is_instance_valid(_cmd_panel):
		bottom = _cmd_panel.get_global_rect().position.y - 6.0
	_detail.position = Vector2(maxf(6.0, vp.x - sz.x - 6.0), maxf(56.0, bottom - sz.y))


func _fill_detail(d: Dictionary) -> void:
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	var inner := DETAIL_W - 24.0
	var pic := PanelContainer.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_theme_stylebox_override("panel", _style(Color(0.16, 0.21, 0.14), Color(0, 0, 0, 0), 4, 0))
	pic.custom_minimum_size = Vector2(inner, DETAIL_BOX.y)
	pic.clip_contents = true
	_detail_box.add_child(pic)
	var entry: Variant = ArtLibrary.manifest()["buildings"].get(str(d["id"]))
	if entry != null:
		var scale := detail_scale(Vector2(float(entry["w"]), float(entry["h"])), DETAIL_BOX)
		var t := TextureRect.new()
		t.name = "DetailSprite"
		t.texture = ArtLibrary.texture(entry["file"])
		t.custom_minimum_size = Vector2(float(entry["w"]), float(entry["h"])) * scale
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.add_child(t)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_box.add_child(head)
	var title := _label(head, 18, INK)
	title.name = "DetailTitle"
	title.text = d["title"]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind := _label(head, 12, DIM)
	kind.text = d["kind"]
	kind.size_flags_vertical = Control.SIZE_SHRINK_END
	var desc := _label(_detail_box, 14, INK)
	desc.name = "DetailDescription"
	desc.text = d["description"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(inner, 0)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_box.add_child(rule)
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	_detail_box.add_child(grid)
	var cost := _detail_row(grid, "Cost", inner)
	for c: Dictionary in d["costs"]:
		var item := HBoxContainer.new()
		item.name = "DetailCost_" + str(c["good"])
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", 3)
		cost.add_child(item)
		_flow_item(item, c["icon"], str(c["name"]), str(c["need"]))
		var have := _label(item, 14, RED if c["short"] else DIM)
		have.name = "Have"
		have.text = "(have %d)" % c["have"]
		have.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if (d["costs"] as Array).is_empty():
		_label(cost, 14, INK).text = "free"
	if int(d["workers"]) > 0:
		_label(_detail_row(grid, "Workers", inner), 14, INK).text = str(d["workers"])
	_label(_detail_row(grid, "Size", inner), 14, INK).text = d["size"]
	if not (d["inputs"] as Array).is_empty() or not (d["outputs"] as Array).is_empty():
		var flow := _detail_row(grid, "Per day", inner)
		flow.name = "DetailFlow"
		for r: Dictionary in d["inputs"]:
			_flow_item(flow, r["icon"], str(r["name"]), str(r["amount"]))
		if not (d["inputs"] as Array).is_empty():
			_label(flow, 14, DIM).text = "->"
		for r: Dictionary in d["outputs"]:
			_flow_item(flow, r["icon"], str(r["name"]), str(r["amount"]))
		_label(flow, 12, DIM).text = "per worker"
	for l: String in d["extra"]:
		_hud_line(_detail_box, l, DIM, 14, inner)
	var unlock := _label(_detail_row(grid, "Unlock", inner), 14, GOLD if d["locked"] else GREEN)
	unlock.name = "DetailUnlock"
	unlock.text = d["unlock"]
	if d["reason"] != "":
		_hud_line(_detail_box, d["reason"], GOLD, 14, inner)
	_detail.reset_size()


## One "label | value" row of the detail grid; returns the value flow.
func _detail_row(grid: GridContainer, label: String, inner: float) -> HFlowContainer:
	var l := _label(grid, 14, DIM)
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 2)
	flow.custom_minimum_size = Vector2(inner - 82.0, 0)
	grid.add_child(flow)
	return flow


## An icon (the good's name when it has none) and a number.
func _flow_item(parent: Node, icon: String, good_name: String, amount: String) -> void:
	if icon != "":
		_icon(parent, icon, 20).name = "Icon"
		var n := _label(parent, 14, INK)
		n.name = "Num"
		n.text = amount
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		var n := _label(parent, 14, INK)
		n.name = "Num"
		n.text = "%s %s" % [amount, good_name]


# ---------------------------------------------------------------- tooltips

func _build_tooltip() -> void:
	_tip_panel = PanelContainer.new()
	_tip_panel.add_theme_stylebox_override("panel", _style())
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.z_index = 10
	_tip_panel.visible = false
	_tip_box = VBoxContainer.new()
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_box)
	add_child(_tip_panel)


func tooltip_visible() -> bool:
	return _tip_panel.visible


## What the open tooltip says (all its lines), "" when hidden.
func tooltip_text() -> String:
	return _tip_text if _tip_panel.visible else ""


func _hide_tip() -> void:
	_tip_panel.visible = false
	_tip_key = ""
	_tip_text = ""
	_tip_t = 0.0


## Advance the hover timer. A hovered build button wins; else the building under the mouse (or `tile`, for tests) when
## no build tool is active, no region map is open, the camera is not being dragged and no HUD panel is under the mouse.
func hover_tick(delta: float, tile: Vector2i = NO_TILE) -> void:
	var key := ""
	var data := {}
	if _tip_btn != null and not is_instance_valid(_tip_btn):
		_tip_btn = null
	# A hovered or keyboard-picked grid cell opens the detail panel at once (tickets 117, 129) instead of the tooltip.
	var detail_id := ""
	if _tip_btn != null and _tip_btn.is_visible_in_tree():
		detail_id = str(_tip_btn.get_meta("def_id"))
	elif _grid_focus_id != "":
		detail_id = _grid_focus_id
	_set_detail(detail_id)
	if _detail.visible:
		if _tip_panel.visible or _tip_key != "":
			_hide_tip()
		return
	if camera != null and (build == null or build.mode == BuildController.Mode.NONE) and not _right.down \
			and not _mid_down and not page_open() and (tile != NO_TILE or get_viewport().gui_get_hovered_control() == null):
		var t := tile
		if t == NO_TILE:
			var p := camera.get_global_mouse_position()
			t = Vector2i(floori(p.x / ArtLibrary.TILE), floori(p.y / ArtLibrary.TILE))
		var b := model.s.building_at(t, model.active_layer)
		if b != null:
			key = "b:%d" % b.id
			data = model.tooltip_for_building(b)
		elif model.active_layer == Building.LAYER_GROUND and model.s.is_clear_marked(t):
			key = "clear:%d,%d" % [t.x, t.y]
			data = model.clear_tooltip(t)
		elif model.active_layer == Building.LAYER_GROUND and model.s.is_plant_marked(t):
			key = "plant:%d,%d" % [t.x, t.y]
			data = model.plant_tooltip(t)
		elif model.active_layer == Building.LAYER_GROUND and MapState.in_bounds(t.x, t.y) and model.s.map.terrain_id_at(t.x, t.y) == "stump":
			key = "stump:%d,%d" % [t.x, t.y]
			data = model.stump_tooltip(t)
	if key == "" or data.is_empty():
		if _tip_panel.visible or _tip_key != "":
			_hide_tip()
		return
	if key != _tip_key:
		_tip_key = key
		_tip_t = 0.0
		_tip_panel.visible = false
	_tip_t += delta
	if _tip_t < TIP_DELAY:
		return
	if not _tip_panel.visible or str(data["text"]) != _tip_text:
		_fill_tip(data)
	_tip_panel.visible = true
	_place_tip()


func _fill_tip(d: Dictionary) -> void:
	_tip_text = str(d["text"])
	for c in _tip_box.get_children():
		_tip_box.remove_child(c)
		c.queue_free()
	var title := _label(_tip_box, 18, GOLD)
	title.text = d["title"]
	var rows: Array = []
	rows.append([d["description"], INK])
	for l in d["status"]:
		rows.append([l, Color("e8a33a") if str(l).begins_with("Halted") else CYAN])
	for l in d["lines"]:
		rows.append([l, DIM])
	for row in rows:
		if row[0] == "":
			continue
		_hud_line(_tip_box, row[0], row[1], 14, TIP_WIDTH)
	_tip_panel.reset_size()


## Beside the mouse, clamped to the screen.
func _place_tip() -> void:
	var vp := get_viewport().get_visible_rect().size
	var sz := _tip_panel.get_combined_minimum_size()
	_tip_panel.size = sz
	var pos := get_viewport().get_mouse_position() + Vector2(18, 18)
	_tip_panel.position = Vector2(clampf(pos.x, 6.0, maxf(6.0, vp.x - sz.x - 6.0)),
			clampf(pos.y, 6.0, maxf(6.0, vp.y - sz.y - 6.0)))
