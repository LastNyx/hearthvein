class_name TitleScreen
extends CanvasLayer
## The title screen (ticket 77, D56): a placeholder logo label and the main menu buttons over the backdrop map Main
## draws. Only emits signals; ui/main.gd decides what each button does. Continue is hidden when there is no save.

signal continue_pressed
signal new_game_pressed
signal load_pressed
signal milestones_pressed
signal settings_pressed
signal quit_pressed

const LOGO_TEXT := "Hearthvein"  # placeholder, ticket 78 swaps in the art

var continue_button: Button


func setup(has_save: bool) -> void:
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(320, 0)
	center.add_child(col)
	var logo := Label.new()
	logo.name = "Logo"
	logo.text = LOGO_TEXT
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_override("font", Hud._pixel_font(Hud.FONT_PATH))
	logo.add_theme_font_size_override("font_size", 88)
	logo.add_theme_color_override("font_color", Hud.GOLD)
	logo.add_theme_color_override("font_outline_color", Color(0.09, 0.07, 0.06))
	logo.add_theme_constant_override("outline_size", 12)
	col.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	col.add_child(gap)
	var font := Hud._pixel_font(Hud.FONT_PATH)
	continue_button = _button(col, font, "Continue", "Continue", continue_pressed)
	continue_button.visible = has_save
	_button(col, font, "New game", "NewGame", new_game_pressed)
	_button(col, font, "Load", "Load", load_pressed)
	_button(col, font, "Milestones", "Milestones", milestones_pressed)
	_button(col, font, "Settings", "Settings", settings_pressed)
	_button(col, font, "Quit", "Quit", quit_pressed)


func _button(parent: Node, font: FontFile, text: String, id: String, sig: Signal) -> Button:
	var b := Button.new()
	b.name = id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", Hud._px_size(22))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Hud.INK)
	b.add_theme_stylebox_override("normal", SaveMenu._style(Color(0.173, 0.149, 0.133, 0.95), Hud.PANEL_EDGE, 5, 2, 18))
	b.add_theme_stylebox_override("hover", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 18))
	b.add_theme_stylebox_override("pressed", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 18))
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
	return b
