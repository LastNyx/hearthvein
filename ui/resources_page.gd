class_name ResourcesPage
extends PanelContainer
## The Resources page (key E or a click on a top-bar resource, D7): a table of every good (stock, change per day, made
## and used yesterday), a click on a row charts it for 60 days under the table, hovering a made number lists what made
## it. Centred, opaque like the Workforce page; the sim keeps running. Thin: rows, breakdown and series come from
## HudModel (resource_rows, made_breakdown, resource_history), which reads the ResourceLedgerSystem.

const SIZE := Vector2(900, 590)
const COL_NAME := 180
const COL_NUM := 90
const GREEN := Color("78be5a")
const CHART_BG := Color(0.07, 0.06, 0.055)
const CHART_FILL := Color(0.69, 0.47, 0.25)
const CHART_PAD := Vector4(40, 8, 12, 22)  # left, top, right, bottom room inside the chart for labels

var hud: Hud
var model: HudModel
var selected := "food"
var _list: VBoxContainer
var _crumb_icon: TextureRect
var _chart_title: Label
var _chart: Chart
var _tip: PanelContainer
var _tip_box: VBoxContainer
var _key := ""
var _hover := ""


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
	title.text = "Resources (E)"
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var hint := hud._label(top, 14, Hud.DIM)
	hint.text = "Esc or E closes. Click a row to chart it."
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	v.add_child(mid)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.custom_minimum_size = Vector2(COL_NAME + 4 * COL_NUM + 40, 0)
	mid.add_child(_list)
	_tip = hud._panel(mid)  # the made-by breakdown, beside the table, shown while a made number is hovered
	_tip.add_theme_stylebox_override("panel", hud._style(Color(0.094, 0.078, 0.071, 1.0), Hud.GOLD))
	_tip.custom_minimum_size = Vector2(250, 0)
	_tip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tip.modulate.a = 0.0  # hidden but keeps its width, so the table does not jump
	_tip_box = VBoxContainer.new()
	_tip_box.add_theme_constant_override("separation", 3)
	_tip.add_child(_tip_box)
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", hud._style(CHART_BG, Hud.PANEL_EDGE, 4, 1))
	cp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cp)
	var cv := VBoxContainer.new()
	cp.add_child(cv)
	var ch := HBoxContainer.new()
	cv.add_child(ch)
	_crumb_icon = hud._icon(ch, "food", 22)
	_chart_title = hud._label(ch, 16, Hud.INK)
	_chart = Chart.new()
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.custom_minimum_size = Vector2(0, 150)
	_chart.font = hud._px_font(14)
	cv.add_child(_chart)


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


## Opens the page with `id` (a top-bar resource id) selected.
func open_for(id: String) -> void:
	if HudModel.RESOURCES.has(id):
		selected = id
	open()


func select(id: String) -> void:
	if not HudModel.RESOURCES.has(id):
		return
	selected = id
	_key = ""
	refresh()


## Rebuilds only when the data changed, so a row is never freed between press and release.
func refresh() -> void:
	if not visible:
		return
	var rows := model.resource_rows()
	var hist := model.resource_history(selected)
	var key := "%s|%s|%s" % [selected, str(rows), str(hist)]
	if key == _key:
		return
	_key = key
	_hover = ""
	_tip.modulate.a = 0.0
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	_list.add_child(head)
	_cell(head, "Good", COL_NAME, Hud.DIM, false, 14, 36)
	for t in ["Stock", "Change/day", "Made yesterday", "Used yesterday"]:
		_cell(head, t, COL_NUM, Hud.DIM, true, 14)
	for r: Dictionary in rows:
		_add_row(r)
	_chart_title.text = "%s stock, last 60 days" % _name_of(rows, selected)
	_crumb_icon.texture = ArtLibrary.texture(ArtLibrary.manifest()["icons"][selected])
	_chart.set_values(hist)


func _name_of(rows: Array[Dictionary], id: String) -> String:
	for r in rows:
		if r["id"] == id:
			return r["name"]
	return id


func _cell(parent: Node, text: String, width: int, color: Color, right: bool, size: int = 16, indent: int = 0) -> Label:
	var l := hud._label(parent, size, color)
	l.text = text
	l.custom_minimum_size = Vector2(width + indent, 0)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.clip_text = true
	return l


func _add_row(r: Dictionary) -> void:
	var id: String = r["id"]
	var on := id == selected
	var p := PanelContainer.new()
	p.name = "Row_" + id
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := hud._style(Color(0.25, 0.21, 0.17) if on else Color(0.12, 0.1, 0.09), Color(0, 0, 0, 0), 0, 0)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.border_width_left = 4 if on else 0
	sb.border_color = Hud.GOLD
	p.add_theme_stylebox_override("panel", sb)
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			select(id))
	_list.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	var ic := hud._icon(h, r["icon"], 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cell(h, r["name"], COL_NAME - 26, Hud.INK, false)
	_cell(h, str(r["stock"]), COL_NUM, Hud.INK, true)
	var ch: int = r["change"]
	_cell(h, HudModel.delta_text(ch), COL_NUM, GREEN if ch > 0 else (Hud.RED if ch < 0 else Hud.DIM), true)
	var made := _cell(h, str(r["made"]), COL_NUM, Hud.INK if r["made"] > 0 else Hud.DIM, true)
	made.name = "Made"
	made.mouse_filter = Control.MOUSE_FILTER_PASS  # gets hover, still lets the row see the click
	made.mouse_entered.connect(func() -> void: show_breakdown(id))
	made.mouse_exited.connect(func() -> void: hide_breakdown())
	_cell(h, str(r["used"]), COL_NUM, Hud.INK if r["used"] > 0 else Hud.DIM, true)


## Lists what made `id` yesterday beside the table (hover on the made number).
func show_breakdown(id: String) -> void:
	_hover = id
	for c in _tip_box.get_children():
		_tip_box.remove_child(c)
		c.queue_free()
	var rows := model.resource_rows()
	var made := 0
	for r in rows:
		if r["id"] == id:
			made = r["made"]
	var t := hud._label(_tip_box, 16, Hud.GOLD)
	t.text = "%s made yesterday: %d" % [_name_of(rows, id), made]
	for e: Dictionary in model.made_breakdown(id):
		var line := HBoxContainer.new()
		_tip_box.add_child(line)
		var n := _cell(line, e["label"], 170, Hud.INK, false, 15)
		n.name = "Label"
		var a := _cell(line, str(e["amount"]), 60, Hud.INK, true, 15)
		a.name = "Amount"
	if _tip_box.get_child_count() == 1:
		var none := hud._label(_tip_box, 14, Hud.DIM)
		none.text = "Nothing made yesterday"
	_tip.modulate.a = 1.0


func hide_breakdown() -> void:
	_hover = ""
	_tip.modulate.a = 0.0


## The row of a good (test and shot seam), or null.
func row_node(id: String) -> Control:
	return _list.get_node_or_null("Row_" + id) as Control


## The breakdown lines currently shown: [[label, amount text]].
func breakdown_lines() -> Array:
	var out: Array = []
	if _tip.modulate.a <= 0.0:
		return out
	for c in _tip_box.get_children():
		var l := c.find_child("Label", true, false) as Label
		var a := c.find_child("Amount", true, false) as Label
		if l != null and a != null:
			out.append([l.text, a.text])
	return out


func chart() -> Chart:
	return _chart


## The 60-day line chart: the series left to right (today last) as a filled line, labelled min and max on the axis.
class Chart extends Control:
	var font: Font
	var values: Array[float] = []

	func set_values(v: Array[float]) -> void:
		values = v
		queue_redraw()

	## Axis maximum: the series maximum rounded up to 1, 2 or 5 times a power of ten (10 for an empty or flat-zero series).
	static func nice_max(v: float) -> float:
		if v <= 0.0:
			return 10.0
		var p := pow(10.0, floorf(log(v) / log(10.0)))
		for m: float in [1.0, 2.0, 5.0, 10.0]:
			if v <= m * p + 0.0001:
				return m * p
		return 10.0 * p

	## Pixel points of a series inside `plot` (a Rect2), oldest left, today at the right edge, axis from 0 to `top`.
	static func points_for(vals: Array[float], plot: Rect2, top: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		var n := vals.size()
		for i in n:
			var x := plot.end.x if n == 1 else plot.position.x + plot.size.x * float(i) / float(n - 1)
			var y := plot.end.y - plot.size.y * clampf(vals[i] / top, 0.0, 1.0)
			out.append(Vector2(x, y))
		return out

	func plot_rect() -> Rect2:
		return Rect2(CHART_PAD.x, CHART_PAD.y, maxf(size.x - CHART_PAD.x - CHART_PAD.z, 1.0), maxf(size.y - CHART_PAD.y - CHART_PAD.w, 1.0))

	func axis_top() -> float:
		var m := 0.0
		for v in values:
			m = maxf(m, v)
		return nice_max(m)

	## The points as drawn (test seam).
	func points() -> PackedVector2Array:
		return points_for(values, plot_rect(), axis_top())

	func _draw() -> void:
		var plot := plot_rect()
		var top := axis_top()
		var dim := Hud.DIM
		var fs := 16
		for f: float in [0.0, 0.5, 1.0]:
			var y := plot.end.y - plot.size.y * f
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.08))
			if font != null:
				draw_string(font, Vector2(0, y + 5), str(roundi(top * f)), HORIZONTAL_ALIGNMENT_RIGHT, plot.position.x - 6, fs, dim)
		var n := values.size()
		if font != null:
			var by := size.y - 4.0
			draw_string(font, Vector2(plot.position.x, by), "%d days ago" % maxi(n - 1, 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
			draw_string(font, Vector2(plot.position.x, by), "%d" % (n / 2), HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, fs, dim)
			draw_string(font, Vector2(plot.position.x, by), "today", HORIZONTAL_ALIGNMENT_RIGHT, plot.size.x, fs, dim)
		if n == 0:
			return
		var pts := points_for(values, plot, top)
		var poly := PackedVector2Array(pts)
		poly.append(Vector2(pts[n - 1].x, plot.end.y))
		poly.append(Vector2(pts[0].x, plot.end.y))
		if n > 1:
			draw_colored_polygon(poly, CHART_FILL)
			draw_polyline(pts, Hud.GOLD, 2.0)
		draw_circle(pts[n - 1], 4.0, Hud.GOLD)
		if font != null:
			var label := str(roundi(values[n - 1]))
			draw_string(font, pts[n - 1] + Vector2(-10 - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Hud.GOLD)
