extends GutTest
## Ticket 141: the Night Market and the night caravan (spec .scratch/v1/night-shift-spec.md N9).
##
## The Night Market sells the stock of priced goods above their keep level for gold at the night shift's start, only
## while it is lit and staffed. Every 4-6 nights (seed and day only) a caravan stops at a lit, staffed Night Market,
## offers one rare good for gold until 06:00, and its state is saved.

const SEED := 42

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the night fill, not the small-town first-hand rule, is under test


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


## A fresh settlement with the growth system off and a clear road strip east of the Hearth.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 22):
		for y in range(hs.y - 4, hs.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


func _put(s: Settlement, id: String, origin: Vector2i) -> Building:
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	return s.buildings.get(bid)


## A Night Market north of the road strip and, when `lit`, a fuelled lamp south of it.
func _market(s: Settlement, lit: bool = true) -> Building:
	var hs := s.map.hearth_spot
	var m := _put(s, "night_market", Vector2i(hs.x + 6, hs.y - 2))
	if lit:
		var lamp := _put(s, "lamp", Vector2i(hs.x + 6, hs.y + 1))
		lamp.input_buffer.add("wood", 6.0)
	return m


func _step_to(s: Settlement, hour: int) -> void:
	s.step_hours(posmod(hour - s.clock.hour(), 24))


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


func _caravan(s: Settlement) -> CaravanSystem:
	return s.get_system(CaravanSystem) as CaravanSystem


## Steps to 21:00 of the first caravan night of the settlement and returns that day.
func _to_caravan_night(s: Settlement) -> int:
	var day: int = CaravanSystem.arrival_days(SEED, 30)[0]
	s.step_days(day - s.clock.total_days())
	_step_to(s, 19)
	s.step_hours(2)
	return day


## Criterion 1: the market sells the silk above its keep (10) at the night shift's start only while lit and staffed.
func test_market_sells_surplus_only_at_night_when_lit_and_staffed() -> void:
	var s := _new_settlement()
	var m := _market(s)
	_keep_citizens(s, 5)
	s.hearth.inventory.add("silk", 30.0)
	var gold := s.gold
	_step_to(s, 12)
	assert_almost_eq(s.gold, gold, 0.001, "nothing sold by day")
	_step_to(s, 19)
	assert_true(s.is_lit(m), "the lamp lights the market")
	assert_gt(SpiritSystem.night_workers(s, m), 0, "the market has night workers")
	assert_almost_eq(s.gold, gold, 0.001, "nothing sold before the night shift starts")
	_step_to(s, 21)
	assert_almost_eq(s.gold, gold + 20.0 * 8.0, 0.01, "20 silk above the keep sold for 8 gold each")
	assert_almost_eq(float(s.totals().get("silk", 0.0)), 10.0, 0.001, "the keep level stays in storage")

	var dark := _new_settlement()
	_market(dark, false)
	_keep_citizens(dark, 5)
	dark.hearth.inventory.add("silk", 30.0)
	var dgold := dark.gold
	_step_to(dark, 21)
	assert_almost_eq(dark.gold, dgold, 0.001, "an unlit market sells nothing")

	var idle := _new_settlement()
	_market(idle)
	_keep_citizens(idle, 0)
	idle.hearth.inventory.add("silk", 30.0)
	var igold := idle.gold
	_step_to(idle, 21)
	assert_almost_eq(idle.gold, igold, 0.001, "an unstaffed market sells nothing")


## Criterion 2: the schedule depends on the seed and the day only (gaps of 4-6 nights); the caravan makes its offer at
## a lit, staffed market, a buy takes the gold and adds the goods once, and it is gone at 06:00.
func test_caravan_schedule_is_deterministic_and_offer_buy_and_leave() -> void:
	var days: Array = CaravanSystem.arrival_days(SEED, 60)
	assert_eq(days, CaravanSystem.arrival_days(SEED, 60), "same seed, same schedule")
	assert_gt(days.size(), 5, "a caravan every few nights")
	var prev := 0
	for d: int in days:
		assert_between(d - prev, 4, 6, "4-6 nights between caravans")
		prev = d
	var other: Array = CaravanSystem.arrival_days(SEED + 1, 60)
	assert_ne(other, days, "another seed has its own schedule")

	var s := _new_settlement()
	var nc := NotificationCenter.new(s)
	var m := _market(s)
	_keep_citizens(s, 5)
	var day := _to_caravan_night(s)
	assert_eq(day, days[0], "the first caravan night")
	var cv := _caravan(s)
	assert_true(cv.visiting(), "the caravan is parked at the market")
	assert_eq(cv.market_id(), m.id)
	var offer := cv.offer()
	assert_eq(offer["good"], "tools")
	assert_eq([offer["amount"], offer["gold"]], [5, 40], "tools x5 for 40 gold")
	assert_eq(cv.notice_text(s), "Night caravan: tools x5 for 40 gold, tonight only")
	assert_true(nc.items.any(func(it: Dictionary) -> bool: return it["text"] == cv.notice_text(s)),
			"the notice is raised")
	s.gold = 10.0
	assert_false(cv.buy(s), "not enough gold")
	assert_eq(s.gold, 10.0)
	s.gold = 100.0
	var tools := float(s.totals().get("tools", 0.0))
	assert_true(cv.buy(s), "the buy goes through")
	assert_almost_eq(s.gold, 60.0, 0.001, "40 gold paid")
	assert_almost_eq(float(s.totals().get("tools", 0.0)), tools + 5.0, 0.001, "5 tools added")
	assert_false(cv.buy(s), "one buy per visit")
	_step_to(s, 5)
	assert_true(cv.visiting(), "still parked before dawn")
	_step_to(s, 6)
	assert_false(cv.visiting(), "gone at 06:00")
	assert_false(cv.buy(s), "nothing to buy once it left")

	var dark := _new_settlement()
	_market(dark, false)
	_keep_citizens(dark, 5)
	dark.step_days(days[0] - dark.clock.total_days())
	_step_to(dark, 21)
	assert_false(_caravan(dark).visiting(), "no caravan at an unlit market")


## Criterion 3: a save in the middle of a visit loads with the same offer and can still be bought.
func test_save_and_load_mid_visit() -> void:
	var s := _new_settlement()
	_market(s)
	_keep_citizens(s, 5)
	_to_caravan_night(s)
	assert_true(_caravan(s).visiting())
	var path := "/tmp/hv_night_market_141_%d.sav" % OS.get_process_id()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded)
	if loaded == null:
		return
	var cv := _caravan(loaded)
	assert_true(cv.visiting(), "the caravan is still parked after loading")
	assert_eq(cv.offer(), _caravan(s).offer())
	assert_eq(cv.market_id(), _caravan(s).market_id())
	loaded.gold = 100.0
	assert_true(cv.buy(loaded), "the loaded visit can be bought")
	loaded.step_hours(9)
	assert_false(cv.visiting(), "and it leaves at 06:00")


## The notice carries a Buy button while the caravan is parked, the market's selection panel has one too, and the
## wagon stands beside the market until the caravan leaves.
func test_notice_and_selection_panel_buy_buttons_and_wagon() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	var tmp := OS.get_environment("TMPDIR")
	main.settings_path = (tmp if tmp != "" else "/tmp").path_join("hearthvein_caravan141_%d.cfg" % OS.get_process_id())
	main.saves_dir = main.settings_path + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	var s: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var hs := s.map.hearth_spot
	var m := _put(s, "night_market", Vector2i(hs.x + 6, hs.y - 2))
	var cv := _caravan(s)
	assert_eq(main.placement.wagon_node_count(), 0, "no wagon before the caravan comes")
	cv.start_visit(s, m)  # the schedule itself is covered above; this opens a visit now
	await wait_process_frames(2)
	assert_gt(main.placement.wagon_node_count(), 0, "the wagon is parked beside the market")
	var price := float(cv.offer()["gold"])
	hud.model.select(m.id)
	s.gold = 100.0
	hud.refresh()
	assert_true(hud.model.selection()["caravan"]["visible"], "the panel shows the caravan row")
	var panel_btn := hud.find_child("BuyCaravan", true, false) as Button
	assert_not_null(panel_btn, "the selection panel has a buy button")
	assert_true(panel_btn.visible)
	assert_false(panel_btn.disabled)
	var notice_btn := hud.find_child("NoticeBuy", true, false) as Button
	assert_not_null(notice_btn, "the notice has a buy button")
	notice_btn.pressed.emit()
	assert_almost_eq(s.gold, 100.0 - price, 0.001, "the notice button bought the offer")
	hud.refresh()
	assert_true(panel_btn.disabled, "one buy per visit")
	s.step_days(1)
	assert_eq(main.placement.wagon_node_count(), 0, "the wagon leaves with the caravan")
