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


# ---------------------------------------------------------------- terrain polish (ticket 49)
func test_grass_has_at_least_three_variants_in_use() -> void:
	var t: Dictionary = ArtLibrary.manifest()["terrain"]["grass"]
	assert_gte(int(t["cols"]), 3, "grass atlas has 3+ variant tiles")
	var used := {}
	for p in t["pick"]:
		used[int(p)] = true
	assert_gte(used.size(), 3, "pick list uses 3+ variants")
	var seen := {}
	for y in 20:
		for x in 20:
			seen[ArtLibrary.terrain_variant("grass", x, y, 42)] = true
	assert_gte(seen.size(), 3, "variants actually picked across tiles")


func test_variant_picks_are_deterministic_per_seed() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	var c: Array[int] = []
	for y in 16:
		for x in 16:
			a.append(ArtLibrary.terrain_variant("grass", x, y, 7))
			b.append(ArtLibrary.terrain_variant("grass", x, y, 7))
			c.append(ArtLibrary.terrain_variant("grass", x, y, 8))
	assert_eq(a, b, "same seed, same picks")
	assert_ne(a, c, "another seed picks differently")


func test_picks_do_not_touch_rng_state() -> void:
	seed(5)
	var before := randi()
	seed(5)
	for i in 50:
		ArtLibrary.terrain_cell("grass", i, i * 3, 99)
	assert_eq(randi(), before, "drawing leaves the global RNG alone")


func test_edge_masks_exist_and_stumps_are_forest_floor() -> void:
	var m := ArtLibrary.manifest()
	for g in ["forest", "soil", "rock"]:
		assert_true(m["overlays"].has(g), "overlay atlas for %s" % g)
		assert_true(FileAccess.file_exists(ArtLibrary.ROOT + m["overlays"][g]), g)
	assert_eq(ArtLibrary.ground_of("stump"), "forest", "felled tiles read as forest floor")
	var used := {}
	for mask in 256:
		used[int(m["overlay_index"][mask])] = true
	assert_gt(used.size(), 20, "blob set covers the 8-neighbour masks")


func _mapview() -> MapView:
	var map := MapGen.generate(42, _reg)
	var v := MapView.new()
	add_child_autofree(v)
	v.setup(map)
	return v


func test_border_between_soil_and_grass_uses_a_soil_edge_tile() -> void:
	var v := _mapview()
	var soil_layer := v.get_node("Overlay_soil") as TileMapLayer
	var checked := 0
	for y in range(1, MapState.HEIGHT - 1):
		for x in range(1, MapState.WIDTH - 1):
			if v.map.terrain_id_at(x, y) == "grass" and v.map.terrain_id_at(x + 1, y) == "fertile_soil":
				assert_ne(soil_layer.get_cell_source_id(Vector2i(x, y)), -1, "grass next to soil has an edge tile")
				checked += 1
	assert_gt(checked, 0, "map has a soil/grass border")


func test_refresh_tile_updates_neighbour_edges() -> void:
	var v := _mapview()
	var soil_layer := v.get_node("Overlay_soil") as TileMapLayer
	var spot := Vector2i(-1, -1)
	for y in range(3, MapState.HEIGHT - 3):
		for x in range(3, MapState.WIDTH - 3):
			var clear := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if v.map.terrain_id_at(x + dx, y + dy) != "grass":
						clear = false
			if clear and spot.x < 0:
				spot = Vector2i(x, y)
	assert_gt(spot.x, -1, "found open grass")
	assert_eq(soil_layer.get_cell_source_id(spot + Vector2i(1, 0)), -1, "no edge before")
	v.map.set_terrain(spot.x, spot.y, v.map.terrain_index("fertile_soil"))
	v.refresh_tile(spot)
	assert_ne(soil_layer.get_cell_source_id(spot + Vector2i(1, 0)), -1, "neighbour got an edge tile")
	assert_ne(soil_layer.get_cell_source_id(spot + Vector2i(-1, -1)), -1, "diagonal neighbour got an edge tile")
