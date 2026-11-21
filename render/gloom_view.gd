class_name GloomView
extends Node2D
## The gloom overlay (ticket 149): flat dark purple-black steps over the gloom tiles, darkest where the creep is
## deepest, and a 2x2 pixel checker on the ragged front once it has grown three rings (mockup
## .scratch/v1/mockups/nightlife/nl_dimming_night.png). It reads GloomSystem only and draws nothing outside a Dimming
## night; it sits in MapView.fx under the additive NightView pools, so lamp light still reads on top of the gloom.

const TILE := ArtLibrary.TILE
const COLOR := Color(0.10, 0.03, 0.16)
## Alpha per depth, from the first ring (depth 0, the forest) deeper and darker.
const STEPS: Array[float] = [0.78, 0.66, 0.54, 0.42, 0.32, 0.22, 0.14]
## The front goes ragged from this depth on: a 2x2 pixel checker, as the mockup draws it.
const RAGGED_FROM := 3

var settlement: Settlement
var _seen: int = -1
var _tiles: Dictionary = {}
var _max: int = -1
var _checker: ImageTexture


func setup(s: Settlement) -> void:
	settlement = s
	_seen = -1
	refresh()


## Rebuilds the view from GloomSystem and schedules a redraw.
func refresh() -> void:
	_tiles = {}
	_max = -1
	var g := _gloom()
	if g != null:
		_seen = g.version()
		_tiles = g.tiles
		_max = g.max_depth()
	queue_redraw()


func _process(_delta: float) -> void:
	var g := _gloom()
	if g != null and g.version() != _seen:
		refresh()


func _gloom() -> GloomSystem:
	if settlement == null:
		return null
	return settlement.get_system(GloomSystem) as GloomSystem


func _draw() -> void:
	var ragged := _max >= RAGGED_FROM
	for t: Vector2i in _tiles:
		var d := int(_tiles[t])
		var col := COLOR
		col.a = STEPS[mini(d, STEPS.size() - 1)]
		var rect := Rect2(Vector2(t) * TILE, Vector2(TILE, TILE))
		if ragged and d == _max:
			draw_texture_rect(_checker_texture(), rect, false, col)
		else:
			draw_rect(rect, col)


## A TILE x TILE checker of 2x2 pixel blocks, white at full and half alpha; the draw's modulate tints and fades it.
func _checker_texture() -> ImageTexture:
	if _checker != null:
		return _checker
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var on := ((x / 2) + (y / 2)) % 2 == 0
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if on else 0.5))
	_checker = ImageTexture.create_from_image(img)
	return _checker
