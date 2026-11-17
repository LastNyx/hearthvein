class_name CameraController
extends Camera2D
## Wheel zoom in exactly 4 steps, middle-drag and WASD pan, clamped to the map. Pure maths is static.

const ZOOM_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0]
const START_STEP := 2
const PAN_SPEED := 900.0  # screen pixels per second

var bounds: Rect2 = Rect2(0, 0, 4096, 3072)
var zoom_step: int = START_STEP
var _dragging := false
var _right := RightDrag.new()


## True at the farthest zoom step (D46: walkers and prop shadows are not drawn there).
static func is_farthest_zoom(zoom_value: float) -> bool:
	return zoom_value <= ZOOM_STEPS[0] + 0.0001


## Next zoom step index after a wheel notch (dir > 0 zooms in), clamped to the valid range.
static func step_index(current: int, dir: int) -> int:
	return clampi(current + signi(dir), 0, ZOOM_STEPS.size() - 1)


## Clamp a camera centre so the view stays inside bounds. If the view is larger than the bounds on an axis,
## the camera centres on the bounds on that axis.
static func clamp_center(pos: Vector2, zoom_value: float, viewport_size: Vector2, b: Rect2) -> Vector2:
	var half := viewport_size / (2.0 * zoom_value)
	var out := pos
	if half.x * 2.0 >= b.size.x:
		out.x = b.position.x + b.size.x * 0.5
	else:
		out.x = clampf(pos.x, b.position.x + half.x, b.end.x - half.x)
	if half.y * 2.0 >= b.size.y:
		out.y = b.position.y + b.size.y * 0.5
	else:
		out.y = clampf(pos.y, b.position.y + half.y, b.end.y - half.y)
	return out


## Camera centre after a pan of `screen_delta` screen pixels (content follows the cursor when dragging).
static func panned(pos: Vector2, screen_delta: Vector2, zoom_value: float) -> Vector2:
	return pos - screen_delta / zoom_value


func setup(world_bounds: Rect2, start_pos: Vector2) -> void:
	bounds = world_bounds
	_apply_zoom(START_STEP)
	position = _clamped(start_pos)


func set_zoom_step(i: int) -> void:
	_apply_zoom(i)
	position = _clamped(position)


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


func _clamped(p: Vector2) -> Vector2:
	return clamp_center(p, ZOOM_STEPS[zoom_step], _viewport_size(), bounds)


func _apply_zoom(i: int) -> void:
	zoom_step = clampi(i, 0, ZOOM_STEPS.size() - 1)
	var z := ZOOM_STEPS[zoom_step]
	zoom = Vector2(z, z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_step(step_index(zoom_step, 1))
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_step(step_index(zoom_step, -1))
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	_right.feed(event)
	if event is InputEventMouseMotion and (_dragging or _right.dragged):
		position = _clamped(panned(position, (event as InputEventMouseMotion).relative, zoom.x))


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): dir.y += 1
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	if dir != Vector2.ZERO:
		position = _clamped(position + dir.normalized() * PAN_SPEED * delta / zoom.x)
