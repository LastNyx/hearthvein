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
	var up := BuildingDef.new()
	up.id = "test_hud_grid_consumer"
	up.display_name = "Test HUD grid consumer"
	up.era = "town"
	up.category = "resources"
	up.size = Vector2i(2, 1)
	up.upkeep_lumen = 2.0
	reg.buildings[up.id] = up


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


## The first free spot for any def (ticket 128 needs a 2x1 Sawmill).
func _free_spot(id: String, from: int) -> Vector2i:
	for y in range(h.y - 8, h.y + 8):
		for x in range(h.x + from, h.x + 24):
			if s.can_place(id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_resources_show_values_and_daily_deltas() -> void:
	s.step_days(1)
	s.hearth.inventory.add("wood", 7.0)
	s.hearth.inventory.add("stone", 7.0)
	s.step_days(1)
	var r := _res("wood")
	assert_eq(r["delta"], 7)
	assert_eq(r["value"], 107)
	assert_eq(r["text"], "107 +7")
	var st := _res("stone")
	assert_eq([st["value"], st["delta"], st["icon"]], [7, 7, "stone"])
	assert_eq(m.resources().map(func(x: Dictionary) -> String: return x["id"]),
			["food", "bread", "wood", "charcoal", "stone", "planks", "cut_stone", "tools", "lumen", "cells", "gold"])
	assert_eq(_res("food")["icon"], "food")
	s.gold = 12.0
	s.step_days(1)
	assert_eq(_res("gold")["text"], "12 +12")
	s.gold = 10.0
	s.step_days(1)
	assert_eq(_res("gold")["text"], "10 -2")
	assert_eq(HudModel.delta_text(0), "+0")


## Ticket 112: the refined goods and lumen cells are in the bar too, with their own daily change.
func test_refined_goods_and_cells_in_the_bar() -> void:
	s.step_days(1)
	for g in ["planks", "cut_stone", "tools", "lumen_cells"]:
		s.hearth.inventory.add(g, 5.0)
	s.step_days(1)
	assert_eq([_res("planks")["value"], _res("planks")["delta"]], [5, 5])
	assert_eq(_res("cut_stone")["value_text"], "5")
	assert_eq(_res("tools")["delta_text"], "+5")
	assert_eq(_res("cells")["value"], 5, "lumen cells stock")
	assert_eq([_res("planks")["icon"], _res("cells")["icon"]], ["planks", "cells"])


## Ticket 112: a goods line splits into text and good segments so the HUD can draw the icons; other lines stay plain.
func test_line_segments_find_the_goods() -> void:
	assert_eq(m.line_segments("Cost: 14 Wood, 21 Stone"),
			[{"text": "Cost: "}, {"good": "wood", "text": "14"}, {"text": ", "}, {"good": "stone", "text": "21"}])
	assert_eq(m.line_segments("Waiting for materials: 12/24 wood, 0/10 lumen"),
			[{"text": "Waiting for materials: "}, {"good": "wood", "text": "12/24"}, {"text": ", "},
					{"good": "lumen", "text": "0/10"}])
	assert_eq(m.line_segments("Upgrade to Cottage: 3 Planks, 2 Cut stone"),
			[{"text": "Upgrade to Cottage: "}, {"good": "planks", "text": "3"}, {"text": ", "},
					{"good": "cut_stone", "text": "2"}])
	assert_eq(m.line_segments("Delivered: 12 Wood"), [{"text": "Delivered: "}, {"good": "wood", "text": "12"}])
	assert_eq(m.line_segments("Cost: free"), [], "not all goods: draw it as plain text")
	assert_eq(m.line_segments("Per worker per day: 6 Wood -> 3 Planks"), [], "a recipe line is not a cost line")
	assert_eq(m.line_segments("Workers 0/2"), [])
	assert_eq(m.line_segments("Waiting for builders (1st in line)"), [])


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


## Ticket 126: the objectives panel lists one row per City gate part (from the era data), with the progress the
## settlement has made on it.
func test_objectives_rows_match_next_era_gate_parts() -> void:
	s.era_current = "town"
	s.gold = 120.0
	var rows := m.objectives()
	assert_eq(rows.size(), 3)
	assert_eq(rows[0], {"label": "People", "value": 8, "max": 100, "done": false, "kind": "pop"})
	assert_eq(rows[1], {"label": "Gold", "value": 120, "max": 500, "done": false, "kind": "gold"})
	assert_eq(rows[2]["label"], "Lumen Spire")
	assert_eq(rows[2]["kind"], "landmark")
	assert_false(rows[2]["done"])
	assert_eq(m.objectives_header(), "Town -> City: gate parts")


## Ticket 126: the forecast and active Dimming lines, and the win objectives at the last era (Skyheart stages, the
## Great Dimming, planet health >= 50 from the campaign data).
func test_objectives_dimming_lines_and_final_era_win_rows() -> void:
	var d: DimmingSystem = s.get_system(DimmingSystem)
	d._start_day = s.clock.total_days() + 2
	d._length = 3
	d._active = false
	var lines := m.objectives_dimming_lines()
	assert_eq(lines[0], "Dimming in 2 days, lasts 3")
	assert_eq(lines[1], "Lumen output halves. Stock: 2 days.")
	d._start_day = s.clock.total_days()
	d._length = 3
	d._active = true
	assert_eq(m.objectives_dimming_lines()[0], "Dimming: day 1 of 3")
	d.last_light = {"short": 1.0}
	assert_eq(m.objectives_dimming_lines()[1], "Light short: Spirit falls")
	s.era_current = "ascendant"
	var rows := m.objectives()
	assert_eq(rows.map(func(r: Dictionary) -> String: return r["label"]),
			["Skyheart", "Great Dimming", "Planet health >= 50%"])
	assert_eq([rows[0]["max"], rows[0]["done"]], [4, false], "the Skyheart's four stages")
	s.planet_health_override = 40.0
	assert_false(m.objectives()[2]["done"])
	s.planet_health_override = 60.0
	assert_true(m.objectives()[2]["done"], "planet health at or above the win line")


## Ticket 126: the panel collapses to one line through its button, and the collapsed state is stored in GameSettings.
func test_objectives_collapse_state_persists() -> void:
	var dir := "/tmp/nyx-flash/hearthvein_hud126_ui_%d" % OS.get_process_id()
	var cfg := dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(cfg)
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	var hud: Hud = main.get_node("Hud")
	assert_false(main.hud_model.objectives_collapsed())
	hud._objectives_toggle.pressed.emit()
	await wait_process_frames(2)
	assert_true(main.hud_model.objectives_collapsed())
	assert_false(hud._objectives_body.visible, "collapsed shows one line, not the rows")
	assert_true(hud._obj_collapsed_line.visible)
	assert_string_contains(hud._obj_collapsed_line.text, "Objectives: ")
	var saved := GameSettings.new()
	saved.path = cfg
	saved.load_file()
	assert_true(saved.objectives_collapsed, "the collapsed state is saved")
	hud._objectives_toggle.pressed.emit()
	await wait_process_frames(2)
	var reopened := GameSettings.new()
	reopened.path = cfg
	reopened.load_file()
	assert_false(reopened.objectives_collapsed, "expanding is saved too")
	DirAccess.remove_absolute(cfg)
	DirAccess.remove_absolute(dir)


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
	assert_string_contains(m.selection()["halt"], "Output full")
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


## Ticket 128: the fixed bottom-centre panel reads the Sawmill's tier, workers, makes/uses per day and both buffers.
func test_selection_rows_of_a_sawmill() -> void:
	var id := s.place_building_instant("sawmill", _free_spot("sawmill", 4))
	assert_true(id >= 0)
	var b: Building = s.buildings[id]
	b.input_buffer.add("wood", 22.0)
	b.door_buffer.add("planks", 3.0)
	m.select(id)
	var sel := m.selection()
	assert_eq(sel["title"], "Sawmill")
	assert_eq(sel["tier_text"], "Tier I")
	assert_eq(sel["subtitle"], "Refining, village era")
	assert_eq(sel["workers_text"], "0/2")
	assert_eq(sel["workers_slots"], 2)
	assert_eq(sel["makes"], "6 planks / day")
	assert_eq(sel["uses"], "uses 12 wood")
	assert_eq(sel["in_text"], "22 / 24")
	assert_eq(sel["out_text"], "3 / 40")


## Ticket 128: a site keeps its progress and missing-goods rows; with nothing selected the model gives the town summary.
func test_site_rows_and_the_town_summary() -> void:
	var t := m.town_summary()
	assert_eq(t["name"], "Hearthvein")
	assert_eq(t["era"], "Camp")
	assert_eq(t["date"], "Year 1, Spring")
	assert_eq([t["people"], t["beds"], t["idle"]], [8, 8, 6], "8 people, 8 Hearth beds, 6 with Hearth jobs")
	s.spirit_override = 74.0
	s.planet_health_override = 81.0
	t = m.town_summary()
	assert_eq(t["spirit"], 74)
	assert_eq(t["spirit_text"], "74 / 100")
	assert_eq(t["planet"], 81)
	assert_eq(t["planet_text"], "81 / 100")
	assert_string_contains(t["planet_trend"], "/ yr")
	assert_eq(t["hint"], "Click a building to see it here.", "Esc is in the help screen (130b)")
	var id := s.place_building("storehouse", _site_free_spot())
	assert_true(id >= 0)
	m.select(id)
	var sel := m.selection()
	assert_true(sel["site"])
	assert_false(sel["show_workers"])
	assert_true(sel["makes"] == "" and sel["in_text"] == "", "a site shows progress instead of production rows")
	assert_true((sel["lines"] as Array).any(func(l: String) -> bool: return l.begins_with("Under construction")))
	assert_true((sel["lines"] as Array).any(func(l: String) -> bool: return l.begins_with("Waiting for materials")))
	m.clear_selection()
	assert_eq(m.selection(), {})


## The Workforce page's row for a building ({} when it has none).
func _workforce_row(id: int) -> Dictionary:
	for g: Dictionary in m.workforce()["groups"]:
		for r: Dictionary in g["rows"]:
			if r["id"] == id:
				return r
	return {}


## Places a Camp Brazier on the first free tile inside its own radius of `b`, or -1.
func _lamp_near(b: Building) -> int:
	var r: int = reg.get_building("lamp").lamp_radius
	for y in range(b.origin.y - r, b.origin.y + b.def.size.y + r):
		for x in range(b.origin.x - r, b.origin.x + b.def.size.x + r):
			var t := Vector2i(x, y)
			if not s.can_place("lamp", t, true)["ok"]:
				continue
			for bt in b.tiles():
				var d: Vector2i = t - bt
				if d.x * d.x + d.y * d.y <= r * r:
					var id := s.place_building_instant("lamp", t)
					if id >= 0:
						return id
	return -1


## Ticket 136: a Workforce row carries its day and night shifts; a night slot with no lamp in reach says so.
func test_workforce_rows_carry_day_and_night_counts() -> void:
	var mill := s.place_building_instant("sawmill", _free_spot("sawmill", 4))
	var wood := s.place_building_instant("woodcutter", _free_spot("woodcutter", 4))
	assert_true(mill >= 0 and wood >= 0)
	var row := _workforce_row(mill)
	assert_eq([row["day_slots"], row["day_filled"]], [2, 0], "the Sawmill's two day worker slots")
	assert_eq([row["night_slots"], row["night_filled"]], [1, 0], "and its one night slot")
	assert_eq(row["day_text"], "0/2")
	assert_eq(row["night_text"], "Needs a lamp", "no lamp reaches it")
	var plain := _workforce_row(wood)
	assert_eq(plain["night_slots"], 0)
	assert_eq(plain["night_text"], "-", "a building without night slots")
	assert_true(_lamp_near(s.buildings[mill]) >= 0, "a lamp went up beside the Sawmill")
	row = _workforce_row(mill)
	assert_eq(row["night_text"], "0/1", "a lamp in reach: the night column counts again")


## Ticket 136: the selection panel has a night row only when the building has night worker slots.
func test_selection_rows_include_night_only_with_night_slots() -> void:
	var mill := s.place_building_instant("sawmill", _free_spot("sawmill", 4))
	var wood := s.place_building_instant("woodcutter", _free_spot("woodcutter", 4))
	assert_true(mill >= 0 and wood >= 0)
	m.select(mill)
	var sel := m.selection()
	assert_true(sel["show_night"], "the Sawmill has a night slot")
	assert_eq(sel["night_slots"], 1)
	assert_eq(sel["night_text"], "0/1")
	assert_eq(sel["workers_text"], "0/2", "the day row keeps the day workers only")
	m.select(wood)
	sel = m.selection()
	assert_false(sel["show_night"], "the Woodcutter has no night shift")
	assert_eq(sel["night_slots"], 0)


func test_build_bar_lists_unlocked_by_category_and_next_era_locked() -> void:
	var bar := m.build_bar()
	var ids: Array = bar.map(func(c: Dictionary) -> String: return c["id"])
	assert_eq(ids[0], "roads")
	assert_true(ids.has("housing"))
	assert_false(ids.has("sky"))
	for cat in bar:
		for e: Dictionary in cat["entries"]:
			if e["kind"] == "building":
				assert_eq(not s.is_unlocked(reg.get_building(e["id"])), e["locked"], e["id"])
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


# A halt that clears and returns raises a second item (the cause had cleared) but the HUD list shows one toast per
# cause, the newest (ticket 35: two identical Lumen Reactor toasts at once).
func test_recent_shows_one_toast_per_cause() -> void:
	var id := s.place_building_instant("woodcutter", _site_free_spot())
	var n := m.notifications
	s.events.emit("production_halted", {"id": id, "why": "door_full"})
	s.events.emit("production_resumed", {"id": id, "why": ""})
	s.step_hours(2)
	s.events.emit("production_halted", {"id": id, "why": "door_full"})
	assert_eq(n.items.size(), 2, "both raises are kept in the history")
	var shown := n.recent(48)
	assert_eq(shown.size(), 1, "one toast for one building and reason")
	assert_eq(shown[0]["hour"], s.clock.total_hours, "the newest one")
	s.events.emit("production_halted", {"id": 9999, "why": "door_full"})
	assert_eq(n.recent(48).size(), 2, "another building still gets its own toast")


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
	assert_true("Makes: Wood" in lines)
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
	assert_eq(e["cost"], "1 Stone")
	assert_eq(HudModel.channel_refusal_text("stone"), "Not enough stone")


func test_roads_category_offers_paved_in_town() -> void:
	var kinds := func(bar: Array[Dictionary]) -> Array:
		return bar[0]["entries"].map(func(e: Dictionary) -> String: return e["kind"])
	s.era_override = "village"
	assert_false(kinds.call(m.build_bar()).has("paved"))
	s.era_override = "town"
	assert_true(kinds.call(m.build_bar()).has("paved"))
	var e: Dictionary = m.build_bar()[0]["entries"].filter(func(x: Dictionary) -> bool: return x["kind"] == "paved")[0]
	assert_eq(e["cost"], "1 Wood, 0.2 Cut stone")
	assert_false(e["cost"].contains("_") or e["cost"].contains("  "))
	assert_eq(HudModel.paved_refusal_text("cut_stone"), "Not enough cut stone")


func test_roads_category_offers_rail_track_from_conflux() -> void:
	var track_entries := func(bar: Array[Dictionary]) -> Array:
		return bar[0]["entries"].filter(func(e: Dictionary) -> bool: return e["kind"] == "track")
	for era in ["camp", "village", "town"]:
		s.era_override = era
		assert_true(track_entries.call(m.build_bar()).is_empty(), "no track in %s" % era)
	s.era_override = "conflux"
	var found: Array = track_entries.call(m.build_bar())
	assert_eq(found.size(), 1, "track in Conflux")
	assert_eq(found[0]["cost"], "1 Wood, 1 Stone, 1 Cut stone")
	assert_eq(found[0]["label"], "Rail track (J)")
	assert_eq(HudModel.track_refusal_text("cut_stone"), "Not enough cut stone")
	assert_eq(HudModel.track_refusal_text("road"), "A road is here")


func test_hud_overlay_keys_and_minimap_buttons() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	add_child_autofree(main)
	main.start_new_game()
	await get_tree().process_frame
	var hud: Hud = main.get_node("Hud")
	var model: HudModel = main.hud_model
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.pressed = true
	hud._unhandled_input(ev)
	assert_true(model.overlay_on("water"))
	hud.minimap.overlay_button("roads").pressed.emit()
	assert_true(model.overlay_on("roads"))
	hud.minimap.overlay_button("water").pressed.emit()
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


# ---------------------------------------------------------------- grid overlay (ticket 36c)

func _grid_put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var bid := s.place_building_instant(id, Vector2i(h.x + dx, h.y - def.size.y))
	assert_true(bid >= 0, "%s placed at dx %d" % [id, dx])
	return s.buildings.get(bid)


func _grid_ground() -> void:
	s.era_override = "conflux"
	for x in range(h.x - 30, h.x + 15):
		for y in range(h.y - 5, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")


func test_grid_overlay_toggle() -> void:
	assert_true(HudModel.OVERLAYS.has("grid"))
	assert_false(m.overlay_on("grid"))
	assert_true(m.toggle_overlay("grid"))
	assert_true(m.overlay_on("grid"))
	assert_false(m.overlay_on("coverage"))
	assert_false(m.toggle_overlay("grid"))


func test_grid_data_is_empty_without_nodes() -> void:
	assert_eq(m.grid_ranges().size(), 0)
	assert_eq(m.grid_links().size(), 0)
	assert_eq(m.grid_consumers().size(), 0)
	assert_eq(m.grid_batteries().size(), 0)
	assert_eq(m.grid_stamp(), 0)


func test_grid_ranges_and_links() -> void:
	_grid_ground()
	var a := _grid_put("lumen_pylon", 3)
	var b := _grid_put("lumen_pylon", 12)
	var far := _grid_put("lumen_pylon", -16)
	var ranges := m.grid_ranges()
	assert_eq(ranges.size(), 2, "the far pylon is its own grid")
	var gs := s.get_system(GridSystem) as GridSystem
	assert_eq(ranges[0]["id"], gs.grid_of(s, a.id))
	assert_eq(ranges[0]["nodes"], [a.id, b.id])
	assert_eq(ranges[0]["tiles"].size(), gs.covered_tiles(s, ranges[0]["id"]).size())
	assert_true(ranges[0]["tiles"].has(a.origin))
	assert_eq(ranges[1]["nodes"], [far.id])
	var links := m.grid_links()
	assert_eq(links.size(), 1)
	assert_eq(links[0][0], Vector2(a.origin) + Vector2(0.5, 0.5))
	assert_eq(links[0][1], Vector2(b.origin) + Vector2(0.5, 0.5))


func test_grid_consumers_fed_and_unfed() -> void:
	_grid_ground()
	_grid_put("lumen_pylon", 3)
	var near := _grid_put("test_hud_grid_consumer", 6)
	var out := _grid_put("test_hud_grid_consumer", -10)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	var by_id := {}
	for c in m.grid_consumers():
		by_id[c["id"]] = c
	assert_eq(by_id.size(), 2, "only buildings that pay Lumen upkeep or take Lumen input")
	assert_false(by_id[near.id]["fed"], "on a grid with no Lumen yet")
	assert_false(by_id[out.id]["fed"])
	assert_gt(by_id[near.id]["grid"], -1)
	assert_eq(by_id[out.id]["grid"], -1)
	s.hearth.inventory.add("lumen", 20.0)
	by_id.clear()
	for c in m.grid_consumers():
		by_id[c["id"]] = c
	assert_true(by_id[near.id]["fed"], "the Hearth store is on the grid and holds Lumen")
	assert_false(by_id[out.id]["fed"], "outside every feed radius")


func test_grid_battery_charge_counts_as_fed_and_is_reported() -> void:
	_grid_ground()
	_grid_put("lumen_pylon", 3)
	var bat := _grid_put("grid_battery", 5)
	var user := _grid_put("test_hud_grid_consumer", 8)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	var gs := s.get_system(GridSystem) as GridSystem
	var bats := m.grid_batteries()
	assert_eq(bats.size(), 1)
	assert_eq(bats[0]["id"], bat.id)
	assert_eq(bats[0]["capacity"], 600.0)
	assert_eq(bats[0]["charge"], 0.0)
	var stamp := m.grid_stamp()
	gs._charge[bat.id] = 150.0
	bats = m.grid_batteries()
	assert_eq(bats[0]["charge"], 150.0)
	assert_almost_eq(float(bats[0]["fraction"]), 0.25, 0.0001)
	assert_ne(m.grid_stamp(), stamp, "the overlay redraws when charge changes")
	assert_eq(m.grid_ranges()[0]["charge"], 150.0)
	for c in m.grid_consumers():
		if c["id"] == user.id:
			assert_true(c["fed"], "battery charge counts as supply")


func test_battery_charge_counts_in_the_lumen_bar() -> void:
	_grid_ground()
	_grid_put("lumen_pylon", 3)
	var bat := _grid_put("grid_battery", 5)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	var gs := s.get_system(GridSystem) as GridSystem
	gs._charge[bat.id] = 150.0
	for r in m.resources():
		if r["id"] == "lumen":
			assert_eq(r["value"], floori(float(s.totals().get("lumen", 0.0)) + 150.0), "battery charge shows as Lumen stock")


func test_survey_texts() -> void:
	assert_eq(HudModel.survey_reason_text("no_dock"), "Needs a staffed dock")
	assert_eq(HudModel.survey_reason_text("busy"), "All airships are out")
	assert_eq(HudModel.survey_reason_text(""), "")
	var row := {"surveying": true, "survey_days_left": 1.2, "revealed": false, "owned": false, "reward_detail": ""}
	assert_eq(HudModel.survey_status_text(row), "Surveying, 2 days")
	row["survey_days_left"] = 0.4
	assert_eq(HudModel.survey_status_text(row), "Surveying, 1 day")
	row = {"surveying": false, "survey_days_left": 0.0, "revealed": true, "owned": false, "reward_detail": "100 gold"}
	assert_eq(HudModel.survey_status_text(row), "100 gold")
	row["owned"] = true
	assert_eq(HudModel.survey_status_text(row), "", "an owned region needs no survey text")


func test_region_map_survey_button_states() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	add_child_autofree(main)
	main.start_new_game()
	await get_tree().process_frame
	var hud: Hud = main.get_node("Hud")
	var st: Settlement = main.settlement
	var air := st.get_system(AirshipSystem) as AirshipSystem
	var rm: RegionMap = hud._region_map
	var locked: Array[int] = []
	for r in MapState.REGION_COUNT:
		if st.map.get_region_reward(r) != "" and not st.map.is_region_owned(r) \
				and (main.hud_model.region_rows()[r] as Dictionary)["state"] == "locked":
			locked.append(r)
	assert_gte(locked.size(), 2, "two locked regions with rewards")
	rm.open()
	var b: Button = rm._surveys[locked[0]]
	assert_true(b.visible, "locked, unsurveyed: a Survey button")
	assert_true(b.disabled, "no staffed dock yet")
	assert_eq(b.tooltip_text, "Needs a staffed dock")
	assert_eq((rm._notes[locked[0]] as Label).text, "Needs a staffed dock")
	# A flight out over the second region, a finished survey over the first.
	air._surveys.append({"dock": 0, "region": locked[1], "start": 0.0, "done": st.clock.total_hours + 30.0})
	air._revealed[locked[0]] = true
	rm.refresh()
	assert_false((rm._surveys[locked[0]] as Button).visible, "surveyed: no button")
	var detail := HudModel.survey_status_text((main.hud_model.region_rows()[locked[0]] as Dictionary))
	assert_ne(detail, "")
	assert_eq((rm._notes[locked[0]] as Label).text, detail, "the revealed detail")
	assert_false((rm._surveys[locked[1]] as Button).visible)
	assert_eq((rm._notes[locked[1]] as Label).text, "Surveying, 2 days")
	for r in MapState.REGION_COUNT:
		if st.map.is_region_owned(r):
			assert_false((rm._surveys[r] as Button).visible, "owned regions have no Survey button")


func test_region_map_survey_on_buyable_with_buy_beside_it() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	add_child_autofree(main)
	main.start_new_game()
	await get_tree().process_frame
	var hud: Hud = main.get_node("Hud")
	var st: Settlement = main.settlement
	var rm: RegionMap = hud._region_map
	rm.open()
	var found := -1
	for row: Dictionary in main.hud_model.region_rows():
		if row["state"] == "buyable" and row["reward"] != "":
			found = row["region"]
	assert_gte(found, 0, "a buyable region with a reward")
	var buy: Button = rm._buttons[found]
	var sv: Button = rm._surveys[found]
	assert_true(buy.visible and sv.visible, "Buy and Survey both shown")
	assert_false(Rect2(buy.position, buy.size).intersects(Rect2(sv.position, sv.size)), "side by side")
	assert_true(st.map.is_region_owned(st.map.start_region))


# ---------------------------------------------------------------- who does what (ticket 103)

func _set_job(cid: int, bid: int, kind: String) -> void:
	var c: Citizen = s.citizens[cid]
	c.job_id = bid
	c.job_kind = kind


func _idle_everyone() -> void:
	for cid in s.citizens:
		_set_job(cid, -1, Citizen.JOB_NONE)


func test_placed_hearth_shows_filled_haulers_and_builders() -> void:
	_idle_everyone()
	var ids: Array = s.citizens.keys()
	_set_job(ids[0], s.hearth.id, Citizen.JOB_HAUL)
	for i in [1, 2, 3]:
		_set_job(ids[i], s.hearth.id, Citizen.JOB_BUILD)
	m.select(s.hearth.id)
	assert_true("Haulers 1/2, Builders 3/4" in m.selection()["lines"], str(m.selection()["lines"]))
	assert_string_contains(m.tooltip_for_building(s.hearth)["text"], "Haulers 1/2, Builders 3/4")
	assert_string_contains(m.tooltip_for("storehouse")["text"], "Haulers 2")
	assert_false((m.tooltip_for("storehouse")["text"] as String).contains("/"), "the build menu keeps plain slot counts")


func test_house_shows_residents_and_their_roles() -> void:
	_idle_everyone()
	var tent := s.place_building_instant("tent", _site_free_spot())
	var wc := s.place_building_instant("woodcutter", _site_free_spot())
	assert_true(tent >= 0 and wc >= 0)
	var ids: Array = s.citizens.keys()
	for i in [0, 1]:
		(s.citizens[ids[i]] as Citizen).home_id = tent
	_set_job(ids[0], s.hearth.id, Citizen.JOB_HAUL)
	_set_job(ids[1], wc, Citizen.JOB_WORK)
	m.select(tent)
	var lines: Array = m.selection()["lines"]
	assert_true("Residents 2/3" in lines, str(lines))
	assert_true("1 hauler, 1 woodcutter" in lines, str(lines))
	_set_job(ids[0], -1, Citizen.JOB_NONE)
	_set_job(ids[1], -1, Citizen.JOB_NONE)
	assert_true("idle" in m.selection()["lines"])


func test_people_tooltip_counts_add_up_to_the_population() -> void:
	_idle_everyone()
	var wc := s.place_building_instant("woodcutter", _site_free_spot())
	assert_true(wc >= 0)
	var ids: Array = s.citizens.keys()
	for i in [0, 1]:
		_set_job(ids[i], s.hearth.id, Citizen.JOB_HAUL)
	for i in [2, 3, 4]:
		_set_job(ids[i], s.hearth.id, Citizen.JOB_BUILD)
	for i in [5, 6]:
		_set_job(ids[i], wc, Citizen.JOB_WORK)
	assert_eq(s.citizens.size(), 8)
	assert_eq(m.population()["tooltip"], "8 people: 2 haulers, 3 builders, 2 woodcutters, 1 idle")


func _far_producer() -> Building:
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	for y in range(MapState.HEIGHT):
		for x in range(MapState.WIDTH):
			var t := Vector2i(x, y)
			if absi(x - h.x) > 30 or absi(y - h.y) > 30:
				if s.map.terrain_id_at(x, y) == "forest":
					s.set_terrain(t, "grass")
				if s.can_place("woodcutter", t, true)["ok"]:
					return s.buildings[s.place_building_instant("woodcutter", t)]
	return null


func test_output_full_advice_for_each_state() -> void:
	var near := s.buildings[s.place_building_instant("woodcutter", _site_free_spot())] as Building
	near.halt = "door_full"
	m.select(near.id)
	assert_eq(m.halt_text(near), "Output full: no hauler has picked it up")
	# haulers short: nobody holds a hauler slot
	_idle_everyone()
	assert_eq(m.selection()["advice"], "Haulers short: 0 of 2 filled (people are busy elsewhere)")
	# all hauler slots filled
	var ids: Array = s.citizens.keys()
	_set_job(ids[0], s.hearth.id, Citizen.JOB_HAUL)
	_set_job(ids[1], s.hearth.id, Citizen.JOB_HAUL)
	assert_eq(m.selection()["advice"], "Haulers are busy: add a Storehouse or a Handcart Shed")
	# no storage within reach
	var far := _far_producer()
	assert_not_null(far, "a spot far from the Hearth")
	far.halt = "door_full"
	m.select(far.id)
	assert_eq(m.selection()["advice"], "Build a Storehouse nearby (2 more haulers, shorter trips)")
	assert_string_contains(m.tooltip_for_building(far)["text"], "Build a Storehouse nearby")
	near.halt = ""
	assert_eq(m.halt_advice(near), "")


## Ticket 125: the top-right order is the six fixed entries then up to three pinned goods; a fourth pin drops the
## oldest, a core entry cannot be pinned, and the pins live in the user settings (not the save game).
func test_top_goods_core_then_pins_persist_in_settings() -> void:
	var path := "/tmp/nyx-flash/hearthvein_hud125_settings_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(path)
	var settings := GameSettings.new()
	settings.path = path
	var hm := HudModel.new(s, settings)
	assert_eq(hm.top_goods(), ["people", "food", "wood", "stone", "lumen", "gold"])
	assert_true(hm.toggle_pin("planks"))
	assert_eq(hm.top_goods(), ["people", "food", "wood", "stone", "lumen", "gold", "planks"])
	hm.toggle_pin("cut_stone")
	hm.toggle_pin("tools")
	assert_eq(hm.pinned(), ["planks", "cut_stone", "tools"])
	hm.toggle_pin("cells")
	assert_eq(hm.pinned(), ["cut_stone", "tools", "cells"], "the fourth pin replaces the oldest")
	assert_eq(hm.top_goods().slice(6), ["cut_stone", "tools", "cells"])
	assert_false(hm.toggle_pin("tools"), "a pinned good's toggle unpins it")
	assert_eq(hm.pinned(), ["cut_stone", "cells"])
	assert_false(hm.toggle_pin("food"), "the six fixed entries are always there and cannot be pinned")
	assert_eq(settings.pinned_goods, ["cut_stone", "cells"], "saved in the settings at once")
	var fresh := GameSettings.new()
	fresh.path = path
	fresh.load_file()
	var hm2 := HudModel.new(s, fresh)
	assert_eq(hm2.pinned(), ["cut_stone", "cells"], "the pins persist via the settings file")
	assert_eq(hm2.top_goods().slice(6), ["cut_stone", "cells"])
	DirAccess.remove_absolute(path)


## Ticket 125: the full-width top bar is replaced by a compact top-right cluster with a clock row under it; at
## 1280x720 no other HUD panel overlaps either one.
func test_top_right_cluster_is_compact_and_clear_of_other_panels() -> void:
	var dir := "/tmp/nyx-flash/hearthvein_hud125_ui_%d" % OS.get_process_id()
	var cfg := dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	var old := get_window().size
	get_window().size = Vector2i(1280, 720)  # the headless window is tiny
	await wait_process_frames(3)
	var hud: Hud = main.get_node("Hud")
	var vp := hud.get_viewport().get_visible_rect().size
	assert_eq(vp, Vector2(1280, 720))
	var goods := hud.goods_panel.get_global_rect()
	var clock := hud.clock_panel.get_global_rect()
	assert_true(goods.size.x < vp.x * 0.75, "a compact cluster, not the old full-width bar")
	assert_true(goods.position.x > vp.x * 0.25, "pinned to the top-right")
	assert_true(goods.end.x <= vp.x + 1.0 and goods.position.y >= 0.0)
	assert_false(goods.intersects(clock), "the clock row sits under the goods panel")
	hud.open_category("food")
	await wait_process_frames(3)
	var objectives := hud.objectives_panel.get_global_rect()
	assert_true(objectives.position.x < vp.x * 0.25, "the objectives panel is at the top-left")
	assert_false(objectives.intersects(goods), "clear of the top-right goods cluster")
	assert_false(objectives.intersects(clock), "clear of the clock row")
	var labels: Array[Label] = []
	_collect_labels(hud, labels)
	var objectives_title := false
	for l in labels:
		assert_false(l.text.begins_with("Era: "), "the old era panel is gone")
		objectives_title = objectives_title or l.text == "Objectives"
	assert_true(objectives_title, "the objectives panel is drawn")
	var others: Array[Control] = [hud._cmd_panel]
	for other in others:
		if other == null or not other.visible:
			continue
		assert_false(goods.intersects(other.get_global_rect()), "no overlap with %s" % other.name)
		assert_false(clock.intersects(other.get_global_rect()), "no overlap with %s" % other.name)
	assert_lte(hud._cmd_panel.get_global_rect().end.y, 720.0, "the command grid fits inside 720")
	get_window().size = old
	DirAccess.remove_absolute(cfg)
	DirAccess.remove_absolute(dir)


func _collect_labels(node: Node, out: Array[Label]) -> void:
	if node is Label:
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)
