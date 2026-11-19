extends SceneTree
## All 23 generic buildings in a grid at zoom 2: godot --path . -s tools/generic_shot.gd
## Writes /tmp/hv_110_generic.png (ticket 110).

const IDS := ["forager", "storehouse", "fishing_dock", "quarry", "sawmill", "forester", "builders_yard", "workshop",
	"tax_office", "well", "mason", "refinery", "kitchen", "handcart_shed", "lift_anchor", "lumen_arcology",
	"heartroot_tap", "verdant_spring", "vein_mender", "rewilding_grove", "clearwater_works", "bloom_orchard",
	"hall_of_seasons"]


func _init() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for i in IDS.size():
		var t := Vector2i(h.x - 12 + (i % 6) * 5, h.y + 4 + (i / 6) * 5)
		s.place_building_instant(IDS[i], t)
	var cam: CameraController = main.get_node("Camera")
	cam.set_zoom_step(3)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/hv_110_generic.png")
	quit()
