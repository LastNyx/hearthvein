class_name PlacementView
extends Node2D
## Shows roads and placed buildings from a Settlement using the exported sprites (roads on the MapView road
## layer, buildings as y-sorted sprites in the MapView object layer), plus the "no road" icon over unconnected
## buildings. Construction sites (D48) show a dirt plot, a wooden scaffold, the building sprite rising bottom-up with
## the build progress and a progress bar (orange while goods are delivered, green while building); the real sprite
## replaces all of it on building_completed. Reads the sim only. Updates when the sim emits placement events.

const TILE := ArtLibrary.TILE

var settlement: Settlement
var view: MapView
var _nodes: Dictionary = {}  # building id -> Array[Node]


func setup(s: Settlement, v: MapView) -> void:
	settlement = s
	view = v
	z_index = 20  # the no-road icon sits above sprites and glows
	for kind in ["building_placed", "building_demolished", "road_changed", "building_connection_changed", "building_completed"]:
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
		"building_completed":
			if _nodes.has(e["id"]):
				for n in _nodes[e["id"]]:
					(n as CanvasItem).visible = true
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
		# Props come back unless a building still covers the tile.
		view.set_props_visible(t, settlement.building_at(t) == null)
		return
	view.set_props_visible(t, false)  # roads cover rock/vein/tree props
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
	holder.visible = not b.site  # a site draws itself in _draw
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
	if b.site:  # shadow and glows wait for the finished building
		for n in list:
			(n as CanvasItem).visible = false
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


func _process(_d: float) -> void:
	if settlement == null:
		return
	for id in settlement.buildings:
		if (settlement.buildings[id] as Building).site:
			queue_redraw()
			return


func _draw() -> void:
	if settlement == null:
		return
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.site:
			_draw_site(b)
		if not b.connected:
			_draw_no_road(b)


## Share of the cost already delivered to a site, 0..1.
func _delivered_share(b: Building) -> float:
	var need := 0.0
	var have := 0.0
	for g in b.def.cost:
		if g != BuildingDef.GOLD:
			need += float(b.def.cost[g])
			have += minf(float(b.def.cost[g]), b.input_buffer.amount_of(g))
	return have / need if need > 0.0 else 1.0


func _draw_site(b: Building) -> void:
	var fr := Rect2(Vector2(b.origin) * TILE, Vector2(b.def.size) * TILE)
	var r := ArtLibrary.sprite_rect(b.def.id, b.origin, b.def.size)
	var p := b.build_progress()
	draw_rect(fr, Color(0.45, 0.34, 0.2, 0.7))
	draw_rect(fr, Color(0.25, 0.17, 0.09, 0.9), false, 1.0)
	if p > 0.0:
		var tex := ArtLibrary.texture(ArtLibrary.building_entry(b.def.id)["file"])
		var h := r.size.y * p
		draw_texture_rect_region(tex, Rect2(r.position.x, r.end.y - h, r.size.x, h),
				Rect2(0, r.size.y - h, r.size.x, h), Color(1, 1, 1, 0.92))
	var wood := Color("8a6235")
	var dark := Color("4d3419")
	var top := fr.end.y - maxf(r.size.y * 0.75, 40.0)
	var xs := [fr.position.x + 1.0, fr.end.x - 1.0]
	for x: float in xs:
		draw_line(Vector2(x, fr.end.y), Vector2(x, top), dark, 4.0)
		draw_line(Vector2(x, fr.end.y), Vector2(x, top), wood, 2.0)
	var rungs := 3
	for i in range(1, rungs + 1):
		var y := fr.end.y - (fr.end.y - top) * float(i) / float(rungs)
		draw_line(Vector2(xs[0], y), Vector2(xs[1], y), dark, 3.0)
		draw_line(Vector2(xs[0], y), Vector2(xs[1], y), wood, 1.5)
	draw_line(Vector2(xs[0], fr.end.y), Vector2(xs[1], top), wood, 1.5)
	var bar := Rect2(fr.position.x, fr.end.y + 2.0, fr.size.x, 5.0)
	draw_rect(bar.grow(1.0), Color(0.05, 0.05, 0.05, 0.85))
	var building := b.site_delivered()
	var share := p if building else _delivered_share(b)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)),
			Color("5fc34a") if building else Color("e8a33a"))


func _draw_no_road(b: Building) -> void:
	var r := ArtLibrary.sprite_rect(b.def.id, b.origin, b.def.size)
	var c := Vector2(r.end.x - 6, r.position.y + 8)
	draw_circle(c, 7.0, Color(0.1, 0.05, 0.05, 0.9))
	draw_circle(c, 6.0, Color("d8362e"))
	draw_rect(Rect2(c + Vector2(-3.5, -1.5), Vector2(7, 3)), Color.WHITE)
	draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(0.1, 0.05, 0.05), 2.0)
