class_name BuildingArt
extends RefCounted
## Procedural placeholder building sprites (D55): a 3/4 box with a roof, tinted by category, sized to the footprint.
## Also the dirt/paved road tiles. Not final art.

const TILE := TileAtlas.TILE
const TINTS := {
	"housing": Color("c98b5a"), "food": Color("7fae52"), "materials": Color("9a7a52"), "lumen": Color("4fb6cf"),
	"refining": Color("b86a4a"), "water": Color("4f86c8"), "logistics": Color("b0a070"), "civic": Color("c8b05a"),
	"sky": Color("9ab0d0"), "landmark": Color("d8d0e0"),
}
static var _cache: Dictionary = {}


static func texture_for(def: BuildingDef) -> Texture2D:
	var key := "%s_%d_%d" % [def.category, def.size.x, def.size.y]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(build_image(def.category, def.size))
	return _cache[key]


static func build_image(category: String, size: Vector2i) -> Image:
	var w := size.x * TILE
	var h := size.y * TILE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var tint: Color = TINTS.get(category, Color("aaaaaa"))
	var wall := tint.lightened(0.15)
	var wall_side := tint.darkened(0.15)
	var roof := tint.darkened(0.4)
	var roof_hi := tint.darkened(0.2)
	var m := 2
	# ground shadow
	_rect(img, m + 2, h - 5, w - m, h - 2, Color(0, 0, 0, 0.3))
	# front wall (bottom 45%), with a darker right side strip
	var wall_top := int(h * 0.5)
	_rect(img, m, wall_top, w - m - 3, h - 4, wall)
	_rect(img, w - m - 6, wall_top, w - m - 3, h - 4, wall_side)
	_rect(img, m, h - 6, w - m - 3, h - 4, wall_side)
	# door
	var dx := (w - 8) / 2
	_rect(img, dx, h - 14, dx + 6, h - 5, Color("3a2818"))
	# roof: trapezoid wider than the wall, with ridge highlight
	var roof_top := m
	for y in range(roof_top, wall_top + 3):
		var t := float(y - roof_top) / float(maxi(1, wall_top + 2 - roof_top))
		var inset := int((1.0 - t) * minf(w * 0.25, 8.0))
		_rect(img, m - 1 + inset, y, w - m - 2 - inset, y, roof)
		if y - roof_top < 3:
			_rect(img, m - 1 + inset, y, w - m - 2 - inset, y, roof_hi)
	return img


static func road_image(level: int, variant: int) -> Image:
	var pal: Array[Color] = TileAtlas.DIRT if level == 1 else TileAtlas.ROCK
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + variant + level * 10
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, pal[rng.randi_range(1, 2) if level == 1 else rng.randi_range(2, 3)])
	for i in 18:
		img.set_pixel(rng.randi_range(0, 31), rng.randi_range(0, 31), pal[3] if level == 1 else pal[4])
	for i in 10:
		img.set_pixel(rng.randi_range(0, 31), rng.randi_range(0, 31), pal[0])
	return img


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(y0, 0), mini(y1, img.get_height() - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, img.get_width() - 1) + 1):
			if c.a < 1.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(c))
			else:
				img.set_pixel(x, y, c)
