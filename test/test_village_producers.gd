extends GutTest
## Ticket 20c: Fishing Dock and Quarry (design.md sections 9-10, 14 and 16 Village).
## Placement rules and output through the real Settlement command API, ProductionSystem and HaulingSystem.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	# Count what is hauled, not what the citizens eat.
	s.systems.erase(s.get_system(GrowthSystem))
	h = s.map.hearth_spot
	_strip()


## A cleared, road-connected strip east of the Hearth (the same patch test_hauling uses).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 2, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## A free land tile beside the road with a free land neighbour to its east. The neighbour becomes water, so the
## tile is shore. (-1, -1) when the strip has no such pair.
func _make_shore_spot() -> Vector2i:
	for dx in range(2, 16):
		for side in [-1, 1]:
			var t := Vector2i(h.x + dx, h.y + side)
			if s.road_at(Vector2i(h.x + dx, h.y)) == 0:
				continue
			if s.road_at(t) != 0 or s.building_at(t) != null:
				continue
			var n := t + Vector2i(1, 0)
			if not MapState.in_bounds(n.x, n.y) or s.road_at(n) != 0 or s.building_at(n) != null:
				continue
			var was := s.map.terrain_id_at(n.x, n.y)
			var tdef := reg.get_terrain(was)
			if was == "water" or (tdef != null and not tdef.buildable):
				continue
			s.set_terrain(n, "water")
			if s.can_place("fishing_dock", t)["ok"]:
				return t
			s.set_terrain(n, was)  # not a usable spot after all
	return Vector2i(-1, -1)


## A free, road-adjacent land tile turned to rock, where a Quarry can stand. (-1, -1) when none.
func _make_rock_spot() -> Vector2i:
	for dx in range(2, 16):
		for side in [-1, 1]:
			var t := Vector2i(h.x + dx, h.y + side)
			if s.road_at(Vector2i(h.x + dx, h.y)) == 0:
				continue
			if s.road_at(t) != 0 or s.building_at(t) != null:
				continue
			var was := s.map.terrain_id_at(t.x, t.y)
			s.set_terrain(t, "rock")
			if s.can_place("quarry", t)["ok"]:
				return t
			s.set_terrain(t, was)
	return Vector2i(-1, -1)


## Some tile where placing `def_id` fails with `reason` (a negative placement case).
func _spot_with_reason(def_id: String, reason: String) -> Vector2i:
	for y in range(MapState.HEIGHT):
		for x in range(MapState.WIDTH):
			var t := Vector2i(x, y)
			if s.can_place(def_id, t)["reason"] == reason:
				return t
	return Vector2i(-1, -1)


# AC1a: both data rows match the Village table, and the Dock's food is tagged for variety.
func test_data_matches_the_village_table() -> void:
	var dock := reg.get_building("fishing_dock")
	assert_not_null(dock)
	assert_eq([dock.era, dock.category], ["village", "food"])
	assert_eq([dock.size, dock.cost, dock.worker_slots], [Vector2i(1, 1), {"materials": 20}, 2])
	assert_eq(dock.placement_rule, "shore")
	assert_eq(dock.recipe.outputs, {"fish": 7.0})
	assert_eq(reg.get_good("fish").food_type, "fish", "the Dock's food counts as the fish type")
	var quarry := reg.get_building("quarry")
	assert_not_null(quarry)
	assert_eq([quarry.era, quarry.category], ["village", "materials"])
	assert_eq([quarry.size, quarry.cost, quarry.worker_slots], [Vector2i(1, 1), {"materials": 25}, 2])
	assert_eq(quarry.placement_rule, "on_rock")
	assert_eq(quarry.recipe.outputs, {"materials": 12.0})


# AC1b: the Dock places only on shore and the Quarry only on rock.
func test_dock_places_only_on_shore() -> void:
	var shore := _make_shore_spot()
	assert_ne(shore, Vector2i(-1, -1), "a shore spot in the strip")
	assert_true(s.can_place("fishing_dock", shore)["ok"])
	assert_gt(s.place_building_instant("fishing_dock", shore), -1)
	var inland := _spot_with_reason("fishing_dock", "needs_shore")
	assert_ne(inland, Vector2i(-1, -1), "a grass tile away from water")
	assert_false(s.can_place("fishing_dock", inland)["ok"])
	# Water is not land, so it fails before the shore rule.
	var water := shore + Vector2i(1, 0)
	assert_eq(s.map.terrain_id_at(water.x, water.y), "water")
	assert_eq(s.can_place("fishing_dock", water), {"ok": false, "reason": "water"})


func test_quarry_places_only_on_rock() -> void:
	var rock := _make_rock_spot()
	assert_ne(rock, Vector2i(-1, -1), "a rock spot in the strip")
	assert_true(s.can_place("quarry", rock)["ok"])
	assert_gt(s.place_building_instant("quarry", rock), -1)
	var inland := _spot_with_reason("quarry", "needs_rock")
	assert_ne(inland, Vector2i(-1, -1), "a grass tile that is not rock")
	assert_false(s.can_place("quarry", inland)["ok"])


# AC2a: two Dock workers make about 9 fish a day and the haulers move it into the Hearth.
func test_dock_output_reaches_the_hearth_through_hauling() -> void:
	var spot := _make_shore_spot()
	assert_ne(spot, Vector2i(-1, -1), "a shore spot in the strip")
	var dock: Building = s.buildings.get(s.place_building_instant("fishing_dock", spot))
	assert_not_null(dock)
	s.step_days(2)  # let the crew walk to work and fill a few door buffers
	var before := s.hearth.inventory.amount_of("fish")
	s.step_days(5)
	var per_day := (s.hearth.inventory.amount_of("fish") - before) / 5.0
	assert_between(per_day, 12.5, 15.5, "fish per day into the Hearth was %f" % per_day)
	assert_gt(s.totals().get("fish", 0.0), 0.0, "fish is a real stockpiled good")


# AC2b: two Quarry workers make about 12 materials a day (hauling-limited) and the haulers move it into the Hearth.
func test_quarry_output_reaches_the_hearth_through_hauling() -> void:
	var spot := _make_rock_spot()
	assert_ne(spot, Vector2i(-1, -1), "a rock spot in the strip")
	var quarry: Building = s.buildings.get(s.place_building_instant("quarry", spot))
	assert_not_null(quarry)
	s.step_days(2)
	var before := s.hearth.inventory.amount_of("materials")
	s.step_days(5)
	var per_day := (s.hearth.inventory.amount_of("materials") - before) / 5.0
	assert_between(per_day, 10.5, 15.0, "materials per day into the Hearth was %f" % per_day)
