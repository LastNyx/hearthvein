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
		assert_string_contains(b.text, pair[2], "the button carries its key")
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


# AC5: the old top-right Overlays button (and its menu) is gone.
func test_old_overlay_menu_button_is_gone() -> void:
	var main: Node = await _game()
	var texts: Array[String] = []
	_collect_buttons(main.get_node("Hud"), texts)
	assert_false(texts.has("Overlays"), "no button labelled Overlays in the HUD")
	assert_gt(texts.size(), 0)
