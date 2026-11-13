class_name MapView
extends Node2D
## Draws a MapState: terrain base layer, soft transition overlays, y-sorted trees/boulders with shadows, and a
## region overlay (dimmed locked regions, thin borders). Art comes from ArtLibrary only. Reads the sim only.
##
## Child order (back to front): Base, one overlay layer per ground (Shade, the broad tonal patches, sits after the
## soil one), Roads (filled by PlacementView), Shadows, Objects (y-sorted: props and
## buildings share it), Fx (glows, smoke), region overlay.

const TILE := ArtLibrary.TILE

var map: MapState
var roads: TileMapLayer
var shadows: Node2D
var objects: Node2D
var fx: Node2D
var _base: TileMapLayer
var _shade: Sprite2D
var _shade_image: Image
var _shade_dirty := false
var _overlay: RegionOverlay
var _props: Dictionary = {}  # Vector2i -> Array[Node]
var _ground := PackedStringArray()
var _overlays: Dictionary = {}  # ground -> TileMapLayer


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
		if g == "soil":  # tonal patches sit over the ground blends but under rock, vein and sky edges
			_shade = Sprite2D.new()
			_shade.name = "Shade"
			_shade.centered = false
			_shade.scale = Vector2(TILE, TILE)
			_shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			add_child(_shade)
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
	_ground = ground
	_overlays = overlays
	_fill()
	_shade_image = ArtLibrary.shade_image(map.seed_used, MapState.WIDTH, MapState.HEIGHT, _ground_at)
	_shade.texture = ImageTexture.create_from_image(_shade_image)
	_overlay = RegionOverlay.new()
	_overlay.map = map
	add_child(_overlay)


func _ground_at(x: int, y: int) -> String:
	return _ground[map.get_terrain(x, y)]


func _fill() -> void:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			_paint_base(x, y)
			_paint_overlays(x, y)
			_add_props(map.terrain_id_at(x, y), x, y)


func _paint_base(x: int, y: int) -> void:
	var cell := ArtLibrary.terrain_cell(map.terrain_id_at(x, y), x, y, map.seed_used)
	_base.set_cell(Vector2i(x, y), cell[0], cell[1])
	if _shade_image != null:  # during setup the whole image is built in one pass
		_shade_image.set_pixel(x, y, ArtLibrary.shade_color(map.seed_used, _ground_at(x, y), x, y))
		_shade_dirty = true


## Soft transition overlays of higher grounds onto this tile (cleared first, so it can be called again).
func _paint_overlays(x: int, y: int) -> void:
	var bits := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
			Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	var here := _ground_at(x, y)
	var rank := ArtLibrary.ground_rank(here)
	for g in ArtLibrary.overlay_grounds():
		var layer: TileMapLayer = _overlays[g]
		layer.erase_cell(Vector2i(x, y))
		if ArtLibrary.ground_rank(g) <= rank:
			continue
		var mask := 0
		for i in 8:
			var nx: int = x + bits[i].x
			var ny: int = y + bits[i].y
			if MapState.in_bounds(nx, ny) and _ground_at(nx, ny) == g:
				mask |= 1 << i
		if mask != 0:
			var c := ArtLibrary.overlay_coords(mask, here == "water", ArtLibrary.tile_hash(map.seed_used + 3, x, y))
			if c.x >= 0:
				layer.set_cell(Vector2i(x, y), 0, c)


## Redraw one tile after its terrain changed (Settlement event terrain_changed): base cell, the overlays of the
## tile and its 8 neighbours, and the tile's props (trees go, stump appears).
func refresh_tile(tile: Vector2i) -> void:
	if map == null or not MapState.in_bounds(tile.x, tile.y):
		return
	_paint_base(tile.x, tile.y)
	if _shade_dirty:
		(_shade.texture as ImageTexture).update(_shade_image)
		_shade_dirty = false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := tile + Vector2i(dx, dy)
			if MapState.in_bounds(n.x, n.y):
				_paint_overlays(n.x, n.y)
	for n in _props.get(tile, []):
		(n as Node).queue_free()
	_props.erase(tile)
	_add_props(map.terrain_id_at(tile.x, tile.y), tile.x, tile.y)


## Sum of directions toward neighbouring tiles of another ground (zero inside a stand), for edge-tree jitter.
func _open_dir(x: int, y: int) -> Vector2i:
	var here := _ground_at(x, y)
	var d := Vector2i.ZERO
	for o in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if MapState.in_bounds(x + o.x, y + o.y) and _ground_at(x + o.x, y + o.y) != here:
			d += o
	return d


func _add_props(terrain_id: String, x: int, y: int) -> void:
	for p in ArtLibrary.scatter(terrain_id, x, y, _open_dir(x, y)):
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
