class_name HelpScreen
extends CanvasLayer
## The F1 help screen (ticket 85, D59c): page list on the left, page text on the right (pages are data/help/*.tres,
## HelpPageDef). It pauses the game through the SimDriver speed (like the era card) and puts the speed back on close.
## F1 toggles it, Esc closes it (Main checks it first, so Esc never opens the pause menu over it). open_page(id) is what
## the pause menu's Help button and a hint's More button call; an unknown or empty id opens the first page.
## Page text may hold {tokens} that resolve() fills from data: {gates}, {dimming_days}, {building.<id>.<prop>},
## {era.<id>.<prop>}, {road.<id>.<prop>}, {logistics.<prop>}, {spirit.<prop>}, {growth.<prop>}, {planet.<prop>}.
## A prop ending in % is shown times 100. Numbers are shown without their sign (the page says up or down).

const WIDTH := 880.0
const BODY_WIDTH := 600.0

var registry: DataRegistry
## Returns the running SimDriver, or null on the title screen (then F1 does nothing).
var get_driver: Callable
var _driver: SimDriver
var _dim: ColorRect
var _list: VBoxContainer
var _title: Label
var _body: Label
var _scroll: ScrollContainer
var _font: FontFile
var _body_font: FontFile
var _page := ""
var _open := false
var _saved_speed := 1
var _buttons: Dictionary = {}


func setup(reg: DataRegistry, driver_fn: Callable) -> void:
	registry = reg
	get_driver = driver_fn
	name = "HelpScreen"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = Hud._pixel_font(Hud.FONT_PATH)
	_body_font = Hud._pixel_font(Hud.BODY_FONT_PATH)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", SaveMenu._style(Color(Hud.PANEL_BG, 1.0), Hud.PANEL_EDGE, 8, 2, 18))
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.custom_minimum_size = Vector2(WIDTH, 0)
	panel.add_child(row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.custom_minimum_size = Vector2(230, 0)
	row.add_child(_list)
	_text(_list, "Help", 22, Hud.GOLD)
	for p in registry.help_pages_in_order():
		var b := _button(_list, p.title, 16)
		b.name = "Page_" + p.id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_page.bind(p.id))
		_buttons[p.id] = b
	var close_b := _button(_list, "Close (F1)", 16)
	close_b.name = "HelpClose"
	close_b.pressed.connect(close)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_title = _text(right, "", 22, Hud.CYAN)
	_title.name = "HelpTitle"
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(BODY_WIDTH + 20, 460)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_body = _text(_scroll, "", 17, Hud.INK)
	_body.name = "HelpBody"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(BODY_WIDTH, 0)


func is_open() -> bool:
	return _open


func current_page() -> String:
	return _page


## Opens the help on page `id` (the first page when it is empty or unknown). Pauses the sim while it is open.
func open_page(id: String) -> void:
	var driver := get_driver.call() as SimDriver
	if driver == null:
		return
	if not _open:
		_driver = driver
		_saved_speed = driver.speed
		driver.set_speed(0)
	_open = true
	_dim.visible = true
	show_page(id)


func show_page(id: String) -> void:
	var pages := registry.help_pages_in_order()
	if pages.is_empty():
		return
	var page := registry.help_pages.get(id, pages[0]) as HelpPageDef
	_page = page.id
	_title.text = page.title
	_body.text = resolve(page.body, registry)
	_scroll.scroll_vertical = 0
	for pid: String in _buttons:
		(_buttons[pid] as Button).disabled = pid == _page  # the open page's button stays lit and inert


func close() -> void:
	if not _open:
		return
	_open = false
	_dim.visible = false
	if _driver != null and is_instance_valid(_driver) and _driver.speed == 0:
		_driver.set_speed(_saved_speed)
	_driver = null


func toggle() -> void:
	if _open:
		close()
	else:
		open_page(_page)


## F1 toggles; Esc closes. This node always processes, so both work while the pause menu has paused the tree.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			toggle()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _open:
				close()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- text tokens

## Fills the {tokens} of a page body from data (see the class comment). An unknown token becomes "?" and is reported.
static func resolve(text: String, reg: DataRegistry) -> String:
	var re := RegEx.create_from_string("\\{([a-z_0-9.%]+)\\}")
	var out := ""
	var at := 0
	for m in re.search_all(text):
		out += text.substr(at, m.get_start() - at)
		out += _token(m.get_string(1), reg)
		at = m.get_end()
	return out + text.substr(at)


static func _token(tok: String, reg: DataRegistry) -> String:
	if tok == "gates":
		var lines: Array[String] = []
		for e in reg.eras_in_order():
			if e.gate_landmark == "":
				continue
			var lm := reg.get_building(e.gate_landmark)
			lines.append("%s: %d citizens, %d gold, and the %s built." % [e.display_name, e.gate_pop, e.gate_gold,
					lm.display_name if lm != null else e.gate_landmark])
		return "\n".join(lines)
	if tok == "dimming_days":
		var parts: Array[String] = []
		for e in reg.eras_in_order():
			parts.append("%s %d" % [e.display_name, e.dimming_base_days])
		return ", ".join(parts)
	var bits := tok.split(".")
	var res: Object = null
	var prop := ""
	match bits[0]:
		"building", "era", "road":
			if bits.size() == 3:
				res = {"building": reg.buildings, "era": reg.eras, "road": reg.roads}[bits[0]].get(bits[1])
				prop = bits[2]
		"logistics", "spirit", "growth", "planet":
			if bits.size() == 2:
				res = reg.get(bits[0])
				prop = bits[1]
	var pct := prop.ends_with("%")
	prop = prop.trim_suffix("%")
	if res == null or not (prop in res):
		push_error("HelpScreen: unknown token {%s}" % tok)
		return "?"
	var v := absf(float(res.get(prop)))
	return _num(v * 100.0 if pct else v)


static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	var s := String.num(v, 6)
	return s.rstrip("0").rstrip(".") if s.contains(".") else s


# ---------------------------------------------------------------- look (same as ui/save_menu.gd)

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
	b.add_theme_color_override("font_disabled_color", Hud.GOLD)
	b.add_theme_stylebox_override("normal", SaveMenu._style(Color(0.173, 0.149, 0.133), Color(0, 0, 0, 0), 5, 2, 10))
	b.add_theme_stylebox_override("hover", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.PANEL_EDGE, 5, 2, 10))
	b.add_theme_stylebox_override("pressed", SaveMenu._style(Color(0.33, 0.28, 0.23), Hud.GOLD, 5, 2, 10))
	b.add_theme_stylebox_override("disabled", SaveMenu._style(Color(0.25, 0.21, 0.16), Hud.GOLD, 5, 2, 10))
	parent.add_child(b)
	return b
