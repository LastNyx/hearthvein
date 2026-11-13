class_name OverlayView
extends Node2D
## Map overlays toggled from the HUD (HudModel.overlays): blight (strong tint on every blighted tile), water (wet land tinted blue, dry land faintly warm) and road
## connection (green footprint = connected to the Hearth, red = not, road tiles outlined). Also outlines the selected
## building. Reads the sim and the view-model only; redraws when something it shows changes.

const TILE := ArtLibrary.TILE

var settlement: Settlement
var model: HudModel
var _dirty := true
var _seen_selected := -2
var _seen_blight := false
var _seen_roads := false
var _seen_water := false
var _seen_coverage := false


func setup(s: Settlement, m: HudModel) -> void:
	settlement = s
	model = m
	z_index = 15
	for kind in ["blight_changed", "building_connection_changed", "building_placed", "building_demolished",
			"road_changed", "building_completed", "channel_changed"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void: _dirty = true)


func _process(_d: float) -> void:
	if model == null:
		return
	var sel := model.selected_id
	if sel != _seen_selected or model.overlay_on("blight") != _seen_blight or model.overlay_on("roads") != _seen_roads \
			or model.overlay_on("water") != _seen_water or model.overlay_on("coverage") != _seen_coverage:
		_seen_selected = sel
		_seen_blight = model.overlay_on("blight")
		_seen_roads = model.overlay_on("roads")
		_seen_water = model.overlay_on("water")
		_seen_coverage = model.overlay_on("coverage")
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
	if model.overlay_on("water"):
		var map := settlement.map
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if map.is_wet(x, y) and map.terrain_id_at(x, y) != "water":
					draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(0.2, 0.5, 0.95, 0.32))
				elif not map.is_wet(x, y):
					draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(0.85, 0.6, 0.25, 0.07))
	if model.overlay_on("coverage"):
		_draw_coverage()
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


## Coverage overlay: Market reach in a muted teal (tint + outline), coverage sources (Shrine) in a soft gold tint over
## the union of their areas with an outline each, then a mark on every finished home: green check = covered, dim red
## cross = not. The areas are the same footprint_gap measure the sim uses (HudModel.reach_areas).
func _draw_coverage() -> void:
	var market_col := Color(0.35, 0.7, 0.7)
	var gold_col := Color(1.0, 0.8, 0.3)
	var market_areas := model.reach_areas("market")
	for a in market_areas:
		draw_rect(Rect2(Vector2(a.position) * TILE, Vector2(a.size) * TILE), Color(market_col, 0.10))
	for a in market_areas:
		draw_rect(Rect2(Vector2(a.position) * TILE, Vector2(a.size) * TILE), Color(market_col, 0.6), false, 2.0)
	var areas := model.reach_areas("coverage")
	var seen := {}
	for a in areas:
		for y in range(a.position.y, a.end.y):
			for x in range(a.position.x, a.end.x):
				var key := MapState.idx(x, y)
				if not seen.has(key):
					seen[key] = true
					draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(gold_col, 0.2))
	for a in areas:
		var r := Rect2(Vector2(a.position) * TILE, Vector2(a.size) * TILE)
		draw_rect(r, Color(0.2, 0.12, 0.02, 0.8), false, 4.0)
		draw_rect(r, Color(gold_col, 0.95), false, 2.0)
	for h: Dictionary in model.coverage_homes():
		var b: Building = settlement.buildings[h["id"]]
		var c := (Vector2(b.origin) + Vector2(b.def.size)) * TILE - Vector2(9, 9)  # bottom-right corner of the footprint
		if h["covered"]:
			draw_circle(c, 8.0, Color(0.05, 0.25, 0.08, 0.9))
			draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]),
					Color(0.5, 1.0, 0.5), 2.5)
		else:
			draw_circle(c, 8.0, Color(0.25, 0.05, 0.05, 0.7))
			draw_line(c + Vector2(-3, -3), c + Vector2(3, 3), Color(0.9, 0.35, 0.35, 0.85), 2.0)
			draw_line(c + Vector2(-3, 3), c + Vector2(3, -3), Color(0.9, 0.35, 0.35, 0.85), 2.0)
