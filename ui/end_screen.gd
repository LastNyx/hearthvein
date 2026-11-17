class_name EndScreen
extends CanvasLayer
## Modal win / no-win / loss screen (ticket 45d). Opens on the campaign_* events (ui/main.gd wires them), pauses the
## scene tree like the save menu, and is built in code with the same fonts and panel look. Continue closes and
## unpauses; the loss screen stays up and keeps the game paused (also while the save menu is opened over it).

## The loss screen's Quit: ui/main.gd returns to the title (ticket 80).
signal title_requested

var menu: SaveMenu
var slots: SaveSlots
var settlement_fn: Callable
var outcome: String = ""
var _font: FontFile
var _body_font: FontFile
var _dim: ColorRect
var _title: Label
var _body: Label
var _buttons: HBoxContainer
var _ids: Array[String] = []


func setup(m: SaveMenu, s: SaveSlots, settlement_getter: Callable) -> void:
	menu = m
	slots = s
	settlement_fn = settlement_getter
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = Hud._pixel_font(Hud.FONT_PATH)
	_body_font = Hud._pixel_font(Hud.BODY_FONT_PATH)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(Hud.PANEL_BG, 1.0), Hud.PANEL_EDGE, 8, 2, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(620, 0)
	panel.add_child(col)
	_title = _text(col, "", 26, Hud.GOLD)
	_body = _text(col, "", 16, Hud.INK)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_buttons)
	_dim.visible = false
	visible = false


func is_open() -> bool:
	return visible


## Shows the screen for `out` and pauses. Does nothing for an unknown outcome.
func show_outcome(out: String, s: Settlement) -> void:
	var d := EndScreenModel.build(out, s)
	if d.is_empty():
		return
	outcome = out
	_title.text = d["title"]
	_body.text = d["body"]
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	_ids.clear()
	for b in d["buttons"]:
		var id: String = b["id"]
		_ids.append(id)
		_button(_buttons, b["text"], 16).pressed.connect(func() -> void: press(id))
	visible = true
	_dim.visible = true
	if is_inside_tree():
		get_tree().paused = true


func button_ids() -> Array[String]:
	return _ids


func close() -> void:
	if not visible:
		return
	visible = false
	_dim.visible = false
	if is_inside_tree() and not (menu != null and menu.is_open()):
		get_tree().paused = false


func press(id: String) -> void:
	match id:
		"continue":
			close()
		"save_quit":
			var s: Settlement = settlement_fn.call()
			if s != null and slots != null:
				slots.autosave(s)
			get_tree().quit()
		"load":
			if menu != null:
				menu.open()
		"quit":
			title_requested.emit()


## The loss screen keeps the game paused even after the save menu opened over it was closed.
func _process(_delta: float) -> void:
	if visible and outcome == "lost" and not get_tree().paused and not (menu != null and menu.is_open()):
		get_tree().paused = true


# ---------------------------------------------------------------- look (same as ui/save_menu.gd)

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
	b.add_theme_stylebox_override("normal", _style(Color(0.173, 0.149, 0.133), Color(0, 0, 0, 0), 5, 2, 10))
	b.add_theme_stylebox_override("hover", _style(Color(0.33, 0.28, 0.23), Hud.PANEL_EDGE, 5, 2, 10))
	b.add_theme_stylebox_override("pressed", _style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 10))
	parent.add_child(b)
	return b
