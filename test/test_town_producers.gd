extends GutTest
## Ticket 27c: Workshop and Lumen Pump (design.md sections 12, 13 and 16 Town).
## The two Town data rows, the Workshop's 2 Lumen -> 3 materials through haulers, and the Pump's blight.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY

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


## A cleared, road-connected strip east of the Hearth (the same patch test_sawmill uses).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## The first vein tile a Lumen Pump may stand on.
func _vein_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if s.map.terrain_id_at(x, y) == "lumen_vein" and s.can_place("lumen_pump", t)["ok"]:
				return t
	return Vector2i(-1, -1)


## Lays road tiles from the Hearth's road to a tile beside `target`, so a building on `target` is connected.
## Breadth-first over free, road-placeable land (roads are free in the sim API). False when no such route exists.
func _road_to(target: Vector2i) -> bool:
	var start := Vector2i(h.x + 2, h.y)
	if s.road_at(start) == 0:
		return false
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var goal := Vector2i(-1, -1)
	while head < queue.size() and goal.x < 0:
		var c: Vector2i = queue[head]
		head += 1
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or n == target or not MapState.in_bounds(n.x, n.y):
				continue
			if s.road_at(n) == 0 and not s.can_place_road(n):
				continue
			prev[n] = c
			if absi(n.x - target.x) + absi(n.y - target.y) == 1:
				goal = n
				break
			queue.append(n)
	if goal.x < 0:
		return false
	var t := goal
	while t != start:
		s.place_road(t)
		t = prev[t]
	return true


## A placeable vein a laid road reaches. (-1, -1) when there is none.
func _connected_pump_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if s.map.terrain_id_at(x, y) != "lumen_vein" or not s.can_place("lumen_pump", t)["ok"]:
				continue
			if _road_to(t):
				return t
	return Vector2i(-1, -1)


# AC1a: both rows are the Town table's.
func test_data_matches_the_town_table() -> void:
	var shop := reg.get_building("workshop")
	assert_not_null(shop)
	assert_eq([shop.era, shop.size, shop.cost], ["town", Vector2i(2, 1), {"materials": 50, "gold": 10}])
	assert_eq([shop.worker_slots, shop.upkeep_lumen], [3, 1.0])
	assert_eq(shop.recipe.inputs, {"lumen": 2.0}, "2 Lumen per worker-day")
	assert_eq(shop.recipe.outputs, {"materials": 3.0}, "3 materials per worker-day")
	assert_false(shop.upgradable, "design section 10: refiners do not upgrade")
	var pump := reg.get_building("lumen_pump")
	assert_not_null(pump)
	assert_eq([pump.era, pump.category, pump.size], ["town", "lumen", Vector2i(1, 1)])
	assert_eq(pump.cost, {"materials": 60, "gold": 15, "planks": 10})
	assert_eq([pump.worker_slots, pump.upkeep_lumen], [3, 0.0])
	assert_eq(pump.placement_rule, "on_vein")
	assert_eq(pump.recipe.inputs, {})
	assert_eq(pump.recipe.outputs, {"lumen": 7.0})
	assert_eq([pump.blight_radius, pump.blight_period_days], [4, 3])
	assert_true(pump.vein_extractor and pump.health_per_day < 0.0, "section 13: a vein extractor")


# AC1b: haulers bring Lumen in, the Workshop makes 3 materials per 2 Lumen, and the materials reach storage.
func test_workshop_turns_hauled_lumen_into_materials() -> void:
	s.systems.erase(s.get_system(StorageSystem))  # no 1%/day Lumen leak: it would blur the 2:3 ratio
	_strip()
	s.hearth.inventory.add("lumen", 120.0)
	s.hearth.inventory.add("food", 200.0)  # no starving workers skewing the rate
	var o := Vector2i(h.x + 4, h.y - 1)
	var shop: Building = s.buildings.get(s.place_building_instant("workshop", o))
	assert_not_null(shop)
	assert_true(shop.connected, "the Workshop door sits on the road")
	s.step_days(3)  # the crew walks to work and haulers fill the two-day input buffer
	assert_gt(shop.input_buffer.amount_of("lumen"), 8.0, "haulers keep the Workshop in Lumen")
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us.is_paid(shop.id), "the day's Lumen upkeep was paid")
	var before_m := s.hearth.inventory.amount_of("materials")
	var before_l := s.hearth.inventory.amount_of("lumen")
	s.step_days(5)
	var materials := s.hearth.inventory.amount_of("materials") - before_m
	var lumen := before_l - s.hearth.inventory.amount_of("lumen")
	assert_gt(materials, 0.0, "materials reached the Hearth's storage")
	assert_between(materials / 5.0, 7.0, 9.6, "three workers x 3 materials a day, got %f" % (materials / 5.0))
	# 3 materials per 2 Lumen of recipe input, plus the 1 Lumen a day of upkeep.
	assert_between(materials / lumen, 1.2, 1.4, "%f materials per Lumen" % (materials / lumen))
	assert_eq(shop.halt, "", "the Workshop kept running")


# AC2a: the Pump only fits on a vein.
func test_lumen_pump_places_only_on_a_vein() -> void:
	var vein := _vein_spot()
	assert_ne(vein, Vector2i(-1, -1), "a vein on seed 42")
	assert_true(s.can_place("lumen_pump", vein)["ok"])
	assert_gt(s.place_building_instant("lumen_pump", vein), -1)
	var inland := Vector2i(-1, -1)
	for y in 2:
		for x in 2:
			var t := Vector2i(h.x + 3 + x, h.y - 3 + y)
			if inland.x < 0 and s.can_place("lumen_pump", t)["reason"] == "needs_vein":
				inland = t
	assert_ne(inland, Vector2i(-1, -1), "grass near the Hearth")
	assert_false(s.can_place("lumen_pump", inland)["ok"])


# AC2b: a working Pump blights one tile every 3 days inside radius 4, and stops when demolished.
func test_lumen_pump_blights_radius_4_every_3_days() -> void:
	var vein := _vein_spot()
	assert_ne(vein, Vector2i(-1, -1), "a vein on seed 42")
	var id := s.place_building_instant("lumen_pump", vein)
	assert_gt(id, -1)
	var pump: Building = s.buildings[id]
	assert_eq(BlightSystem.count(s), 0)
	s.step_days(2)
	assert_eq(BlightSystem.count(s), 0, "nothing before the 3rd day")
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 1)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_blighted(x, y):
				var d := Vector2i(x, y) - pump.origin
				assert_true(d.x * d.x + d.y * d.y <= 16, "inside radius 4")
	assert_eq(BlightSystem.count(s), 1)
	s.step_days(3)
	assert_eq(BlightSystem.count(s), 2, "one more tile on day 6")
	assert_true(s.demolish(id))
	s.step_days(9)
	assert_eq(BlightSystem.count(s), 2, "removed: no more spread, old blight stays")


# AC2c: with a road to it, the Pump's crew makes Lumen into its door buffer (7 per worker-day, data).
func test_lumen_pump_produces_lumen_when_connected() -> void:
	var vein := _connected_pump_spot()
	assert_ne(vein, Vector2i(-1, -1), "a vein a road reaches")
	var id := s.place_building_instant("lumen_pump", vein)
	assert_gt(id, -1)
	var pump: Building = s.buildings[id]
	assert_true(pump.connected, "the pump door sits on the road")
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var before := prod.produced_total
	s.step_days(4)
	assert_gt(prod.produced_total - before, 0.0, "the pump made Lumen")
	assert_gt(s.totals().get("lumen", 0.0) + pump.door_buffer.amount_of("lumen"), 0.0)
	assert_true(pump.halt == "" or pump.halt == "door_full", "waiting for haulers, not idle: %s" % pump.halt)
