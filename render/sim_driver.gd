class_name SimDriver
extends Node
## Real-time driver: feeds real seconds x speed to Settlement.step_seconds.
## Space toggles pause, 1/2/3 set speed. Optional Label shows the clock.

## Emitted whenever the speed changes, however it was set (keys, buttons, era card, help screen).
signal speed_changed(speed: int)

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
	var old := speed
	speed = clampi(s, 0, 3)
	if speed > 0:
		_last_speed = speed
	if speed != old:
		speed_changed.emit(speed)


func toggle_pause() -> void:
	set_speed(_last_speed if speed == 0 else 0)


func status_text() -> String:
	var sp := "paused" if speed == 0 else "%dx" % speed
	return "%s, %s" % [settlement.clock.label(), sp]


## Fraction of the current hour already simulated, 0..1 (render-side only: the clock bar and the day and night tint).
## Holds while paused, because the sim does not move.
func hour_fraction() -> float:
	return settlement.hour_fraction() if settlement != null else 0.0


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
