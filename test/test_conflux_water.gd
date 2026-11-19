extends GutTest
## Ticket 39: Conduit Terraces and Water Tower (design.md sections 9, 10 and 17 Conflux).
## Terraces: 3x2 housing for 36 that needs drinking water and upgrades like the Rowhouse. Water Tower: drinking water
## r16 from any tile, wets tiles r3.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var sp: SpiritSystem
var h: Vector2i
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "conflux"
	sp = s.get_system(SpiritSystem)
	h = s.map.hearth_spot


## A finished building inserted straight into the layout (no cost, no road).
func _fake(def_id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	_next_fake += 1
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	s.buildings[b.id] = b
	s.structure_version += 1
	return b


func _all_live_in(home_id: int) -> void:
	for cid in s.citizens:
		(s.citizens[cid] as Citizen).home_id = home_id


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


## A cleared 3x2 patch near the Hearth that takes a Terraces.
func _terraces_spot() -> Vector2i:
	var rect := MapState.region_rect(s.map.start_region)
	for y in range(rect.position.y, rect.end.y - 2):
		for x in range(rect.position.x, rect.end.x - 3):
			if s.can_place("conduit_terraces", Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# Data: the Conflux rows.
func test_rows_match_the_conflux_table() -> void:
	var t := reg.get_building("conduit_terraces")
	assert_eq([t.era, t.category, t.size], ["conflux", "housing", Vector2i(3, 2)])
	assert_eq(t.cost, {"wood": 98, "stone": 42, "gold": 40, "planks": 40, "cut_stone": 40, "tools": 10})
	assert_eq([t.upkeep_lumen, t.worker_slots, t.housing_beds, t.needs_water], [2.0, 0, 36, true])
	var w := reg.get_building("water_tower")
	assert_eq([w.era, w.category, w.size], ["conflux", "water", Vector2i(1, 1)])
	assert_eq(w.cost, {"wood": 32, "stone": 48, "gold": 20, "cut_stone": 30})
	assert_eq([w.upkeep_lumen, w.water_radius, w.wet_radius, w.needs_water], [1.0, 16, 3, false])
	assert_ne(w.placement_rule, "on_wet", "a pumped tower needs no wet tile")


# AC1a: Conduit Terraces house 36.
func test_terraces_house_36() -> void:
	var o := _terraces_spot()
	assert_ne(o, Vector2i(-1, -1))
	var beds := s.beds_total()
	assert_gt(s.place_building_instant("conduit_terraces", o), -1)
	assert_eq(s.beds_total(), beds + 36)


# AC1b: without a water source in reach the Terraces cost Spirit water; with one they do not.
func test_unwatered_terraces_pay_the_water_penalty() -> void:
	var home := _fake("conduit_terraces", Vector2i(230, 230))
	_all_live_in(home.id)
	assert_eq(_factor("water"), -reg.spirit.water_max, "no well or tower in reach")
	_fake("well", Vector2i(222, 230))
	assert_eq(_factor("water"), 0.0, "a Well in r8 serves the Terraces")


# AC1c: Terraces upgrade to tier II (x1.5, 54 beds) and III (x2, 72 beds) like the Rowhouse.
func test_terraces_upgrade() -> void:
	var id := s.place_building_instant("conduit_terraces", Vector2i(h.x + 4, h.y - 2))
	assert_gt(id, -1, "placed beside the Hearth road")
	var b: Building = s.buildings[id]
	assert_true(s.can_upgrade(id)["ok"])
	assert_eq(reg.get_building("conduit_terraces").tiers.size(), 2)
	s.hearth.inventory.add("planks", 200.0)
	s.hearth.inventory.add("cut_stone", 200.0)
	assert_true(s.upgrade(id))
	for i in 30 * 24:
		if not b.upgrading():
			break
		s.step_hours(1)
	assert_eq(b.tier, 2)
	assert_eq(b.effective_beds(reg), 54)
	b.tier = 3
	assert_eq(b.effective_beds(reg), 72)


# AC2a: a Water Tower serves a home 16 tiles away and not 17.
func test_tower_serves_at_16_tiles_and_not_17() -> void:
	var home := _fake("conduit_terraces", Vector2i(230, 230))  # footprint x 230..232
	_all_live_in(home.id)
	_fake("water_tower", Vector2i(230 - 16, 230))  # 16 tiles from the footprint edge
	assert_eq(_factor("water"), 0.0, "16 tiles away is served")
	s.buildings.erase(s.buildings.keys().max())
	s.structure_version += 1
	_fake("water_tower", Vector2i(230 - 17, 230))  # 17 tiles
	assert_eq(_factor("water"), -reg.spirit.water_max, "17 tiles away is not")


# AC2b: a finished Water Tower wets the tiles within 3 and not the ring beyond; a demolished one stops.
func test_tower_wets_r3() -> void:
	var spot := Vector2i(-1, -1)
	var rect := MapState.region_rect(s.map.start_region)
	for y in range(rect.position.y + 6, rect.end.y - 6):
		for x in range(rect.position.x + 6, rect.end.x - 6):
			var ok := true
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					if s.map.is_wet(x + dx, y + dy):
						ok = false
			if ok and s.can_place("water_tower", Vector2i(x, y), true)["ok"]:
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	assert_ne(spot, Vector2i(-1, -1), "a dry patch for the tower")
	var id := s.place_building_instant("water_tower", spot)
	assert_gt(id, -1)
	assert_true(s.map.is_wet(spot.x + 3, spot.y - 3), "r3 corner is wet")
	assert_true(s.map.is_wet(spot.x - 3, spot.y))
	assert_false(s.map.is_wet(spot.x + 4, spot.y), "r4 is dry")
	assert_true(s.demolish(id))
	assert_false(s.map.is_wet(spot.x + 3, spot.y), "demolished: dry again")
