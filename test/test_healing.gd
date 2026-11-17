extends GutTest
## Ticket 43: Verdant Spring and Rewilding Grove (design.md sections 13 and 17 Ascendant).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var c: Vector2i  # centre of a flat grass square, 26 tiles wide, nothing built on it
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "ascendant"
	s.systems.erase(s.get_system(JobSystem))  # keep the hand-assigned crew
	s.hearth.inventory.add("food", 600.0)
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	c = _flat_centre(13)


## Finds a free area, then makes it all plain grass, so terrain never gets in the way.
func _flat_centre(radius: int) -> Vector2i:
	for y in range(radius + 1, MapState.HEIGHT - radius - 1):
		for x in range(radius + 1, MapState.WIDTH - radius - 1):
			var ok := true
			for dy in range(-radius, radius + 1, 3):
				for dx in range(-radius, radius + 1, 3):
					if s.building_at(Vector2i(x + dx, y + dy)) != null:
						ok = false
			if ok:
				for dy in range(-radius, radius + 1):
					for dx in range(-radius, radius + 1):
						s.map.set_terrain_id(x + dx, y + dy, "grass")
						s.map.set_blighted(x + dx, y + dy, false)
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	b.input_buffer = Inventory.new("per_good", 1000.0)
	s.buildings[b.id] = b
	for t in b.tiles():
		s.occupancy[MapState.idx(t.x, t.y)] = b.id
	s.structure_version += 1
	return b


func _staff(b: Building) -> void:
	for cid in s.citizens:
		var cz: Citizen = s.citizens[cid]
		cz.job_id = b.id
		cz.job_kind = Citizen.JOB_WORK
		return


func _power(b: Building) -> void:
	b.input_buffer.cap = 1000.0
	b.input_buffer.add("lumen", 1000.0)


func _working(def_id: String) -> Building:
	var b := _fake(def_id, c)
	_staff(b)
	_power(b)
	return b


func _forest_count() -> int:
	return s.map.terrain.count(s.map.terrain_index("forest"))


func test_data_rows() -> void:
	var v := reg.get_building("verdant_spring")
	var g := reg.get_building("rewilding_grove")
	assert_eq([v.era, v.size, v.worker_slots, v.upkeep_lumen], ["ascendant", Vector2i(2, 2), 2, 4.0])
	assert_eq(v.cost, {"materials": 250, "gold": 150, "cut_stone": 50, "lumen_cells": 30})
	assert_eq([v.heal_blight_radius, v.heal_blight_per_day], [10, 1])
	assert_almost_eq(v.health_per_day, 0.08, 0.0000001)
	assert_eq([g.era, g.size, g.worker_slots, g.upkeep_lumen], ["ascendant", Vector2i(2, 2), 2, 1.0])
	assert_eq(g.cost, {"materials": 100, "gold": 60, "planks": 20})
	assert_eq([g.rewild_radius, g.rewild_per_day], [8, 1])
	assert_almost_eq(g.health_per_day, 0.03, 0.0000001)
	var ids: Array = s.unlocked_buildings().map(func(d: BuildingDef) -> String: return d.id)
	assert_true(ids.has("verdant_spring") and ids.has("rewilding_grove"), "both reach the build bar")


# AC1: one blighted tile a day, nearest first (ties lower y then lower x), turned into fertility-100 soil.
func test_spring_heals_one_tile_a_day_nearest_first() -> void:
	var b := _working("verdant_spring")  # occupies c .. c+1
	var near := c + Vector2i(-2, 0)    # d2 4
	var far := c + Vector2i(1, 8)      # d2 49
	for t in [near, far]:
		s.map.set_fertility(t.x, t.y, 20)
		s.set_blighted(t, true)
	s.step_days(1)
	assert_false(s.map.is_blighted(near.x, near.y), "the nearest went first")
	assert_true(s.map.is_blighted(far.x, far.y), "only one a day")
	assert_eq(s.map.terrain_id_at(near.x, near.y), "fertile_soil")
	assert_eq(s.map.get_fertility(near.x, near.y), 100)
	s.step_days(1)
	assert_false(s.map.is_blighted(far.x, far.y))
	assert_eq(s.map.get_fertility(far.x, far.y), 100)
	assert_true(b.id > 0)


func test_spring_tie_goes_to_lower_y_then_lower_x() -> void:
	_working("verdant_spring")
	var up := c + Vector2i(0, -2)
	var left := c + Vector2i(-2, 0)
	var right := c + Vector2i(3, 0)  # same distance as left from the 2x2 footprint
	for t in [up, left, right]:
		s.set_blighted(t, true)
	var spring: Building = s.buildings[_next_fake]
	assert_eq(HealingSystem.next_blight_tile(s, spring), up, "lower y wins")
	s.set_blighted(up, false)
	assert_eq(HealingSystem.next_blight_tile(s, spring), left, "then lower x")


func test_spring_radius_10() -> void:
	var b := _working("verdant_spring")
	var in_r := c + Vector2i(0, 11)   # 10 below the footprint's bottom row (c.y+1)
	var out_r := c + Vector2i(0, 12)
	s.set_blighted(out_r, true)
	s.step_days(3)
	assert_true(s.map.is_blighted(out_r.x, out_r.y), "11 tiles away is out of reach")
	s.set_blighted(in_r, true)
	s.step_days(1)
	assert_false(s.map.is_blighted(in_r.x, in_r.y), "10 tiles away is in reach")
	assert_true(b.id > 0)


func test_spring_under_a_building_clears_blight_but_keeps_terrain() -> void:
	_working("verdant_spring")
	var other := _fake("cottage", c + Vector2i(4, 0))
	var t := other.origin
	s.set_blighted(t, true)
	s.map.set_fertility(t.x, t.y, 10)
	s.step_days(1)
	assert_false(s.map.is_blighted(t.x, t.y))
	assert_eq(s.map.terrain_id_at(t.x, t.y), "grass", "no terrain change under a building")
	assert_eq(s.map.get_fertility(t.x, t.y), 100)


# AC2: one grass or stump tile a day, nearest first, r8.
func test_grove_plants_one_tile_a_day_nearest_first_in_r8() -> void:
	_working("rewilding_grove")
	var before := _forest_count()
	s.map.set_terrain_id(c.x, c.y - 1, "stump")  # first of the distance-1 ties: lower y, then lower x
	s.step_days(1)
	assert_eq(_forest_count(), before + 1, "one tile a day")
	assert_eq(s.map.terrain_id_at(c.x, c.y - 1), "forest", "nearest first, ties lower y then lower x; a stump counts")
	s.step_days(7)
	assert_eq(_forest_count(), before + 8)
	for y in range(c.y - 12, c.y + 14):
		for x in range(c.x - 12, c.x + 14):
			if s.map.terrain_id_at(x, y) == "forest":
				var dx := maxi(maxi(c.x - x, x - (c.x + 1)), 0)
				var dy := maxi(maxi(c.y - y, y - (c.y + 1)), 0)
				assert_lte(dx * dx + dy * dy, 64, "forest only inside r8")


func test_grove_radius_8_and_skips_unplantable_tiles() -> void:
	var b := _working("rewilding_grove")
	# Make everything within r8 unplantable except one tile at exactly 8, and one blighted tile nearer.
	for y in range(c.y - 12, c.y + 14):
		for x in range(c.x - 12, c.x + 14):
			if s.map.terrain_id_at(x, y) == "grass":
				s.map.set_terrain_id(x, y, "rock")
	var edge := c + Vector2i(0, 9)  # 8 below the footprint's bottom row
	var past := c + Vector2i(0, 10)
	var blighted := c + Vector2i(-2, 0)
	for t in [edge, past, blighted]:
		s.map.set_terrain_id(t.x, t.y, "grass")
	s.set_blighted(blighted, true)
	var road_tile := c + Vector2i(3, 0)
	s.map.set_terrain_id(road_tile.x, road_tile.y, "grass")
	s.roads[MapState.idx(road_tile.x, road_tile.y)] = Settlement.ROAD_DIRT
	assert_eq(HealingSystem.next_rewild_tile(s, b), edge, "blighted, road and out-of-range tiles are skipped")
	s.step_days(1)
	assert_eq(s.map.terrain_id_at(edge.x, edge.y), "forest")
	assert_eq(s.map.terrain_id_at(past.x, past.y), "grass")
	assert_eq(s.map.terrain_id_at(blighted.x, blighted.y), "grass")
	assert_eq(HealingSystem.next_rewild_tile(s, b), Vector2i(-1, -1))


# AC (both): not working means no effect.
func test_not_working_does_nothing() -> void:
	var sp := _fake("verdant_spring", c)
	var gr := _fake("rewilding_grove", c + Vector2i(6, 0))
	var t := c + Vector2i(-2, 0)
	s.set_blighted(t, true)
	var before := _forest_count()
	s.step_days(2)
	assert_true(s.map.is_blighted(t.x, t.y), "unstaffed Spring does nothing")
	assert_eq(_forest_count(), before, "unstaffed Grove does nothing")
	_staff(sp)
	_power(sp)
	sp.paused = true
	s.step_days(1)
	assert_true(s.map.is_blighted(t.x, t.y), "paused Spring does nothing")
	sp.paused = false
	sp.input_buffer.remove("lumen", 9999.0)
	s.hearth.inventory.remove("lumen", 9999.0)
	s.step_days(1)
	assert_true(s.map.is_blighted(t.x, t.y), "unpowered Spring does nothing")
	_power(sp)
	s.step_days(1)
	assert_false(s.map.is_blighted(t.x, t.y), "staffed and powered it works")
	assert_true(gr.id > 0)


# AC3: the planet terms count only while working.
func test_planet_terms_count_only_while_working() -> void:
	var sp := _fake("verdant_spring", c)
	var gr := _fake("rewilding_grove", c + Vector2i(6, 0))
	var ph := s.get_system(PlanetHealthSystem) as PlanetHealthSystem
	assert_almost_eq(ph.daily_breakdown(s)["buildings"], 0.0, 0.000001, "idle: no term")
	_staff(sp)
	_power(sp)
	assert_almost_eq(ph.daily_breakdown(s)["buildings"], 0.08, 0.000001, "Spring +0.08")
	for cid in s.citizens:
		var cz: Citizen = s.citizens[cid]
		cz.job_id = gr.id
		cz.job_kind = Citizen.JOB_WORK
	_power(gr)
	assert_almost_eq(ph.daily_breakdown(s)["buildings"], 0.03, 0.000001, "Grove +0.03, Spring unstaffed")


func test_save_round_trip() -> void:
	_working("verdant_spring")
	s.set_blighted(c + Vector2i(-2, 0), true)
	s.step_days(1)
	var d := s.to_dict()
	var r := Settlement.from_dict(d, reg)
	assert_eq(r.map.terrain_id_at(c.x - 2, c.y), "fertile_soil")
	assert_false(r.map.is_blighted(c.x - 2, c.y))
	assert_not_null(r.get_system(HealingSystem))
