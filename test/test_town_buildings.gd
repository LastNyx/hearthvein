extends GutTest
## Ticket 27b: Rowhouse and Greenhouse (design.md sections 14 and 16 Town).
## The two Town data rows, housing beds through the real command API, and the Greenhouse's Dimming-proof output.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const AUTUMN := 2 * GameClock.DAYS_PER_SEASON  # total day of autumn day 1
const WINTER := 3 * GameClock.DAYS_PER_SEASON

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
	s.planet_health_override = 100.0


func _free_spot(def_id: String) -> Vector2i:
	for y in range(MapState.HEIGHT - 3):
		for x in range(MapState.WIDTH - 3):
			if s.can_place(def_id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A cleared, road-connected strip east of the Hearth (the same patch test_sawmill uses).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## Runs the clock to `day` (keeping everyone fed, so the population and its light need stay put).
func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


# AC1a: the Rowhouse row is the Town table's: 2x1, 40M 5G 10P, no upkeep, houses 10.
func test_rowhouse_data_matches_the_town_table() -> void:
	var def := reg.get_building("rowhouse")
	assert_not_null(def)
	assert_eq([def.era, def.category], ["town", "housing"])
	assert_eq([def.size, def.cost], [Vector2i(2, 1), {"wood": 28, "stone": 12, "gold": 5, "planks": 10}])
	assert_eq([def.worker_slots, def.upkeep_lumen], [0, 0.0])
	assert_eq(def.housing_beds, 10)


# AC1b: placing a Rowhouse adds ten beds, and it is a Town unlock only.
func test_rowhouse_houses_ten() -> void:
	var before := s.beds_total()
	var o := _free_spot("rowhouse")
	assert_true(o.x >= 0, "a free spot for the Rowhouse")
	assert_gt(s.place_building_instant("rowhouse", o), -1)
	assert_eq(s.beds_total(), before + 10)
	assert_false(s.can_place("rowhouse", o, false)["ok"], "the tile is taken now")
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("rowhouse"))
	s.era_override = "village"
	assert_eq(s.can_place("rowhouse", _free_spot("rowhouse")), {"ok": false, "reason": "era_locked"})
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("rowhouse"), "Town set only")


# AC2a: the Greenhouse row is the Town table's: 2x1, 3 workers, 1 Lumen upkeep, +16 food, Dimming-proof.
func test_greenhouse_data_matches_the_town_table() -> void:
	var def := reg.get_building("greenhouse")
	assert_not_null(def)
	assert_eq([def.era, def.category], ["town", "food"])
	assert_eq([def.size, def.cost],
			[Vector2i(2, 1), {"wood": 35, "stone": 15, "gold": 10, "lumen": 10, "planks": 10}])
	assert_eq([def.worker_slots, def.upkeep_lumen], [3, 1.0])
	assert_eq(def.recipe.inputs, {})
	assert_eq(def.recipe.outputs, {"greenhouse": 16.0})
	assert_eq(def.dimming_factor, 1.0, "design section 14: Greenhouse unaffected")
	assert_eq(reg.get_good("greenhouse").food_type, "greenhouse", "its own food type (section 7)")
	assert_true(GrowthSystem.food_goods(reg).has("greenhouse"), "citizens can eat it")


# AC2b: the Greenhouse makes food through the real systems and the haulers bring it to the Hearth.
func test_greenhouse_food_reaches_storage() -> void:
	_strip()
	s.hearth.inventory.add("food", 200.0)
	s.hearth.inventory.add("lumen", 150.0)  # the 1 Lumen upkeep a day comes from the Hearth
	var o := Vector2i(h.x + 4, h.y - 1)
	var gh: Building = s.buildings.get(s.place_building_instant("greenhouse", o))
	assert_not_null(gh)
	assert_true(gh.connected, "the Greenhouse door sits on the road")
	s.step_days(1)  # the crew walks to work and the haulers fill the upkeep buffer
	var before := s.hearth.inventory.amount_of("greenhouse")
	s.step_days(2)  # (a 5 s game hour: walks are short and the haulers keep up, so the Hearth is full from day 3 on)
	var per_day := (s.hearth.inventory.amount_of("greenhouse") - before) / 2.0
	assert_between(per_day, 4.0, 50.0, "three workers x 16 food a day, got %f" % per_day)
	assert_gt(s.totals().get("greenhouse", 0.0), 0.0, "greenhouse food is a real stored good")
	assert_true(["", "door_full"].has(gh.halt), "the Greenhouse kept running (at 48 food a day a full door buffer is the only halt)")


# AC2c: during a Dimming a plain Farm runs at x0.5 but the Greenhouse is unaffected.
func test_greenhouse_ignores_the_dimming_crop_penalty() -> void:
	var gh := Building.new()
	gh.def = reg.get_building("greenhouse")
	var farm := Building.new()
	farm.def = reg.get_building("farm")
	_to_day(WINTER - 1)
	assert_false(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, gh), 1.0)
	assert_eq(DimmingSystem.output_modifier(s, farm), 1.0)
	_to_day(WINTER)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, farm), 0.5, "plain farms lose half their output")
	assert_eq(DimmingSystem.output_modifier(s, gh), 1.0, "the Greenhouse is Dimming-proof")
