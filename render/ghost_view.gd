class_name GhostView
extends Node2D
## Placement preview: footprint tiles tinted green when valid, red when not, with the building sprite faded in.

const TILE := ArtLibrary.TILE
const VALID := Color(0.2, 0.9, 0.3, 0.45)
const INVALID := Color(0.95, 0.2, 0.2, 0.5)

var def: BuildingDef = null   # null with show_tile = true draws a single tile (road / demolish tool)
var tile := Vector2i.ZERO
var valid := false
var show_tile := false


static func color_for(is_valid: bool) -> Color:
	return VALID if is_valid else INVALID


func set_state(d: BuildingDef, t: Vector2i, is_valid: bool, visible_tile: bool) -> void:
	def = d
	tile = t
	valid = is_valid
	show_tile = visible_tile
	visible = visible_tile
	queue_redraw()


func _draw() -> void:
	if not show_tile:
		return
	var size := def.size if def != null else Vector2i.ONE
	var col := color_for(valid)
	if def != null:
		draw_texture(ArtLibrary.texture(ArtLibrary.building_entry(def.id)["file"]), ArtLibrary.sprite_rect(def.id, tile, def.size).position, Color(1, 1, 1, 0.6))
	draw_rect(Rect2(Vector2(tile) * TILE, Vector2(size) * TILE), col)
	draw_rect(Rect2(Vector2(tile) * TILE, Vector2(size) * TILE), Color(col.r, col.g, col.b, 1.0), false, 2.0)
