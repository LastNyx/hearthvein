extends GutTest
## Ticket 17: HUD view-model (numbers the bar shows), notifications once per cause, overlay toggles, build bar.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var m: HudModel
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	h = s.map.hearth_spot
	m = HudModel.new(s)


func _res(id: String) -> Dictionary:
	for r in m.resources():
		if r["id"] == id:
			return r
	return {}


func _site_free_spot() -> Vector2i:
	for y in range(h.y - 8, h.y + 8):
		for x in range(h.x + 4, h.x + 20):
			if s.can_place("woodcutter", Vector2i(x, y))["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_resources_show_values_and_daily_deltas() -> void:
	s.step_days(1)
	s.hearth.inventory.add("materials", 7.0)
	s.step_days(1)
	var r := _res("materials")
	assert_eq(r["delta"], 7)
	assert_eq(r["value"], 47)
	assert_eq(r["text"], "47 +7")
	assert_eq(_res("food")["icon"], "food")
	s.gold = 12.0
	s.step_days(1)
	assert_eq(_res("gold")["text"], "12 +12")
	s.gold = 10.0
	s.step_days(1)
	assert_eq(_res("gold")["text"], "10 -2")
	assert_eq(HudModel.delta_text(0), "+0")


func test_population_beds_and_spirit_planet_numbers() -> void:
	var p := m.population()
	assert_eq(p["pop"], 8)
	assert_eq(p["text"], "8 / %d" % s.beds_total())
	s.spirit_override = 72.0
	var sp := m.spirit()
	assert_eq(sp["text"], "Spirit 72")
	assert_eq(sp["state"], "good")
	assert_string_contains(sp["tooltip"], "Base 50")
	s.spirit_override = 20.0
	assert_eq(m.spirit()["state"], "bad")
	s.planet_health_override = 63.4
	assert_string_contains(m.planet()["text"], "63%")
	assert_string_contains(m.planet()["text"], "/yr")


func test_era_panel_gate_and_dimming_forecast_text() -> void:
	var ep := m.era_panel()
	assert_eq(ep["title"], "Era: Camp")
	assert_string_contains(ep["gate"], "Next:")
	assert_string_contains(ep["gate"], "pop")
	assert_eq(ep["date"], "Year 1, Spring")
	var d: DimmingSystem = s.get_system(DimmingSystem)
	var guard := 0
	while d.status(s)["state"] == "none" and guard < 120:
		s.step_days(1)
		guard += 1
	var st := d.status(s)
	assert_ne(st["state"], "none")
	var txt := m.dimming_text()
	if st["state"] == "forecast":
		assert_true(txt.begins_with("Dimming "))
		assert_string_contains(txt, "lasts %d" % st["length"])
	while d.status(s)["state"] != "active" and guard < 400:
		s.step_days(1)
		guard += 1
	assert_string_contains(m.dimming_text(), "DIMMING - day 1 of")


func test_selected_building_panel_and_priority() -> void:
	var id := s.place_building_instant("woodcutter", _site_free_spot())
	assert_true(id >= 0)
	m.select(id)
	var sel := m.selection()
	assert_eq(sel["title"], "Woodcutter")
	assert_true("Workers 0/%d" % s.buildings[id].def.worker_slots in sel["lines"])
	assert_eq(sel["priority"], "normal")
	assert_true(m.set_priority("high"))
	assert_eq(m.selection()["priority"], "high")
	assert_true(m.toggle_pause())
	assert_true(m.selection()["paused"])
	assert_true(m.toggle_pause())
	assert_false(m.selection()["paused"])
	s.buildings[id].halt = "door_full"
	assert_string_contains(m.selection()["halt"], "buffer full")
	s.demolish(id)
	assert_eq(m.selection(), {})
	assert_eq(m.selected_id, -1)


func test_selection_of_a_site_shows_progress() -> void:
	var id := s.place_building("storehouse", _site_free_spot())
	assert_true(id >= 0)
	m.select(id)
	var sel := m.selection()
	assert_true(sel["site"])
	assert_true((sel["lines"][0] as String).begins_with("Under construction"))


func test_build_bar_lists_only_unlocked_by_category() -> void:
	var bar := m.build_bar()
	var ids: Array = bar.map(func(c: Dictionary) -> String: return c["id"])
	assert_eq(ids[0], "roads")
	assert_true(ids.has("housing"))
	assert_false(ids.has("sky"))
	for cat in bar:
		for e: Dictionary in cat["entries"]:
			if e["kind"] == "building":
				assert_true(s.is_unlocked(reg.get_building(e["id"])), e["id"])
				assert_ne(e["id"], "hearth")
	# an era unlock adds entries
	var before := 0
	for cat in bar:
		before += (cat["entries"] as Array).size()
	s.era_override = "village"
	var after := 0
	for cat in m.build_bar():
		after += (cat["entries"] as Array).size()
	assert_true(after >= before)


func test_notifications_fire_once_per_cause() -> void:
	var id := s.place_building_instant("woodcutter", _site_free_spot())
	var n := m.notifications
	s.events.emit("production_halted", {"id": id, "why": "door_full"})
	s.events.emit("production_halted", {"id": id, "why": "door_full"})
	assert_eq(n.items.size(), 1)
	assert_string_contains(n.items[0]["text"], "buffer full")
	s.events.emit("production_resumed", {"id": id, "why": ""})
	s.events.emit("production_halted", {"id": id, "why": "door_full"})
	assert_eq(n.items.size(), 2, "fires again after the cause cleared")
	# a different building is a different cause
	s.events.emit("production_halted", {"id": 9999, "why": "door_full"})
	assert_eq(n.items.size(), 3)
	# forecast: once per forecast
	s.events.emit("dimming_forecast", {"start_day": 20, "length": 2})
	s.events.emit("dimming_forecast", {"start_day": 20, "length": 2})
	assert_eq(n.items.size(), 4)
	s.events.emit("dimming_forecast", {"start_day": 30, "length": 2})
	assert_eq(n.items.size(), 5)


func test_no_workers_notice_once_until_staffed() -> void:
	var id := s.place_building_instant("woodcutter", _site_free_spot())
	var n := m.notifications
	n.poll()
	n.poll()
	var count := 0
	for it in n.items:
		if it["key"] == "%d:no_workers" % id:
			count += 1
	assert_eq(count, 1)
	var c: Citizen = s.citizens[s.citizens.keys()[0]]
	c.job_id = id
	c.job_kind = Citizen.JOB_WORK
	n.poll()
	assert_false(n.is_active("%d:no_workers" % id))
	c.job_id = -1
	c.job_kind = Citizen.JOB_NONE
	n.poll()
	assert_true(n.is_active("%d:no_workers" % id))
	assert_eq(n.items.filter(func(it: Dictionary) -> bool: return it["key"] == "%d:no_workers" % id).size(), 2)


func test_recent_notices_expire_from_display() -> void:
	s.events.emit("dimming_forecast", {"start_day": 5, "length": 2})
	assert_eq(m.notifications.recent(48).size(), 1)
	s.step_hours(60)
	assert_eq(m.notifications.recent(48).size(), 0)


func test_overlays_toggle() -> void:
	assert_false(m.overlay_on("blight"))
	assert_true(m.toggle_overlay("blight"))
	assert_true(m.overlay_on("blight"))
	assert_false(m.overlay_on("roads"))
	assert_true(m.toggle_overlay("roads"))
	assert_false(m.toggle_overlay("blight"))
	assert_false(m.toggle_overlay("nonsense"))


func test_selection_names_the_made_good_and_skips_empty_output() -> void:
	var id := s.place_building_instant("woodcutter", _site_free_spot())
	m.select(id)
	var lines: Array = m.selection()["lines"]
	assert_true("Makes: Materials" in lines)
	for l in lines:
		assert_false(String(l).begins_with("Output:"), "empty output buffer is not listed")


func test_population_reports_growth_share() -> void:
	var g: float = m.population()["growth"]
	assert_true(g >= 0.0 and g <= 1.0)


func test_water_overlay_toggle() -> void:
	assert_false(m.overlay_on("water"))
	assert_true(m.toggle_overlay("water"))
	assert_true(m.overlay_on("water"))
	assert_false(m.overlay_on("blight"))
	assert_false(m.toggle_overlay("water"))


func test_roads_category_offers_channel_from_village() -> void:
	var kinds := func(bar: Array[Dictionary]) -> Array:
		return bar[0]["entries"].map(func(e: Dictionary) -> String: return e["kind"])
	s.era_override = "camp"
	assert_false(kinds.call(m.build_bar()).has("channel"))
	s.era_override = "village"
	assert_true(kinds.call(m.build_bar()).has("channel"))
	var e: Dictionary = m.build_bar()[0]["entries"].filter(func(x: Dictionary) -> bool: return x["kind"] == "channel")[0]
	assert_eq(e["cost"], "1 Materials")
	assert_eq(HudModel.channel_refusal_text("materials"), "Not enough materials")


func test_roads_category_offers_paved_in_town() -> void:
	var kinds := func(bar: Array[Dictionary]) -> Array:
		return bar[0]["entries"].map(func(e: Dictionary) -> String: return e["kind"])
	s.era_override = "village"
	assert_false(kinds.call(m.build_bar()).has("paved"))
	s.era_override = "town"
	assert_true(kinds.call(m.build_bar()).has("paved"))
	var e: Dictionary = m.build_bar()[0]["entries"].filter(func(x: Dictionary) -> bool: return x["kind"] == "paved")[0]
	assert_eq(e["cost"], "1 Materials, 0.2 Cut stone")
	assert_false(e["cost"].contains("_") or e["cost"].contains("  "))
	assert_eq(HudModel.paved_refusal_text("cut_stone"), "Not enough cut stone")


func test_hud_overlay_keys_and_menu_buttons() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	add_child_autofree(main)
	await get_tree().process_frame
	var hud: Hud = main.get_node("Hud")
	var model: HudModel = main.hud_model
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.pressed = true
	hud._unhandled_input(ev)
	assert_true(model.overlay_on("water"))
	hud.toggle_overlay_menu()
	assert_true(hud._overlay_panel.visible)
	(hud._overlay_buttons["roads"] as Button).pressed.emit()
	assert_true(model.overlay_on("roads"))
	(hud._overlay_buttons["water"] as Button).pressed.emit()
	assert_false(model.overlay_on("water"))


func test_coverage_overlay_toggle_and_geometry() -> void:
	assert_false(m.overlay_on("coverage"))
	assert_true(m.toggle_overlay("coverage"))
	assert_true(m.overlay_on("coverage"))
	assert_false(m.toggle_overlay("coverage"))
	assert_eq(m.reach_areas("coverage").size(), 0)
	for y in range(h.y + 4, h.y + 12):
		for x in range(h.x + 4, h.x + 14):
			s.set_terrain(Vector2i(x, y), "grass")
	assert_gt(s.place_building_instant("shrine", h + Vector2i(6, 6)), -1)
	var areas := m.reach_areas("coverage")
	assert_eq(areas.size(), 1)
	var sh: Building = s.building_at(h + Vector2i(6, 6))
	assert_eq(areas[0], sh.footprint().grow(6).intersection(Rect2i(0, 0, MapState.WIDTH, MapState.HEIGHT)))
	var near := s.place_building_instant("tent", h + Vector2i(6, 8))
	var homes := m.coverage_homes()
	var found := false
	for e in homes:
		if e["id"] == near:
			found = true
			assert_true(e["covered"])
	assert_true(found)


func test_water_overlay_marks_fouled_tiles_and_well_range() -> void:
	assert_eq(m.fouled_tiles().size(), 0)
	assert_eq(m.reach_areas("water").size(), 0)
	var river: Vector2i = s.map.river_path[0]
	assert_true(s.set_fouled(river, true))
	assert_true(s.set_fouled(s.map.river_path[1], true))
	var f := m.fouled_tiles()
	assert_eq(f.size(), 2)
	assert_true(f.has(river))
	s.set_fouled(river, false)
	assert_eq(m.fouled_tiles(), [s.map.river_path[1]] as Array[Vector2i])
	# a Well inserted off the map edge keeps the fixture simple: its water_radius area is clipped to the map
	var wb := Building.new()
	wb.id = 9001
	wb.def = reg.get_building("well")
	wb.origin = Vector2i(10, 10)
	s.buildings[wb.id] = wb
	var areas := m.reach_areas("water")
	assert_eq(areas.size(), 1)
	assert_eq(areas[0], wb.footprint().grow(wb.def.water_radius).intersection(Rect2i(0, 0, MapState.WIDTH, MapState.HEIGHT)))
	assert_eq(m.reach_areas("coverage").size(), 0, "a Well is not Shrine coverage")


# ---------------------------------------------------------------- region map (ticket 25c)

func test_region_rows_owned_buyable_locked() -> void:
	var rows := m.region_rows()
	assert_eq(rows.size(), 16)
	var start: int = s.map.start_region
	assert_eq(rows[start]["state"], "owned")
	assert_eq(rows[start]["note"], "Home")
	var buyable := 0
	for r in rows:
		if r["state"] == "buyable":
			buyable += 1
			assert_true(MapState.region_neighbours(r["region"]).has(start))
			assert_eq(r["price"], 50)
			assert_eq(r["reason"], "gold")
			assert_eq(r["note"], "Need 50 gold")
		elif r["state"] == "locked":
			assert_eq(r["price"], 0)
			assert_eq(r["note"], "Locked")
	assert_eq(buyable, MapState.region_neighbours(start).size())


func test_region_rows_buy_updates_price_and_state() -> void:
	s.gold = 500.0
	var target := -1
	for r in m.region_rows():
		if r["state"] == "buyable":
			assert_true(r["can_buy"])
			assert_eq(r["note"], "")
			target = r["region"]
	assert_true(m.buy_region(target))
	var rows := m.region_rows()
	assert_eq(rows[target]["state"], "owned")
	assert_eq(rows[target]["note"], "Owned")
	assert_eq(s.gold, 450.0)
	for r in rows:
		if r["state"] == "buyable":
			assert_eq(r["price"], 100)
	var locked_buy := -1
	for r in rows:
		if r["state"] == "locked":
			locked_buy = r["region"]
	assert_false(m.buy_region(locked_buy))


func test_region_rows_rewards_shown_on_locked_regions() -> void:
	var seen := 0
	for r in m.region_rows():
		var want := s.map.get_region_reward(r["region"])
		assert_eq(r["reward"], want)
		if want != "":
			seen += 1
			assert_ne(r["reward_label"], "")
			assert_true(r["reward_pos"].x >= 0)
			assert_true(MapState.region_rect(r["region"]).has_point(r["reward_pos"]))
	assert_true(seen >= 4)


# ---------------------------------------------------------------- upgrade panel (31d)

func _tent_selected() -> int:
	var id := s.place_building_instant("tent", _site_free_spot())
	assert_true(id >= 0)
	m.select(id)
	return id


func test_selection_shows_tier_next_cost_and_era_reason() -> void:
	var id := _tent_selected()
	var sel := m.selection()
	assert_eq(sel["tier"], 1)
	assert_eq(sel["next_tier"], 2)
	assert_eq(sel["next_name"], "Hut")
	assert_eq(sel["next_cost"], "3 Planks, 2 Cut stone")
	assert_true(sel["show_upgrade"])
	assert_false(sel["can_upgrade"])
	assert_eq(sel["upgrade_reason"], "Needs Town era")
	s.era_override = "town"
	sel = m.selection()
	assert_true(sel["can_upgrade"])
	assert_eq(sel["upgrade_reason"], "")
	assert_true(id >= 0)


func test_upgrade_command_and_progress_in_selection() -> void:
	s.era_override = "town"
	_tent_selected()
	assert_true(m.upgrade())
	var sel := m.selection()
	assert_true(sel["upgrading"])
	assert_false(sel["show_upgrade"])
	assert_false(sel["can_upgrade"])
	assert_eq(sel["upgrade_reason"], "Upgrade in progress")
	assert_eq(sel["upgrade_progress"], 0.0)
	assert_false(m.upgrade())


func test_wet_reason_and_non_upgradable_building() -> void:
	assert_eq(m.upgrade_reason_text("needs_wet"), "Needs wet ground")
	var id := s.place_building_instant("storehouse", _site_free_spot())
	m.select(id)
	var sel := m.selection()
	assert_false(sel["show_upgrade"])
	assert_eq(sel["next_tier"], 0)
	assert_false(m.upgrade())
