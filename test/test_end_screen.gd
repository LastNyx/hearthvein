extends GutTest
## Ticket 45d: end screen view-model per outcome, and the screen opening on the campaign events, pausing, Continue.

const SEED := 42

var reg: DataRegistry
var dir: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_end_%d" % OS.get_process_id()
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


func _main() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	main.saves_dir = dir
	add_child_autofree(main)
	main.start_new_game()
	return main


func _ids(d: Dictionary) -> Array:
	return d["buttons"].map(func(b: Dictionary) -> String: return b["id"])


func test_model_won_has_numbers_and_two_buttons() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.step_days(40)
	var d := EndScreenModel.build("won", s)
	assert_eq(d["title"], "The Skyheart held")
	assert_string_contains(d["body"], "Year %d" % s.clock.year())
	assert_string_contains(d["body"], "%d%%" % roundi(s.planet_health()))
	assert_string_contains(d["body"], "%d citizens" % s.citizens.size())
	assert_string_contains(d["body"], "goes on")
	assert_eq(_ids(d), ["continue", "save_quit"])


func test_model_no_win_names_health_and_threshold() -> void:
	var s := Settlement.new_game(SEED, reg)
	var d := EndScreenModel.build("no_win", s)
	assert_eq(d["title"], "The light held, the land did not")
	assert_string_contains(d["body"], "%d%%" % roundi(s.planet_health()))
	assert_string_contains(d["body"], "below 50%")
	assert_string_contains(d["body"], "Play goes on")
	assert_eq(_ids(d), ["continue"])


func test_model_lost() -> void:
	var s := Settlement.new_game(SEED, reg)
	var d := EndScreenModel.build("lost", s)
	assert_eq(d["title"], "The hearth went cold")
	assert_string_contains(d["body"], "No citizens remain")
	assert_string_contains(d["body"], "Year %d" % s.clock.year())
	assert_eq(_ids(d), ["load", "quit"])
	assert_true(EndScreenModel.build("", s).is_empty())


func test_screen_opens_on_each_event_and_pauses() -> void:
	for pair in [["campaign_won", "won"], ["campaign_no_win", "no_win"], ["campaign_lost", "lost"]]:
		var main := _main()
		await wait_process_frames(2)
		var es: EndScreen = main.end_screen
		assert_false(es.is_open())
		main.settlement.events.emit(pair[0], {})
		assert_true(es.is_open(), pair[0])
		assert_eq(es.outcome, pair[1])
		assert_true(get_tree().paused, "paused while " + pair[1] + " is up")
		es.close()
		get_tree().paused = false
		main.queue_free()
		await wait_process_frames(2)


func test_continue_unpauses_and_closes() -> void:
	var main := _main()
	await wait_process_frames(2)
	var es: EndScreen = main.end_screen
	main.settlement.events.emit("campaign_won", {})
	assert_eq(es.button_ids(), ["continue", "save_quit"])
	es.press("continue")
	assert_false(es.is_open())
	assert_false(get_tree().paused)


func test_loss_screen_keeps_paused_even_after_the_save_menu_closes() -> void:
	var main := _main()
	await wait_process_frames(2)
	var es: EndScreen = main.end_screen
	main.settlement.events.emit("campaign_lost", {})
	es.press("load")
	assert_true(main.menu.is_open())
	main.menu.close()
	await wait_process_frames(2)
	assert_true(es.is_open())
	assert_true(get_tree().paused, "the loss screen re-pauses")


func test_no_reopen_after_loading_a_save_with_an_outcome_set() -> void:
	var main := _main()
	await wait_process_frames(2)
	var other := Settlement.new_game(7, reg)
	(other.get_system(CampaignSystem) as CampaignSystem).outcome = "won"
	var slots := SaveSlots.new(dir)
	assert_eq(slots.save_slot(0, other), OK)
	var loaded := slots.load_slot(0, reg)
	assert_eq((loaded.get_system(CampaignSystem) as CampaignSystem).outcome, "won")
	main.swap_settlement(loaded)
	await wait_process_frames(2)
	assert_false(main.end_screen.is_open())
	assert_false(get_tree().paused)


func test_loss_screen_quit_goes_to_the_title() -> void:
	var main := _main()
	await wait_process_frames(2)
	main.settlement.events.emit("campaign_lost", {})
	main.end_screen.press("quit")
	await wait_process_frames(2)
	assert_eq(main.state, main.State.TITLE)
	assert_false(main.end_screen.is_open())
	assert_false(get_tree().paused)
