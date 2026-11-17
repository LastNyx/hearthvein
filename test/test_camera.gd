extends GutTest

const B := Rect2(0, 0, 4096, 3072)
const VP := Vector2(1280, 720)


func test_exactly_four_zoom_steps() -> void:
	assert_eq(CameraController.ZOOM_STEPS.size(), 4)
	assert_eq(CameraController.ZOOM_STEPS, [0.25, 0.5, 1.0, 2.0] as Array[float])


func test_step_index_clamps_at_both_ends() -> void:
	assert_eq(CameraController.step_index(2, 1), 3)
	assert_eq(CameraController.step_index(3, 1), 3)
	assert_eq(CameraController.step_index(0, -1), 0)
	assert_eq(CameraController.step_index(1, -5), 0)


func test_pan_clamps_to_map_bounds() -> void:
	var p := CameraController.clamp_center(Vector2(-500, -500), 1.0, VP, B)
	assert_eq(p, Vector2(640, 360))
	p = CameraController.clamp_center(Vector2(99999, 99999), 1.0, VP, B)
	assert_eq(p, Vector2(4096 - 640, 3072 - 360))
	p = CameraController.clamp_center(Vector2(2000, 1500), 1.0, VP, B)
	assert_eq(p, Vector2(2000, 1500))


func test_clamp_depends_on_zoom() -> void:
	var p := CameraController.clamp_center(Vector2(0, 0), 2.0, VP, B)
	assert_eq(p, Vector2(320, 180))


func test_view_larger_than_map_centres() -> void:
	var p := CameraController.clamp_center(Vector2(10, 10), 0.25, VP, B)
	assert_eq(p.x, 2048.0)  # 5120 px wide view > 4096 map
	assert_eq(p.y, 1440.0)  # 2880 < 3072, so y still clamps


func test_pan_moves_opposite_to_drag_scaled_by_zoom() -> void:
	assert_eq(CameraController.panned(Vector2(100, 100), Vector2(20, 0), 2.0), Vector2(90, 100))


func _btn(button: int, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	return e


func _move(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	return e


func _camera() -> CameraController:
	var c := CameraController.new()
	add_child_autofree(c)
	c.setup(B, Vector2(2000, 1500))
	return c


func test_right_drag_pans_and_middle_drag_still_pans() -> void:
	var c := _camera()
	c._unhandled_input(_btn(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)))
	c._unhandled_input(_move(Vector2(103, 100), Vector2(3, 0)))
	assert_eq(c.position, Vector2(2000, 1500), "under 6 px does not pan")
	c._unhandled_input(_move(Vector2(110, 100), Vector2(7, 0)))
	assert_eq(c.position, Vector2(1993, 1500), "past 6 px pans")
	c._unhandled_input(_btn(MOUSE_BUTTON_RIGHT, false, Vector2(110, 100)))
	c._unhandled_input(_move(Vector2(130, 100), Vector2(20, 0)))
	assert_eq(c.position, Vector2(1993, 1500), "no pan after release")
	c._unhandled_input(_btn(MOUSE_BUTTON_MIDDLE, true, Vector2(130, 100)))
	c._unhandled_input(_move(Vector2(140, 100), Vector2(10, 0)))
	assert_eq(c.position, Vector2(1983, 1500), "middle drag pans")


func _build_controller() -> BuildController:
	var reg := DataRegistry.new()
	reg.load_all()
	var s := Settlement.new_game(42, reg)
	var c := BuildController.new()
	add_child_autofree(c)
	var ghost := GhostView.new()
	add_child_autofree(ghost)
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	c.setup(s, ghost, layer)
	c.set_mode(BuildController.Mode.ROAD)
	return c


func test_right_click_cancels_build_mode_on_release() -> void:
	var c := _build_controller()
	c._unhandled_input(_btn(MOUSE_BUTTON_RIGHT, true, Vector2(50, 50)))
	assert_eq(c.mode, BuildController.Mode.ROAD, "press alone does not cancel")
	c._unhandled_input(_btn(MOUSE_BUTTON_RIGHT, false, Vector2(52, 50)))
	assert_eq(c.mode, BuildController.Mode.NONE)


func test_right_drag_keeps_build_mode() -> void:
	var c := _build_controller()
	c._unhandled_input(_btn(MOUSE_BUTTON_RIGHT, true, Vector2(50, 50)))
	c._unhandled_input(_move(Vector2(80, 50), Vector2(30, 0)))
	c._unhandled_input(_btn(MOUSE_BUTTON_RIGHT, false, Vector2(80, 50)))
	assert_eq(c.mode, BuildController.Mode.ROAD)
