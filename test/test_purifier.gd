extends GutTest
## Ticket 33c: Purifier Tower (design.md sections 12, 13 and 16 City). It clears one blighted tile a day in r8,
## shields r4 from new blight and adds its +0.03/day planet health term.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var cs: CleaningSystem
var bs: BlightSystem
var ph: PlanetHealthSystem
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "city"
	h = s.map.hearth_spot
	s.systems.erase(s.get_system(JobSystem))  # keep the hand-assigned crew: the hourly refresh would drop it
	s.hearth.inventory.add("food", 600.0)  # long tests must not starve the assigned worker out of the settlement
	cs = s.get_system(CleaningSystem) as CleaningSystem
	bs = s.get_system(BlightSystem) as BlightSystem
	ph = s.get_system(PlanetHealthSystem) as PlanetHealthSystem


## A placeable Purifier Tower spot near the Hearth.
func _spot() -> Vector2i:
	for r in range(2, 16):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place("purifier_tower", Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _placed() -> Building:
	var origin := _spot()
	assert_ne(origin, Vector2i(-1, -1), "a Purifier Tower fits near the Hearth")
	var id := s.place_building_instant("purifier_tower", origin)
	assert_true(id >= 0, "the Purifier Tower was placed")
	return s.buildings[id]


func _staff(b: Building, n: int = 1) -> void:
	var i := 0
	for cid in s.citizens:
		if i >= n:
			break
		var c: Citizen = s.citizens[cid]
		c.job_id = b.id
		c.job_kind = Citizen.JOB_WORK
		i += 1


func _unstaff(b: Building) -> void:
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id:
			c.job_id = -1
			c.job_kind = Citizen.JOB_NONE


## Enough Lumen in the input buffer for a long test: the real cap holds two days of upkeep.
func _power(b: Building) -> void:
	b.input_buffer.cap = 1000.0
	b.input_buffer.add("lumen", 1000.0)


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


## Squared distance from the tile to the closest footprint tile of `b` (the blight radius measure).
func _dist2(b: Building, t: Vector2i) -> int:
	var best := 1 << 30
	for ft in b.tiles():
		var d := (t.x - ft.x) * (t.x - ft.x) + (t.y - ft.y) * (t.y - ft.y)
		if d < best:
			best = d
	return best


func _forest_count() -> int:
	var fi := s.map.terrain_index("forest")
	return s.map.terrain.count(fi) if fi >= 0 else 0


# AC0: the data row is the City table's, with the cleaning and shielding numbers in data, not code.
func test_data_matches_the_city_row() -> void:
	var d := reg.get_building("purifier_tower")
	assert_not_null(d, "data/buildings/purifier_tower.tres exists")
	assert_eq([d.era, d.category, d.size], ["city", "civic", Vector2i(1, 1)])
	assert_eq(d.cost, {"wood": 40, "stone": 60, "gold": 40, "lumen": 20, "cut_stone": 20})
	assert_eq([d.worker_slots, d.upkeep_lumen], [2, 3.0])
	assert_eq([d.clean_radius, d.clean_interval_days], [8, 1], "section 12: 1 tile/day in r8")
	assert_eq(d.blight_block_radius, 4, "section 12: blocks new blight in r4")
	assert_almost_eq(d.health_per_day, 0.03, 0.0000001, "section 13: Purifier Tower +0.03/day")
	assert_null(d.recipe)
	s.era_override = "town"
	assert_false(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "purifier_tower"))


# AC1: one tile a day, nearest first, inside r8 only.
func test_purifier_clears_one_tile_a_day_in_r8() -> void:
	var b := _placed()
	_staff(b)
	_power(b)
	var near := b.origin + Vector2i(0, -2)  # squared distance 4
	var mid := b.origin + Vector2i(0, 3)    # 9
	var far := b.origin + Vector2i(7, 0)    # 49, inside r8
	var out := b.origin + Vector2i(9, 0)    # 81, outside r8
	assert_true(MapState.in_bounds(out.x, out.y), "the out-of-range tile is on the map")
	for t in [near, mid, far, out]:
		assert_true(s.set_blighted(t, true))
	assert_eq(BlightSystem.count(s), 4)
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 3, "one tile a day, not a whole radius at once")
	assert_false(s.map.is_blighted(near.x, near.y), "the nearest tile went first")
	s.step_days(1)
	assert_false(s.map.is_blighted(mid.x, mid.y))
	assert_true(s.map.is_blighted(far.x, far.y))
	s.step_days(1)
	assert_false(s.map.is_blighted(far.x, far.y), "r8 reaches 7 tiles out")
	assert_true(s.map.is_blighted(out.x, out.y), "r8 does not reach 9 tiles out")
	assert_eq(BlightSystem.count(s), 1)


# AC1b: the Cleanser's working rule: staffed and its Lumen upkeep paid.
func test_purifier_only_works_when_staffed_and_powered() -> void:
	var b := _placed()
	var t := b.origin + Vector2i(0, -2)
	assert_true(s.set_blighted(t, true))
	s.step_days(2)
	assert_true(s.map.is_blighted(t.x, t.y), "nobody is assigned: nothing is cleaned")
	_staff(b)
	s.hearth.inventory.remove("lumen", 9999.0)
	if b.input_buffer != null:
		b.input_buffer.remove("lumen", 9999.0)
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	us.on_day(s)
	assert_false(us.is_paid(b.id), "no Lumen anywhere")
	s.step_days(2)
	assert_true(s.map.is_blighted(t.x, t.y), "staffed but unpowered: nothing is cleaned")
	_power(b)
	s.step_days(1)
	assert_false(s.map.is_blighted(t.x, t.y), "staffed and powered: it cleans")


# AC2: new blight never lands within r4 of a working Purifier; the spread takes the next eligible tile instead.
func test_purifier_blocks_new_blight_within_r4() -> void:
	var c := _dry_center(5)
	assert_ne(c, Vector2i(-1, -1), "a dry open area on the map")
	var pump := _fake("lumen_pump", c)               # 1x1, blights r4/3d
	var pur := _fake("purifier_tower", c + Vector2i(2, 0))
	_staff(pur)
	# Every neighbour of the pump is inside the shield; the nearest eligible tile is two left and one up.
	var picked := bs.next_tile(s, pump)
	assert_eq(picked, c + Vector2i(-2, -1),
			"blocked tiles are skipped: the nearest eligible tile after them wins, deterministically")
	assert_gt(_dist2(pur, picked), 16, "the chosen tile is outside r4")
	# Keep spreading: nothing inside the shield is ever chosen, and it stops when only shielded tiles remain.
	var blighted := 0
	while true:
		var t := bs.next_tile(s, pump)
		if t.x < 0:
			break
		assert_gt(_dist2(pur, t), 16, "tile %s is inside the Purifier's r4" % t)
		assert_true(s.set_blighted(t, true))
		blighted += 1
		assert_lt(blighted, 200, "the spread must run out of eligible tiles")
	assert_gt(blighted, 0, "the shield leaves some room to spread")
	assert_true(s.map.is_blighted(c.x - 4, c.y), "a tile outside r4 was blighted")


func test_unstaffed_paused_or_unpaid_purifier_blocks_nothing() -> void:
	var c := _dry_center(5)
	assert_ne(c, Vector2i(-1, -1), "a dry open area on the map")
	var pump := _fake("lumen_pump", c)
	var pur := _fake("purifier_tower", c + Vector2i(2, 0))
	pur.input_buffer = Inventory.new("per_good", 10.0)  # its hauled Lumen upkeep
	var us := s.get_system(UpkeepSystem) as UpkeepSystem
	# Unstaffed.
	assert_true(_dist2(pur, bs.next_tile(s, pump)) <= 16, "an unstaffed Purifier shields nothing")
	# Staffed but unpaid.
	_staff(pur)
	us.on_day(s)
	assert_false(us.is_paid(pur.id), "no Lumen: upkeep unpaid")
	assert_true(_dist2(pur, bs.next_tile(s, pump)) <= 16, "an unpaid Purifier shields nothing")
	# Paused.
	pur.paused = true
	assert_true(_dist2(pur, bs.next_tile(s, pump)) <= 16, "a paused Purifier shields nothing")
	# Paid and unpaused: it shields again.
	pur.paused = false
	pur.input_buffer.add("lumen", 10.0)
	us.on_day(s)
	assert_true(us.is_paid(pur.id), "the upkeep is paid")
	assert_gt(_dist2(pur, bs.next_tile(s, pump)), 16, "working again: it shields")


# AC3: the Purifier adds its planet health term while it works.
func test_purifier_adds_its_planet_health_term() -> void:
	var b := _placed()
	_staff(b)
	_power(b)
	assert_true(PlanetHealthSystem.is_working(s, b))
	assert_almost_eq(float(ph.daily_breakdown(s)["buildings"]), 0.03, 0.0000001,
			"section 13: Purifier Tower +0.03/day")
	ph.value = 50.0
	s.step_days(1)
	var want := 0.03 + float(_forest_count()) * reg.planet.per_forest_tile
	assert_almost_eq(s.planet_health() - 50.0, want, 0.0000001, "the daily delta carries the Purifier's term")
	_unstaff(b)
	assert_false(PlanetHealthSystem.is_working(s, b), "an unstaffed Purifier adds nothing")
	assert_eq(float(ph.daily_breakdown(s)["buildings"]), 0.0)
