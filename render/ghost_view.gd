class_name GhostView
extends Node2D
## Placement preview: footprint tiles tinted green when valid, red when not, with the building sprite faded in.

const TILE := ArtLibrary.TILE
const VALID := Color(0.2, 0.9, 0.3, 0.45)
const INVALID := Color(0.95, 0.2, 0.2, 0.5)
const WET := Color(0.25, 0.55, 0.95, 0.35)

var def: BuildingDef = null   # null with show_tile = true draws a single tile (road / demolish tool)
var tile := Vector2i.ZERO
var valid := false
var show_tile := false
## Tiles a channel placed here would wet (ticket 95), tinted blue under the tile.
var wet_tiles: Array[Vector2i] = []
## Hover marker (ticket 160): a thin outline on the tile or footprint the pointer acts on, even with no tool active,
## and the tree a Clear / Demolish click would fell, tinted red.
var hover_on := false
var hover_tile := Vector2i.ZERO
var hover_size := Vector2i.ONE
var hover_tree: Dictionary = {}


static func color_for(is_valid: bool) -> Color:
	return VALID if is_valid else INVALID


func set_state(d: BuildingDef, t: Vector2i, is_valid: bool, visible_tile: bool) -> void:
	def = d
	tile = t
	valid = is_valid
	show_tile = visible_tile
	wet_tiles = []
	visible = visible_tile or hover_on
	queue_redraw()


## Set after set_state: the wet preview of a channel.
func set_wet(tiles: Array[Vector2i]) -> void:
	wet_tiles = tiles
	queue_redraw()


## The hover marker: outline `size` tiles from `t`, and tint the `tree` prop {name, pos} that a Clear would fell.
func set_hover(t: Vector2i, size: Vector2i, tree: Dictionary = {}) -> void:
	hover_on = true
	hover_tile = t
	hover_size = size
	hover_tree = tree
	visible = true
	queue_redraw()


## No hover marker (a tool that draws its own footprint preview).
func clear_hover() -> void:
	if not hover_on:
		return
	hover_on = false
	hover_tree = {}
	visible = show_tile
	queue_redraw()


func _draw() -> void:
	if hover_on:
		var hr := Rect2(Vector2(hover_tile) * TILE, Vector2(hover_size) * TILE)
		draw_rect(hr, Color(0.05, 0.03, 0.02, 0.65), false, 2.0)
		draw_rect(hr.grow(-1.0), Color(1, 1, 1, 0.65), false, 1.0)
		if not hover_tree.is_empty():
			var e := ArtLibrary.prop_entry(String(hover_tree["name"]))
			var p: Vector2 = hover_tree["pos"]
			draw_texture(ArtLibrary.texture(e["file"]), p - Vector2(float(e["base"][0]), float(e["base"][1])),
					Color(1.0, 0.35, 0.3, 0.7))
	if not show_tile:
		return
	for w in wet_tiles:
		draw_rect(Rect2(Vector2(w) * TILE, Vector2(TILE, TILE)), WET)
	var size := def.size if def != null else Vector2i.ONE
	var col := color_for(valid)
	if def != null:
		draw_texture(ArtLibrary.texture(ArtLibrary.building_entry(def.id)["file"]), ArtLibrary.sprite_rect(def.id, tile, def.size).position, Color(1, 1, 1, 0.6))
	draw_rect(Rect2(Vector2(tile) * TILE, Vector2(size) * TILE), col)
	draw_rect(Rect2(Vector2(tile) * TILE, Vector2(size) * TILE), Color(col.r, col.g, col.b, 1.0), false, 2.0)
