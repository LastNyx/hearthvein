class_name PlacementView
extends Node2D
## Shows roads and placed buildings from a Settlement using the exported sprites (roads on the MapView road
## layer, buildings as y-sorted sprites in the MapView object layer), plus the "no road" icon over unconnected
## buildings. Reads the sim only. Updates when the sim emits placement events.

const TILE := ArtLibrary.TILE

var settlement: Settlement
var view: MapView
var _nodes: Dictionary = {}  # building id -> Array[Node]


func setup(s: Settlement, v: MapView) -> void:
	settlement = s
	view = v
	z_index = 20  # the no-road icon sits above sprites and glows
	for kind in ["building_placed", "building_demolished", "road_changed", "building_connection_changed"]:
		s.events.subscribe(kind, func(entry: Dictionary) -> void: _on_event(entry["kind"], entry["data"]))
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.roads[MapState.idx(x, y)] > 0:
				_refresh_road(Vector2i(x, y))
	for id in s.buildings:
		_add_building(s.buildings[id])
	queue_redraw()


func _on_event(kind: String, e: Dictionary) -> void:
	match kind:
		"road_changed":
			var t: Vector2i = e["tile"]
			for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				_refresh_road(t + d)
		"building_placed":
			if settlement.buildings.has(e["id"]) and not _nodes.has(e["id"]):
				_add_building(settlement.buildings[e["id"]])
		"building_demolished":
			_remove_building(e["id"], e["origin"], e["def"])
	queue_redraw()


func _level(t: Vector2i) -> int:
	if not MapState.in_bounds(t.x, t.y):
		return 0
	return settlement.roads[MapState.idx(t.x, t.y)]


func _refresh_road(t: Vector2i) -> void:
	if not MapState.in_bounds(t.x, t.y):
		return
	var lv := _level(t)
	if lv <= 0:
		view.roads.erase_cell(t)
		return
	var mask := 0
	for i in 4:
		if _level(t + [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][i]) > 0:
			mask |= 1 << i
	view.roads.set_cell(t, lv, ArtLibrary.road_coords(mask, t.x, t.y))


func _add_building(b: Building) -> void:
	var e := ArtLibrary.building_entry(b.def.id)
	var base := ArtLibrary.base_point(b.origin, b.def.size)
	var list: Array = []
	var holder := Node2D.new()
	holder.position = base
	holder.add_child(ArtLibrary.building_sprite(b.def.id))
	view.objects.add_child(holder)
	list.append(holder)
	var sh := ArtLibrary.shadow_sprite(e)
	if sh != null:
		sh.position = base
		view.shadows.add_child(sh)
		list.append(sh)
	var f := ArtLibrary.fx_sprite(e)
	if f != null:
		f.position = base
		view.fx.add_child(f)
		list.append(f)
	_nodes[b.id] = list
	for t in b.tiles():
		view.set_props_visible(t, false)


func _remove_building(id: int, origin: Vector2i, def_id: String) -> void:
	for n in _nodes.get(id, []):
		(n as Node).queue_free()
	_nodes.erase(id)
	var def := settlement.registry.get_building(def_id)
	for y in def.size.y:
		for x in def.size.x:
			view.set_props_visible(origin + Vector2i(x, y), true)


func _draw() -> void:
	if settlement == null:
		return
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if not b.connected:
			_draw_no_road(b)


func _draw_no_road(b: Building) -> void:
	var r := ArtLibrary.sprite_rect(b.def.id, b.origin, b.def.size)
	var c := Vector2(r.end.x - 6, r.position.y + 8)
	draw_circle(c, 7.0, Color(0.1, 0.05, 0.05, 0.9))
	draw_circle(c, 6.0, Color("d8362e"))
	draw_rect(Rect2(c + Vector2(-3.5, -1.5), Vector2(7, 3)), Color.WHITE)
	draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(0.1, 0.05, 0.05), 2.0)
