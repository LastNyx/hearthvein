extends GutTest
## Ticket 77: Main boots into TITLE (a backdrop map and the TitleScreen, nothing ticking) and enters GAME on request.

var dir: String
var cfg: String
var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_states_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	_wipe()
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	_wipe()
	DirAccess.remove_absolute(cfg)


func _wipe() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(dir)


func _main() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	return main


func _button(main: Node, id: String) -> Button:
	return main.get_node("TitleScreen").find_child(id, true, false) as Button


func test_boot_shows_the_title_and_nothing_ticks() -> void:
	var main := _main()
	await wait_process_frames(3)
	assert_eq(main.state, main.State.TITLE)
	assert_null(main.settlement)
	assert_null(main.driver)
	assert_null(main.hud)
	assert_not_null(main.get_node("MapView"))
	assert_not_null(main.get_node("TitleScreen"))
	assert_false(main.has_node("Hud"))
	for id in ["NewGame", "Load", "Milestones", "Settings", "Quit"]:
		assert_not_null(_button(main, id), id)


func test_continue_is_hidden_without_a_save_and_loads_the_newest_one() -> void:
	var main := _main()
	await wait_process_frames(2)
	assert_false(_button(main, "Continue").visible)
	main.queue_free()
	await wait_process_frames(1)
	var s := Settlement.new_game(7, reg)
	s.step_days(3)
	var slots := SaveSlots.new(dir)
	assert_eq(slots.save_slot(2, s), OK)
	var main2 := _main()
	await wait_process_frames(2)
	var cont := _button(main2, "Continue")
	assert_true(cont.visible)
	cont.pressed.emit()
	await wait_process_frames(2)
	assert_eq(main2.state, main2.State.GAME)
	assert_eq(main2.settlement.clock.total_hours, s.clock.total_hours)
	assert_not_null(main2.get_node("Hud"))


func test_new_game_enters_game_and_returning_to_title_frees_the_world() -> void:
	var main := _main()
	await wait_process_frames(2)
	var title_children: int = main.get_child_count()
	_button(main, "NewGame").pressed.emit()
	await wait_process_frames(2)
	assert_eq(main.state, main.State.GAME)
	assert_not_null(main.settlement)
	assert_eq(main.settlement.clock.total_hours, 0)
	assert_not_null(main.get_node("Hud"))
	assert_not_null(main.driver)
	main.return_to_title()
	await wait_process_frames(2)
	assert_eq(main.state, main.State.TITLE)
	assert_null(main.settlement)
	assert_null(main.driver)
	assert_false(main.has_node("Hud"))
	assert_eq(main.get_child_count(), title_children)
	assert_eq(SaveSlots.new(dir).latest_auto(), 0, "leaving the game autosaves")
	assert_true(_button(main, "Continue").visible)


func test_start_new_game_takes_seed_and_endless() -> void:
	var main := _main()
	await wait_process_frames(2)
	main.start_new_game(42, true)
	await wait_process_frames(1)
	assert_eq(main.settlement.map.seed_used, 42)
	assert_true((main.settlement.get_system(CampaignSystem) as CampaignSystem).endless_start)


## Ticket 78: the title shows the logo art (nearest filter, buttons stay column width) over a backdrop without region tint.
func test_title_logo_art_and_backdrop_without_region_tint() -> void:
	var main := _main()
	await wait_process_frames(3)
	var logo := main.get_node("TitleScreen").find_child("Logo", true, false) as TextureRect
	assert_true(logo is TextureRect)
	assert_eq(logo.texture, ArtLibrary.texture(ArtLibrary.manifest()["logo"]["file"]))
	assert_eq(logo.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_true(ArtLibrary.manifest()["logo"]["file_2x"] != "")
	assert_lt(_button(main, "NewGame").size.x, 400.0)
	assert_false(main.map_view.show_regions)
	assert_false(main.map_view.get_children().filter(func(n: Node) -> bool: return n is MapView.RegionOverlay)[0].visible)
	main.start_new_game()
	await wait_process_frames(2)
	assert_true(main.map_view.show_regions)
