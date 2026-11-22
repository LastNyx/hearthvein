extends GutTest
## Ticket 127: the bottom-left minimap (hud-rts-spec H7). The map is one image at 1 px per tile (terrain, roads,
## building footprints, unbought regions dimmed), the camera view rectangle sits on top, a click or drag moves the
## camera centre, and the Ground/Sky + overlay toggles live to its right.

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _game() -> Node:
	var dir := "/tmp/nyx-flash/hearthvein_minimap_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	main.saves_dir = dir
	main.settings_path = dir + "/settings.cfg"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game()
	await wait_process_frames(2)
	return main


func _mini(main: Node) -> Minimap:
	return (main.get_node("Hud") as Hud).minimap


## A row with no building on those six tiles, left to right from x = 10.
func _empty_row(s: Settlement) -> int:
	for y in range(1, MapState.HEIGHT - 1):
		var ok := true
		for x in range(10, 16):
			if s.occupancy[MapState.idx(x, y)] != -1:
				ok = false
		if ok:
			return y
	return -1


## A free ground tile near the Hearth for a 1x1 woodcutter.
func _free_spot(s: Settlement) -> Vector2i:
	var h := s.map.hearth_spot
	for y in range(h.y - 10, h.y + 10):
		for x in range(h.x + 4, h.x + 24):
			var t := Vector2i(x, y)
			if MapState.in_bounds(t.x, t.y) and s.can_place("woodcutter", t)["ok"]:
				return t
	return Vector2i(-1, -1)


func _collect_buttons(n: Node, out: Array[String]) -> void:
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_collect_buttons(c, out)


# AC1: 1 px per tile, the terrain colours of the ticket, and a building's whole footprint.
func test_image_size_colours_and_building_footprint() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var mini: Minimap = _mini(main)
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)  # bought land, so no dimming on the colours below
	var y := _empty_row(s)
	assert_true(y >= 0, "a row with no buildings")
	var painted := {"water": Color("3d6a9a"), "grass": Color("6a9a48"), "forest": Color("2f5e32"),
			"rock": Color("8a8a8e"), "lumen_vein": Color("6fd8e8"), "fertile_soil": Color("8a6a42")}
	var x := 10
	for id in painted:
		s.set_terrain(Vector2i(x, y), id)
		x += 1
	mini.rebuild()
	assert_eq(mini.image.get_size(), Vector2i(MapState.WIDTH, MapState.HEIGHT), "1 px per map tile")
	x = 10
	for id in painted:
		assert_eq(mini.image.get_pixel(x, y), painted[id], id)
		x += 1
	var hb: Building = s.hearth
	assert_not_null(hb)
	var inked := 0
	for dy in hb.def.size.y:
		for dx in hb.def.size.x:
			if mini.image.get_pixel(hb.origin.x + dx, hb.origin.y + dy) == Minimap.BUILDING:
				inked += 1
	assert_eq(inked, hb.def.size.x * hb.def.size.y, "the Hearth's footprint is drawn as a building")


# AC2: a minimap point maps to the world tile under it, clamped at the map edges; a click (or drag) moves the camera.
func test_minimap_point_to_world_and_click_jump() -> void:
	assert_eq(Minimap.point_to_world(Vector2.ZERO), Vector2.ZERO, "the top-left corner")
	assert_eq(Minimap.point_to_world(Vector2(64, 48)), Vector2(2048, 1536), "the centre")
	assert_eq(Minimap.point_to_world(Vector2(MapState.WIDTH, MapState.HEIGHT)), Vector2(4096, 3072),
			"the bottom-right edge")
	assert_eq(Minimap.point_to_world(Vector2(200, 200)), Vector2(4096, 3072), "past the edge clamps to it")
	var main: Node = await _game()
	var mini: Minimap = _mini(main)
	var cam: CameraController = main.camera
	cam.set_zoom_step(3)  # 2x, half a view is 320 x 180 world px
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(64, 48)
	mini.map_area.gui_input.emit(click)
	assert_eq(cam.position, Vector2(2048, 1536), "the view centre goes to the clicked tile")
	click.position = Vector2.ZERO
	mini.map_area.gui_input.emit(click)
	var half := cam.get_viewport_rect().size / 4.0
	assert_eq(cam.position, Vector2(half.x, half.y), "the top-left edge stops at the view's half size")
	click.position = Vector2(MapState.WIDTH, MapState.HEIGHT)
	mini.map_area.gui_input.emit(click)
	var world := Vector2(MapState.WIDTH, MapState.HEIGHT) * ArtLibrary.TILE
	assert_eq(cam.position, world - half, "the bottom-right edge")
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(32, 24)
	drag.relative = Vector2(1, 1)
	mini.map_area.gui_input.emit(drag)
	assert_eq(cam.position, Vector2(1024, 768), "a drag moves the centre while the button is down")


# AC3: the image is rebuilt by building events, not once per frame.
func test_image_rebuilds_on_building_events_not_every_frame() -> void:
	var main: Node = await _game()
	var s: Settlement = main.settlement
	var mini: Minimap = _mini(main)
	var start := mini.rebuilds
	await wait_process_frames(3)
	assert_eq(mini.rebuilds, start, "frames alone do not rebuild the image")
	var spot := _free_spot(s)
	assert_true(spot.x >= 0, "a free spot")
	var id := s.place_building_instant("woodcutter", spot)
	assert_true(id >= 0)
	assert_eq(mini.rebuilds, start + 1, "placing a building rebuilds it")
	assert_eq(mini.image.get_pixel(spot.x, spot.y), Minimap.BUILDING, "and the footprint is on the new image")
	s.demolish(id)
	assert_eq(mini.rebuilds, start + 2, "demolishing rebuilds it")
	assert_ne(mini.image.get_pixel(spot.x, spot.y), Minimap.BUILDING, "and the footprint is gone")


# AC4: the minimap's overlay buttons switch the same HudModel state as the V G T H L keys.
func test_minimap_overlay_toggles_match_the_keys() -> void:
	var main: Node = await _game()
	var mini: Minimap = _mini(main)
	var m: HudModel = main.hud_model
	for pair in Minimap.TOGGLES:
		var id: String = pair[0]
		var b: Button = mini.overlay_button(id)
		assert_not_null(b, id)
		assert_string_contains(b.text, OS.get_keycode_string(Hud.OVERLAY_KEYS[id]), "the button carries its key")
		var before := m.overlay_on(id)
		b.pressed.emit()
		assert_eq(m.overlay_on(id), not before, "the %s button toggles it" % id)
	var ev := InputEventKey.new()
	ev.keycode = KEY_V
	ev.pressed = true
	var on := m.overlay_on("blight")
	main.hud._unhandled_input(ev)
	assert_eq(m.overlay_on("blight"), not on, "V toggles the same state")
	main.hud._unhandled_input(ev)
	assert_eq(m.overlay_on("blight"), on)


# AC (130b): every overlay label names the key the HUD input reads from the same table (Hud.OVERLAY_KEYS).
func test_overlay_labels_use_the_input_key_table() -> void:
	var main: Node = await _game()
	var mini: Minimap = _mini(main)
	var m: HudModel = main.hud_model
	var ids: Array[String] = ["blight", "roads", "water", "coverage", "grid"]
	var letters: Array[String] = ["V", "G", "T", "H", "L"]
	for i in ids.size():
		var id := ids[i]
		var key: Key = Hud.OVERLAY_KEYS[id]
		assert_eq(OS.get_keycode_string(key), letters[i], "the %s key is %s" % [id, letters[i]])
		assert_eq((mini.overlay_button(id).text as String).split(" ")[0], letters[i],
				"the %s button shows its key" % id)
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.pressed = true
		var before := m.overlay_on(id)
		main.hud._unhandled_input(ev)
		assert_eq(m.overlay_on(id), not before, "%s toggles through the same table" % letters[i])


# AC5: the old top-right Overlays button (and its menu) is gone.
func test_old_overlay_menu_button_is_gone() -> void:
	var main: Node = await _game()
	var texts: Array[String] = []
	_collect_buttons(main.get_node("Hud"), texts)
	assert_false(texts.has("Overlays"), "no button labelled Overlays in the HUD")
	assert_gt(texts.size(), 0)


## A region that is not the Hearth's, and a tile of it with no building, for the image-only tests below.
func _other_region_tile(s: Settlement) -> Vector2i:
	var home := s.map.get_region(s.map.hearth_spot.x, s.map.hearth_spot.y)
	for r in MapState.REGION_COUNT:
		if r == home:
			continue
		var rect := MapState.region_rect(r)
		return rect.position + Vector2i(2, 2)
	return Vector2i(-1, -1)


# ticket 160 (1): an unowned region's pixel is dimmer than the same terrain once the region is owned.
func test_unowned_region_pixel_is_dimmed() -> void:
	var s := Settlement.new_game(SEED, reg)
	var t := _other_region_tile(s)
	var r := s.map.get_region(t.x, t.y)
	assert_false(s.map.is_region_owned(r), "a region the start does not own")
	s.map.set_terrain_id(t.x, t.y, "grass")
	var dim := Minimap.build_image(s).get_pixel(t.x, t.y)
	s.map.set_region_owned(r, true)
	var owned := Minimap.build_image(s).get_pixel(t.x, t.y)
	assert_eq(owned, Color("6a9a48"), "owned grass keeps its colour")
	var want := owned.darkened(Minimap.DIM)
	assert_almost_eq(dim.r, want.r, 0.01, "unowned grass is the same colour darkened (8-bit image)")
	assert_almost_eq(dim.g, want.g, 0.01)
	assert_almost_eq(dim.b, want.b, 0.01)
	assert_lt(dim.get_luminance(), owned.get_luminance(), "and so is dimmer")


# ticket 160 (2): a road tile draws the road colour (dirt and paved).
func test_road_tile_draws_the_road_colour() -> void:
	var s := Settlement.new_game(SEED, reg)
	var y := _empty_row(s)
	assert_true(y >= 0, "a row with no buildings")
	s.roads[MapState.idx(10, y)] = Settlement.ROAD_DIRT
	s.roads[MapState.idx(11, y)] = Settlement.ROAD_PAVED
	var img := Minimap.build_image(s)
	assert_eq(img.get_pixel(10, y), Minimap.ROAD, "a dirt road")
	assert_eq(img.get_pixel(11, y), Minimap.PAVED, "a paved road")
	assert_ne(img.get_pixel(12, y), Minimap.ROAD, "its neighbour is plain ground")


# ticket 160 (3): with the Sky layer the image shows the island terrain and its buildings, not the ground.
func test_sky_layer_image_shows_island_and_its_buildings() -> void:
	var s := Settlement.new_game(SEED, reg)
	var hb: Building = s.hearth
	var land := Vector2i(40, 40)
	var spot := Vector2i(41, 40)
	s.sky_map.set_terrain_id(land.x, land.y, MapState.SKY_STONE)
	s.sky_map.set_terrain_id(spot.x, spot.y, MapState.SKY_STONE)
	var b := Building.new()
	b.id = 9001
	b.def = reg.get_building("woodcutter")
	b.origin = spot
	b.layer = Building.LAYER_SKY
	s.buildings[b.id] = b
	var sky := Minimap.build_image(s, Building.LAYER_SKY)
	assert_eq(sky.get_pixel(land.x, land.y), RegionMap.GROUND_COLORS["sky"], "island stone")
	assert_eq(sky.get_pixel(spot.x, spot.y), Minimap.BUILDING, "the sky building's footprint")
	assert_eq(sky.get_pixel(land.x + 5, land.y), Minimap.VOID, "empty air beyond the island")
	assert_ne(sky.get_pixel(hb.origin.x, hb.origin.y), Minimap.BUILDING, "the ground Hearth is not on the Sky image")
	var ground := Minimap.build_image(s)
	assert_ne(ground.get_pixel(spot.x, spot.y), Minimap.BUILDING, "and the sky building is not on the ground image")
