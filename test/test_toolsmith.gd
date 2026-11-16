extends GutTest
## Ticket 34: Toolsmith (design.md sections 7 and 16 City).
## The data row and the recipe 1 plank + 1 Lumen cell -> 1 tool run end to end through haulers.

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _strip(s: Settlement) -> void:
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


func test_data_matches_the_city_table() -> void:
	var t := reg.get_building("toolsmith")
	assert_not_null(t)
	assert_eq([t.era, t.category, t.size], ["city", "refining", Vector2i(2, 1)])
	assert_eq(t.cost, {"materials": 80, "gold": 30, "cut_stone": 20})
	assert_eq([t.worker_slots, t.upkeep_lumen], [2, 1.0])
	assert_eq(t.recipe.inputs, {"planks": 1.5, "lumen_cells": 1.5}, "1 P + 1 C per tool, 1.5 tools a worker-day")
	assert_eq(t.recipe.outputs, {"tools": 1.5})
	assert_false(t.upgradable)
	assert_eq(reg.get_good("tools").kind, "refined")


func test_locked_before_city() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_override = "town"
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("toolsmith"))
	s.era_override = "city"
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("toolsmith"))


func test_toolsmith_makes_tools_from_hauled_planks_and_cells() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_override = "city"
	_strip(s)
	var h := s.map.hearth_spot
	s.hearth.inventory.add("planks", 100.0)
	s.hearth.inventory.add("lumen_cells", 100.0)
	s.hearth.inventory.add("food", 200.0)
	s.hearth.inventory.add("lumen", 100.0)
	var bid := s.place_building_instant("toolsmith", Vector2i(h.x + 4, h.y - 1))
	assert_true(bid >= 0)
	var b: Building = s.buildings.get(bid)
	assert_true(b.connected)
	s.step_days(3)
	assert_gt(b.input_buffer.amount_of("planks"), 1.0, "planks were hauled in")
	assert_gt(b.input_buffer.amount_of("lumen_cells"), 1.0, "Lumen cells were hauled in")
	var p0 := s.hearth.inventory.amount_of("planks") + b.input_buffer.amount_of("planks")
	var c0 := s.hearth.inventory.amount_of("lumen_cells") + b.input_buffer.amount_of("lumen_cells")
	var t0 := s.hearth.inventory.amount_of("tools")
	s.step_days(5)
	var tools := s.hearth.inventory.amount_of("tools") - t0
	assert_gt(tools, 0.0, "tools reached storage")
	assert_between(tools / 5.0, 2.2, 3.2, "two workers x 1.5 tools a day")
	assert_between((p0 - s.hearth.inventory.amount_of("planks") - b.input_buffer.amount_of("planks")) / tools, 0.9, 1.1, "1 plank per tool")
	assert_between((c0 - s.hearth.inventory.amount_of("lumen_cells") - b.input_buffer.amount_of("lumen_cells")) / tools, 0.9, 1.1, "1 cell per tool")
	assert_eq(b.halt, "")
