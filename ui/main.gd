extends Node
## Main scene: builds a new Settlement, draws its map, runs it in real time.

var game_seed: int = -1
var settlement: Settlement
var hud_model: HudModel


func _ready() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var driver := SimDriver.new()
	driver.settlement = Settlement.new_game(game_seed if game_seed >= 0 else randi(), reg)
	settlement = driver.settlement
	var view := MapView.new()
	view.name = "MapView"
	add_child(view)
	view.setup(driver.settlement.map)
	settlement.events.subscribe("blight_changed", func(e: Dictionary) -> void: view.refresh_state(e["data"]["tile"]))
	settlement.events.subscribe("terrain_changed", func(e: Dictionary) -> void: view.refresh_tile(e["data"]["tile"]))
	# Dimming: darken the world (CanvasModulate does not touch the CanvasLayer HUD).
	var dim := CanvasModulate.new()
	dim.name = "DimmingTint"
	add_child(dim)
	settlement.events.subscribe("dimming_started", func(_e: Dictionary) -> void: dim.color = Color(0.45, 0.48, 0.65))
	settlement.events.subscribe("dimming_ended", func(_e: Dictionary) -> void: dim.color = Color.WHITE)
	var placed := PlacementView.new()
	placed.name = "PlacementView"
	view.add_child(placed)
	placed.setup(settlement, view)
	var walkers := WalkerView.new()
	walkers.name = "WalkerView"
	view.add_child(walkers)
	walkers.setup(settlement)
	var ghost := GhostView.new()
	ghost.name = "Ghost"
	ghost.visible = false
	view.add_child(ghost)
	var cam := CameraController.new()
	cam.name = "Camera"
	add_child(cam)
	cam.setup(Rect2(Vector2.ZERO, view.world_size()), view.hearth_world_pos())
	cam.make_current()
	var layer := CanvasLayer.new()
	add_child(driver)
	var build := BuildController.new()
	build.name = "BuildController"
	add_child(build)
	build.setup(settlement, ghost, layer)
	add_child(layer)
	var model := HudModel.new(settlement)
	var overlay := OverlayView.new()
	overlay.name = "OverlayView"
	view.add_child(overlay)
	overlay.setup(settlement, model)
	var hud := Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(model, build, cam, driver)
	hud_model = model
