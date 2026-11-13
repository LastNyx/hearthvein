extends Node
## Main scene: builds a new Settlement, draws its map, runs it in real time.

func _ready() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var driver := SimDriver.new()
	driver.settlement = Settlement.new_game(randi(), reg)
	var view := MapView.new()
	view.name = "MapView"
	add_child(view)
	view.setup(driver.settlement.map)
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
	add_child(layer)
