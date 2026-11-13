class_name OverlayView
extends Node2D
## Map overlays toggled from the HUD (HudModel.overlays): blight (strong tint on every blighted tile) and road
## connection (green footprint = connected to the Hearth, red = not, road tiles outlined). Also outlines the selected
## building. Reads the sim and the view-model only; redraws when something it shows changes.

const TILE := ArtLibrary.TILE

var settlement: Settlement
var model: HudModel
var _dirty := true
var _seen_selected := -2
var _seen_blight := false
var _seen_roads := false


func setup(s: Settlement, m: HudModel) -> void:
	settlement = s
	model = m
	z_index = 15
	for kind in ["blight_changed", "building_connection_changed", "building_placed", "building_demolished",
			"road_changed", "building_completed"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void: _dirty = true)


func _process(_d: float) -> void:
	if model == null:
		return
	var sel := model.selected_id
	if sel != _seen_selected or model.overlay_on("blight") != _seen_blight or model.overlay_on("roads") != _seen_roads:
		_seen_selected = sel
		_seen_blight = model.overlay_on("blight")
		_seen_roads = model.overlay_on("roads")
		_dirty = true
	if _dirty:
		_dirty = false
		queue_redraw()


func _draw() -> void:
	if settlement == null:
		return
	if model.overlay_on("blight"):
		var map := settlement.map
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if map.is_blighted(x, y):
					draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(0.62, 0.2, 0.85, 0.42))
					draw_rect(Rect2(x * TILE + 1, y * TILE + 1, TILE - 2, TILE - 2), Color(0.85, 0.5, 1.0, 0.5), false, 1.0)
	if model.overlay_on("roads"):
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if settlement.roads[MapState.idx(x, y)] > 0:
					draw_rect(Rect2(x * TILE + 3, y * TILE + 3, TILE - 6, TILE - 6), Color(1.0, 0.9, 0.35, 0.5))
		for id in settlement.buildings:
			var b: Building = settlement.buildings[id]
			var r := Rect2(Vector2(b.origin) * TILE, Vector2(b.def.size) * TILE)
			var c := Color(0.25, 0.85, 0.35, 0.4) if b.connected else Color(0.9, 0.2, 0.2, 0.55)
			draw_rect(r, c)
			draw_rect(r, c.lightened(0.3), false, 2.0)
	var sb := model.selected()
	if sb != null:
		var r := Rect2(Vector2(sb.origin) * TILE, Vector2(sb.def.size) * TILE).grow(2.0)
		draw_rect(r, Color(0.05, 0.03, 0.02, 0.9), false, 4.0)
		draw_rect(r, Color("f2d27a"), false, 2.0)
