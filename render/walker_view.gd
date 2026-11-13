class_name WalkerView
extends Node2D
## Draws every walking citizen in one _draw pass (no node per walker). Walkers standing at a building door
## are inside it and not drawn. Reads the sim only; redraws each frame.

const TILE := ArtLibrary.TILE
const BODY := Color(0.20, 0.30, 0.55)
const HEAD := Color(0.93, 0.78, 0.62)
const SHADOW := Color(0, 0, 0, 0.3)

var settlement: Settlement
var _system: WalkerSystem


func setup(s: Settlement) -> void:
	settlement = s
	_system = s.get_system(WalkerSystem)
	z_index = 10  # above the y-sorted objects, below the no-road icons


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _system == null:
		return
	for id in _system.walkers:
		var w: Walker = _system.walkers[id]
		if not w.is_walking():
			continue
		var p := w.position() * TILE
		draw_rect(Rect2(p + Vector2(-5, 0), Vector2(10, 4)), SHADOW)
		draw_rect(Rect2(p + Vector2(-3, -9), Vector2(6, 9)), BODY)
		draw_rect(Rect2(p + Vector2(-2, -13), Vector2(4, 4)), HEAD)
