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


## Longest real frame the sim follows (ticket 157). A slow frame (a hitch, a window drag, a debugger stop) used to feed
## its whole length into the next step, so a heavy step made the next one heavier: a death spiral at x3. Now a long
## frame only slows the game down: at most MAX_FRAME_SECONDS x speed of game time passes per frame.
const MAX_FRAME_SECONDS := 0.25


func advance(delta: float) -> void:
	if settlement == null or speed == 0:
		return
	settlement.step_seconds(minf(delta, MAX_FRAME_SECONDS) * speed)


func set_speed(s: int) -> void:
	var old := speed
	speed = clampi(s, 0, 3)
	if speed > 0:
		_last_speed = speed
	if speed != old:
		speed_changed.emit(speed)


func toggle_pause() -> void:
	set_speed(_last_speed if speed == 0 else 0)


## The clock bar (ticket 113): "Day 3, 06:40", with the minutes from the progress inside the current hour.
func status_text() -> String:
	if settlement == null:
		return ""
	return HudModel.clock_bar_text(settlement.clock.day(), float(settlement.clock.hour()) + hour_fraction())


## "1x"/"2x"/"3x" or "paused": the era panel shows it beside the year and season.
func speed_text() -> String:
	return "paused" if speed == 0 else "%dx" % speed


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
