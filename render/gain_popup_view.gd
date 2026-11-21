class_name GainPopupView
extends Node2D
## The gain popup (ticket 137): a small "+N" with the good's icon over a building with BuildingDef.gain_popup
## (Woodcutter, Quarry) or over a Clear tile, when whole goods are made. Pixel font, white with a 1 px dark outline,
## rises 10 px and fades out over about a second; no glow, bounce, sparkles or colour flash.
##
## Reads the ledger's made goods only (ResourceLedgerSystem.made_by_today, polled as a delta) and the Clear
## clear_marks_changed events for the tile of a clear yield. Nothing in the sim is written. The spawn rules themselves
## live in GainPopupModel; the Settings panel's "Gain popups" switch and the farthest zoom hide it.

const TILE := ArtLibrary.TILE
## How often the ledger is polled for new made goods (production settles per in-game hour).
const POLL_SECONDS := 0.25
## Icons and text of the popup, in world pixels (the text stays readable at every zoom step).
const ICON_SIZE := 10.0
const ICON_GAP := 2.0
const TEXT_SIZE := 16
## The dark outline around the white text, in pixels.
const OUTLINE := 1
const WHITE := Color(1, 1, 1)
const DARK := Color(0.08, 0.07, 0.06)

var settlement: Settlement
var settings: GameSettings
var model := GainPopupModel.new()
var _seen: Dictionary = {}  # "good|def id" -> made amount at the last poll
var _poll := 0.0
var _font: FontFile
var _marked_terrain: Dictionary = {}  # tile -> terrain id of a marked Clear job (the tile turns grass when cleared)
var _cleared: Array[Dictionary] = []  # {def_id, tile}: cleared tiles waiting for their ledger delta


func setup(s: Settlement, st: GameSettings) -> void:
	settlement = s
	settings = st
	model.settings = st
	_font = Hud._pixel_font(Hud.BODY_FONT_PATH)
	z_index = 6  # inside MapView.fx, over the night render
	s.events.subscribe("clear_marks_changed", func(entry: Dictionary) -> void: _on_clear_event(entry["data"]))
	# The ledger's made counters restart with the day: drop the old keys so no delta compares across the roll.
	s.events.subscribe("day_started", func(_entry: Dictionary) -> void: _seen = {})
	_remember_marks()
	_seen = snapshot(s)
	queue_redraw()


# ---------------------------------------------------------------- read-only sim queries

## True at every zoom step but the farthest (D46: the popups hide with the walkers).
static func shown_at_zoom(zoom_value: float) -> bool:
	return not CameraController.is_farthest_zoom(zoom_value)


## What every good made today, per producing def: "good|def id" -> amount. A read of the ledger only.
static func snapshot(s: Settlement) -> Dictionary:
	var out := {}
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	if ledger == null:
		return out
	for good in ledger.made_by_today:
		var by: Dictionary = ledger.made_by_today[good]
		for def_id in by:
			out["%s|%s" % [good, def_id]] = float(by[def_id])
	return out


## Made goods since `seen`: [{key, good, def_id, amount}], one per good and producing def. Reads the ledger only.
static func made_since(s: Settlement, seen: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	if ledger == null:
		return out
	for good in ledger.made_by_today:
		var by: Dictionary = ledger.made_by_today[good]
		for def_id in by:
			var key := "%s|%s" % [good, def_id]
			var delta := float(by[def_id]) - float(seen.get(key, 0.0))
			if delta > Inventory.EPS:
				out.append({"key": key, "good": str(good), "def_id": str(def_id), "amount": delta})
	return out


## True when a ledger made key earns a popup: a def with the gain_popup flag, or a Clear yield (clear_<terrain>).
static func gain_source(s: Settlement, def_id: String) -> bool:
	if def_id.begins_with(ConstructionSystem.CLEAR_PREFIX):
		var terrain := s.registry.get_terrain(def_id.trim_prefix(ConstructionSystem.CLEAR_PREFIX))
		return terrain != null and terrain.clear_good != "" and terrain.clear_amount > 0.0
	var def := s.registry.get_building(def_id)
	return def != null and def.gain_popup


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if settlement == null:
		return
	model.enabled = settings == null or settings.gain_popups
	model.tick(delta)
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var show := cam == null or shown_at_zoom(cam.zoom.x)
	if visible != show:
		visible = show
	_poll += delta
	if _poll >= POLL_SECONDS:
		_poll = 0.0
		_collect(show)
	if not model.popups().is_empty():
		queue_redraw()


## Turns the ledger delta into popup notes: per finished building of a gain_popup def, or over a cleared tile. The
## seen snapshot advances even while hidden, so zooming back in never replays old gains.
func _collect(show: bool) -> void:
	var gains := made_since(settlement, _seen)
	_seen = snapshot(settlement)
	if not show:
		_cleared.clear()  # hidden at the far zoom: the gains pass unseen, no popup waits for the zoom-in
	for g in gains:
		var good := str(g["good"])
		var def_id := str(g["def_id"])
		if not gain_source(settlement, def_id):
			continue
		var amount := float(g["amount"])
		if def_id.begins_with(ConstructionSystem.CLEAR_PREFIX):
			var tiles := _take_cleared(def_id)
			if tiles.is_empty():
				continue
			var share := amount / float(tiles.size())
			for t: Vector2i in tiles:
				var at := Vector2(t.x + 0.5, t.y)
				if show and _on_screen(at):
					model.note("clear:%d" % MapState.idx(t.x, t.y), good, share, at)
			continue
		var def := settlement.registry.get_building(def_id)
		var bs := _buildings_of(def)
		if bs.is_empty():
			continue
		var share := amount / float(bs.size())
		for b in bs:
			var at := Vector2(float(b.origin.x) + float(b.def.size.x) * 0.5, float(b.origin.y))
			if show and _on_screen(at):
				model.note(b.id, good, share, at)


func _buildings_of(def: BuildingDef) -> Array[Building]:
	var out: Array[Building] = []
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.def == def and not b.site:
			out.append(b)
	out.sort_custom(func(a: Building, c: Building) -> bool: return a.id < c.id)
	return out


## Cleared tiles of this ledger def, removed from the queue (they are consumed once).
func _take_cleared(def_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rest: Array[Dictionary] = []
	for e in _cleared:
		if str(e["def_id"]) == def_id:
			out.append(e["tile"])
		else:
			rest.append(e)
	_cleared = rest
	return out


## A marked tile's terrain is remembered for its Clear yield (the tile is grass by the time the clear event fires).
func _on_clear_event(e: Dictionary) -> void:
	var t: Vector2i = e["tile"]
	if bool(e.get("marked", false)):
		var d := settlement.registry.get_terrain(settlement.map.terrain_id_at(t.x, t.y))
		if d != null:
			_marked_terrain[t] = d.id
	elif bool(e.get("cleared", false)):
		var terrain := str(_marked_terrain.get(t, ""))
		_marked_terrain.erase(t)
		if terrain != "":
			_cleared.append({"def_id": ConstructionSystem.CLEAR_PREFIX + terrain, "tile": t})
	else:
		_marked_terrain.erase(t)


## Marks already standing when the view is created (a save loaded mid-clear).
func _remember_marks() -> void:
	var cs := settlement.get_system(ConstructionSystem) as ConstructionSystem
	if cs == null:
		return
	for idx in cs.clear_marks:
		var t := Vector2i(int(idx) % MapState.WIDTH, int(idx) / MapState.WIDTH)
		var d := settlement.registry.get_terrain(settlement.map.terrain_id_at(t.x, t.y))
		if d != null:
			_marked_terrain[t] = d.id


## True when a popup at `at` (tile coordinates) falls inside the visible world, with a tile of margin.
func _on_screen(at: Vector2) -> bool:
	if not is_inside_tree():
		return true
	var view := get_viewport_transform().affine_inverse() * get_viewport_rect()
	return view.grow(TILE).has_point(at * TILE)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not model.allowed():
		return
	var pops := model.popups()
	if pops.is_empty():
		return
	var zoom := 1.0
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	if cam != null and cam.zoom.x > 0.0:
		zoom = cam.zoom.x
	var fs := Hud._px_size(TEXT_SIZE)
	for p in pops:
		var k := clampf(float(p["age"]) / GainPopupModel.LIFE, 0.0, 1.0)
		var alpha := 1.0 if k <= 1.0 / 3.0 else clampf(1.0 - (k - 1.0 / 3.0) / (2.0 / 3.0), 0.0, 1.0)
		var base := Vector2(p["at"]) * float(TILE) - Vector2(0.0, GainPopupModel.RISE * k / zoom)
		var text := "+%d" % int(p["units"])
		var tex := _icon(str(p["good"]))
		var iw := ICON_SIZE if tex != null else 0.0
		var gap := ICON_GAP if tex != null else 0.0
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := base.x - (iw + gap + tw) * 0.5
		var top := base.y - ICON_SIZE * 0.5
		var white := Color(WHITE, alpha)
		var dark := Color(DARK, alpha)
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(x, top), Vector2(ICON_SIZE, ICON_SIZE)), false, white)
		var pos := Vector2(x + iw + gap, top + ICON_SIZE * 0.5 + fs * 0.35)
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OUTLINE, dark)
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)


## The good's HUD icon (lumen cells and every food share theirs), null when the good has none.
func _icon(good: String) -> Texture2D:
	var icons: Dictionary = ArtLibrary.manifest()["icons"]
	var id := good
	if good == "lumen_cells":
		id = "cells"
	elif not icons.has(id) and GrowthSystem.food_goods(settlement.registry).has(good):
		id = "food"
	if not icons.has(id):
		return null
	return ArtLibrary.texture(icons[id])
