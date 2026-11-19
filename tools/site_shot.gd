extends SceneTree
## Windowed screenshots of a Storehouse construction site: godot --path . -s tools/site_shot.gd
## Writes /tmp/hv_site.png (mid-build), /tmp/hv_site_wait.png (site panel with the wait line) and /tmp/hv_site_done.png.
## Night mode (ticket 105): godot --path . -s tools/site_shot.gd -- night
## Writes /tmp/hv_site_night.png (a Meeting Hall site at 23:00 with its crew resting at the door) and
## /tmp/hv_site_night_day.png (the same crew at work at 12:00 the next day).

func _shoot(path: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	var night := OS.get_cmdline_user_args().has("night")
	for x in range(h.x + 2, h.x + 12):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	if night:
		await _night(main, s, h)
		quit()
		return
	var id := s.place_building("storehouse", Vector2i(h.x + 5, h.y - 1))
	var b: Building = s.buildings[id]
	var model: HudModel = main.hud_model
	model.select(id)  # the site panel and tooltip show the wait line
	print("site wait line: ", model.wait_text(b))
	await _shoot("/tmp/hv_site_wait.png")
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(4)
	cam.position = (Vector2(h) + Vector2(5, 0)) * ArtLibrary.TILE
	var guard := 0
	while b.site and b.build_progress() < 0.55 and guard < 400:
		s.step_seconds(1.0)
		guard += 1
	print("site progress ", b.build_progress(), " at ", s.clock.label())
	await _shoot("/tmp/hv_site.png")
	guard = 0
	while b.site and guard < 2000:
		s.step_seconds(1.0)
		guard += 1
	print("done ", not b.site, " at ", s.clock.label())
	await _shoot("/tmp/hv_site_done.png")
	quit()


## A crew resting at an unfinished site: the cost is put into the site, the crew works one shift and is shot at 23:00
## standing at the door, then again at noon the next day at work.
func _night(main: Node, s: Settlement, h: Vector2i) -> void:
	var id := s.place_building("meeting_hall", Vector2i(h.x + 5, h.y - 2))
	var b: Building = s.buildings[id]
	var cost := b.effective_cost()
	for g in cost:
		if g != BuildingDef.GOLD:
			b.input_buffer.add(g, float(cost[g]))
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(4)
	cam.position = (Vector2(h) + Vector2(5.5, -1)) * ArtLibrary.TILE
	var guard := 0
	while b.site and s.clock.hour() != 23 and guard < 400:
		s.step_hours(1)
		guard += 1
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	print("night: site ", b.site, " progress ", b.build_progress(), " crew ", cs.crews.size(), " at ", s.clock.label())
	await _shoot("/tmp/hv_site_night.png")
	guard = 0
	while b.site and s.clock.hour() != 12 and guard < 400:
		s.step_hours(1)
		guard += 1
	print("day: site ", b.site, " progress ", b.build_progress(), " at ", s.clock.label())
	await _shoot("/tmp/hv_site_night_day.png")
