extends GutTest
## Ticket 23: Market gold and market-gated food variety (design.md sections 11 and 16 Village).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ms: MarketSystem
var sp: SpiritSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	ms = s.get_system(MarketSystem)
	sp = s.get_system(SpiritSystem)
	h = s.map.hearth_spot


## A cleared, road-connected strip east of the Hearth (the patch test_hauling and test_village_farm use).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## First placeable origin for `def_id` scanning a square around `center`; -1 when there is none.
func _spot_near(def_id: String, center: Vector2i, radius: int) -> Vector2i:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var o := Vector2i(x, y)
			if s.can_place(def_id, o, true)["ok"]:
				return o
	return Vector2i(-1, -1)


## First placeable origin scanning the owned start region.
func _spot_in_region(def_id: String) -> Vector2i:
	var rect := MapState.region_rect(s.map.start_region)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if s.can_place(def_id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## First placeable origin in the owned start region whose footprint the home is NOT within market range of.
func _spot_out_of_reach(def_id: String, home: Building) -> Vector2i:
	var def := reg.get_building(def_id)
	var rect := MapState.region_rect(s.map.start_region)
	for y in range(rect.position.y, rect.end.y - def.size.y + 1):
		for x in range(rect.position.x, rect.end.x - def.size.x + 1):
			var o := Vector2i(x, y)
			if not s.can_place(def_id, o, true)["ok"]:
				continue
			var probe := Building.new()
			probe.def = def
			probe.origin = o
			if not MarketSystem.market_covers(probe, home):
				return o
	return Vector2i(-1, -1)


func _workers(building_id: int) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == building_id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


## The Hearth holds one unit of each of three food types, so a Market in reach would mean three types.
func _stock_three_types() -> void:
	s.hearth.inventory.add("food", 10.0)  # forage
	s.hearth.inventory.add("crops", 10.0)
	s.hearth.inventory.add("fish", 10.0)


# AC1a: the data row matches the Village table and the reach number is in data.
func test_market_data_matches_the_village_row() -> void:
	var m := reg.get_building("market")
	assert_not_null(m)
	assert_eq([m.era, m.category], ["camp", "gold"])
	assert_eq([m.size, m.cost, m.worker_slots], [Vector2i(2, 2), {"materials": 40}, 2])
	assert_eq(m.gold_per_worker_day, 1.0)
	assert_eq(m.market_reach, 12, "design gives no reach; ticket 23 chose 12 tiles")
	assert_null(m.recipe, "gold is a counter, not a recipe output")


func test_market_is_a_camp_building() -> void:
	var o := _spot_in_region("market")
	assert_ne(o, Vector2i(-1, -1), "a free spot in the start region")
	s.era_override = ""
	assert_true(s.can_place("market", o)["ok"], "Camp has a gold source")
	assert_true(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "market"))


# AC1b: the food types the Market gate needs exist on the right goods.
func test_food_type_data() -> void:
	assert_eq(reg.get_good("food").food_type, "forage", "Forager food is forage")
	assert_eq(reg.get_good("crops").food_type, "crops", "Farm food is crops")
	assert_eq(reg.get_good("fish").food_type, "fish")
	assert_eq(reg.get_building("forager").recipe.outputs, {"food": 8.0})
	assert_eq(reg.get_building("farm").recipe.outputs, {"crops": 4.0})


# AC2: each assigned worker brings one gold a day; paused or unstaffed Markets pay nothing.
func test_market_pays_gold_per_worker_per_day() -> void:
	_strip()
	var o := Vector2i(h.x + 4, h.y - 2)
	var id := s.place_building_instant("market", o)
	assert_true(id >= 0, "market placed beside the road")
	var b: Building = s.buildings[id]
	assert_true(b.connected, "the market is road-connected")
	assert_eq(_workers(id), 2, "both worker slots are filled")
	assert_eq(s.gold, 0.0)
	s.step_days(1)
	assert_almost_eq(s.gold, 2.0, 0.001, "two workers, one gold each")
	s.step_days(1)
	assert_almost_eq(s.gold, 4.0, 0.001)
	assert_true(s.set_building_priority(id, "paused"))
	s.step_days(1)
	assert_almost_eq(s.gold, 4.0, 0.001, "a paused Market pays nothing")


func test_unstaffed_market_pays_nothing() -> void:
	var o := _spot_in_region("market")
	assert_ne(o, Vector2i(-1, -1), "a free spot in the start region")
	var id := s.place_building_instant("market", o)
	assert_true(id >= 0)
	assert_false(s.buildings[id].connected, "no road reaches this market")
	assert_eq(_workers(id), 0, "so nobody is assigned to it")
	s.step_days(1)
	assert_eq(s.gold, 0.0)


# AC1c: reach is Chebyshev from the Market footprint: 12 tiles counts, 13 does not.
func test_reach_is_chebyshev_from_the_footprint() -> void:
	var market := Building.new()
	market.def = reg.get_building("market")
	market.origin = Vector2i(10, 10)  # footprint 10..11 in both axes
	var home := Building.new()
	home.def = reg.get_building("cottage")
	home.origin = Vector2i(23, 10)  # 12 tiles east of the footprint's east edge
	assert_true(MarketSystem.market_covers(market, home), "12 tiles is in reach")
	home.origin = Vector2i(24, 10)
	assert_false(MarketSystem.market_covers(market, home), "13 tiles is out of reach")
	home.origin = Vector2i(23, 23)  # 12 east, 12 south: still Chebyshev 12
	assert_true(MarketSystem.market_covers(market, home))
	home.origin = Vector2i(24, 23)
	assert_false(MarketSystem.market_covers(market, home))


# AC1: a home's variety is gated by a Market in reach; without one it counts at most one type.
# The Hearth itself is a home (8 beds), so the starting population lives there.
func test_without_a_market_home_counts_one_type() -> void:
	assert_eq(s.homeless_count(), 0, "the starting citizens live in the Hearth")
	_stock_three_types()
	assert_eq(ms.available_food_types(s), 1, "three types stored, one reachable")
	assert_eq(_factor("food_types"), 0.0, "no Market in reach, no variety bonus")


func test_market_in_reach_counts_all_stored_types() -> void:
	var market_o := _spot_near("market", h, 10)
	assert_ne(market_o, Vector2i(-1, -1), "a Market spot near the Hearth")
	var market_id := s.place_building_instant("market", market_o)
	assert_true(market_id >= 0)
	assert_true(ms.home_covered(s, s.hearth.id), "the Hearth is inside the Market's reach")
	_stock_three_types()
	assert_eq(ms.available_food_types(s), 3)
	assert_eq(_factor("food_types"), 10.0, "three types, two beyond the first")


func test_market_out_of_reach_gives_no_variety() -> void:
	var market_o := _spot_out_of_reach("market", s.hearth)
	assert_ne(market_o, Vector2i(-1, -1), "a Market spot beyond the Hearth's reach")
	var market_id := s.place_building_instant("market", market_o)
	assert_true(market_id >= 0)
	assert_false(ms.home_covered(s, s.hearth.id), "Market %s vs hearth %s is out of reach" % [market_o, h])
	_stock_three_types()
	assert_eq(ms.available_food_types(s), 1)
	assert_eq(_factor("food_types"), 0.0)


## Only citizens with a home the Market serves carry variety; a homeless citizen never does.
func test_homeless_citizens_do_not_count_variety() -> void:
	_stock_three_types()
	var market_o := _spot_near("market", h, 10)
	assert_ne(market_o, Vector2i(-1, -1), "a Market spot near the Hearth")
	assert_gt(s.place_building_instant("market", market_o), -1)
	for c in s.citizens.values():
		(c as Citizen).home_id = -1  # make them homeless without asking the JobSystem to rehouse them
	assert_eq(ms.available_food_types(s), 1, "a Market with no homes in reach")
	assert_eq(_factor("food_types"), 0.0)
