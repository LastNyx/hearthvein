extends GutTest
## Ticket 33: Apartment Block and Grand Bazaar (design.md sections 11 and 16 City).
## The two City rows, Apartment beds and its well need like the Rowhouse, and the Bazaar's gold plus its
## counts-as-a-food-type flag.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ms: MarketSystem
var sp: SpiritSystem
var h: Vector2i
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "city"
	ms = s.get_system(MarketSystem)
	sp = s.get_system(SpiritSystem)
	h = s.map.hearth_spot


## A cleared, road-connected strip east of the Hearth (the patch test_market and test_tax_office use).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 22):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## First placeable origin for `def_id` scanning the owned start region.
func _free_spot(def_id: String) -> Vector2i:
	var rect := MapState.region_rect(s.map.start_region)
	for y in range(rect.position.y, rect.end.y - 1):
		for x in range(rect.position.x, rect.end.x - 1):
			if s.can_place(def_id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Places a finished building north of the road, `dx` tiles east of the Hearth.
func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(h.x + dx, h.y - def.size.y)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	var b: Building = s.buildings.get(bid)
	assert_true(b.connected, "%s is connected to the Hearth by road" % id)
	return b


## A finished building inserted straight into the layout (no road, no cost), for the coverage query.
func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	s.buildings[b.id] = b
	s.structure_version += 1
	return b


func _workers(building_id: int) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == building_id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


## The Hearth holds one unit of each of three food types.
func _stock_three_types() -> void:
	s.hearth.inventory.add("food", 10.0)
	s.hearth.inventory.add("crops", 10.0)
	s.hearth.inventory.add("fish", 10.0)


# AC1a: the Apartment Block row is the City table's: 2x2, 90M 20G 30P 20S, 1 Lumen upkeep, houses 24, needs well.
func test_apartment_block_data_matches_the_city_table() -> void:
	var def := reg.get_building("apartment_block")
	assert_not_null(def)
	assert_eq([def.era, def.category], ["city", "housing"])
	assert_eq([def.size, def.cost],
			[Vector2i(2, 2), {"materials": 90, "gold": 20, "planks": 30, "cut_stone": 20}])
	assert_eq([def.worker_slots, def.upkeep_lumen, def.housing_beds], [0, 1.0, 24])
	assert_true(def.needs_water, "design row: needs well")
	assert_null(def.recipe)


# AC1b: placing an Apartment Block adds 24 beds, and it is a City unlock only.
func test_apartment_block_houses_24() -> void:
	var before := s.beds_total()
	var o := _free_spot("apartment_block")
	assert_ne(o, Vector2i(-1, -1), "a free spot in the start region")
	assert_gt(s.place_building_instant("apartment_block", o), -1)
	assert_eq(s.beds_total(), before + 24)
	s.era_override = "town"
	assert_eq(s.can_place("apartment_block", _free_spot("apartment_block")), {"ok": false, "reason": "era_locked"})
	assert_false(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "apartment_block"))


# AC1c: like the Rowhouse, an Apartment Block without a well costs Spirit water; a well in r8 clears it.
func test_apartment_block_needs_a_well_like_the_rowhouse() -> void:
	var home := _fake("apartment_block", Vector2i(230, 230))
	for cid in s.citizens:
		(s.citizens[cid] as Citizen).home_id = home.id
	assert_eq(_factor("water"), -reg.spirit.water_max, "every citizen lacks a well")
	_fake("well", Vector2i(222, 230))  # 8 tiles west: just in range
	assert_eq(_factor("water"), 0.0, "the Well serves the Apartment Block")


# AC2a: the Grand Bazaar row is the City table's: 3x2, 120M 30G 30P, 4 workers, 1 Lumen upkeep, +1.5 G/worker/day.
func test_grand_bazaar_data_matches_the_city_table() -> void:
	var def := reg.get_building("grand_bazaar")
	assert_not_null(def)
	assert_eq([def.era, def.category], ["city", "gold"])
	assert_eq([def.size, def.cost],
			[Vector2i(3, 2), {"materials": 120, "gold": 30, "planks": 30}])
	assert_eq([def.worker_slots, def.upkeep_lumen], [4, 1.0])
	assert_eq(def.gold_per_worker_day, 1.5)
	assert_true(def.counts_as_food_type, "design row: counts as a food type")
	assert_null(def.recipe, "gold is a counter, not a recipe output")
	s.era_override = "town"
	assert_false(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "grand_bazaar"))


# AC2b: each assigned worker brings 1.5 gold a day; a paused Bazaar pays nothing.
func test_grand_bazaar_pays_1_5_gold_per_worker_per_day() -> void:
	s.systems.erase(s.get_system(GrowthSystem))  # fixed population, exact expected gold
	_strip()
	s.hearth.inventory.add("lumen", 100.0)  # its 1 Lumen upkeep is hauled from the Hearth
	s.hearth.inventory.add("food", 200.0)
	var b := _put("grand_bazaar", 4)
	assert_eq(_workers(b.id), 4, "all four worker slots are filled")
	s.step_days(3)  # the crew walks to work and haulers fill the upkeep buffer
	assert_true((s.get_system(UpkeepSystem) as UpkeepSystem).is_paid(b.id), "upkeep is paid")
	var before := s.gold
	s.step_days(1)
	assert_almost_eq(s.gold - before, 1.5 * 4.0, 0.001, "four workers x 1.5 gold")
	b.paused = true
	before = s.gold
	s.step_days(1)
	assert_almost_eq(s.gold, before, 0.001, "a paused Bazaar pays nothing")


# AC2c: a staffed Bazaar counts as one more food type than the homes can reach; paused or unstaffed it counts none.
func test_grand_bazaar_counts_as_one_food_type_while_staffed() -> void:
	_stock_three_types()
	assert_eq(ms.available_food_types(s), 1, "no Market in reach: one type")
	assert_eq(_factor("food_types"), 0.0)
	_strip()
	var b := _put("grand_bazaar", 4)
	assert_gt(_workers(b.id), 0, "the Bazaar is staffed")
	assert_eq(ms.available_food_types(s), 2, "one reachable type plus the Bazaar")
	assert_eq(_factor("food_types"), 5.0, "one extra type is +5 Spirit")
	b.paused = true
	assert_eq(ms.available_food_types(s), 1, "a paused Bazaar is no food type")
	assert_eq(_factor("food_types"), 0.0)


func test_unstaffed_grand_bazaar_counts_as_no_food_type() -> void:
	_stock_three_types()
	var o := _free_spot("grand_bazaar")
	assert_ne(o, Vector2i(-1, -1), "a free spot in the start region")
	var id := s.place_building_instant("grand_bazaar", o)
	assert_true(id >= 0)
	assert_false(s.buildings[id].connected, "no road reaches this Bazaar")
	assert_eq(_workers(id), 0)
	assert_eq(ms.available_food_types(s), 1, "no workers, no extra food type")


# A Market in reach still stacks its stored types on top of the Bazaar's one.
func test_grand_bazaar_stacks_with_a_market_in_reach() -> void:
	var market_o := _free_spot("market")
	assert_ne(market_o, Vector2i(-1, -1), "a free Market spot")
	assert_gt(s.place_building_instant("market", market_o), -1)
	assert_true(ms.home_covered(s, s.hearth.id), "the Hearth is inside the Market's reach")
	_stock_three_types()
	assert_eq(ms.available_food_types(s), 3, "three stored types in reach")
	_strip()
	s.hearth.inventory.add("food", 200.0)
	var b := _put("grand_bazaar", 4)
	assert_gt(_workers(b.id), 0)
	assert_eq(ms.available_food_types(s), 4, "three stored types plus the Bazaar")
