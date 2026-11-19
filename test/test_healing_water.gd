extends GutTest
## Ticket 43b: Vein Mender and Clearwater Works (design.md sections 9, 13 and 17 Ascendant).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var _next_fake: int = 9000
var _staff_n: int = 0
var _src := Vector2i(-1, -1)  # a river tile next to a land tile, with a downstream run of three
var _land := Vector2i(-1, -1)
var _path: Array[Vector2i] = []


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "ascendant"
	s.systems.erase(s.get_system(JobSystem))  # keep the hand-assigned crew
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	_staff_n = 0


func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	b.input_buffer = Inventory.new("per_good", 1000.0)
	b.input_buffer.add("lumen", 1000.0)  # upkeep stays paid across day changes
	s.buildings[b.id] = b
	for t in b.tiles():
		s.occupancy[MapState.idx(t.x, t.y)] = b.id
	s.structure_version += 1
	return b


## Gives the building its own citizen as a worker.
func _staff(b: Building) -> Citizen:
	var ids: Array = s.citizens.keys()
	ids.sort()
	var cz: Citizen = s.citizens[ids[_staff_n]]
	_staff_n += 1
	cz.job_id = b.id
	cz.job_kind = Citizen.JOB_WORK
	return cz


func _working(def_id: String, origin: Vector2i) -> Building:
	var b := _fake(def_id, origin)
	_staff(b)
	return b


func _buildings_term() -> float:
	return (s.get_system(PlanetHealthSystem) as PlanetHealthSystem).daily_breakdown(s)["buildings"]


const TAP := -0.005


func test_data_rows() -> void:
	var m := reg.get_building("vein_mender")
	var w := reg.get_building("clearwater_works")
	assert_eq([m.era, m.size, m.worker_slots, m.upkeep_lumen, m.layers], ["ascendant", Vector2i(1, 1), 2, 3.0, "ground"])
	assert_eq(m.cost, {"wood": 60, "stone": 90, "gold": 100, "lumen_cells": 40})
	assert_eq([m.drain_radius, m.drain_factor, m.placement_rule], [6, 0.5, "on_vein"])
	assert_almost_eq(m.health_per_day, 0.04, 0.0000001)
	assert_eq([w.era, w.size, w.worker_slots, w.upkeep_lumen, w.layers], ["ascendant", Vector2i(2, 1), 2, 2.0, "ground"])
	assert_eq(w.cost, {"wood": 64, "stone": 96, "gold": 80, "cut_stone": 40, "tools": 20})
	assert_true(w.stops_fouling)
	assert_eq(w.placement_rule, "on_river")
	assert_almost_eq(w.health_per_day, 0.03, 0.0000001)
	var ids: Array = s.unlocked_buildings().map(func(d: BuildingDef) -> String: return d.id)
	assert_true(ids.has("vein_mender") and ids.has("clearwater_works"), "both reach the build bar")


# ------------------------------------------------------------------ Vein Mender

func test_mender_halves_drain_within_r6_and_not_at_r7() -> void:
	_working("lumen_tap", Vector2i(10, 10))
	assert_almost_eq(_buildings_term(), TAP, 0.0000001, "full drain before a mender")
	var m := _working("vein_mender", Vector2i(16, 10))  # gap 6 from the tap
	assert_eq(Building.footprint_gap(m, s.buildings[_next_fake - 1]), 6)
	assert_almost_eq(_buildings_term(), TAP * 0.5 + 0.04, 0.0000001, "r6: half the drain, plus the mender's term")
	m.origin = Vector2i(17, 10)  # gap 7
	assert_almost_eq(_buildings_term(), TAP + 0.04, 0.0000001, "r7: full drain")


func test_menders_do_not_stack() -> void:
	_working("lumen_tap", Vector2i(10, 10))
	_working("vein_mender", Vector2i(12, 10))
	_working("vein_mender", Vector2i(10, 12))
	assert_almost_eq(_buildings_term(), TAP * 0.5 + 0.08, 0.0000001, "still x0.5, two planet terms")


func test_a_mender_that_is_not_working_gives_full_drain() -> void:
	_working("lumen_tap", Vector2i(10, 10))
	var unstaffed := _fake("vein_mender", Vector2i(12, 10))
	assert_almost_eq(_buildings_term(), TAP, 0.0000001, "no worker: no halving, no planet term")
	var cz := _staff(unstaffed)
	assert_almost_eq(_buildings_term(), TAP * 0.5 + 0.04, 0.0000001)
	unstaffed.paused = true
	assert_almost_eq(_buildings_term(), TAP, 0.0000001, "paused")
	unstaffed.paused = false
	cz.job_kind = Citizen.JOB_NONE
	assert_almost_eq(_buildings_term(), TAP, 0.0000001, "worker gone")


func test_mender_only_touches_vein_extractors() -> void:
	var farm := _working("farm", Vector2i(10, 10))
	farm.def = farm.def.duplicate()
	farm.def.health_per_day = -0.01  # a negative term on a non-extractor stays as it is
	_working("vein_mender", Vector2i(12, 10))
	assert_almost_eq(_buildings_term(), -0.01 + 0.04, 0.0000001)


func test_mender_needs_a_vein_tile() -> void:
	var vein := Vector2i(-1, -1)
	var plain := Vector2i(-1, -1)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var id := s.map.terrain_id_at(x, y)
			if vein.x < 0 and id == "lumen_vein" and s.building_at(Vector2i(x, y)) == null:
				vein = Vector2i(x, y)
			if plain.x < 0 and id == "grass" and s.building_at(Vector2i(x, y)) == null:
				plain = Vector2i(x, y)
	assert_ne(vein, Vector2i(-1, -1))
	assert_true(s.can_place("vein_mender", vein)["ok"])
	assert_eq(s.can_place("vein_mender", plain)["reason"], "needs_vein")


# ------------------------------------------------------------------ Clearwater Works

func _chain(t: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [t]
	while out.size() < n:
		var d := s.map.downstream(out[-1].x, out[-1].y)
		if not MapState.in_bounds(d.x, d.y) or not s.map.is_river(d.x, d.y):
			break
		out.append(d)
	return out


## A river tile beside a land tile, with two more river tiles downstream that the land tile does not touch.
func _find_source() -> void:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if not s.map.is_river(x, y):
				continue
			var chain := _chain(t, 3)
			if chain.size() < 3:
				continue
			for d in Placement.DIRS:
				var l := t + d
				if not MapState.in_bounds(l.x, l.y) or s.map.terrain_id_at(l.x, l.y) == "water":
					continue
				var clear := true
				for i in range(1, chain.size()):
					if absi(chain[i].x - l.x) + absi(chain[i].y - l.y) == 1:
						clear = false
				if clear:
					_src = t
					_land = l
					_path = chain
					return
	fail_test("no river source found")


func _works_at(t: Vector2i) -> Building:
	return _fake("clearwater_works", t)


func test_clearwater_blocks_downstream_fouling_but_not_upstream() -> void:
	_find_source()
	var w := _works_at(_path[1])
	_staff(w)
	s.set_blighted(_land, true)
	s.step_hours(6)
	assert_true(s.map.is_fouled(_src.x, _src.y), "upstream of the Works still fouls")
	assert_true(s.map.is_fouled(_path[1].x, _path[1].y), "the Works' own tile may be fouled")
	assert_false(s.map.is_fouled(_path[2].x, _path[2].y), "nothing past the Works")
	assert_true(w.id > 0)


func test_without_a_works_the_front_passes() -> void:
	_find_source()
	s.set_blighted(_land, true)
	s.step_hours(6)
	assert_true(s.map.is_fouled(_path[2].x, _path[2].y), "control: it does spread when nothing stops it")


func test_works_stops_blocking_when_unstaffed_and_already_fouled_tiles_clear() -> void:
	_find_source()
	var w := _works_at(_path[1])
	var cz := _staff(w)
	s.set_blighted(_land, true)
	s.step_hours(4)
	assert_false(s.map.is_fouled(_path[2].x, _path[2].y))
	cz.job_kind = Citizen.JOB_NONE
	s.step_hours(4)
	assert_true(s.map.is_fouled(_path[2].x, _path[2].y), "unstaffed: fouling spreads again")
	# Staff it again: the tiles past it lose their feed and clear two days later.
	cz.job_id = w.id
	cz.job_kind = Citizen.JOB_WORK
	var hours := reg.water.foul_clear_hours
	s.step_hours(hours - 2)
	assert_true(s.map.is_fouled(_path[2].x, _path[2].y), "still counting down")
	s.step_hours(4)
	assert_false(s.map.is_fouled(_path[2].x, _path[2].y), "cleared on the normal rule")
	assert_true(s.map.is_fouled(_path[1].x, _path[1].y), "the Works' tile stays fed by the source")


func test_demolished_works_stops_blocking() -> void:
	_find_source()
	var w := _works_at(_path[1])
	_staff(w)
	s.set_blighted(_land, true)
	s.step_hours(3)
	assert_false(s.map.is_fouled(_path[2].x, _path[2].y))
	assert_true(s.demolish(w.id))
	s.step_hours(3)
	assert_true(s.map.is_fouled(_path[2].x, _path[2].y))


func test_works_placement_needs_a_river_tile() -> void:
	_find_source()
	assert_true(s.can_place("clearwater_works", _path[1])["ok"], "on the river")
	var far := Vector2i(-1, -1)
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 3):
			if far.x >= 0:
				break
			if s.map.terrain_id_at(x, y) == "grass" and s.map.terrain_id_at(x + 1, y) == "grass" \
					and not s.map.is_river(x, y) and not s.map.is_river(x + 1, y):
				far = Vector2i(x, y)
	assert_eq(s.can_place("clearwater_works", far)["reason"], "needs_river")
	assert_eq(s.can_place("well", _path[1])["reason"], "water", "other buildings still cannot stand in the river")


func test_works_planet_term_only_while_working() -> void:
	_find_source()
	var w := _works_at(_path[1])
	assert_almost_eq(_buildings_term(), 0.0, 0.0000001, "no worker")
	var cz := _staff(w)
	assert_almost_eq(_buildings_term(), 0.03, 0.0000001)
	cz.job_kind = Citizen.JOB_NONE
	assert_almost_eq(_buildings_term(), 0.0, 0.0000001)

