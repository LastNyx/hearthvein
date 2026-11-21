class_name SettingsPanel
extends VBoxContainer
## The Settings panel (ticket 76): fullscreen, UI scale, hints, reset tutorial, three volumes, mute in background.
## Every change is applied and saved at once. Same pixel look as the save menu; the menu (and later the title
## screen) hosts it and listens for `back_requested`.

signal back_requested

var settings: GameSettings
var _font: FontFile
var _body_font: FontFile
var _scale_buttons: Dictionary = {}
var _fullscreen_box: CheckBox
var _hints_box: CheckBox
var _day_night_box: CheckBox
var _gain_popups_box: CheckBox
var _mute_box: CheckBox
var _updates_box: CheckBox
var _sliders: Dictionary = {}
var _status: Label


func setup(s: GameSettings) -> void:
	settings = s
	_font = Hud._pixel_font(Hud.FONT_PATH)
	_body_font = Hud._pixel_font(Hud.BODY_FONT_PATH)
	add_theme_constant_override("separation", 8)
	_text(self, "Settings", 22, Hud.GOLD)
	_fullscreen_box = _check("Fullscreen", s.fullscreen, set_fullscreen)
	_fullscreen_box.name = "FullscreenToggle"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_text(row, "UI scale", 16, Hud.INK).custom_minimum_size = Vector2(150, 0)
	for sc in GameSettings.SCALES:
		var b := _button(row, "%d%%" % roundi(sc * 100.0), 16)
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(sc, s.ui_scale)
		b.pressed.connect(set_ui_scale.bind(sc))
		_scale_buttons[sc] = b
	_hints_box = _check("Show hints", s.hints_enabled, set_hints_enabled)
	_hints_box.name = "HintsToggle"
	_day_night_box = _check("Day and night", s.day_night, set_day_night)
	_day_night_box.name = "DayNightToggle"
	_gain_popups_box = _check("Gain popups", s.gain_popups, set_gain_popups)
	_gain_popups_box.name = "GainPopupsToggle"
	var reset := _button(self, "Reset tutorial and hints", 16)
	reset.name = "ResetTutorial"
	reset.pressed.connect(reset_tutorial)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_slider("volume_master", "Master volume", s.volume_master)
	_slider("volume_effects", "Effects volume", s.volume_effects)
	_slider("volume_ambience", "Ambience volume", s.volume_ambience)
	_mute_box = _check("Mute when the window is in the background", s.mute_in_background, set_mute_in_background)
	_mute_box.name = "MuteToggle"
	_updates_box = _check("Check for updates", s.check_updates, set_check_updates)
	_updates_box.name = "UpdatesToggle"
	_status = _text(self, "", 16, Hud.DIM)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(bar)
	_button(bar, "Back", 16).pressed.connect(func() -> void: back_requested.emit())


# ---------------------------------------------------------------- changes (each applies and saves)

func set_fullscreen(on: bool) -> void:
	settings.fullscreen = on
	_commit()


func set_ui_scale(v: float) -> void:
	settings.ui_scale = v
	for sc: float in _scale_buttons:
		(_scale_buttons[sc] as Button).button_pressed = is_equal_approx(sc, v)
	_commit()


func set_hints_enabled(on: bool) -> void:
	settings.hints_enabled = on
	_commit()


func set_day_night(on: bool) -> void:
	settings.day_night = on
	_commit()


func set_gain_popups(on: bool) -> void:
	settings.gain_popups = on
	_commit()


func set_mute_in_background(on: bool) -> void:
	settings.mute_in_background = on
	_commit()


func set_check_updates(on: bool) -> void:
	settings.check_updates = on
	_commit()


func set_volume(key: String, v: float) -> void:
	settings.set(key, clampf(v, 0.0, 1.0))
	_commit()


func reset_tutorial() -> void:
	settings.reset_tutorial()
	_commit()
	_status.text = "Tutorial and hints will show again."


func _commit() -> void:
	settings.apply(get_window() if is_inside_tree() else null)
	settings.changed.emit()
	if settings.save() != OK:
		_status.text = "Could not save settings."


# ---------------------------------------------------------------- building

func _check(text: String, on: bool, handler: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = on
	cb.add_theme_font_override("font", _body_font)
	cb.add_theme_font_size_override("font_size", Hud._px_size(16))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(c, Hud.INK)
	var hover_ink := Hud.INK.lightened(0.35)
	cb.add_theme_color_override("font_hover_color", hover_ink)
	cb.add_theme_color_override("font_hover_pressed_color", hover_ink)
	cb.add_theme_constant_override("h_separation", 10)
	for k in ["unchecked", "checked", "unchecked_disabled", "checked_disabled", "unchecked_mirrored", "checked_mirrored"]:
		cb.add_theme_icon_override(k, SaveMenu._box_icon(k.begins_with("checked"), Hud.INK))
	cb.toggled.connect(handler)
	add_child(cb)
	return cb


func _slider(key: String, label: String, value: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_text(row, label, 16, Hud.INK).custom_minimum_size = Vector2(150, 0)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(260, 24)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.name = key.capitalize().replace(" ", "")
	var track := SaveMenu._style(Color(0.173, 0.149, 0.133), Hud.PANEL_EDGE, 3, 2, 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", SaveMenu._style(Hud.GOLD, Hud.GOLD, 3, 0, 4))
	sl.add_theme_stylebox_override("grabber_area_highlight", SaveMenu._style(Hud.GOLD.lightened(0.3), Hud.GOLD, 3, 0, 4))
	row.add_child(sl)
	var pct := _text(row, "%d%%" % roundi(value * 100.0), 16, Hud.DIM)
	pct.custom_minimum_size = Vector2(52, 0)
	sl.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v * 100.0)
		set_volume(key, v))
	_sliders[key] = sl


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
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Hud.INK)
	b.add_theme_stylebox_override("normal", SaveMenu._style(Color(0.173, 0.149, 0.133), Color(0, 0, 0, 0), 5, 2, 10))
	b.add_theme_stylebox_override("hover", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.PANEL_EDGE, 5, 2, 10))
	b.add_theme_stylebox_override("pressed", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 10))
	b.add_theme_stylebox_override("hover_pressed", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 10))
	parent.add_child(b)
	return b
