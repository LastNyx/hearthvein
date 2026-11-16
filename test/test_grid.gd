extends GutTest
## Ticket 36: the Lumen grid (design.md sections 7, 8 and 17). Pylons (feed r8, link 12) and the Lumen Nexus (r12) form
## grids; buildings on a grid take Lumen straight from its supply and pay upkeep x0.75.

const SEED := 42
const UP_ID := "test_grid_consumer"
const MAKER_ID := "test_grid_maker"
const UPKEEP := 2.0

var reg: DataRegistry
var s: Settlement
var gs: GridSystem
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	var d := BuildingDef.new()
	d.id = UP_ID
	d.display_name = "Test grid consumer"
	d.era = "town"
	d.category = "materials"
	d.size = Vector2i(2, 1)
	d.upkeep_lumen = UPKEEP
	reg.buildings[d.id] = d
	var m := BuildingDef.new()
	m.id = MAKER_ID
	m.display_name = "Test grid Lumen maker"
	m.era = "town"
	m.category = "lumen"
	m.size = Vector2i(2, 1)
	m.recipe = RecipeDef.new()
	m.recipe.outputs = {"lumen": 4.0}
	reg.buildings[m.id] = m


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "conflux"
	gs = s.get_system(GridSystem)
	h = s.map.hearth_spot
	_clear(s)


## Clears forest east of the Hearth (the owned region ends near x = 95) and lays a road along its row.
func _clear(st: Settlement, road: bool = true) -> void:
	for x in range(h.x - 2, h.x + 15):
		for y in range(h.y - 5, h.y + 5):
			if st.map.terrain_id_at(x, y) == "forest":
				st.set_terrain(Vector2i(x, y), "grass")
		if road and x >= h.x + 2:
			st.place_road(Vector2i(x, h.y))


## Places a building north of the road, `dx` tiles east of the Hearth.
func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var bid := s.place_building_instant(id, Vector2i(h.x + dx, h.y - def.size.y))
	assert_true(bid >= 0, "%s placed at dx %d" % [id, dx])
	return s.buildings.get(bid)


func test_pylon_and_nexus_data() -> void:
	var p := reg.get_building("lumen_pylon")
	assert_eq(p.era, "conflux")
	assert_eq(p.size, Vector2i(1, 1))
	assert_eq(p.cost, {"materials": 30, "cut_stone": 10, "tools": 5})
	assert_eq(p.grid_feed_radius, 8)
	assert_eq(p.grid_link_range, 12)
	var n := reg.get_building("lumen_nexus")
	assert_eq(n.grid_feed_radius, 12)
	assert_eq(n.grid_link_range, 12)
	assert_eq(reg.logistics.grid_upkeep_factor, 0.75)


# AC1: a building in pylon range gets Lumen with no hauler trip.
func test_building_in_pylon_range_gets_lumen_without_a_hauler() -> void:
	_put("lumen_pylon", 3)
	var near := _put(UP_ID, 6)
	var far := _put(UP_ID, 13)
	assert_true(GridSystem.on_grid(s, near))
	assert_true(GridSystem.on_grid(s, s.hearth), "the Hearth store is within r8 of the pylon")
	assert_false(GridSystem.on_grid(s, far))
	assert_eq(HaulingSystem.input_need(reg, near.def)["lumen"], UPKEEP * 2.0, "it would need hauling off-grid")
	s.hearth.inventory.add("lumen", 90.0)
	s.step_days(2)
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	assert_eq(near.input_buffer.amount_of("lumen"), 0.0, "nothing was hauled into its buffer")
	assert_true((s.get_system(UpkeepSystem) as UpkeepSystem).is_paid(near.id), "upkeep paid from the grid supply")
	assert_gt(far.input_buffer.amount_of("lumen"), 0.0, "off the grid a hauler does bring the Lumen")
	assert_eq(hs.trips.size(), 0, "no trips carry Lumen")


# AC1b: Lumen sitting in an on-grid producer's door buffer is grid supply and is not hauled to a storage.
func test_on_grid_producer_lumen_is_supply_and_stays_put() -> void:
	_put("lumen_pylon", 3)
	var maker := _put(MAKER_ID, 6)
	maker.door_buffer.add("lumen", 10.0)
	var gid := gs.grid_of(s, maker.id)
	assert_gt(gid, -1)
	assert_almost_eq(gs.supply(s, gid), 10.0 + s.hearth.inventory.amount_of("lumen"), 0.001)
	s.step_days(2)
	assert_gte(maker.door_buffer.amount_of("lumen"), 10.0, "not hauled to the on-grid Hearth")
	# Control: the same layout off-grid hauls the door buffer away.
	var s2 := Settlement.new_game(SEED, reg)
	s2.systems.erase(s2.get_system(GrowthSystem))
	s2.era_override = "conflux"
	_clear(s2)
	var bid := s2.place_building_instant(MAKER_ID, Vector2i(h.x + 6, h.y - 1))
	var m2: Building = s2.buildings[bid]
	m2.door_buffer.add("lumen", 10.0)
	s2.step_days(2)
	assert_lt(m2.door_buffer.amount_of("lumen"), 10.0, "off the grid, haulers carry it")


# AC2: upkeep is x0.75 on the grid.
func test_upkeep_is_cut_by_a_quarter_inside_the_grid() -> void:
	_put("lumen_pylon", 3)
	var on := _put(UP_ID, 6)
	var off := _put(UP_ID, 13)
	off.input_buffer.add("lumen", 4.0)
	s.hearth.inventory.add("lumen", 90.0)  # 100 Lumen in the Hearth
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_true(us._pay(s, on))
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 100.0 - UPKEEP * 0.75, 0.001, "on the grid x0.75 from the supply")
	assert_true(us._pay(s, off))
	assert_almost_eq(off.input_buffer.amount_of("lumen"), 4.0 - UPKEEP, 0.001, "off the grid the full upkeep")


func test_on_grid_recipe_lumen_input_comes_from_the_grid() -> void:
	_put("lumen_pylon", 3)
	var ref := _put("refinery", 6)
	s.hearth.inventory.add("lumen", 40.0)
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	ps.batch_seconds = 0.0
	gs.feed_inputs(s, ref)
	assert_gt(ref.input_buffer.amount_of("lumen"), 0.0, "filled from the grid, not by a hauler")
	assert_lt(s.hearth.inventory.amount_of("lumen"), 50.0)


# AC3: pylons link only within 12 tiles (11, 12 link; 13 does not).
func test_pylons_link_within_twelve_tiles_only() -> void:
	for gap in [11, 12, 13]:
		var s2 := Settlement.new_game(SEED, reg)
		s2.era_override = "conflux"
		var g2 := s2.get_system(GridSystem) as GridSystem
		_clear(s2, false)
		var a := s2.place_building_instant("lumen_pylon", Vector2i(h.x + 13, h.y - 3))
		var b := s2.place_building_instant("lumen_pylon", Vector2i(h.x + 13 - gap, h.y - 3))
		assert_true(a >= 0 and b >= 0)
		var linked := g2.grid_of(s2, a) == g2.grid_of(s2, b)
		assert_eq(linked, gap <= 12, "pylons %d tiles apart" % gap)
		assert_eq(g2.links(s2).size(), 1 if gap <= 12 else 0)
		assert_eq(g2.grid_ids(s2).size(), 1 if gap <= 12 else 2)


func test_chain_of_pylons_and_nexus_is_one_grid() -> void:
	var a := _put("lumen_pylon", 13)
	var b := _put("lumen_pylon", 1)
	var nexus := s.place_building_instant("lumen_nexus", Vector2i(h.x + 8, h.y + 2))
	assert_true(nexus >= 0)
	assert_eq(gs.grid_of(s, a.id), gs.grid_of(s, b.id))
	assert_eq(gs.grid_of(s, nexus), gs.grid_of(s, a.id), "the Nexus links like a pylon")
	assert_eq(gs.nodes_of(s, gs.grid_of(s, a.id)).size(), 3)


func test_cache_rebuilds_on_demolition() -> void:
	var p := _put("lumen_pylon", 3)
	var c := _put(UP_ID, 6)
	assert_true(GridSystem.on_grid(s, c))
	assert_true(s.demolish(p.id))
	assert_false(GridSystem.on_grid(s, c), "no node left")
	assert_eq(gs.grid_ids(s).size(), 0)


func test_grid_save_roundtrip_keeps_membership() -> void:
	var p := _put("lumen_pylon", 3)
	var c := _put(UP_ID, 6)
	assert_true(GridSystem.on_grid(s, c))
	var s2 := Settlement.from_dict(s.to_dict(), reg)
	var g2 := s2.get_system(GridSystem) as GridSystem
	assert_eq(g2.grid_of(s2, c.id), gs.grid_of(s, c.id))
	assert_eq(g2.grid_of(s2, p.id), p.id)
