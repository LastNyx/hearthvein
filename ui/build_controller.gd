class_name BuildController
extends Node
## Build mode input: R road tool (click-drag), C irrigation channel (click-drag, Village era on), P paved road (click-drag, Town era on, upgrades dirt), J rail track (click-drag, Conflux era on), X demolish, Z clear (click-drag forest, stump and rock to mark them for builders; click again or X unmarks), Y plant (click-drag grass to mark it for Foresters; click again or X unmarks), U upgrade (click buildings, stays on), right click / Esc cancel, left click places.
## The menus live in the HUD (ui/hud.gd), which calls set_build / set_mode. Writes to the sim only through Settlement commands.

enum Mode { NONE, BUILD, ROAD, DEMOLISH, CHANNEL, PAVED, TRACK, UPGRADE, CLEAR, PLANT }

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
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # the channel hint is two long lines; stay clear of the objectives panel
	_hint.custom_minimum_size = Vector2(880, 0)
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
		Mode.CLEAR: _hint.text = "Clear: click-drag forest, stumps and rock to mark them for builders (right click cancels)"
		Mode.PLANT: _hint.text = "Plant: click-drag grass to mark it for Foresters to plant first (right click cancels)"
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


## What the Clear tool picks at a world point (ticket 160): {tile, tree}. A canopy hangs over the tile above its
## trunk, so the trunk's owning tile wins, not the tile under the cursor: the nearest trunk in the 3x3 tiles around
## the cursor whose sprite covers the point (or whose base is within 12 px). Defaults to the tile under the cursor.
static func pick_clear(s: Settlement, world: Vector2) -> Dictionary:
	var base := Vector2i(floori(world.x / GhostView.TILE), floori(world.y / GhostView.TILE))
	var best := base
	var best_tree: Dictionary = {}
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var t := base + Vector2i(dx, dy)
			if not MapState.in_bounds(t.x, t.y):
				continue
			var id := s.map.terrain_id_at(t.x, t.y)
			if ArtLibrary.ground_of(id) != "forest":
				continue
			for p: Dictionary in ArtLibrary.scatter(id, t.x, t.y, PropBatch.open_dir(s.map, t.x, t.y)):
				var pos: Vector2 = p["pos"]
				var d := world.distance_to(pos)
				if d > best_d or (d > 12.0 and not _prop_rect(p, pos).has_point(world)):
					continue
				best_d = d
				best = t
				best_tree = p
	return {"tile": best, "tree": best_tree}


## The screen rectangle a prop sprite covers when its base point sits at `pos`.
static func _prop_rect(p: Dictionary, pos: Vector2) -> Rect2:
	var e := ArtLibrary.prop_entry(String(p["name"]))
	var base := Vector2(float(e["base"][0]), float(e["base"][1]))
	return Rect2(pos - base, Vector2(float(e["w"]), float(e["h"]))).grow(2.0)


## What the pointer acts on: {tile, tree}. Clear (and Demolish off a building) resolve a canopy to the tile its
## trunk stands on, so the trunk's tile is marked / unmarked rather than the empty tile behind the leaves.
func _tool_hover() -> Dictionary:
	var raw := _mouse_tile()
	if _layer() != Building.LAYER_GROUND:
		return {"tile": raw, "tree": {}}
	if mode == Mode.CLEAR or (mode == Mode.DEMOLISH and settlement.building_at(raw, Building.LAYER_GROUND) == null):
		return pick_clear(settlement, ghost.get_global_mouse_position())
	return {"tile": raw, "tree": {}}


## The tile a click or drag acts on.
func _tool_tile() -> Vector2i:
	return _tool_hover()["tile"]


func _process(_d: float) -> void:
	if settlement == null or ghost == null:
		return
	var hover := _tool_hover()
	var t: Vector2i = hover["tile"]
	if mode == Mode.NONE:
		ghost.set_hover(t, Vector2i.ONE)
		return
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
		Mode.CLEAR:
			var cm := settlement.is_clear_marked(t)
			var cc := settlement.can_mark_clear(t)
			ghost.set_state(null, t, cc["ok"] or cm, true)
			_hint.text = _clear_hint(t, cm, cc)
		Mode.PLANT:
			var pm := settlement.is_plant_marked(t)
			var pc := settlement.can_mark_plant(t)
			ghost.set_state(null, t, pc["ok"] or pm, true)
			_hint.text = _plant_hint(t, pm, pc)
		Mode.DEMOLISH:
			var dl := _layer()
			var b := settlement.building_at(t, dl)
			ghost.set_state(null, t, (b != null and b != settlement.hearth) or _road_level(t, dl) != 0
					or (dl == Building.LAYER_GROUND and (settlement.channel_at(t) or settlement.track_at(t) or settlement.is_clear_marked(t) or settlement.is_plant_marked(t))), true)
	# The thin tile outline on the pointer tools (ticket 160), with the tree or building that would go.
	match mode:
		Mode.CLEAR:
			ghost.set_hover(t, Vector2i.ONE, hover["tree"])
		Mode.DEMOLISH:
			var hb := settlement.building_at(t, _layer())
			ghost.set_hover(t, hb.def.size if hb != null else Vector2i.ONE, hover["tree"])
		Mode.PLANT:
			ghost.set_hover(t, Vector2i.ONE)
		_:
			ghost.clear_hover()


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
			KEY_Z: set_mode(Mode.CLEAR)
			KEY_Y: set_mode(Mode.PLANT)
			KEY_U: set_mode(Mode.UPGRADE)
			KEY_ESCAPE: cancel()
	elif event is InputEventMouseButton and mode != Mode.NONE:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_click(_tool_tile())
			else:
				_painting = false
	elif event is InputEventMouseMotion and _painting and (mode == Mode.ROAD or mode == Mode.CHANNEL or mode == Mode.PAVED or mode == Mode.TRACK or mode == Mode.CLEAR or mode == Mode.PLANT):
		_paint_to(_tool_tile())


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
		Mode.CLEAR:
			if _layer() == Building.LAYER_GROUND:  # marks are on the ground map
				_painting = true
				_last_tile = t
				if not settlement.unmark_clear(t):  # a click on a marked tile takes the mark off, on any other puts one on
					settlement.mark_clear(t)
		Mode.PLANT:
			if _layer() == Building.LAYER_GROUND:
				_painting = true
				_last_tile = t
				if not settlement.unmark_plant(t):  # like Clear: a click on a marked tile unmarks, on any other marks
					settlement.mark_plant(t)
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
			elif settlement.is_clear_marked(t):
				settlement.unmark_clear(t)
			elif settlement.is_plant_marked(t):
				settlement.unmark_plant(t)
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
		return {"ok": false, "text": "%s: %s" % [nm, hm.upgrade_reason_text(str(can["reason"]), nxt, b.def)]}
	var info := hm.upgrade_info(b)
	return {"ok": true, "id": b.id, "name": nm, "text": "%s: click to upgrade to %s (%s)" % [nm, info["next_name"], info["next_cost"]]}


## What the Clear tool says about tile t (cm: it is marked, c: can_mark_clear).
func _clear_hint(t: Vector2i, cm: bool, c: Dictionary) -> String:
	if cm:
		var cs := settlement.get_system(ConstructionSystem) as ConstructionSystem
		var far := cs != null and cs.clear_far.has(MapState.idx(t.x, t.y))
		return "Clear: marked%s (click or X unmarks)" % (", no Builder's Yard can reach it" if far else "")
	if c["ok"]:
		return "Clear: click-drag to mark (right click cancels)"
	return "Clear: %s" % HudModel.clear_refusal_text(str(c["reason"]))


## What the Plant tool says about tile t (pm: it is marked, c: can_mark_plant).
func _plant_hint(t: Vector2i, pm: bool, c: Dictionary) -> String:
	if pm:
		var far := settlement.plant_mark_unreached(t)
		return "Plant: marked%s (click or X unmarks)" % (", no Forester reaches it" if far else "")
	if c["ok"]:
		return "Plant: click-drag to mark (right click cancels)"
	return "Plant: %s" % HudModel.plant_refusal_text(str(c["reason"]))


func _channel_hint(cost: String) -> String:
	var help := settlement.registry.water.channel_help() if settlement.registry.water != null else ""
	return "Channel (%s a tile): click-drag (right click cancels)\n%s" % [cost, help]


func _channel_cost() -> String:
	var c := settlement.registry.water.channel_cost_stone if settlement.registry.water != null else 0.0
	return "%d stone" % roundi(c)


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
		elif mode == Mode.CLEAR:
			settlement.mark_clear(cur)  # a drag only marks, so a pass over a marked tile keeps its mark
		elif mode == Mode.PLANT:
			settlement.mark_plant(cur)
		else:
			settlement.place_road(cur, Settlement.ROAD_DIRT, _layer())
	_last_tile = t
