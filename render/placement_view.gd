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
var _sky_ids: Dictionary = {}  # id -> true for buildings on the sky layer (their tiles never touch ground props)
var _sky_canvas: SkyCanvas
var _channels_dirty := false
var _drawn_channels: Dictionary = {}  # tile -> true for every channel cell currently on the layer
var _smoke: Dictionary = {}  # building id -> chimney smoke Sprite2D (ticket 90); shown only while the building works
var _smoke_clock := 0.0
const SMOKE_EVERY := 0.5  # seconds between working checks


func setup(s: Settlement, v: MapView) -> void:
	settlement = s
	view = v
	v.prop_blocked = func(t: Vector2i) -> bool: return _level(t) > 0 or _dug(t) or settlement.track_at(t) or settlement.building_at(t) != null
	_sky_canvas = SkyCanvas.new()
	_sky_canvas.owner_view = self
	v.sky_draw.add_child(_sky_canvas)
	z_index = 20  # the no-road icon sits above sprites and glows
	for kind in ["building_placed", "building_demolished", "road_changed", "building_connection_changed", "building_completed", "building_upgraded"]:
		s.events.subscribe(kind, func(entry: Dictionary) -> void: _on_event(entry["kind"], entry["data"]))
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.roads[MapState.idx(x, y)] > 0:
				_refresh_road(Vector2i(x, y))
	s.events.subscribe("channel_changed", func(_e: Dictionary) -> void: _channels_dirty = true)
	s.events.subscribe("track_changed", func(e: Dictionary) -> void:
		var t: Vector2i = e["data"]["tile"]
		for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			_refresh_track(t + d))
	for i in s.sky_roads.size():
		if s.sky_roads[i] > 0:
			_refresh_sky_road(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH))
	for i in s.track.size():
		if s.track[i] != 0:
			_refresh_track(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH))
	for id in s.buildings:
		_add_building(s.buildings[id])
	_refresh_channels()
	refresh_smoke()
	queue_redraw()
	_sky_canvas.queue_redraw()




func _on_event(kind: String, e: Dictionary) -> void:
	match kind:
		"road_changed":
			var t: Vector2i = e["tile"]
			for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if int(e.get("layer", Building.LAYER_GROUND)) == Building.LAYER_SKY:
					_refresh_sky_road(t + d)
					continue
				_refresh_road(t + d)
				_refresh_track(t + d)  # a crossing tile switches between plain track and the crossing art
		"building_placed":
			if settlement.buildings.has(e["id"]) and not _nodes.has(e["id"]):
				_add_building(settlement.buildings[e["id"]])
		"building_completed":
			if _nodes.has(e["id"]):
				for n in _nodes[e["id"]]:
					(n as CanvasItem).visible = true
				refresh_smoke()
		"building_upgraded":
			if settlement.buildings.has(e["id"]):  # new tier: swap in its sprite
				_remove_building(e["id"], e["origin"], e["def"])
				_add_building(settlement.buildings[e["id"]])
		"building_demolished":
			_remove_building(e["id"], e["origin"], e["def"])
	queue_redraw()
	_sky_canvas.queue_redraw()


func _level(t: Vector2i) -> int:
	if not MapState.in_bounds(t.x, t.y):
		return 0
	return settlement.roads[MapState.idx(t.x, t.y)]


func _sky_level(t: Vector2i) -> int:
	if not MapState.in_bounds(t.x, t.y):
		return 0
	return settlement.sky_roads[MapState.idx(t.x, t.y)]


## Sky road tile on the island road layer (same atlas as the ground, 4-neighbour mask among sky roads).
func _refresh_sky_road(t: Vector2i) -> void:
	if not MapState.in_bounds(t.x, t.y):
		return
	var lv := _sky_level(t)
	if lv <= 0:
		view.sky_roads.erase_cell(t)
		return
	var mask := 0
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in 4:
		if _sky_level(t + dirs[i]) > 0:
			mask |= 1 << i
	view.sky_roads.set_cell(t, lv, ArtLibrary.road_coords(mask, t.x, t.y))


func _refresh_road(t: Vector2i) -> void:
	if not MapState.in_bounds(t.x, t.y):
		return
	var lv := _level(t)
	if lv <= 0:
		view.roads.erase_cell(t)
		view.bridges.erase_cell(t)
		# Props come back unless a building or track still covers the tile.
		view.set_props_visible(t, settlement.building_at(t) == null and not settlement.track_at(t))
		return
	view.set_props_visible(t, false)  # roads cover rock/vein/tree props
	var mask := 0
	for i in 4:
		if _level(t + [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][i]) > 0:
			mask |= 1 << i
	if settlement.is_water_tile(t):  # a bridge: the deck goes on its own layer and the water stays visible around it
		view.roads.erase_cell(t)
		view.bridges.set_cell(t, lv, Vector2i(mask, 0))
		return
	view.bridges.erase_cell(t)
	view.roads.set_cell(t, lv, ArtLibrary.road_coords(mask, t.x, t.y))


## Redraw one track tile (only the tiles a track_changed touches): the 4-neighbour mask picks straight, corner, T or
## cross from the track atlas. A lifted tile gives its props back unless a road, channel or building holds the tile.
func _refresh_track(t: Vector2i) -> void:
	if not MapState.in_bounds(t.x, t.y):
		return
	if not settlement.track_at(t):
		view.track.erase_cell(t)
		view.set_props_visible(t, settlement.building_at(t) == null and _level(t) <= 0 and not _dug(t))
		return
	view.set_props_visible(t, false)
	var mask := 0
	var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in 4:
		if settlement.track_at(t + dirs[i]):
			mask |= 1 << i
	var src := 1 if _level(t) > 0 else 0  # source 1: level crossing over a road (a bridge deck, on water)
	if src == 0 and settlement.is_water_tile(t):
		src = ArtLibrary.BRIDGE_TRESTLE  # rail bridge with no road deck under it
	view.track.set_cell(t, src, Vector2i(mask, 0))


func _dug(t: Vector2i) -> bool:
	return settlement.channel_at(t)


## Redraw every channel tile: flow is global (one new tile can make a whole line flow), so the layer is rebuilt
## from the channel grid and WaterSystem.flowing_channels. Looks: dry earth ditch, or the same with water in it.
func _refresh_channels() -> void:
	_channels_dirty = false
	var flow := WaterSystem.flowing_channels(settlement)
	var now: Dictionary = {}
	var at := settlement.channels.find(Settlement.CHANNEL_DUG)
	while at >= 0:
		now[Vector2i(at % MapState.WIDTH, at / MapState.WIDTH)] = true
		at = settlement.channels.find(Settlement.CHANNEL_DUG, at + 1)
	for t: Vector2i in _drawn_channels:
		if not now.has(t):
			view.channels.erase_cell(t)
			view.set_props_visible(t, settlement.building_at(t) == null and _level(t) <= 0)
	for t: Vector2i in now:
		var mask := 0
		var dirs := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
		for i in 4:
			if now.has(t + dirs[i]):
				mask |= 1 << i
		var src := ArtLibrary.CHANNEL_FLOWING if flow[MapState.idx(t.x, t.y)] != 0 else ArtLibrary.CHANNEL_DRY
		view.channels.set_cell(t, src, Vector2i(mask, 0))
		view.set_props_visible(t, false)
	_drawn_channels = now


## Manifest id of the building's sprite: its tier art where the manifest has it, else the base sprite.
func _art_id(b: Building) -> String:
	var id := b.tier_art_id(settlement.registry)
	return id if id != "" and ArtLibrary.manifest()["buildings"].has(id) else b.def.id


func _add_building(b: Building) -> void:
	var e := ArtLibrary.building_entry(_art_id(b))
	var base := ArtLibrary.base_point(b.origin, b.def.size)
	var list: Array = []
	var holder := Node2D.new()
	holder.position = base
	holder.add_child(ArtLibrary.building_sprite(_art_id(b)))
	holder.visible = not b.site  # a site draws itself in _draw
	# A flat building (the Park) lies on the ground: a tall neighbour in front must overhang it, never hide it.
	# A sky building (layer 1) lives in the sky group; a Sky Lift (ground building, also on the island) in `lifts`, solid in both views.
	var sky := b.layer == Building.LAYER_SKY
	var parent: Node = view.objects
	var shadow_parent: Node = view.shadows
	var fx_parent: Node = view.fx
	if sky:
		parent = view.sky_objects
		shadow_parent = view.sky_shadows
		fx_parent = view.sky_fx
	elif b.def.sky_lift:
		parent = view.lifts
	elif e.get("flat", false):
		parent = view.flats
	parent.add_child(holder)
	list.append(holder)
	var sh := ArtLibrary.shadow_sprite(e)
	if sh != null:
		sh.position = base
		shadow_parent.add_child(sh)
		list.append(sh)
	var f := ArtLibrary.fx_sprite(e)
	if f != null:
		f.position = base
		fx_parent.add_child(f)
		list.append(f)
	var sm := ArtLibrary.smoke_sprite(e)
	if sm != null:
		sm.position = base
		sm.visible = false  # refresh_smoke turns it on while the building works
		fx_parent.add_child(sm)
		list.append(sm)
		_smoke[b.id] = sm
	_nodes[b.id] = list
	if b.site:  # shadow and glows wait for the finished building
		for n in list:
			(n as CanvasItem).visible = false
	if sky:
		_sky_ids[b.id] = true
	else:
		for t in b.tiles():
			view.set_props_visible(t, false)


func _remove_building(id: int, origin: Vector2i, def_id: String) -> void:
	for n in _nodes.get(id, []):
		(n as Node).queue_free()
	_nodes.erase(id)
	_smoke.erase(id)
	if _sky_ids.erase(id):
		_sky_canvas.queue_redraw()
		return
	var def := settlement.registry.get_building(def_id)
	for y in def.size.y:
		for x in def.size.x:
			view.set_props_visible(origin + Vector2i(x, y), true)


func _process(delta: float) -> void:
	if settlement == null:
		return
	if _channels_dirty:
		_refresh_channels()
	_smoke_clock += delta
	if _smoke_clock >= SMOKE_EVERY:
		_smoke_clock = 0.0
		refresh_smoke()
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.site or b.upgrading():
			queue_redraw()
			_sky_canvas.queue_redraw()
			return


## Is the building's chimney lit: finished and not paused, and either staffed right now (someone at work there),
## housing with a resident, or a building that needs neither workers nor residents (the Hearth).
func smoke_active(b: Building, work_counts: Dictionary, homes: Dictionary) -> bool:
	if b.site or b.paused:
		return false
	if b.def.worker_slots > 0:
		return work_counts.get(b.id, 0) > 0
	if b.def.housing_beds > 0:
		return homes.has(b.id)
	return true


## Show the smoke of the working buildings, hide it elsewhere. One pass over walkers and citizens, twice a second.
func refresh_smoke() -> void:
	if _smoke.is_empty() or settlement == null:
		return
	var ws := settlement.get_system(WalkerSystem) as WalkerSystem
	var counts: Dictionary = ws.work_counts() if ws != null else {}
	var homes := {}
	for cid in settlement.citizens:
		homes[(settlement.citizens[cid] as Citizen).home_id] = true
	for id in _smoke:
		var b: Building = settlement.buildings.get(id)
		(_smoke[id] as Sprite2D).visible = b != null and smoke_active(b, counts, homes)


func _draw() -> void:
	_draw_layer(self, Building.LAYER_GROUND)


## Construction sites, upgrade bars and no-road icons of the buildings on `layer`, drawn on `ci` (this node for the
## ground, the SkyCanvas inside the sky group for islands).
func _draw_layer(ci: CanvasItem, layer: int) -> void:
	if settlement == null:
		return
	for id in settlement.buildings:
		var b: Building = settlement.buildings[id]
		if b.layer != layer:
			continue
		if b.site:
			_draw_site(ci, b)
		elif b.upgrading():
			_draw_upgrade_bar(ci, b)
		if not b.connected:
			_draw_no_road(ci, b)


## Draw node of the sky group: forwards to PlacementView._draw_layer for the sky layer.
class SkyCanvas extends Node2D:
	var owner_view: PlacementView

	func _draw() -> void:
		if owner_view != null:
			owner_view._draw_layer(self, Building.LAYER_SKY)


## Share of the cost already delivered to a site, 0..1.
func _delivered_share(b: Building) -> float:
	var need := 0.0
	var have := 0.0
	for g in b.def.cost:
		if g != BuildingDef.GOLD:
			need += float(b.def.cost[g])
			have += minf(float(b.def.cost[g]), b.input_buffer.amount_of(g))
	return have / need if need > 0.0 else 1.0


func _draw_site(ci: CanvasItem, b: Building) -> void:
	var fr := Rect2(Vector2(b.origin) * TILE, Vector2(b.def.size) * TILE)
	var r := ArtLibrary.sprite_rect(b.def.id, b.origin, b.def.size)
	var p := b.build_progress()
	var art := ArtLibrary.site_art(b.def.size, r.size.y)
	ci.draw_texture(art["plot"], fr.position)
	if p > 0.0:  # the finished sprite rises bottom-up behind the scaffold
		var tex := ArtLibrary.texture(ArtLibrary.building_entry(b.def.id)["file"])
		var h := r.size.y * p
		ci.draw_texture_rect_region(tex, Rect2(r.position.x, r.end.y - h, r.size.x, h),
				Rect2(0, r.size.y - h, r.size.x, h), Color(1, 1, 1, 0.95))
	var sc: Texture2D = art["scaffold"]
	ci.draw_texture(sc, Vector2(fr.position.x, fr.end.y - sc.get_height()))
	var bar := Rect2(fr.position.x, fr.end.y + 2.0, fr.size.x, 5.0)
	ci.draw_rect(bar.grow(1.0), Color(0.05, 0.05, 0.05, 0.85))
	var building := b.site_delivered()
	var share := p if building else _delivered_share(b)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)),
			Color("5fc34a") if building else Color("e8a33a"))


## Progress bar under a building that is being upgraded, same look as a site's: orange while goods are delivered,
## green while builders work.
func _draw_upgrade_bar(ci: CanvasItem, b: Building) -> void:
	var fr := Rect2(Vector2(b.origin) * TILE, Vector2(b.def.size) * TILE)
	var bar := Rect2(fr.position.x, fr.end.y + 2.0, fr.size.x, 5.0)
	ci.draw_rect(bar.grow(1.0), Color(0.05, 0.05, 0.05, 0.85))
	var working := b.upgrade_delivered()
	var share := b.upgrade_progress()
	if not working:
		var need := 0.0
		var have := 0.0
		for g in b.upgrade_cost:
			need += float(b.upgrade_cost[g])
			have += minf(float(b.upgrade_cost[g]), b.upgrade_buffer.amount_of(g))
		share = have / need if need > 0.0 else 1.0
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)),
			Color("5fc34a") if working else Color("e8a33a"))


func _draw_no_road(ci: CanvasItem, b: Building) -> void:
	var r := ArtLibrary.sprite_rect(b.def.id, b.origin, b.def.size)
	var c := Vector2(r.end.x - 6, r.position.y + 8)
	ci.draw_circle(c, 7.0, Color(0.1, 0.05, 0.05, 0.9))
	ci.draw_circle(c, 6.0, Color("d8362e"))
	ci.draw_rect(Rect2(c + Vector2(-3.5, -1.5), Vector2(7, 3)), Color.WHITE)
	ci.draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color(0.1, 0.05, 0.05), 2.0)
