extends GutTest
## Ticket 46c: Milestones panel view-model (run and lifetime rows, counts, bonus) and the New game option.

const LIFE := "/tmp/nyx-flash/hearthvein_panel_life.json"

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func after_each() -> void:
	MilestoneSystem.lifetime_path = ""
	DirAccess.remove_absolute(LIFE)


func _ms(s: Settlement) -> MilestoneSystem:
	return s.get_system(MilestoneSystem) as MilestoneSystem


func test_rows_in_data_order_with_done_locked_and_date() -> void:
	var s := Settlement.new_game(42, reg)
	for i in 24:
		s.step_hours(1)
	var ms := _ms(s)
	ms._fire(s, reg.milestones["village"])
	var d := MilestonePanelModel.build(reg, ms, {})
	var rows: Array = d["run"]["rows"]
	var order: Array[String] = []
	for m in reg.milestones_in_order():
		order.append(m.id)
	var ids: Array[String] = []
	for r in rows:
		ids.append(r["id"])
	assert_eq(ids, order)
	for r in rows:
		if r["id"] == "village":
			assert_true(r["done"])
			assert_eq(r["date"], s.clock.label())
			assert_eq(r["name"], reg.milestones["village"].display_name)
		elif r["id"] != "population" and not ms.has(r["id"]):
			assert_false(r["done"])
			assert_eq(r["date"], "")


func test_lifetime_rows_use_stored_date() -> void:
	var life := {"tier3": {"date": "Year 5, Summer, Day 12", "seed": 7}}
	var d := MilestonePanelModel.build(reg, null, life)
	for r in d["lifetime"]["rows"]:
		if r["id"] == "tier3":
			assert_true(r["done"])
			assert_eq(r["date"], "Year 5, Summer, Day 12")
		else:
			assert_false(r["done"])
	assert_eq(d["lifetime"]["done"], 1)
	assert_eq(d["run"]["done"], 0)


func test_counts_and_bonus_flag() -> void:
	var s := Settlement.new_game(42, reg)
	var ms := _ms(s)
	var all := reg.milestones_in_order()
	var bonus_ids: Array[String] = []
	for m in all:
		if m.bonus:
			bonus_ids.append(m.id)
	assert_eq(bonus_ids.size(), 1)
	var d := MilestonePanelModel.build(reg, ms, {})
	assert_eq(d["run"]["total"], all.size() - 1)
	assert_eq(d["run"]["header"], "This run 0 / %d (+bonus locked)" % (all.size() - 1))
	ms._fire(s, all[0])
	ms._fire(s, reg.milestones[bonus_ids[0]])
	d = MilestonePanelModel.build(reg, ms, {})
	assert_eq(d["run"]["done"], 1)
	assert_true(d["run"]["bonus_done"])
	assert_eq(d["run"]["header"], "This run 1 / %d (+bonus)" % (all.size() - 1))
	for r in d["run"]["rows"]:
		assert_eq(r["bonus"], r["id"] == bonus_ids[0])


func test_run_date_saved_and_old_save_has_none() -> void:
	var s := Settlement.new_game(42, reg)
	var ms := _ms(s)
	ms._fire(s, reg.milestones["village"])
	var st := ms.save_state()
	var ms2 := MilestoneSystem.new()
	ms2.load_state(st, s)
	assert_eq(ms2.date_of("village"), s.clock.label())
	st.erase("dates")
	var ms3 := MilestoneSystem.new()
	ms3.load_state(st, s)
	assert_true(ms3.has("village"))
	assert_eq(ms3.date_of("village"), "")


func test_header_splits_title_and_count() -> void:
	var d := MilestonePanelModel.build(reg, null, {})
	assert_eq(d["run"]["title"], "This run")
	assert_eq(d["run"]["count"], "0 / %d" % d["run"]["total"])
	assert_eq(d["lifetime"]["bonus_text"], "(+bonus locked)")


func test_menu_header_count_label_and_no_new_game_row() -> void:
	var dir := "/tmp/nyx-flash/hearthvein_panel_ui_%d" % OS.get_process_id()
	var m := SaveMenuModel.new(SaveSlots.new(dir), reg, func() -> Settlement: return null)
	var menu := SaveMenu.new()
	add_child_autofree(menu)
	menu.setup(m)
	menu.refresh()
	# Ticket 79: New game and the Endless toggle moved to the title's NewGamePanel.
	assert_null(menu.find_child("EndlessToggle", true, false))
	for l in menu.find_children("*", "Label", true, false):
		assert_ne((l as Label).text, "New game")
	for b in menu.find_children("*", "Button", true, false):
		assert_ne((b as Button).text, "Start")
	menu.refresh_milestones()
	var counts := menu.find_children("Count", "Label", true, false)
	assert_eq(counts.size(), 2)
	assert_eq((counts[0] as Label).text, "0 / %d" % (reg.milestones_in_order().size() - 1))
