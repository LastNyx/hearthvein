extends Node
## Main scene: builds a new Settlement, draws its map, runs it in real time.

var game_seed: int = -1
var settlement: Settlement


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
	settlement.events.subscribe("terrain_changed", func(e: Dictionary) -> void: view.refresh_tile(e["data"]["tile"]))
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
	var label := Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	driver.label = label
	add_child(driver)
	var build := BuildController.new()
	build.name = "BuildController"
	add_child(build)
	build.setup(settlement, ghost, layer)
	add_child(layer)
