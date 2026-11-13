class_name PropBatch
extends RefCounted
## Batched prop drawing for MapView (ticket 55): one MultiMeshInstance2D per (prop texture, 32 px base row)
## instead of one Sprite2D per prop. Thousands of prop sprites cost about 10 ms of render at the farthest zoom;
## a few hundred multimeshes are one draw item each.
##
## Z-order is kept: every band is a y-sorted child of MapView.objects and sits at the lowest base y of its
## instances, so it draws where the old per-prop sprites did against buildings (building base y is always a
## multiple of TILE) and against the bands above and below it. Inside a band one multimesh per texture keeps its
## instances in base-y order, because a MultiMesh draws instances in index order. Only props of different textures
## whose bases fall in the same 32 px row can change which of the two is in front; positions, art and modulate are
## the sprite's own.
##
## refresh_tile and prop hiding rebuild the affected bands from the tile's records; nothing else is touched.

const TILE := ArtLibrary.TILE
## Bits of a band key: texture index in the low bits, base row above it.
const _ROW_SHIFT := 8

var _parent: Node2D                  # MapView.objects (y-sorted)
var _mesh: QuadMesh
var _textures: Array[Texture2D] = []
var _entries: Array[Dictionary] = []
var _tex_index: Dictionary = {}      # prop name -> texture index
var _records: Dictionary = {}        # Vector2i tile -> Array[Dictionary {name, pos, band, seq}]
var _tile_bands: Dictionary = {}     # Vector2i tile -> Array[int] base rows the tile has props in
var _band_tiles: Dictionary = {}     # int base row -> Dictionary tile -> true
var _hidden: Dictionary = {}         # Vector2i tile -> true (roads and buildings cover the tile)
var _bands: Dictionary = {}          # int (texture index | base row) -> MultiMeshInstance2D
var _xforms: Dictionary = {}         # same key -> Array[Transform2D] uploaded to that band
var _dirty: Dictionary = {}          # int base row -> true
var _seq: int = 0


func setup(parent: Node2D) -> void:
	_parent = parent
	_mesh = QuadMesh.new()
	_mesh.size = Vector2.ONE
	for name in ArtLibrary.prop_names():
		_tex_index[name] = _entries.size()
		_entries.append(ArtLibrary.prop_entry(name))
		_textures.append(ArtLibrary.prop_texture(name))


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


## Test/debug: the multimesh nodes of one base row.
func band_nodes(row: int) -> Array:
	var out: Array = []
	for key in _bands:
		if key >> _ROW_SHIFT == row:
			out.append(_bands[key])
	return out


## Instance transforms of one band, in draw order. The dummy renderer of a headless run does not keep MultiMesh
## instance data, so this is what the tests look at; it is the same array that was pushed to the multimesh.
func band_transforms(key: int) -> Array:
	return _xforms.get(key, [])


## Base rows that currently hold prop instances.
func band_rows() -> Array:
	var rows := {}
	for key in _bands:
		if (_bands[key] as MultiMeshInstance2D).multimesh.instance_count > 0:
			rows[key >> _ROW_SHIFT] = true
	var out: Array = rows.keys()
	out.sort()
	return out


# ---------------------------------------------------------------- internals

func _rebuild(band: int) -> void:
	var by_tex := {}  # texture index -> Array[Dictionary]
	for tile in _band_tiles.get(band, {}):
		if _hidden.has(tile):
			continue
		for rec in _records[tile]:
			if rec["band"] != band:
				continue
			var ti: int = _tex_index[rec["name"]]
			if not by_tex.has(ti):
				by_tex[ti] = []
			by_tex[ti].append(rec)
	for key in _bands.keys():
		if key >> _ROW_SHIFT == band and not by_tex.has(key & 0xff):
			(_bands[key] as Node).queue_free()
			_bands.erase(key)
			_xforms.erase(key)
	for ti in by_tex:
		_fill_band(ti, band, by_tex[ti])


func _fill_band(tex_index: int, band: int, list: Array) -> void:
	list.sort_custom(_record_before)
	var key := tex_index | (band << _ROW_SHIFT)
	var inst: MultiMeshInstance2D = _bands.get(key)
	if inst == null:
		inst = MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = _mesh
		inst.multimesh = mm
		inst.texture = _textures[tex_index]
		inst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_parent.add_child(inst)
		_bands[key] = inst
	var e := _entries[tex_index]
	var base := Vector2(e["base"][0], e["base"][1])
	var w := float(e["w"])
	var h := float(e["h"])
	# Node y is the lowest base y of the band (see the class comment).
	var node_y := float(list[0]["pos"].y)
	inst.position = Vector2(0.0, node_y)
	var mm: MultiMesh = inst.multimesh
	mm.instance_count = list.size()
	var xs: Array[Transform2D] = []
	xs.resize(list.size())
	for i in list.size():
		var pos: Vector2 = list[i]["pos"]
		var left := pos.x - base.x
		var top := pos.y - base.y - node_y
		# A QuadMesh is y-up in 2D, so the y axis is negated to draw the texture upright.
		var xf := Transform2D(Vector2(w, 0.0), Vector2(0.0, -h), Vector2(left + w * 0.5, top + h * 0.5))
		xs[i] = xf
		mm.set_instance_transform_2d(i, xf)
	_xforms[key] = xs


static func _record_before(a: Dictionary, b: Dictionary) -> bool:
	if a["pos"].y == b["pos"].y:
		return a["seq"] < b["seq"]
	return a["pos"].y < b["pos"].y
