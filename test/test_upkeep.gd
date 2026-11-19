extends GutTest
## Ticket 27: Lumen upkeep as a hauled good (design.md sections 8 and 14; section 16 Town: "Lumen upkeep starts").
## Haulers bring Lumen into a consumer's input buffer (two days of need) and the day hook spends one day's worth;
## a building whose day was not paid runs at x0.5.

const SEED := 42
const DEF_ID := "test_upkeep_workshop"
const UPKEEP := 2.0

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	# No Town building exists as data yet (27b/27c add the real rows): inject a simple Town producer.
	var d := BuildingDef.new()
	d.id = DEF_ID
	d.display_name = "Test workshop"
	d.era = "town"
	d.category = "materials"
	d.size = Vector2i(2, 1)
	d.worker_slots = 1
	d.upkeep_lumen = UPKEEP
	d.recipe = RecipeDef.new()
	d.recipe.inputs = {}
	d.recipe.outputs = {"materials": 2.0}
	reg.buildings[d.id] = d


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	_strip(s)


## A cleared, road-connected strip east of the Hearth (the patch test_hauling and test_sawmill use).
func _strip(settlement: Settlement) -> void:
	var h := settlement.map.hearth_spot
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if settlement.map.terrain_id_at(x, y) == "forest":
				settlement.set_terrain(Vector2i(x, y), "grass")
		settlement.place_road(Vector2i(x, h.y))


## Places the test producer north of the road, `dx` tiles east of the Hearth.
func _put(settlement: Settlement, dx: int) -> Building:
	var def := reg.get_building(DEF_ID)
	var h := settlement.map.hearth_spot
	var origin := Vector2i(h.x + dx, h.y - def.size.y)
	var bid := settlement.place_building_instant(DEF_ID, origin)
	assert_true(bid >= 0, "%s placed at %s" % [DEF_ID, origin])
	var b: Building = settlement.buildings.get(bid)
	assert_true(b.connected, "%s is connected to the Hearth by road" % DEF_ID)
	return b


# AC1a: no Camp or Village row has upkeep (design section 16 lists "-" for all of them), and the x0.5 comes from data.
func test_data_starts_upkeep_in_town_and_keeps_before_town_rows_clean() -> void:
	assert_eq(reg.logistics.input_buffer_days, 2.0, "consumers keep two days of need")
	assert_eq(reg.logistics.unpaid_upkeep_factor, 0.5, "design sections 8 and 14: x0.5")
	assert_eq(reg.get_era("town").order, 3)
	assert_true(reg.buildings.values().any(func(d: BuildingDef) -> bool: return d.era == "camp"))
	for d: BuildingDef in reg.buildings.values():
		# The Cleanser moved to Village in 1.1.4 and keeps its 2 Lumen row; upkeep still only runs from Town.
		if (d.era == "camp" or d.era == "village") and d.id != "cleanser":
			assert_eq(d.upkeep_lumen, 0.0, "%s needs no Lumen before Town" % d.id)


# AC1b: haulers deliver upkeep Lumen into the input buffer (an upkeep-only consumer gets one), and the day hook
# spends one day's worth from it.
func test_haulers_fill_the_upkeep_buffer_and_it_is_spent_daily() -> void:
	s.era_override = "town"
	var def := reg.get_building(DEF_ID)
	assert_eq(HaulingSystem.input_need(reg, def), {"lumen": UPKEEP * reg.logistics.input_buffer_days})
	s.hearth.inventory.add("lumen", 100.0)
	var b := _put(s, 4)
	assert_not_null(b.input_buffer, "a building with upkeep and no recipe input still gets an input buffer")
	s.step_days(3)
	s.step_hours(7)  # haulers top the buffer up after the day-start spend
	assert_gt(b.input_buffer.amount_of("lumen"), 0.0, "haulers brought the upkeep Lumen in")
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us.is_paid(b.id), "the day's upkeep was paid")
	s.systems.erase(s.get_system(HaulingSystem))  # isolate the daily spend from refills
	var before := b.input_buffer.amount_of("lumen")
	s.step_hours(24)
	assert_almost_eq(b.input_buffer.amount_of("lumen"), before - UPKEEP, 0.001,
			"one day's upkeep was spent from the buffer")
	assert_eq(b.halt, "", "the producer kept running")


# AC2: the same building producing with a paid day and with an unpaid day differs by exactly the x0.5 factor.
func test_unpaid_upkeep_halves_output() -> void:
	var paid := _second_day_output(true)
	var unpaid := _second_day_output(false)
	assert_gt(paid, 0.5, "a paid building produces (%.2f)" % paid)
	assert_between(unpaid / paid, 0.45, 0.55,
			"unpaid upkeep runs at x0.5 (%.2f vs %.2f)" % [unpaid, paid])


## Door-buffer output over one full day whose day-start check already decided the flag. Day 0 is left out: a fresh
## building counts as paid until its first check, so both runs produce it at the same rate.
func _second_day_output(fed: bool) -> float:
	var settlement := Settlement.new_game(SEED, reg)
	settlement.era_override = "town"
	_strip(settlement)
	settlement.systems.erase(settlement.get_system(HaulingSystem))  # deliver by hand, so the day check is the only variable
	settlement.hearth.inventory.remove("lumen", 1000.0)  # no other Lumen in the settlement
	var b := _put(settlement, 4)
	if fed:
		b.input_buffer.add("lumen", UPKEEP * reg.logistics.input_buffer_days)  # two days at the buffer cap
	settlement.step_days(1)  # the first check sets the flag the measured day runs on
	var before := b.door_buffer.amount_of("materials")
	settlement.step_days(1)
	return b.door_buffer.amount_of("materials") - before


# Upkeep waits for the Town era even when a debug-placed building has an upkeep: nothing is spent and nothing runs
# at half before Town.
func test_upkeep_waits_for_the_town_era() -> void:
	assert_eq(s.era_id(), "camp")
	s.systems.erase(s.get_system(HaulingSystem))
	var b := _put(s, 4)  # the debug path bypasses the era lock
	b.input_buffer.add("lumen", UPKEEP * 2.0)
	s.step_days(3)
	assert_almost_eq(b.input_buffer.amount_of("lumen"), UPKEEP * 2.0, 0.001, "nothing is spent before Town")
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us.is_paid(b.id), "no unpaid flag before Town")
	assert_gt(b.door_buffer.amount_of("materials"), 0.0, "production runs before Town")
