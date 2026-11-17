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
var _main_view: VBoxContainer
var _ms_view: VBoxContainer
var _ms_body: HBoxContainer
var _settings_view: VBoxContainer
## Built by setup() when a GameSettings is given (Main passes its own); the Settings button opens it.
var settings_panel: SettingsPanel
## Title screen mode (ticket 77): opened from the title, so no pause, no Save buttons, no Continue.
## The three views (load list, Milestones, Settings) are opened one at a time with open_view(); Back closes the menu.
var title_mode: bool = false
var _view: String = ""
var _heading: Label
var _resume: Button


func setup(m: SaveMenuModel, settings: GameSettings = null) -> void:
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
	_main_view = VBoxContainer.new()
	_main_view.add_theme_constant_override("separation", 8)
	col.add_child(_main_view)
	_ms_view = VBoxContainer.new()
	_ms_view.add_theme_constant_override("separation", 8)
	_ms_view.visible = false
	col.add_child(_ms_view)
	_settings_view = VBoxContainer.new()
	_settings_view.visible = false
	col.add_child(_settings_view)
	_heading = _text(_main_view, "Paused", 22, Hud.GOLD)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_main_view.add_child(top)
	_resume = _button(top, "Resume", 16)
	_resume.pressed.connect(close)
	_continue = _button(top, "Continue (latest autosave)", 16)
	_continue.pressed.connect(func() -> void: _emit_load(model.continue_latest()))
	_button(top, "Milestones", 16).pressed.connect(show_milestones)
	if settings != null:
		_button(top, "Settings", 16).pressed.connect(show_settings)
		settings_panel = SettingsPanel.new()
		settings_panel.name = "SettingsPanel"
		_settings_view.add_child(settings_panel)
		settings_panel.setup(settings)
		settings_panel.back_requested.connect(hide_settings)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_main_view.add_child(_list)
	_status = _text(_main_view, "", 16, Hud.DIM)
	_build_milestone_view()
	_dim.visible = false
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible or model == null:
		return
	visible = true
	_dim.visible = true
	if not title_mode:
		get_tree().paused = true
	refresh()


## Title screen: opens the menu in title mode on one view: "load" (the slot list), "milestones" or "settings".
func open_view(view: String) -> void:
	title_mode = true
	_view = view
	_heading.text = "Load game"
	_resume.text = "Back"
	_continue.visible = false
	open()
	if view == "milestones":
		show_milestones()
	elif view == "settings":
		show_settings()


func close() -> void:
	if not visible:
		return
	model.pending = {}
	title_mode = false
	_view = ""
	_heading.text = "Paused"
	_resume.text = "Resume"
	_continue.visible = true
	_ms_view.visible = false
	_settings_view.visible = false
	_main_view.visible = true
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
		if r["confirm"] != "":
			_text(row, "Overwrite?" if r["confirm"] == "overwrite" else "Delete?", 16, Hud.GOLD)
			_button(row, "Yes", 16).pressed.connect(func() -> void: model.confirm(); refresh())
			_button(row, "No", 16).pressed.connect(func() -> void: model.cancel(); refresh())
			continue
		if r["can_save"] and not title_mode:
			_button(row, "Save", 16).pressed.connect(func() -> void: model.request_save(slot); refresh())
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


## The Milestones panel (ticket 46c): "This run" and "Lifetime" side by side, Back returns to the menu.
func show_milestones() -> void:
	_main_view.visible = false
	_ms_view.visible = true
	refresh_milestones()


func show_settings() -> void:
	if settings_panel == null:
		return
	_main_view.visible = false
	_settings_view.visible = true


func hide_settings() -> void:
	if title_mode and _view == "settings":
		close()
		return
	_settings_view.visible = false
	_main_view.visible = true


func hide_milestones() -> void:
	if title_mode and _view == "milestones":
		close()
		return
	_ms_view.visible = false
	_main_view.visible = true


func _build_milestone_view() -> void:
	_text(_ms_view, "Milestones", 22, Hud.GOLD)
	_ms_body = HBoxContainer.new()
	_ms_body.add_theme_constant_override("separation", 24)
	_ms_view.add_child(_ms_body)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	_ms_view.add_child(bar)
	_button(bar, "Back", 16).pressed.connect(hide_milestones)


func refresh_milestones() -> void:
	for c in _ms_body.get_children():
		_ms_body.remove_child(c)
		c.queue_free()
	var s: Settlement = model.current.call()
	var ms: MilestoneSystem = s.get_system(MilestoneSystem) as MilestoneSystem if s != null else null
	var data := MilestonePanelModel.build(model.registry, ms, MilestoneSystem.lifetime())
	for key in ["run", "lifetime"]:
		var sec: Dictionary = data[key]
		var colm := VBoxContainer.new()
		colm.add_theme_constant_override("separation", 4)
		colm.custom_minimum_size = Vector2(360, 0)
		_ms_body.add_child(colm)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		colm.add_child(head)
		_text(head, sec["title"], 17, Hud.CYAN)
		_text(head, sec["count"], 16, Hud.CYAN).name = "Count"  # Tiny5: Pixelify reads "15" as "1S"
		if sec["bonus_text"] != "":
			_text(head, sec["bonus_text"], 16, Hud.DIM)
		for r: Dictionary in sec["rows"]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			colm.add_child(row)
			var done: bool = r["done"]
			var name_l := _text(row, ("Bonus: " if r["bonus"] else "") + str(r["name"]), 16, Hud.INK if done else Hud.DIM)
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_text(row, MilestonePanelModel.status_text(r), 16, Hud.GOLD if done else Color(Hud.DIM, 0.6))


## A 20 px box drawn in code: 2 px light border on the dark panel; checked adds a filled square inside.
static func _box_icon(checked: bool, ink: Color) -> ImageTexture:
	var n := 20
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var border := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			var inner := checked and x >= 6 and y >= 6 and x < n - 6 and y < n - 6
			if border or inner:
				img.set_pixel(x, y, ink)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0.35))
	return ImageTexture.create_from_image(img)


func _emit_load(s: Settlement) -> void:
	if s == null:
		refresh()
		return
	load_requested.emit(s)


# ---------------------------------------------------------------- look (same as ui/hud.gd)

static func _style(bg: Color, edge: Color, radius: int = 5, border: int = 2, margin: int = 12) -> StyleBoxFlat:
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
