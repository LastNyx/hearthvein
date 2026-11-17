class_name SimDriver
extends Node
## Real-time driver: feeds real seconds x speed to Settlement.step_seconds.
## Space toggles pause, 1/2/3 set speed. Optional Label shows the clock.

const SPEEDS: Array[int] = [0, 1, 2, 3]

var settlement: Settlement
var speed: int = 1
var label: Label
var _last_speed: int = 1


func advance(delta: float) -> void:
	if settlement == null or speed == 0:
		return
	settlement.step_seconds(delta * speed)


func set_speed(s: int) -> void:
	speed = clampi(s, 0, 3)
	if speed > 0:
		_last_speed = speed


func toggle_pause() -> void:
	if speed == 0:
		speed = _last_speed
	else:
		speed = 0


func status_text() -> String:
	var sp := "paused" if speed == 0 else "%dx" % speed
	return "%s, %s" % [settlement.clock.label(), sp]


func _process(delta: float) -> void:
	advance(delta)
	if label != null and settlement != null:
		label.text = status_text()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: toggle_pause()
			KEY_1: set_speed(1)
			KEY_2: set_speed(2)
			KEY_3: set_speed(3)
