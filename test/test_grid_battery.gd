extends GutTest
## Ticket 36b: the Grid Battery holds 600 Lumen for its grid, lossless, and gives it up only when doors and storages
## run dry.

const SEED := 42
const UP_ID := "test_bat_consumer"
const MAKER_ID := "test_bat_maker"

var reg: DataRegistry
var s: Settlement
var gs: GridSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	var m := BuildingDef.new()
	m.id = MAKER_ID
	m.display_name = "Test battery Lumen maker"
	m.era = "town"
	m.category = "lumen"
	m.size = Vector2i(2, 1)
	m.recipe = RecipeDef.new()
	m.recipe.outputs = {"lumen": 4.0}
	reg.buildings[m.id] = m
	var u := BuildingDef.new()
	u.id = UP_ID
	u.display_name = "Test battery consumer"
	u.era = "town"
	u.category = "resources"
	u.size = Vector2i(2, 1)
	u.upkeep_lumen = 2.0
	reg.buildings[u.id] = u


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "conflux"
	gs = s.get_system(GridSystem)
	h = s.map.hearth_spot
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	for x in range(h.x - 2, h.x + 15):
		for y in range(h.y - 5, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if x >= h.x + 2:
			s.place_road(Vector2i(x, h.y))


func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var bid := s.place_building_instant(id, Vector2i(h.x + dx, h.y - def.size.y))
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings.get(bid)


## Feeds `amount` Lumen through the maker's door (it holds only a little at a time), running on_hour after each fill.
func _feed(maker: Building, amount: float) -> void:
	var left := amount
	var guard := 0
	while left > 0.001 and guard < 1000:
		guard += 1
		left -= maker.door_buffer.add("lumen", left)
		gs.on_hour(s)


func _grid() -> Array:
	_put("lumen_pylon", 3)
	var bat := _put("grid_battery", 5)
	var maker := _put(MAKER_ID, 8)
	return [bat, maker, gs.grid_of(s, bat.id)]


func test_battery_data() -> void:
	var d := reg.get_building("grid_battery")
	assert_eq(d.era, "conflux")
	assert_eq(d.size, Vector2i(2, 1))
	assert_eq(d.cost, {"wood": 42, "stone": 18, "gold": 30, "cut_stone": 20, "lumen_cells": 20})
	assert_eq(d.battery_capacity, 600.0)


# AC1: charges to 600, never past it, no loss over days.
func test_charges_to_capacity_without_loss() -> void:
	var g := _grid()
	var bat: Building = g[0]
	var maker: Building = g[1]
	var gid: int = g[2]
	assert_gt(gid, -1)
	assert_eq(gs.grid_of(s, bat.id), gid)
	_feed(maker, 100.0)
	assert_almost_eq(gs.charge_of(bat.id), 100.0, 0.001)
	assert_almost_eq(maker.door_buffer.amount_of("lumen"), 0.0, 0.001)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 0.0, 0.001, "batteries fill before storages")
	assert_almost_eq(gs.supply(s, gid), 0.0, 0.001, "supply excludes battery charge")
	assert_almost_eq(gs.battery_charge(s, gid), 100.0, 0.001)
	# no leak across days
	for i in 5 * 24:
		gs.on_hour(s)
	s.step_days(5)
	assert_almost_eq(gs.charge_of(bat.id), 100.0, 0.001, "lossless")
	# overfill: the rest goes to storage
	_feed(maker, 700.0)
	assert_almost_eq(gs.charge_of(bat.id), 600.0, 0.001)
	assert_almost_eq(gs.battery_charge(s, gid), 600.0, 0.001)
	assert_gt(s.hearth.inventory.amount_of("lumen"), 0.0, "overflow goes to storage")
	_feed(maker, 50.0)
	assert_almost_eq(gs.charge_of(bat.id), 600.0, 0.001, "never past capacity")


# AC2a: no discharge while doors and storages cover demand.
func test_no_discharge_while_supply_covers() -> void:
	var g := _grid()
	var maker: Building = g[1]
	var gid: int = g[2]
	_feed(maker, 100.0)
	s.hearth.inventory.add("lumen", 50.0)
	assert_almost_eq(gs.draw(s, gid, 30.0), 30.0, 0.001)
	assert_almost_eq(gs.battery_charge(s, gid), 100.0, 0.001, "battery untouched")
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 20.0, 0.001)


# AC2b: discharge when everything else is empty, then the cells fallback is not reached early.
func test_discharges_when_supply_is_short() -> void:
	var g := _grid()
	var maker: Building = g[1]
	var gid: int = g[2]
	_feed(maker, 100.0)
	s.hearth.inventory.add("lumen", 20.0)
	assert_almost_eq(gs.draw(s, gid, 50.0), 50.0, 0.001)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 0.0, 0.001)
	assert_almost_eq(gs.battery_charge(s, gid), 70.0, 0.001, "battery covered the 30 shortfall")
	assert_almost_eq(gs.draw(s, gid, 500.0), 70.0, 0.001, "can only give what it holds")
	assert_almost_eq(gs.battery_charge(s, gid), 0.0, 0.001)


func test_battery_pays_on_grid_upkeep_in_a_dry_spell() -> void:
	var g := _grid()
	var maker: Building = g[1]
	var gid: int = g[2]
	_feed(maker, 60.0)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	var ref := _put(UP_ID, 11)
	assert_true(us._pay(s, ref), "paid from the battery")
	assert_lt(gs.battery_charge(s, gid), 60.0)


func test_charge_survives_a_save_round_trip() -> void:
	var g := _grid()
	var bat: Building = g[0]
	var maker: Building = g[1]
	_feed(maker, 123.0)
	var st := gs.save_state()
	var gs2 := GridSystem.new()
	gs2.load_state(st.duplicate(true), s)
	assert_almost_eq(gs2.charge_of(bat.id), 123.0, 0.001)
