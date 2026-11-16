extends GutTest
## Ticket 70: airship freight to island docks. An island dock is its own freight node (ManifestBase._region keys sky-layer
## buildings by region + REGION_COUNT): own stock table, trades with any dock by daily manifest, skipped while still.

const SEED := 42
const SAVE_PATH := "user://test_island_freight.save"

var reg: DataRegistry
var s: Settlement
var air: AirshipSystem
var h: Vector2i
var isl: Island
var ground_dock: Building
var island_dock: Building
var far_dock: Building
var tent: Building


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## Island over the Hearth's region with a ground dock and an island dock; a second ground dock and a tent (10 homed
## citizens) in the neighbouring region. Docks are staffed by hand. keep_islands = false drops IslandSystem so the
## unfed island does not go still while time runs.
func _setup(keep_islands: bool = false) -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.systems.erase(s.get_system(JobSystem))
	s.era_override = "skyborne"
	air = s.get_system(AirshipSystem)
	h = s.map.hearth_spot
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 5, h.y + 6):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
	s.hearth.inventory.add("materials", 500.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.place_building_instant("lumen_pylon", Vector2i(h.x + 3, h.y - 1))
	var aid := s.place_building_instant("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	assert_gt(aid, -1, "anchor placed")
	var isys := s.get_system(IslandSystem) as IslandSystem
	isl = isys.island_of_anchor(aid)
	var gd := s.place_building_instant("airship_dock", Vector2i(h.x + 12, h.y + 1))
	var did := s.place_building_instant("airship_dock", isl.rect.position + Vector2i(1, 1), Building.LAYER_SKY)
	assert_true(gd >= 0 and did >= 0, "both docks placed")
	ground_dock = s.buildings[gd]
	island_dock = s.buildings[did]
	var other := isl.region + 1 if isl.region % MapState.REGION_COLS < MapState.REGION_COLS - 1 else isl.region - 1
	var rect := MapState.region_rect(other)
	var o := rect.position + Vector2i(10, 10)
	for x in range(o.x - 2, o.x + 16):
		for y in range(o.y - 5, o.y + 6):
			s.set_terrain(Vector2i(x, y), "grass")
	far_dock = s.buildings[s.place_building_instant("airship_dock", o)]
	tent = s.buildings[s.place_building_instant("tent", o + Vector2i(8, 0))]
	assert_ne(s.map.get_region(far_dock.origin.x, far_dock.origin.y), isl.region)
	while s.citizens.size() < 14:
		s.add_citizen()
	var ids: Array = s.citizens.keys()
	ids.sort()
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.job_id = -1
		c.job_kind = Citizen.JOB_NONE
		c.home_id = -1
		if i < 3:
			c.job_id = [island_dock.id, far_dock.id, ground_dock.id][i]
			c.job_kind = Citizen.JOB_WORK
		elif i >= 4:
			c.home_id = tent.id
	for g in s.hearth.inventory.goods():
		if g != "materials" and g != "cut_stone":
			s.hearth.inventory.remove(g, 1000000.0)
	if not keep_islands:
		s.systems.erase(isys)


func _food_at(b: Building) -> float:
	return b.inventory.amount_of("food")


func test_island_dock_is_its_own_node_and_trades_with_a_ground_dock_elsewhere() -> void:
	_setup()
	var stocked := island_dock.inventory.add("food", 200.0)
	assert_gt(stocked, 30.0, "the island dock holds food")
	s.step_days(2)
	assert_gt(_food_at(far_dock) + (tent.inventory.amount_of("food") if tent.inventory != null else 0.0), 0.0,
			"food reached the other region by air")
	var sent := s.events.log_of("airship_sent")
	assert_false(sent.is_empty(), "an airship left")
	assert_eq(int(sent[0]["data"]["from"]), island_dock.id, "from the island dock")
	assert_eq(int(sent[0]["data"]["to"]), far_dock.id)
	assert_true(s.events.log_of("shipment_sent").is_empty(), "no train: rail never serves an island")
	assert_true(_food_at(island_dock) < stocked, "the island dock gave food away")


func test_ground_dock_under_the_island_keeps_its_own_stock_table() -> void:
	_setup()
	island_dock.inventory.add("food", 120.0)
	ground_dock.inventory.add("food", 40.0)
	var table := air._region_table(s)
	var rg := isl.region
	var ri := isl.region + MapState.REGION_COUNT
	assert_almost_eq(float(table["stock"][rg]["@food"]), _food_at(ground_dock) + _hearth_region_food(), 0.01)
	assert_almost_eq(float(table["stock"][ri]["@food"]), _food_at(island_dock), 0.01, "island stock is only the island's")
	assert_ne(air._region(s, ground_dock), air._region(s, island_dock))
	assert_eq(air._region(s, ground_dock), rg, "ground keys stay plain regions")
	# a ground dock and an island dock in one region are two nodes: both are staffed docks
	assert_eq(air._staffed_docks(s).size(), 3)


func _hearth_region_food() -> float:
	var sum := 0.0
	for b: Building in s.buildings.values():
		if b != ground_dock and b.layer == Building.LAYER_GROUND and b.inventory != null and not b.site \
				and s.map.get_region(b.origin.x, b.origin.y) == isl.region:
			sum += b.inventory.amount_of("food")
	return sum


func test_a_still_island_dock_skips_the_manifests() -> void:
	_setup(true)
	var held := island_dock.inventory.add("food", 200.0)
	assert_true(air._staffed_docks(s).has(island_dock.id))
	isl.still_why = "no_grid"
	assert_false(air._staffed_docks(s).has(island_dock.id), "still: not a node")
	air.on_day(s)
	assert_eq(air.ship_count(), 0, "a still island's dock sends nothing")
	assert_almost_eq(_food_at(island_dock), held, 0.01)
	isl.still_why = ""
	air.on_day(s)
	assert_gt(air.ship_count(), 0, "fed again, it trades")


func test_save_round_trip_with_an_island_dock() -> void:
	_setup(true)
	island_dock.inventory.add("food", 200.0)
	air.on_day(s)
	assert_gt(air.ship_count(), 0, "an airship is out of the island dock")
	var before := air.shipments(s)
	assert_eq(int(before[0]["from_dock"]), island_dock.id)
	assert_eq(SaveGame.save(s, SAVE_PATH), OK)
	var loaded := SaveGame.load(SAVE_PATH, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	var a2 := loaded.get_system(AirshipSystem) as AirshipSystem
	var after := a2.shipments(loaded)
	assert_eq(after.size(), before.size())
	assert_eq(after[0]["from_dock"], before[0]["from_dock"])
	assert_eq(after[0]["goods"], before[0]["goods"])
	assert_almost_eq(float(after[0]["arrive_hour"]), float(before[0]["arrive_hour"]), 0.0001)
	var d2: Building = loaded.buildings[island_dock.id]
	assert_eq(d2.layer, Building.LAYER_SKY)
	assert_eq(a2._region(loaded, d2), isl.region + MapState.REGION_COUNT, "same node key after load")
