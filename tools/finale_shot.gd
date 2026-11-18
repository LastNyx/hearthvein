extends SceneTree
## Windowed shots of the three end screens: godot --path . -s tools/finale_shot.gd
## Builds a settlement, shows the won, no_win and lost screens in turn and writes
## .scratch/v1/hv_45d_won.png, hv_45d_no_win.png, hv_45d_lost.png.

const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	main.saves_dir = "/tmp/hv_finale_saves"
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 12):
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.place_building_instant("cottage", Vector2i(h.x + 7, h.y - 2))
	s.hearth.inventory.add("food", 300.0)
	for i in 20 * 24:
		s.step_hours(1)
	var es: EndScreen = main.end_screen
	for o in ["won", "no_win", "lost"]:
		es.close()
		es.show_outcome(o, s)
		await _shoot(OUT + "hv_45d_%s.png" % o)
	es.close()
	quit()
