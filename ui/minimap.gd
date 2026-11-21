class_name Minimap
extends PanelContainer
## The bottom-left minimap (hud-rts-spec H7, ticket 127): the map as one image at 1 px per tile inside the ~150x130
## slot (nearest filtering), the camera view rectangle over it, and to the right the Ground/Sky toggle (the same state
## as Tab, hidden before the first island) with the overlay buttons for V G T H L.
##
## The image is rebuilt only on the Settlement's own change events (terrain, roads, buildings, regions, islands) and on
## a layer switch; the camera rectangle is redrawn every frame. A click or drag on the map moves the camera centre
## there, clamped to the camera's bounds like a pan.

signal jumped(world_pos: Vector2)

## Map image pixels per map tile. 128 x 96 fits the 150 x 130 slot at 1:1; a larger factor would blur the 1 px tiles.
const IMAGE_SCALE := 1
const MAP_SIZE := Vector2(MapState.WIDTH, MapState.HEIGHT) * IMAGE_SCALE
const TILE := ArtLibrary.TILE
## Building footprints use the mockup's home colour; roads use its road colours.
const BUILDING := Color("d67c48")
const ROAD := Color("aa8a62")
const PAVED := Color("c8b088")
## The sky layer's empty air (islands are drawn on it).
const VOID := Color("0b1020")
## How much an unbought region's terrain darkens.
const DIM := 0.55
## id, label: the overlay toggles right of the map, in the same order as the HUD. Each shows its key from
## Hud.OVERLAY_KEYS, the one table the input reads too (ticket 130b).
const TOGGLES := [["blight", "Blight"], ["roads", "Roads"], ["water", "Water"],
		["coverage", "Cover"], ["grid", "Grid"]]
## Settlement events that change what the image shows. Nothing else (a frame passing, the camera moving) rebuilds it.
const EVENTS := ["terrain_changed", "road_changed", "region_bought", "building_placed", "building_completed",
		"building_demolished", "building_upgraded", "island_raised", "island_removed"]

var hud: Hud
var model: HudModel
var camera: Camera2D
## The map image, 1 px per tile (a test and the panel read it).
var image: Image
## The map texture on screen, kept current through update() so no new texture is made per change.
var texture: ImageTexture
## How many times the image has been rebuilt (the per-frame test reads it).
var rebuilds: int = 0
var map_area: MapArea
var ground_button: Button
var sky_button: Button
var _toggles: Dictionary = {}  # overlay id -> Button
var _dragging := false


func setup(h: Hud, m: HudModel, cam: Camera2D) -> void:
	hud = h
	model = m
	camera = cam
	name = "Minimap"
	var sb := hud._style(Hud.PANEL_BG, Hud.PANEL_EDGE, 6, 2, 8)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 3)
	row.add_child(left)
	map_area = MapArea.new()
	map_area.panel = self
	map_area.custom_minimum_size = MAP_SIZE
	map_area.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_area.tooltip_text = "Click or drag to move the camera"
	left.add_child(map_area)
	var layers := HBoxContainer.new()
	layers.name = "LayerRow"
	layers.add_theme_constant_override("separation", 3)
	left.add_child(layers)
	ground_button = hud._compact_button(layers, "Ground")
	ground_button.name = "LayerGround"
	ground_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_button.tooltip_text = "Ground layer (Tab)"
	ground_button.pressed.connect(func() -> void: model.set_layer(Building.LAYER_GROUND))
	sky_button = hud._compact_button(layers, "Sky")
	sky_button.name = "LayerSky"
	sky_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sky_button.tooltip_text = "Sky islands (Tab)"
	sky_button.pressed.connect(func() -> void: model.set_layer(Building.LAYER_SKY))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(76, 0)
	row.add_child(col)
	for pair in TOGGLES:
		var key := OS.get_keycode_string(Hud.OVERLAY_KEYS[pair[0]])
		var b := hud._compact_button(col, "%s %s" % [key, pair[1]])
		b.name = "Overlay_" + str(pair[0])
		b.tooltip_text = "%s overlay (%s)" % [pair[1], key]
		b.pressed.connect(_on_overlay.bind(pair[0]))
		_toggles[pair[0]] = b
	for kind in EVENTS:
		model.s.events.subscribe(kind, func(_e: Dictionary) -> void: rebuild())
	model.layer_changed.connect(func(_layer: int) -> void: rebuild())
	rebuild()
	refresh_toggles()


## The map image for a layer: terrain, roads, building footprints, and (ground) unbought regions dimmed.
static func build_image(s: Settlement, layer: int = Building.LAYER_GROUND) -> Image:
	var img: Image
	if layer == Building.LAYER_SKY:
		img = Image.create(MapState.WIDTH, MapState.HEIGHT, false, Image.FORMAT_RGBA8)
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				img.set_pixel(x, y, void_color(s.sky_map.terrain_id_at(x, y)))
	else:
		img = RegionMap.minimap_image(s.map)
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if not s.map.is_region_owned(s.map.get_region(x, y)):
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(DIM))
	var roads: PackedByteArray = s.sky_roads if layer == Building.LAYER_SKY else s.roads
	for i in roads.size():
		if roads[i] != Settlement.ROAD_NONE:
			img.set_pixel(i % MapState.WIDTH, i / MapState.WIDTH, ROAD if roads[i] == Settlement.ROAD_DIRT else PAVED)
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.layer != layer:
			continue
		for dy in b.def.size.y:
			for dx in b.def.size.x:
				var t := b.origin + Vector2i(dx, dy)
				if MapState.in_bounds(t.x, t.y):
					img.set_pixel(t.x, t.y, BUILDING)
	return img


## A sky tile's colour: island stone reads as land, empty air as the dark beyond.
static func void_color(terrain_id: String) -> Color:
	return RegionMap.GROUND_COLORS["sky"] if terrain_id == MapState.SKY_STONE else VOID


## Minimap-local point (image pixels) -> world position, clamped to the map's edges.
static func point_to_world(p: Vector2) -> Vector2:
	return (p / IMAGE_SCALE).clamp(Vector2.ZERO, Vector2(MapState.WIDTH, MapState.HEIGHT)) * TILE


func rebuild() -> void:
	image = build_image(model.s, model.active_layer)
	rebuilds += 1
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	if map_area != null:
		map_area.queue_redraw()


## The camera's view on the map image, in image pixels, clipped to the image.
func camera_rect() -> Rect2:
	if camera == null:
		return Rect2()
	var vp := camera.get_viewport_rect().size
	var z := camera.zoom.x if camera.zoom.x > 0.0 else 1.0
	var tl := (camera.get_screen_center_position() - vp / (2.0 * z)) / TILE * IMAGE_SCALE
	var want := Rect2(tl, vp / z / TILE * IMAGE_SCALE)
	return want.intersection(Rect2(Vector2.ZERO, MAP_SIZE))


## Moves the camera centre to the world point under a minimap point, clamped like a pan.
func jump_to(local: Vector2) -> void:
	if camera == null:
		return
	var world := point_to_world(local)
	var bounds := Rect2(Vector2.ZERO, Vector2(MapState.WIDTH, MapState.HEIGHT) * TILE)
	if camera is CameraController:
		bounds = (camera as CameraController).bounds
	camera.position = CameraController.clamp_center(world, camera.zoom.x, camera.get_viewport_rect().size, bounds)
	jumped.emit(world)


func overlay_button(id: String) -> Button:
	return _toggles.get(id)


## Lights the overlay buttons from the model, and shows Ground/Sky only once there is an island (ticket 98 rule).
func refresh_toggles() -> void:
	if model == null or hud == null:
		return
	for id in _toggles:
		hud._style_button(_toggles[id], model.overlay_on(id))
	var show_layer := model.layer_tag_visible()
	ground_button.get_parent().visible = show_layer
	ground_button.visible = show_layer
	sky_button.visible = show_layer
	var sky := model.active_layer == Building.LAYER_SKY
	hud._style_button(ground_button, not sky)
	hud._style_button(sky_button, sky)


func _on_overlay(id: String) -> void:
	model.toggle_overlay(id)
	refresh_toggles()


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		if _dragging:
			jump_to((event as InputEventMouseButton).position)
		map_area.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		jump_to((event as InputEventMouseMotion).position)
		map_area.accept_event()


func _process(_delta: float) -> void:
	if map_area != null:
		map_area.queue_redraw()  # only the camera rectangle moves per frame; the image waits for an event


## The map itself: the image and the camera rectangle over it. Kept a child Control so the buttons to the right keep
## their own clicks; the panel owns the image and the jump.
class MapArea extends Control:
	var panel: Minimap

	func _draw() -> void:
		if panel == null or panel.texture == null:
			return
		draw_texture_rect(panel.texture, Rect2(Vector2.ZERO, Minimap.MAP_SIZE), false)
		var r := panel.camera_rect()
		if r.size.x > 0.0 and r.size.y > 0.0:
			draw_rect(r, Color(1, 1, 1, 0.9), false, 1.0)

	func _ready() -> void:
		gui_input.connect(func(event: InputEvent) -> void:
			if panel != null:
				panel._on_map_input(event))
