extends SceneTree
## Windowed paved road shots: godot --path . -s tools/paved_shot.gd [-- seed]
## Ticket 30d: a Town-era settlement with a dirt road that turns into a paved stretch: a dirt/paved seam, a paved
## T junction, a paved cross, and a dirt branch meeting paved. Writes /tmp/hv_paved.png (map) and
## /tmp/hv_paved_bar.png (build bar with the Roads flyout open, showing the Paved road entry).


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for r in MapState.REGION_COUNT:
		s.map.region_owned[r] = 1
	s.era_override = "town"
	var hud: Hud = main.get_node("Hud")
	hud._rebuild_categories()
	var y := h.y + 3
	# Dirt road west to east along y, paved from x0 on; the seam is at x0.
	var x0 := h.x - 1
	for x in range(h.x - 12, h.x + 14):
		s.place_road(Vector2i(x, y))
	# Dirt branch going north that meets the road (stays dirt), and a paved T going south at x0 + 4.
	for k in range(1, 5):
		s.place_road(Vector2i(h.x - 7, y - k))
	for k in range(1, 5):
		s.place_road(Vector2i(x0 + 4, y + k))
	# Paved cross at x0 + 9 with arms north and south.
	for k in range(-3, 4):
		s.place_road(Vector2i(x0 + 9, y + k))
	s.hearth.inventory.add("materials", 500.0)
	s.hearth.inventory.add("cut_stone", 50.0)
	var paved := 0
	for x in range(x0, h.x + 14):
		if s.pave_road(Vector2i(x, y)):
			paved += 1
	for k in range(1, 5):
		if s.pave_road(Vector2i(x0 + 4, y + k)):
			paved += 1
	for k in range(-3, 4):
		if k != 0 and s.pave_road(Vector2i(x0 + 9, y + k)):
			paved += 1
	print("PAVED tiles=%d unlocked=%s" % [paved, s.paved_roads_unlocked()])
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(x0 + 2, y) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	cam.set_zoom_step(3)
	await _shoot("/tmp/hv_paved.png")
	hud.open_category("roads")
	await _shoot("/tmp/hv_paved_bar.png")
	quit()
