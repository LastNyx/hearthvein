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


# ---------------------------------------------------------------- walker sprites (ticket 50)
func test_walker_sheet_has_4_directions_and_walk_frames() -> void:
	var e := ArtLibrary.walker_entry()
	assert_eq((e["directions"] as Array).size(), 4)
	assert_gte(int(e["frames"]), 3, "two steps plus a standing frame")
	assert_gt(int(e["variants"]), 8, "several seeded looks")
	var img := ArtLibrary.texture(e["file"]).get_image()
	var cell: Array = e["cell"]
	assert_eq(img.get_width(), int(e["frames"]) * int(cell[0]))
	assert_eq(img.get_height(), int(e["variants"]) * 4 * int(cell[1]))
	# every direction and frame cell of look 0 has pixels, and the two step frames differ
	for d in 4:
		for f in int(e["frames"]):
			var r := ArtLibrary.walker_region(0, d, f)
			assert_false(img.get_region(Rect2i(r)).is_invisible(), "dir %d frame %d drawn" % [d, f])
		var a := img.get_region(Rect2i(ArtLibrary.walker_region(0, d, 0)))
		var b := img.get_region(Rect2i(ArtLibrary.walker_region(0, d, 1)))
		assert_ne(a.get_data(), b.get_data(), "step frames differ in dir %d" % d)
	assert_true(FileAccess.file_exists(ArtLibrary.ROOT + e["shadow"]))
	for k in e["bundle"]:
		assert_true(FileAccess.file_exists(ArtLibrary.ROOT + e["bundle"][k]))


func test_walker_facing_follows_movement_vector() -> void:
	assert_eq(ArtLibrary.facing_for(Vector2(1, 0)), ArtLibrary.DIR_RIGHT)
	assert_eq(ArtLibrary.facing_for(Vector2(-1, 0)), ArtLibrary.DIR_LEFT)
	assert_eq(ArtLibrary.facing_for(Vector2(0, 1)), ArtLibrary.DIR_DOWN)
	assert_eq(ArtLibrary.facing_for(Vector2(0, -1)), ArtLibrary.DIR_UP)
	assert_eq(ArtLibrary.facing_for(Vector2.ZERO, ArtLibrary.DIR_LEFT), ArtLibrary.DIR_LEFT, "standing keeps facing")
	var w := Walker.new()
	w.tile = Vector2i(5, 5)
	assert_eq(WalkerView.move_vector(w), Vector2.ZERO, "no path, not moving")
	w.path = [Vector2i(4, 5)] as Array[Vector2i]
	assert_eq(ArtLibrary.facing_for(WalkerView.move_vector(w)), ArtLibrary.DIR_LEFT)


func test_same_citizen_keeps_the_same_look() -> void:
	var n := int(ArtLibrary.walker_entry()["variants"])
	var seen := {}
	for id in 60:
		var v := ArtLibrary.walker_variant(id, 42)
		assert_eq(v, ArtLibrary.walker_variant(id, 42), "stable")
		assert_true(v >= 0 and v < n)
		seen[v] = true
	assert_gt(seen.size(), 8, "a crowd is not cloned")


# ---------------------------------------------------------------- terrain polish round 2 (ticket 51)
func test_shade_is_not_periodic_over_20_or_40_tiles() -> void:
	for period in [20, 40]:
		var same := 0
		var n := 0
		for y in range(0, 60, 3):
			for x in range(0, 60, 3):
				n += 1
				if absf(ArtLibrary.shade_value(42, x, y) - ArtLibrary.shade_value(42, x + period, y)) < 0.01 \
						and absf(ArtLibrary.shade_value(42, x, y) - ArtLibrary.shade_value(42, x, y + period)) < 0.01:
					same += 1
		assert_lt(same, n / 4, "shade does not repeat every %d tiles" % period)


func test_shade_is_deterministic_per_seed_and_varies() -> void:
	var a: Array[float] = []
	var b: Array[float] = []
	var c: Array[float] = []
	for i in 80:
		a.append(ArtLibrary.shade_value(9, i, i * 2))
		b.append(ArtLibrary.shade_value(9, i, i * 2))
		c.append(ArtLibrary.shade_value(10, i, i * 2))
	assert_eq(a, b, "same seed, same shade")
	assert_ne(a, c, "another seed shades differently")
	assert_gt(a.max() - a.min(), 0.3, "patches actually vary")
	seed(5)
	var before := randi()
	seed(5)
	ArtLibrary.shade_value(1, 3, 4)
	assert_eq(randi(), before, "shade leaves the global RNG alone")


func test_shade_covers_grass_not_water_or_rock() -> void:
	var v := _mapview()
	var img: Image = v._shade_image
	assert_eq(img.get_width(), MapState.WIDTH)
	var grass_alpha := 0.0
	var other_alpha := 0.0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := v.map.terrain_id_at(x, y)
			if t == "grass":
				grass_alpha += img.get_pixel(x, y).a
			elif t in ["water", "rock", "lumen_vein"]:
				other_alpha += img.get_pixel(x, y).a
	assert_gt(grass_alpha, 10.0, "grass is shaded")
	assert_eq(other_alpha, 0.0, "water and rock are not")


func _border_has_edge(ground_hi: String, layer_name: String) -> int:
	var v := _mapview()
	var layer := v.get_node(layer_name) as TileMapLayer
	var checked := 0
	for y in range(1, MapState.HEIGHT - 1):
		for x in range(1, MapState.WIDTH - 1):
			if v.map.terrain_id_at(x, y) == "grass" and ArtLibrary.ground_of(v.map.terrain_id_at(x + 1, y)) == ground_hi:
				assert_ne(layer.get_cell_source_id(Vector2i(x, y)), -1, "grass next to %s has an edge tile" % ground_hi)
				checked += 1
	return checked


func test_rock_borders_use_soft_edge_tiles() -> void:
	assert_gt(_border_has_edge("rock", "Overlay_rock"), 0, "map has a rock/grass border")


func test_vein_borders_use_soft_edge_tiles() -> void:
	var m := ArtLibrary.manifest()
	assert_true(m["overlays"].has("vein"))
	_border_has_edge("vein", "Overlay_vein")


func test_rock_and_vein_edges_are_wide_dithers() -> void:
	# soft outline: the edge tile of rock/vein must have partial coverage deep into the neighbour tile
	for g in ["rock", "vein"]:
		var img := ArtLibrary.texture(ArtLibrary.manifest()["overlays"][g]).get_image()
		var mask := 4  # east neighbour only
		var idx := int(ArtLibrary.manifest()["overlay_index"][mask])
		var c := ArtLibrary.overlay_coords(mask, false)
		assert_eq(idx, c.y * 8 + c.x)
		var covered := 0
		var clear := 0
		for px in range(32 - 14, 32 - 6):  # a band that a hard edge would leave fully on or off
			for py in 32:
				if img.get_pixel(c.x * 32 + px, c.y * 32 + py).a > 0.0:
					covered += 1
				else:
					clear += 1
		assert_gt(covered, 0, "%s bleeds into the neighbour tile" % g)
		assert_gt(clear, 0, "%s fades out, so the outline is not a straight tile edge" % g)


func test_overlay_variants_exist_and_are_picked_by_hash() -> void:
	var n := int(ArtLibrary.manifest()["overlay_variants"])
	assert_gte(n, 2)
	assert_ne(ArtLibrary.overlay_coords(4, false, 0), ArtLibrary.overlay_coords(4, false, 1))


func test_forest_edge_trees_jitter_and_thin_deterministically() -> void:
	var inner := 0
	var edge := 0
	var moved := 0
	for i in 200:
		var a := ArtLibrary.scatter("forest", i, 7)
		var b := ArtLibrary.scatter("forest", i, 7, Vector2i(1, 0))
		assert_eq(b, ArtLibrary.scatter("forest", i, 7, Vector2i(1, 0)), "deterministic")
		inner += a.size()
		edge += b.size()
		if not a.is_empty() and not b.is_empty() and a[0]["pos"] != b[0]["pos"]:
			moved += 1
	assert_lt(edge, inner, "edge tiles hold fewer trees")
	assert_gt(moved, 50, "edge trees are offset")


func test_grass_confetti_is_dense() -> void:
	var img := ArtLibrary.texture(ArtLibrary.manifest()["terrain"]["grass"]["file"]).get_image()
	var palette := [Color8(0xf0, 0x7a, 0xa8), Color8(0xf6, 0xf0, 0xe0), Color8(0x8a, 0xb8, 0xf8), Color8(0xf4, 0xd0, 0x50)]
	var specks := 0
	for y in 32:
		for x in range(32 * 3, 32 * 4):  # the flowers variant
			var c := img.get_pixel(x, y)
			for p in palette:
				if c.is_equal_approx(p):
					specks += 1
	assert_gt(specks, 8, "flower tile carries confetti")
