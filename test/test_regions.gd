extends GutTest
## Ticket 25: region buying and prices (design.md section 4, D34, D40).
##
## A region can be bought when it is 4-adjacent on the 4x4 region grid to an owned one, for gold at
## 50/100/200/350/500 and 600 for every later region (RegionsDef). The start region is owned for free.

const SEED := 42

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)


## First unowned region, in index order (regions 0..15).
func _unowned() -> int:
	for r in MapState.REGION_COUNT:
		if not s.map.is_region_owned(r):
			return r
	return -1


## First unowned region sharing an edge with an owned one.
func _adjacent_unowned() -> int:
	for r in MapState.REGION_COUNT:
		if s.map.is_region_owned(r):
			continue
		for n in MapState.region_neighbours(r):
			if s.map.is_region_owned(n):
				return r
	return -1


## First unowned region with no owned neighbour at all.
func _non_adjacent_unowned() -> int:
	for r in MapState.REGION_COUNT:
		if s.map.is_region_owned(r):
			continue
		var touches := false
		for n in MapState.region_neighbours(r):
			if s.map.is_region_owned(n):
				touches = true
				break
		if not touches:
			return r
	return -1


## Buys every region on a 4-connected path from the owned set to r, in order. False when the path cannot be bought.
func _own_region(r: int) -> bool:
	if s.map.is_region_owned(r):
		return true
	var prev := {}  # region -> region it was reached from (BFS from all owned regions)
	var queue: Array[int] = []
	for owned in MapState.REGION_COUNT:
		if s.map.is_region_owned(owned):
			queue.append(owned)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if cur == r:
			break
		for n in MapState.region_neighbours(cur):
			if s.map.is_region_owned(n) or prev.has(n):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(r):
		return false
	var path: Array[int] = []
	var c := r
	while not s.map.is_region_owned(c):
		path.push_front(c)
		c = prev[c]
	for region in path:
		if not s.buy_region(region):
			return false
	return true


# AC1 data: the price table is the design's sequence, in data.
func test_prices_come_from_data() -> void:
	assert_not_null(reg.regions, "data/regions/regions.tres is loaded")
	if reg.regions == null:
		return
	assert_eq(reg.regions.prices, [50, 100, 200, 350, 500] as Array[int])
	assert_eq(reg.regions.price_after, 600)


func test_region_grid_adjacency_is_4_way() -> void:
	assert_true(MapState.regions_adjacent(5, 6), "east")
	assert_true(MapState.regions_adjacent(5, 1), "north")
	assert_true(MapState.regions_adjacent(5, 9), "south")
	assert_true(MapState.regions_adjacent(5, 4), "west")
	assert_false(MapState.regions_adjacent(5, 10), "diagonals do not count")
	assert_false(MapState.regions_adjacent(5, 5), "a region is not adjacent to itself")
	assert_false(MapState.regions_adjacent(0, -1))
	assert_false(MapState.regions_adjacent(0, MapState.REGION_COUNT))
	assert_eq(MapState.region_neighbours(0), [1, 4] as Array[int], "a corner has two")
	assert_eq(MapState.region_neighbours(5), [1, 4, 6, 9] as Array[int], "a middle region has four")


func test_start_region_is_owned_and_cannot_be_bought() -> void:
	assert_true(s.map.is_region_owned(s.map.start_region))
	assert_eq(s.can_buy_region(s.map.start_region), {"ok": false, "reason": "owned"})
	s.gold = 10000.0
	assert_false(s.buy_region(s.map.start_region))
	assert_eq(s.gold, 10000.0, "nothing was spent")


func test_unknown_region_is_rejected() -> void:
	for r in [-1, MapState.REGION_COUNT]:
		assert_eq(s.can_buy_region(r), {"ok": false, "reason": "unknown"}, "region %d" % r)


# AC1: a region with no owned neighbour cannot be bought, even with plenty of gold.
func test_non_adjacent_region_cannot_be_bought() -> void:
	var r := _non_adjacent_unowned()
	assert_ne(r, -1, "a region with no owned neighbour")
	s.gold = 10000.0
	assert_eq(s.can_buy_region(r), {"ok": false, "reason": "not_adjacent"})
	assert_false(s.buy_region(r))
	assert_false(s.map.is_region_owned(r), "still locked")
	assert_eq(s.gold, 10000.0, "nothing was spent")
	assert_eq(s.events.log_of("region_bought").size(), 0, "no event for a refused purchase")


# AC1b: an adjacent region still waits for its gold.
func test_adjacent_region_needs_gold() -> void:
	var r := _adjacent_unowned()
	assert_ne(r, -1, "a region touching the owned start region")
	assert_eq(s.can_buy_region(r), {"ok": false, "reason": "gold"}, "the treasury is empty")
	assert_false(s.buy_region(r))
	assert_false(s.map.is_region_owned(r))
	s.gold = 49.0
	assert_eq(s.can_buy_region(r)["reason"], "gold", "49 is not the first price")
	s.gold = 50.0
	assert_eq(s.can_buy_region(r), {"ok": true, "reason": ""})
	assert_true(s.buy_region(r))
	assert_true(s.map.is_region_owned(r))
	assert_eq(s.gold, 0.0, "the 50 gold was spent")


# AC2: six regions cost 50, 100, 200, 350, 500 and 600, and the gold leaves the treasury.
func test_price_sequence_and_gold_spent() -> void:
	s.gold = 2000.0
	var start_gold := s.gold
	var prices: Array[int] = reg.regions.prices.duplicate()
	prices.append(reg.regions.price_after)  # the sixth region
	var spent := 0
	for i in prices.size():
		var r := _adjacent_unowned()
		assert_ne(r, -1, "an adjacent region for purchase %d" % (i + 1))
		assert_eq(s.next_region_price(), prices[i], "price of purchase %d" % (i + 1))
		assert_eq(s.regions_bought(), i, "start region excluded")
		assert_true(s.buy_region(r), "purchase %d buys region %d" % [i + 1, r])
		spent += prices[i]
		assert_almost_eq(s.gold, start_gold - float(spent), 0.001, "gold after purchase %d" % (i + 1))
	assert_eq(s.regions_bought(), prices.size())
	assert_eq(s.next_region_price(), reg.regions.price_after, "every further region costs 600")
	assert_eq(s.events.log_of("region_bought").size(), prices.size())
	assert_almost_eq(s.gold, start_gold - 1800.0, 0.001)


func test_purchase_event_carries_region_and_price() -> void:
	var r := _adjacent_unowned()
	s.gold = 50.0
	assert_true(s.buy_region(r))
	var e: Dictionary = s.events.log_of("region_bought")[0]["data"]
	assert_eq(e["region"], r)
	assert_eq(e["price"], 50)
	assert_eq(e["reward"], s.map.get_region_reward(r))


# AC1 from 25's notes: placement already refuses locked regions; buying one lifts the refusal.
func test_locked_region_refuses_placement_and_buying_lifts_it() -> void:
	var r := _adjacent_unowned()
	var rect := MapState.region_rect(r)
	var tile := Vector2i(-1, -1)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var t := Vector2i(x, y)
			if s.map.terrain_id_at(x, y) in ["grass", "fertile_soil"] and s.building_at(t) == null \
					and s.road_at(t) == Settlement.ROAD_NONE:
				tile = t
				break
		if tile.x >= 0:
			break
	assert_ne(tile, Vector2i(-1, -1), "a plain tile in the locked region")
	assert_eq(s.can_place("tent", tile, true)["reason"], "locked_region")
	s.gold = 50.0
	assert_true(s.buy_region(r))
	assert_true(s.can_place("tent", tile, true)["ok"], "placement is allowed once the region is owned")
