extends GutTest
## Ticket 37c: track tiles autotile by 4-neighbour mask and redraw on track_changed; train cars face their move.

func test_dir_column_matches_the_atlas_order() -> void:
	assert_eq(TrainView.dir_column(Vector2i(1, 0)), 0)
	assert_eq(TrainView.dir_column(Vector2i(-1, 0)), 1)
	assert_eq(TrainView.dir_column(Vector2i(0, 1)), 2)
	assert_eq(TrainView.dir_column(Vector2i(0, -1)), 3)


func test_track_tiles_autotile_and_clear() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	add_child_autofree(main)
	main.start_new_game()
	await get_tree().process_frame
	var s: Settlement = main.settlement
	s.era_override = "conflux"
	s.hearth.inventory.add("materials", 100.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var o := s.map.hearth_spot + Vector2i(0, 12)
	for t in [o, o + Vector2i(1, 0), o + Vector2i(1, 1)]:
		s.set_terrain(t, "grass")
		assert_true(s.place_track(t), "laid %s" % str(t))
	var layer: TileMapLayer = main.map_view.track
	assert_eq(layer.get_cell_atlas_coords(o), Vector2i(2, 0), "end tile joins east")
	assert_eq(layer.get_cell_atlas_coords(o + Vector2i(1, 0)), Vector2i(8 | 4, 0), "corner joins south and west")
	assert_eq(layer.get_cell_atlas_coords(o + Vector2i(1, 1)), Vector2i(1, 0), "end tile joins north")
	s.remove_track(o + Vector2i(1, 0))
	assert_eq(layer.get_cell_atlas_coords(o + Vector2i(1, 0)), Vector2i(-1, -1), "lifted tile is erased")
	assert_eq(layer.get_cell_atlas_coords(o), Vector2i(0, 0), "its neighbours redraw")
