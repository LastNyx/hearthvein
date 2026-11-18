class_name WhatsNewPanel
extends CanvasLayer
## The What's new panel opened from the title (ticket 92): CHANGELOG.md as BBCode in a scrollable RichTextLabel, Back
## closes it (Esc is handled by ui/main.gd). Only emits back_pressed.

signal back_pressed

var text_label: RichTextLabel
var back_button: Button


## `bbcode` comes from ChangelogText.to_bbcode.
func setup(bbcode: String) -> void:
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
	panel.add_child(col)
	var title := Label.new()
	title.text = "What's new"
	title.add_theme_font_override("font", Hud._pixel_font(Hud.FONT_PATH))
	title.add_theme_font_size_override("font_size", Hud._px_size(22))
	title.add_theme_color_override("font_color", Hud.GOLD)
	col.add_child(title)
	text_label = RichTextLabel.new()
	text_label.name = "Text"
	text_label.bbcode_enabled = true
	text_label.scroll_active = true
	text_label.custom_minimum_size = Vector2(620, 400)
	text_label.add_theme_font_override("normal_font", Hud._pixel_font(Hud.BODY_FONT_PATH))
	text_label.add_theme_font_size_override("normal_font_size", Hud._px_size(16))
	text_label.add_theme_color_override("default_color", Hud.INK)
	text_label.text = bbcode
	col.add_child(text_label)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bar)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_override("font", Hud._pixel_font(Hud.FONT_PATH))
	back_button.add_theme_font_size_override("font_size", Hud._px_size(18))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		back_button.add_theme_color_override(c, Hud.INK)
	back_button.add_theme_stylebox_override("normal", SaveMenu._style(Color(0.173, 0.149, 0.133), Hud.PANEL_EDGE, 5, 2, 14))
	back_button.add_theme_stylebox_override("hover", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 14))
	back_button.add_theme_stylebox_override("pressed", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 14))
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	bar.add_child(back_button)
