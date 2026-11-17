extends GutTest
## Ticket 41: Skyspire and Cloud Cistern (design.md section 17). Settlement API plus step_hours.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var anchor: Building
var isl: Island


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "skyborne"
	h = s.map.hearth_spot
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 5, h.y + 6):
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
	s.hearth.inventory.add("lumen", 400.0)
	s.step_seconds(0.01)
	JobSystem.refresh(s)


func _isl() -> IslandSystem:
	return s.get_system(IslandSystem) as IslandSystem


func _cov() -> CoverageSystem:
	return s.get_system(CoverageSystem) as CoverageSystem


## Island-relative tile (dx, dy from the rect corner).
func _at(dx: int, dy: int) -> Vector2i:
	return isl.rect.position + Vector2i(dx, dy)


func _sky(def_id: String, dx: int, dy: int) -> Building:
	var id := s.place_building_instant(def_id, _at(dx, dy), Building.LAYER_SKY)
	assert_true(id >= 0, "%s placed on the island" % def_id)
	return s.buildings[id]


func test_data_rows() -> void:
	var sp := reg.get_building("skyspire")
	assert_eq(sp.era, "skyborne")
	assert_eq(sp.size, Vector2i(2, 2))
	assert_eq(sp.cost, {"materials": 160, "gold": 60, "planks": 40, "cut_stone": 40, "tools": 20})
	assert_eq(sp.housing_beds, 40)
	assert_eq(sp.upkeep_lumen, 2.0)
	assert_true(sp.needs_water)
	assert_eq(sp.layers, "either")
	assert_false(sp.upgradable)
	var cc := reg.get_building("cloud_cistern")
	assert_eq(cc.size, Vector2i(2, 1))
	assert_eq(cc.cost, {"materials": 60, "gold": 20, "cut_stone": 20})
	assert_eq(cc.upkeep_lumen, 0.0)
	assert_eq(cc.worker_slots, 0)
	assert_eq(cc.layers, "island")
	assert_eq(cc.water_radius, 10)
	assert_eq(cc.wet_radius, 3)


# AC1: the Cistern is island-only; the Skyspire places on either layer.
func test_cistern_island_only_skyspire_either() -> void:
	var g := Vector2i(h.x + 8, h.y + 3)
	assert_eq(s.can_place("cloud_cistern", g, true)["reason"], "wrong_layer")
	assert_eq(s.place_building_instant("cloud_cistern", g), -1)
	assert_true(s.can_place("cloud_cistern", _at(1, 1), true, Building.LAYER_SKY)["ok"])
	assert_true(s.can_place("skyspire", g, true)["ok"], "ground")
	assert_true(s.can_place("skyspire", _at(1, 1), true, Building.LAYER_SKY)["ok"], "island")
	assert_eq(_sky("cloud_cistern", 1, 1).layer, Building.LAYER_SKY)


# AC2: the Cistern waters homes within r10 on its island, not r11, not the ground, and wets r3 of the sky only.
func test_cistern_water_range_and_wet() -> void:
	var cc := _sky("cloud_cistern", 0, 0)  # tiles x0..1, y0
	var near := _sky("skyspire", 11, 0)  # gap 10
	var far := _sky("skyspire", 12, 4)  # gap 11
	assert_eq(Building.footprint_gap(cc, near), 10)
	assert_eq(Building.footprint_gap(cc, far), 11)
	assert_true(_cov().home_has_water(s, near.id), "r10 is served")
	assert_false(_cov().home_has_water(s, far.id), "r11 is not")
	# A ground Skyspire right under the island is not served by the sky cistern.
	var gid := s.place_building_instant("skyspire", _at(0, 2))
	if gid >= 0:
		assert_false(_cov().home_has_water(s, gid), "ground home under the island")
	# Wet: r3 around the 2x1 footprint on the sky, nothing on the ground.
	WaterSystem.recompute(s)
	assert_true(s.sky_map.is_wet(_at(4, 0).x, _at(4, 0).y), "x1 + 3")
	assert_false(s.sky_map.is_wet(_at(5, 0).x, _at(5, 0).y), "x1 + 4")
	assert_true(s.sky_map.is_wet(_at(0, 3).x, _at(0, 3).y), "y0 + 3")
	assert_false(s.sky_map.is_wet(_at(0, 4).x, _at(0, 4).y), "y0 + 4")
	var ground_wet_under := 0
	for y in range(isl.rect.position.y, isl.rect.position.y + 4):
		for x in range(isl.rect.position.x, isl.rect.position.x + 5):
			if s.map.is_wet(x, y) and s.map.get_terrain(x, y) != s.map.terrain_index("water"):
				ground_wet_under += 1
	# Ground wetness near the Hearth may come from terrain; the sky stamp must not add tiles. Compare to a no-cistern run.
	s.demolish(cc.id)
	WaterSystem.recompute(s)
	var after := 0
	for y in range(isl.rect.position.y, isl.rect.position.y + 4):
		for x in range(isl.rect.position.x, isl.rect.position.x + 5):
			if s.map.is_wet(x, y) and s.map.get_terrain(x, y) != s.map.terrain_index("water"):
				after += 1
	assert_eq(ground_wet_under, after, "the cistern wets no ground tile")
	assert_false(s.sky_map.is_wet(_at(4, 0).x, _at(4, 0).y), "demolished: sky dry again")


func test_ground_wet_does_not_leak_to_sky() -> void:
	s.place_building_instant("water_tower", Vector2i(h.x + 8, h.y + 3))
	WaterSystem.recompute(s)
	assert_true(s.map.is_wet(h.x + 8, h.y + 3))
	assert_eq(s.sky_map.wet.count(1), 0, "a ground tower wets no sky tile")


func test_sky_skyspire_lacks_water_and_ground_well_does_not_serve_it() -> void:
	var sp := _connected_sky_skyspire()
	assert_false(_cov().home_has_water(s, sp.id), "no cistern")
	s.place_building_instant("water_tower", Vector2i(h.x + 8, h.y + 3))
	assert_false(_cov().home_has_water(s, sp.id), "a ground tower does not serve the sky")
	_house_one(sp)
	assert_lt(CoverageSystem.water_factor(s), 0.0, "missing water costs Spirit")
	var cid := s.place_building_instant("cloud_cistern", sp.origin + Vector2i(0, 3), Building.LAYER_SKY)
	assert_true(cid >= 0, "cistern placed")
	assert_true(_cov().home_has_water(s, sp.id))
	assert_eq(CoverageSystem.water_factor(s), 0.0)


func test_still_island_cistern_serves_nobody() -> void:
	var cc := _sky("cloud_cistern", 0, 0)
	var sp := _sky("skyspire", 4, 0)
	assert_true(_cov().home_has_water(s, sp.id))
	_isl().islands[0].still_why = "short_lumen"
	s.structure_version += 1
	assert_false(_cov().home_has_water(s, sp.id))
	WaterSystem.recompute(s)
	assert_eq(s.sky_map.wet.count(1), 0, "and wets nothing")
	assert_not_null(cc)


# Citizens move into a connected sky Skyspire (through a Sky Lift and a sky road).
func test_citizens_move_into_connected_skyspire() -> void:
	var lift_t := Vector2i(-1, -1)
	for x in range(h.x + 2, h.x + 5):
		var t := Vector2i(x, h.y + 1)
		if isl.rect.has_point(t) and isl.rect.has_point(t + Vector2i(3, 1)) and s.can_place("sky_lift", t, true)["ok"]:
			lift_t = t
			break
	assert_true(lift_t.x >= 0)
	var lid := s.place_building_instant("sky_lift", lift_t)
	assert_true(lid >= 0)
	s.place_road(lift_t + Vector2i(1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	var sid := s.place_building_instant("skyspire", lift_t + Vector2i(2, 0), Building.LAYER_SKY)
	assert_true(sid >= 0)
	var sp: Building = s.buildings[sid]
	assert_true(sp.connected, "joined to the lift")
	_house_one(sp)
	var living := 0
	for c: Citizen in s.citizens.values():
		if c.home_id == sp.id:
			living += 1
	assert_gt(living, 0, "citizens live in the sky Skyspire")


## A Skyspire joined to a Sky Lift by a sky road (a sky home only takes residents when connected, ticket 41b).
func _connected_sky_skyspire() -> Building:
	for x in range(h.x + 2, h.x + 5):
		var t := Vector2i(x, h.y + 1)
		if isl.rect.has_point(t) and isl.rect.has_point(t + Vector2i(3, 4)) and s.can_place("sky_lift", t, true)["ok"]:
			assert_true(s.place_building_instant("sky_lift", t) >= 0)
			s.place_road(t + Vector2i(1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
			var sid := s.place_building_instant("skyspire", t + Vector2i(2, 0), Building.LAYER_SKY)
			assert_true(sid >= 0)
			return s.buildings[sid]
	fail_test("no lift spot")
	return null


## Adds citizens until the Hearth's beds overflow, runs the job system, and expects some to live in `sp`.
func _house_one(sp: Building) -> void:
	while s.citizens.size() < s.hearth.def.housing_beds + 4:
		s.add_citizen()
	s.step_hours(2)
	JobSystem.refresh(s)
	for c: Citizen in s.citizens.values():
		if c.home_id == sp.id:
			return
	fail_test("nobody moved into the Skyspire")
