extends GutTest
## Ticket 44: Lumen Arcology and Heartroot Tap (design.md sections 10, 11, 13 and 17 Ascendant).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "ascendant"
	s.systems.erase(s.get_system(JobSystem))
	s.systems.erase(s.get_system(GrowthSystem))
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	h = s.map.hearth_spot


func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	b.input_buffer = Inventory.new("per_good", 1000.0)
	b.input_buffer.add("lumen", 1000.0)
	if b.def.recipe != null:
		b.door_buffer = Inventory.new("total", reg.logistics.door_buffer_cap)
	s.buildings[b.id] = b
	for t in b.tiles():
		s.occupancy[MapState.idx(t.x, t.y)] = b.id
	s.structure_version += 1
	return b


func _spot(w: int, ht: int) -> Vector2i:
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var o := Vector2i(h.x + dx, h.y + dy)
			if absi(dx) < 4 and absi(dy) < 4:
				continue
			if s.can_place("lumen_arcology", o, true)["ok"] and w <= 3 and ht <= 3:
				return o
	fail_test("no spot")
	return Vector2i.ZERO


func _cov() -> CoverageSystem:
	return s.get_system(CoverageSystem) as CoverageSystem


func test_data_rows() -> void:
	var a := reg.get_building("lumen_arcology")
	assert_eq([a.era, a.size, a.category, a.layers], ["ascendant", Vector2i(3, 3), "housing", "either"])
	assert_eq(a.cost, {"wood": 210, "stone": 90, "gold": 120, "cut_stone": 60, "tools": 40, "lumen_cells": 20})
	assert_eq([a.housing_beds, a.upkeep_lumen, a.needs_water, a.upgradable], [60, 4.0, true, true])
	var t := reg.get_building("heartroot_tap")
	assert_eq([t.era, t.size, t.worker_slots, t.upkeep_lumen, t.layers], ["ascendant", Vector2i(2, 2), 3, 0.0, "ground"])
	assert_eq(t.cost, {"wood": 80, "stone": 120, "gold": 100, "cut_stone": 40, "tools": 30})
	assert_eq(t.recipe.outputs, {"lumen": 12.0})
	assert_eq([t.placement_rule, t.blight_radius, t.health_per_day, t.vein_extractor, t.upgradable, t.min_planet_health],
			["on_vein", 0, 0.0, false, false, 50.0])
	var ids: Array = s.unlocked_buildings().map(func(d: BuildingDef) -> String: return d.id)
	assert_true(ids.has("lumen_arcology") and ids.has("heartroot_tap"))


func test_arcology_beds_and_tiers() -> void:
	var b := _fake("lumen_arcology", _spot(3, 3))
	assert_eq(b.effective_beds(reg), 60)
	b.tier = 2
	assert_eq(b.effective_beds(reg), 90)
	b.tier = 3
	assert_eq(b.effective_beds(reg), 120)
	b.tier = 1
	assert_true(s.can_upgrade(b.id)["ok"], "upgradable in Ascendant")


func test_arcology_without_water_costs_spirit_and_a_tower_fixes_it() -> void:
	var id := s.place_building_instant("lumen_arcology", _spot(3, 3))
	assert_true(id >= 0)
	var home: Building = s.buildings[id]
	var cz: Citizen = s.citizens[s.citizens.keys()[0]]
	cz.home_id = id
	assert_false(_cov().home_has_water(s, id), "no water source")
	assert_lt(CoverageSystem.water_factor(s), 0.0, "Spirit water penalty")
	_fake("water_tower", home.origin + Vector2i(5, 0))
	assert_true(_cov().home_has_water(s, id), "a Water Tower serves it")
	assert_eq(CoverageSystem.water_factor(s), 0.0)


func _produce(b: Building) -> float:
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var before := b.door_buffer.amount_of("lumen")
	prod._produce(s, b, 1, 1.0)
	return b.door_buffer.amount_of("lumen") - before


func test_heartroot_makes_12_at_health_50_halts_below_and_resumes() -> void:
	var b := _fake("heartroot_tap", _spot(2, 2))
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var mult := prod.multiplier(s, b)
	s.planet_health_override = 50.0
	assert_almost_eq(_produce(b), 12.0 * mult, 0.0001, "12 per worker-day at health 50")
	assert_eq(b.halt, "")
	b.door_buffer.remove("lumen", 100.0)
	s.planet_health_override = 49.9
	assert_eq(_produce(b), 0.0, "halted below 50")
	assert_eq(b.halt, "planet_too_sick")
	var m := HudModel.new(s)
	m.select(b.id)
	assert_eq(m.selection()["halt"], "Halted: planet health below 50%")
	s.planet_health_override = 60.0
	assert_almost_eq(_produce(b), 12.0 * mult, 0.0001, "resumes")
	assert_eq(b.halt, "")


func test_heartroot_no_blight_no_drain_no_vein_factor() -> void:
	var b := _fake("heartroot_tap", _spot(2, 2))
	var staffed := s.citizens[s.citizens.keys()[0]] as Citizen
	staffed.job_id = b.id
	staffed.job_kind = Citizen.JOB_WORK
	var ph := s.get_system(PlanetHealthSystem) as PlanetHealthSystem
	assert_eq(ph.daily_breakdown(s)["buildings"] as float, 0.0, "no planet drain")
	var before := BlightSystem.count(s)
	s.planet_health_override = 80.0
	s.step_days(8)
	assert_eq(BlightSystem.count(s), before, "no blight tiles")
	assert_eq(DimmingSystem.output_modifier(s, b), 1.0, "not a vein extractor: planet default (no Dimming)")
