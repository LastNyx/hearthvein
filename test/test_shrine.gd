extends GutTest
## Ticket 23b: Shrine coverage, the reusable coverage query and the Spirit coverage factor (design.md sections 11, 12,
## 16 Village).

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
	s.era_override = "village"
	cov = s.get_system(CoverageSystem)
	sp = s.get_system(SpiritSystem)
	h = s.map.hearth_spot


## A cleared strip east of the Hearth with a road along its middle (the patch test_market uses).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 20):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## First placeable origin for `def_id` scanning a square around `center`; (-1, -1) when there is none.
func _spot_near(def_id: String, center: Vector2i, radius: int) -> Vector2i:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var o := Vector2i(x, y)
			if s.can_place(def_id, o, true)["ok"]:
				return o
	return Vector2i(-1, -1)


## First placeable origin in the owned start region whose footprint does NOT cover `home`.
func _spot_out_of_coverage(def_id: String, home: Building) -> Vector2i:
	var def := reg.get_building(def_id)
	var rect := MapState.region_rect(s.map.start_region)
	for y in range(rect.position.y, rect.end.y - def.size.y + 1):
		for x in range(rect.position.x, rect.end.x - def.size.x + 1):
			var o := Vector2i(x, y)
			if not s.can_place(def_id, o, true)["ok"]:
				continue
			var probe := Building.new()
			probe.def = def
			probe.origin = o
			if not CoverageSystem.building_covers(probe, home):
				return o
	return Vector2i(-1, -1)


## A finished building inserted straight into the layout (homes and sources for the coverage query). Bumps
## structure_version so the coverage cache rebuilds.
func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	s.buildings[b.id] = b
	s.structure_version += 1
	return b


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


# AC1 data: the Shrine row matches the Village table and the radius is in data.
func test_shrine_data_matches_the_village_row() -> void:
	var d := reg.get_building("shrine")
	assert_not_null(d)
	assert_eq([d.era, d.size, d.cost, d.worker_slots], ["village", Vector2i(1, 1), {"materials": 30, "lumen": 5}, 0])
	assert_eq(d.coverage_radius, 6, "design section 16: Spirit coverage r6")
	assert_eq(d.category, "civic", "the build bar's civic category holds the Shrine")
	assert_true(d.blocked_by_blight, "design section 12: blighted ground cannot hold a Shrine")
	assert_null(d.recipe, "no workers, it makes nothing")


func test_shrine_is_locked_in_camp_and_unlocked_in_village() -> void:
	_strip()
	var o := _spot_near("shrine", h, 6)
	assert_ne(o, Vector2i(-1, -1), "a free spot near the Hearth")
	s.era_override = ""
	assert_eq(s.can_place("shrine", o), {"ok": false, "reason": "era_locked"})
	s.era_override = "village"
	assert_true(s.can_place("shrine", o)["ok"])
	assert_true(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "shrine"))


func test_a_blighted_tile_cannot_hold_a_shrine() -> void:
	_strip()
	var o := _spot_near("shrine", h, 6)
	assert_ne(o, Vector2i(-1, -1), "a free spot near the Hearth")
	s.set_blighted(o, true)
	assert_eq(s.can_place("shrine", o), {"ok": false, "reason": "blighted"})
	assert_eq(s.place_building_instant("shrine", o), -1, "a Shrine site is refused too")
	assert_eq(s.place_building("shrine", o), -1)
	s.set_blighted(o, false)
	assert_true(s.can_place("shrine", o)["ok"], "clean ground again")
	assert_true(s.can_place("cottage", o)["ok"], "only blight-blocked buildings are refused")


# AC2: coverage is Chebyshev between footprints, exactly like Market reach.
func test_building_covers_is_chebyshev_from_the_footprint() -> void:
	var shrine := Building.new()
	shrine.def = reg.get_building("shrine")
	shrine.origin = Vector2i(10, 10)
	var home := Building.new()
	home.def = reg.get_building("cottage")
	home.origin = Vector2i(16, 10)  # 6 tiles east of the Shrine's tile
	assert_true(CoverageSystem.building_covers(shrine, home), "r6 covers 6 tiles")
	home.origin = Vector2i(17, 10)
	assert_false(CoverageSystem.building_covers(shrine, home), "7 tiles is out")
	home.origin = Vector2i(16, 16)  # 6 east, 6 south: still Chebyshev 6
	assert_true(CoverageSystem.building_covers(shrine, home))
	home.origin = Vector2i(17, 17)
	assert_false(CoverageSystem.building_covers(shrine, home))
	var market := Building.new()
	market.def = reg.get_building("market")
	market.origin = Vector2i(10, 10)
	assert_false(CoverageSystem.building_covers(market, home), "a building with no coverage radius covers nothing")


# AC2: covered_homes lists home building ids by radius and home_covered agrees with it.
func test_coverage_query_lists_covered_homes() -> void:
	var shrine := _fake("shrine", Vector2i(200, 200))  # far from the Hearth, so only the probes are in play
	var near := _fake("cottage", Vector2i(206, 200))
	var far := _fake("cottage", Vector2i(207, 200))
	var out := cov.covered_homes(s)
	assert_true(out.has(near.id), "the cottage inside r6 is reported")
	assert_false(out.has(far.id), "the cottage outside r6 is not")
	assert_false(out.has(s.hearth.id), "the Hearth is far outside this Shrine's radius")
	assert_true(cov.home_covered(s, near.id))
	assert_false(cov.home_covered(s, far.id))
	assert_eq(out, cov.covered_homes(s), "the cache is stable while the layout is")


func test_a_shrine_site_covers_nothing() -> void:
	_strip()
	var o := _spot_near("shrine", h, 6)
	assert_ne(o, Vector2i(-1, -1), "a free spot near the Hearth")
	var id := s.place_building("shrine", o)
	assert_true(id >= 0, "a construction site")
	assert_false(cov.home_covered(s, s.hearth.id), "a site has no coverage")
	assert_eq(_factor("coverage"), 0.0)


# AC1: with a finished Shrine near the Hearth, most housed citizens are covered and the Spirit factor pays +10.
func test_shrine_near_homes_applies_the_coverage_factor() -> void:
	_strip()
	var o := _spot_near("shrine", h, 6)
	assert_ne(o, Vector2i(-1, -1), "a free spot near the Hearth")
	assert_true(s.place_building_instant("shrine", o) >= 0)
	assert_eq(s.homeless_count(), 0, "the starting citizens live in the Hearth")
	assert_true(cov.home_covered(s, s.hearth.id), "the Shrine covers the Hearth")
	assert_eq(_factor("coverage"), 10.0, "SpiritDef.coverage_bonus")
	# Data drives the bonus.
	var bonus := reg.spirit.coverage_bonus
	assert_eq(bonus, 10.0)


func test_shrine_out_of_reach_gives_no_coverage_factor() -> void:
	_strip()
	var o := _spot_out_of_coverage("shrine", s.hearth)
	assert_ne(o, Vector2i(-1, -1), "a Shrine spot beyond the Hearth's radius")
	assert_true(s.place_building_instant("shrine", o) >= 0)
	assert_false(cov.home_covered(s, s.hearth.id), "Shrine %s vs Hearth %s is out of reach" % [o, h])
	assert_eq(_factor("coverage"), 0.0, "few homes covered, no bonus")


# AC1 boundary: "most" is more than half of the housed citizens; exactly half is not enough.
func test_coverage_factor_needs_more_than_half_housed() -> void:
	_fake("shrine", Vector2i(200, 200))
	var near := _fake("cottage", Vector2i(206, 200))
	var far := _fake("cottage", Vector2i(207, 200))
	var ids := s.citizens.keys()
	ids.sort()
	assert_eq(ids.size(), Settlement.START_CITIZENS)
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.home_id = near.id if i < 4 else far.id
	assert_eq(_factor("coverage"), 0.0, "4 of 8 is half, not most")
	(s.citizens[ids[4]] as Citizen).home_id = near.id
	assert_eq(_factor("coverage"), 10.0, "5 of 8 is most")


func test_homeless_citizens_do_not_count_toward_most() -> void:
	_fake("shrine", Vector2i(200, 200))
	var near := _fake("cottage", Vector2i(206, 200))
	var far := _fake("cottage", Vector2i(207, 200))
	var ids := s.citizens.keys()
	ids.sort()
	for i in ids.size():
		var c: Citizen = s.citizens[ids[i]]
		c.home_id = near.id if i < 4 else far.id
	assert_eq(_factor("coverage"), 0.0)
	for i in range(4, ids.size()):
		(s.citizens[ids[i]] as Citizen).home_id = -1  # homeless: they neither help nor hurt the share
	assert_eq(_factor("coverage"), 10.0, "all the housed citizens are covered")
