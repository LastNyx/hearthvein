class_name MapView
extends Node2D
## Draws a MapState: terrain base layer, soft transition overlays, y-sorted trees/boulders with shadows, and a
## region overlay (dimmed locked regions, thin borders). Art comes from ArtLibrary only. Reads the sim only.
##
## Child order (back to front): Base, one overlay layer per ground, Roads (filled by PlacementView), Shadows,
## Objects (y-sorted: props and buildings share it), Fx (glows, smoke), region overlay.

const TILE := ArtLibrary.TILE

var map: MapState
var roads: TileMapLayer
var shadows: Node2D
var objects: Node2D
var fx: Node2D
var _base: TileMapLayer
var _overlay: RegionOverlay
var _props: Dictionary = {}  # Vector2i -> Array[Node]


func setup(m: MapState) -> void:
	map = m
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_base = TileMapLayer.new()
	_base.name = "Base"
	_base.tile_set = ArtLibrary.terrain_tileset()
	_base.rendering_quadrant_size = 16
	add_child(_base)
	var ground: PackedStringArray = PackedStringArray()
	for id in map.terrain_ids:
		ground.append(ArtLibrary.ground_of(id) if ArtLibrary.has_terrain(id) else "grass")
	var overlays := {}
	for g in ArtLibrary.overlay_grounds():
		var layer := TileMapLayer.new()
		layer.name = "Overlay_" + g
		layer.tile_set = ArtLibrary.overlay_tileset(g)
		layer.rendering_quadrant_size = 16
		add_child(layer)
		overlays[g] = layer
	roads = TileMapLayer.new()
	roads.name = "Roads"
	roads.tile_set = ArtLibrary.road_tileset()
	add_child(roads)
	shadows = Node2D.new()
	shadows.name = "Shadows"
	add_child(shadows)
	objects = Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)
	fx = Node2D.new()
	fx.name = "Fx"
	add_child(fx)
	_fill(ground, overlays)
	_overlay = RegionOverlay.new()
	_overlay.map = map
	add_child(_overlay)


func _ground_at(ground: PackedStringArray, x: int, y: int) -> String:
	return ground[map.get_terrain(x, y)]


func _fill(ground: PackedStringArray, overlays: Dictionary) -> void:
	var grounds: Array[String] = ArtLibrary.overlay_grounds()
	var bits := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
			Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := map.get_terrain(x, y)
			var id := map.terrain_ids[t]
			var cell := ArtLibrary.terrain_cell(id, x, y)
			_base.set_cell(Vector2i(x, y), cell[0], cell[1])
			var here := ground[t]
			var rank := ArtLibrary.ground_rank(here)
			for g in grounds:
				if ArtLibrary.ground_rank(g) <= rank:
					continue
				var mask := 0
				for i in 8:
					var nx: int = x + bits[i].x
					var ny: int = y + bits[i].y
					if MapState.in_bounds(nx, ny) and _ground_at(ground, nx, ny) == g:
						mask |= 1 << i
				if mask != 0:
					var c := ArtLibrary.overlay_coords(mask, here == "water")
					if c.x >= 0:
						(overlays[g] as TileMapLayer).set_cell(Vector2i(x, y), 0, c)
			_add_props(id, x, y)


func _add_props(terrain_id: String, x: int, y: int) -> void:
	for p in ArtLibrary.scatter(terrain_id, x, y):
		var e := ArtLibrary.prop_entry(p["name"])
		var holder := Node2D.new()
		holder.position = p["pos"]
		holder.add_child(ArtLibrary.prop_sprite(p["name"]))
		objects.add_child(holder)
		var list: Array = _props.get(Vector2i(x, y), [])
		list.append(holder)
		var sh := ArtLibrary.shadow_sprite(e)
		if sh != null:
			sh.position = p["pos"]
			shadows.add_child(sh)
			list.append(sh)
		var f := ArtLibrary.fx_sprite(e)
		if f != null:
			f.position = p["pos"]
			fx.add_child(f)
			list.append(f)
		_props[Vector2i(x, y)] = list


## Hide or show the props of a tile (buildings cover vein/rock props).
func set_props_visible(tile: Vector2i, vis: bool) -> void:
	for n in _props.get(tile, []):
		(n as CanvasItem).visible = vis


func world_size() -> Vector2:
	return Vector2(MapState.WIDTH * TILE, MapState.HEIGHT * TILE)


func hearth_world_pos() -> Vector2:
	return (Vector2(map.hearth_spot) + Vector2(0.5, 0.5)) * TILE


class RegionOverlay extends Node2D:
	const DIM := Color(0.02, 0.03, 0.08, 0.42)
	const BORDER_OWNED := Color(1.0, 0.9, 0.5, 0.55)
	const BORDER_LOCKED := Color(0.8, 0.85, 1.0, 0.35)
	var map: MapState
	var _seen: PackedByteArray = PackedByteArray()

	func _process(_d: float) -> void:
		if map != null and map.region_owned != _seen:
			_seen = map.region_owned.duplicate()
			queue_redraw()

	func _draw() -> void:
		if map == null:
			return
		for r in MapState.REGION_COUNT:
			var rc := MapState.region_rect(r)
			var rect := Rect2(Vector2(rc.position) * TILE, Vector2(rc.size) * TILE)
			var owned := map.is_region_owned(r)
			if not owned:
				draw_rect(rect, DIM)
			draw_rect(rect, BORDER_OWNED if owned else BORDER_LOCKED, false, 2.0)
