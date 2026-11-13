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


## One atlas source for all terrain ids (ticket 57b): the per-id images are stacked into one texture, one row per
## terrain id (row = index in terrain_ids()), so a Base quadrant draws as one batch instead of one per ground change.
static func terrain_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = _terrain_atlas_texture()
	src.texture_region_size = Vector2i(TILE, TILE)
	for row in terrain_ids().size():
		for x in int(manifest()["terrain"][terrain_ids()[row]]["cols"]):
			src.create_tile(Vector2i(x, row))
	ts.add_source(src, 0)
	return ts


static func _terrain_cols() -> int:
	var cols := 1
	for id in terrain_ids():
		cols = maxi(cols, int(manifest()["terrain"][id]["cols"]))
	return cols


static var _terrain_atlas: Texture2D


static func _terrain_atlas_texture() -> Texture2D:
	if _terrain_atlas == null:
		var ids := terrain_ids()
		var img := Image.create(_terrain_cols() * TILE, ids.size() * TILE, false, Image.FORMAT_RGBA8)
		for row in ids.size():
			var part := image_of(manifest()["terrain"][ids[row]]["file"])
			img.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(0, row * TILE))
		_terrain_atlas = ImageTexture.create_from_image(img)
	return _terrain_atlas


## Pixels of an exported asset as RGBA8, from its texture.
static func image_of(rel: String) -> Image:
	var img: Image = texture(rel).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func overlay_tileset(ground: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var cols: int = manifest()["overlay_cols"]
	ts.add_source(_atlas(manifest()["overlays"][ground], cols,
			int(manifest()["overlay_rows"]) * int(manifest()["overlay_variants"])), 0)
	return ts


# ---------------------------------------------------------------- dual-grid autotiles (ticket 54)
## Water/land and rock/land edges: one 4x4 atlas per lower ground, 16 corner configurations each.
## The map view draws them on a layer shifted half a tile up-left, one cell per map corner.
static func autotile_pairs() -> Array[String]:
	var out: Array[String] = []
	for k in manifest()["autotiles"].keys():
		out.append(k)
	out.sort()
	return out


static func autotile_grounds(pair: String) -> Array:
	return manifest()["autotiles"][pair]["grounds"]


## Atlas source id of a lower ground inside the pair's tileset (-1 when the ground has no atlas there).
static func autotile_source(pair: String, ground: String) -> int:
	return autotile_grounds(pair).find(ground)


static func autotile_tileset(pair: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var at: Dictionary = manifest()["autotiles"][pair]
	for i in (at["grounds"] as Array).size():
		ts.add_source(_atlas(at["files"][at["grounds"][i]], int(at["cols"]), int(at["rows"])), i)
	return ts


## Atlas coords of a corner configuration: bit 0 TL, 1 TR, 2 BR, 3 BL of the four map tiles around the corner.
static func autotile_coords(mask: int) -> Vector2i:
	var cols: int = int(manifest()["autotiles"]["water"]["cols"])
	return Vector2i(mask % cols, mask / cols)


## Tile-state overlays (blight, fouled): one atlas of translucent variants each, drawn over the ground.
static func state_tileset(state: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var st: Dictionary = manifest()["states"][state]
	ts.add_source(_atlas(st["file"], int(st["cols"]), int(st["rows"])), 0)  # fill tiles
	ts.add_source(_atlas(st["edge_file"], int(st["edge_cols"]), int(st["edge_rows"])), 1)  # soft bleed onto neighbours
	return ts


## Atlas coords in the edge source of a state for the 8-neighbour mask of flagged tiles (-1,-1 when none).
static func state_edge_coords(mask: int) -> Vector2i:
	var idx: int = int(manifest()["overlay_index"][mask])
	if idx < 0:
		return Vector2i(-1, -1)
	var cols: int = manifest()["overlay_cols"]
	return Vector2i(idx % cols, idx / cols)


## Lumen sparkle prop of a blighted tile, picked by seeded hash ("" for most tiles).
static func blight_sparkle(seed: int, x: int, y: int) -> Dictionary:
	var b: Dictionary = manifest()["blight_sparkle"]
	var h := tile_hash(seed + 11, x, y)
	if h % 100 >= int(b["chance_pct"]):
		return {}
	var names: Array = b["props"]
	var h2 := tile_hash(seed + 12, x, y)
	return {"name": names[h2 % names.size()], "pos": Vector2(x * TILE + 4 + (h2 >> 3) % 24, y * TILE + 6 + (h2 >> 9) % 22)}


static func state_variants(state: String) -> int:
	return int(manifest()["states"][state]["cols"])


## Deterministic variant hash of (seed, tile): no RNG state, so drawing never touches the simulation.
static func tile_hash(seed: int, x: int, y: int) -> int:
	var h := ((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) & 0x7fffffff
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0x7fffffff
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0x7fffffff
	return h ^ (h >> 15)


## Atlas column (variant) of a terrain cell, picked by the seeded hash of the tile.
static func terrain_variant(id: String, x: int, y: int, seed: int) -> int:
	var pick: Array = manifest()["terrain"][id]["pick"]
	return int(pick[tile_hash(seed, x, y) % pick.size()])


## Tile for a terrain cell: atlas source id (always 0) and coords (column = variant, row = terrain id index), stable per (seed, position).
static func terrain_cell(id: String, x: int, y: int, seed: int = 0) -> Array:
	return [0, Vector2i(terrain_variant(id, x, y, seed), terrain_ids().find(id))]


## Broad meadow shading: value noise sampled per tile in world space (lattice values hashed from the map seed), so it
## has no period and no tile-grid alignment. Octave lattice sizes and weights come from the manifest.
static func shade_value(seed: int, x: int, y: int) -> float:
	var sh: Dictionary = manifest()["shade"]
	var cells: Array = sh["cells"]
	var weights: Array = sh["weights"]
	var total := 0.0
	for o in cells.size():
		var fx := (x + 0.5) / float(cells[o])
		var fy := (y + 0.5) / float(cells[o])
		var ix := floori(fx)
		var iy := floori(fy)
		var tx := fx - ix
		var ty := fy - iy
		tx = tx * tx * (3.0 - 2.0 * tx)
		ty = ty * ty * (3.0 - 2.0 * ty)
		var s := seed + 7919 * (o + 1)
		var a := lerpf(_lattice(s, ix, iy), _lattice(s, ix + 1, iy), tx)
		var b := lerpf(_lattice(s, ix, iy + 1), _lattice(s, ix + 1, iy + 1), tx)
		total += lerpf(a, b, ty) * float(weights[o])
	return clampf((total - 0.5) * 1.8 + 0.5, 0.0, 1.0)


static func _lattice(seed: int, ix: int, iy: int) -> float:
	return float(tile_hash(seed, ix + 4096, iy + 4096) % 10007) / 10006.0


static func shade_grounds() -> Array:
	return manifest()["shade"]["grounds"]


## Shade colour of one tile (premultiplied-free RGBA, alpha 0 where the tile is not shaded ground).
static func shade_color(seed: int, ground: String, x: int, y: int) -> Color:
	var sh: Dictionary = manifest()["shade"]
	var v := shade_value(seed, x, y)
	var below: float = sh["dark_below"]
	var above: float = sh["light_above"]
	var ramp: float = sh["ramp"]
	var dk := clampf((below - v) / ramp, 0.0, 1.0)
	var lt := clampf((v - above) / ramp, 0.0, 1.0)
	var src: Array = sh["dark"] if dk >= lt else sh["light"]
	var k := maxf(dk, lt)
	var a := float(src[3]) / 255.0 * k
	if not (sh["grounds"] as Array).has(ground):
		a = 0.0
	return Color(float(src[0]) / 255.0, float(src[1]) / 255.0, float(src[2]) / 255.0, a)


## One pixel per tile; drawn scaled by TILE with linear filtering, so patches blend smoothly across tiles.
static func shade_image(seed: int, w: int, h: int, ground_at: Callable) -> Image:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var i := 0
	for y in h:
		for x in w:
			var c := shade_color(seed, ground_at.call(x, y), x, y)
			data[i] = int(c.r8)
			data[i + 1] = int(c.g8)
			data[i + 2] = int(c.b8)
			data[i + 3] = int(c.a8)
			i += 4
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


## Overlay atlas coords for an 8-neighbour mask (bit order N, NE, E, SE, S, SW, W, NW), or (-1,-1) for none.
## `variant` picks one of overlay_variants edge-wobble versions (callers use the seeded tile hash).
static func overlay_coords(mask: int, variant: int = 0) -> Vector2i:
	var idx: int = int(manifest()["overlay_index"][mask])
	if idx < 0:
		return Vector2i(-1, -1)
	var cols: int = manifest()["overlay_cols"]
	var rows: int = int(manifest()["overlay_rows"])
	return Vector2i(idx % cols, idx / cols + (variant % int(manifest()["overlay_variants"])) * rows)


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


# ---------------------------------------------------------------- irrigation channels
const CHANNEL_DRY := 0
const CHANNEL_FLOWING := 1


## Source CHANNEL_DRY / CHANNEL_FLOWING; atlas coords are (mask, 0) like roads (N=1, E=2, S=4, W=8).
static func channel_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	for pair in [[CHANNEL_DRY, "dry"], [CHANNEL_FLOWING, "flowing"]]:
		var r: Dictionary = manifest()["channels"][pair[1]]
		ts.add_source(_atlas(r["file"], int(r["cols"]), int(r["rows"])), pair[0])
	return ts


# ---------------------------------------------------------------- props
## Props to stand on a terrain cell: [{name, pos}] with pos the sprite base point in world pixels.
## `open` is the direction of the nearest open (non-same-ground) neighbour tiles summed, for edge tiles of a stand:
## edge trees thin out and jitter toward the open side so a forest border is not a straight tile line.
static func scatter(terrain_id: String, x: int, y: int, open: Vector2i = Vector2i.ZERO) -> Array:
	var rules: Dictionary = manifest()["scatter"]
	var out: Array = []
	if not rules.has(terrain_id):
		return out
	var r: Dictionary = rules[terrain_id]
	if r.get("interior_only", false) and open != Vector2i.ZERO:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = ((x * 92821) ^ (y * 68917) ^ 0x5bd1e995) & 0x7fffffff
	var count := 0
	var edge := open != Vector2i.ZERO and r.has("edge_jitter")
	var p1 := float(r["p_first"]) * (0.75 if edge else 1.0)
	var p2 := float(r["p_second"]) * (0.4 if edge else 1.0)
	if rng.randf() < p1:
		count = 1
		if rng.randf() < p2:
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
		var pos := Vector2(x * TILE + px, y * TILE + py)
		if edge:
			var j := float(r["edge_jitter"])
			pos += Vector2(open) * rng.randf_range(0.0, j) + Vector2(rng.randf_range(-j, j), rng.randf_range(-j, j)) * 0.5
		out.append({"name": pick, "pos": pos})
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


## Every prop name, sorted (stable texture order for PropBatch).
static func prop_names() -> Array[String]:
	var out: Array[String] = []
	for k in manifest()["props"].keys():
		out.append(k)
	out.sort()
	return out


## The single-prop texture of a prop (props are one image each, not an atlas).
static func prop_texture(name: String) -> Texture2D:
	return texture(manifest()["props"][name]["file"])


## World position of a building's base point: bottom edge, centred on its footprint.
static func base_point(origin: Vector2i, size: Vector2i) -> Vector2:
	return Vector2((origin.x + size.x * 0.5) * TILE, (origin.y + size.y) * TILE)


## World rect of the building sprite for a footprint at `origin`.
static func sprite_rect(id: String, origin: Vector2i, size: Vector2i) -> Rect2:
	var e := building_entry(id)
	var b := base_point(origin, size)
	return Rect2(b - Vector2(e["base"][0], e["base"][1]), Vector2(e["w"], e["h"]))


# ---------------------------------------------------------------- construction sites
## {plot: Texture2D, scaffold: Texture2D} for a footprint; the scaffold is the smallest height tier covering
## `sprite_h` (the finished building sprite height). Scaffold bottom = footprint bottom, left = footprint left.
static func site_art(size: Vector2i, sprite_h: float) -> Dictionary:
	var st: Dictionary = manifest()["site"]
	var key := "%dx%d" % [clampi(size.x, 1, 3), clampi(size.y, 1, 3)]
	var tier: int = int((st["tiers"] as Array).back())
	for t in st["tiers"]:
		if float(t) >= sprite_h * 0.8:
			tier = int(t)
			break
	return {"plot": texture(st["plot"][key]), "scaffold": texture(st["scaffold"]["%s_%d" % [key, tier]])}


# ---------------------------------------------------------------- walkers
const DIR_DOWN := 0
const DIR_UP := 1
const DIR_LEFT := 2
const DIR_RIGHT := 3


static func walker_entry() -> Dictionary:
	return manifest()["walkers"]


## Facing row (DIR_*) for a movement vector in tiles; the larger axis wins, ties prefer the vertical.
## A zero vector returns `fallback` so a standing walker keeps its last facing.
static func facing_for(delta: Vector2, fallback: int = DIR_DOWN) -> int:
	if delta.is_zero_approx():
		return fallback
	if absf(delta.x) > absf(delta.y):
		return DIR_RIGHT if delta.x > 0.0 else DIR_LEFT
	return DIR_DOWN if delta.y > 0.0 else DIR_UP


## Look (atlas variant) of a citizen: seeded hash of id and map seed, never RNG state.
static func walker_variant(citizen_id: int, map_seed: int) -> int:
	return tile_hash(map_seed, citizen_id, 7919) % int(walker_entry()["variants"])


## Region of the walker atlas for a look, facing (DIR_*) and frame.
static func walker_region(variant: int, facing: int, frame: int) -> Rect2:
	var cell: Array = walker_entry()["cell"]
	return Rect2(frame * cell[0], (variant * 4 + facing) * cell[1], cell[0], cell[1])
