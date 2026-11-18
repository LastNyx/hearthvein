class_name ToolsTab
extends VBoxContainer
## Bottom-left tools tab (ticket 88): one tab button whose label is the current speed, and when open a column with Pause,
## 1x, 2x, 3x, Demolish, Upgrade, Region map and Help. It mirrors SimDriver.speed (signal plus the HUD refresh) and
## keeps its open/closed state in GameSettings. Every button calls what its key calls.

const SPEED_LABELS: Array[String] = ["||", "1x", "2x", "3x"]

var _hud: Hud
var _driver: SimDriver
var _settings: GameSettings
var _tab: Button
var _panel: PanelContainer
var _speed_buttons: Array[Button] = []
var _open := true


func setup(hud: Hud, driver: SimDriver) -> void:
	_hud = hud
	_driver = driver
	name = "ToolsTab"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	grow_horizontal = Control.GROW_DIRECTION_END
	offset_left = 6.0
	offset_bottom = -6.0
	add_theme_constant_override("separation", 4)
	_panel = hud._panel(self)
	_panel.name = "ToolsPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_panel.add_child(col)
	_speed_button(col, "Tool_pause", "Pause", "Pause (Space)", 0)
	for i in range(1, 4):
		_speed_button(col, "Tool_speed%d" % i, "%dx" % i, "Speed %dx (%d)" % [i, i], i)
	_tool(col, "Tool_demolish", "Demolish", "Demolish (X)", func() -> void: hud.build.set_mode(BuildController.Mode.DEMOLISH))
	_tool(col, "Tool_upgrade", "Upgrade", "Upgrade the selected building (U)", func() -> void:
		if hud.model.upgrade():
			hud.refresh())
	_tool(col, "Tool_regionmap", "Region map", "Region map (M)", hud.toggle_region_map)
	_tool(col, "Tool_help", "Help", "Help (F1)", hud.help_requested.emit)
	_tab = hud._button(self, "", 16)
	_tab.name = "Tool_tab"
	_tab.custom_minimum_size = Vector2(64, 34)
	_tab.pressed.connect(func() -> void: set_open(not _open))
	if driver != null:
		driver.speed_changed.connect(func(_s: int) -> void: refresh())
	set_open(_open, false)


## Main hands the settings over once it has them: restores the saved state.
func bind_settings(settings: GameSettings) -> void:
	_settings = settings
	set_open(settings.tools_open, false)


func is_open() -> bool:
	return _open


func set_open(open: bool, save: bool = true) -> void:
	_open = open
	_panel.visible = open
	if save and _settings != null:
		_settings.tools_open = open
		_settings.save()
	refresh()


func button(id: String) -> Button:
	return find_child("Tool_" + id, true, false) as Button


## Tab label = current speed; the matching speed button is highlighted.
func refresh() -> void:
	if _driver == null:
		return
	_tab.text = SPEED_LABELS[_driver.speed]
	_tab.tooltip_text = "Tools (click to %s)" % ("close" if _open else "open")
	_hud._style_button(_tab, _driver.speed == 0)
	for i in _speed_buttons.size():
		_hud._style_button(_speed_buttons[i], i == _driver.speed)


func _speed_button(parent: Node, id: String, text: String, tip: String, speed: int) -> void:
	var b := _tool(parent, id, text, tip, func() -> void:
		if speed == 0:
			_driver.toggle_pause()
		else:
			_driver.set_speed(speed))
	_speed_buttons.append(b)


func _tool(parent: Node, id: String, text: String, tip: String, fn: Callable) -> Button:
	var b := _hud._button(parent, text, 14)
	b.name = id
	b.tooltip_text = tip
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(fn)
	return b
