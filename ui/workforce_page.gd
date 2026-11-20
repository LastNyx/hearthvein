class_name WorkforcePage
extends PanelContainer
## The Workforce page (key Q, D8): header counts, the construction sites on top, then the buildings by category with
## workers filled/slots, Low/Normal/High and Pause/Resume (lit like the selection panel) and a Note. Rows without jobs
## show only their row. Centred, scrolls when long; the sim keeps running. Thin: rows come from HudModel.workforce(),
## the buttons call Settlement.set_building_priority.

const SIZE := Vector2(900, 560)
const COL_NAME := 230
const COL_COUNT := 170
const COL_PRIO := 200
const COL_PAUSE := 76

var hud: Hud
var model: HudModel
var _head: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _key := ""


func setup(h: Hud, m: HudModel) -> void:
	hud = h
	model = m
	add_theme_stylebox_override("panel", hud._style(Color(0.094, 0.078, 0.071, 1.0)))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = SIZE
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := hud._label(top, 18, Hud.GOLD)
	title.text = "Workforce (Q)"
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var hint := hud._label(top, 14, Hud.DIM)
	hint.text = "Esc or Q closes"
	_head = hud._label(v, 17, Hud.INK)
	var note := hud._label(v, 14, Hud.DIM)
	note.text = "Priority orders jobs inside a category only"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)


func open() -> void:
	visible = true
	_key = ""
	refresh()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Rebuilds the rows only when the data changed, so a button is never freed between press and release.
func refresh() -> void:
	if not visible:
		return
	var data := model.workforce()
	var key := str(data)
	if key == _key:
		return
	_key = key
	var hd: Dictionary = data["header"]
	_head.text = "Workers %d, idle %d, haulers %d, builders %d" % [hd["workers"], hd["idle"], hd["haulers"], hd["builders"]]
	if int(hd["short"]) > 0:
		_head.text += ", %d short" % hd["short"]
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var cols := HBoxContainer.new()
	_list.add_child(cols)
	_cell(cols, "Building", COL_NAME, Hud.DIM, 14, 24)
	_cell(cols, "Workers", COL_COUNT, Hud.DIM, 14)
	_cell(cols, "Priority", COL_PRIO + COL_PAUSE + 8, Hud.DIM, 14)
	_cell(cols, "Note", 0, Hud.DIM, 14)
	for g: Dictionary in data["groups"]:
		var gl := hud._label(_list, 15, Hud.GOLD)
		gl.text = g["label"]
		for row: Dictionary in g["rows"]:
			_add_row(row)
	_scroll.scroll_vertical = keep


func _cell(parent: Node, text: String, width: int, color: Color, size: int = 15, indent: int = 0) -> Label:
	var l := hud._label(parent, size, color)
	l.text = text
	l.custom_minimum_size = Vector2(width + indent, 0)
	l.clip_text = true
	if width == 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _add_row(row: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.name = "Row_%d" % row["id"]
	_list.add_child(h)
	var dim: bool = row["paused"]
	_cell(h, row["name"], COL_NAME, Hud.DIM if dim else Hud.INK, 15, 24)
	_cell(h, row["count_text"], COL_COUNT, Hud.DIM if dim else (Hud.INK if row["ok"] else Hud.RED))
	var prio := HBoxContainer.new()
	prio.custom_minimum_size = Vector2(COL_PRIO + COL_PAUSE + 8, 0)
	prio.add_theme_constant_override("separation", 4)
	h.add_child(prio)
	if row["has_jobs"]:
		var id: int = row["id"]
		for p in ["low", "normal", "high"]:
			var b := _small_button(prio, HudModel.PRIORITY_LABELS[p])
			b.name = "Prio_" + p
			b.pressed.connect(func() -> void: _command(id, p))
			_lit(b, row["priority"] == p and not row["paused"])
		var pb := _small_button(prio, "Resume" if row["paused"] else "Pause")
		pb.name = "Pause"
		pb.pressed.connect(func() -> void: _command(id, row["priority"] if row["paused"] else "paused"))
		_lit(pb, row["paused"])
	var nl := _cell(h, row["note"], 0, Hud.GOLD if row["no_road"] else (Hud.RED if (not row["ok"] and not row["paused"]) else Hud.DIM))
	if row["note"].ends_with("Dimming"):
		nl.add_theme_color_override("font_color", Hud.GOLD)


## A compact button (about 22 px tall) so rows with and without buttons are the same height.
func _small_button(parent: Node, text: String) -> Button:
	var b := hud._button(parent, text, 13)
	b.custom_minimum_size = Vector2(0, 22)
	_lit(b, false)
	return b


## Lit like the selection panel's buttons, with thin margins to stay compact.
func _lit(b: Button, on: bool) -> void:
	hud._style_button(b, on)
	for st in ["normal", "hover", "pressed"]:
		var sb := b.get_theme_stylebox(st) as StyleBoxFlat
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		sb.content_margin_left = 6
		sb.content_margin_right = 6


func _command(id: int, priority: String) -> void:
	model.s.set_building_priority(id, priority)
	hud.refresh()
	refresh()


## The row of a building (test and shot seam), or null.
func row_node(building_id: int) -> Control:
	return _list.get_node_or_null("Row_%d" % building_id) as Control
