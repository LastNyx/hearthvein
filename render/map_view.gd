class_name MapView
extends Node2D
## Draws a MapState: terrain base layer, soft ground blends, the water and rock dual-grid edges, y-sorted
## trees/boulders with shadows, and a region overlay (dimmed locked regions, thin borders). Art comes from
## ArtLibrary only. Reads the sim only.
##
## Child order (back to front): Base, the forest and soil blend layers, Shore and RockEdge (dual grid, half a tile
## shifted), Shade (broad tonal patches), the vein blend layer, Roads (filled by PlacementView), Shadows, Objects
## (y-sorted: props and buildings share it), Fx (glows, smoke), region overlay.

const TILE := ArtLibrary.TILE
## Dual-grid layers sit on map corners: the cell is drawn half a tile up-left of the corner it belongs to.
const DUAL_SHIFT := Vector2(-TILE / 2.0, -TILE / 2.0)
## The four map tiles around a corner, in the atlas bit order: TL=1, TR=2, BR=4, BL=8.
const DUAL_CORNERS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]

var map: MapState
var roads: TileMapLayer
var shadows: Node2D
var objects: Node2D
var fx: Node2D
var _base: TileMapLayer
var _shore: TileMapLayer     # water/land dual grid
var _rock_edge: TileMapLayer  # rock/land dual grid
var _blight: TileMapLayer  # blighted ground tint, over the ground blends
var _fouled: TileMapLayer  # fouled river tiles
var _shade: Sprite2D
var _shade_image: Image
var _shade_dirty := false
var _overlay: RegionOverlay
## Optional Callable(tile) -> bool: true where roads or a building cover the tile (PlacementView sets it), so props
## re-added by refresh_tile stay hidden there.
var prop_blocked: Callable = Callable()
var _sparkles: Dictionary = {}  # Vector2i -> Sprite2D
var _props: Dictionary = {}  # Vector2i -> Array[Node]
var _ground := PackedStringArray()
var _overlays: Dictionary = {}  # ground -> TileMapLayer


## At the farthest zoom step the soft prop and building shadows are too small to see: skip drawing them (ticket 18).
func _process(_delta: float) -> void:
	if shadows == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_2d()
	var show_shadows := cam == null or not CameraController.is_farthest_zoom(cam.zoom.x)
	if shadows.visible != show_shadows:
		shadows.visible = show_shadows


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
	# Ground blends first (forest and soil), then the water/rock dual-grid edges, then the broad meadow shade
	# (so the shore's land band is shaded like the meadow around it), then the vein edges on top of the rock.
	# RockEdge goes under Shore: on a rock/water/grass corner the rock atlas paints water corners on its own
	# side, and the shore draws the water back over them.
	for g in ["forest", "soil"]:
		if ArtLibrary.overlay_grounds().has(g):
			overlays[g] = _overlay_layer(g)
	_rock_edge = _autotile_layer("RockEdge", "rock")
	_shore = _autotile_layer("Shore", "water")
	_shade = Sprite2D.new()  # tonal patches over the ground blends but under the vein and sky edges
	_shade.name = "Shade"
	_shade.centered = false
	_shade.scale = Vector2(TILE, TILE)
	_shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_shade)
	for g in ArtLibrary.overlay_grounds():
		if not overlays.has(g):
			overlays[g] = _overlay_layer(g)
	_blight = _state_layer("Blight", "blight")
	_fouled = _state_layer("Fouled", "fouled")
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


func _overlay_layer(ground: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "Overlay_" + ground
	layer.tile_set = ArtLibrary.overlay_tileset(ground)
	layer.rendering_quadrant_size = 16
	add_child(layer)
	return layer


func _autotile_layer(layer_name: String, pair: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = ArtLibrary.autotile_tileset(pair)
	layer.rendering_quadrant_size = 16
	layer.position = DUAL_SHIFT
	add_child(layer)
	return layer


func _state_layer(layer_name: String, state: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = ArtLibrary.state_tileset(state)
	layer.rendering_quadrant_size = 16
	add_child(layer)
	return layer


## Redraw the blight and fouled tint around one tile (Settlement event blight_changed; ticket 29 calls it for
## fouling). The 8 neighbours are repainted too, because their soft edge depends on this tile.
func refresh_state(tile: Vector2i) -> void:
	if map == null or not MapState.in_bounds(tile.x, tile.y):
		return
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if MapState.in_bounds(tile.x + dx, tile.y + dy):
				_paint_state(tile.x + dx, tile.y + dy)
	_paint_sparkle(tile.x, tile.y)


const _NBR_BITS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]


func _flag(state: String, x: int, y: int) -> bool:
	return map.is_blighted(x, y) if state == "blight" else map.is_fouled(x, y)


func _paint_state(x: int, y: int) -> void:
	var c := Vector2i(x, y)
	for pair in [[_blight, "blight"], [_fouled, "fouled"]]:
		var layer: TileMapLayer = pair[0]
		var st: String = pair[1]
		if _flag(st, x, y):
			var v := ArtLibrary.tile_hash(map.seed_used + 5, x, y) % ArtLibrary.state_variants(st)
			layer.set_cell(c, 0, Vector2i(v, 0))
			continue
		var mask := 0
		for i in 8:
			var nx: int = x + _NBR_BITS[i].x
			var ny: int = y + _NBR_BITS[i].y
			if MapState.in_bounds(nx, ny) and _flag(st, nx, ny):
				mask |= 1 << i
		var e := ArtLibrary.state_edge_coords(mask) if mask != 0 else Vector2i(-1, -1)
		if e.x >= 0 and not (st == "blight" and _ground_at(x, y) == "water") and not (st == "fouled" and _ground_at(x, y) != "water"):
			layer.set_cell(c, 1, e)
		else:
			layer.erase_cell(c)
	_paint_sparkle(x, y)


## Seeded Lumen sparkle on some blighted tiles (Fx layer, so it sits above props).
func _paint_sparkle(x: int, y: int) -> void:
	var key := Vector2i(x, y)
	if _sparkles.has(key):
		(_sparkles[key] as Node).queue_free()
		_sparkles.erase(key)
	if not map.is_blighted(x, y) or _ground_at(x, y) == "water":
		return
	var sp := ArtLibrary.blight_sparkle(map.seed_used, x, y)
	if sp.is_empty():
		return
	var spr := ArtLibrary.prop_sprite(sp["name"])
	spr.position = sp["pos"]
	fx.add_child(spr)
	_sparkles[key] = spr


func _ground_at(x: int, y: int) -> String:
	return _ground[map.get_terrain(x, y)]


func _fill() -> void:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			_paint_base(x, y)
			_paint_overlays(x, y)
			_paint_state(x, y)
			_add_props(map.terrain_id_at(x, y), x, y)
	for j in MapState.HEIGHT + 1:
		for i in MapState.WIDTH + 1:
			_paint_dual(i, j)


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
		if here == "water" or ArtLibrary.ground_rank(g) <= rank:  # water shores come from the dual grid
			continue
		var mask := 0
		for i in 8:
			var nx: int = x + bits[i].x
			var ny: int = y + bits[i].y
			if MapState.in_bounds(nx, ny) and _ground_at(nx, ny) == g:
				mask |= 1 << i
		if mask != 0:
			var c := ArtLibrary.overlay_coords(mask, ArtLibrary.tile_hash(map.seed_used + 3, x, y))
			if c.x >= 0:
				layer.set_cell(Vector2i(x, y), 0, c)


## Draw the water/land and rock/land dual cells around the map corner (i, j): each looks at the four map tiles
## that meet there and picks the atlas by the highest lower ground among them.
func _paint_dual(i: int, j: int) -> void:
	_paint_dual_pair(_shore, "water", i, j)
	_paint_dual_pair(_rock_edge, "rock", i, j)


func _paint_dual_pair(layer: TileMapLayer, pair: String, i: int, j: int) -> void:
	var cell := Vector2i(i, j)
	layer.erase_cell(cell)
	var mask := 0
	var water_bits := 0
	var ground := ""
	var ground_rank := -1
	for k in 4:
		var p: Vector2i = cell + DUAL_CORNERS[k]
		if not MapState.in_bounds(p.x, p.y):
			return  # the map border keeps its plain tile edge
		var g := _ground_at(p.x, p.y)
		if g == pair:
			mask |= 1 << k
			continue
		var r := ArtLibrary.ground_rank(g)
		if pair == "rock":
			if g == "water":  # three-way corner: shape the rock against the land, the shore draws the water
				water_bits |= 1 << k
				continue
			# a ground above rock (vein, sky) owns its own edge
			if r >= ArtLibrary.ground_rank("rock"):
				return
		if r > ground_rank:
			ground_rank = r
			ground = g
	if mask == 0 or ground == "":
		return
	# Water counts as the pair side of the rock atlas, so a rock/water/grass corner still rounds the rock against
	# the grass instead of leaving a square corner; the Shore layer above repaints the water over it.
	mask |= water_bits
	if mask == 15:
		return
	var src := ArtLibrary.autotile_source(pair, ground)
	if src < 0:
		return
	layer.set_cell(cell, src, ArtLibrary.autotile_coords(mask))


## Redraw one tile after its terrain changed (Settlement event terrain_changed): base cell, the overlays of the
## tile and its 8 neighbours, the 4 dual cells at its corners, and the tile's props (trees go, stump appears).
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
	for dy in 2:
		for dx in 2:
			_paint_dual(tile.x + dx, tile.y + dy)
	for n in _props.get(tile, []):
		(n as Node).queue_free()
	_props.erase(tile)
	_add_props(map.terrain_id_at(tile.x, tile.y), tile.x, tile.y)
	if prop_blocked.is_valid() and prop_blocked.call(tile):
		set_props_visible(tile, false)


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
