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


func test_new_game_with_endless_toggle() -> void:
	var dir := "/tmp/nyx-flash/hearthvein_panel_%d" % OS.get_process_id()
	var m := SaveMenuModel.new(SaveSlots.new(dir), reg, func() -> Settlement: return null)
	m.endless_toggle = true
	m.request_new_game()
	assert_eq(m.pending["action"], "new_game")
	var s := m.confirm()
	assert_not_null(s)
	assert_true(m.pending.is_empty())
	var c := s.get_system(CampaignSystem) as CampaignSystem
	assert_true(c.endless_start)
	assert_false(c.win_check_enabled)


func test_new_game_without_toggle_is_normal_campaign() -> void:
	var dir := "/tmp/nyx-flash/hearthvein_panel_%d" % OS.get_process_id()
	var m := SaveMenuModel.new(SaveSlots.new(dir), reg, func() -> Settlement: return null)
	m.request_new_game()
	var s := m.confirm()
	var c := s.get_system(CampaignSystem) as CampaignSystem
	assert_false(c.endless_start)
	assert_true(c.win_check_enabled)
	m.request_new_game()
	m.cancel()
	assert_null(m.confirm())
