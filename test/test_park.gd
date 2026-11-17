extends GutTest
## Ticket 33d: Park (design.md sections 11, 13 and 16 City). Its 2x2 footprint never blights, it covers homes in r5
## and adds its +0.005/day planet health term with no workers.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var bs: BlightSystem
var cov: CoverageSystem
var ph: PlanetHealthSystem
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "city"
	h = s.map.hearth_spot
	bs = s.get_system(BlightSystem) as BlightSystem
	cov = s.get_system(CoverageSystem) as CoverageSystem
	ph = s.get_system(PlanetHealthSystem) as PlanetHealthSystem


## A placeable Park (2x2) spot near the Hearth.
func _spot() -> Vector2i:
	for r in range(2, 16):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place("park", Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## A dry (no water) open centre with `radius` tiles around it, so spread tests are not cut short by the river.
func _dry_center(radius: int) -> Vector2i:
	for y in range(radius + 1, MapState.HEIGHT - radius - 1):
		for x in range(radius + 1, MapState.WIDTH - radius - 1):
			var ok := true
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var t := Vector2i(x + dx, y + dy)
					if s.map.terrain_id_at(t.x, t.y) == "water" or s.building_at(t) != null:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A finished building inserted straight into the layout (no cost, no road), occupying its tiles.
func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	s.buildings[b.id] = b
	for t in b.tiles():
		s.occupancy[MapState.idx(t.x, t.y)] = b.id
	s.structure_version += 1
	return b


func _forest_count() -> int:
	var fi := s.map.terrain_index("forest")
	return s.map.terrain.count(fi) if fi >= 0 else 0


# AC0: the data row is the City table's, with the coverage and planet numbers in data, not code.
func test_data_matches_the_city_row() -> void:
	var d := reg.get_building("park")
	assert_not_null(d, "data/buildings/park.tres exists")
	assert_eq([d.era, d.category, d.size], ["city", "civic", Vector2i(2, 2)])
	assert_eq(d.cost, {"materials": 40, "gold": 10})
	assert_eq([d.worker_slots, d.upkeep_lumen], [0, 0.0])
	assert_eq(d.coverage_radius, 5, "section 16: Spirit coverage r5")
	assert_true(d.blight_proof, "section 12: the footprint is blight-proof")
	assert_true(d.blocked_by_blight, "section 12: blighted ground cannot hold a Park")
	assert_almost_eq(d.health_per_day, 0.005, 0.0000001, "section 13: Park +0.005/day")
	assert_null(d.recipe)
	s.era_override = "town"
	assert_false(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "park"))


# A blighted tile blocks Park placement (BuildingDef.blocked_by_blight, ticket 23b).
func test_blighted_ground_cannot_hold_a_park() -> void:
	var o := _spot()
	assert_ne(o, Vector2i(-1, -1), "a Park fits near the Hearth")
	assert_true(s.set_blighted(o, true))
	assert_eq(s.can_place("park", o), {"ok": false, "reason": "blighted"})


# AC1: the spread never picks a finished Park's footprint; blocked tiles are skipped, not filled.
func test_park_footprint_never_blights() -> void:
	var c := _dry_center(6)
	assert_ne(c, Vector2i(-1, -1), "a dry open area on the map")
	var pump := _fake("lumen_pump", c)                  # 1x1, blights r4/3d
	var park := _fake("park", c + Vector2i(2, -1))      # 2x2: (2,-1) .. (3,0) from c, inside the pump's r4
	var blighted := 0
	while true:
		var t := bs.next_tile(s, pump)
		if t.x < 0:
			break
		assert_false(park.footprint().has_point(t), "the spread picked a Park tile %s" % t)
		assert_true(s.set_blighted(t, true))
		blighted += 1
		assert_lt(blighted, 200, "the spread must run out of eligible tiles")
	assert_gt(blighted, 0, "the pump still spreads outside the Park")
	for t in park.tiles():
		assert_false(s.map.is_blighted(t.x, t.y), "Park tile %s stayed clear" % t)


# A Park still being built is not yet park land: only a finished one shields its footprint.
func test_park_site_does_not_shield_its_footprint() -> void:
	var c := _dry_center(6)
	assert_ne(c, Vector2i(-1, -1), "a dry open area on the map")
	var pump := _fake("lumen_pump", c)
	var park := _fake("park", c + Vector2i(1, 0))
	park.site = true
	for t in [c + Vector2i(-1, 0), c + Vector2i(0, -1), c + Vector2i(0, 1)]:
		assert_true(s.set_blighted(t, true), "the neighbours outside the site are already blighted")
	assert_true(park.footprint().has_point(bs.next_tile(s, pump)), "a site does not block blight")
	park.site = false
	assert_false(park.footprint().has_point(bs.next_tile(s, pump)), "a finished Park shields its footprint")


# AC2a: Park coverage r5 is the shared CoverageSystem query, measured footprint to footprint.
func test_park_covers_homes_in_r5() -> void:
	var c := _dry_center(8)
	assert_ne(c, Vector2i(-1, -1), "a dry open area on the map")
	_fake("park", c)
	var near := _fake("tent", c + Vector2i(6, 0))  # Chebyshev gap 5 from the 2x2 footprint
	var far := _fake("tent", c + Vector2i(7, 0))   # gap 6
	assert_true(cov.home_covered(s, near.id), "a home 5 tiles out is covered")
	assert_false(cov.home_covered(s, far.id), "a home 6 tiles out is not")
	assert_true(cov.covered_homes(s).has(near.id))
	assert_false(cov.covered_homes(s).has(far.id))


# AC2b: the Park adds its planet health term while finished, with no workers needed.
func test_park_adds_its_planet_health_term() -> void:
	var c := _dry_center(8)
	assert_ne(c, Vector2i(-1, -1), "a dry open area on the map")
	var park := _fake("park", c)
	assert_true(PlanetHealthSystem.is_working(s, park), "a finished Park works with nobody assigned")
	assert_almost_eq(float(ph.daily_breakdown(s)["buildings"]), 0.005, 0.0000001,
			"section 13: Park +0.005/day")
	ph.value = 50.0
	s.step_days(1)
	var want := 0.005 + float(_forest_count()) * reg.planet.per_forest_tile
	assert_almost_eq(s.planet_health() - 50.0, want, 0.0000001, "the daily delta carries the Park's term")
	park.paused = true
	assert_false(PlanetHealthSystem.is_working(s, park), "a paused Park adds nothing")
	assert_eq(float(ph.daily_breakdown(s)["buildings"]), 0.0)
