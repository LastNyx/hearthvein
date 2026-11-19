extends GutTest
## Ticket 42: the Dawn Beacon (light need 0.35, Ascendant gate) and every Skyborne building being buildable.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


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


func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func test_beacon_row_matches_the_design() -> void:
	var b := reg.get_building("dawn_beacon")
	assert_not_null(b)
	assert_eq([b.era, b.category, b.size, b.layers], ["skyborne", "landmark", Vector2i(2, 2), "ground"])
	assert_eq(b.cost, {"wood": 320, "stone": 480, "gold": 800, "lumen": 600, "cut_stone": 150, "tools": 120, "lumen_cells": 100})
	assert_eq([b.worker_slots, b.upkeep_lumen, b.light_need_per_citizen], [0, 0.0, 0.35])
	var asc := reg.get_era("ascendant")
	assert_eq([asc.gate_pop, asc.gate_gold, asc.gate_landmark], [450, 4000, "dawn_beacon"])


# AC1: a finished Beacon lowers the per-citizen light need from 0.5 to 0.35 (a site does not).
func test_beacon_lowers_light_need() -> void:
	assert_eq(DimmingSystem.light_per_citizen(s), 0.5)
	var id := s.place_building_instant("dawn_beacon", _free_spot("dawn_beacon"))
	assert_gt(id, -1)
	s.buildings[id].site = true
	assert_eq(DimmingSystem.light_per_citizen(s), 0.5, "a site changes nothing")
	s.buildings[id].site = false
	assert_eq(DimmingSystem.light_per_citizen(s), 0.35)


# AC1b: the Dimming's nightly draw uses the lower need.
func test_dimming_draw_uses_the_beacon_need() -> void:
	s.planet_health_override = 100.0
	assert_gt(s.place_building_instant("dawn_beacon", _free_spot("dawn_beacon")), -1)
	var pop := s.citizens.size()
	_to_day(WINTER - 1)
	s.hearth.inventory.add("lumen", 100.0)
	_to_day(WINTER)
	var d: DimmingSystem = s.get_system(DimmingSystem)
	assert_almost_eq(d.last_light["need"], 0.35 * pop, 0.001)


# AC2: Beacon + pop 450 + gold 4000 advances Skyborne -> Ascendant; the gold is checked, not spent.
func test_beacon_pop_and_gold_advance_to_ascendant() -> void:
	s.era_current = "skyborne"
	assert_gt(s.place_building_instant("dawn_beacon", _free_spot("dawn_beacon")), -1)
	_grow_to(450)
	s.gold = 4000.0
	s.step_hours(1)
	assert_eq(s.era_id(), "ascendant")
	var ev := s.events.log_of("era_changed")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["data"], {"from": "skyborne", "to": "ascendant"})
	assert_eq(s.gold, 4000.0)


func test_each_ascendant_gate_part_is_required() -> void:
	s.era_current = "skyborne"
	var id := s.place_building_instant("dawn_beacon", _free_spot("dawn_beacon"))
	assert_gt(id, -1)
	_grow_to(449)
	s.gold = 4000.0
	s.step_hours(1)
	assert_eq(s.era_id(), "skyborne", "pop 449")
	_grow_to(450)
	s.gold = 3999.0
	s.step_hours(1)
	assert_eq(s.era_id(), "skyborne", "gold 3999")
	s.gold = 4000.0
	s.buildings[id].site = true
	s.step_hours(1)
	assert_eq(s.era_id(), "skyborne", "site only")
	s.buildings[id].site = false
	s.step_hours(1)
	assert_eq(s.era_id(), "ascendant")


func test_no_beacon_no_advance() -> void:
	s.era_current = "skyborne"
	_grow_to(450)
	s.gold = 4000.0
	s.step_hours(1)
	assert_eq(s.era_id(), "skyborne")


## Places a site through place_building (the real validity, era and gold rules) and finishes it at once.
func _build(def_id: String, origin: Vector2i, layer: int = Building.LAYER_GROUND) -> Building:
	var id := s.place_building(def_id, origin, layer)
	assert_gt(id, -1, "%s placed through place_building at %s (layer %d)" % [def_id, origin, layer])
	if id < 0:
		return null
	var b: Building = s.buildings[id]
	s.complete_site(b)
	assert_false(b.site, "%s finished" % def_id)
	return b


# AC3: every Skyborne row is placeable through place_building on seed 42 in a Skyborne settlement and shows in the bar.
func test_every_skyborne_building_can_be_built() -> void:
	s.era_current = "skyborne"
	s.gold = 20000.0
	var h := s.map.hearth_spot
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 5, h.y + 6):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
	var sky: Array[BuildingDef] = []
	for d: BuildingDef in reg.buildings.values():
		if d.era == "skyborne":
			sky.append(d)
	assert_eq(sky.size(), 9, "anchor, lift, spire, cistern, garden, collector, forge, observatory, beacon")
	var hud := HudModel.new(s)
	var bar_ids := {}
	for cat in hud.build_bar():
		for e: Dictionary in cat["entries"]:
			bar_ids[e["id"]] = true
	for d in sky:
		assert_true(bar_ids.has(d.id), "%s shows in the Skyborne build bar" % d.id)

	var anchor := _build("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	var isl: Island = (s.get_system(IslandSystem) as IslandSystem).island_of_anchor(anchor.id)
	assert_not_null(isl, "finishing the anchor raised the island")
	var at := func(dx: int, dy: int) -> Vector2i: return isl.rect.position + Vector2i(dx, dy)
	# island-only rows on the sky layer, then the either-layer rows on both layers
	var row := 0
	for def_id in ["cloud_cistern", "sky_garden", "aether_collector", "skyforge", "skyspire", "observatory"]:
		var b := _build(def_id, at.call(1, row * 2), Building.LAYER_SKY)
		if b != null:
			assert_eq(b.layer, Building.LAYER_SKY)
		row += 1
	for def_id in ["skyspire", "observatory"]:
		var spot := _free_spot(def_id)
		assert_ne(spot, Vector2i(-1, -1), "%s has a ground spot" % def_id)
		_build(def_id, spot)
	# Sky Lift through the ground API (a ground tile under the island), the Beacon on the ground
	var lift_t := Vector2i(-1, -1)
	for y in range(isl.rect.position.y, isl.rect.end.y):
		for x in range(isl.rect.position.x, isl.rect.end.x):
			if lift_t.x < 0 and s.can_place("sky_lift", Vector2i(x, y))["ok"]:
				lift_t = Vector2i(x, y)
	assert_ne(lift_t, Vector2i(-1, -1), "a Sky Lift spot exists under the island")
	_build("sky_lift", lift_t)
	var beacon_t := _free_spot("dawn_beacon")
	assert_ne(beacon_t, Vector2i(-1, -1))
	_build("dawn_beacon", beacon_t)
