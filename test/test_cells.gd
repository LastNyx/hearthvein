extends GutTest
## Ticket 28b: Refinery and Lumen cells (design.md sections 7 and 16 Town, D38).
## The data row and the 6 Lumen -> 1 cell recipe end to end through haulers, and cells covering upkeep and light
## automatically once raw Lumen is gone.

const SEED := 42
const RAW := "lumen"
const CELL := "lumen_cells"

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


# AC1a: the data row is the Town table's: 2x2, 60M 20G 15P, 2 workers, 6 Lumen -> 1 cell at 2 cells/worker-day.
func test_refinery_data_matches_the_town_table() -> void:
	var r := reg.get_building("refinery")
	assert_not_null(r)
	assert_eq([r.era, r.category], ["town", "refining"])
	assert_eq([r.size, r.cost, r.worker_slots], [Vector2i(2, 2), {"materials": 60, "gold": 20, "planks": 15}, 2])
	assert_eq(r.upkeep_lumen, 0.0)
	assert_eq(r.recipe.inputs, {RAW: 12.0}, "6 Lumen per cell x 2 a worker-day")
	assert_eq(r.recipe.outputs, {CELL: 2.0})
	assert_false(r.upgradable, "design section 10: refiners do not upgrade")
	assert_eq(reg.get_good(CELL).kind, "refined")


func test_refinery_is_a_town_unlock() -> void:
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("refinery"))
	s.era_override = "village"
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("refinery"), "Town set only")


# AC1b: end to end. Haulers bring Lumen, the Refinery makes cells, haulers carry them into the Hearth's storage,
# and the settlement loses six Lumen for every cell it gains.
func test_refinery_recipe_runs_end_to_end_through_haulers() -> void:
	s.systems.erase(s.get_system(StorageSystem))  # no 1%/day Lumen leak blurring the 6:1 ratio
	_strip()
	s.hearth.inventory.add(RAW, 140.0)  # clamped to the Hearth's 150
	s.hearth.inventory.add("food", 200.0)  # no starving workers skewing the rate
	var refinery := _put("refinery", 4)
	s.step_days(2)  # the crew walks to work and haulers fill the two-day input buffer
	assert_gt(refinery.input_buffer.amount_of(RAW), 10.0, "Lumen was hauled to the Refinery")
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var before_made := prod.produced_total
	# Count the Refinery's input buffer too: Lumen sitting there was taken from storage before it went into a cell.
	var before_l := s.hearth.inventory.amount_of(RAW) + refinery.input_buffer.amount_of(RAW)
	s.step_days(3)
	var made := prod.produced_total - before_made
	var lumen := before_l - s.hearth.inventory.amount_of(RAW) - refinery.input_buffer.amount_of(RAW)
	assert_gt(s.hearth.inventory.amount_of(CELL), 0.0, "cells reached the Hearth's storage")
	assert_between(made / 3.0, 3.0, 4.4, "two workers x 2 cells a day, got %f" % (made / 3.0))
	assert_between(lumen / made, 5.98, 6.02, "6 Lumen per cell")
	assert_eq(refinery.halt, "", "the Refinery kept running")
	assert_eq(s.totals().get(CELL, 0.0), s.hearth.inventory.amount_of(CELL), "cells are a real stored good")


# AC2a: with raw Lumen gone from storage, a cell is broken for the day's upkeep (design.md section 7: 1 cell = 5 L).
func test_cells_cover_upkeep_when_raw_lumen_is_gone() -> void:
	_strip()
	s.hearth.inventory.remove(RAW, 1000.0)  # not a drop of raw Lumen in the settlement
	s.hearth.inventory.add(CELL, 10.0)
	var shop := _put("workshop", 4)  # Town, 1 Lumen upkeep a day
	s.step_days(3)
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us.is_paid(shop.id), "cells paid the upkeep")
	assert_lt(s.hearth.inventory.amount_of(CELL), 10.0, "a cell was broken for the upkeep")
	assert_between(s.hearth.inventory.amount_of(RAW), 0.0, 5.0, "the broken cell's Lumen sits in storage")


# AC2b: while raw Lumen is in storage, cells are left alone.
func test_raw_lumen_is_spent_before_cells() -> void:
	_strip()
	s.hearth.inventory.add(RAW, 100.0)
	s.hearth.inventory.add(CELL, 10.0)
	var shop := _put("workshop", 4)
	s.step_days(2)
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us.is_paid(shop.id), "raw Lumen paid the upkeep")
	assert_eq(s.hearth.inventory.amount_of(CELL), 10.0, "cells untouched while raw Lumen exists")


# AC2c: the Dimming's light draw already falls back to cells; with no raw Lumen the day is lit from cells.
func test_cells_cover_light_when_raw_lumen_is_gone() -> void:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	s.hearth.inventory.remove(RAW, 1000.0)
	s.hearth.inventory.add(CELL, 10.0)
	d._start_day = s.clock.total_days()
	d._length = 5
	d._active = true
	s.step_days(1)
	assert_false(DimmingSystem.is_dark(s), "the light was covered")
	assert_gt(d.last_light["drawn_cells"], 0.0, "light came from cells")
	assert_lt(s.hearth.inventory.amount_of(CELL), 10.0)
	assert_eq(d.last_light["drawn_lumen"], 0.0, "no raw Lumen was there to draw")
