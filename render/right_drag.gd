class_name RightDrag
extends RefCounted
## Tells a right-button click from a right-button drag (D62, D63). Each node that cares owns one and feeds it every
## mouse event; nothing is consumed, so the order of the nodes' _unhandled_input does not matter.

const THRESHOLD := 6.0  # screen pixels of motion from the press before it counts as a drag (pan)

var down := false
var dragged := false
var _origin := Vector2.ZERO


## Feed an event. Returns true when it is a right-button release that was a plain click (no drag).
func feed(event: InputEvent) -> bool:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			down = true
			dragged = false
			_origin = mb.position
			return false
		var was_click := down and not dragged
		down = false
		dragged = false
		return was_click
	if event is InputEventMouseMotion and down and not dragged:
		dragged = (event as InputEventMouseMotion).position.distance_to(_origin) >= THRESHOLD
	return false
