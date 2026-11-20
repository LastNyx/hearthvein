extends GutTest

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ws: WalkerSystem
var hs: HaulingSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))  # these tests count food moved, not food eaten
	ws = s.get_system(WalkerSystem)
	hs = s.get_system(HaulingSystem)
	h = s.map.hearth_spot
	# Seed 42 has forest right east of the Hearth: clear a strip for the road and the buildings beside it
	# (the owned region ends at x = 95). Walking 1 tile takes about 0.4 game hours, so keep things close.
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 2, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## Places a building beside the road: north of it (side -1) or south (side 1), `dx` tiles east of the Hearth.
func _put(id: String, dx: int, side: int = -1) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(h.x + dx, h.y - def.size.y if side < 0 else h.y + 1)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	return s.buildings.get(bid)


func _food() -> float:
	return s.totals().get("food", 0.0)


func test_numbers_come_from_data() -> void:
	assert_eq(reg.logistics.door_buffer_cap, 40.0)
	assert_eq(reg.logistics.haul_load, 10.0)
	assert_eq(reg.logistics.input_buffer_days, 2.0)
	assert_eq(reg.get_building("hearth").hauler_slots, 2)
	assert_eq(reg.get_building("storehouse").hauler_slots, 2)


func test_forager_two_workers_add_about_15_food_per_day() -> void:
	var f := _put("forager", 4)
	_put("storehouse", 6)
	s.step_days(2)
	var before := _food()
	s.step_days(5)
	var per_day := (_food() - before) / 5.0
	assert_between(per_day, 13.0, 16.5, "food per day into storage was %f" % per_day)
	assert_not_null(f.door_buffer)


func test_door_buffer_full_stops_production_and_sets_flag() -> void:
	var f := _put("forager", 4)
	s.set_storage_filter(s.hearth.id, ["lumen"])  # nowhere to put food: nobody can haul it
	s.step_days(9)
	assert_almost_eq(f.door_buffer.amount_of("food"), 40.0, 0.001)
	assert_eq(f.halt, "door_full")
	assert_eq(s.events.log_of("production_halted").size(), 1)
	var seen := _food()
	s.step_days(1)
	assert_almost_eq(f.door_buffer.amount_of("food"), 40.0, 0.001, "stays at the cap")
	assert_eq(_food(), seen, "nothing was hauled")
	s.set_storage_filter(s.hearth.id, [])
	s.step_days(2)
	assert_lt(f.door_buffer.amount_of("food"), 40.0, "hauling frees the buffer")
	assert_eq(f.halt, "", "production resumed")


func test_haulers_pick_nearest_storehouse_with_room() -> void:
	_put("forager", 4)
	var near := _put("storehouse", 6)
	var far := _put("storehouse", 12)
	s.set_storage_filter(s.hearth.id, ["lumen"])
	s.step_days(3)
	assert_gt(near.inventory.amount_of("food"), 0.0)
	assert_eq(far.inventory.amount_of("food"), 0.0)
	# Fill the near one: the next load goes to the far one.
	near.inventory.add("wood", 400.0 - near.inventory.total())
	s.step_days(2)
	assert_gt(far.inventory.amount_of("food"), 0.0)


func test_two_haulers_never_take_the_same_units() -> void:
	var f := _put("forager", 4)
	_put("storehouse", 6)
	f.door_buffer.add("food", 5.0)
	s.set_building_priority(f.id, "paused")  # no new production, only the 5 units
	s.step_hours(6)
	s.step_seconds(1.0)
	var trips_now := 0
	for i in 40:
		trips_now = maxi(trips_now, hs.trips.size())
		s.step_seconds(0.5)
	assert_eq(trips_now, 1, "one trip for one load of 5")
	s.step_days(1)
	assert_almost_eq(f.door_buffer.amount_of("food"), 0.0, 0.001)
	assert_almost_eq(_food(), 65.0, 0.001, "all 5 arrived, none twice")


func test_haulers_are_controlled_only_while_on_a_trip() -> void:
	var f := _put("forager", 4)
	_put("storehouse", 6)
	f.door_buffer.add("food", 12.0)
	s.step_hours(6)
	var saw_controlled := false
	for i in 80:
		s.step_seconds(0.5)
		for cid in hs.trips:
			assert_true(ws.walker_of(cid).controlled)
			saw_controlled = true
	assert_true(saw_controlled)
	s.set_building_priority(f.id, "paused")
	s.step_hours(18)
	assert_eq(hs.trips.size(), 0)
	for cid in s.citizens:
		assert_false(ws.walker_of(cid).controlled, "citizen %d released" % cid)


func test_consumer_input_buffer_holds_two_days_of_need() -> void:
	var def := BuildingDef.new()
	def.id = "test_mill"
	def.era = "camp"
	def.category = "refining"
	def.worker_slots = 1
	def.recipe = RecipeDef.new()
	def.recipe.inputs = {"food": 2.0}
	def.recipe.outputs = {"meals": 1.0}
	reg.buildings["test_mill"] = def
	var mill := s._insert_building(def, Vector2i(h.x + 5, h.y + 1))
	assert_not_null(mill.input_buffer)
	assert_eq(HaulingSystem.input_need(reg, def), {"food": 4.0})
	s.set_building_priority(mill.id, "paused")  # keep it from eating the buffer
	_put("storehouse", 7)
	var start := _food()
	s.step_days(2)
	assert_almost_eq(mill.input_buffer.amount_of("food"), 4.0, 0.001)
	assert_almost_eq(_food() + 4.0, start, 0.001, "taken from storage, not made up")
	reg.buildings.erase("test_mill")


func test_woodcutter_turns_forest_into_stumps() -> void:
	var w := _put("woodcutter", 4)
	_put("storehouse", 6)
	for dy in [-4, -3]:  # 3-4 rows above the woodcutter: inside radius 4
		for dx in range(-2, 3):
			s.set_terrain(Vector2i(h.x + 4 + dx, h.y + dy), "forest")
	var before := s.events.log_of("terrain_changed").size()
	s.step_days(6)
	var stumps: Array[Vector2i] = []
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.terrain_id_at(x, y) == "stump":
				stumps.append(Vector2i(x, y))
	assert_gt(stumps.size(), 0)
	for t in stumps:
		assert_lte(Vector2(t - w.origin).length(), 4.0, "stump %s inside radius 4" % t)
	var made: float = s.totals().get("wood", 0.0) - 100.0 + w.door_buffer.amount_of("wood")
	assert_almost_eq(float(stumps.size()), made / reg.logistics.units_per_felled_tile, 3.0)
	assert_eq(s.events.log_of("terrain_changed").size() - before, stumps.size(), "one event per stump")



func _site_for(id: String, dx: int) -> Building:
	var bid := s.place_building(id, Vector2i(h.x + dx, h.y + 1))
	assert_true(bid >= 0, "site placed")
	return s.buildings[bid]


func test_site_last_delivery_may_be_below_min_pickup() -> void:
	var store := _put("storehouse", 7)
	var site := _site_for("woodcutter", 4)
	var cost: Dictionary = site.effective_cost()
	var need: float = float(cost["wood"])
	site.input_buffer.add("wood", need - 0.4)  # 0.4 left, min_pickup is 1.0
	store.inventory.add("wood", 50.0)
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_not_null(t, "a trip for the last 0.4 units")
	assert_eq(t.dst, site.id)
	assert_almost_eq(t.planned, 0.4, 0.001)


func test_site_is_served_before_a_full_door_buffer() -> void:
	var store := _put("storehouse", 7)
	var fg := _put("forager", 3, -1)
	fg.door_buffer.add("food", 15.0)
	var site := _site_for("woodcutter", 10)
	store.inventory.add("wood", 50.0)
	store.inventory.add("stone", 50.0)
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_not_null(t)
	assert_eq(t.dst, site.id, "the site comes before emptying the door buffer")
	assert_false(t.src_door)


func test_consumer_inputs_are_not_starved_by_a_busy_door_buffer() -> void:
	var store := _put("storehouse", 7)
	var fg := _put("forager", 3, -1)
	var saw := _put("sawmill", 10, -1)
	store.inventory.add("wood", 50.0)
	store.inventory.add("stone", 50.0)
	s.step_hours(1)
	fg.door_buffer.add("food", 15.0)
	var served := false
	for i in 2:
		var t: HaulingSystem.Trip = hs._plan(s, ws, -1 - i)  # the two ids take opposite turns
		assert_not_null(t)
		if t != null and t.dst == saw.id:
			served = true
	assert_true(served, "within two plans the sawmill's input is served though a door buffer waits")


func _fill_store(store: Building) -> void:
	for g in ["wood", "stone", "planks", "cut_stone", "tools", "lumen_cells", "lumen"]:
		store.inventory.add(g, 100.0)


func test_new_site_gets_its_goods_before_a_workshops_input_refill() -> void:
	var store := _put("storehouse", 7)
	var saw := _put("sawmill", 3, -1)  # older building, input buffer empty
	_fill_store(store)
	var site := _site_for("woodcutter", 10)
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_not_null(t)
	assert_eq(t.dst, site.id, "the site comes before the sawmill's input")
	assert_ne(t.dst, saw.id)


func test_sites_are_served_by_priority_then_oldest_and_paused_sites_get_nothing() -> void:
	var store := _put("storehouse", 7)
	_fill_store(store)
	var old_site := _site_for("woodcutter", 4)
	var new_site := _site_for("woodcutter", 10)
	s.step_hours(1)
	var t: HaulingSystem.Trip = hs._plan(s, ws, -1)
	assert_eq(t.dst, old_site.id, "same priority: the oldest first")
	s.set_building_priority(new_site.id, "high")
	t = hs._plan(s, ws, -1)
	assert_eq(t.dst, new_site.id, "a high-priority site goes before an older normal one")
	s.set_building_priority(old_site.id, "low")
	s.set_building_priority(new_site.id, "normal")
	t = hs._plan(s, ws, -1)
	assert_eq(t.dst, new_site.id, "low comes after normal")
	s.set_building_priority(new_site.id, "paused")
	t = hs._plan(s, ws, -1)
	assert_eq(t.dst, old_site.id, "the paused site is skipped")
	s.set_building_priority(old_site.id, "paused")
	t = hs._plan(s, ws, -1)
	assert_true(t == null or (t.dst != old_site.id and t.dst != new_site.id), "paused sites get nothing")
