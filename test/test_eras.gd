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
	assert_eq(bell.cost, {"wood": 48, "stone": 72, "gold": 20, "lumen": 20, "planks": 20})
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
	_stock(s, "wood", 500.0)
	_stock(s, "stone", 500.0)
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
	assert_eq(village.size(), 10, "the Village set (Cleanser moved here in 1.1.4) of design section 16")

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


# ---------------------------------------------------------------- ticket 32: the Lumen Spire and the City gate

# AC1a: the row and the gate numbers are the design's (section 15 City row, section 16 Town table).
func test_lumen_spire_and_city_gate_match_the_design() -> void:
	var spire := reg.get_building("lumen_spire")
	assert_not_null(spire)
	assert_eq([spire.era, spire.category, spire.size], ["town", "landmark", Vector2i(2, 2)])
	assert_eq(spire.cost, {"wood": 100, "stone": 150, "gold": 80, "lumen": 120, "planks": 40, "cut_stone": 40})
	assert_eq(spire.worker_slots, 0)
	var city := reg.get_era("city")
	assert_eq([city.gate_pop, city.gate_gold, city.gate_landmark], [100, 500, "lumen_spire"])
	# the Town gate (the previous landmark) is unchanged
	var town := reg.get_era("town")
	assert_eq([town.gate_pop, town.gate_gold, town.gate_landmark], [40, 150, "bell_tower"])


# AC1b: a finished Lumen Spire + pop 100 + gold 500 advances Town -> City, and the gate only checks the gold.
func test_lumen_spire_pop_and_gold_advance_to_city() -> void:
	s.era_current = "town"
	var id := s.place_building_instant("lumen_spire", _free_spot("lumen_spire"))
	assert_gt(id, -1, "the Lumen Spire is placeable in the Town era")
	_grow_to(100)
	s.gold = 500.0
	s.step_hours(1)
	assert_eq(s.era_id(), "city")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "town", "to": "city"})
	assert_eq(s.gold, 500.0, "a gate checks the gold, it does not spend it")


# AC1c: each part of the City gate is required on its own: pop, gold, and a finished (not a site) Lumen Spire.
func test_each_city_gate_part_is_required() -> void:
	s.era_current = "town"
	var id := s.place_building_instant("lumen_spire", _free_spot("lumen_spire"))
	assert_gt(id, -1)
	_grow_to(99)
	s.gold = 500.0
	s.step_hours(1)
	assert_eq(s.era_id(), "town", "pop 99")
	_grow_to(100)
	s.gold = 499.0
	s.step_hours(1)
	assert_eq(s.era_id(), "town", "gold 499")
	s.gold = 500.0
	s.buildings[id].site = true  # an unfinished Lumen Spire does not count
	s.step_hours(1)
	assert_eq(s.era_id(), "town", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "city")


# AC2: nothing in the Town set is unbuildable. A Town settlement with enough storage and gold places every Town
# building through the real command API, delivers its cost and lets the builders finish it on seed 42. Same shape as
# the Village test above: one site at a time, no roads (so finished buildings take no jobs).
func test_every_town_building_can_be_built() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_current = "town"
	s.gold = 3000.0
	# Storage for the whole Town set: the Hearth holds 150 per good, each storehouse 400 units shared. Food keeps the
	# builders from leaving over the months of work (GrowthSystem: 1 food per citizen per day, then they leave).
	for i in 4:
		var st_spot := _village_spot(s, "storehouse")
		assert_ne(st_spot, Vector2i(-1, -1), "a storehouse fits on seed 42")
		assert_gt(s.place_building_instant("storehouse", st_spot), -1)
	_stock(s, "wood", 380.0)  # the Town set costs 345 wood and 345 stone
	_stock(s, "stone", 380.0)
	_stock(s, "planks", 125.0)
	_stock(s, "lumen", 400.0)  # the whole cost plus the Town upkeep that runs while the sites go up
	_stock(s, "cut_stone", 45.0)
	_stock(s, "food", 600.0)

	var real := DataRegistry.new()
	real.load_all()
	var town: Array[BuildingDef] = []
	for d: BuildingDef in real.buildings.values():
		if d.era == "town":
			town.append(d)
	town.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool: return a.id < b.id)
	assert_eq(town.size(), 11, "the Town set (Cleanser moved to Village in 1.1.4) of design section 16")

	for d in town:
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



# ---------------------------------------------------------------- ticket 35: the Lumen Nexus and the Conflux gate

# AC1a: the row and the gate numbers are the design's (section 15 Conflux row, section 16 City table).
func test_lumen_nexus_and_conflux_gate_match_the_design() -> void:
	var nexus := reg.get_building("lumen_nexus")
	assert_not_null(nexus)
	assert_eq([nexus.era, nexus.category, nexus.size], ["city", "landmark", Vector2i(3, 3)])
	assert_eq(nexus.cost, {"wood": 160, "stone": 240, "gold": 200, "lumen": 300, "cut_stone": 80, "tools": 40, "lumen_cells": 30})
	assert_eq(nexus.worker_slots, 0)
	var conflux := reg.get_era("conflux")
	assert_eq([conflux.gate_pop, conflux.gate_gold, conflux.gate_landmark], [200, 1200, "lumen_nexus"])
	# the City gate (the previous landmark) is unchanged
	var city := reg.get_era("city")
	assert_eq([city.gate_pop, city.gate_gold, city.gate_landmark], [100, 500, "lumen_spire"])


# AC1b: a finished Lumen Nexus + pop 200 + gold 1200 advances City -> Conflux, and the gate only checks the gold.
func test_lumen_nexus_pop_and_gold_advance_to_conflux() -> void:
	s.era_current = "city"
	var id := s.place_building_instant("lumen_nexus", _free_spot("lumen_nexus"))
	assert_gt(id, -1, "the Lumen Nexus is placeable in the City era")
	_grow_to(200)
	s.gold = 1200.0
	s.step_hours(1)
	assert_eq(s.era_id(), "conflux")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "city", "to": "conflux"})
	assert_eq(s.gold, 1200.0, "a gate checks the gold, it does not spend it")


# AC1c: each part of the Conflux gate is required on its own: pop, gold, and a finished (not a site) Lumen Nexus.
func test_each_conflux_gate_part_is_required() -> void:
	s.era_current = "city"
	var id := s.place_building_instant("lumen_nexus", _free_spot("lumen_nexus"))
	assert_gt(id, -1)
	_grow_to(199)
	s.gold = 1200.0
	s.step_hours(1)
	assert_eq(s.era_id(), "city", "pop 199")
	_grow_to(200)
	s.gold = 1199.0
	s.step_hours(1)
	assert_eq(s.era_id(), "city", "gold 1199")
	s.gold = 1200.0
	s.buildings[id].site = true  # an unfinished Lumen Nexus does not count
	s.step_hours(1)
	assert_eq(s.era_id(), "city", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "conflux")


# AC2: nothing in the City set is unbuildable. A City settlement with enough storage and gold places every City
# building through the real command API, delivers its cost and lets the builders finish it on seed 42. Same shape as
# the Town test above. The Lumen Reactor (on_vein) goes first: veins are scarce and the other sites would cover them.
func test_every_city_building_can_be_built() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_current = "city"
	s.gold = 3000.0
	for i in 8:
		var st_spot := _village_spot(s, "storehouse")
		assert_ne(st_spot, Vector2i(-1, -1), "a storehouse fits on seed 42")
		assert_gt(s.place_building_instant("storehouse", st_spot), -1)
	for i in 24:
		s.add_citizen()  # eight storehouses open 24 hauler slots, which rank above the builders: enough hands for both
	_stock(s, "wood", 430.0)  # the City set costs 419 wood and 561 stone
	_stock(s, "stone", 570.0)
	_stock(s, "planks", 60.0)
	_stock(s, "lumen", 1200.0)  # the whole cost plus the upkeep of the finished buildings while the sites go up
	_stock(s, "cut_stone", 175.0)
	_stock(s, "tools", 40.0)
	_stock(s, "lumen_cells", 30.0)
	_stock(s, "food", 800.0)  # keeps the builders from leaving over the months of work

	var real := DataRegistry.new()
	real.load_all()
	var city: Array[BuildingDef] = []
	for d: BuildingDef in real.buildings.values():
		if d.era == "city":
			city.append(d)
	city.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		if (a.placement_rule == "on_vein") != (b.placement_rule == "on_vein"):
			return a.placement_rule == "on_vein"
		return a.id < b.id)
	assert_eq(city.size(), 7, "the City set of design section 16")

	for d in city:
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
		for i in 60 * 24:
			if not site.site:
				break
			s.step_hours(1)
		assert_false(site.site, "builders finished the %s" % d.id)


# ---------------------------------------------------------------- ticket 39d: the Sky Foundry and the Skyborne gate

# AC1a: the row and the gate numbers are the design's (section 15 Conflux row, section 17).
func test_sky_foundry_and_skyborne_gate_match_the_design() -> void:
	var f := reg.get_building("sky_foundry")
	assert_not_null(f)
	assert_eq([f.era, f.category, f.size], ["conflux", "landmark", Vector2i(3, 3)])
	assert_eq(f.cost, {"wood": 240, "stone": 360, "gold": 400, "lumen": 400, "cut_stone": 120, "tools": 80, "lumen_cells": 60})
	var sky := reg.get_era("skyborne")
	assert_eq([sky.gate_pop, sky.gate_gold, sky.gate_landmark], [320, 2500, "sky_foundry"])


# AC1b: a finished Sky Foundry + pop 320 + gold 2500 advances Conflux -> Skyborne; the gate does not spend the gold.
func test_sky_foundry_pop_and_gold_advance_to_skyborne() -> void:
	s.era_current = "conflux"
	var id := s.place_building_instant("sky_foundry", _free_spot("sky_foundry"))
	assert_gt(id, -1, "the Sky Foundry is placeable in the Conflux era")
	_grow_to(320)
	s.gold = 2500.0
	s.step_hours(1)
	assert_eq(s.era_id(), "skyborne")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "conflux", "to": "skyborne"})
	assert_eq(s.gold, 2500.0, "a gate checks the gold, it does not spend it")


# AC1c: each part of the Skyborne gate is required on its own: pop, gold and a finished (not a site) Sky Foundry.
func test_each_skyborne_gate_part_is_required() -> void:
	s.era_current = "conflux"
	var id := s.place_building_instant("sky_foundry", _free_spot("sky_foundry"))
	assert_gt(id, -1)
	_grow_to(319)
	s.gold = 2500.0
	s.step_hours(1)
	assert_eq(s.era_id(), "conflux", "pop 319")
	_grow_to(320)
	s.gold = 2499.0
	s.step_hours(1)
	assert_eq(s.era_id(), "conflux", "gold 2499")
	s.gold = 2500.0
	s.buildings[id].site = true  # an unfinished Sky Foundry does not count
	s.step_hours(1)
	assert_eq(s.era_id(), "conflux", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "skyborne")


## Raises the total stock of a good over all storage to at least `level`.
func _top_up(s: Settlement, good: String, level: float) -> void:
	var have := s.hearth.inventory.amount_of(good)
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b != s.hearth and not b.site and b.inventory != null:
			have += b.inventory.amount_of(good)
	if have < level:
		_stock(s, good, level - have)


# AC2: nothing in the Conflux set is unbuildable. Same shape as the City test: every Conflux row is placed through
# place_building on a legal tile on seed 42, has its cost delivered, is finished by the builders, and shows in the
# build bar of the Conflux era. The Vein Bore (on_vein) goes first: veins are scarce. One site at a time: each finished
# building is demolished once checked, so it does not wall the next site's door in (as the Town test avoids).
func test_every_conflux_building_can_be_built() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_current = "conflux"
	s.gold = 4000.0
	for i in 8:
		var st_spot := _village_spot(s, "storehouse")
		assert_ne(st_spot, Vector2i(-1, -1), "a storehouse fits on seed 42")
		assert_gt(s.place_building_instant("storehouse", st_spot), -1)
	for i in 24:
		s.add_citizen()  # eight storehouses open 24 hauler slots, which rank above the builders: enough hands for both

	var real := DataRegistry.new()
	real.load_all()
	var conflux: Array[BuildingDef] = []
	for d: BuildingDef in real.buildings.values():
		if d.era == "conflux":
			conflux.append(d)
	conflux.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		if (a.placement_rule == "on_vein") != (b.placement_rule == "on_vein"):
			return a.placement_rule == "on_vein"
		return a.id < b.id)
	assert_eq(conflux.size(), 9, "the Conflux set: pylon, battery, depot, dock, terraces, tower, bore, hall, foundry")

	var hud := HudModel.new(s)  # kept in a variable: it subscribes to the event bus
	var bar_ids := {}
	for cat in hud.build_bar():
		for e: Dictionary in cat["entries"]:
			bar_ids[e["id"]] = true

	for d in conflux:
		assert_true(bar_ids.has(d.id), "%s shows in the Conflux build bar" % d.id)
		var spot := _village_spot(s, d.id)
		assert_ne(spot, Vector2i(-1, -1), "%s has a legal spot on seed 42" % d.id)
		var id := s.place_building(d.id, spot)
		assert_gt(id, -1, "%s placed through place_building at %s" % [d.id, spot])
		var site: Building = s.buildings.get(id)
		# food keeps the builders from leaving; the cost is stocked, then delivered from storage as a hauler would
		_top_up(s, "food", 600.0)
		_top_up(s, "lumen", 300.0)
		for g in d.cost:
			if g != BuildingDef.GOLD:
				_stock(s, g, float(d.cost[g]))
		for g in d.cost:
			if g == BuildingDef.GOLD:
				continue
			assert_eq(_deliver(s, site, g, float(d.cost[g])), 0.0, "%s: the %s cost was in storage" % [d.id, g])
		assert_true(site.site_delivered(), "%s site has its whole cost" % d.id)
		s.refresh_population()
		for i in 60 * 24:
			if not site.site:
				break
			s.step_hours(1)
		assert_false(site.site, "builders finished the %s" % d.id)
		if not site.site:
			s.demolish(id)
