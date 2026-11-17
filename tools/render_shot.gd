extends SceneTree
## Windowed screenshot helper: godot --path . -s tools/render_shot.gd
## Saves /tmp/hv_render_zoom<N>.png for each zoom step N (0..3).

func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var cam: CameraController = main.get_node("Camera")
	for i in CameraController.ZOOM_STEPS.size():
		cam.set_zoom_step(i)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/hv_render_zoom%d.png" % i)
	quit()
