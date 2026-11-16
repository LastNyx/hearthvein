class_name RegionMap
extends PanelContainer
## The region map (key M, design.md section 4): the 4x4 region grid over a scaled summary of the real terrain. Owned
## regions are bright, buyable ones (4-adjacent to an owned region) show their price and a Buy button (disabled, with the
## reason, when gold is short), the rest are dimmed; each reward gets a marker and a short label. Thin: rows come from
## HudModel.region_rows(), Buy goes through HudModel.buy_region().

const SCALE := 5  # screen pixels per map tile: 128 x 96 tiles -> 640 x 480
const CELL := Vector2(MapState.REGION_W * SCALE, MapState.REGION_H * SCALE)
const GROUND_COLORS := {"water": Color("3d6a9a"), "grass": Color("6a9a48"), "forest": Color("2f5e32"),
		"soil": Color("8a6a42"), "rock": Color("8a8a8e"), "vein": Color("6fd8e8"), "sky": Color("c8d8f0")}

var hud: Hud
var model: HudModel
var _tex: TextureRect
var _marks: Marks
var _gold: Label
var _buttons: Dictionary = {}  # region -> Button
var _notes: Dictionary = {}  # region -> Label
var _surveys: Dictionary = {}  # region -> Button (locked regions with an unrevealed reward)


func setup(h: Hud, m: HudModel) -> void:
	hud = h
	model = m
	add_theme_stylebox_override("panel", hud._style())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := hud._label(head, 18, Hud.GOLD)
	title.text = "Regions"
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_gold = hud._label(head, 17, Hud.GOLD)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(MapState.WIDTH * SCALE, MapState.HEIGHT * SCALE)
	v.add_child(holder)
	_tex = TextureRect.new()
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_tex)
	_tex.size = Vector2(MapState.WIDTH * SCALE, MapState.HEIGHT * SCALE)
	_marks = Marks.new()
	_marks.owner_panel = self
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_marks)
	_marks.size = _tex.size
	for r in MapState.REGION_COUNT:
		var origin := Vector2((r % MapState.REGION_COLS) * CELL.x, (r / MapState.REGION_COLS) * CELL.y)
		var b := hud._button(holder, "Buy", 16)
		b.position = origin + Vector2(CELL.x / 2.0 - 50.0, CELL.y - 62.0)
		b.custom_minimum_size = Vector2(100, 28)
		b.size = Vector2(100, 28)
		b.pressed.connect(_buy.bind(r))
		_buttons[r] = b
		var sb := hud._button(holder, "Survey", 16)
		sb.position = b.position
		sb.custom_minimum_size = Vector2(100, 28)
		sb.size = Vector2(100, 28)
		sb.pressed.connect(_survey.bind(r))
		_surveys[r] = sb
		var n := hud._label(holder, 14, Hud.INK)
		n.position = origin + Vector2(0, CELL.y - 28.0)
		n.size = Vector2(CELL.x, 20)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notes[r] = n
	var hint := hud._label(v, 14, Hud.DIM)
	hint.text = "Buy a region next to your land. Docks survey locked ones. M or Esc closes."
	visible = false


func open() -> void:
	_tex.texture = ImageTexture.create_from_image(minimap_image(model.s.map))
	visible = true
	refresh()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _buy(r: int) -> void:
	model.buy_region(r)
	refresh()


func _survey(r: int) -> void:
	model.survey_region(r)
	refresh()


func refresh() -> void:
	if not visible:
		return
	_gold.text = "Gold %d" % floori(model.s.gold)
	_marks.rows = model.region_rows()
	for row: Dictionary in _marks.rows:
		var r: int = row["region"]
		var b: Button = _buttons[r]
		b.visible = row["state"] == "buyable"
		b.text = "Buy %d" % row["price"]
		b.disabled = not row["can_buy"]
		var n: Label = _notes[r]
		var status := HudModel.survey_status_text(row)
		n.text = status if status != "" else row["note"]
		var sb: Button = _surveys[r]
		sb.visible = row["state"] == "locked" and row["reward"] != "" and not row["revealed"] and not row["surveying"]
		sb.disabled = not row["can_survey"]
		sb.tooltip_text = HudModel.survey_reason_text(row["survey_reason"])
		if sb.visible and sb.disabled:
			n.text = sb.tooltip_text
		n.add_theme_color_override("font_color", Hud.GOLD if row["state"] == "buyable" else Hud.INK)
	_marks.queue_redraw()


## One pixel per map tile, coloured by its ground; scaled up with nearest filtering.
static func minimap_image(map: MapState) -> Image:
	var img := Image.create(MapState.WIDTH, MapState.HEIGHT, false, Image.FORMAT_RGBA8)
	var cache := {}
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var id := map.terrain_id_at(x, y)
			if not cache.has(id):
				cache[id] = GROUND_COLORS.get(ArtLibrary.ground_of(id) if ArtLibrary.has_terrain(id) else "grass",
						GROUND_COLORS["grass"])
			img.set_pixel(x, y, cache[id])
	return img


## Dimming, borders and reward markers over the minimap (drawn under the Buy buttons).
class Marks extends Control:
	var owner_panel: RegionMap
	var rows: Array[Dictionary] = []

	func _draw() -> void:
		var font := owner_panel.hud._px_font(14)
		var fsize := Hud._px_size(14)
		for row: Dictionary in rows:
			var origin := Vector2(row["col"] * CELL.x, row["row"] * CELL.y)
			var rect := Rect2(origin, CELL)
			match row["state"]:
				"locked": draw_rect(rect, Color(0.02, 0.03, 0.08, 0.68))
				"buyable": draw_rect(rect, Color(0.02, 0.03, 0.08, 0.3))
			draw_rect(rect, Color(Hud.GOLD, 0.9) if row["state"] == "buyable" else Color(1, 1, 1, 0.35), false, 2.0)
			var reward: String = row["reward"]
			var pos: Vector2i = row["reward_pos"]
			if reward == "" or pos.x < 0:
				continue
			var c: Color = MapState.REWARD_COLORS.get(reward, Color.WHITE)
			var o := (Vector2(pos) + Vector2(0.5, 0.5)) * SCALE
			var k := 7.0
			var pts := PackedVector2Array([o + Vector2(0, -k), o + Vector2(k, 0), o + Vector2(0, k), o + Vector2(-k, 0)])
			draw_colored_polygon(pts, c)
			pts.append(pts[0])
			draw_polyline(pts, Color(0.05, 0.05, 0.1), 2.0)
			var label: String = row["reward_label"]
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			var tp := Vector2(clampf(o.x - w / 2.0, origin.x + 4.0, origin.x + CELL.x - w - 4.0), o.y + k + 16.0)
			tp.y = minf(tp.y, origin.y + CELL.y - 70.0)
			draw_string(font, tp + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.9))
			draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(c.lightened(0.3), 1.0))
