extends GutTest

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _new() -> Settlement:
	return Settlement.new_game(SEED, reg)


func _free_spot(s: Settlement, w: int, h: int, skip: int = 0) -> Vector2i:
	var seen := 0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if s.can_place("storehouse", t)["ok"]:
				if seen == skip:
					return t
				seen += 1
	return Vector2i(-1, -1)


func _storehouse(s: Settlement, skip: int = 0) -> Building:
	var id := s.place_building_instant("storehouse", _free_spot(s, 2, 1, skip))
	assert_gt(id, -1)
	return s.buildings[id]


func test_start_stock_in_hearth() -> void:
	var s := _new()
	var t := s.totals()
	assert_eq(t["food"], 60.0)
	assert_eq(t["wood"], 100.0)
	assert_eq(t["lumen"], 10.0)
	assert_eq(s.gold, 0.0)
	assert_eq(s.hearth.inventory.amount_of("food"), 60.0)


func test_hearth_caps_each_good_at_150() -> void:
	var s := _new()
	var inv := s.hearth.inventory
	assert_eq(inv.add("food", 500.0), 90.0)
	assert_eq(inv.amount_of("food"), 150.0)
	assert_eq(inv.add("food", 1.0), 0.0)
	assert_eq(inv.add("planks", 500.0), 150.0)
	assert_eq(inv.free_for("lumen"), 140.0)


func test_storehouse_caps_total_at_400() -> void:
	var s := _new()
	var inv := _storehouse(s).inventory
	assert_eq(inv.add("food", 300.0), 300.0)
	assert_eq(inv.add("wood", 300.0), 100.0)
	assert_eq(inv.total(), 400.0)
	assert_eq(inv.add("lumen", 1.0), 0.0)
	assert_eq(inv.remove("food", 50.0), 50.0)
	assert_eq(inv.free_for("lumen"), 50.0)
	assert_eq(inv.remove("food", 1000.0), 250.0)


func test_storehouse_respects_filter() -> void:
	var s := _new()
	var b := _storehouse(s)
	assert_true(s.set_storage_filter(b.id, ["food", "lumen"]))
	assert_eq(b.inventory.add("wood", 10.0), 0.0)
	assert_eq(b.inventory.add("stone", 10.0), 0.0)
	assert_eq(b.inventory.add("food", 10.0), 10.0)
	assert_eq(b.inventory.add("lumen", 10.0), 10.0)
	assert_true(s.set_storage_filter(b.id, []))
	assert_eq(b.inventory.add("wood", 10.0), 10.0)
	assert_eq(b.inventory.add("stone", 10.0), 10.0)
	assert_false(s.set_storage_filter(b.id, ["nonsense"]))
	assert_false(s.set_storage_filter(999, ["food"]))


func test_lumen_leaks_three_percent_per_day_cells_do_not() -> void:
	var s := _new()
	# StorageSystem is registered by new_game (add_default_systems).
	s.hearth.inventory.add("lumen", 90.0)  # 100 total
	s.hearth.inventory.add("lumen_cells", 20.0)
	s.step_days(1)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 97.0, 0.0001)
	assert_eq(s.hearth.inventory.amount_of("lumen_cells"), 20.0)
	s.step_days(1)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 94.09, 0.0001)
	assert_eq(s.hearth.inventory.amount_of("lumen_cells"), 20.0)


func test_totals_equal_sum_of_inventories() -> void:
	var s := _new()
	var a := _storehouse(s)
	var b := _storehouse(s, 5)
	a.inventory.add("food", 30.0)
	b.inventory.add("food", 12.5)
	b.inventory.add("planks", 7.0)
	var t := s.totals()
	assert_eq(t["food"], 60.0 + 30.0 + 12.5)
	assert_eq(t["planks"], 7.0)
	assert_eq(t["wood"], 100.0)
	var sum := 0.0
	for g in t:
		sum += t[g]
	var inv_sum := 0.0
	for id in s.buildings:
		var inv: Inventory = s.buildings[id].inventory
		if inv != null:
			inv_sum += inv.total()
	assert_almost_eq(sum, inv_sum, 0.0001)


func test_demolish_storehouse_drops_its_goods() -> void:
	var s := _new()
	var a := _storehouse(s)
	a.inventory.add("food", 30.0)
	assert_true(s.demolish(a.id))
	assert_eq(s.totals()["food"], 60.0)


func test_nearest_storage_with_room() -> void:
	var s := _new()
	var near := _storehouse(s)
	var far := _storehouse(s, 400)
	assert_not_null(far)
	var from := near.origin + Vector2i(0, -1)
	assert_eq(s.find_storage_with_room("food", from), near)
	# Full or filtered out -> next nearest.
	near.inventory.add("wood", 400.0)
	near.inventory.add("stone", 400.0)
	assert_ne(s.find_storage_with_room("food", from), near)
	var h := s.find_storage_with_room("food", s.hearth.origin)
	assert_eq(h, s.hearth)
	s.hearth.inventory.add("food", 100.0)
	s.set_storage_filter(far.id, ["lumen"])
	s.set_storage_filter(s.hearth.id, ["lumen"])
	assert_null(s.find_storage_with_room("food", from))
