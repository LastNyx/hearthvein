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
## Sound (ticket 86): outlives swaps, re-bound to each Settlement.
var sound: SoundPlayer
## What quit_game() ends the program with; tests swap it so the test run survives.
var quit_fn: Callable = func() -> void: get_tree().quit()
var settlement: Settlement
var hud_model: HudModel
var registry: DataRegistry
var slots: SaveSlots
var menu: SaveMenu
var menu_model: SaveMenuModel
var end_screen: EndScreen
var help: HelpScreen
var title_screen: TitleScreen
var new_game_panel: NewGamePanel
var whats_new_panel: WhatsNewPanel
var update_panel: UpdatePanel
## Auto-update (ticket 94). `update_offer` is the newer release found, {} when none; the other vars are seams the tests swap.
var updater: UpdateCheck
var update_offer: Dictionary = {}
var update_url: String = ""
var install_kind: String = UpdateCheck.install_kind(OS.get_name(), OS.has_feature("editor"), OS.get_environment("APPIMAGE"))
var appimage_path: String = OS.get_environment("APPIMAGE")
var update_dir: String = "user://updates"
var open_fn: Callable = func(target: String) -> void: OS.shell_open(target)
var launch_fn: Callable = func(path: String) -> void: OS.create_process(path, [])
## The version shown on the title and compared for the What's new auto-open; blank = the project's. Tests set it.
var app_version: String = ""
var changelog_path: String = "res://CHANGELOG.md"
var _world: Array[Node] = []
var _title: Array[Node] = []
var _updating := false
var _pan: Tween
var driver: SimDriver
## The world CanvasModulate (ticket 107): night tint x Dimming colour, refreshed every frame from the clock.
var dim_tint: CanvasModulate
var map_view: MapView
var placement: PlacementView
var walkers: WalkerView
var trains: TrainView
var airships: AirshipView
## The night render (ticket 135): light pools, lit windows and kiln embers, in MapView.fx under the map tint.
var night: NightView
## The gloom overlay (ticket 149): dark stepped tiles under the night light, in MapView.fx.
var gloom: GloomView
## Vein surge sparkles (ticket 150): pixel crosses over the Lumen vein tiles after a Dimming.
var vein_surge: VeinSurgeView
## The gain popup (ticket 137): "+N" with the good's icon over a producer or a cleared tile.
var gain_popups: GainPopupView
var overlay: OverlayView
var hud: Hud
var camera: CameraController


func _ready() -> void:
	settings = GameSettings.new()
	settings.path = settings_path
	settings.load_file()
	settings.apply(get_window())
	if app_version == "":
		app_version = str(ProjectSettings.get_setting("application/config/version", ""))
	sound = SoundPlayer.new()
	sound.name = "SoundPlayer"
	add_child(sound)  # first, so every button built below clicks
	sound.setup(settings)
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
	help = HelpScreen.new()
	add_child(help)
	help.setup(registry, func() -> SimDriver: return driver if state == State.GAME else null)
	menu.help_requested.connect(func() -> void: help.open_page(help.current_page()))
	end_screen = EndScreen.new()
	end_screen.name = "EndScreen"
	add_child(end_screen)
	end_screen.setup(menu, slots, func() -> Settlement: return settlement)
	menu.load_requested.connect(func(_s: Settlement) -> void: end_screen.close())
	menu.main_menu_requested.connect(return_to_title)
	menu.quit_requested.connect(quit_game)
	end_screen.title_requested.connect(return_to_title)
	updater = UpdateCheck.new()
	updater.name = "UpdateCheck"
	add_child(updater)
	_build_title()
	if ChangelogText.auto_open(settings, app_version):
		open_whats_new()
	_start_update_check()


## Starts a fresh Settlement and enters GAME. Seed -1 is the tutorial seed (data) when `tutorial` is on, else `game_seed`,
## else a random one; endless is OR-ed with `endless_start`. A tutorial game marks the tutorial as done in the settings.
func start_new_game(new_seed: int = -1, endless: bool = false, tutorial: bool = false) -> void:
	var sd := new_seed
	if sd < 0:
		sd = registry.mapgen.tutorial_seed if tutorial else (game_seed if game_seed >= 0 else randi())
	if tutorial and not settings.tutorial_first_run_done:
		settings.tutorial_first_run_done = true
		settings.save()
	var s := Settlement.new_game(sd, registry, endless or endless_start, tutorial)
	s.clock.total_hours = Settlement.PLAYER_START_HOUR  # open in daylight (day and night, 1.1.6)
	swap_settlement(s)


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


## The title's What's new button: CHANGELOG.md in a scrollable panel over the title (Back or Esc closes it). The
## Unreleased section is left out of exported builds when the changelog has a section for this version.
func open_whats_new() -> void:
	if whats_new_panel != null or state != State.TITLE:
		return
	var md := FileAccess.get_file_as_string(changelog_path)
	var hide := ChangelogText.hide_unreleased(md, app_version, OS.has_feature("editor"))
	whats_new_panel = WhatsNewPanel.new()
	whats_new_panel.name = "WhatsNewPanel"
	_add_title(whats_new_panel)
	whats_new_panel.setup(ChangelogText.to_bbcode(ChangelogText.drop_preamble(md), hide))
	whats_new_panel.back_pressed.connect(close_whats_new)


func close_whats_new() -> void:
	if whats_new_panel == null:
		return
	_title.erase(whats_new_panel)
	remove_child(whats_new_panel)
	whats_new_panel.queue_free()
	whats_new_panel = null


## Once on every launch, toggle permitting; never in a headless run (tests) unless HV_UPDATE_URL points
## somewhere (then it always asks: the override is for local checks).
func _start_update_check() -> void:
	var override := OS.get_environment("HV_UPDATE_URL")
	if update_url == "":
		update_url = override if override != "" else UpdateCheck.API_URL
	if override == "" and DisplayServer.get_name() == "headless":
		return
	var now := int(Time.get_unix_time_from_system())
	if not settings.check_updates or (override == "" and not UpdateCheck.should_check(settings, now)):
		return
	updater.check_done.connect(func(offer: Dictionary) -> void:
		settings.update_last_check = now
		settings.save()
		show_update_offer(offer), CONNECT_ONE_SHOT)
	updater.check(update_url, app_version, install_kind)


## An offer from a check: the title gets its button unless the player skipped that version.
func show_update_offer(offer: Dictionary) -> void:
	if UpdateCheck.is_skipped(offer, settings):
		offer = {}
	update_offer = offer
	if title_screen != null:
		if offer.is_empty():
			title_screen.hide_update()
		else:
			title_screen.show_update(str(offer["version"]))


func open_update_panel() -> void:
	if update_panel != null or state != State.TITLE or update_offer.is_empty():
		return
	update_panel = UpdatePanel.new()
	update_panel.name = "UpdatePanel"
	_add_title(update_panel)
	update_panel.setup(update_offer)
	update_panel.later_pressed.connect(close_update_panel)
	update_panel.skip_pressed.connect(skip_update)
	update_panel.page_pressed.connect(open_update_page)
	update_panel.primary_pressed.connect(start_update_download)


func close_update_panel() -> void:
	if update_panel == null or _updating:
		return
	_title.erase(update_panel)
	remove_child(update_panel)
	update_panel.queue_free()
	update_panel = null


func skip_update() -> void:
	if update_offer.is_empty():
		return
	settings.update_skipped_version = str(update_offer["version"])
	settings.save()
	close_update_panel()
	show_update_offer(update_offer)


func open_update_page() -> void:
	var url := str(update_offer.get("html_url", ""))
	if url != "":
		open_fn.call(url)


## The panel's install button: downloads the asset (Windows: user://updates/, AppImage: beside the old one as .new),
## then installs. Any failure shows in the panel with a download page button; the partial file is gone.
func start_update_download() -> void:
	if _updating or update_panel == null or not bool(update_offer.get("downloadable", false)):
		return
	var dest := ""
	if install_kind == "appimage":
		dest = appimage_path + ".new"
	else:
		DirAccess.make_dir_recursive_absolute(update_dir)
		dest = ProjectSettings.globalize_path(update_dir).path_join(str(update_offer["asset_name"]))
	_updating = true
	update_panel.set_busy(true)
	updater.progress.connect(update_panel.set_progress)
	updater.download_done.connect(_on_update_downloaded.bind(dest), CONNECT_ONE_SHOT)
	updater.download(str(update_offer["asset_url"]), dest, int(update_offer["asset_size"]), str(update_offer["asset_digest"]))


func _on_update_downloaded(err: String, dest: String) -> void:
	if update_panel != null and updater.progress.is_connected(update_panel.set_progress):
		updater.progress.disconnect(update_panel.set_progress)
	if err == "" and install_kind == "appimage":
		err = UpdateCheck.replace_file(dest, appimage_path)
	if err != "":
		_updating = false
		if update_panel != null:
			update_panel.set_busy(false)
			update_panel.set_message(err, true)
		return
	if install_kind == "appimage":
		launch_fn.call(appimage_path)
	else:
		open_fn.call(dest)
	quit_game()


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
	menu.close()
	end_screen.close()
	_free_world()
	_build_title()


## The pause menu's Quit: autosaves a running game, then ends the program (quit_fn is replaced in tests).
func quit_game() -> void:
	if state == State.GAME:
		slots.autosave(settlement)
	quit_fn.call()


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
	dim_tint = null
	map_view = null
	placement = null
	walkers = null
	trains = null
	airships = null
	night = null
	gain_popups = null
	overlay = null
	help.close()
	hud = null
	hud_model = null
	camera = null
	get_tree().paused = false


func _build_title() -> void:
	state = State.TITLE
	sound.set_title()
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
	# The pan ends are worked out from the view size at boot; a bigger or maximised window later would look past the
	# map's edge (empty strip on the left). Limits keep the view on the map at any window size.
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(size.x)
	cam.limit_bottom = int(size.y)
	var y := randf_range(half.y, maxf(half.y, size.y - half.y))
	cam.position = Vector2(half.x, y)
	_pan = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pan.tween_property(cam, "position", Vector2(maxf(half.x, size.x - half.x), y), 120.0)
	_pan.tween_property(cam, "position", Vector2(half.x, y), 120.0)
	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	_add_title(title_screen)
	title_screen.setup(not menu_model.newest_save().is_empty(), app_version)
	title_screen.continue_pressed.connect(func() -> void:
		var s := menu_model.continue_newest()
		if s != null:
			swap_settlement(s))
	title_screen.new_game_pressed.connect(open_new_game_panel)
	title_screen.load_pressed.connect(menu.open_view.bind("load"))
	title_screen.milestones_pressed.connect(menu.open_view.bind("milestones"))
	title_screen.whats_new_pressed.connect(open_whats_new)
	title_screen.update_pressed.connect(open_update_panel)
	if not update_offer.is_empty():
		title_screen.show_update(str(update_offer["version"]))
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
	whats_new_panel = null
	update_panel = null
	map_view = null


func _build_world(s: Settlement) -> void:
	settlement = s
	sound.bind(s)
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
	# Regrowing stumps show a sapling from half way (ticket 111): render-only, redrawn when a season starts.
	var forest := s.get_system(ForestSystem) as ForestSystem
	view.stump_progress = func(t: Vector2i) -> float: return forest.regrow_progress(s, t)
	s.events.subscribe("season_started", func(_e: Dictionary) -> void: view.refresh_stumps())
	view.refresh_stumps()
	for kind in ["island_raised", "island_removed"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void: _refresh_sky())
	_refresh_sky()
	# End screens: once per outcome, on the event only (a loaded save with an outcome already set stays closed).
	for kind in ["campaign_won", "campaign_no_win", "campaign_lost"]:
		s.events.subscribe(kind, func(_e: Dictionary) -> void:
			end_screen.show_outcome(kind.trim_prefix("campaign_"), s))
	# Day and night x Dimming: darken the world (CanvasModulate does not touch the CanvasLayer HUD). Refreshed every
	# frame in _process so the dusk and dawn blends move with the hour fraction; paused, the sim holds and so does it.
	var dim := CanvasModulate.new()
	dim.name = "DimmingTint"
	_add(dim)
	dim_tint = dim
	_update_tint()
	placement = PlacementView.new()
	placement.name = "PlacementView"
	view.add_child(placement)
	placement.setup(s, view)
	night = NightView.new()
	night.name = "NightView"
	view.fx.add_child(night)
	night.setup(s)
	gloom = GloomView.new()
	gloom.name = "GloomView"
	gloom.z_index = 4  # under the additive light pools (NightView, 5)
	view.fx.add_child(gloom)
	gloom.setup(s)
	vein_surge = VeinSurgeView.new()
	vein_surge.name = "VeinSurgeView"
	vein_surge.z_index = 3  # over the ground, under the gloom (4) and the light pools (5)
	view.fx.add_child(vein_surge)
	vein_surge.setup(s, s.map)
	gain_popups = GainPopupView.new()
	gain_popups.name = "GainPopupView"
	view.fx.add_child(gain_popups)
	gain_popups.setup(s, settings)
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
	camera.explored.connect(s.report_camera_moved)
	var layer := CanvasLayer.new()
	_add(driver)
	var build := BuildController.new()
	build.name = "BuildController"
	_add(build)
	build.setup(s, ghost, layer)
	_add(layer)
	hud_model = HudModel.new(s, settings)
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
	hud.minimap.jumped.connect(func(_world: Vector2) -> void: s.report_camera_moved())  # the player moved the camera
	hud.add_cards(settings)
	hud.hint_cards.help_page_requested.connect(help.open_page)
	hud.help_requested.connect(help.toggle)


## The map tint: the day and night colour (from DayNightDef) times the Dimming colour, or plain Dimming when the
## player turned day and night off. Cheap, so it runs every frame.
func _update_tint() -> void:
	if dim_tint == null or settlement == null or registry == null:
		return
	var hours_f := float(settlement.clock.hour())
	if driver != null:
		hours_f += driver.hour_fraction()
	dim_tint.color = DayNight.map_tint(hours_f, registry.day_night, DimmingSystem.is_active(settlement),
			settings == null or settings.day_night)


func _process(_delta: float) -> void:
	_update_tint()


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
		if help.is_open():
			help.close()
			get_viewport().set_input_as_handled()
		elif menu.is_open():
			menu.close()
			get_viewport().set_input_as_handled()
		elif update_panel != null:
			close_update_panel()
			get_viewport().set_input_as_handled()
		elif whats_new_panel != null:
			close_whats_new()
			get_viewport().set_input_as_handled()
		elif new_game_panel != null:
			close_new_game_panel()
			get_viewport().set_input_as_handled()
		elif state == State.GAME and not hud.has_cancelable():
			menu.open()
			get_viewport().set_input_as_handled()
