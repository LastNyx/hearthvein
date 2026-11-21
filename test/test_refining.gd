extends GutTest
## Ticket 28: Mason and cut stone (design.md sections 7 and 16 Town, D38).
## The data row and the recipe end to end: haulers bring stone, the Mason cuts stone, haulers carry it back.

const SEED := 42

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


## Places a finished building north of the road, `dx` tiles east of the Hearth.
func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(h.x + dx, h.y - def.size.y)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	var b: Building = s.buildings.get(bid)
	assert_true(b.connected, "%s is connected to the Hearth by road" % id)
	return b


# AC1a: the data row is the Town table's: 2x1, 45M 10P, 2 workers, 3 stone -> 1 cut stone at 2/worker/day.
func test_data_matches_the_town_table() -> void:
	var m := reg.get_building("mason")
	assert_not_null(m)
	assert_eq([m.era, m.category], ["town", "refining"])
	assert_eq([m.size, m.cost, m.worker_slots], [Vector2i(2, 1), {"wood": 18, "stone": 27, "planks": 10}, 2])
	assert_eq(m.upkeep_lumen, 0.0)
	assert_eq(m.recipe.inputs, {"stone": 6.0}, "3 per cut stone x 2 a worker-day")
	assert_eq(m.recipe.outputs, {"cut_stone": 2.0})
	assert_false(m.upgradable, "design section 10: refiners do not upgrade")
	assert_eq(reg.get_good("cut_stone").kind, "refined")


func test_mason_is_a_town_unlock() -> void:
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("mason"))
	s.era_override = "village"
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("mason"), "Town set only")


# AC1b: end to end. Haulers bring stone, the Mason makes cut stone, haulers carry it into the Hearth's storage,
# and the Hearth loses three stone for every cut stone that arrives.
func test_mason_recipe_runs_end_to_end_through_haulers() -> void:
	_strip()
	s.hearth.inventory.add("wood", 400.0)  # clamped to the Hearth's 150
	s.hearth.inventory.add("stone", 400.0)  # clamped to the Hearth's 150
	s.hearth.inventory.add("food", 200.0)  # no starving workers skewing the rate
	var mason := _put("mason", 4)
	s.step_days(3)  # the crew walks to work and haulers fill the two-day input buffer
	assert_gt(mason.input_buffer.amount_of("stone"), 10.0, "stone was hauled to the Mason")
	var before_m := s.hearth.inventory.amount_of("stone")
	var before_s := s.hearth.inventory.amount_of("cut_stone")
	s.step_days(5)
	var stone := s.hearth.inventory.amount_of("cut_stone") - before_s
	var used := before_m - s.hearth.inventory.amount_of("stone")
	assert_gt(stone, 0.0, "cut stone reached the Hearth's storage")
	# The two day workers make 4 a day; the Mason's night slot (ticket 132) adds about 2 x 10/12 over the night.
	assert_between(stone / 5.0, 5.0, 6.3, "two workers x 2 cut stone a day plus the night slot, got %f" % (stone / 5.0))
	assert_between(used / stone, 2.8, 3.15, "3 stone per cut stone")
	assert_eq(mason.halt, "", "the Mason kept running")
	assert_eq(s.totals().get("cut_stone", 0.0), s.hearth.inventory.amount_of("cut_stone"),
			"cut stone is a real stored good")
