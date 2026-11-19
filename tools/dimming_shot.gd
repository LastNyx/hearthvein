extends SceneTree
## Windowed screenshot of the Dimming made visible (ticket 108): godot --path . -s tools/dimming_shot.gd
## A Dimming in progress (day 1 of 4) with the era panel's light and output lines and a farm selected, whose panel
## and tooltip show "x0.5 Dimming". Writes /tmp/hv_108_dimming.png. Parse-check only in the sandbox; the planner
## takes the shot.

func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var m: HudModel = main.hud_model
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.place_building_instant("storehouse", Vector2i(h.x + 10, h.y + 1))
	var farm := -1
	for dy in range(-10, 11):
		for dx in range(2, 16):
			var o := Vector2i(h.x + dx, h.y + dy)
			if farm < 0 and s.can_place("farm", o, true)["ok"]:
				farm = s.place_building_instant("farm", o)
	s.hearth.inventory.add("lumen", 40.0)
	s.hearth.inventory.add("lumen_cells", 2.0)
	s.hearth.inventory.add("food", 300.0)
	for i in 17 * 24:
		s.step_hours(1)
	var d := s.get_system(DimmingSystem) as DimmingSystem
	d._start_day = s.clock.total_days()
	d._length = 4
	d._active = true
	d.last_light = {"need": DimmingSystem.light_need(s), "drawn_lumen": 0.0, "drawn_cells": 0.0, "short": 0.0}
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(7, 1)) * ArtLibrary.TILE
	main.driver.set_speed(0)
	m.select(farm)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_108_dimming.png")
	quit()
