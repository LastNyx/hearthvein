class_name PlacementView
extends Node2D
## Draws roads and placed buildings from a Settlement, plus the "no road" icon over unconnected ones.
## Reads the sim only. Redraws when the sim emits placement events.

const TILE := TileAtlas.TILE

var settlement: Settlement
var _road_tex: Array[Array] = []  # level -> variants


func setup(s: Settlement) -> void:
	settlement = s
	for level in 3:
		var arr: Array[Texture2D] = []
		if level > 0:
			for v in 2:
				arr.append(ImageTexture.create_from_image(BuildingArt.road_image(level, v)))
		_road_tex.append(arr)
	for kind in ["building_placed", "building_demolished", "road_changed", "building_connection_changed"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void: queue_redraw())
	queue_redraw()


func _draw() -> void:
	if settlement == null:
		return
	var roads := settlement.roads
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var lv := roads[MapState.idx(x, y)]
			if lv > 0:
				var tex: Texture2D = _road_tex[lv][TileAtlas.variant_for("grass", x, y) % 2]
				draw_texture(tex, Vector2(x, y) * TILE)
	var ids := settlement.buildings.keys()
	ids.sort()
	var list: Array[Building] = []
	for id in ids:
		list.append(settlement.buildings[id])
	list.sort_custom(func(a: Building, b: Building) -> bool: return a.origin.y < b.origin.y)
	for b in list:
		draw_texture(BuildingArt.texture_for(b.def), Vector2(b.origin) * TILE)
		if not b.connected:
			_draw_no_road(b)


func _draw_no_road(b: Building) -> void:
	var c := Vector2(b.origin) * TILE + Vector2(b.def.size.x * TILE - 8, 8)
	draw_circle(c, 7.0, Color(0.1, 0.05, 0.05, 0.9))
	draw_circle(c, 6.0, Color("d8362e"))
	draw_rect(Rect2(c + Vector2(-3.5, -1.5), Vector2(7, 3)), Color.WHITE)
	draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(0.1, 0.05, 0.05), 2.0)
