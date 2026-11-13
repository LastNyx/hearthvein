extends GutTest
## Art manifest coverage (ticket 48): every building and terrain id from data/ has exported art.

var _reg: DataRegistry


func before_each() -> void:
	_reg = DataRegistry.new()
	_reg.load_all()


func test_every_building_has_a_sprite() -> void:
	var missing: Array[String] = []
	for id in _reg.buildings.keys():
		if not ArtLibrary.has_building(id):
			missing.append(id)
	assert_eq(missing, [] as Array[String], "buildings without a sprite in assets/art_manifest.json")


func test_building_sprite_files_exist() -> void:
	for id in _reg.buildings.keys():
		var e := ArtLibrary.building_entry(id)
		assert_true(FileAccess.file_exists(ArtLibrary.ROOT + e["file"]), "%s file" % id)
		assert_true(e.has("base") and e.has("w") and e.has("h"), "%s anchor" % id)


func test_every_terrain_has_tiles() -> void:
	for id in _reg.terrain.keys():
		assert_true(ArtLibrary.has_terrain(id), "terrain %s has tiles" % id)
		var t: Dictionary = ArtLibrary.manifest()["terrain"][id]
		assert_true(FileAccess.file_exists(ArtLibrary.ROOT + t["file"]), "%s atlas" % id)
		assert_gt((t["pick"] as Array).size(), 0, "%s variants" % id)


func test_tilesets_and_sprites_load() -> void:
	assert_gt(ArtLibrary.terrain_tileset().get_source_count(), 0)
	assert_eq(ArtLibrary.road_tileset().get_source_count(), 2)
	var spr := ArtLibrary.building_sprite("hearth")
	assert_not_null(spr.texture)
	spr.free()


func test_anchor_puts_sprite_bottom_on_footprint_bottom() -> void:
	var r := ArtLibrary.sprite_rect("hearth", Vector2i(10, 10), Vector2i(2, 2))
	assert_eq(int(r.end.y) - 1, 12 * ArtLibrary.TILE)
	assert_almost_eq(r.get_center().x, 11.0 * ArtLibrary.TILE, 1.0)
