extends GutTest
## Ticket 79: the New game panel on the title (seed, Endless, Tutorial, Start/Back) and the tutorial seed's map.

var dir: String
var cfg: String
var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_ngp_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _main() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	return main


func _open(main: Node) -> NewGamePanel:
	(main.get_node("TitleScreen").find_child("NewGame", true, false) as Button).pressed.emit()
	return main.get_node("NewGamePanel") as NewGamePanel


func test_blank_seed_is_random_typed_seed_is_used_tutorial_blank_is_the_data_seed() -> void:
	var main := _main()
	await wait_process_frames(3)
	var panel := _open(main)
	panel.tutorial_toggle.button_pressed = false
	assert_eq(panel.chosen_seed(), -1, "blank")
	panel.seed_edit.text = "1234"
	panel.seed_edit.text_changed.emit("1234")
	panel.start_button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(main.state, 1)
	assert_eq(main.settlement.map.seed_used, 1234, "typed seed")
	assert_false((main.settlement.get_system(TutorialSystem) as TutorialSystem).is_active())
	# blank + tutorial on: the data seed and the tutorial runs
	main.return_to_title()
	await wait_process_frames(2)
	panel = _open(main)
	assert_true(panel.tutorial_toggle.button_pressed, "default on before the first tutorial run")
	panel.start_button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(main.settlement.map.seed_used, reg.mapgen.tutorial_seed)
	assert_true((main.settlement.get_system(TutorialSystem) as TutorialSystem).is_active())
	assert_true(main.settings.tutorial_first_run_done)
	var again := GameSettings.new()
	again.path = cfg
	again.load_file()
	assert_true(again.tutorial_first_run_done, "saved")
	# blank + tutorial off: random (seed differs from the tutorial seed is not guaranteed, so only check it starts)
	main.return_to_title()
	await wait_process_frames(2)
	panel = _open(main)
	assert_false(panel.tutorial_toggle.button_pressed, "off once the tutorial has run")
	panel.start_button.pressed.emit()
	await wait_process_frames(1)
	assert_eq(main.state, 1)


func test_seed_field_keeps_digits_only_and_back_closes_the_panel() -> void:
	var main := _main()
	await wait_process_frames(3)
	var panel := _open(main)
	panel.seed_edit.text = "12ab3"
	panel.seed_edit.text_changed.emit("12ab3")
	assert_eq(panel.seed_edit.text, "123")
	panel.back_button.pressed.emit()
	await wait_process_frames(2)
	assert_false(main.has_node("NewGamePanel"))
	assert_eq(main.state, 0)


func test_endless_toggle_reaches_the_win_check() -> void:
	var main := _main()
	await wait_process_frames(3)
	var panel := _open(main)
	panel.tutorial_toggle.button_pressed = false
	panel.endless_toggle.button_pressed = true
	panel.start_button.pressed.emit()
	await wait_process_frames(1)
	var c := main.settlement.get_system(CampaignSystem) as CampaignSystem
	assert_true(c.endless_start)
	assert_false(c.win_check_enabled)


func test_tutorial_seed_map_has_forest_vein_river_and_room_to_build() -> void:
	var map := MapGen.generate(reg.mapgen.tutorial_seed, reg)
	var r := TutorialSeedCheck.measure(map, reg)
	assert_lte(r["forest"], 4.0, "forest within 4 of a woodcutter spot near the road")
	assert_lte(r["vein"], 8.0, "vein tile within 8 of the Hearth")
	assert_lte(r["river"], 12.0, "river within 12 of the Hearth")
	assert_gte(r["tent_spots"], 6, "grass for 6 tents near the road start")
	assert_true(r["market_spot"], "a free 2x2 for the Market")
