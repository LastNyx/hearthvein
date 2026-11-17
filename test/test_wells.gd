extends GutTest
## Ticket 29: Wells and drinking water (design.md sections 9 and 11).
## A Well is 1x1 on a wet tile and serves homes from Rowhouse up within r8; homes without it cost Spirit.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var cov: CoverageSystem
var sp: SpiritSystem
var h: Vector2i
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	cov = s.get_system(CoverageSystem)
	sp = s.get_system(SpiritSystem)
	h = s.map.hearth_spot


func _owned(t: Vector2i) -> bool:
	return s.map.is_region_owned(s.map.get_region(t.x, t.y))


## First owned, empty land tile that is wet and can take a Well (forest is cleared to grass).
func _wet_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if not _owned(t) or s.map.terrain_id_at(x, y) == "water" or not s.map.is_wet(x, y):
				continue
			if s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE:
				continue
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(t, "grass")
			if s.can_place("well", t, true)["ok"]:
				return t
	return Vector2i(-1, -1)


## First owned, empty, dry tile that a 1x1 "any" building could take (a Well must refuse it).
func _dry_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if not _owned(t) or s.map.is_wet(x, y):
				continue
			if s.can_place("cottage", t, true)["ok"]:
				return t
	return Vector2i(-1, -1)


## A finished building inserted straight into the layout (sources and homes for the coverage query). Bumps
## structure_version so the coverage caches rebuild.
func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	s.buildings[b.id] = b
	s.structure_version += 1
	return b


## Moves every starting citizen into `home_id` (sorted by citizen id).
func _all_live_in(home_id: int) -> void:
	for cid in s.citizens:
		(s.citizens[cid] as Citizen).home_id = home_id


func _sorted_citizen_ids() -> Array:
	var ids: Array = s.citizens.keys()
	ids.sort()
	return ids


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


# Data: the Well is the Town table's row, 1x1 on wet ground, 25M 5S, no workers, drinking water r8.
func test_well_data_matches_the_town_table() -> void:
	var d := reg.get_building("well")
	assert_not_null(d)
	assert_eq([d.era, d.category], ["town", "water"])
	assert_eq([d.size, d.cost], [Vector2i(1, 1), {"materials": 25, "cut_stone": 5}])
	assert_eq([d.worker_slots, d.upkeep_lumen], [0, 0.0])
	assert_eq([d.placement_rule, d.water_radius], ["on_wet", 8])
	assert_false(d.needs_water, "a Well supplies water, it does not need it")
	assert_null(d.recipe, "no workers, it makes nothing")


# AC1: a Well places on a wet tile and nowhere else.
func test_well_places_only_on_a_wet_tile() -> void:
	var wet := _wet_spot()
	assert_ne(wet, Vector2i(-1, -1), "an owned wet tile that can take a Well")
	assert_true(s.can_place("well", wet)["ok"])
	assert_gt(s.place_building_instant("well", wet), -1)
	var dry := _dry_spot()
	assert_ne(dry, Vector2i(-1, -1), "an owned dry tile")
	assert_eq(s.can_place("well", dry, true), {"ok": false, "reason": "needs_wet"})
	assert_eq(s.place_building_instant("well", dry), -1, "a site is refused on dry ground too")
	s.map.set_wet(dry.x, dry.y, true)
	assert_true(s.can_place("well", dry, true)["ok"], "the rule reads the wet grid, not the terrain")
	s.map.set_wet(dry.x, dry.y, false)
	assert_eq(s.can_place("well", dry, true), {"ok": false, "reason": "needs_wet"})


func test_well_is_a_town_unlock() -> void:
	var o := _wet_spot()
	assert_ne(o, Vector2i(-1, -1), "an owned wet tile that can take a Well")
	s.era_override = ""
	assert_eq(s.can_place("well", o), {"ok": false, "reason": "era_locked"})
	s.era_override = "town"
	assert_true(s.can_place("well", o)["ok"])
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("well"))


# AC2 data: Rowhouse and later homes need water; Tent, Cottage and Hearth never do.
func test_rowhouse_needs_water_and_earlier_homes_do_not() -> void:
	assert_true(reg.get_building("rowhouse").needs_water)
	for id in ["tent", "cottage", "hearth"]:
		assert_false(reg.get_building(id).needs_water, "%s never needs a well" % id)


# The water query is Chebyshev from the footprint, r8 for a Well, and separate from Shrine coverage.
func test_well_serves_homes_within_r8_only() -> void:
	_fake("well", Vector2i(200, 200))
	var near := _fake("rowhouse", Vector2i(208, 200))  # 8 tiles east of the Well's tile
	var far := _fake("rowhouse", Vector2i(212, 200))
	assert_true(cov.home_has_water(s, near.id), "r8 covers 8 tiles")
	assert_false(cov.home_has_water(s, far.id), "12 tiles is out")
	var cottage := _fake("cottage", Vector2i(202, 202))
	assert_true(cov.home_has_water(s, cottage.id), "a Cottage inside the radius is covered, it just does not need it")
	var served := cov.water_served_homes(s)
	assert_true(served.has(near.id))
	assert_false(served.has(far.id))
	assert_eq(served, cov.water_served_homes(s), "the cache is stable while the layout is")


func test_a_well_site_serves_no_water() -> void:
	var o := _wet_spot()
	assert_ne(o, Vector2i(-1, -1), "an owned wet tile that can take a Well")
	assert_true(s.place_building("well", o) >= 0, "a construction site")
	var home := _fake("rowhouse", o + Vector2i(2, 0))
	assert_false(cov.home_has_water(s, home.id), "a site has no water coverage")


# AC2: a Rowhouse outside every well counts as missing water; a Cottage never does.
func test_rowhouse_outside_well_range_counts_as_missing_water() -> void:
	var home := _fake("rowhouse", Vector2i(220, 220))
	_all_live_in(home.id)
	assert_eq(_factor("water"), -reg.spirit.water_max, "every water-needing home lacks a well")
	_fake("well", Vector2i(212, 220))  # 8 tiles west: just in range
	assert_eq(_factor("water"), 0.0, "the Well now serves the Rowhouse")


func test_cottages_never_count_as_missing_water() -> void:
	var home := _fake("cottage", Vector2i(240, 240))
	_all_live_in(home.id)
	assert_eq(_factor("water"), 0.0, "no home that needs water, no penalty")
	var ids := _sorted_citizen_ids()
	assert_eq((s.citizens[ids[0]] as Citizen).home_id, home.id)
	assert_eq(s.homeless_count(), 0)


# The share is weighed by housed citizens in homes that need water (like the coverage factor weighs citizens).
func test_water_share_is_weighed_by_housed_citizens() -> void:
	var served := _fake("rowhouse", Vector2i(208, 200))
	var unserved := _fake("rowhouse", Vector2i(230, 200))
	_fake("well", Vector2i(200, 200))  # serves the first Rowhouse only
	var cottage := _fake("cottage", Vector2i(240, 240))
	var ids := _sorted_citizen_ids()
	assert_eq(ids.size(), Settlement.START_CITIZENS)
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.home_id = served.id if i == 0 else (cottage.id if i >= 6 else unserved.id)
	# 1 served, 5 unserved of the 6 citizens in water-needing homes; the 2 in the Cottage are not counted.
	assert_almost_eq(_factor("water"), -reg.spirit.water_max * 5.0 / 6.0, 0.001)
	assert_eq(s.homeless_count(), 0)


# A Well gives no Spirit coverage and a Shrine gives no drinking water: the two fields never mix.
func test_wells_do_not_count_as_shrine_coverage() -> void:
	var covered_home := _fake("rowhouse", Vector2i(240, 200))
	_fake("shrine", Vector2i(246, 200))  # covers the home, no water
	assert_true(cov.home_covered(s, covered_home.id))
	assert_false(cov.home_has_water(s, covered_home.id), "a Shrine provides no drinking water")
	var watered_home := _fake("rowhouse", Vector2i(260, 200))
	_fake("well", Vector2i(252, 200))  # 8 tiles west, no Spirit coverage
	assert_true(cov.home_has_water(s, watered_home.id))
	assert_false(cov.home_covered(s, watered_home.id), "a Well gives no Spirit coverage")
