class_name UpdatePanel
extends CanvasLayer
## The Update panel opened from the title's "Update x available" button (ticket 94): the release notes, a progress bar
## and buttons by install kind. Only emits signals; ui/main.gd runs the download. Same look as the What's new panel.

signal primary_pressed
signal page_pressed
signal skip_pressed
signal later_pressed

var text_label: RichTextLabel
var primary_button: Button
var page_button: Button
var skip_button: Button
var later_button: Button
var progress_bar: ProgressBar
var message_label: Label
var _installs := false


## `offer` comes from UpdateCheck.offer_from_text. The primary button installs when the build can (Windows exe, AppImage
## with an asset in the release), else it opens the download page.
func setup(offer: Dictionary) -> void:
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
	title.name = "Title"
	title.text = "Update %s available" % str(offer.get("version", ""))
	title.add_theme_font_override("font", Hud._pixel_font(Hud.FONT_PATH))
	title.add_theme_font_size_override("font_size", Hud._px_size(22))
	title.add_theme_color_override("font_color", Hud.GOLD)
	col.add_child(title)
	text_label = RichTextLabel.new()
	text_label.name = "Text"
	text_label.bbcode_enabled = true
	text_label.scroll_active = true
	text_label.custom_minimum_size = Vector2(620, 340)
	text_label.add_theme_font_override("normal_font", Hud._pixel_font(Hud.BODY_FONT_PATH))
	text_label.add_theme_font_size_override("normal_font_size", Hud._px_size(16))
	text_label.add_theme_color_override("default_color", Hud.INK)
	text_label.text = ChangelogText.to_bbcode(str(offer.get("notes", "")), false)
	col.add_child(text_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = "Progress"
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = true
	progress_bar.visible = false
	col.add_child(progress_bar)
	message_label = Label.new()
	message_label.name = "Message"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(620, 0)
	message_label.add_theme_font_override("font", Hud._pixel_font(Hud.BODY_FONT_PATH))
	message_label.add_theme_font_size_override("font_size", Hud._px_size(16))
	message_label.add_theme_color_override("font_color", Hud.DIM)
	message_label.visible = false
	col.add_child(message_label)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bar)
	skip_button = _button(bar, "Skip this version", "Skip", skip_pressed)
	later_button = _button(bar, "Later", "Later", later_pressed)
	page_button = _button(bar, "Open download page", "Page", page_pressed)
	_installs = bool(offer.get("downloadable", false))
	var downloadable := _installs
	var label := "Open download page"
	match str(offer.get("kind", "other")) if downloadable else "":
		"windows":
			label = "Download and install"
		"appimage":
			label = "Download and restart"
	primary_button = _button(bar, label, "Primary", primary_pressed if downloadable else page_pressed)
	# Without a way to install here the primary button already opens the page; the second one shows after a failure.
	page_button.visible = false


func set_busy(busy: bool) -> void:
	progress_bar.visible = busy
	primary_button.disabled = busy
	skip_button.disabled = busy
	if busy:
		progress_bar.value = 0.0
		set_message("Downloading...", false)


func set_progress(fraction: float) -> void:
	progress_bar.value = fraction


## Shows `text` under the notes; `offer_page` adds an "Open download page" button next to the others.
func set_message(text: String, offer_page: bool) -> void:
	message_label.text = text
	message_label.visible = text != ""
	if offer_page and _installs:
		page_button.visible = true


func _button(parent: Node, text: String, id: String, sig: Signal) -> Button:
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
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
	return b
