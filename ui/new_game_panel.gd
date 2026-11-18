class_name NewGamePanel
extends CanvasLayer
## The New game options screen opened from the title (ticket 79, D57, D67): a seed field (digits, blank = random), the
## Endless start toggle, the Tutorial toggle (on by default until a tutorial game has been started), Start and Back.
## Only emits signals; ui/main.gd starts the game. Blank seed with Tutorial on means the data's tutorial seed.

signal start_pressed(seed: int, endless: bool, tutorial: bool)
signal back_pressed

const MAX_DIGITS := 9

var seed_edit: LineEdit
var endless_toggle: CheckBox
var tutorial_toggle: CheckBox
var start_button: Button
var back_button: Button


## `tutorial_done`: a tutorial game was started before, so the Tutorial toggle starts off.
func setup(tutorial_done: bool) -> void:
	layer = 25
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", SaveMenu._style(Color(Hud.PANEL_BG, 1.0), Hud.PANEL_EDGE, 8, 2, 18))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(520, 0)
	panel.add_child(col)
	_label(col, "New game", 22, Hud.GOLD, Hud.FONT_PATH)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_label(row, "Seed", 16, Hud.INK, Hud.BODY_FONT_PATH)
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedField"
	seed_edit.placeholder_text = "blank = random"
	seed_edit.max_length = MAX_DIGITS
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.add_theme_font_override("font", Hud._pixel_font(Hud.BODY_FONT_PATH))
	seed_edit.add_theme_font_size_override("font_size", Hud._px_size(16))
	seed_edit.add_theme_color_override("font_color", Hud.INK)
	seed_edit.add_theme_color_override("font_placeholder_color", Color(Hud.DIM, 0.6))
	seed_edit.add_theme_color_override("caret_color", Hud.INK)
	seed_edit.add_theme_stylebox_override("normal", SaveMenu._style(Color(0.13, 0.115, 0.105), Hud.PANEL_EDGE, 4, 2, 10))
	seed_edit.add_theme_stylebox_override("focus", SaveMenu._style(Color(0.13, 0.115, 0.105), Hud.GOLD, 4, 2, 10))
	seed_edit.text_changed.connect(_digits_only)
	row.add_child(seed_edit)
	endless_toggle = _check(col, "EndlessToggle", "Endless start (no Great Dimming, no win)", false)
	tutorial_toggle = _check(col, "TutorialToggle", "Tutorial (guided goals on a hand-picked map when the seed is blank)", not tutorial_done)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bar)
	back_button = _button(bar, "Back", "Back")
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	start_button = _button(bar, "Start", "Start")
	start_button.pressed.connect(func() -> void: start_pressed.emit(chosen_seed(), endless_toggle.button_pressed, tutorial_toggle.button_pressed))


## The typed seed, or -1 for blank (Main picks a random or the tutorial seed).
func chosen_seed() -> int:
	return int(seed_edit.text) if seed_edit.text.is_valid_int() else -1


func _digits_only(text: String) -> void:
	var out := ""
	for c in text:
		if c >= "0" and c <= "9":
			out += c
	if out != text:
		var at := seed_edit.caret_column
		seed_edit.text = out
		seed_edit.caret_column = mini(at, out.length())


func _label(parent: Node, text: String, size: int, color: Color, font_path: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Hud._pixel_font(font_path))
	l.add_theme_font_size_override("font_size", Hud._px_size(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _check(parent: Node, id: String, text: String, on: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.name = id
	cb.text = text
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = on
	cb.add_theme_font_override("font", Hud._pixel_font(Hud.BODY_FONT_PATH))
	cb.add_theme_font_size_override("font_size", Hud._px_size(16))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(c, Hud.INK)
	var hover_ink := Hud.INK.lightened(0.35)
	cb.add_theme_color_override("font_hover_color", hover_ink)
	cb.add_theme_color_override("font_hover_pressed_color", hover_ink)
	cb.add_theme_constant_override("h_separation", 10)
	for k in ["unchecked", "checked", "unchecked_disabled", "checked_disabled", "unchecked_mirrored", "checked_mirrored"]:
		cb.add_theme_icon_override(k, SaveMenu._box_icon(k.begins_with("checked"), Hud.INK))
	parent.add_child(cb)
	return cb


func _button(parent: Node, text: String, id: String) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Hud._pixel_font(Hud.FONT_PATH))
	b.add_theme_font_size_override("font_size", Hud._px_size(18))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Hud.INK)
	b.add_theme_stylebox_override("normal", SaveMenu._style(Color(0.173, 0.149, 0.133), Hud.PANEL_EDGE, 5, 2, 14))
	b.add_theme_stylebox_override("hover", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 14))
	b.add_theme_stylebox_override("pressed", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 14))
	parent.add_child(b)
	return b
