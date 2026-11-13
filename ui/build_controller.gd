class_name BuildController
extends Node
## Build mode input: R road tool (click-drag), X demolish, right click / Esc cancel, left click places.
## The menus live in the HUD (ui/hud.gd), which calls set_build / set_mode. Writes to the sim only through Settlement commands.

enum Mode { NONE, BUILD, ROAD, DEMOLISH }

var settlement: Settlement
var ghost: GhostView
var mode: Mode = Mode.NONE
var def_id: String = ""
var _painting := false
var _last_tile := Vector2i(-1, -1)
var _hint: Label


func setup(s: Settlement, g: GhostView, ui_layer: CanvasLayer) -> void:
	settlement = s
	ghost = g
	_hint = Label.new()
	_hint.position = Vector2(12, 56)
	_hint.add_theme_color_override("font_color", Color("f2d27a"))
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	ui_layer.add_child(_hint)
	_hint.visible = false


func set_build(id: String) -> void:
	def_id = id
	mode = Mode.BUILD
	_refresh()


func set_mode(m: Mode) -> void:
	mode = m
	def_id = ""
	_refresh()


func cancel() -> void:
	_painting = false
	mode = Mode.NONE
	def_id = ""
	_refresh()


func _refresh() -> void:
	_hint.visible = mode != Mode.NONE
	match mode:
		Mode.BUILD: _hint.text = "Placing %s (right click cancels)" % def_id
		Mode.ROAD: _hint.text = "Road: click-drag (right click cancels)"
		Mode.DEMOLISH: _hint.text = "Demolish: click (right click cancels)"
	if mode == Mode.NONE:
		ghost.set_state(null, Vector2i.ZERO, false, false)


func _mouse_tile() -> Vector2i:
	var p := ghost.get_global_mouse_position()
	return Vector2i(floori(p.x / GhostView.TILE), floori(p.y / GhostView.TILE))


func _process(_d: float) -> void:
	if mode == Mode.NONE:
		return
	var t := _mouse_tile()
	match mode:
		Mode.BUILD:
			var def := settlement.registry.get_building(def_id)
			ghost.set_state(def, t, settlement.can_place(def_id, t)["ok"], true)
		Mode.ROAD:
			ghost.set_state(null, t, settlement.can_place_road(t) and settlement.road_at(t) == 0, true)
		Mode.DEMOLISH:
			var b := settlement.building_at(t)
			ghost.set_state(null, t, (b != null and b != settlement.hearth) or settlement.road_at(t) != 0, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_R: set_mode(Mode.ROAD)
			KEY_X: set_mode(Mode.DEMOLISH)
			KEY_ESCAPE: cancel()
	elif event is InputEventMouseButton and mode != Mode.NONE:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_click(_mouse_tile())
			else:
				_painting = false
	elif event is InputEventMouseMotion and _painting and mode == Mode.ROAD:
		_paint_to(_mouse_tile())


func _click(t: Vector2i) -> void:
	match mode:
		Mode.BUILD:
			settlement.place_building(def_id, t)  # stays in build mode for repeated placement
		Mode.ROAD:
			_painting = true
			_last_tile = t
			settlement.place_road(t)
		Mode.DEMOLISH:
			var b := settlement.building_at(t)
			if b != null:
				settlement.demolish(b.id)
			else:
				settlement.remove_road(t)


## Paint a gap-free line of dirt road from the last painted tile to t.
func _paint_to(t: Vector2i) -> void:
	var cur := _last_tile
	while cur != t:
		var d := t - cur
		if absi(d.x) >= absi(d.y):
			cur.x += signi(d.x)
		else:
			cur.y += signi(d.y)
		settlement.place_road(cur)
	_last_tile = t
