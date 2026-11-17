class_name TrainView
extends Node2D
## Draws one short train (a locomotive and two wagons) for every shipment in flight (ticket 37c), in a single _draw
## pass with no node per car. A train slides along the shipment's track path by its progress (the sim computes
## progress from the fractional game hour, so motion is smooth every frame), each car facing the way its own path
## segment runs. The head enters at the first track tile and leaves the track at the last one; at progress 1.0 (waiting
## to unload) nothing is drawn. Reads the sim only and allocates nothing per frame.

var settlement: Settlement
var _rail: RailManifestSystem
var _atlas: Texture2D
var _cell := Vector2(32, 32)
var _foot := Vector2(16, 20)
var _gap := 0.95
var _cars: Array = []  # atlas row per car, head first
var _drawing := false


func setup(s: Settlement) -> void:
	settlement = s
	_rail = s.get_system(RailManifestSystem)
	var e := ArtLibrary.train_entry()
	_atlas = ArtLibrary.texture(e["file"])
	_cell = Vector2(e["cell"][0], e["cell"][1])
	_foot = Vector2(e["foot"][0], e["foot"][1])
	_gap = float(e["gap"])
	for k in e["cars"]:
		_cars.append((e["kinds"] as Array).find(k))
	z_index = 9  # above the y-sorted objects, below the walkers


func _process(_d: float) -> void:
	var any := _rail != null and _rail.ship_count() > 0
	if any or _drawing:
		_drawing = any
		queue_redraw()


## Atlas column of a move vector: e, w, s, n (the manifest's dirs order).
static func dir_column(step: Vector2i) -> int:
	if step.x != 0:
		return 0 if step.x > 0 else 1
	return 2 if step.y > 0 else 3


func _draw() -> void:
	if _rail == null:
		return
	var tile := float(ArtLibrary.TILE)
	var n_cars := _cars.size()
	for i in _rail.ship_count():
		var progress := _rail.ship_progress(settlement, i)
		if progress >= 1.0:
			continue
		var path := _rail.ship_path(settlement, i)
		var n := path.size()
		if n == 0:
			continue
		var head := progress * (float(n - 1) + float(n_cars - 1) * _gap)
		for k in range(n_cars - 1, -1, -1):
			var q := head - float(k) * _gap
			if q < 0.0 or q > float(n - 1):
				continue
			var seg := mini(int(q), maxi(n - 2, 0))
			var a := path[seg]
			var step := Vector2i(1, 0)
			var p := (Vector2(a) + Vector2(0.5, 0.5)) * tile
			if n > 1:
				var b := path[seg + 1]
				step = b - a
				p += Vector2(step) * (q - float(seg)) * tile
			p = p.round()
			var region := Rect2(Vector2(dir_column(step), int(_cars[k])) * _cell, _cell)
			draw_texture_rect_region(_atlas, Rect2(p - _foot, _cell), region)
