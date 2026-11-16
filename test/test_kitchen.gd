extends GutTest
## Ticket 28c: Kitchen and meals (design.md sections 7, 11 and 16 Town, D38).
## Two different food types make meals through the haulers, and meals count as one food type for Spirit variety.

const SEED := 42
const FOODS: Array[String] = ["food", "crops", "fish", "greenhouse", "sky_produce"]

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	h = s.map.hearth_spot


## A cleared, road-connected strip east of the Hearth (the same patch test_refining uses).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## Places a finished building north of the road, `dx` tiles east of the Hearth.
func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(h.x + dx, h.y - def.size.y)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	var b: Building = s.buildings.get(bid)
	assert_true(b.connected, "%s is connected to the Hearth by road" % id)
	return b


# AC1a: the data row is the Town table's: 1x1, 30M 10P, 2 workers, two food types -> 3 meals at 4/worker/day.
func test_kitchen_data_matches_the_town_table() -> void:
	var k := reg.get_building("kitchen")
	assert_not_null(k)
	assert_eq([k.era, k.category], ["town", "refining"])
	assert_eq([k.size, k.cost, k.worker_slots], [Vector2i(1, 1), {"materials": 30, "planks": 10}, 2])
	assert_eq(k.upkeep_lumen, 0.0)
	assert_eq(k.recipe.outputs, {"meals": 4.0}, "4 meals per worker-day")
	assert_eq(k.recipe.inputs, {}, "the two types are flexible, not fixed goods")
	assert_eq(k.recipe.any_input_count, 2, "one food of type A + one of type B")
	assert_almost_eq(k.recipe.any_input_amount, 4.0 / 3.0, 0.0001, "4 meals = 4/3 batches of 1 + 1 -> 3")
	assert_eq(k.recipe.any_input_goods, FOODS as Array[String])
	assert_false(k.upgradable, "design section 10: refiners do not upgrade")
	assert_eq(reg.get_good("meals").food_type, "meals")


func test_kitchen_is_a_town_unlock() -> void:
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("kitchen"))
	s.era_override = "village"
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("kitchen"), "Town set only")


# AC1b: end to end. Haulers fill the Kitchen with several food types, it eats two different ones and its meals
# reach the Hearth's storage.
func test_kitchen_recipe_runs_end_to_end_through_haulers() -> void:
	s.systems.erase(s.get_system(GrowthSystem))  # nobody eats, so every food unit lost is the Kitchen's
	_strip()
	s.hearth.inventory.add("food", 100.0)
	s.hearth.inventory.add("crops", 100.0)
	s.hearth.inventory.add("fish", 80.0)
	var kitchen := _put("kitchen", 4)
	s.step_days(3)  # the crew walks to work and haulers fill the two-day input buffer
	var types := 0
	for g in FOODS:
		if kitchen.input_buffer.amount_of(g) > 1.0:
			types += 1
	assert_gte(types, 2, "haulers brought two food types")
	var before := {}
	for g in ["food", "crops", "fish"]:
		before[g] = s.hearth.inventory.amount_of(g)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var before_made := prod.produced_total
	s.step_days(5)
	var made := prod.produced_total - before_made
	assert_gt(s.hearth.inventory.amount_of("meals"), 0.0, "meals reached the Hearth's storage")
	assert_between(made / 5.0, 6.0, 9.6, "two workers x 4 meals a day, got %f" % (made / 5.0))
	var dropped: Array[String] = []
	for g in ["food", "crops", "fish"]:
		if before[g] - s.hearth.inventory.amount_of(g) > 1.0:
			dropped.append(g)
	assert_gte(dropped.size(), 2, "two different food types were used: %s" % [dropped])
	assert_eq(kitchen.halt, "", "the Kitchen kept running")
	assert_eq(s.totals().get("meals", 0.0), s.hearth.inventory.amount_of("meals"), "meals are a stored good")


# AC1c: one food type is not enough; a second one starts the Kitchen.
func test_kitchen_needs_two_different_food_types() -> void:
	s.systems.erase(s.get_system(HaulingSystem))  # fill the buffer by hand
	s.systems.erase(s.get_system(GrowthSystem))
	_strip()
	var kitchen := _put("kitchen", 4)
	kitchen.input_buffer.add("food", 20.0)
	_hour(14)  # mid-shift: the crew is at the door, so a halt means the recipe, not the clock
	assert_eq(kitchen.halt, "no_input", "one food type is not a meal")
	assert_eq(kitchen.door_buffer.amount_of("meals"), 0.0)
	kitchen.input_buffer.add("crops", 20.0)
	_hour(18)
	assert_gt(kitchen.door_buffer.amount_of("meals"), 0.0, "two types make meals")


# AC2: meals add one food type to the Spirit variety a Market delivers (design.md section 11).
func test_meals_add_one_food_type_to_spirit_variety() -> void:
	var ms := s.get_system(MarketSystem) as MarketSystem
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	var o := _spot_near("market", 10)
	assert_ne(o, Vector2i(-1, -1), "a Market spot near the Hearth")
	assert_gt(s.place_building_instant("market", o), -1)
	assert_true(ms.home_covered(s, s.hearth.id), "the Hearth is inside the Market's reach")
	assert_eq(ms.available_food_types(s), 1, "the start stock is one food type")
	assert_eq(sp.factor_value(s, "food_types"), 0.0)
	s.hearth.inventory.add("meals", 10.0)
	assert_eq(ms.available_food_types(s), 2, "meals count as one more type")
	assert_eq(sp.factor_value(s, "food_types"), 5.0, "one type beyond the first")


# Meals are food when eaten: 1 meal is 1 unit on the GrowthSystem's food list.
func test_meals_are_food_when_eaten() -> void:
	assert_true(GrowthSystem.food_goods(reg).has("meals"))
	assert_eq(GrowthSystem.food_type_of(reg, "meals"), "meals")


## Steps whole hours until the clock reads `hour` (the same hour today, or the next one).
func _hour(hour: int) -> void:
	var guard := 0
	while s.clock.hour() != hour and guard < 2 * GameClock.HOURS_PER_DAY:
		s.step_hours(1)
		guard += 1
	assert_eq(s.clock.hour(), hour, "reached %02d:00" % hour)


## First placeable origin for the Market scanning a square around the Hearth.
func _spot_near(def_id: String, radius: int) -> Vector2i:
	for y in range(h.y - radius, h.y + radius + 1):
		for x in range(h.x - radius, h.x + radius + 1):
			var o := Vector2i(x, y)
			if s.can_place(def_id, o, true)["ok"]:
				return o
	return Vector2i(-1, -1)
