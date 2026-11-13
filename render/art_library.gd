class_name ArtLibrary
extends RefCounted
## Loader for the exported art in assets/ (written by tools/export_art.py from tools/mockups.py, D55).
## Reads assets/art_manifest.json and builds TileSets, sprites and anchors. It draws nothing itself.

const TILE := 32
const ROOT := "res://assets/"
const MANIFEST := "res://assets/art_manifest.json"

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _terrain_order: Array[String] = []
static var _family_noise: FastNoiseLite = null


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(MANIFEST, FileAccess.READ)
		assert(f != null, "assets/art_manifest.json missing: run python3 tools/export_art.py")
		_manifest = JSON.parse_string(f.get_as_text())
	return _manifest


static func texture(rel: String) -> Texture2D:
	if not _textures.has(rel):
		var path := ROOT + rel
		if ResourceLoader.exists(path):
			_textures[rel] = load(path)
		else:  # not imported yet (fresh checkout, scripted run): read the PNG directly
			_textures[rel] = ImageTexture.create_from_image(Image.load_from_file(path))
	return _textures[rel]


# ---------------------------------------------------------------- terrain
static func terrain_ids() -> Array[String]:
	if _terrain_order.is_empty():
		for k in manifest()["terrain"].keys():
			_terrain_order.append(k)
		_terrain_order.sort()
	return _terrain_order


static func has_terrain(id: String) -> bool:
	return manifest()["terrain"].has(id)


static func ground_of(terrain_id: String) -> String:
	return manifest()["terrain"][terrain_id]["ground"]


## Rank in the ground order; a higher ground draws soft overlays onto lower neighbours.
static func ground_rank(ground: String) -> int:
	return manifest()["ground_order"].find(ground)


## Grounds that have transition overlays, lowest rank first.
static func overlay_grounds() -> Array[String]:
	var out: Array[String] = []
	for g in manifest()["ground_order"]:
		if manifest()["overlays"].has(g):
			out.append(g)
	return out


static func _atlas(rel: String, cols: int, rows: int) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = texture(rel)
	src.texture_region_size = Vector2i(TILE, TILE)
	for y in rows:
		for x in cols:
			src.create_tile(Vector2i(x, y))
	return src


## One atlas source per terrain id; source id = index in terrain_ids().
static func terrain_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	for id in terrain_ids():
		var t: Dictionary = manifest()["terrain"][id]
		ts.add_source(_atlas(t["file"], int(t["cols"]), int(t["rows"])), terrain_ids().find(id))
	return ts


static func overlay_tileset(ground: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var cols: int = manifest()["overlay_cols"]
	ts.add_source(_atlas(manifest()["overlays"][ground], cols, int(manifest()["overlay_shore_row"]) * 2), 0)
	return ts


## Tile for a terrain cell: atlas source id and coords, stable per position.
static func terrain_cell(id: String, x: int, y: int) -> Array:
	var t: Dictionary = manifest()["terrain"][id]
	var pick: Array = t["pick"]
	var h := ((x * 73856093) ^ (y * 19349663)) & 0x7fffffff
	var col: int = int(pick[(h >> 4) % pick.size()])
	var family := 0
	if int(t["rows"]) > 1:  # light / mid / dark patches from low-frequency noise
		if _family_noise == null:
			_family_noise = FastNoiseLite.new()
			_family_noise.seed = 7
			_family_noise.frequency = 0.02
		var n := _family_noise.get_noise_2d(x, y)
		family = 0 if n > 0.3 else (2 if n < -0.3 else 1)
	return [terrain_ids().find(id), Vector2i(col, family)]


## Overlay atlas coords for an 8-neighbour mask (bit order N, NE, E, SE, S, SW, W, NW), or (-1,-1) for none.
static func overlay_coords(mask: int, over_water: bool) -> Vector2i:
	var idx: int = int(manifest()["overlay_index"][mask])
	if idx < 0:
		return Vector2i(-1, -1)
	var cols: int = manifest()["overlay_cols"]
	var row := idx / cols + (int(manifest()["overlay_shore_row"]) if over_water else 0)
	return Vector2i(idx % cols, row)


# ---------------------------------------------------------------- roads
static func road_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	for level in [1, 2]:
		var r: Dictionary = manifest()["roads"][str(level)]
		ts.add_source(_atlas(r["file"], int(r["cols"]), int(r["rows"])), level)
	return ts


## Atlas coords for a road tile: mask N=1, E=2, S=4, W=8 of connected neighbours.
static func road_coords(mask: int, x: int, y: int) -> Vector2i:
	return Vector2i(mask, ((x * 31 + y * 17) >> 1) & 1)


# ---------------------------------------------------------------- props
## Props to stand on a terrain cell: [{name, pos}] with pos the sprite base point in world pixels.
static func scatter(terrain_id: String, x: int, y: int) -> Array:
	var rules: Dictionary = manifest()["scatter"]
	var out: Array = []
	if not rules.has(terrain_id):
		return out
	var r: Dictionary = rules[terrain_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = ((x * 92821) ^ (y * 68917) ^ 0x5bd1e995) & 0x7fffffff
	var count := 0
	if rng.randf() < float(r["p_first"]):
		count = 1
		if rng.randf() < float(r["p_second"]):
			count = 2
	var choices: Array = r["choices"]
	var total := 0.0
	for c in choices:
		total += float(c[1])
	for i in count:
		var roll := rng.randf() * total
		var pick: String = choices[0][0]
		for c in choices:
			roll -= float(c[1])
			if roll <= 0.0:
				pick = c[0]
				break
		var px := rng.randi_range(int(r["x"][0]), int(r["x"][1]))
		var py := rng.randi_range(int(r["y"][0]), int(r["y"][1]))
		out.append({"name": pick, "pos": Vector2(x * TILE + px, y * TILE + py)})
	return out


# ---------------------------------------------------------------- sprites
static func _sprite(rel: String, offset: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture(rel)
	s.centered = false
	s.offset = offset
	return s


## Sprite whose node origin is the base point (bottom centre), so y-sorting uses the foot of the object.
static func prop_sprite(name: String) -> Sprite2D:
	return _sprite_for(manifest()["props"][name])


static func building_sprite(id: String) -> Sprite2D:
	return _sprite_for(manifest()["buildings"][id])


static func _sprite_for(e: Dictionary) -> Sprite2D:
	return _sprite(e["file"], -Vector2(e["base"][0], e["base"][1]))


## Ground shadow sprite (null when the entry has none). Same origin convention as the object sprite.
static func shadow_sprite(e: Dictionary) -> Sprite2D:
	if not e.has("shadow"):
		return null
	return _sprite(e["shadow"]["file"], Vector2(e["shadow"]["offset"][0], e["shadow"]["offset"][1]))


## Light glows and chimney smoke (null when none), drawn above everything.
static func fx_sprite(e: Dictionary) -> Sprite2D:
	if not e.has("fx"):
		return null
	return _sprite(e["fx"]["file"], Vector2(e["fx"]["offset"][0], e["fx"]["offset"][1]))


static func has_building(id: String) -> bool:
	return manifest()["buildings"].has(id)


static func building_entry(id: String) -> Dictionary:
	return manifest()["buildings"][id]


static func prop_entry(name: String) -> Dictionary:
	return manifest()["props"][name]


## World position of a building's base point: bottom edge, centred on its footprint.
static func base_point(origin: Vector2i, size: Vector2i) -> Vector2:
	return Vector2((origin.x + size.x * 0.5) * TILE, (origin.y + size.y) * TILE)


## World rect of the building sprite for a footprint at `origin`.
static func sprite_rect(id: String, origin: Vector2i, size: Vector2i) -> Rect2:
	var e := building_entry(id)
	var b := base_point(origin, size)
	return Rect2(b - Vector2(e["base"][0], e["base"][1]), Vector2(e["w"], e["h"]))
