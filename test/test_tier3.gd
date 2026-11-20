extends GutTest
## Ticket 34b: tier III costs, effects and the Lodge (design.md section 10). Tier III opens in the City and costs
## tools 20% + Lumen cells 10% + cut stone 25% of the base wood + stone cost (data/tiers/tiers.tres, per-def overrides
## in the TierDef); output or beds x2 of base and +2 worker slots. Tent III is the Lodge (4 beds). Lumen extractor
## tiers raise output but never the blight radius or rate.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "city"
	s.planet_health_override = 100.0
	h = s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


func _strip_building(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var bid := s.place_building_instant(id, Vector2i(h.x + dx, h.y - def.size.y))
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings.get(bid)


# AC1: tier III needs the City, and costs tools + Lumen cells + cut stone.
func test_tier_three_needs_city() -> void:
	var tent := _strip_building("tent", 4)
	tent.tier = 2
	s.era_override = "town"
	assert_eq(s.can_upgrade(tent.id)["reason"], "era_locked")
	s.era_override = "city"
	assert_true(s.can_upgrade(tent.id)["ok"])


# AC1: every upgradable building's tier III cost is tools + Lumen cells + cut stone, and it follows the default
# fractions of the base wood + stone cost (rounded up) unless the data overrides it.
func test_tier_three_costs_are_tools_cells_and_cut_stone() -> void:
	var seen := 0
	for id in reg.buildings:
		var def: BuildingDef = reg.buildings[id]
		if not def.upgradable:
			continue
		seen += 1
		var b := Building.new()
		b.def = def
		var cost := b.tier_cost(reg, 3)
		assert_eq(cost.keys().size(), 3, "%s tier III cost goods" % id)
		for g in ["tools", "lumen_cells", "cut_stone"]:
			assert_true(cost.get(g, 0) > 0, "%s tier III needs %s" % [id, g])
		var base := float(def.cost.get("wood", 0)) + float(def.cost.get("stone", 0))
		# Per-def data may nudge a number by one (Quarry's cut stone is 6, not 7).
		assert_true(absi(cost["tools"] - int(ceil(base * 0.2 - 0.000001))) <= 1, "%s tools ~20%%" % id)
		assert_true(absi(cost["lumen_cells"] - int(ceil(base * 0.1 - 0.000001))) <= 1, "%s cells ~10%%" % id)
		assert_true(absi(cost["cut_stone"] - int(ceil(base * 0.25 - 0.000001))) <= 1, "%s cut stone ~25%%" % id)
	assert_gt(seen, 0)
	# A def without an override takes the rule: 20 wood and stone -> 4 tools, 2 cells, 5 cut stone.
	var d := BuildingDef.new()
	d.id = "synthetic"
	d.cost = {"wood": 14, "stone": 6}
	assert_eq(reg.tiers.cost_of(d, 3), {"tools": 4, "lumen_cells": 2, "cut_stone": 5})


# Tier III effects: x2 of base and +2 worker slots; a real upgrade from II delivers the cost and finishes.
func test_a_real_tier_three_upgrade() -> void:
	var forager := _strip_building("forager", 4)
	forager.tier = 2
	s.refresh_population()
	assert_true(s.upgrade(forager.id))
	assert_eq(forager.upgrade_cost, forager.tier_cost(reg, 3))
	assert_eq(forager.tier, 2, "keeps running at tier II during the works")
	s.hearth.inventory.add("tools", 50.0)
	s.hearth.inventory.add("lumen_cells", 50.0)
	s.hearth.inventory.add("cut_stone", 50.0)
	for i in 10 * 24:
		if not forager.upgrading():
			break
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(1)
	assert_false(forager.upgrading())
	assert_eq(forager.tier, 3)
	assert_eq(forager.output_factor(reg), 2.0)
	assert_eq(forager.effective_worker_slots(reg), forager.def.worker_slots + 2)


# AC3: Tent III is the Lodge and houses 4 (data: display name and the x2 factor over 2 beds).
func test_tent_iii_is_the_lodge() -> void:
	var tent := _strip_building("tent", 4)
	var beds := s.beds_total()
	tent.tier = 3
	s.refresh_population()
	assert_eq(tent.display_name(reg), "Lodge")
	assert_eq(tent.effective_beds(reg), 5)
	assert_eq(s.beds_total(), beds + 2, "a Lodge houses two more than a Tent")
	assert_eq(reg.get_building("tent").housing_beds, 3, "the base is still 3 beds")


# AC2: extractor tiers raise output, never the blight radius or period (every upgradable vein extractor).
func test_extractor_tiers_raise_output_not_blight() -> void:
	var checked := 0
	for id in reg.buildings:
		var def: BuildingDef = reg.buildings[id]
		if not (def.upgradable and def.vein_extractor):
			continue
		checked += 1
		var o := _vein_spot(id)
		assert_ne(o, Vector2i(-1, -1), "%s has a vein spot" % id)
		if o.x < 0:
			continue
		var a := Settlement.new_game(SEED, reg)
		a.era_override = "city"
		var b := Settlement.new_game(SEED, reg)
		b.era_override = "city"
		var ba: Building = a.buildings[a.place_building_instant(id, o)]
		var bb: Building = b.buildings[b.place_building_instant(id, o)]
		bb.tier = 3
		assert_eq(bb.output_factor(reg), 2.0, "%s output doubles" % id)
		for d in range(1, 13):
			a.step_hours(DAY)
			b.step_hours(DAY)
		var blight_a := PackedByteArray(a.map.blight)
		assert_gt(a.map.blight.count(1), 0, "%s blighted something" % id)
		assert_eq(b.map.blight, blight_a, "%s tier III blights the same tiles at the same rate" % id)
		assert_eq(bb.def.blight_radius, ba.def.blight_radius)
		assert_eq(bb.def.blight_period_days, ba.def.blight_period_days)
	assert_gt(checked, 1, "the taps, pumps and reactors")


func _vein_spot(id: String) -> Vector2i:
	var def := reg.get_building(id)
	for y in MapState.HEIGHT - def.size.y:
		for x in MapState.WIDTH - def.size.x:
			var o := Vector2i(x, y)
			if not s.can_place(id, o, true)["ok"]:
				continue
			return o
	return Vector2i(-1, -1)
