extends Node
## Main scene: builds a new Settlement, draws its map, runs it in real time, and owns the pause/save menu.
##
## Everything that belongs to one Settlement is a direct child of Main named as before (MapView, DimmingTint, Camera,
## SimDriver, BuildController, Hud; tools/*_shot.gd look them up by name) and is tracked in `_world` so a swap can free
## exactly those. swap_settlement() is the one path that replaces the Settlement (a load): it
## detaches autosave, silences the old EventBus, frees those nodes and builds fresh ones for the new Settlement, so every
## view is bound to the new Settlement and its bus and draws it from scratch. The menu and SaveSlots outlive swaps.

var game_seed: int = -1
## Where saves go; tests set a temp dir before add_child.
var saves_dir: String = "user://saves"
var settlement: Settlement
var hud_model: HudModel
var registry: DataRegistry
var slots: SaveSlots
var menu: SaveMenu
var menu_model: SaveMenuModel
var _world: Array[Node] = []
var driver: SimDriver
var map_view: MapView
var placement: PlacementView
var walkers: WalkerView
var trains: TrainView
var airships: AirshipView
var overlay: OverlayView
var hud: Hud
var camera: CameraController


func _ready() -> void:
	registry = DataRegistry.new()
	registry.load_all()
	slots = SaveSlots.new(saves_dir)
	menu_model = SaveMenuModel.new(slots, registry, func() -> Settlement: return settlement)
	menu = SaveMenu.new()
	menu.name = "SaveMenu"
	add_child(menu)
	menu.setup(menu_model)
	menu.load_requested.connect(func(s: Settlement) -> void:
		menu.close()
		swap_settlement(s))
	_build_world(Settlement.new_game(game_seed if game_seed >= 0 else randi(), registry))
	slots.attach(settlement)


## Replaces the running Settlement with `s` (a loaded one) and re-binds every view to it.
func swap_settlement(s: Settlement) -> void:
	slots.detach()
	settlement.events.clear_subscribers()
	for n in _world:
		remove_child(n)  # out of the tree now so the new nodes' names are free
		n.queue_free()
	_world.clear()
	_build_world(s)
	slots.attach(s)


func _build_world(s: Settlement) -> void:
	settlement = s
	driver = SimDriver.new()
	driver.settlement = s
	map_view = MapView.new()
	map_view.name = "MapView"
	_add(map_view)
	map_view.setup(s.map)
	var view := map_view
	s.events.subscribe("blight_changed", func(e: Dictionary) -> void: view.refresh_state(e["data"]["tile"]))
	s.events.subscribe("fouled_changed", func(e: Dictionary) -> void: view.refresh_state(e["data"]["tile"]))
	s.events.subscribe("terrain_changed", func(e: Dictionary) -> void: view.refresh_tile(e["data"]["tile"]))
	# Dimming: darken the world (CanvasModulate does not touch the CanvasLayer HUD).
	var dim := CanvasModulate.new()
	dim.name = "DimmingTint"
	_add(dim)
	dim.color = Color(0.45, 0.48, 0.65) if DimmingSystem.is_active(s) else Color.WHITE
	s.events.subscribe("dimming_started", func(_e: Dictionary) -> void: dim.color = Color(0.45, 0.48, 0.65))
	s.events.subscribe("dimming_ended", func(_e: Dictionary) -> void: dim.color = Color.WHITE)
	placement = PlacementView.new()
	placement.name = "PlacementView"
	view.add_child(placement)
	placement.setup(s, view)
	walkers = WalkerView.new()
	walkers.name = "WalkerView"
	view.add_child(walkers)
	walkers.setup(s)
	trains = TrainView.new()
	trains.name = "TrainView"
	view.add_child(trains)
	trains.setup(s)
	airships = AirshipView.new()
	airships.name = "AirshipView"
	view.add_child(airships)
	airships.setup(s)
	var ghost := GhostView.new()
	ghost.name = "Ghost"
	ghost.visible = false
	view.add_child(ghost)
	camera = CameraController.new()
	camera.name = "Camera"
	_add(camera)
	camera.setup(Rect2(Vector2.ZERO, view.world_size()), view.hearth_world_pos())
	camera.make_current()
	var layer := CanvasLayer.new()
	_add(driver)
	var build := BuildController.new()
	build.name = "BuildController"
	_add(build)
	build.setup(s, ghost, layer)
	_add(layer)
	hud_model = HudModel.new(s)
	overlay = OverlayView.new()
	overlay.name = "OverlayView"
	view.add_child(overlay)
	overlay.setup(s, hud_model)
	hud = Hud.new()
	hud.name = "Hud"
	_add(hud)
	hud.setup(hud_model, build, camera, driver)


func _add(n: Node) -> void:
	add_child(n)
	_world.append(n)


## Esc opens the menu unless it still has something to cancel (build tool, selection, flyout) or the menu is open.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		if menu.is_open():
			menu.close()
			get_viewport().set_input_as_handled()
		elif not hud.has_cancelable():
			menu.open()
			get_viewport().set_input_as_handled()
