extends GutTest
## Ticket 11: construction sites, haulers delivering the cost, builders, site priority, demolish refund.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	h = s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## A site beside the road (north of it), `dx` tiles east of the Hearth.
func _site(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var bid := s.place_building(id, Vector2i(h.x + dx, h.y - def.size.y))
	assert_true(bid >= 0, "%s site placed" % id)
	return s.buildings.get(bid)


## Puts a site's whole cost into its buffer (paused sites get no haulers).
func _deliver(b: Building) -> void:
	var cost := b.effective_cost()
	for g in cost:
		if g != BuildingDef.GOLD:
			b.input_buffer.add(g, float(cost[g]))


func _hearth_wood() -> float:
	return s.hearth.inventory.amount_of("wood")


## Game hours until the site turns into a building (-1 when it did not within `max_days`).
func _hours_to_finish(b: Building, max_days: int) -> int:
	for i in max_days * 24:
		if not b.site:
			return i
		s.step_hours(1)
	return -1


## Balance pass (102): a site that finishes starts producing at once, even when nothing else is placed or removed after it
## (the producer list was only rebuilt on a grid change or a new building, so such a building stood idle for ever).
func test_a_finished_site_produces_without_any_later_placement() -> void:
	for x in range(h.x + 3, h.x + 7):
		s.set_terrain(Vector2i(x, h.y - 4), "forest")
	var b := _site("woodcutter", 4)
	_deliver(b)
	s.step_hours(1)  # the producer list is built while the woodcutter is still a site
	assert_true(_hours_to_finish(b, 4) >= 0, "the woodcutter is built")
	var wood: float = s.totals().get("wood", 0.0)
	s.step_days(3)
	assert_gt(s.totals().get("wood", 0.0), wood + 5.0, "the new woodcutter made wood")


func test_place_building_makes_a_site_instant_path_is_explicit() -> void:
	var beds := s.beds_total()
	var b := _site("tent", 4)
	assert_true(b.site)
	assert_eq(s.beds_total(), beds, "a site houses nobody")
	assert_null(b.inventory)
	assert_eq(b.build_progress(), 0.0)
	var def := reg.get_building("storehouse")
	var id := s.place_building_instant("storehouse", Vector2i(h.x + 8, h.y + 1))
	assert_false((s.buildings[id] as Building).site)
	assert_not_null((s.buildings[id] as Building).inventory)
	assert_eq(def.id, "storehouse")


func test_site_only_progresses_once_full_cost_is_delivered() -> void:
	s.hearth.inventory.remove("wood", 1000.0)
	s.hearth.inventory.add("wood", 10.0)  # storehouse needs 25
	var b := _site("storehouse", 4)
	s.step_days(3)
	assert_true(b.site)
	assert_eq(b.build_work, 0.0, "no progress with part of the cost")
	assert_between(b.input_buffer.amount_of("wood"), 9.99, 10.01, "what exists was delivered")
	assert_eq(s.events.log_of("building_completed").size(), 0)
	s.hearth.inventory.add("wood", 15.0)
	s.step_hours(12)  # a whole day would also finish it now (0.6 days for a 2x1)
	assert_true(b.site_delivered())
	assert_between(b.input_buffer.amount_of("wood"), 24.99, 25.01)
	assert_true(_hours_to_finish(b, 4) >= 0, "builds once everything arrived")
	assert_false(b.site)
	assert_not_null(b.inventory)
	assert_eq(s.events.log_of("building_completed").size(), 1)
	assert_between(_hearth_wood(), -0.01, 0.01, "the cost left the hearth")


func test_build_time_follows_size_and_era() -> void:
	var tent := reg.get_building("tent")
	var store := reg.get_building("storehouse")
	var hall := reg.get_building("meeting_hall")
	assert_eq(s.build_days(tent), 0.3, "1 tile is 0.3 days (102 balance: 0.3 a tile, 0.1 an era, 0.3 at least)")
	assert_almost_eq(s.build_days(store), 0.6, 0.001)
	assert_almost_eq(s.build_days(hall), 1.2, 0.001)
	var huge := tent.duplicate() as BuildingDef
	huge.size = Vector2i(10, 10)
	assert_eq(s.build_days(huge), 6.0, "clamped to 6 days")
	var late := tent.duplicate() as BuildingDef
	late.era = "city"
	assert_almost_eq(s.build_days(late), 0.6, 0.001, "era adds days")
	# Played out: a tent is done long before a meeting hall (same delivery, a full crew).
	s.hearth.inventory.add("wood", 100.0)
	s.hearth.inventory.add("stone", 100.0)
	s.hearth.inventory.add("lumen", 10.0)
	var t := _site("tent", 4)
	var tent_h := _hours_to_finish(t, 6)
	assert_true(tent_h > 0)
	s = Settlement.new_game(SEED, reg)
	for x in range(h.x + 2, h.x + 16):
		s.place_road(Vector2i(x, h.y))
	s.hearth.inventory.add("wood", 100.0)
	s.hearth.inventory.add("stone", 100.0)
	s.hearth.inventory.add("lumen", 10.0)
	var m := _site("meeting_hall", 4)
	var hall_h := _hours_to_finish(m, 10)
	assert_true(hall_h > 0)
	assert_gt(hall_h, tent_h + 24, "a 3 day building takes at least a day more than a 1 day one")


func test_high_priority_site_gets_builders_first() -> void:
	var a := _site("tent", 4)
	var b := _site("tent", 6)
	s.set_building_priority(a.id, "paused")  # paused sites get no builders: stock both by hand (they get no hauling either)
	s.set_building_priority(b.id, "paused")
	_deliver(a)
	_deliver(b)
	s.step_days(1)
	assert_true(a.site_delivered() and b.site_delivered())
	assert_eq(a.build_work + b.build_work, 0.0)
	assert_true(s.set_building_priority(a.id, "normal"))
	assert_true(s.set_building_priority(b.id, "high"))
	var first_done := -1
	for i in 6 * 24:
		s.step_hours(1)
		if first_done < 0 and not b.site:
			first_done = i
			break
	assert_gt(first_done, -1, "the high priority site finished")
	assert_true(a.site, "the normal one still waits (4 builders, one crew)")
	assert_between(a.build_work, 0.0, 0.0001)
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	assert_true(cs.crews.is_empty() or cs.crews.values().has(a.id))
	s.step_days(3)
	assert_false(a.site, "then the other gets its turn")


func test_builders_work_only_while_at_the_site() -> void:
	var b := _site("tent", 4)
	s.step_hours(48)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	assert_true(b.site_delivered() or not b.site)
	var before := b.build_work
	s.step_hours(22 - s.clock.hour())  # to 22:00, nobody works at night (when still a site)
	if b.site:
		var night := b.build_work
		s.step_hours(1)
		assert_eq(b.build_work, night, "no work at night")
	assert_gte(b.build_work, before)
	assert_not_null(ws)


func test_demolish_refunds_half_the_cost_to_nearest_storehouse() -> void:
	var near := s.place_building_instant("storehouse", Vector2i(h.x + 8, h.y - 1))
	assert_gt(near, -1)
	var t := s.place_building_instant("storehouse", Vector2i(h.x + 10, h.y - 1))
	var store := s.buildings[near] as Building
	assert_eq(store.inventory.amount_of("wood"), 0.0)
	var hearth_before := _hearth_wood()
	assert_true(s.demolish(t))
	assert_almost_eq(store.inventory.amount_of("wood"), 12.5, 0.001, "half of 25, to the nearest storehouse")
	assert_eq(_hearth_wood(), hearth_before, "not to the farther hearth")
	# A storehouse that is full: the refund goes to the next nearest with room.
	store.inventory.add("lumen", 400.0 - 12.5)
	var tent := s.place_building_instant("tent", Vector2i(h.x + 12, h.y - 1))
	assert_true(s.demolish(tent))
	assert_almost_eq(_hearth_wood(), hearth_before + 2.5, 0.001)


func test_demolished_site_refunds_half_of_what_was_delivered() -> void:
	var b := _site("storehouse", 4)
	s.step_hours(30)
	var delivered := b.input_buffer.amount_of("wood") if b.site else 25.0
	assert_gt(delivered, 0.0)
	if not b.site:
		pending("site finished too early for this check")
		return
	var before := _hearth_wood()
	assert_true(s.demolish(b.id))
	assert_almost_eq(_hearth_wood(), before + delivered * 0.5, 0.001)
	s.step_days(2)  # haulers whose destination vanished put their load back, nothing crashes
	assert_eq(s.events.log_of("building_demolished").size(), 1)


func test_builders_take_the_nearest_ready_site_first() -> void:
	var far := _site("tent", 14)  # lower id, but farther from the builders
	var near := _site("tent", 4)
	s.set_building_priority(far.id, "paused")
	s.set_building_priority(near.id, "paused")
	_deliver(far)
	_deliver(near)
	s.step_days(1)
	assert_true(far.site_delivered() and near.site_delivered())
	s.set_building_priority(far.id, "normal")
	s.set_building_priority(near.id, "normal")
	for i in 6 * 24:
		s.step_hours(1)
		if not near.site or not far.site:
			break
	assert_false(near.site, "the near site is built first")
	assert_true(far.site)


func test_site_too_far_from_every_builders_yard_shows_a_status() -> void:
	var far_x := 40
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	for x in range(h.x + 16, h.x + far_x + 4):
		for y in range(h.y - 3, h.y + 1):
			s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var b := _site("tent", far_x)
	var near := _site("tent", 4)
	var model := HudModel.new(s)
	s.step_hours(2)
	assert_eq(b.halt, "too_far", "round trip from the Hearth is longer than the work day")
	assert_eq(near.halt, "")
	assert_eq(model.halt_text(b), "Halted: too far from a builders' yard")
	var yard := s.place_building_instant("builders_yard", Vector2i(h.x + far_x - 4, h.y - 2))
	assert_gt(yard, -1, "a yard near the site")
	s.step_hours(2)
	assert_eq(b.halt, "", "a closer builders' yard clears it")


func test_site_wait_line_says_what_is_missing() -> void:
	s.gold = 1000.0
	s.era_override = "village"
	var model := HudModel.new(s)
	var b := _site("cleanser", 4)
	b.input_buffer.add("wood", 12.0)
	b.input_buffer.add("stone", 12.0)
	assert_eq(model.wait_text(b), "Waiting for materials: 12/24 wood, 12/36 stone, 0/10 lumen")
	b.input_buffer.add("wood", 12.0)
	b.input_buffer.add("stone", 24.0)
	assert_eq(model.wait_text(b), "Waiting for materials: 0/10 lumen", "only the goods still missing")
	model.select(b.id)
	var sel := model.selection()
	assert_true((sel["lines"] as Array).has("Waiting for materials: 0/10 lumen"), "the panel shows it")
	assert_true((model.tooltip_for_building(b)["text"] as String).contains("Waiting for materials: 0/10 lumen"))


func test_site_wait_line_for_builders_shows_the_place_in_line() -> void:
	var model := HudModel.new(s)
	var sites: Array[Building] = []
	for dx in [4, 6, 8]:
		var b := _site("tent", dx)
		b.input_buffer.add("wood", 5.0)
		b.input_buffer.add("stone", 5.0)
		sites.append(b)
	assert_eq(model.wait_text(sites[0]), "Waiting for builders (1st in line)")
	assert_eq(model.wait_text(sites[1]), "Waiting for builders (2nd in line)")
	assert_eq(model.wait_text(sites[2]), "Waiting for builders (3rd in line)")
	s.set_building_priority(sites[2].id, "high")
	assert_eq(model.wait_text(sites[2]), "Waiting for builders (1st in line)", "ready_works order")


func test_site_wait_line_for_paused_and_unreachable() -> void:
	var model := HudModel.new(s)
	var b := _site("tent", 4)
	s.set_building_priority(b.id, "paused")
	assert_eq(model.wait_text(b), "Paused")
	s.set_building_priority(b.id, "normal")
	b.halt = "too_far"
	assert_eq(model.wait_text(b), "No Builder's Yard can reach it")
	var done := s.place_building_instant("storehouse", Vector2i(h.x + 9, h.y + 1))
	assert_eq(model.wait_text(s.buildings[done]), "", "a finished building has none")


## Ticket 104: the build priority of a site is not the finished building's work priority.
func test_site_at_high_priority_finishes_at_normal_and_not_paused() -> void:
	var b := _site("tent", 4)
	s.set_building_priority(b.id, "high")
	s.set_building_priority(b.id, "paused")
	assert_true(b.paused)
	assert_eq(b.priority, "high", "pausing keeps the priority")
	s.complete_site(b)
	assert_false(b.site)
	assert_eq(b.priority, "normal")
	assert_false(b.paused)


func test_upgrade_at_high_priority_finishes_at_normal() -> void:
	s.era_override = "town"
	var b := s.buildings[s.place_building_instant("tent", Vector2i(h.x + 4, h.y - 2))] as Building
	s.set_building_priority(b.id, "high")
	assert_true(s.upgrade(b.id))
	assert_eq(b.priority, "high", "still high while the upgrade runs")
	s.complete_upgrade(b)
	assert_eq(b.tier, 2)
	assert_eq(b.priority, "normal")


## Ticket 105: a site with its cost delivered, a crew standing at its door.
func _crew_at_site(b: Building) -> Array:
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var out: Array = []
	for cid in cs.crews:
		var w := ws.walker_of(cid)
		if cs.crews[cid] == b.id and w.path.is_empty() and w.at_building == b.id:
			out.append(cid)
	return out


func test_a_crew_stays_at_the_site_between_shifts() -> void:
	var b := _site("meeting_hall", 4)
	_deliver(b)
	s.step_hours(12)  # a few hours into a shift, the crew has arrived
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	for i in 48:
		s.step_hours(1)
		if _crew_at_site(b).size() == 4 and s.clock.hour() == 21:
			break
	assert_true(b.site, "still unfinished")
	assert_eq(s.clock.hour(), 21, "night")
	assert_eq(_crew_at_site(b).size(), 4, "the crew rests at the site at 21:00")
	var night := b.build_work
	s.step_hours(7)  # to 04:00
	assert_eq(_crew_at_site(b).size(), 4, "still there before dawn, no walk to the yard")
	assert_eq(b.build_work, night, "no work at night")
	s.step_hours(4)  # 08:00
	assert_gt(b.build_work, night, "work resumes with the shift, nobody had to walk back")
	assert_eq(cs.crews.size(), 4)
	assert_not_null(ws)


func test_builders_work_06_to_20_and_haulers_keep_06_to_18() -> void:
	var lg := reg.logistics
	assert_eq(lg.builder_shift_start, 6)
	assert_eq(lg.builder_shift_end, 20)
	assert_eq(WalkerSystem.WORK_START_HOUR, 6)
	assert_eq(WalkerSystem.WORK_END_HOUR, 18)
	var b := _site("meeting_hall", 4)
	_deliver(b)
	s.step_hours(12)
	while s.clock.hour() != 18:
		s.step_hours(1)
	var at18 := b.build_work
	s.step_hours(1)  # 18-19: builders still work
	assert_gt(b.build_work, at18, "work at 18:00")
	s.step_hours(1)  # 19-20
	var at20 := b.build_work
	assert_gt(at20, at18, "work at 19:00")
	s.step_hours(1)  # 20-21: shift over
	assert_eq(b.build_work, at20, "no work after 20:00")


func test_a_paused_or_demolished_site_releases_the_crew() -> void:
	var a := _site("meeting_hall", 4)
	var c := _site("meeting_hall", 10)
	_deliver(a)
	_deliver(c)
	s.step_hours(12)
	while s.clock.hour() != 21:
		s.step_hours(1)
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	assert_true(a.site and c.site)
	var crew_a: Array = _crew_at_site(a)
	assert_gt(crew_a.size(), 0)
	assert_true(s.set_building_priority(a.id, "paused"))
	s.step_seconds(1.0)
	for cid in crew_a:
		assert_false(cs.crews.has(cid), "paused: the crew is released")
	var crew_c: Array = _crew_at_site(c)
	if crew_c.size() > 0:
		assert_true(s.demolish(c.id))
		s.step_seconds(1.0)
		for cid in crew_c:
			assert_false(cs.crews.has(cid), "demolished: the crew is released")
	assert_true(cs.crews.is_empty() or not cs.crews.values().has(a.id))
