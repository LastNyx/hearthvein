class_name TitleScreen
extends CanvasLayer
## The title screen (ticket 77, D56): the logo art (assets/ui/logo.png) and the main menu buttons over the backdrop map Main
## draws. Only emits signals; ui/main.gd decides what each button does. Continue is hidden when there is no save.

signal continue_pressed
signal new_game_pressed
signal load_pressed
signal milestones_pressed
signal whats_new_pressed
signal settings_pressed
signal quit_pressed

var continue_button: Button


## `version` is shown small in the bottom-right corner (empty: no label).
func setup(has_save: bool, version: String = "") -> void:
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.2)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vignette := _vignette()
	add_child(vignette)
	# Full-rect, not inside the CenterContainer: a fixed-size child there sets the container's minimum and pushes the
	# button column off the bottom of a 720 px window.
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(320, 0)
	center.add_child(col)
	var logo := TextureRect.new()
	logo.name = "Logo"
	logo.texture = ArtLibrary.texture(ArtLibrary.manifest()["logo"]["file"])
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # the art is wider than the button column: centred, not stretched
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	logo.custom_minimum_size = Vector2(0, logo.texture.get_height())
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_button(col, font, "What's new", "WhatsNew", whats_new_pressed)
	_button(col, font, "Settings", "Settings", settings_pressed)
	_button(col, font, "Quit", "Quit", quit_pressed)
	if version != "":
		var v := Label.new()
		v.name = "VersionLabel"
		v.text = "v" + version
		v.add_theme_font_override("font", Hud._pixel_font(Hud.BODY_FONT_PATH))
		v.add_theme_font_size_override("font_size", Hud._px_size(16))
		v.add_theme_color_override("font_color", Hud.DIM)
		v.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.9))
		v.add_theme_constant_override("outline_size", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)
		v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


## A soft dark ellipse behind the logo and buttons so they do not sit on busy forest.
func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.03, 0.02, 0.02, 0.78), Color(0.03, 0.02, 0.02, 0.7), Color(0.03, 0.02, 0.02, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.85, 0.5)
	t.width = 256
	t.height = 256
	var r := TextureRect.new()
	r.name = "Vignette"
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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
