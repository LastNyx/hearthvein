class_name BoatView
extends Node2D
## Draws one cargo boat for every hauler riding a river link (ticket 153), in a single _draw pass with no node per boat.
## The sim's trip holds the river tiles and the ride progress; the boat slides along them and is mirrored when it runs
## west. Reads the sim only; nothing is drawn when no hauler is on the water.

var settlement: Settlement
var _hauling: HaulingSystem
var _tex: Texture2D
var _foot := Vector2(19, 18)
var _drawing := false


func setup(s: Settlement) -> void:
	settlement = s
	_hauling = s.get_system(HaulingSystem)
	var e := ArtLibrary.prop_entry("river_boat")
	_tex = ArtLibrary.texture(e["file"])
	_foot = Vector2(float(e["base"][0]), float(e["base"][1]))
	z_index = 9  # above the water and its shore, below the walkers


func _process(_d: float) -> void:
	var any := _hauling != null and _hauling.has_boats()
	if any or _drawing:
		_drawing = any
		queue_redraw()


func _draw() -> void:
	if _hauling == null:
		return
	var tile := float(ArtLibrary.TILE)
	for boat in _hauling.active_boats():
		var path: Array = boat["path"]
		if path.is_empty():
			continue
		var q: float = float(boat["progress"]) * float(path.size() - 1)
		var i := mini(int(q), maxi(path.size() - 2, 0))
		var a: Vector2i = path[i]
		var b: Vector2i = path[mini(i + 1, path.size() - 1)]
		var p := (Vector2(a).lerp(Vector2(b), q - float(i)) + Vector2(0.5, 0.5)) * tile
		draw_set_transform(p.round(), 0.0, Vector2(-1.0, 1.0) if b.x < a.x else Vector2.ONE)
		draw_texture(_tex, -_foot)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
