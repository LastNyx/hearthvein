class_name SaveMenu
extends CanvasLayer
## The Esc pause menu (ticket 19d): Resume, Continue (latest autosave), then the autosaves and 8 manual slots with
## Save / Load / Delete. Styled like the HUD (same pixel fonts and panel look). Opening pauses the scene tree (this
## layer keeps running); the logic lives in SaveMenuModel. Loading emits `load_requested` and ui/main.gd swaps.

signal load_requested(settlement: Settlement)

var model: SaveMenuModel
var _font: FontFile
var _body_font: FontFile
var _dim: ColorRect
var _list: VBoxContainer
var _status: Label
var _continue: Button


func setup(m: SaveMenuModel) -> void:
	model = m
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = Hud._pixel_font(Hud.FONT_PATH)
	_body_font = Hud._pixel_font(Hud.BODY_FONT_PATH)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(Hud.PANEL_BG, 1.0), Hud.PANEL_EDGE, 8, 2, 18))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(760, 0)
	panel.add_child(col)
	_text(col, "Paused", 22, Hud.GOLD)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	_button(top, "Resume", 16).pressed.connect(close)
	_continue = _button(top, "Continue (latest autosave)", 16)
	_continue.pressed.connect(func() -> void: _emit_load(model.continue_latest()))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	col.add_child(_list)
	_status = _text(col, "", 16, Hud.DIM)
	_dim.visible = false
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible or model == null:
		return
	visible = true
	_dim.visible = true
	get_tree().paused = true
	refresh()


func close() -> void:
	if not visible:
		return
	model.pending = {}
	visible = false
	_dim.visible = false
	if is_inside_tree():
		get_tree().paused = false


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for r in model.rows():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var title := _text(row, r["title"], 16, Hud.CYAN if r["kind"] == "auto" else Hud.INK)
		title.custom_minimum_size = Vector2(110, 0)
		var detail := _text(row, r["detail"], 16, Hud.DIM if r["empty"] else Hud.INK)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot: int = r["slot"]
		if r["can_save"]:
			_button(row, "Save", 16).pressed.connect(func() -> void: model.save_to(slot); refresh())
		var load_b := _button(row, "Load", 16)
		load_b.disabled = not r["can_load"]
		var kind: String = r["kind"]
		load_b.pressed.connect(func() -> void: _emit_load(model.load_row(kind, slot)))
		if r["kind"] == "manual":
			var del := _button(row, "Delete", 16)
			del.disabled = not r["can_delete"]
			del.pressed.connect(func() -> void: model.request_delete(slot); refresh())
	_continue.disabled = not model.has_continue()
	_status.text = model.status


func _emit_load(s: Settlement) -> void:
	if s == null:
		refresh()
		return
	load_requested.emit(s)


# ---------------------------------------------------------------- look (same as ui/hud.gd)

func _style(bg: Color, edge: Color, radius: int = 5, border: int = 2, margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = maxi(7, margin - 5)
	sb.content_margin_bottom = maxi(7, margin - 5)
	return sb


func _text(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font if size >= 17 else _body_font)
	l.add_theme_font_size_override("font_size", Hud._px_size(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font if size >= 17 else _body_font)
	b.add_theme_font_size_override("font_size", Hud._px_size(size))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Hud.INK)
	b.add_theme_color_override("font_disabled_color", Color(Hud.DIM, 0.5))
	b.add_theme_stylebox_override("normal", _style(Color(0.173, 0.149, 0.133), Color(0, 0, 0, 0), 5, 2, 10))
	b.add_theme_stylebox_override("hover", _style(Color(0.33, 0.28, 0.23), Hud.PANEL_EDGE, 5, 2, 10))
	b.add_theme_stylebox_override("pressed", _style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 10))
	b.add_theme_stylebox_override("disabled", _style(Color(0.13, 0.115, 0.105), Color(0, 0, 0, 0), 5, 2, 10))
	parent.add_child(b)
	return b
