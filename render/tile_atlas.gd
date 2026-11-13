class_name TileAtlas
extends RefCounted
## Procedural placeholder terrain art (D55). Builds a 32x32-per-tile atlas Image at runtime, one row per
## terrain id, VARIANTS columns, palette taken from tools/mockups.py. Not final art.

const TILE := 32
const VARIANTS := 4
const ORDER: Array[String] = ["grass", "fertile_soil", "forest", "rock", "water", "lumen_vein", "stump", "skystone"]
## How many variants of each terrain are drawn (others repeat).
const VARIANT_COUNT := {"grass": 4, "fertile_soil": 2, "forest": 4, "rock": 2, "water": 2, "lumen_vein": 2, "stump": 2, "skystone": 1}

const GRASS: Array[Color] = [Color("2c6a34"), Color("3f8a3a"), Color("5aaa44"), Color("7cc452"), Color("a2da64")]
const WATER: Array[Color] = [Color("23508c"), Color("2f66a8"), Color("3f80c2"), Color("5fa6d8"), Color("9cd6ec"), Color("d4f2f8")]
const DIRT: Array[Color] = [Color("6e4c30"), Color("8a6440"), Color("a47e52"), Color("c09a6a")]
const SOIL: Array[Color] = [Color("3e2a1c"), Color("5a3e28"), Color("6e4c30"), Color("8a6440")]
const BARK: Array[Color] = [Color("2e2016"), Color("4a3424"), Color("6a4c32"), Color("8a6a46")]
const ROCK: Array[Color] = [Color("3e3e48"), Color("5a5a66"), Color("7c7c88"), Color("a2a2ae"), Color("c8c8d2")]
const VEIN: Array[Color] = [Color("262f30"), Color("323e3e"), Color("414f4d"), Color("56685f")]
const CRYSTAL: Array[Color] = [Color("12586c"), Color("2a92aa"), Color("58c8dc"), Color("a8eef8"), Color("eaffff")]
const LEAF_GREEN: Array[Color] = [Color("1c4426"), Color("2a6232"), Color("3f8a3a"), Color("62b048"), Color("96d460")]
const LEAF_DEEP: Array[Color] = [Color("163a2a"), Color("1f5232"), Color("2e703a"), Color("4a9444"), Color("74b85a")]
const LEAF_AUTUMN: Array[Color] = [Color("4e2416"), Color("7e3e1e"), Color("b0662a"), Color("dc9a3a"), Color("f4c862")]
const SKY: Array[Color] = [Color("3a4a5c"), Color("5a7a8c"), Color("7e9eb0"), Color("aac6d4"), Color("d8eef4")]


static func row_of(id: String) -> int:
	var r := ORDER.find(id)
	return maxi(r, 0)


## Variant column for a tile position, stable per position.
static func variant_for(id: String, x: int, y: int) -> int:
	var n: int = VARIANT_COUNT.get(id, 1)
	var h := ((x * 73856093) ^ (y * 19349663)) & 0x7fffffff
	return (h >> 4) % n


static func build_image() -> Image:
	var img := Image.create(TILE * VARIANTS, TILE * ORDER.size(), false, Image.FORMAT_RGBA8)
	for row in ORDER.size():
		var id := ORDER[row]
		var count: int = VARIANT_COUNT[id]
		for col in VARIANTS:
			var v := col % count
			var tile := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(id) + v * 1000 + 7
			_draw_tile(tile, id, v, rng)
			img.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(col * TILE, row * TILE))
	return img


static func build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(build_image())
	src.texture_region_size = Vector2i(TILE, TILE)
	for row in ORDER.size():
		for col in VARIANTS:
			src.create_tile(Vector2i(col, row))
	ts.add_source(src, 0)
	return ts


static func _draw_tile(img: Image, id: String, v: int, rng: RandomNumberGenerator) -> void:
	match id:
		"grass": _grass(img, rng, v)
		"fertile_soil": _soil(img, rng)
		"forest": _forest(img, rng, v)
		"rock": _rock(img, rng, v)
		"water": _water(img, rng, v)
		"lumen_vein": _vein(img, rng, v)
		"stump": _stump(img, rng)
		"skystone": _skystone(img, rng)


# ---------------------------------------------------------------- helpers
static func _noise_fill(img: Image, pal: Array[Color], rng: RandomNumberGenerator, lo: int, hi: int) -> void:
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, pal[rng.randi_range(lo, hi)])


static func _disc(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(maxi(0, int(cy - ry) - 1), mini(TILE, int(cy + ry) + 2)):
		for x in range(maxi(0, int(cx - rx) - 1), mini(TILE, int(cx + rx) + 2)):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


## Shaded blob: dark rim, mid body, highlight offset up-left.
static func _blob(img: Image, cx: float, cy: float, rx: float, ry: float, pal: Array[Color]) -> void:
	_disc(img, cx, cy, rx, ry, pal[0])
	_disc(img, cx - 0.5, cy - 0.5, rx - 1.2, ry - 1.2, pal[2])
	_disc(img, cx - rx * 0.25, cy - ry * 0.3, rx * 0.55, ry * 0.5, pal[3])
	_disc(img, cx - rx * 0.35, cy - ry * 0.4, rx * 0.25, ry * 0.2, pal[4] if pal.size() > 4 else pal[3])


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < TILE and y < TILE:
		img.set_pixel(x, y, c)


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, c)


# ---------------------------------------------------------------- terrains
static func _grass(img: Image, rng: RandomNumberGenerator, v: int) -> void:
	_noise_fill(img, GRASS, rng, 1, 2)
	for i in 14:
		_px(img, rng.randi_range(0, 31), rng.randi_range(0, 31), GRASS[3])
	for i in 8:
		_px(img, rng.randi_range(0, 31), rng.randi_range(0, 31), GRASS[0])
	for i in 3 + v:
		var x := rng.randi_range(2, 29)
		var y := rng.randi_range(3, 29)
		_px(img, x, y, GRASS[4])
		_px(img, x, y - 1, GRASS[3])
	if v == 3:
		var flowers: Array[Color] = [Color("e8506a"), Color("f4f0e0"), Color("f4c040")]
		for i in 4:
			_px(img, rng.randi_range(1, 30), rng.randi_range(1, 30), flowers[rng.randi_range(0, 2)])


static func _soil(img: Image, rng: RandomNumberGenerator) -> void:
	_noise_fill(img, SOIL, rng, 1, 2)
	for row in range(3, 32, 6):
		for x in TILE:
			_px(img, x, row, SOIL[0])
			_px(img, x, row + 1, SOIL[3] if rng.randf() < 0.4 else SOIL[2])
	for i in 10:
		_px(img, rng.randi_range(0, 31), rng.randi_range(0, 31), SOIL[3])
	# little green sprouts show it is fertile
	for i in 5:
		var x := rng.randi_range(2, 29)
		var y := rng.randi_range(2, 29)
		_px(img, x, y, GRASS[3])
		_px(img, x, y - 1, GRASS[4])


static func _forest(img: Image, rng: RandomNumberGenerator, v: int) -> void:
	_grass(img, rng, 0)
	var pal: Array[Color] = LEAF_GREEN
	if v == 1:
		pal = LEAF_DEEP
	elif v == 3:
		pal = LEAF_AUTUMN
	# ground shadow, trunk, then three layered canopy blobs
	_disc(img, 16, 28, 9, 3, Color(0, 0, 0, 0.28))
	_rect(img, 14, 20, 17, 28, BARK[1])
	_rect(img, 14, 20, 15, 28, BARK[2])
	_blob(img, 16, 17, 12, 8, pal)
	_blob(img, 10, 12, 8, 7, pal)
	_blob(img, 21, 11, 8, 7, pal)
	_blob(img, 16, 8, 8, 6, pal)


static func _rock(img: Image, rng: RandomNumberGenerator, v: int) -> void:
	_grass(img, rng, 1)
	_disc(img, 16, 25, 12, 4, Color(0, 0, 0, 0.25))
	if v == 0:
		_blob(img, 16, 18, 11, 8, ROCK)
		_blob(img, 8, 24, 6, 4.5, ROCK)
	else:
		_blob(img, 11, 17, 8, 7, ROCK)
		_blob(img, 22, 21, 7, 5.5, ROCK)
		_blob(img, 17, 9, 5, 4, ROCK)


static func _water(img: Image, rng: RandomNumberGenerator, v: int) -> void:
	_noise_fill(img, WATER, rng, 1, 2)
	for i in 6:
		var x := rng.randi_range(2, 24)
		var y := rng.randi_range(2, 29)
		var len := rng.randi_range(3, 6)
		for k in len:
			_px(img, x + k, y, WATER[4] if k % 2 == 0 else WATER[3])
	for i in 6:
		_px(img, rng.randi_range(0, 31), rng.randi_range(0, 31), WATER[0])
	for i in 1 + v:
		_px(img, rng.randi_range(2, 29), rng.randi_range(2, 29), WATER[5])


static func _vein(img: Image, rng: RandomNumberGenerator, v: int) -> void:
	_noise_fill(img, VEIN, rng, 0, 2)
	# glow halo
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 16, y - 18).length() / 16.0
			if d < 1.0:
				var c := img.get_pixel(x, y).lerp(CRYSTAL[1], (1.0 - d) * 0.45)
				img.set_pixel(x, y, c)
	var shards := [Vector2i(15, 26), Vector2i(8, 27), Vector2i(23, 27)] if v == 0 else [Vector2i(13, 27), Vector2i(21, 26), Vector2i(7, 24)]
	var heights := [17, 10, 12] if v == 0 else [15, 11, 8]
	for i in shards.size():
		var b: Vector2i = shards[i]
		var h: int = heights[i]
		var w := 3 if i == 0 else 2
		for k in h:
			var half: float = w * (1.0 - float(k) / h) + 0.4
			for dx in range(-int(half) - 1, int(half) + 2):
				if abs(dx) <= half:
					var c := CRYSTAL[3] if dx < 0 else CRYSTAL[1]
					if dx == 0:
						c = CRYSTAL[2]
					_px(img, b.x + dx, b.y - k, c)
		_px(img, b.x, b.y - h + 1, CRYSTAL[4])


static func _stump(img: Image, rng: RandomNumberGenerator) -> void:
	_grass(img, rng, 2)
	_disc(img, 16, 24, 9, 3.5, Color(0, 0, 0, 0.28))
	_rect(img, 10, 17, 21, 24, BARK[1])
	_rect(img, 11, 17, 14, 24, BARK[2])
	_disc(img, 16, 17, 6.5, 3.5, BARK[1])
	_disc(img, 16, 17, 5.5, 2.8, DIRT[3])
	_disc(img, 16, 17, 3.5, 1.6, DIRT[2])
	_px(img, 16, 17, DIRT[1])
	# a couple of roots/chips
	_px(img, 8, 25, BARK[1])
	_px(img, 23, 25, BARK[1])
	_px(img, 24, 26, DIRT[2])


static func _skystone(img: Image, rng: RandomNumberGenerator) -> void:
	_noise_fill(img, SKY, rng, 1, 2)
	for i in 3:
		var x := rng.randi_range(0, 25)
		var y := rng.randi_range(2, 29)
		for k in 6:
			_px(img, x + k, y + (k / 3), SKY[0])
	for i in 8:
		_px(img, rng.randi_range(0, 31), rng.randi_range(0, 31), SKY[4])
	for i in 4:
		var x := rng.randi_range(3, 28)
		var y := rng.randi_range(3, 28)
		_px(img, x, y, CRYSTAL[3])
		_px(img, x, y - 1, CRYSTAL[2])
		_px(img, x, y + 1, CRYSTAL[2])
		_px(img, x - 1, y, CRYSTAL[2])
		_px(img, x + 1, y, CRYSTAL[2])
