extends GutTest
## The title backdrop pan must never look past the map edge, whatever the window size (Ben, 21 Nov: empty strip on
## the left of the main menu map).

var dir: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_title_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	DirAccess.remove_absolute(dir + ".cfg")
	DirAccess.remove_absolute(dir)


func test_backdrop_camera_is_limited_to_the_map() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = dir + ".cfg"
	add_child_autofree(main)
	await wait_process_frames(2)
	var cam := main.get_node("Camera") as Camera2D
	var size: Vector2 = main.map_view.world_size()
	assert_eq(cam.limit_left, 0)
	assert_eq(cam.limit_top, 0)
	assert_eq(cam.limit_right, int(size.x))
	assert_eq(cam.limit_bottom, int(size.y))
