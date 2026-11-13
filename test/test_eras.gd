extends GutTest
## Ticket 16: eras, gates and the Meeting Hall.
## Ticket 26: the Bell Tower as the Village landmark, the Town gate, and every Village building being buildable.

const SEED := 42

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	# no Village building exists as data yet: inject one (this registry is private to the test)
	var d := BuildingDef.new()
	d.id = "test_village_hut"
	d.display_name = "Village hut"
	d.era = "village"
	d.category = "housing"
	d.size = Vector2i(2, 2)
	d.placement_rule = "any"
	reg.buildings[d.id] = d


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)


func _free_spot(def_id: String) -> Vector2i:
	for y in range(0, MapState.HEIGHT - 3):
		for x in range(0, MapState.WIDTH - 3):
			if s.can_place(def_id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _grow_to(n: int) -> void:
	while s.citizens.size() < n:
		s.add_citizen()


func test_village_building_locked_in_camp() -> void:
	var o := _free_spot("test_village_hut")
	assert_eq(s.era_id(), "camp")
	var r := s.can_place("test_village_hut", o)
	assert_false(r["ok"])
	assert_eq(r["reason"], "era_locked")
	assert_eq(s.place_building("test_village_hut", o), -1)
	assert_false(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "test_village_hut"))
	# the debug path may bypass the lock
	assert_gt(s.place_building_instant("test_village_hut", o), -1)
	s.era_current = "village"
	assert_true(s.can_place("test_village_hut", _free_spot("test_village_hut"))["ok"])


func test_meeting_hall_pop_gold_advances_to_village() -> void:
	var o := _free_spot("meeting_hall")
	var id := s.place_building_instant("meeting_hall", o)
	assert_gt(id, -1)
	_grow_to(15)
	s.gold = 30.0
	s.step_hours(1)
	assert_eq(s.era_id(), "village")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "camp", "to": "village"})
	assert_eq(s.gold, 30.0)
	assert_true(s.unlocked_buildings().any(func(b: BuildingDef) -> bool: return b.id == "test_village_hut"))


func test_each_gate_part_is_required() -> void:
	var id := s.place_building_instant("meeting_hall", _free_spot("meeting_hall"))
	_grow_to(14)
	s.gold = 30.0
	s.step_hours(1)
	assert_eq(s.era_id(), "camp", "pop 14")
	_grow_to(15)
	s.gold = 29.0
	s.step_hours(1)
	assert_eq(s.era_id(), "camp", "gold 29")
	s.gold = 30.0
	s.buildings[id].site = true  # an unfinished landmark does not count
	s.step_hours(1)
	assert_eq(s.era_id(), "camp", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "village")


func test_gate_numbers_come_from_data_rows() -> void:
	var row := reg.get_era("village")
	var old_pop := row.gate_pop
	var old_gold := row.gate_gold
	row.gate_pop = 3
	row.gate_gold = 7
	s.place_building_instant("meeting_hall", _free_spot("meeting_hall"))
	_grow_to(3)
	s.gold = 7.0
	var g := s.era_gate()
	assert_eq(g["pop_need"], 3)
	assert_eq(g["gold_need"], 7)
	s.step_hours(1)
	row.gate_pop = old_pop
	row.gate_gold = old_gold
	assert_eq(s.era_id(), "village")


func test_era_override_still_pins() -> void:
	s.era_override = "town"
	assert_eq(s.era_id(), "town")
	assert_eq(s.era_current, "camp")


# ---------------------------------------------------------------- ticket 26: the Bell Tower and the Town gate

# AC1a: the row and the gate numbers are the design's (section 15 Town row, section 16 Village table).
func test_bell_tower_and_town_gate_match_the_design() -> void:
	var bell := reg.get_building("bell_tower")
	assert_not_null(bell)
	assert_eq([bell.era, bell.category, bell.size], ["village", "landmark", Vector2i(1, 1)])
	assert_eq(bell.cost, {"materials": 120, "gold": 20, "lumen": 20, "planks": 20})
	assert_eq(bell.worker_slots, 0)
	var town := reg.get_era("town")
	assert_eq([town.gate_pop, town.gate_gold, town.gate_landmark], [40, 150, "bell_tower"])
	# the Village gate (the previous landmark) is unchanged
	var village := reg.get_era("village")
	assert_eq([village.gate_pop, village.gate_gold, village.gate_landmark], [15, 30, "meeting_hall"])


# AC1b: a finished Bell Tower + pop 40 + gold 150 advances Village -> Town, and the gate only checks the gold.
func test_bell_tower_pop_and_gold_advance_to_town() -> void:
	s.era_current = "village"
	var id := s.place_building_instant("bell_tower", _free_spot("bell_tower"))
	assert_gt(id, -1, "the Bell Tower is placeable in the Village era")
	_grow_to(40)
	s.gold = 150.0
	s.step_hours(1)
	assert_eq(s.era_id(), "town")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "village", "to": "town"})
	assert_eq(s.gold, 150.0, "a gate checks the gold, it does not spend it")


# AC1c: each part of the Town gate is required on its own: pop, gold, and a finished (not a site) Bell Tower.
func test_each_town_gate_part_is_required() -> void:
	s.era_current = "village"
	var id := s.place_building_instant("bell_tower", _free_spot("bell_tower"))
	assert_gt(id, -1)
	_grow_to(39)
	s.gold = 150.0
	s.step_hours(1)
	assert_eq(s.era_id(), "village", "pop 39")
	_grow_to(40)
	s.gold = 149.0
	s.step_hours(1)
	assert_eq(s.era_id(), "village", "gold 149")
	s.gold = 150.0
	s.buildings[id].site = true  # an unfinished Bell Tower does not count
	s.step_hours(1)
	assert_eq(s.era_id(), "village", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "town")


## Every walkable tile 4-connected to the Hearth (terrain only; water is the only barrier on seed 42).
func _hearth_land(s: Settlement) -> Dictionary:
	var seen := {s.map.hearth_spot: true}
	var queue: Array[Vector2i] = [s.map.hearth_spot]
	var head := 0
	while head < queue.size():
		var t: Vector2i = queue[head]
		head += 1
		for d in Placement.DIRS:
			var n: Vector2i = t + d
			if not MapState.in_bounds(n.x, n.y) or seen.has(n):
				continue
			var td := reg.get_terrain(s.map.terrain_id_at(n.x, n.y))
			if td == null or td.walk_speed <= 0.0:
				continue
			seen[n] = true
			queue.append(n)
	return seen


## First legal origin for `def_id` in a ring around the Hearth, nearest first; (-1, -1) when the owned land has none.
func _ring_spot(s: Settlement, def_id: String, land: Dictionary) -> Vector2i:
	var h := s.map.hearth_spot
	for r in 24:
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if absi(x - h.x) != r and absi(y - h.y) != r:
					continue
				if not land.has(Vector2i(x, y)):
					continue
				if s.can_place(def_id, Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Buys one adjacent unowned region, funding the treasury when it is the only thing short.
func _buy_a_region(s: Settlement) -> bool:
	for attempt in 2:
		for r in MapState.REGION_COUNT:
			if s.can_buy_region(r)["ok"]:
				return s.buy_region(r)
		s.gold += 1000.0
	return false


## A legal spot on reachable, owned land; buys an adjacent region when the owned ones cannot hold the footprint.
func _village_spot(s: Settlement, def_id: String) -> Vector2i:
	var land := _hearth_land(s)
	var spot := _ring_spot(s, def_id, land)
	var tries := 0
	while spot == Vector2i(-1, -1) and tries < MapState.REGION_COUNT - 1:
		tries += 1
		if not _buy_a_region(s):
			break
		land = _hearth_land(s)
		spot = _ring_spot(s, def_id, land)
	return spot


## Puts a good into real storage (Hearth first, then the storehouses), asserting the whole amount fit.
func _stock(s: Settlement, good: String, amount: float) -> void:
	var left := amount
	left -= s.hearth.inventory.add(good, left)
	for id in s.buildings:
		if left <= Inventory.EPS:
			break
		var b: Building = s.buildings[id]
		if b != s.hearth and b.inventory != null:
			left -= b.inventory.add(good, left)
	assert_between(left, -Inventory.EPS, Inventory.EPS, "the test stock of %s fits in storage" % good)


## Takes a cost good out of real storage and puts it into the site's buffer, as a hauler would (hauling itself is
## covered by test_hauling / test_sawmill). Returns what storage could not supply.
func _deliver(s: Settlement, site: Building, good: String, amount: float) -> float:
	var left := amount
	left -= s.hearth.inventory.remove(good, left)
	for id in s.buildings:
		if left <= Inventory.EPS:
			break
		var st: Building = s.buildings[id]
		if st != s.hearth and st != site and not st.site and st.inventory != null:
			left -= st.inventory.remove(good, left)
	if left > Inventory.EPS:
		return left
	site.input_buffer.add(good, amount)
	return 0.0


# AC2: nothing in the Village set is unbuildable. A Village settlement with enough storage and gold places every
# Village building through the real command API, delivers its cost, and lets the builders finish it on seed 42.
# One site at a time, so finished buildings around the Hearth do not wall the next site's door in (without roads
# there is no connection bonus, so completed buildings do not pull citizens off the builder slots either).
func test_every_village_building_can_be_built() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_current = "village"  # the real progression state; the Meeting Hall test reaches it normally
	s.gold = 2000.0
	# Storage for the whole Village set: the Hearth holds 150 per good, each storehouse 400 units shared.
	for i in 3:
		var st_spot := _village_spot(s, "storehouse")
		assert_ne(st_spot, Vector2i(-1, -1), "a storehouse fits on seed 42")
		assert_gt(s.place_building_instant("storehouse", st_spot), -1)
	_stock(s, "materials", 500.0)
	_stock(s, "planks", 60.0)
	_stock(s, "lumen", 80.0)
	_stock(s, "food", 500.0)

	var real := DataRegistry.new()
	real.load_all()
	var village: Array[BuildingDef] = []
	for d: BuildingDef in real.buildings.values():
		if d.era == "village":
			village.append(d)
	village.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool: return a.id < b.id)
	assert_eq(village.size(), 10, "the Village set of design section 16")

	for d in village:
		var spot := _village_spot(s, d.id)
		assert_ne(spot, Vector2i(-1, -1), "%s has a legal spot on seed 42" % d.id)
		var id := s.place_building(d.id, spot)
		assert_gt(id, -1, "%s placed through place_building at %s" % [d.id, spot])
		var site: Building = s.buildings.get(id)
		for g in d.cost:
			if g == BuildingDef.GOLD:
				continue
			assert_eq(_deliver(s, site, g, float(d.cost[g])), 0.0, "%s: the %s cost was in storage" % [d.id, g])
		assert_true(site.site_delivered(), "%s site has its whole cost" % d.id)
		s.refresh_population()
		for i in 30 * 24:
			if not site.site:
				break
			s.step_hours(1)
		assert_false(site.site, "builders finished the %s" % d.id)

