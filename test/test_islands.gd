extends GutTest
## Ticket 40: Lift Anchor, the sky layer and islands. Command API plus step_days, headless.

const SEED := 42
const SAVE_PATH := "user://test_islands.sav"

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	# Island buildings do not exist as data yet (ticket 41): inject two into this private registry.
	var hut := BuildingDef.new()
	hut.id = "test_sky_hut"
	hut.display_name = "Sky hut"
	hut.era = "camp"
	hut.category = "civic"
	hut.size = Vector2i(2, 2)
	hut.layers = "island"
	reg.buildings[hut.id] = hut
	var tap := BuildingDef.new()
	tap.id = "test_sky_tap"
	tap.display_name = "Sky tap"
	tap.era = "camp"
	tap.category = "lumen"
	tap.size = Vector2i(2, 2)
	tap.layers = "island"
	tap.blight_radius = 3
	tap.blight_period_days = 1
	reg.buildings[tap.id] = tap


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


func _isl() -> IslandSystem:
	return s.get_system(IslandSystem) as IslandSystem


## A free 3x3 anchor spot inside region r (owns the region first).
func _anchor_spot(r: int) -> Vector2i:
	s.map.set_region_owned(r, true)
	var rr := MapState.region_rect(r)
	for y in range(rr.position.y, rr.end.y - 3):
		for x in range(rr.position.x, rr.end.x - 3):
			if s.can_place("lift_anchor", Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _instant_anchor(r: int) -> int:
	return s.place_building_instant("lift_anchor", _anchor_spot(r))


## A finished Sky Foundry on the first free 3x3 spot of the start region.
func _foundry() -> int:
	var rr := MapState.region_rect(s.map.start_region)
	for y in range(rr.position.y, rr.end.y - 3):
		for x in range(rr.position.x, rr.end.x - 3):
			if s.can_place("sky_foundry", Vector2i(x, y), true)["ok"]:
				return s.place_building_instant("sky_foundry", Vector2i(x, y))
	return -1


func _sky_count() -> int:
	return s.sky_map.terrain.count(s.sky_map.terrain_index("skystone"))


func test_data_rows() -> void:
	var def := reg.get_building("lift_anchor")
	assert_eq(def.size, Vector2i(3, 3))
	assert_eq(def.layers, "ground")
	assert_eq(def.worker_slots, 2)
	assert_eq(reg.logistics.island_max, 4)
	var st := reg.get_terrain("skystone")
	assert_true(st.buildable)
	assert_eq(st.fertility_start, 0.0)


# AC1: the fifth island is rejected (sites count), and a second anchor in one region.
func test_fifth_anchor_rejected_with_island_cap() -> void:
	for r in 4:
		assert_gt(_instant_anchor(r), -1, "anchor %d" % r)
	assert_eq(_isl().islands.size(), 4)
	s.map.set_region_owned(4, true)
	var rr := MapState.region_rect(4)
	var res := s.can_place("lift_anchor", rr.position + Vector2i(5, 5), true)
	assert_false(res["ok"])
	assert_eq(res["reason"], "island_cap")
	assert_eq(s.place_building_instant("lift_anchor", rr.position + Vector2i(5, 5)), -1)


func test_sites_count_toward_the_cap_and_region_limit() -> void:
	s.era_override = "skyborne"
	s.gold = 5000.0
	var spots: Array[Vector2i] = []
	for r in 4:
		spots.append(_anchor_spot(r))
	for r in 4:
		assert_gt(s.place_building("lift_anchor", spots[r]), -1, "site %d" % r)
	assert_eq(_isl().islands.size(), 0, "sites raise nothing")
	s.map.set_region_owned(4, true)
	var res := s.can_place("lift_anchor", MapState.region_rect(4).position + Vector2i(5, 5))
	assert_eq(res["reason"], "island_cap")


func test_second_anchor_in_a_region_rejected() -> void:
	var o := _anchor_spot(0)
	assert_gt(s.place_building_instant("lift_anchor", o), -1)
	var res := {"ok": true, "reason": ""}
	var rr := MapState.region_rect(0)
	for y in range(rr.position.y, rr.end.y - 3):
		for x in range(rr.position.x, rr.end.x - 3):
			var t := Vector2i(x, y)
			var r := s.can_place("lift_anchor", t, true)
			if r["reason"] != "overlap" and r["reason"] != "road":
				res = r
				break
		if not res["ok"]:
			break
	assert_eq(res["reason"], "region_island")
	assert_eq(_isl().islands.size(), 1)


func test_island_appears_only_on_completion_and_is_centred() -> void:
	s.era_override = "skyborne"
	s.gold = 5000.0
	var o := _anchor_spot(1)
	var id := s.place_building("lift_anchor", o)
	assert_gt(id, -1)
	assert_eq(_sky_count(), 0)
	assert_eq(_isl().islands.size(), 0)
	s.step_days(1)
	assert_eq(_isl().islands.size(), 0, "still a site")
	s.complete_site(s.buildings[id])
	assert_eq(_isl().islands.size(), 1)
	assert_eq(_sky_count(), 16 * 12)
	var isl := _isl().islands[0]
	var rr := MapState.region_rect(1)
	assert_eq(isl.rect, Rect2i(rr.position + Vector2i(8, 6), Vector2i(16, 12)))
	assert_eq(isl.region, 1)
	assert_eq(isl.anchor_id, id)
	assert_eq(s.sky_map.terrain_id_at(isl.rect.position.x, isl.rect.position.y), "skystone")
	assert_eq(s.sky_map.terrain_id_at(isl.rect.position.x - 1, isl.rect.position.y), "void")


func test_sky_placement_only_on_skystone() -> void:
	var rect := Rect2i()
	assert_false(s.can_place("test_sky_hut", s.map.hearth_spot, true, Building.LAYER_SKY)["ok"], "no island yet")
	assert_eq(s.can_place("test_sky_hut", s.map.hearth_spot, true, Building.LAYER_SKY)["reason"], "no_island")
	assert_gt(_instant_anchor(1), -1)
	rect = _isl().islands[0].rect
	var inside := rect.position + Vector2i(3, 3)
	assert_true(s.can_place("test_sky_hut", inside, true, Building.LAYER_SKY)["ok"])
	# off the edge of the island
	assert_eq(s.can_place("test_sky_hut", rect.position - Vector2i(1, 0), true, Building.LAYER_SKY)["reason"], "no_island")
	# wrong layer for the def
	assert_eq(s.can_place("test_sky_hut", inside, true)["reason"], "wrong_layer")
	assert_eq(s.can_place("lift_anchor", inside, true, Building.LAYER_SKY)["reason"], "wrong_layer")
	var id := s.place_building_instant("test_sky_hut", inside, Building.LAYER_SKY)
	assert_gt(id, -1)
	var b: Building = s.buildings[id]
	assert_eq(b.layer, Building.LAYER_SKY)
	assert_eq(s.building_at(inside, Building.LAYER_SKY), b)
	assert_null(s.building_at(inside), "ground tile below is untouched")
	assert_eq(s.can_place("test_sky_hut", inside, true, Building.LAYER_SKY)["reason"], "overlap")
	# a ground tile under the island is still free for a ground building
	assert_true(s.can_place("tent", inside, true)["ok"] or s.can_place("tent", inside, true)["reason"] != "overlap")
	# sky roads only on skystone
	assert_true(s.place_road(rect.position + Vector2i(8, 8), Settlement.ROAD_DIRT, Building.LAYER_SKY))
	assert_false(s.place_road(rect.position - Vector2i(1, 1), Settlement.ROAD_DIRT, Building.LAYER_SKY))
	assert_eq(s.can_place("test_sky_hut", rect.position + Vector2i(8, 8), true, Building.LAYER_SKY)["reason"], "road")


# AC2: skystone never blights and has no soil.
func test_skystone_never_blights_and_has_no_soil() -> void:
	assert_gt(_instant_anchor(1), -1)
	var rect := _isl().islands[0].rect
	var tap := s.place_building_instant("test_sky_tap", rect.position + Vector2i(4, 4), Building.LAYER_SKY)
	assert_gt(tap, -1)
	# blight the ground under the island
	var before := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if s.set_blighted(Vector2i(x, y), true):
				before += 1
	assert_gt(before, 0)
	var ground_blight := BlightSystem.count(s)
	s.step_days(6)
	assert_eq(s.sky_map.blight.count(1), 0, "no sky tile blighted")
	assert_eq(s.sky_map.fertility.count(0), s.sky_map.fertility.size(), "no sky soil")
	assert_eq(BlightSystem.count(s), ground_blight, "a sky extractor does not blight the ground either")
	var b: Building = s.buildings[tap]
	assert_false(BlightSystem.near_blight(s, b))
	assert_false(BlightSystem.blight_hits(s, b))
	var fs := s.get_system(FertilitySystem) as FertilitySystem
	assert_eq(fs.mean_fertility(s, b), 0.0)
	assert_eq(reg.get_terrain("skystone").fertility_start, 0.0)


# AC3: the first anchor after the Sky Foundry costs nothing, the second pays.
func test_first_anchor_after_foundry_is_free_and_second_pays() -> void:
	s.era_override = "skyborne"
	s.gold = 1000.0
	var a := _anchor_spot(1)
	var b2 := _anchor_spot(2)
	assert_eq(s.cost_for("lift_anchor"), reg.get_building("lift_anchor").cost, "no Foundry, no free anchor")
	assert_gt(_foundry(), -1)
	assert_eq(s.cost_for("lift_anchor"), {})
	var id1 := s.place_building("lift_anchor", a)
	assert_gt(id1, -1)
	assert_eq(s.gold, 1000.0, "no gold charged")
	assert_true(s.free_anchor_used)
	var site: Building = s.buildings[id1]
	assert_true(site.site)
	assert_eq(HaulingSystem.need_of(reg, site), {}, "no goods to haul")
	assert_true(site.site_delivered())
	assert_eq(s.cost_for("lift_anchor"), reg.get_building("lift_anchor").cost)
	var id2 := s.place_building("lift_anchor", b2)
	assert_gt(id2, -1)
	assert_eq(s.gold, 700.0, "the second anchor pays 300 gold")
	assert_gt(HaulingSystem.need_of(reg, s.buildings[id2]).size(), 0)
	# demolishing the free site refunds nothing
	var g := s.gold
	assert_true(s.demolish(id1))
	assert_eq(s.gold, g)


func test_free_anchor_builders_finish_it() -> void:
	s.era_override = "skyborne"
	assert_gt(_foundry(), -1)
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 1, h.y + 5):
			if s.map.terrain_id_at(x, y) in ["forest", "water", "lumen_vein"]:
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	var id := s.place_building("lift_anchor", Vector2i(h.x + 4, h.y + 1))
	assert_gt(id, -1, "free anchor site placed beside the road")
	s.step_days(12)
	assert_false((s.buildings[id] as Building).site, "builders finished the free site")
	assert_eq(_isl().islands.size(), 1)


func test_demolish_anchor_rules() -> void:
	var id := _instant_anchor(1)
	var rect := _isl().islands[0].rect
	var hut := s.place_building_instant("test_sky_hut", rect.position + Vector2i(2, 2), Building.LAYER_SKY)
	assert_false(s.demolish(id), "an island with a building on it stays")
	assert_eq(_isl().islands.size(), 1)
	assert_true(s.demolish(hut))
	s.place_road(rect.position + Vector2i(5, 5), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	assert_true(s.demolish(id))
	assert_eq(_isl().islands.size(), 0)
	assert_eq(_sky_count(), 0)
	assert_eq(s.sky_roads.count(0), s.sky_roads.size(), "sky road gone with its island")
	assert_gt(_instant_anchor(1), -1, "the region can raise a new island")


func test_save_round_trip_island_with_sky_building() -> void:
	s.era_override = "skyborne"
	s.gold = 900.0
	assert_gt(_foundry(), -1)
	var spot := _anchor_spot(1)
	var aid := s.place_building("lift_anchor", spot)  # free: sets free_anchor_used
	s.complete_site(s.buildings[aid])
	var rect := _isl().islands[0].rect
	var hid := s.place_building_instant("test_sky_hut", rect.position + Vector2i(3, 3), Building.LAYER_SKY)
	s.place_road(rect.position + Vector2i(8, 8), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	assert_eq(SaveGame.save(s, SAVE_PATH), OK)
	var l := SaveGame.load(SAVE_PATH, reg)
	assert_not_null(l)
	if l == null:
		return
	var li := l.get_system(IslandSystem) as IslandSystem
	assert_eq(li.islands.size(), 1)
	assert_eq(li.islands[0].rect, rect)
	assert_eq(li.islands[0].anchor_id, aid)
	assert_eq(li.islands[0].id, _isl().islands[0].id)
	assert_eq(l.sky_map.terrain, s.sky_map.terrain)
	assert_eq(l.sky_occupancy, s.sky_occupancy)
	assert_eq(l.sky_roads, s.sky_roads)
	assert_eq((l.buildings[hid] as Building).layer, Building.LAYER_SKY)
	assert_eq(l.building_at(rect.position + Vector2i(3, 3), Building.LAYER_SKY).id, hid)
	assert_true(l.free_anchor_used)
	assert_true((l.buildings[aid] as Building).cost_free)
	assert_false(l.demolish(aid), "the loaded island still holds its building")


func test_old_save_without_sky_keys_loads_with_no_islands() -> void:
	var d := s.to_dict()
	for k in ["sky_map", "sky_occupancy", "sky_roads", "free_anchor_used"]:
		d.erase(k)
	(d["systems"] as Dictionary).erase("islands")
	var l := Settlement.from_dict(d, reg)
	assert_not_null(l)
	assert_eq((l.get_system(IslandSystem) as IslandSystem).islands.size(), 0)
	assert_eq(l.sky_map.terrain.count(0), l.sky_map.terrain.size())
	assert_false(l.free_anchor_used)
