extends SceneTree
## Windowed HUD screenshots: godot --path . -s tools/hud_shot.gd
## Writes /tmp/hv_hud.png (building selected) and /tmp/hv_hud_overlay.png (blight + road overlays on), plus the tools
## tab (ticket 88): /tmp/hv_88_tools_open.png (1x), /tmp/hv_88_tools_closed.png (1x) and the same two paused
## (/tmp/hv_88_tools_open_paused.png, /tmp/hv_88_tools_closed_paused.png).

func _shoot(path: String) -> void:
	for i in 4:
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
	var m: HudModel = main.hud_model
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 14):
		for y in range(h.y - 4, h.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.place_building_instant("cottage", Vector2i(h.x + 7, h.y - 2))
	s.place_building_instant("storehouse", Vector2i(h.x + 10, h.y + 1))
	var wc := s.place_building_instant("woodcutter", Vector2i(h.x + 5, h.y + 1))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y + 6))  # no road: red overlay and icon
	for t in [Vector2i(h.x + 8, h.y + 5), Vector2i(h.x + 9, h.y + 5), Vector2i(h.x + 8, h.y + 6), Vector2i(h.x + 9, h.y + 6),
			Vector2i(h.x + 10, h.y + 5)]:
		s.set_blighted(t, true)
	s.place_building("storehouse", Vector2i(h.x + 12, h.y - 3))
	s.hearth.inventory.add("food", 300.0)
	for i in 17 * 24:
		s.step_hours(1)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(2)
	cam.position = (Vector2(h) + Vector2(7, 1)) * ArtLibrary.TILE
	m.select(wc)
	(main.get_node("Hud") as Hud).open_category("housing")
	await _shoot("/tmp/hv_hud.png")
	m.toggle_overlay("blight")
	m.toggle_overlay("roads")
	await _shoot("/tmp/hv_hud_overlay.png")
	var tab: ToolsTab = (main.get_node("Hud") as Hud).tools_tab
	main.driver.set_speed(1)
	tab.set_open(true, false)
	await _shoot("/tmp/hv_88_tools_open.png")
	tab.set_open(false, false)
	await _shoot("/tmp/hv_88_tools_closed.png")
	main.driver.set_speed(0)
	await _shoot("/tmp/hv_88_tools_closed_paused.png")
	tab.set_open(true, false)
	await _shoot("/tmp/hv_88_tools_open_paused.png")
	# Ticket 95: active tool lit, Upgrade mode, channel tooltip and wet preview.
	var hud: Hud = main.get_node("Hud")
	var bc: BuildController = main.get_node("BuildController")
	s.era_override = "village"
	hud._rebuild_categories()
	m.clear_selection()
	hud.open_category("roads")
	bc.set_mode(BuildController.Mode.DEMOLISH)
	await _shoot("/tmp/hv_95_demolish_lit.png")
	hud.open_category("roads")
	hud.open_category("housing")
	bc.set_build("cottage")
	await _shoot("/tmp/hv_95_build_lit.png")
	bc.set_mode(BuildController.Mode.UPGRADE)
	var cot := s.building_at(Vector2i(h.x + 4, h.y - 2))
	cam.position = (Vector2(cot.origin) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	await process_frame
	root.warp_mouse(root.get_visible_rect().size / 2.0)  # the controller follows the real pointer
	await process_frame
	bc.ghost.set_state(null, cot.origin, s.can_upgrade(cot.id)["ok"], true)
	await _shoot("/tmp/hv_95_upgrade_lit.png")
	hud.open_category("housing")
	hud.open_category("roads")
	bc.set_mode(BuildController.Mode.CHANNEL)
	await process_frame
	var water := s.map.terrain_index("water")
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 2):
			if absi(x - h.x) < 40 and absi(y - h.y) < 40 and s.map.get_terrain(x + 1, y) == water and s.can_place_channel(Vector2i(x, y))["ok"]:
				cam.position = (Vector2(x, y) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
				await process_frame
				root.warp_mouse(root.get_visible_rect().size / 2.0)
				await process_frame
				bc.ghost.set_state(null, Vector2i(x, y), true, true)
				bc.ghost.set_wet(WaterSystem.channel_preview(s, Vector2i(x, y)))
				await _shoot("/tmp/hv_95_channel_preview.png")
				break
		if bc.ghost.wet_tiles.size() > 0:
			break
	bc.cancel()
	print(s.clock.label(), " notices: ", m.notifications.items.map(func(i: Dictionary) -> String: return i["text"]))
	quit()
