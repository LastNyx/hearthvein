class_name PropBatch
extends RefCounted
## Batched prop drawing for MapView (ticket 55, 57b): one MultiMeshInstance2D per 32 px base row. All prop images
## are packed into one atlas texture and each instance carries its atlas rectangle as custom data (PropBatch's
## shader maps the quad's UV into it), so a row is one draw item whatever textures it mixes; the farthest zoom
## draws about a hundred of them instead of over a thousand (one per texture and row).
##
## Z-order is kept: every band is a y-sorted child of MapView.objects and sits at the lowest base y of its
## instances, so it draws where the old per-prop sprites did against buildings (building base y is always a
## multiple of TILE) and against the bands above and below it. Inside a band the instances are in base-y order
## (a MultiMesh draws instances in index order), also across textures, so overlapping props of different kinds
## are strictly y-sorted. Positions, art and modulate are the sprite's own.
##
## refresh_tile and prop hiding rebuild the affected bands from the tile's records; nothing else is touched.

const TILE := ArtLibrary.TILE
const _SHADER := """shader_type canvas_item;
void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
"""

var _parent: Node2D                  # MapView.objects (y-sorted)
var _mesh: QuadMesh
var _atlas: Texture2D
var _material: ShaderMaterial
var _entries: Array[Dictionary] = []
var _rects: Array[Color] = []        # atlas rectangle of each texture index, in UV units (x, y, w, h)
var _tex_index: Dictionary = {}      # prop name -> texture index
var _records: Dictionary = {}        # Vector2i tile -> Array[Dictionary {name, pos, band, seq}]
var _tile_bands: Dictionary = {}     # Vector2i tile -> Array[int] base rows the tile has props in
var _band_tiles: Dictionary = {}     # int base row -> Dictionary tile -> true
var _hidden: Dictionary = {}         # Vector2i tile -> true (roads and buildings cover the tile)
var _bands: Dictionary = {}          # int base row -> MultiMeshInstance2D
var _xforms: Dictionary = {}         # same key -> Array[Transform2D] uploaded to that band
var _names: Dictionary = {}          # same key -> Array[String] prop name of each instance
var _dirty: Dictionary = {}          # int base row -> true
var _seq: int = 0


func setup(parent: Node2D) -> void:
	_parent = parent
	_mesh = QuadMesh.new()
	_mesh.size = Vector2.ONE
	var names := ArtLibrary.prop_names()
	var images: Array[Image] = []
	var x := 0
	var y := 0
	var shelf := 0
	var placed: Array[Vector2i] = []
	const ATLAS_W := 256
	for name in names:
		var e := ArtLibrary.prop_entry(name)
		var img := ArtLibrary.image_of(e["file"])
		images.append(img)
		if x + img.get_width() > ATLAS_W:
			x = 0
			y += shelf + 1
			shelf = 0
		placed.append(Vector2i(x, y))
		x += img.get_width() + 1
		shelf = maxi(shelf, img.get_height())
	var atlas_h := 1
	while atlas_h < y + shelf:
		atlas_h *= 2
	var atlas := Image.create(ATLAS_W, atlas_h, false, Image.FORMAT_RGBA8)
	for i in names.size():
		var img := images[i]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), placed[i])
		_tex_index[names[i]] = i
		_entries.append(ArtLibrary.prop_entry(names[i]))
		_rects.append(Color(placed[i].x / float(ATLAS_W), placed[i].y / float(atlas_h),
				img.get_width() / float(ATLAS_W), img.get_height() / float(atlas_h)))
	_atlas = ImageTexture.create_from_image(atlas)
	var shader := Shader.new()
	shader.code = _SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader


## Direction of the nearest open (another ground) neighbours, for ArtLibrary.scatter's edge thinning.
static func open_dir(map: MapState, x: int, y: int) -> Vector2i:
	var here := _ground(map, x, y)
	var d := Vector2i.ZERO
	for o in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if MapState.in_bounds(x + o.x, y + o.y) and _ground(map, x + o.x, y + o.y) != here:
			d += o
	return d


static func _ground(map: MapState, x: int, y: int) -> String:
	var id := map.terrain_id_at(x, y)
	return ArtLibrary.ground_of(id) if ArtLibrary.has_terrain(id) else "grass"


## Replace the props of one tile with the ones its terrain scatters now. Returns the scatter list, so the caller
## can build the matching shadow and glow sprites.
func add_tile(terrain_id: String, tile: Vector2i, open: Vector2i) -> Array:
	var props := ArtLibrary.scatter(terrain_id, tile.x, tile.y, open)
	clear_tile(tile)
	if props.is_empty():
		return props
	var recs: Array = []
	var bands: Array[int] = []
	for p in props:
		var pos: Vector2 = p["pos"]
		var band := floori(pos.y / float(TILE))
		recs.append({"name": p["name"], "pos": pos, "band": band, "seq": _seq})
		_seq += 1
		if not bands.has(band):
			bands.append(band)
	_records[tile] = recs
	_tile_bands[tile] = bands
	for band in bands:
		if not _band_tiles.has(band):
			_band_tiles[band] = {}
		_band_tiles[band][tile] = true
		_dirty[band] = true
	return props


## Drop a tile's props (before it is re-scattered or its terrain stops having any).
func clear_tile(tile: Vector2i) -> void:
	for band in _tile_bands.get(tile, []):
		if _band_tiles.has(band):
			_band_tiles[band].erase(tile)
			if _band_tiles[band].is_empty():
				_band_tiles.erase(band)
			_dirty[band] = true
	_records.erase(tile)
	_tile_bands.erase(tile)
	_hidden.erase(tile)


func set_visible(tile: Vector2i, vis: bool) -> void:
	if vis:
		_hidden.erase(tile)
	else:
		_hidden[tile] = true
	for band in _tile_bands.get(tile, []):
		_dirty[band] = true
	flush()


func is_hidden(tile: Vector2i) -> bool:
	return _hidden.has(tile)


## Rebuild every band marked dirty.
func flush() -> void:
	for band in _dirty.keys():
		_rebuild(band)
	_dirty.clear()


## Instances currently in the batch (all bands).
func prop_count() -> int:
	var n := 0
	for key in _bands:
		n += (_bands[key] as MultiMeshInstance2D).multimesh.instance_count
	return n


func band_count() -> int:
	return _bands.size()


## Test/debug: the multimesh node of one base row (empty array when the row has no props).
func band_nodes(row: int) -> Array:
	return [_bands[row]] if _bands.has(row) else []


## Instance transforms of one band, in draw order. The dummy renderer of a headless run does not keep MultiMesh
## instance data, so this is what the tests look at; it is the same array that was pushed to the multimesh.
func band_transforms(key: int) -> Array:
	return _xforms.get(key, [])


## Prop name of each instance of one band, in draw order.
func band_names(key: int) -> Array:
	return _names.get(key, [])


## Base rows that currently hold prop instances.
func band_rows() -> Array:
	var rows: Array = []
	for key in _bands:
		if (_bands[key] as MultiMeshInstance2D).multimesh.instance_count > 0:
			rows.append(key)
	rows.sort()
	return rows


# ---------------------------------------------------------------- internals

func _rebuild(band: int) -> void:
	var list: Array = []
	for tile in _band_tiles.get(band, {}):
		if _hidden.has(tile):
			continue
		for rec in _records[tile]:
			if rec["band"] == band:
				list.append(rec)
	if list.is_empty():
		if _bands.has(band):
			(_bands[band] as Node).queue_free()
			_bands.erase(band)
			_xforms.erase(band)
			_names.erase(band)
		return
	_fill_band(band, list)


func _fill_band(band: int, list: Array) -> void:
	list.sort_custom(_record_before)
	var inst: MultiMeshInstance2D = _bands.get(band)
	if inst == null:
		inst = MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = _mesh
		inst.multimesh = mm
		inst.texture = _atlas
		inst.material = _material
		inst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_parent.add_child(inst)
		_bands[band] = inst
	# Node y is the lowest base y of the band (see the class comment).
	var node_y := float(list[0]["pos"].y)
	inst.position = Vector2(0.0, node_y)
	var mm: MultiMesh = inst.multimesh
	mm.instance_count = list.size()
	var xs: Array[Transform2D] = []
	var names: Array[String] = []
	xs.resize(list.size())
	names.resize(list.size())
	for i in list.size():
		var pos: Vector2 = list[i]["pos"]
		var ti: int = _tex_index[list[i]["name"]]
		var e := _entries[ti]
		var w := float(e["w"])
		var h := float(e["h"])
		var left := pos.x - float(e["base"][0])
		var top := pos.y - float(e["base"][1]) - node_y
		# A QuadMesh is y-up in 2D, so the y axis is negated to draw the texture upright.
		var xf := Transform2D(Vector2(w, 0.0), Vector2(0.0, -h), Vector2(left + w * 0.5, top + h * 0.5))
		xs[i] = xf
		names[i] = list[i]["name"]
		mm.set_instance_transform_2d(i, xf)
		mm.set_instance_custom_data(i, _rects[ti])
	_xforms[band] = xs
	_names[band] = names


static func _record_before(a: Dictionary, b: Dictionary) -> bool:
	if a["pos"].y == b["pos"].y:
		return a["seq"] < b["seq"]
	return a["pos"].y < b["pos"].y
