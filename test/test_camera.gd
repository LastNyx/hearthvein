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
