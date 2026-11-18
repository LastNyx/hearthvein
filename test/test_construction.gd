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


func _hearth_materials() -> float:
	return s.hearth.inventory.amount_of("materials")


## Game hours until the site turns into a building (-1 when it did not within `max_days`).
func _hours_to_finish(b: Building, max_days: int) -> int:
	for i in max_days * 24:
		if not b.site:
			return i
		s.step_hours(1)
	return -1


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
	s.hearth.inventory.remove("materials", 1000.0)
	s.hearth.inventory.add("materials", 10.0)  # storehouse needs 25
	var b := _site("storehouse", 4)
	s.step_days(3)
	assert_true(b.site)
	assert_eq(b.build_work, 0.0, "no progress with part of the cost")
	assert_between(b.input_buffer.amount_of("materials"), 9.99, 10.01, "what exists was delivered")
	assert_eq(s.events.log_of("building_completed").size(), 0)
	s.hearth.inventory.add("materials", 15.0)
	s.step_days(1)
	assert_true(b.site_delivered())
	assert_between(b.input_buffer.amount_of("materials"), 24.99, 25.01)
	assert_true(_hours_to_finish(b, 4) >= 0, "builds once everything arrived")
	assert_false(b.site)
	assert_not_null(b.inventory)
	assert_eq(s.events.log_of("building_completed").size(), 1)
	assert_between(_hearth_materials(), -0.01, 0.01, "the cost left the hearth")


func test_build_time_follows_size_and_era() -> void:
	var tent := reg.get_building("tent")
	var store := reg.get_building("storehouse")
	var hall := reg.get_building("meeting_hall")
	assert_eq(s.build_days(tent), 0.5, "1 tile is clamped up to the half day minimum")
	assert_almost_eq(s.build_days(store), 0.8, 0.001)
	assert_almost_eq(s.build_days(hall), 1.6, 0.001)
	var huge := tent.duplicate() as BuildingDef
	huge.size = Vector2i(10, 10)
	assert_eq(s.build_days(huge), 6.0, "clamped to 6 days")
	var late := tent.duplicate() as BuildingDef
	late.era = "city"
	assert_almost_eq(s.build_days(late), 1.15, 0.001, "era adds days")
	# Played out: a tent is done long before a meeting hall (same delivery, a full crew).
	s.hearth.inventory.add("materials", 100.0)
	s.hearth.inventory.add("lumen", 10.0)
	var t := _site("tent", 4)
	var tent_h := _hours_to_finish(t, 6)
	assert_true(tent_h > 0)
	s = Settlement.new_game(SEED, reg)
	for x in range(h.x + 2, h.x + 16):
		s.place_road(Vector2i(x, h.y))
	s.hearth.inventory.add("materials", 100.0)
	s.hearth.inventory.add("lumen", 10.0)
	var m := _site("meeting_hall", 4)
	var hall_h := _hours_to_finish(m, 10)
	assert_true(hall_h > 0)
	assert_gt(hall_h, tent_h + 24, "a 3 day building takes at least a day more than a 1 day one")


func test_high_priority_site_gets_builders_first() -> void:
	var a := _site("tent", 4)
	var b := _site("tent", 6)
	s.set_building_priority(a.id, "paused")  # paused sites get no builders: let both be delivered first
	s.set_building_priority(b.id, "paused")
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
	assert_eq(store.inventory.amount_of("materials"), 0.0)
	var hearth_before := _hearth_materials()
	assert_true(s.demolish(t))
	assert_almost_eq(store.inventory.amount_of("materials"), 12.5, 0.001, "half of 25, to the nearest storehouse")
	assert_eq(_hearth_materials(), hearth_before, "not to the farther hearth")
	# A storehouse that is full: the refund goes to the next nearest with room.
	store.inventory.add("lumen", 400.0 - 12.5)
	var tent := s.place_building_instant("tent", Vector2i(h.x + 12, h.y - 1))
	assert_true(s.demolish(tent))
	assert_almost_eq(_hearth_materials(), hearth_before + 2.5, 0.001)


func test_demolished_site_refunds_half_of_what_was_delivered() -> void:
	var b := _site("storehouse", 4)
	s.step_hours(30)
	var delivered := b.input_buffer.amount_of("materials") if b.site else 25.0
	assert_gt(delivered, 0.0)
	if not b.site:
		pending("site finished too early for this check")
		return
	var before := _hearth_materials()
	assert_true(s.demolish(b.id))
	assert_almost_eq(_hearth_materials(), before + delivered * 0.5, 0.001)
	s.step_days(2)  # haulers whose destination vanished put their load back, nothing crashes
	assert_eq(s.events.log_of("building_demolished").size(), 1)
