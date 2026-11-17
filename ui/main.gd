extends Node
## Main scene: builds a new Settlement, draws its map, runs it in real time, and owns the pause/save menu.
##
## Everything that belongs to one Settlement is a direct child of Main named as before (MapView, DimmingTint, Camera,
## SimDriver, BuildController, Hud; tools/*_shot.gd look them up by name) and is tracked in `_world` so a swap can free
## exactly those. Main has two states (ticket 77): TITLE (boot: a backdrop MapView of a fresh random map under a slow
## camera pan, plus TitleScreen; no Settlement, SimDriver or Hud, so nothing ticks) and GAME (the world above).
## start_new_game() and swap_settlement() enter GAME, return_to_title() autosaves and goes back. swap_settlement() is the one path that replaces the Settlement (a load): it
## detaches autosave, silences the old EventBus, frees those nodes and builds fresh ones for the new Settlement, so every
## view is bound to the new Settlement and its bus and draws it from scratch. The menu and SaveSlots outlive swaps.

enum State { TITLE, GAME }

var state: State = State.TITLE
## Default seed for start_new_game() when it is not given one (tests and shot scripts set it; -1 = random).
var game_seed: int = -1
## Default for start_new_game()'s endless option: no win check, no Great Dimming (ticket 46).
var endless_start: bool = false
## Where saves go; tests set a temp dir before add_child.
var saves_dir: String = "user://saves"
## Lifetime milestone list (ticket 46b), outside the saves.
var milestones_path: String = "user://milestones.json"
## User settings (ticket 76); tests set a temp path before add_child. Loaded and applied in _ready, before the world.
var settings_path: String = "user://settings.cfg"
var settings: GameSettings
var settlement: Settlement
var hud_model: HudModel
var registry: DataRegistry
var slots: SaveSlots
var menu: SaveMenu
var menu_model: SaveMenuModel
var end_screen: EndScreen
var title_screen: TitleScreen
var new_game_panel: NewGamePanel
var _world: Array[Node] = []
var _title: Array[Node] = []
var _pan: Tween
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
	settings = GameSettings.new()
	settings.path = settings_path
	settings.load_file()
	settings.apply(get_window())
	registry = DataRegistry.new()
	registry.load_all()
	MilestoneSystem.lifetime_path = milestones_path
	slots = SaveSlots.new(saves_dir)
	menu_model = SaveMenuModel.new(slots, registry, func() -> Settlement: return settlement)
	menu = SaveMenu.new()
	menu.name = "SaveMenu"
	add_child(menu)
	menu.setup(menu_model, settings)
	menu.load_requested.connect(func(s: Settlement) -> void:
		menu.close()
		swap_settlement(s))
	end_screen = EndScreen.new()
	end_screen.name = "EndScreen"
	add_child(end_screen)
	end_screen.setup(menu, slots, func() -> Settlement: return settlement)
	menu.load_requested.connect(func(_s: Settlement) -> void: end_screen.close())
	_build_title()


## Starts a fresh Settlement and enters GAME. Seed -1 is the tutorial seed (data) when `tutorial` is on, else `game_seed`,
## else a random one; endless is OR-ed with `endless_start`. A tutorial game marks the tutorial as done in the settings.
func start_new_game(new_seed: int = -1, endless: bool = false, tutorial: bool = false) -> void:
	var sd := new_seed
	if sd < 0:
		sd = registry.mapgen.tutorial_seed if tutorial else (game_seed if game_seed >= 0 else randi())
	if tutorial and not settings.tutorial_first_run_done:
		settings.tutorial_first_run_done = true
		settings.save()
	swap_settlement(Settlement.new_game(sd, registry, endless or endless_start, tutorial))


## The title's New game button: the options panel over the title (Back closes it, Start begins the game).
func open_new_game_panel() -> void:
	if new_game_panel != null or state != State.TITLE:
		return
	new_game_panel = NewGamePanel.new()
	new_game_panel.name = "NewGamePanel"
	_add_title(new_game_panel)
	new_game_panel.setup(settings.tutorial_first_run_done)
	new_game_panel.back_pressed.connect(close_new_game_panel)
	new_game_panel.start_pressed.connect(start_new_game)


func close_new_game_panel() -> void:
	if new_game_panel == null:
		return
	_title.erase(new_game_panel)
	remove_child(new_game_panel)
	new_game_panel.queue_free()
	new_game_panel = null


## Replaces whatever is showing (the title, or the running Settlement) with `s` and re-binds every view to it.
func swap_settlement(s: Settlement) -> void:
	_free_title()
	_free_world()
	_build_world(s)
	slots.attach(s)
	state = State.GAME


## GAME to TITLE: autosaves, detaches, frees the world nodes and rebuilds the backdrop and title screen.
func return_to_title() -> void:
	if state != State.GAME:
		return
	slots.autosave(settlement)
	_free_world()
	_build_title()


func _free_world() -> void:
	if settlement == null:
		return
	slots.detach()
	settlement.events.clear_subscribers()
	for n in _world:
		remove_child(n)  # out of the tree now so the new nodes' names are free
		n.queue_free()
	_world.clear()
	settlement = null
	driver = null
	map_view = null
	placement = null
	walkers = null
	trains = null
	airships = null
	overlay = null
	hud = null
	hud_model = null
	camera = null
	get_tree().paused = false


func _build_title() -> void:
	state = State.TITLE
	map_view = MapView.new()
	map_view.name = "MapView"
	_add_title(map_view)
	map_view.show_regions = false
	map_view.setup(MapGen.generate(randi(), registry))
	var cam := Camera2D.new()
	cam.name = "Camera"
	_add_title(cam)
	cam.make_current()
	var half := get_viewport().get_visible_rect().size * 0.5
	var size := map_view.world_size()
	var y := randf_range(half.y, maxf(half.y, size.y - half.y))
	cam.position = Vector2(half.x, y)
	_pan = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pan.tween_property(cam, "position", Vector2(maxf(half.x, size.x - half.x), y), 120.0)
	_pan.tween_property(cam, "position", Vector2(half.x, y), 120.0)
	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	_add_title(title_screen)
	title_screen.setup(not menu_model.newest_save().is_empty())
	title_screen.continue_pressed.connect(func() -> void:
		var s := menu_model.continue_newest()
		if s != null:
			swap_settlement(s))
	title_screen.new_game_pressed.connect(open_new_game_panel)
	title_screen.load_pressed.connect(menu.open_view.bind("load"))
	title_screen.milestones_pressed.connect(menu.open_view.bind("milestones"))
	title_screen.settings_pressed.connect(menu.open_view.bind("settings"))
	title_screen.quit_pressed.connect(func() -> void: get_tree().quit())


func _add_title(n: Node) -> void:
	add_child(n)
	_title.append(n)


func _free_title() -> void:
	if _pan != null:
		_pan.kill()
		_pan = null
	for n in _title:
		remove_child(n)
		n.queue_free()
	_title.clear()
	title_screen = null
	new_game_panel = null
	map_view = null


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
	for kind in ["island_raised", "island_removed"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void: _refresh_sky())
	_refresh_sky()
	# End screens: once per outcome, on the event only (a loaded save with an outcome already set stays closed).
	for kind in ["campaign_won", "campaign_no_win", "campaign_lost"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void:
			end_screen.show_outcome(kind.trim_prefix("campaign_"), s))
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
	ghost.z_index = 40  # above the sky layer and its walkers
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
	build.model = hud_model
	overlay = OverlayView.new()
	overlay.name = "OverlayView"
	view.add_child(overlay)
	overlay.setup(s, hud_model)
	hud_model.layer_changed.connect(func(layer: int) -> void:
		view.set_active_layer(layer)
		overlay.z_index = 35 if layer == Building.LAYER_SKY else 15)  # the selection outline stays over the islands
	hud = Hud.new()
	hud.name = "Hud"
	_add(hud)
	hud.setup(hud_model, build, camera, driver)


## Repaint the islands on the sky layer from the sim (raised and removed islands).
func _refresh_sky() -> void:
	var isys := settlement.get_system(IslandSystem) as IslandSystem
	var rects: Array[Rect2i] = []
	if isys != null:
		for isl in isys.islands:
			rects.append(isl.rect)
	map_view.refresh_sky(settlement.sky_map, rects)


func _add(n: Node) -> void:
	add_child(n)
	_world.append(n)


## Esc opens the menu unless it still has something to cancel (build tool, selection, flyout) or the menu is open.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		if menu.is_open():
			menu.close()
			get_viewport().set_input_as_handled()
		elif new_game_panel != null:
			close_new_game_panel()
			get_viewport().set_input_as_handled()
		elif state == State.GAME and not hud.has_cancelable():
			menu.open()
			get_viewport().set_input_as_handled()
