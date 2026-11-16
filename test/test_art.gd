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
	for g in ArtLibrary.overlay_grounds():
		assert_true(FileAccess.file_exists(ArtLibrary.ROOT + m["overlays"][g]), "overlay atlas for %s" % g)
	assert_false(m["overlays"].has("rock"), "rock edges come from the dual grid now")
	assert_false(m["overlays"].has("water"), "water shores come from the dual grid now")
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


func test_rock_borders_use_dual_grid_cells() -> void:
	var v := _mapview()
	var rock := v.get_node("RockEdge") as TileMapLayer
	var rock_ground := ArtLibrary.ground_rank("rock")
	var checked := 0
	var water_only := 0
	var bad: Array[String] = []
	for j in range(1, MapState.HEIGHT):
		for i in range(1, MapState.WIDTH):
			var corner := Vector2i(i, j)
			var mask := 0
			var ground := ""
			var ground_rank := -1
			var blocked := false
			var has_rock := false
			for k in 4:
				var p: Vector2i = corner + MapView.DUAL_CORNERS[k]
				var g := ArtLibrary.ground_of(v.map.terrain_id_at(p.x, p.y))
				if g == "rock":
					mask |= 1 << k
					has_rock = true
					continue
				if g == "water":
					continue  # the shore draws the rock/water boundary; the rock atlas has no water ground
				var r := ArtLibrary.ground_rank(g)
				if r >= rock_ground:
					blocked = true
					continue
				if r > ground_rank:
					ground_rank = r
					ground = g
			if blocked or not has_rock:
				continue
			if ground == "":  # rock against water only: no land ground to draw the rock edge onto
				if rock.get_cell_source_id(corner) != -1:
					bad.append("%s should be empty" % corner)
				water_only += 1
				continue
			if rock.get_cell_atlas_coords(corner) != ArtLibrary.autotile_coords(mask):
				bad.append("%s wrong tile" % corner)
			checked += 1
	assert_eq(bad.size(), 0, "rock corners with the wrong tile: %s" % [bad.slice(0, 8)])
	assert_gt(checked, 20, "map has a rock/grass border")
	assert_gt(water_only, 0, "map has rock/water-only corners for the shore")


func test_vein_borders_use_soft_edge_tiles() -> void:
	var m := ArtLibrary.manifest()
	assert_true(m["overlays"].has("vein"))
	_border_has_edge("vein", "Overlay_vein")


func test_vein_edges_are_wide_dithers() -> void:
	# soft outline: the edge tile of vein must have partial coverage deep into the neighbour tile
	for g in ["vein"]:
		var img := ArtLibrary.texture(ArtLibrary.manifest()["overlays"][g]).get_image()
		var mask := 4  # east neighbour only
		var idx := int(ArtLibrary.manifest()["overlay_index"][mask])
		var c := ArtLibrary.overlay_coords(mask)
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
	assert_ne(ArtLibrary.overlay_coords(4, 0), ArtLibrary.overlay_coords(4, 1))


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


# ---- ticket 53 polish pass

func test_water_lilies_are_hashed_interior_and_vary() -> void:
	var counts := {}
	for y in 40:
		for x in 40:
			var a := ArtLibrary.scatter("water", x, y)
			assert_eq(a, ArtLibrary.scatter("water", x, y), "same tile gives the same pads")
			assert_eq(ArtLibrary.scatter("water", x, y, Vector2i(1, 0)), [], "no pads on shore tiles")
			counts[a.size()] = true
			for p in a:
				assert_true(String(p["name"]).begins_with("lily"))
	assert_true(counts.has(0) and counts.has(1) and counts.has(2), "0, 1 and 2 pads occur")


func test_water_tiles_have_no_baked_lilies() -> void:
	var t: Dictionary = ArtLibrary.manifest()["terrain"]["water"]
	assert_eq(int(t["cols"]), 5)
	var img := ArtLibrary.texture(t["file"]).get_image()
	for v in 5:  # the pad green (leaf) never appears in a water tile
		var found := false
		for y in 32:
			for x in 32:
				var c := img.get_pixel(v * 32 + x, y)
				if c.g > c.b + 0.05:
					found = true
		assert_false(found, "variant %d has no green pad pixels" % v)


func test_state_edges_soft_blight() -> void:
	var st: Dictionary = ArtLibrary.manifest()["states"]
	assert_true(st["blight"].has("edge_file") and st["fouled"].has("edge_file"))
	assert_eq(ArtLibrary.state_edge_coords(0), Vector2i(-1, -1))
	assert_true(ArtLibrary.state_edge_coords(1 << 2).x >= 0)
	# edge tile next to a blighted tile is partly transparent (soft bleed), not a flat square
	var ts := ArtLibrary.state_tileset("blight")
	assert_not_null(ts.get_source(1))
	var img := ArtLibrary.texture(st["blight"]["edge_file"]).get_image()
	var c := ArtLibrary.state_edge_coords(1 << 2)  # blight to the east
	var east_a := img.get_pixel(c.x * 32 + 31, c.y * 32 + 16).a
	var west_a := img.get_pixel(c.x * 32 + 1, c.y * 32 + 16).a
	assert_true(east_a > 0.5 and west_a < 0.1, "opaque at the shared edge, clear far away")


func test_blight_sparkles_are_hashed() -> void:
	var n := 0
	for y in 30:
		for x in 30:
			var a := ArtLibrary.blight_sparkle(42, x, y)
			assert_eq(a, ArtLibrary.blight_sparkle(42, x, y))
			if not a.is_empty():
				n += 1
				assert_true(ArtLibrary.manifest()["props"].has(a["name"]))
	assert_true(n > 100 and n < 450, "about 30 percent of tiles: %d" % n)


func test_site_art_picks_tier_and_exists() -> void:
	var small := ArtLibrary.site_art(Vector2i(1, 1), 20.0)
	var big := ArtLibrary.site_art(Vector2i(3, 2), 90.0)
	assert_eq(small["plot"].get_width(), 32)
	assert_eq(big["plot"].get_height(), 64)
	assert_true(big["scaffold"].get_height() > small["scaffold"].get_height())
	assert_eq(big["scaffold"].get_width(), 96)


func test_refresh_tile_keeps_props_off_roads() -> void:
	var s := Settlement.new_game(42, _reg)
	var view := MapView.new()
	add_child_autofree(view)
	view.setup(s.map)
	var pv := PlacementView.new()
	add_child_autofree(pv)
	pv.setup(s, view)
	var t := Vector2i(-1, -1)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if t.x < 0 and s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
				if s.can_place_road(Vector2i(x, y)):
					t = Vector2i(x, y)
				else:
					s.set_terrain(Vector2i(x, y), "forest")
	assert_true(t.x >= 0)
	assert_true(s.place_road(t))
	s.set_terrain(t, "forest")  # terrain changes under the road: props must stay hidden
	view.refresh_tile(t)
	for n in view._props.get(t, []):
		assert_false((n as CanvasItem).visible)
	assert_true(view._prop_batch.is_hidden(t), "the batched tree instances are hidden under the road too")


# ---------------------------------------------------------------- shore and rock autotiles (ticket 54)

func _autotile_region(pair: String, ground: String, mask: int) -> Image:
	var img := ArtLibrary.texture(ArtLibrary.manifest()["autotiles"][pair]["files"][ground]).get_image()
	var c := ArtLibrary.autotile_coords(mask)
	return img.get_region(Rect2i(c * ArtLibrary.TILE, Vector2i(ArtLibrary.TILE, ArtLibrary.TILE)))


## Mean colour of a square block inside a dual tile.
func _block(img: Image, x: int, y: int, n: int = 4) -> Color:
	var acc := Color(0, 0, 0, 0)
	for py in range(y, y + n):
		for px in range(x, x + n):
			acc += img.get_pixel(px, py)
	return acc * (1.0 / float(n * n))


func _is_water(c: Color) -> bool:
	return c.a > 0.5 and c.b > c.g and c.b > c.r  # every lake band leans blue; the rest does not


func _is_rock(c: Color) -> bool:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return c.a > 0.5 and c.g - c.r < 0.12 and hi - lo < 0.22  # stony grey-green gravel (ticket 56): not meadow, not empty


func test_autotile_pairs_cover_water_and_rock() -> void:
	assert_eq(ArtLibrary.autotile_pairs(), ["rock", "water"] as Array[String])
	assert_eq(ArtLibrary.autotile_grounds("water"), ["grass", "forest", "soil", "rock", "vein", "sky"])
	assert_eq(ArtLibrary.autotile_grounds("rock"), ["grass", "forest", "soil"])
	assert_eq(ArtLibrary.autotile_source("water", "forest"), 1)
	assert_eq(ArtLibrary.autotile_source("rock", "vein"), -1, "vein is not a lower ground of rock")


func test_every_corner_configuration_has_an_atlas_region() -> void:
	for pair in ArtLibrary.autotile_pairs():
		var ts := ArtLibrary.autotile_tileset(pair)
		var grounds: Array = ArtLibrary.autotile_grounds(pair)
		assert_eq(ts.get_source_count(), grounds.size(), "%s has one atlas per lower ground" % pair)
		for gi in grounds.size():
			var src := ts.get_source(gi) as TileSetAtlasSource
			assert_not_null(src, "%s/%s source" % [pair, grounds[gi]])
			assert_eq(ArtLibrary.autotile_source(pair, grounds[gi]), gi)
			var img := src.texture.get_image()
			assert_eq(img.get_size(), Vector2i(4 * ArtLibrary.TILE, 4 * ArtLibrary.TILE), "%s atlas size" % pair)
			for mask in range(1, 15):  # 0 and 15 have no edge and are never drawn
				var c := ArtLibrary.autotile_coords(mask)
				assert_eq(c, Vector2i(mask % 4, mask / 4), "mask %d coords" % mask)
				assert_true(src.has_tile(c), "%s/%s mask %d has a tile" % [pair, grounds[gi], mask])
				assert_false(img.get_region(Rect2i(c * ArtLibrary.TILE, Vector2i(ArtLibrary.TILE, ArtLibrary.TILE))).is_invisible(),
						"%s/%s mask %d is drawn" % [pair, grounds[gi], mask])


func test_lone_corner_is_a_round_lobe_not_a_square() -> void:
	# mask 1: only the top-left map tile is upper ground, so the lobe is the quarter disc around the dual cell corner
	var tile := _autotile_region("water", "grass", 1)
	assert_true(_is_water(_block(tile, 2, 2)), "around the corner is water")
	assert_true(_is_water(_block(tile, 6, 6)), "10 px out on the diagonal still water")
	assert_true(_is_water(_block(tile, 2, 8)), "10 px out along the left edge still water")
	assert_true(_is_water(_block(tile, 8, 2)), "10 px out along the top edge still water")
	assert_false(_is_water(_block(tile, 13, 13)), "the diagonal is land: the disc is round, not a square")
	assert_false(_is_water(_block(tile, 24, 24)), "the far corner is land")
	var rock := _autotile_region("rock", "grass", 1)
	# The rock tile's base texture shows through where the atlas fades out (the tile centre), so sample the band
	# the atlas actually paints and the lower-ground quarters where it must paint nothing.
	assert_true(_is_rock(_block(rock, 8, 2)), "rock inside the lobe edge")
	assert_true(_is_rock(_block(rock, 2, 8)), "rock inside the lobe edge on the other axis")
	assert_false(_is_rock(_block(rock, 24, 24)), "grass at the far corner")


func test_diagonal_shore_connects_instead_of_pinching() -> void:
	# mask 5: water at the top-left and bottom-right corners. A stair-step autotile pinches the diagonal to a
	# point; the saddle shape keeps the water joined through the middle of the dual cell.
	for mask in [5, 10]:
		var t := _autotile_region("water", "forest", mask)
		assert_true(_is_water(_block(t, 14, 14)), "mask %d keeps the diagonal connected" % mask)
	# mask 10: the top-right and bottom-left map tiles are water, the other two are land lobes
	var ten := _autotile_region("water", "forest", 10)
	assert_false(_is_water(_block(ten, 24, 24)), "mask 10 land at the bottom-right")
	assert_false(_is_water(_block(ten, 2, 2)), "mask 10 land at the top-left")


func test_shore_and_rock_are_one_shifted_layer_per_pair() -> void:
	var v := _mapview()
	var shore := v.get_node("Shore") as TileMapLayer
	var rock := v.get_node("RockEdge") as TileMapLayer
	assert_not_null(shore, "one Shore layer")
	assert_not_null(rock, "one RockEdge layer")
	assert_null(v.get_node_or_null("Overlay_rock"), "no per-tile rock bank layer")
	assert_gt(shore.get_index(), rock.get_index(), "the shore draws over the rock edge on three-way corners")
	for layer in [shore, rock]:
		assert_eq(layer.position, Vector2(-ArtLibrary.TILE / 2.0, -ArtLibrary.TILE / 2.0), "drawn on corners")
		assert_eq(layer.get_child_count(), 0, "batched: no per-cell sprite nodes")
		assert_eq(layer.tile_set.tile_size, Vector2i(ArtLibrary.TILE, ArtLibrary.TILE))


func _clear_grass(v: MapView, radius: int) -> Vector2i:
	for y in range(radius + 1, MapState.HEIGHT - radius - 1):
		for x in range(radius + 1, MapState.WIDTH - radius - 1):
			var clear := true
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if v.map.terrain_id_at(x + dx, y + dy) != "grass":
						clear = false
			if clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_shore_cells_match_the_four_corners_of_each_map_corner() -> void:
	var v := _mapview()
	var shore := v.get_node("Shore") as TileMapLayer
	var checked := 0
	var bad: Array[String] = []
	for j in range(1, MapState.HEIGHT):
		for i in range(1, MapState.WIDTH):
			var corner := Vector2i(i, j)
			var mask := 0
			for k in 4:
				var p: Vector2i = corner + MapView.DUAL_CORNERS[k]
				if ArtLibrary.ground_of(v.map.terrain_id_at(p.x, p.y)) == "water":
					mask |= 1 << k
			if mask == 0 or mask == 15:
				if shore.get_cell_source_id(corner) != -1:
					bad.append("%s should be empty" % corner)
			else:
				if shore.get_cell_atlas_coords(corner) != ArtLibrary.autotile_coords(mask):
					bad.append("%s wrong tile" % corner)
				checked += 1
	assert_eq(bad.size(), 0, "shore corners: %s" % [bad.slice(0, 8)])
	assert_gt(checked, 100, "the map has a long shore")


func test_refresh_tile_updates_the_four_dual_cells_around_it() -> void:
	var v := _mapview()
	var shore := v.get_node("Shore") as TileMapLayer
	var spot := _clear_grass(v, 2)
	assert_true(spot.x >= 0, "found open grass")
	var corner_cells := [spot, spot + Vector2i(1, 0), spot + Vector2i(0, 1), spot + Vector2i(1, 1)]
	for c in corner_cells:
		assert_eq(shore.get_cell_source_id(c), -1, "no shore at %s before" % c)
	var untouched := spot + Vector2i(3, 3)  # not one of the four corners of the changed tile
	var before_src := shore.get_cell_source_id(untouched)
	var before_coords := shore.get_cell_atlas_coords(untouched)
	v.map.set_terrain(spot.x, spot.y, v.map.terrain_index("water"))
	v.refresh_tile(spot)
	var expected := [4, 8, 2, 1]  # the new water tile is the BR, BL, TR and TL quadrant of the four corners
	for i in 4:
		var mask: int = expected[i]
		assert_ne(shore.get_cell_source_id(corner_cells[i]), -1, "dual cell %s updated" % corner_cells[i])
		assert_eq(shore.get_cell_atlas_coords(corner_cells[i]), ArtLibrary.autotile_coords(mask),
				"mask at %s" % corner_cells[i])
	assert_eq(shore.get_cell_source_id(untouched), before_src, "far cells untouched")
	assert_eq(shore.get_cell_atlas_coords(untouched), before_coords, "far tile unchanged")
	assert_eq(shore.get_cell_atlas_coords(spot), ArtLibrary.autotile_coords(4))


## Three-way corner (fix round 2): water bottom-left, rock bottom-right, two land tiles on top. The shore used to
## take the highest non-water ground (rock) as its atlas and stamp rock texture over the land tiles' quarters, which
## read as a square rock corner at the lake. Land lowers than rock must win, and the shore must not paint the land
## quarters at all; the rock tile keeps its own ground from RockEdge.
func _three_way_corner(v: MapView, land_id: String) -> Vector2i:
	var s := _clear_grass(v, 3)
	assert_true(s.x >= 0, "found open grass")
	for dy in 2:
		for dx in 2:
			v.map.set_terrain(s.x + dx, s.y + dy, v.map.terrain_index(land_id))
	v.map.set_terrain(s.x, s.y + 1, v.map.terrain_index("water"))
	v.map.set_terrain(s.x + 1, s.y + 1, v.map.terrain_index("rock"))
	#                     land  land
	#                     water rock  -> the corner at the tile centre
	for dy in 2:
		for dx in 2:
			v.refresh_tile(s + Vector2i(dx, dy))
	return s + Vector2i(1, 1)


func test_three_way_corner_keeps_the_land_ground() -> void:
	var v := _mapview()
	var shore := v.get_node("Shore") as TileMapLayer
	var rock := v.get_node("RockEdge") as TileMapLayer
	for land_id in ["fertile_soil", "grass"]:
		var ground := ArtLibrary.ground_of(land_id)
		var c := _three_way_corner(v, land_id)
		assert_eq(rock.get_cell_source_id(c), ArtLibrary.autotile_source("rock", ground),
				"the rock edge is drawn (%s)" % ground)
		assert_eq(rock.get_cell_atlas_coords(c), ArtLibrary.autotile_coords(4),
				"only the rock tile is on the rock side (%s)" % ground)
		var src := shore.get_cell_source_id(c)
		assert_ne(src, ArtLibrary.autotile_source("water", "rock"),
				"the shore does not use the rock atlas (%s)" % ground)
		assert_eq(src, ArtLibrary.autotile_source("water", ground),
				"the shore fills with the land below rock (%s)" % ground)
		assert_eq(shore.get_cell_atlas_coords(c), ArtLibrary.autotile_coords(8),
				"water in the bottom-left quadrant (%s)" % ground)
		# Pixel level: the shore atlas tile paints nothing on the three land quadrants, so the soil/grass and
		# rock tiles keep their own ground instead of a stamped square.
		var img := ArtLibrary.texture(ArtLibrary.manifest()["autotiles"]["water"]["files"][ground]).get_image()
		var ac := shore.get_cell_atlas_coords(c)
		for q in [Vector2i(0, 0), Vector2i(16, 0), Vector2i(16, 16)]:
			var opaque := 0
			for y in 16:
				for x in 16:
					if img.get_pixel(ac.x * ArtLibrary.TILE + q.x + x, ac.y * ArtLibrary.TILE + q.y + y).a > 0.0:
						opaque += 1
			assert_eq(opaque, 0, "shore tile is clear on land quadrant %s (%s)" % [q, ground])


func test_rock_water_only_corners_are_left_to_the_shore() -> void:
	var v := _mapview()
	var rock := v.get_node("RockEdge") as TileMapLayer
	var shore := v.get_node("Shore") as TileMapLayer
	var s := _clear_grass(v, 3)
	assert_true(s.x >= 0, "found open grass")
	for dy in 2:
		for dx in 2:
			v.map.set_terrain(s.x + dx, s.y + dy, v.map.terrain_index("rock"))
	v.map.set_terrain(s.x, s.y + 1, v.map.terrain_index("water"))
	for dy in 2:
		for dx in 2:
			v.refresh_tile(s + Vector2i(dx, dy))
	var c := s + Vector2i(1, 1)
	assert_eq(rock.get_cell_source_id(c), -1, "no rock edge atlas has a water ground: the shore draws this corner")
	assert_eq(shore.get_cell_source_id(c), ArtLibrary.autotile_source("water", "rock"),
			"the shore rounds the water against the rock")
	assert_eq(shore.get_cell_atlas_coords(c), ArtLibrary.autotile_coords(8), "water in the bottom-left")


# ---------------------------------------------------------------- City art (ticket 64)
func test_city_buildings_and_tier_art_are_not_generic_fallbacks() -> void:
	for id in ["grand_bazaar", "purifier_tower", "toolsmith", "lumen_nexus", "hut", "lodge"]:
		assert_true(ArtLibrary.has_building(id), "%s has a sprite" % id)
		assert_false(ArtLibrary.building_entry(id)["generic"], "%s is a drawn sprite, not the category house" % id)


func test_tent_tiers_use_hut_and_lodge_art() -> void:
	var tent := _reg.get_building("tent")
	assert_eq((tent.tiers[0] as TierDef).art_id, "hut")
	assert_eq((tent.tiers[1] as TierDef).art_id, "lodge")


func test_park_is_flat_and_draws_under_a_tall_neighbour() -> void:
	assert_true(ArtLibrary.building_entry("park")["flat"])
	assert_false(ArtLibrary.building_entry("apartment_block")["flat"])
	var s := Settlement.new_game(42, _reg)
	var view := MapView.new()
	add_child_autofree(view)
	view.setup(s.map)
	var o := Vector2i(-1, -1)
	for y in range(2, MapState.HEIGHT - 6):
		for x in range(2, MapState.WIDTH - 6):
			if o.x < 0:
				var clear := true
				for dy in 4:
					for dx in 2:
						if s.map.terrain_id_at(x + dx, y + dy) != "grass":
							clear = false
				if clear:
					o = Vector2i(x, y)
	assert_true(o.x >= 0, "found open grass")
	s._insert_building(_reg.get_building("park"), o)  # placement rules (era, roads) are not under test
	s._insert_building(_reg.get_building("apartment_block"), o + Vector2i(0, 2))
	var before := view.objects.get_child_count()
	var pv := PlacementView.new()
	add_child_autofree(pv)
	pv.setup(s, view)
	assert_eq(view.flats.get_child_count(), 1, "the park sits on the flats layer")
	assert_true(view.objects.get_child_count() >= before + 1, "the apartment block stays among the y-sorted objects")
	assert_lt(view.flats.get_index(), view.objects.get_index(), "flats draw before (under) objects")
