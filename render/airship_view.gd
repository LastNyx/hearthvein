class_name AirshipView
extends Node2D
## Draws one small airship for every air shipment in flight (ticket 68), in a single _draw pass with no node per ship.
## The airship flies straight between the two docks by the shipment's progress (the sim derives it from the fractional
## game hour, so motion is smooth each frame), floats above the buildings with a soft shadow on the ground below it,
## faces its direction of travel (the sprite faces east, mirrored for west) and bobs a pixel or two, deterministic
## from time. Nothing is drawn at progress 1.0 (waiting to unload). Reads the sim only and allocates nothing per frame.

const ALTITUDE := 26.0  # pixels between the ground shadow and the hull
const SHADOW_DROP := 4.0  # extra pixels the shadow sits below the ground point (light from the upper left)

var settlement: Settlement
var _air: AirshipSystem
var _tex: Texture2D
var _shadow: Texture2D
var _cell := Vector2(48, 32)
var _foot := Vector2(24, 14)
var _shadow_cell := Vector2(48, 12)
var _drawing := false


func setup(s: Settlement) -> void:
	settlement = s
	_air = s.get_system(AirshipSystem)
	var e := ArtLibrary.airship_entry()
	_tex = ArtLibrary.texture(e["file"])
	_shadow = ArtLibrary.texture(e["shadow"])
	_cell = Vector2(e["cell"][0], e["cell"][1])
	_foot = Vector2(e["foot"][0], e["foot"][1])
	_shadow_cell = Vector2(e["shadow_cell"][0], e["shadow_cell"][1])
	z_index = 12  # above buildings, trains and walkers, below the no-road icons


func _process(_d: float) -> void:
	var any := _air != null and _air.ship_count() > 0
	if any or _drawing:
		_drawing = any
		queue_redraw()


## Bob in pixels (-1.5 .. 1.5, whole pixels after rounding by the caller) for ship i at time t seconds.
static func bob(t: float, i: int) -> float:
	return sin(t * 1.6 + float(i) * 1.9) * 1.5


func _draw() -> void:
	if _air == null:
		return
	var tile := float(ArtLibrary.TILE)
	var t := float(Time.get_ticks_msec()) / 1000.0
	for i in _air.ship_count():
		var progress := _air.ship_progress(settlement, i)
		if progress >= 1.0:
			continue
		var a := _air.ship_from(settlement, i)
		var b := _air.ship_to(settlement, i)
		var g := (a.lerp(b, progress) * tile).round()  # ground point under the airship
		var flip := -1.0 if b.x < a.x else 1.0
		var sp := g + Vector2(0.0, SHADOW_DROP)
		draw_set_transform(sp, 0.0, Vector2(flip, 1.0))
		draw_texture(_shadow, Vector2(-_shadow_cell.x * 0.5, -_shadow_cell.y * 0.5))
		var hp := g + Vector2(0.0, -ALTITUDE + roundf(bob(t, i)))
		draw_set_transform(hp, 0.0, Vector2(flip, 1.0))
		draw_texture(_tex, Vector2(-_foot.x, -_foot.y))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
