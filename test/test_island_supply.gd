extends GutTest
## Ticket 40b: island Lumen supply and still state (design.md section 17). Each island draws 20 L/day (hourly, pro rata)
## through the grid of its Lift Anchor; short of it, off-grid or with an unstaffed anchor it goes still.

const SEED := 42
const SAVE_PATH := "user://test_island_supply.sav"

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var anchor: Building
var isl: Island
var grid_id: int


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	var d := BuildingDef.new()
	d.id = "test_sky_farm"
	d.display_name = "Sky farm"
	d.era = "camp"
	d.category = "food"
	d.size = Vector2i(2, 2)
	d.layers = "island"
	d.recipe = RecipeDef.new()
	d.recipe.outputs = {"food": 2.0}
	reg.buildings[d.id] = d


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "conflux"
	h = s.map.hearth_spot
	for x in range(h.x - 2, h.x + 15):
		for y in range(h.y - 5, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if x >= h.x + 2:
			s.place_road(Vector2i(x, h.y))
	s.place_building_instant("lumen_pylon", Vector2i(h.x + 3, h.y - 1))
	var aid := s.place_building_instant("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	assert_true(aid >= 0, "anchor placed")
	anchor = s.buildings[aid]
	isl = _isl().island_of_anchor(aid)
	assert_not_null(isl)
	grid_id = _gs().grid_of(s, aid)
	assert_gt(grid_id, -1, "anchor on the grid")
	s.hearth.inventory.add("lumen", 100.0)
	assert_gt(_gs().grid_of(s, s.hearth.id), -1, "hearth store on the grid")


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func _isl() -> IslandSystem:
	return s.get_system(IslandSystem) as IslandSystem


func _gs() -> GridSystem:
	return s.get_system(GridSystem) as GridSystem


## The anchor sits on the road, so the job system staffs it; run it once so the first hourly check sees workers.
func _staff() -> void:
	JobSystem.refresh(s)
	var n := 0
	for c: Citizen in s.citizens.values():
		if c.job_id == anchor.id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	assert_eq(n, anchor.def.worker_slots, "anchor staffed")


func _farm() -> Building:
	var t := Vector2i(isl.rect.position.x + 2, isl.rect.position.y + 2)
	var id := s.place_building_instant("test_sky_farm", t, Building.LAYER_SKY)
	assert_true(id >= 0)
	return s.buildings[id]


func _count_events(kind: String) -> Array:
	var out := []
	s.events.subscribe(kind, func(e: Dictionary) -> void: out.append(e["data"]))
	return out


func test_data_row() -> void:
	assert_eq(reg.logistics.island_upkeep_lumen, 20.0)
	assert_eq(anchor.def.upkeep_lumen, 0.0)


# AC1: short of Lumen the island goes still, its producer halts, and it recovers when fed.
func test_short_of_lumen_goes_still_and_recovers() -> void:
	var farm := _farm()
	var still := _count_events("island_still")
	var resumed := _count_events("island_resumed")
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	_gs().draw(s, grid_id, 1000.0)
	_staff()
	s.step_hours(3)
	assert_eq(isl.still_why, "short_lumen")
	assert_eq(farm.halt, "island_still")
	assert_true(IslandSystem.is_still_building(s, farm))
	assert_false(IslandSystem.is_still_building(s, anchor), "ground buildings are never still")
	assert_eq(still.size(), 1)
	s.hearth.inventory.add("lumen", 50.0)
	s.step_hours(2)
	assert_eq(isl.still_why, "")
	assert_ne(farm.halt, "island_still")
	assert_eq(resumed.size(), 1)
	assert_true(s.buildings.has(farm.id), "nothing is destroyed")


# AC2: one island_still per cause across many hours, a new one when the cause changes.
func test_one_notification_per_cause() -> void:
	var still := _count_events("island_still")
	_staff()
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	_gs().draw(s, grid_id, 1000.0)
	s.step_hours(30)
	assert_eq(still.size(), 1)
	assert_eq(still[0]["why"], "short_lumen")
	anchor.paused = true
	s.step_hours(30)
	assert_eq(still.size(), 2)
	assert_eq(still[1]["why"], "anchor_unstaffed")
	assert_eq(isl.still_why, "anchor_unstaffed")


func test_notification_center_one_toast_per_cause() -> void:
	s.systems.erase(s.get_system(MilestoneSystem))  # its "first island" toast is not what this counts
	var nc := NotificationCenter.new(s)
	_staff()
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	_gs().draw(s, grid_id, 1000.0)
	s.step_hours(30)
	assert_eq(nc.items.size(), 1)
	assert_string_contains(nc.items[0]["text"], "is still")
	anchor.paused = true
	s.step_hours(5)
	assert_eq(nc.items.size(), 2)


func test_draw_over_a_day_is_20_lumen() -> void:
	_staff()
	var before := _gs().supply(s, grid_id)
	for i in 24:
		_isl().on_hour(s)  # the system alone, so other upkeep does not muddy the count
	var spent := before - _gs().supply(s, grid_id)
	assert_almost_eq(spent, 20.0, 0.01)
	assert_eq(isl.still_why, "")


func test_unstaffed_anchor_is_still_and_draws_nothing() -> void:
	for c: Citizen in s.citizens.values():
		c.job_id = -1
	var before := _gs().supply(s, grid_id)
	s.step_hours(1)
	assert_eq(isl.still_why, "anchor_unstaffed")
	assert_almost_eq(_gs().supply(s, grid_id), before, 0.001)


func test_off_grid_anchor_is_still() -> void:
	_staff()
	var pylon := s.building_at(Vector2i(h.x + 3, h.y - 1))
	assert_true(s.demolish(pylon.id))
	assert_eq(_gs().grid_of(s, anchor.id), -1)
	s.step_hours(1)
	assert_eq(isl.still_why, "no_grid")


func test_still_island_is_no_water_source() -> void:
	var farm := _farm()
	var src := BuildingDef.new()
	src.id = "test_sky_well"
	src.display_name = "Sky well"
	src.era = "camp"
	src.category = "water"
	src.size = Vector2i(1, 1)
	src.layers = "island"
	src.water_radius = 10
	reg.buildings[src.id] = src
	var wid := s.place_building_instant("test_sky_well", Vector2i(isl.rect.position.x + 6, isl.rect.position.y + 2), Building.LAYER_SKY)
	assert_true(wid >= 0)
	farm.def.work_needs_water = true
	assert_true(WaterSystem.has_water(s, farm))
	isl.still_why = "short_lumen"
	assert_false(WaterSystem.has_water(s, farm))
	farm.def.work_needs_water = false


func test_still_state_round_trips_through_save() -> void:
	isl.still_why = "no_grid"
	var d := _isl().save_state()
	var other := IslandSystem.new()
	other.load_state(d, s)
	assert_eq(other.islands[0].still_why, "no_grid")
	assert_eq(SaveGame.save(s, SAVE_PATH), OK)
	var loaded := SaveGame.load(SAVE_PATH, reg)
	assert_eq((loaded.get_system(IslandSystem) as IslandSystem).islands[0].still_why, "no_grid")
