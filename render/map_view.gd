class_name MapView
extends Node2D
## Draws a MapState: terrain base layer, soft ground blends, the water and rock dual-grid edges, y-sorted
## trees/boulders with shadows, and a region overlay (dimmed locked regions, thin borders). Art comes from
## ArtLibrary only. Reads the sim only.
##
## Child order (back to front): Base, the forest and soil blend layers, Shore and RockEdge (dual grid, half a tile
## shifted; Shore on top so the water and its bank cover the rock edge's dithered creep at the water tile's
## corner), Shade (broad tonal patches), the vein blend layer, Roads (filled by PlacementView), Shadows, Objects
## (y-sorted: props and buildings share it), Fx (glows, smoke), region overlay.

const TILE := ArtLibrary.TILE
## Dual-grid layers sit on map corners: the cell is drawn half a tile up-left of the corner it belongs to.
const DUAL_SHIFT := Vector2(-TILE / 2.0, -TILE / 2.0)
## The four map tiles around a corner, in the atlas bit order: TL=1, TR=2, BR=4, BL=8.
## Alpha of the sky layer seen from the ground view (islands and everything on them).
const GROUND_VIEW_SKY_ALPHA := 0.6
const DUAL_CORNERS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]

var map: MapState
var roads: TileMapLayer
var channels: TileMapLayer
var track: TileMapLayer
var shadows: Node2D
var flats: Node2D  # flat footprints (Park): on the ground, under every y-sorted object
var objects: Node2D
var fx: Node2D
## Sky layer (ticket 40d), all inside one CanvasGroup so a translucent island fades as one piece: skystone base and
## shore_sky rim tile layers (one batched TileMapLayer each), sky roads, y-sorted sky buildings with their shadows and
## glows, and a node PlacementView draws sky construction sites on. `lifts` holds Sky Lifts (they stand in both layers,
## so they are drawn solid in either view). SkyDim darkens the ground in the sky view.
var active_layer: int = 0  # Building.LAYER_GROUND; set through set_active_layer
var sky_group: CanvasGroup
var sky_base: TileMapLayer
var sky_rim: TileMapLayer     # cliff rim autotile (crisp: outside the faded group)
var sky_under: TileMapLayer   # stone hanging under the south edge
var sky_corners: Node2D       # corner tiles with the rounded bite cut out (inside the group)
var sky_cap_rims: Node2D      # cliff band round those bites
var sky_edge: Node2D          # rim + cap rims, z 31
var sky_roads: TileMapLayer
var sky_shadows: Node2D
var sky_objects: Node2D
var sky_fx: Node2D
var sky_draw: Node2D
var lifts: Node2D
var _sky_dim: SkyDim
var _island_shadow: IslandShadow
var _sky_rects: Array[Rect2i] = []
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
## Shadow and glow sprites of each tile's props (the prop sprites themselves are batched by PropBatch).
var _props: Dictionary = {}  # Vector2i -> Array[Node]
var _prop_batch: PropBatch = PropBatch.new()
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
		sky_shadows.visible = show_shadows


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
	# Shore goes above RockEdge: at a water corner the rock edge's dithered creep would otherwise speckle the
	# bank, and the shore's own quarters do not reach into a rock tile, so nothing of the rock edge is lost.
	for g in ["forest", "soil"]:
		if ArtLibrary.overlay_grounds().has(g):
			overlays[g] = _overlay_layer(g)
	_rock_edge = _autotile_layer("RockEdge", "rock")
	_fouled = _state_layer("Fouled", "fouled")  # under the shore line so the bank stays crisp over the murk
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
	roads = TileMapLayer.new()
	roads.name = "Roads"
	roads.tile_set = ArtLibrary.road_tileset()
	add_child(roads)
	channels = TileMapLayer.new()
	channels.name = "Channels"
	channels.tile_set = ArtLibrary.channel_tileset()
	add_child(channels)
	track = TileMapLayer.new()  # rail track (ticket 37c); a road+track crossing tile (ticket 67) would sit here too
	track.name = "Track"
	track.tile_set = ArtLibrary.track_tileset()
	add_child(track)
	shadows = Node2D.new()
	shadows.name = "Shadows"
	add_child(shadows)
	flats = Node2D.new()
	flats.name = "Flats"
	flats.y_sort_enabled = true
	add_child(flats)
	objects = Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)
	_prop_batch.setup(objects)  # bands are y-sorted children of Objects, added before any building
	fx = Node2D.new()
	fx.name = "Fx"
	add_child(fx)
	_build_sky()
	_ground = ground
	_overlays = overlays
	_fill()
	_prop_batch.flush()
	_shade_image = ArtLibrary.shade_image(map.seed_used, MapState.WIDTH, MapState.HEIGHT, _ground_at)
	_shade.texture = ImageTexture.create_from_image(_shade_image)
	_overlay = RegionOverlay.new()
	_overlay.map = map
	add_child(_overlay)


func _build_sky() -> void:
	_island_shadow = IslandShadow.new()
	_island_shadow.name = "IslandShadow"
	_island_shadow.z_index = 5
	add_child(_island_shadow)
	_sky_dim = SkyDim.new()
	_sky_dim.name = "SkyDim"
	_sky_dim.z_index = 25
	_sky_dim.size = world_size()
	_sky_dim.visible = false
	add_child(_sky_dim)
	sky_group = CanvasGroup.new()
	sky_group.name = "Sky"
	sky_group.z_index = 30
	sky_group.visible = false
	sky_group.modulate.a = GROUND_VIEW_SKY_ALPHA
	add_child(sky_group)
	sky_base = TileMapLayer.new()
	sky_base.name = "SkyBase"
	sky_base.tile_set = ArtLibrary.terrain_tileset()
	sky_base.rendering_quadrant_size = 16
	sky_group.add_child(sky_base)
	sky_corners = Node2D.new()
	sky_corners.name = "SkyCorners"
	sky_group.add_child(sky_corners)
	sky_roads = TileMapLayer.new()
	sky_roads.name = "SkyRoads"
	sky_roads.tile_set = ArtLibrary.road_tileset()
	sky_group.add_child(sky_roads)
	sky_shadows = Node2D.new()
	sky_shadows.name = "SkyShadows"
	sky_group.add_child(sky_shadows)
	sky_objects = Node2D.new()
	sky_objects.name = "SkyObjects"
	sky_objects.y_sort_enabled = true
	sky_group.add_child(sky_objects)
	sky_fx = Node2D.new()
	sky_fx.name = "SkyFx"
	sky_group.add_child(sky_fx)
	sky_draw = Node2D.new()
	sky_draw.name = "SkyDraw"
	sky_group.add_child(sky_draw)
	lifts = Node2D.new()
	lifts.name = "Lifts"
	lifts.y_sort_enabled = true
	lifts.z_index = 30
	add_child(lifts)
	# The rim and the underside stay crisp in the ground view while the island body is translucent: they sit outside
	# the faded group, the underside below it (z 29, it only hangs outside the data rect) and the rim above (z 31).
	sky_under = TileMapLayer.new()
	sky_under.name = "SkyUnder"
	sky_under.tile_set = ArtLibrary.sky_under_tileset()
	sky_under.rendering_quadrant_size = 16
	sky_under.z_index = 29
	sky_under.visible = false
	add_child(sky_under)
	sky_edge = Node2D.new()
	sky_edge.name = "SkyEdge"
	sky_edge.z_index = 31
	sky_edge.visible = false
	add_child(sky_edge)
	sky_rim = TileMapLayer.new()
	sky_rim.name = "SkyRim"
	sky_rim.tile_set = ArtLibrary.sky_rim_tileset()
	sky_rim.rendering_quadrant_size = 16
	sky_rim.position = DUAL_SHIFT
	sky_edge.add_child(sky_rim)
	sky_cap_rims = Node2D.new()
	sky_cap_rims.name = "SkyCapRims"
	sky_edge.add_child(sky_cap_rims)


## Switch the drawn layer (HudModel.layer_changed): the ground view shows the islands translucent over a normal
## ground; the sky view darkens the ground and draws the islands solid.
func set_active_layer(layer: int) -> void:
	active_layer = layer
	var sky := layer == 1  # Building.LAYER_SKY
	sky_group.modulate.a = 1.0 if sky else GROUND_VIEW_SKY_ALPHA
	_sky_dim.visible = sky and not _sky_rects.is_empty()


## Repaint every island from the sky map: skystone tiles in `rects` (the island rects), the cliff rim round them, the
## four corner tiles as rounded caps (drawn instead of the skystone cell; the data tiles are unchanged) and the
## underside hanging below the south edge. All of it is outside the data rect except the rim's 2 px lip.
func refresh_sky(sky: MapState, rects: Array[Rect2i]) -> void:
	_sky_rects = rects.duplicate()
	sky_base.clear()
	sky_rim.clear()
	sky_under.clear()
	for n in sky_corners.get_children():
		n.queue_free()
		sky_corners.remove_child(n)
	for n in sky_cap_rims.get_children():
		n.queue_free()
		sky_cap_rims.remove_child(n)
	var info := ArtLibrary.sky_rim_info()
	var fill_tex := ArtLibrary.texture(info["corner_fill"])
	var cap_tex := ArtLibrary.texture(info["corner_rim"])
	var cap_size: int = int(info["corner_size"])
	for r in rects:
		var corners: Array[Vector2i] = [r.position, Vector2i(r.end.x - 1, r.position.y),
				Vector2i(r.end.x - 1, r.end.y - 1), Vector2i(r.position.x, r.end.y - 1)]
		var skip := {}  # rim cells a cap covers (2x2 cells from each corner tile)
		for ci in 4:
			var c: Vector2i = corners[ci]
			for dj in 2:
				for di in 2:
					skip[c + Vector2i(di, dj)] = true
			var fill := Sprite2D.new()
			fill.texture = fill_tex
			fill.region_enabled = true
			fill.region_rect = Rect2(ci * TILE, 0, TILE, TILE)
			fill.centered = false
			fill.position = Vector2(c) * TILE
			sky_corners.add_child(fill)
			var cap := Sprite2D.new()
			cap.texture = cap_tex
			cap.region_enabled = true
			cap.region_rect = Rect2(ci * cap_size, 0, cap_size, cap_size)
			cap.centered = false
			cap.position = Vector2(c) * TILE - Vector2(TILE, TILE) / 2.0
			sky_cap_rims.add_child(cap)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if sky.terrain_id_at(x, y) == MapState.SKY_STONE and not corners.has(Vector2i(x, y)):
					var cell := ArtLibrary.terrain_cell(MapState.SKY_STONE, x, y, map.seed_used)
					sky_base.set_cell(Vector2i(x, y), cell[0], cell[1])
		for j in range(r.position.y, r.end.y + 1):
			for i in range(r.position.x, r.end.x + 1):
				if skip.has(Vector2i(i, j)):
					continue
				var mask := 0
				for k in 4:
					var p: Vector2i = Vector2i(i, j) + DUAL_CORNERS[k]
					if not MapState.in_bounds(p.x, p.y) or sky.terrain_id_at(p.x, p.y) != MapState.SKY_STONE:
						mask |= 1 << k
				if mask != 0 and mask != 15:
					sky_rim.set_cell(Vector2i(i, j), 0, ArtLibrary.autotile_coords(mask))
		_paint_underside(r)
	for c in sky_roads.get_used_cells():  # a removed island takes its roads with it (no road_changed event)
		if not _sky_rects.any(func(r: Rect2i) -> bool: return r.has_point(c)):
			sky_roads.erase_cell(c)
	_island_shadow.rects = _sky_rects
	_island_shadow.queue_redraw()
	var any := not _sky_rects.is_empty()
	sky_group.visible = any
	sky_edge.visible = any
	sky_under.visible = any
	_sky_dim.visible = active_layer == 1 and any


## Underside of one island: a row of stone hanging from the south edge (end pieces taper at the corners), and below
## the hosts in the middle stretch a stalactite, so the island tapers away to the south. Variants are hashed per tile.
func _paint_underside(r: Rect2i) -> void:
	var kinds: Array = ArtLibrary.sky_rim_info()["under_kinds"]
	var y := r.end.y
	for x in range(r.position.x, r.end.x):
		var h := absi(hash(Vector3i(x, y, map.seed_used)))
		var col: int
		if x == r.position.x:
			col = kinds.find("left")
		elif x == r.end.x - 1:
			col = kinds.find("right")
		else:
			var host := x >= r.position.x + 3 and x <= r.end.x - 4 and h % 100 < 55
			if host:
				col = kinds.find("host_a") + (h / 100) % 2
				sky_under.set_cell(Vector2i(x, y + 1), 0, Vector2i((h / 200) % 8, 1))
			else:
				col = (h / 100) % 4  # plain_a, plain_b, roots, crystal come first
		sky_under.set_cell(Vector2i(x, y), 0, Vector2i(col, 0))


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
	var ground := ""
	var ground_rank := -1
	var low_ground := ""  # best ground below rock (the water atlas must not take rock itself)
	var low_rank := -1
	var rock_rank := ArtLibrary.ground_rank("rock")
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
			if g == "water":
				continue  # the shore rounds the water; the rock atlas has no water ground
			# a ground above rock (vein, sky) owns its own edge
			if r >= rock_rank:
				return
		if r > ground_rank:
			ground_rank = r
			ground = g
		if r < rock_rank and r > low_rank:
			low_rank = r
			low_ground = g
	if mask == 0 or ground == "":
		return
	# Water over rock and another land: fill the water tile's rounded quarters with the land below rock, so the
	# rock tile keeps its own ground (RockEdge draws it) instead of the shore stamping rock over soil or grass.
	if pair == "water" and low_ground != "":
		ground = low_ground
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
	_prop_batch.flush()
	if prop_blocked.is_valid() and prop_blocked.call(tile):
		set_props_visible(tile, false)


func _add_props(terrain_id: String, x: int, y: int) -> void:
	var tile := Vector2i(x, y)
	for p in _prop_batch.add_tile(terrain_id, tile, _open_dir(x, y)):
		var e := ArtLibrary.prop_entry(p["name"])
		var list: Array = _props.get(tile, [])
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
		_props[tile] = list


## Sum of directions toward neighbouring tiles of another ground (zero inside a stand), for edge-tree jitter.
func _open_dir(x: int, y: int) -> Vector2i:
	return PropBatch.open_dir(map, x, y)


## Hide or show the props of a tile (buildings cover vein/rock props). The batched sprites are rebuilt for the
## tile's base row; shadow and glow sprites are toggled in place.
func set_props_visible(tile: Vector2i, vis: bool) -> void:
	for n in _props.get(tile, []):
		(n as CanvasItem).visible = vis
	_prop_batch.set_visible(tile, vis)


func world_size() -> Vector2:
	return Vector2(MapState.WIDTH * TILE, MapState.HEIGHT * TILE)


func hearth_world_pos() -> Vector2:
	return (Vector2(map.hearth_spot) + Vector2(0.5, 0.5)) * TILE


## Soft drop shadow of each island on the ground: one pre-blurred blob texture (assets/terrain/island_shadow.png)
## stretched over the island and offset south-east, drawn with linear filtering so it stays smooth when scaled.
class IslandShadow extends Node2D:
	## The blob inside the 64x48 texture spans x 12..52, y 10..38, so the quad is scaled up to put that over the island.
	const BLOB := Rect2(12.0, 10.0, 40.0, 28.0)
	const TEX := Vector2(64.0, 48.0)
	const OFFSET := Vector2(16.0, 30.0)
	var rects: Array[Rect2i] = []
	var _tex: Texture2D

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	func _draw() -> void:
		if _tex == null:
			_tex = ArtLibrary.texture(ArtLibrary.sky_rim_info()["shadow"])
		for r in rects:
			var sz := Vector2(r.size) * TILE
			var k := sz / BLOB.size
			var o := Vector2(r.position) * TILE + OFFSET - BLOB.position * k
			draw_texture_rect(_tex, Rect2(o, TEX * k), false)


## Darkens the whole ground (about a 0.4 modulate) under the sky layer in the sky view.
class SkyDim extends Node2D:
	var size := Vector2.ZERO

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.08, 0.6))


class RegionOverlay extends Node2D:
	const DIM := Color(0.02, 0.03, 0.08, 0.42)
	const BORDER_OWNED := Color(1.0, 1.0, 1.0, 0.16)
	const BORDER_LOCKED := Color(0.8, 0.85, 1.0, 0.18)
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
				_draw_reward(map.get_region_reward(r), map.region_reward_pos[r])
			draw_rect(rect, BORDER_OWNED if owned else BORDER_LOCKED, false, 1.0)

	## Small diamond marker on the reward tile of a locked region (design section 4), bright enough to read through the dim.
	func _draw_reward(reward: String, pos: Vector2i) -> void:
		if reward == "" or pos.x < 0:
			return
		var c: Color = MapState.REWARD_COLORS.get(reward, Color.WHITE)
		var o := (Vector2(pos) + Vector2(0.5, 0.5)) * TILE
		var k := TILE * 1.1
		var pts := PackedVector2Array([o + Vector2(0, -k), o + Vector2(k, 0), o + Vector2(0, k), o + Vector2(-k, 0)])
		draw_colored_polygon(pts, Color(c, 0.9))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.05, 0.05, 0.1, 0.9), 2.0)
