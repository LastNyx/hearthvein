class_name BuildController
extends Node
## Build mode input: R road tool (click-drag), C irrigation channel (click-drag, Village era on), P paved road (click-drag, Town era on, upgrades dirt), J rail track (click-drag, Conflux era on), X demolish, U upgrade (click buildings, stays on), right click / Esc cancel, left click places.
## The menus live in the HUD (ui/hud.gd), which calls set_build / set_mode. Writes to the sim only through Settlement commands.

enum Mode { NONE, BUILD, ROAD, DEMOLISH, CHANNEL, PAVED, TRACK, UPGRADE }

## The mode or the building being placed changed (the HUD lights the matching tool).
signal mode_changed

var settlement: Settlement
## The HUD model whose active_layer placement targets (ticket 40d); null means the ground (tests, tools).
var model: HudModel
var ghost: GhostView
var mode: Mode = Mode.NONE
var def_id: String = ""
var _right := RightDrag.new()
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


## The hint line now on screen.
func hint_text() -> String:
	return _hint.text


func _refresh() -> void:
	mode_changed.emit()
	_hint.visible = mode != Mode.NONE
	match mode:
		Mode.BUILD: _hint.text = "Placing %s (right click cancels)" % def_id
		Mode.ROAD: _hint.text = "Road: click-drag (right click cancels)"
		Mode.CHANNEL: _hint.text = _channel_hint(_channel_cost())
		Mode.PAVED: _hint.text = "Paved road (%s a tile): click-drag (right click cancels)" % _paved_cost()
		Mode.TRACK: _hint.text = "Rail track (%s a tile): click-drag (right click cancels)" % _track_cost()
		Mode.DEMOLISH: _hint.text = "Demolish: click (right click cancels)"
		Mode.UPGRADE: _hint.text = "Upgrade: click a building (right click cancels)"
	if mode == Mode.NONE:
		ghost.set_state(null, Vector2i.ZERO, false, false)


## Layer a click or the ghost acts on: the active layer.
func _layer() -> int:
	return model.active_layer if model != null else Building.LAYER_GROUND


## Layer a building def is placed on from the active view: a Sky Lift always goes through the ground API.
func _place_layer(def: BuildingDef) -> int:
	return Building.LAYER_GROUND if def != null and def.sky_lift else _layer()


func _road_level(t: Vector2i, layer: int) -> int:
	return settlement.road_at(t) if layer == Building.LAYER_GROUND else (
			settlement.sky_roads[MapState.idx(t.x, t.y)] if MapState.in_bounds(t.x, t.y) else 0)


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
			var ok: bool = settlement.can_place(def_id, t, false, _place_layer(def))["ok"] \
					and (model == null or model.layer_block_reason(def) == "")
			ghost.set_state(def, t, ok, true)
		Mode.ROAD:
			var rl := _layer()
			ghost.set_state(null, t, settlement.can_place_road(t, rl) and _road_level(t, rl) == 0, true)
		Mode.CHANNEL:
			var c := settlement.can_place_channel(t)
			ghost.set_state(null, t, c["ok"] or settlement.channel_at(t), true)
			if c["ok"]:
				ghost.set_wet(WaterSystem.channel_preview(settlement, t))
			if c["ok"]:
				_hint.text = _channel_hint(_channel_cost())
			elif settlement.channel_at(t):
				_hint.text = "Channel: already dug (X removes it)"
			else:
				_hint.text = "Channel: %s" % HudModel.channel_refusal_text(str(c["reason"]))
		Mode.PAVED:
			var c := settlement.can_pave_road(t)
			ghost.set_state(null, t, c["ok"], true)
			if c["ok"]:
				_hint.text = "Paved road (%s a tile): click-drag (right click cancels)" % _paved_cost()
			else:
				_hint.text = "Paved road: %s" % HudModel.paved_refusal_text(str(c["reason"]))
		Mode.TRACK:
			var c := settlement.can_place_track(t)
			ghost.set_state(null, t, c["ok"] or settlement.track_at(t), true)
			if c["ok"]:
				_hint.text = "Rail track (%s a tile): click-drag (right click cancels)" % _track_cost()
			elif settlement.track_at(t):
				_hint.text = "Rail track: already laid (X lifts it)"
			else:
				_hint.text = "Rail track: %s" % HudModel.track_refusal_text(str(c["reason"]))
		Mode.UPGRADE:
			var u := _upgrade_check(t)
			ghost.set_state(null, t, u["ok"], true)
			_hint.text = u["text"]
		Mode.DEMOLISH:
			var dl := _layer()
			var b := settlement.building_at(t, dl)
			ghost.set_state(null, t, (b != null and b != settlement.hearth) or _road_level(t, dl) != 0
					or (dl == Building.LAYER_GROUND and (settlement.channel_at(t) or settlement.track_at(t))), true)


func _unhandled_input(event: InputEvent) -> void:
	if _right.feed(event) and mode != Mode.NONE:  # a right click cancels on release; a right drag pans (camera) and keeps the mode
		cancel()
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_R: set_mode(Mode.ROAD)
			KEY_C:
				if settlement.channels_unlocked():
					set_mode(Mode.CHANNEL)
			KEY_P:
				if settlement.paved_roads_unlocked():
					set_mode(Mode.PAVED)
			KEY_J:
				if settlement.track_unlocked():
					set_mode(Mode.TRACK)
			KEY_X: set_mode(Mode.DEMOLISH)
			KEY_U: set_mode(Mode.UPGRADE)
			KEY_ESCAPE: cancel()
	elif event is InputEventMouseButton and mode != Mode.NONE:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_click(_mouse_tile())
			else:
				_painting = false
	elif event is InputEventMouseMotion and _painting and (mode == Mode.ROAD or mode == Mode.CHANNEL or mode == Mode.PAVED or mode == Mode.TRACK):
		_paint_to(_mouse_tile())


func _click(t: Vector2i) -> void:
	match mode:
		Mode.BUILD:
			var def := settlement.registry.get_building(def_id)
			if model == null or model.layer_block_reason(def) == "":
				settlement.place_building(def_id, t, _place_layer(def))  # stays in build mode for repeated placement
		Mode.ROAD:
			_painting = true
			_last_tile = t
			settlement.place_road(t, Settlement.ROAD_DIRT, _layer())
		Mode.CHANNEL:
			_painting = true
			_last_tile = t
			settlement.place_channel(t)
		Mode.PAVED:
			_painting = true
			_last_tile = t
			settlement.pave_road(t)
		Mode.TRACK:
			_painting = true
			_last_tile = t
			settlement.place_track(t)
		Mode.UPGRADE:
			var u := _upgrade_check(t)
			if u["ok"]:
				settlement.upgrade(int(u["id"]))
				u = {"text": "Upgrade started: %s" % u["name"]}
			_hint.text = u["text"]  # stays in upgrade mode; a refusal says why
		Mode.DEMOLISH:
			var b := settlement.building_at(t, _layer())
			if b != null:
				settlement.demolish(b.id)
			elif _layer() == Building.LAYER_SKY:
				settlement.remove_road(t, Building.LAYER_SKY)
			elif settlement.track_at(t):
				settlement.remove_track(t)
			elif settlement.channel_at(t):
				settlement.remove_channel(t)
			else:
				settlement.remove_road(t)


## What the upgrade tool says about the building on tile t: {ok, id, name, text}.
func _upgrade_check(t: Vector2i) -> Dictionary:
	var b := settlement.building_at(t, _layer())
	if b == null:
		return {"ok": false, "text": "Upgrade: point at a building (right click cancels)"}
	var hm := model if model != null else HudModel.new(settlement)
	var can := settlement.can_upgrade(b.id)
	var nm := b.display_name(settlement.registry)
	if not can["ok"]:
		var nxt := b.tier + 1
		return {"ok": false, "text": "%s: %s" % [nm, hm.upgrade_reason_text(str(can["reason"]), nxt)]}
	var info := hm.upgrade_info(b)
	return {"ok": true, "id": b.id, "name": nm, "text": "%s: click to upgrade to %s (%s)" % [nm, info["next_name"], info["next_cost"]]}


func _channel_hint(cost: String) -> String:
	var help := settlement.registry.water.channel_help() if settlement.registry.water != null else ""
	return "Channel (%s a tile): click-drag (right click cancels)\n%s" % [cost, help]


func _channel_cost() -> String:
	var c := settlement.registry.water.channel_cost_materials if settlement.registry.water != null else 0.0
	return "%d materials" % roundi(c)


func _track_cost() -> String:
	return HudModel.new(settlement).track_cost_text()


func _paved_cost() -> String:
	return HudModel.new(settlement).paved_cost_text()


## Paint a gap-free line of dirt road (or channel, or paved road) from the last painted tile to t.
func _paint_to(t: Vector2i) -> void:
	var cur := _last_tile
	while cur != t:
		var d := t - cur
		if absi(d.x) >= absi(d.y):
			cur.x += signi(d.x)
		else:
			cur.y += signi(d.y)
		if mode == Mode.CHANNEL:
			settlement.place_channel(cur)
		elif mode == Mode.PAVED:
			settlement.pave_road(cur)
		elif mode == Mode.TRACK:
			settlement.place_track(cur)
		else:
			settlement.place_road(cur, Settlement.ROAD_DIRT, _layer())
	_last_tile = t
