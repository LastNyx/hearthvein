class_name VeinSurgeView
extends Node2D
## Vein surge sparkles (ticket 150): a seeded scatter of white pixel crosses on every Lumen vein tile while the
## surge after a Dimming runs (mockup .scratch/v1/mockups/nightlife/nl_surge.png). Reads DimmingSystem only and draws
## nothing outside the surge; sits in MapView.fx under the light pools, over the ground.

const TILE := ArtLibrary.TILE
const COLOR := Color(0.86, 0.97, 1.0, 0.9)
## Cross positions are seeded per tile, so the scatter never flickers between frames.
const SEED_OFFSET := 61

var settlement: Settlement
var map: MapState
var _on: bool = false
var _tiles: Array[Vector2i] = []


func setup(s: Settlement, m: MapState) -> void:
	settlement = s
	map = m
	_on = false
	_tiles.clear()
	refresh()


func _process(_delta: float) -> void:
	if not is_inside_tree() or settlement == null:
		return
	if DimmingSystem.vein_surge(settlement) != _on:
		refresh()


## Rebuilds the tile list when the surge starts or ends, and schedules a redraw.
func refresh() -> void:
	_on = DimmingSystem.vein_surge(settlement) if settlement != null else false
	_tiles.clear()
	if _on and map != null:
		var vein := map.terrain_index("lumen_vein")
		if vein >= 0:
			for y in MapState.HEIGHT:
				for x in MapState.WIDTH:
					if map.get_terrain(x, y) == vein:
						_tiles.append(Vector2i(x, y))
	queue_redraw()


func _draw() -> void:
	if not _on:
		return
	for t in _tiles:
		var h := ArtLibrary.tile_hash(map.seed_used + SEED_OFFSET, t.x, t.y)
		_cross(t, 5 + h % 22, 6 + (h >> 5) % 20)
		if (h >> 10) % 3 != 0:
			var h2 := ArtLibrary.tile_hash(map.seed_used + SEED_OFFSET + 1, t.x, t.y)
			_cross(t, 5 + h2 % 22, 6 + (h2 >> 5) % 20)


## A 5-pixel plus at (px, py) inside tile t, the pixel-cross sparkle of the mockup.
func _cross(t: Vector2i, px: int, py: int) -> void:
	var p := t * TILE + Vector2i(px, py)
	draw_rect(Rect2(p.x, p.y, 1, 1), COLOR)
	draw_rect(Rect2(p.x - 1, p.y, 1, 1), COLOR)
	draw_rect(Rect2(p.x + 1, p.y, 1, 1), COLOR)
	draw_rect(Rect2(p.x, p.y - 1, 1, 1), COLOR)
	draw_rect(Rect2(p.x, p.y + 1, 1, 1), COLOR)
