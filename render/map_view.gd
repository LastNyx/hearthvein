class_name MapView
extends Node2D
## Draws a MapState with a TileMapLayer plus a region overlay (dimmed locked regions, thin borders).
## Reads the sim only; never writes to it.

const TILE := TileAtlas.TILE

var map: MapState
var _layer: TileMapLayer
var _overlay: RegionOverlay


func setup(m: MapState) -> void:
	map = m
	_layer = TileMapLayer.new()
	_layer.tile_set = TileAtlas.build_tileset()
	_layer.rendering_quadrant_size = 16
	add_child(_layer)
	var rows := PackedInt32Array()
	for id in map.terrain_ids:
		rows.append(TileAtlas.row_of(id))
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := map.get_terrain(x, y)
			var id := map.terrain_ids[t]
			var col := TileAtlas.variant_for(id, x, y)
			_layer.set_cell(Vector2i(x, y), 0, Vector2i(col, rows[t]))
	_overlay = RegionOverlay.new()
	_overlay.map = map
	add_child(_overlay)


func world_size() -> Vector2:
	return Vector2(MapState.WIDTH * TILE, MapState.HEIGHT * TILE)


func hearth_world_pos() -> Vector2:
	return (Vector2(map.hearth_spot) + Vector2(0.5, 0.5)) * TILE


class RegionOverlay extends Node2D:
	const DIM := Color(0.02, 0.03, 0.08, 0.42)
	const BORDER_OWNED := Color(1.0, 0.9, 0.5, 0.55)
	const BORDER_LOCKED := Color(0.8, 0.85, 1.0, 0.35)
	var map: MapState
	var _seen: PackedByteArray = PackedByteArray()

	func _process(_d: float) -> void:
		if map != null and map.region_owned != _seen:
			_seen = map.region_owned.duplicate()
			queue_redraw()

	func _draw() -> void:
		if map == null:
			return
		for r in MapState.REGION_COUNT:
			var rc := MapState.region_rect(r)
			var rect := Rect2(Vector2(rc.position) * TILE, Vector2(rc.size) * TILE)
			var owned := map.is_region_owned(r)
			if not owned:
				draw_rect(rect, DIM)
			draw_rect(rect, BORDER_OWNED if owned else BORDER_LOCKED, false, 2.0)
