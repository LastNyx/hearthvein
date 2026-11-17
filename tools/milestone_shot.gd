extends SceneTree
## Windowed shots of the pause menu with the new rows and the Milestones panel: godot --path . -s tools/milestone_shot.gd
## A few milestones reached this run, the lifetime file (a /tmp path) holding others. Writes
## .scratch/v1/hv_46c_menu.png and hv_46c_milestones.png.

const OUT := "/home/ngeng/Proyek/hearthvein/.scratch/v1/"
const LIFE := "/tmp/hv_milestone_shot_life.json"


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var f := FileAccess.open(LIFE, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"first_dimming": {"date": "Year 2, Winter, Day 9", "seed": 7},
		"village": {"date": "Year 1, Autumn, Day 3", "seed": 7},
		"citizens_100": {"date": "Year 4, Spring, Day 1", "seed": 7},
		"tier3": {"date": "Year 5, Summer, Day 12", "seed": 7},
	}))
	f.close()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	main.saves_dir = "/tmp/hv_milestone_shot_saves"
	main.milestones_path = LIFE
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 12):
		s.place_road(Vector2i(x, h.y))
	s.place_building_instant("cottage", Vector2i(h.x + 4, h.y - 2))
	s.hearth.inventory.add("food", 300.0)
	for i in 30 * 24:
		s.step_hours(1)
	main.menu.open()
	await _shoot(OUT + "hv_46c_menu.png")
	main.menu.show_milestones()
	await _shoot(OUT + "hv_46c_milestones.png")
	main.menu.close()
	quit()
