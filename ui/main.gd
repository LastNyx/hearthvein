extends Node
## Main scene: builds a new Settlement and runs it in real time.

func _ready() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var driver := SimDriver.new()
	driver.settlement = Settlement.new_game(randi(), reg)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(12, 8)
	layer.add_child(label)
	driver.label = label
	add_child(driver)
	add_child(layer)
