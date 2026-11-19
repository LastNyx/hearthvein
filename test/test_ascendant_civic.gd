extends GutTest
## Ticket 44b: Bloom Orchard and Hall of Seasons (design.md sections 11, 14 and 17 Ascendant).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var _next_fake: int = 9000
var _staff_n: int = 0


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
	_staff_n = 0
	while s.citizens.size() < 6:
		s.add_citizen()


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


func _staff(b: Building) -> void:
	var ids: Array = s.citizens.keys()
	ids.sort()
	var cz: Citizen = s.citizens[ids[_staff_n]]
	_staff_n += 1
	cz.job_id = b.id
	cz.job_kind = Citizen.JOB_WORK


func _citizens() -> Array[Citizen]:
	var ids: Array = s.citizens.keys()
	ids.sort()
	var out: Array[Citizen] = []
	for id in ids:
		out.append(s.citizens[id])
	return out


## A 3x3 spot of buildable ground away from the Hearth, with its fertility set by the caller afterwards.
func _orchard_spot() -> Vector2i:
	for r in range(5, 30):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				var o := Vector2i(x, y)
				var ok := true
				for t in [o, o + Vector2i(2, 2)]:
					if not MapState.in_bounds(t.x, t.y):
						ok = false
				if not ok:
					continue
				_set_fertility(o, 100)
				if s.can_place("bloom_orchard", o)["ok"]:
					return o
	fail_test("no orchard spot")
	return Vector2i.ZERO


func _set_fertility(o: Vector2i, v: int) -> void:
	for y in 3:
		for x in 3:
			s.map.set_fertility(o.x + x, o.y + y, v)


func test_data_rows() -> void:
	var o := reg.get_building("bloom_orchard")
	assert_eq([o.era, o.size, o.worker_slots, o.upkeep_lumen, o.layers, o.upgradable],
			["ascendant", Vector2i(3, 3), 4, 0.0, "ground", false])
	assert_eq(o.cost, {"wood": 84, "stone": 36, "gold": 40, "planks": 30})
	assert_eq(o.recipe.outputs, {"fruit": 3.0})
	assert_eq([o.min_fertility, o.dimming_factor, o.fertility_output], [60.0, 0.75, false])
	var hl := reg.get_building("hall_of_seasons")
	assert_eq([hl.era, hl.size, hl.worker_slots, hl.upkeep_lumen, hl.layers], ["ascendant", Vector2i(3, 2), 2, 2.0, "either"])
	assert_eq(hl.cost, {"wood": 80, "stone": 120, "gold": 150, "cut_stone": 60})
	assert_eq([hl.coverage_radius, hl.darkness_factor], [12, 0.5])
	var ids: Array = s.unlocked_buildings().map(func(d: BuildingDef) -> String: return d.id)
	assert_true(ids.has("bloom_orchard") and ids.has("hall_of_seasons"))


# ------------------------------------------------------------------ Bloom Orchard

func test_placement_needs_average_fertility_60() -> void:
	var o := _orchard_spot()
	_set_fertility(o, 59)
	assert_eq(s.can_place("bloom_orchard", o)["reason"], "low_fertility")
	_set_fertility(o, 60)
	assert_true(s.can_place("bloom_orchard", o)["ok"], "60 exactly is allowed")
	# It is the average: five rich tiles and four poor ones make exactly 60.
	_set_fertility(o, 10)
	for i in 5:
		s.map.set_fertility(o.x + i % 3, o.y + i / 3, 100)
	assert_true(s.can_place("bloom_orchard", o)["ok"], "mean 60.0")
	s.map.set_fertility(o.x, o.y, 99)
	assert_eq(s.can_place("bloom_orchard", o)["reason"], "low_fertility", "mean just under 60")


func test_output_is_3_of_its_own_food_type_and_ignores_fertility() -> void:
	var o := _orchard_spot()
	_set_fertility(o, 60)
	var b := _fake("bloom_orchard", o)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var mult := prod.multiplier(s, b)
	prod._produce(s, b, 1, 1.0)
	assert_almost_eq(b.door_buffer.amount_of("fruit"), 3.0 * mult, 0.0001)
	_set_fertility(o, 100)
	b.door_buffer.remove("fruit", 100.0)
	prod._produce(s, b, 1, 1.0)
	assert_almost_eq(b.door_buffer.amount_of("fruit"), 3.0 * mult, 0.0001, "fertility does not scale it")
	assert_eq(GrowthSystem.food_type_of(reg, "fruit"), "fruit")
	assert_true(GrowthSystem.food_goods(reg).has("fruit"), "citizens can eat it")


func test_fruit_adds_one_to_food_variety() -> void:
	var market := _fake("market", h + Vector2i(6, 0))
	_staff(market)
	var ms := s.get_system(MarketSystem) as MarketSystem
	for c in _citizens():
		c.home_id = s.hearth.id
	var before := ms.available_food_types(s)
	assert_eq(before, 1, "start food only")
	s.hearth.inventory.add("fruit", 10.0)
	assert_eq(ms.available_food_types(s), before + 1, "fruit is one more type")
	assert_eq(SpiritSystem.food_type_factor(reg.spirit, before + 1) - SpiritSystem.food_type_factor(reg.spirit, before),
			reg.spirit.food_type_bonus)


func test_dimming_makes_x075() -> void:
	var b := _fake("bloom_orchard", _orchard_spot())
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var normal := prod.multiplier(s, b)
	assert_eq(DimmingSystem.output_modifier(s, b), 1.0)
	(s.get_system(DimmingSystem) as DimmingSystem)._active = true
	assert_eq(DimmingSystem.output_modifier(s, b), 0.75)
	assert_almost_eq(prod.multiplier(s, b), normal * 0.75, 0.0001)


# ------------------------------------------------------------------ Hall of Seasons

func _hall(dx: int, staffed: bool = true) -> Building:
	var hall := _fake("hall_of_seasons", Vector2i(h.x + dx, h.y))
	if staffed:
		_staff(hall)
	return hall


## A far home (rowhouse) well outside any Hall near the Hearth.
func _far_home() -> Building:
	var x := h.x + 40 if h.x + 40 < MapState.WIDTH - 3 else h.x - 40
	return _fake("rowhouse", Vector2i(x, h.y))


func _dark(on: bool = true) -> void:
	(s.get_system(DimmingSystem) as DimmingSystem)._dark = on


func test_hall_covers_r12_and_gives_the_covered_home_bonus() -> void:
	var hall := _hall(6)
	var cov := s.get_system(CoverageSystem) as CoverageSystem
	for c in _citizens():
		c.home_id = s.hearth.id
	assert_true(cov.home_covered(s, s.hearth.id))
	assert_eq(Building.footprint_gap(hall, s.hearth) <= 12, true)
	assert_eq(CoverageSystem.spirit_factor(s), reg.spirit.coverage_bonus, "most homes covered")
	hall.origin = Vector2i(h.x + 6 + 40, h.y)  # moved far away
	s.structure_version += 1
	var far_gap := Building.footprint_gap(hall, s.hearth)
	assert_gt(far_gap, 12)
	assert_eq(CoverageSystem.spirit_factor(s), 0.0)
	# The edge itself: a gap of exactly 12 covers, 13 does not.
	hall.origin = Vector2i(s.hearth.origin.x + s.hearth.def.size.x + 11, h.y)
	s.structure_version += 1
	assert_eq(Building.footprint_gap(hall, s.hearth), 12)
	assert_true(cov.home_covered(s, s.hearth.id))
	hall.origin.x += 1
	s.structure_version += 1
	assert_false(cov.home_covered(s, s.hearth.id))


func test_darkness_penalty_halved_for_covered_homes_full_for_others() -> void:
	_hall(6)
	var far := _far_home()
	var cs := _citizens()
	for c in cs:
		c.home_id = s.hearth.id
	_dark()
	assert_eq(DimmingSystem.darkness_factor(s), -10.0, "all covered: -10 instead of -20")
	for c in cs:
		c.home_id = far.id
	assert_eq(DimmingSystem.darkness_factor(s), -20.0, "all uncovered: full")
	for i in cs.size():
		cs[i].home_id = s.hearth.id if i < cs.size() / 2 else far.id
	assert_almost_eq(DimmingSystem.darkness_factor(s), -15.0, 0.0001, "half and half")
	assert_eq((s.get_system(SpiritSystem) as SpiritSystem).factor_value(s, "darkness"), DimmingSystem.darkness_factor(s))
	_dark(false)
	assert_eq(DimmingSystem.darkness_factor(s), 0.0, "no darkness, no penalty")


func test_a_hall_that_is_not_working_does_not_halve() -> void:
	var hall := _hall(6, false)
	for c in _citizens():
		c.home_id = s.hearth.id
	_dark()
	assert_eq(DimmingSystem.darkness_factor(s), -20.0, "no worker")
	_staff(hall)
	assert_eq(DimmingSystem.darkness_factor(s), -10.0, "staffed")
	hall.paused = true
	assert_eq(DimmingSystem.darkness_factor(s), -20.0, "paused")
	hall.paused = false
	hall.site = true
	assert_eq(DimmingSystem.darkness_factor(s), -20.0, "still a site")
