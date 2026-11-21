extends SceneTree
## Xvfb screenshot (ticket 156): a crew of 3 at a site beside a river plus a tree being cleared, at work.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tools/crew_shot.gd
## Writes /tmp/hv_crew.png.

func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	s.registry.logistics.builder_crew = 3
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 5, h.y + 6):
			s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y - 1))
	var o := Vector2i(h.x + 6, h.y)
	var def := s.registry.get_building("meeting_hall")
	for x in range(o.x - 3, o.x + def.size.x + 4):  # the river along the south side
		for y in range(o.y + def.size.y, o.y + def.size.y + 2):
			s.set_terrain(Vector2i(x, y), "water")
	var tree := Vector2i(h.x + 12, h.y - 3)
	s.set_terrain(tree, "forest")
	var id := s.place_building("meeting_hall", o)
	var b: Building = s.buildings[id]
	var cost := b.effective_cost()
	for g in cost:
		if g != BuildingDef.GOLD:
			b.input_buffer.add(g, float(cost[g]))
	print("mark clear ", s.mark_clear(tree))
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(4)
	cam.position = (Vector2(h) + Vector2(9.5, 0.5)) * ArtLibrary.TILE
	var guard := 0
	while s.clock.hour() != 10 and guard < 400:
		s.step_hours(1)
		guard += 1
	s.step_seconds(0.5)
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	print("crews ", cs.crews, " hour ", s.clock.hour(), " site ", b.site)
	if main.hud != null:
		main.hud.hide()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_crew.png")
	quit()
