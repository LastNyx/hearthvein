extends GutTest
## Ticket 41c: Aether Collector (design.md sections 13 and 17 Skyborne). Settlement API plus step_hours.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var isl: Island
var lift: Building


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "skyborne"
	s.planet_health_override = 100.0
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
	isl = (s.get_system(IslandSystem) as IslandSystem).island_of_anchor(aid)
	assert_not_null(isl)
	s.hearth.inventory.add("lumen", 400.0)
	s.step_seconds(0.01)
	while s.citizens.size() < 12:
		s.add_citizen()
	JobSystem.refresh(s)


func _collector() -> Building:
	for x in range(h.x + 2, h.x + 5):
		var t := Vector2i(x, h.y + 1)
		if isl.rect.has_point(t) and isl.rect.has_point(t + Vector2i(5, 4)) and s.can_place("sky_lift", t, true)["ok"]:
			lift = s.buildings[s.place_building_instant("sky_lift", t)]
			break
	assert_not_null(lift, "lift placed")
	s.place_road(lift.origin + Vector2i(1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	var id := s.place_building_instant("aether_collector", lift.origin + Vector2i(2, 0), Building.LAYER_SKY)
	assert_true(id >= 0, "collector placed")
	return s.buildings[id]


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("lumen", 50.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _blighted() -> int:
	return BlightSystem.count(s)


func test_data_row() -> void:
	var d := reg.get_building("aether_collector")
	assert_eq([d.era, d.size, d.layers, d.category], ["skyborne", Vector2i(2, 2), "island", "lumen"])
	assert_eq(d.cost, {"wood": 60, "stone": 90, "gold": 60, "cut_stone": 30, "tools": 20})
	assert_eq([d.worker_slots, d.upkeep_lumen], [3, 0.0])
	assert_eq(d.recipe.outputs, {"lumen": 6.0})
	assert_false(d.vein_extractor)
	assert_eq(d.placement_rule, "any")


# AC1: island-only.
func test_island_only() -> void:
	var g := Vector2i(h.x + 8, h.y + 3)
	assert_eq(s.can_place("aether_collector", g, true)["reason"], "wrong_layer")
	assert_eq(s.place_building_instant("aether_collector", g), -1)
	assert_true(s.can_place("aether_collector", isl.rect.position + Vector2i(1, 1), true, Building.LAYER_SKY)["ok"])


# AC2: no blight, no planet drain while it works.
func test_no_blight_no_planet_drain() -> void:
	var b := _collector()
	var blight0 := _blighted()
	s.step_days(1)
	var staffed := 0
	for c: Citizen in s.citizens.values():
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			staffed += 1
	assert_eq(staffed, 3, "staffed")
	var ph := s.get_system(PlanetHealthSystem) as PlanetHealthSystem
	s.planet_health_override = -1.0
	var before := s.planet_health()
	assert_eq(ph.daily_breakdown(s)["buildings"] as float, 0.0, "no planet drain")
	s.step_days(6)
	assert_eq(_blighted(), blight0, "no blight tiles appear")
	assert_almost_eq(s.planet_health(), before, 0.00001, "planet health unchanged by it")


# AC2: Dimming x0.5 through the general dimming_factor field (not a vein extractor).
func test_dimming_halves_output() -> void:
	var b := _collector()
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	_to_day(WINTER - 1)
	var normal := prod.multiplier(s, b)
	assert_eq(DimmingSystem.output_modifier(s, b), 1.0)
	_to_day(WINTER)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, b), 0.5)
	assert_almost_eq(prod.multiplier(s, b), normal * 0.5, 0.0001, "x0.5 of normal")


# Ticket 186: the gloom is a ground state; an island building above it keeps working (sky Lumen sits above the dark).
func test_gloom_below_does_not_stop_an_island_building() -> void:
	var b := _collector()
	var g := s.get_system(GloomSystem) as GloomSystem
	g.tiles[b.origin] = 0
	g.tiles[s.hearth.origin] = 0
	assert_false(GloomSystem.building_in_gloom(s, b), "the collector over a gloom tile is not stopped")
	assert_true(GloomSystem.building_in_gloom(s, s.hearth), "a ground building on a gloom tile still is")
