extends GutTest
## Ticket 34c: special tier III rules (design.md sections 9 and 10). Farm III is the Terraced Farm, which loses no
## fertility; Greenhouse III ignores blight, where a Greenhouse of tier I or II stops ("blight" halt) when its tiles
## or the ring around them are blighted.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "city"
	s.planet_health_override = 100.0
	h = s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


func _place(id: String, dx: int, side: int) -> Building:
	var def := reg.get_building(id)
	var o := Vector2i(h.x + dx, h.y - def.size.y if side < 0 else h.y + 1)
	var bid := s.place_building_instant(id, o)
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings[bid]


func _run_days(n: int) -> void:
	for i in n:
		s.hearth.inventory.add("food", 30.0)
		s.step_hours(GameClock.HOURS_PER_DAY)


# AC1: the Terraced Farm keeps fertility over a year where a plain farm wears it.
func test_terraced_farm_keeps_fertility() -> void:
	var fs := s.get_system(FertilitySystem) as FertilitySystem
	var plain := _place("farm", 4, -1)
	var terraced := _place("farm", 8, -1)
	for b in [plain, terraced]:
		for t in b.tiles():
			s.set_terrain(t, "grass")
			s.map.set_fertility(t.x, t.y, 60)
	terraced.tier = 3
	s.refresh_population()
	assert_eq(terraced.display_name(reg), "Terraced Farm")
	for i in 4:
		fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, terraced.origin), 60.0, 0.001, "Terraced Farm: no loss in a year")
	assert_almost_eq(fs.fertility_at(s, plain.origin), 56.0, 0.001, "a plain farm loses 4 a year")


# AC2: a Greenhouse of tier I and II stops beside blight; Greenhouse III keeps working.
func test_greenhouse_three_keeps_working_on_blight() -> void:
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	var g := _place("greenhouse", 4, -1)
	s.refresh_population()
	_run_days(1)
	assert_eq(g.halt, "", "clean ground: it works")
	var before := ps.produced_total
	_run_days(1)
	assert_gt(ps.produced_total, before, "it produces")
	# Blight on a footprint tile and on the ring beside it.
	s.set_blighted(g.origin, true)
	s.set_blighted(g.origin + Vector2i(-1, 0), true)
	for tier in [1, 2]:
		g.tier = tier
		s.refresh_population()
		_run_days(1)
		assert_eq(g.halt, "blight", "tier %d halts on blight" % tier)
		before = ps.produced_total
		_run_days(1)
		assert_almost_eq(ps.produced_total, before, 0.0001, "tier %d makes nothing under blight" % tier)
	g.tier = 3
	s.refresh_population()
	_run_days(1)
	assert_ne(g.halt, "blight", "tier III ignores blight")
	before = ps.produced_total
	_run_days(1)
	assert_gt(ps.produced_total, before, "Greenhouse III keeps producing on blighted tiles")


# Blight farther than the ring does not stop a tier I Greenhouse; other buildings are unaffected.
func test_blight_reach_is_one_tile() -> void:
	var g := _place("greenhouse", 4, -1)
	s.set_blighted(g.origin + Vector2i(-2, 0), true)
	assert_false(BlightSystem.halts_production(s, g), "two tiles away")
	s.set_blighted(g.origin + Vector2i(-1, 0), true)
	assert_true(BlightSystem.halts_production(s, g), "the ring")
	var farm := _place("farm", 8, -1)
	s.set_blighted(farm.origin, true)
	assert_false(BlightSystem.halts_production(s, farm), "farms only lose fertility")
