extends SceneTree
## Windowed screenshots: godot --path . -s tools/hint_shot.gd
## Writes /tmp/hv_hint.png (a hint card, buffer full, at the right edge under the objectives and goods panels) and /tmp/hv_era_card.png
## (the Village era card).

func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.settings_path = "/tmp/hv_hint_settings.cfg"
	root.add_child(main)
	await process_frame
	main.start_new_game(42)
	main.settings.seen_hints.clear()
	main.settings.hints_enabled = true
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	hud.hint_cards.help_page_requested.connect(func(_p: String) -> void: pass)  # shows the More button
	s.events.emit("production_halted", {"id": 1, "why": "door_full"})
	hud.hint_cards.set_process(false)
	await _shoot("/tmp/hv_hint.png")
	hud.hint_cards.close()
	s.era_current = "village"
	s.events.emit("era_changed", {"from": "camp", "to": "village"})
	await _shoot("/tmp/hv_era_card.png")
	quit()
