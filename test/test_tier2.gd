extends GutTest
## Ticket 31b: tier II costs, effects and the Hut (design.md section 10). The default rule (x1.5, +1 slot, planks 50%
## and cut stone 25% of the base wood + stone cost) lives in data/tiers/tiers.tres; a TierDef overrides it per building.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"
	h = s.map.hearth_spot
	_strip()


func _strip() -> void:
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


func _workers_on(b: Building) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id:
			n += 1
	return n


## A throwaway def with two empty-cost tiers, to check the default-cost fractions.
func _synthetic_def(base_wood: int) -> BuildingDef:
	var d := BuildingDef.new()
	d.id = "synthetic"
	d.display_name = "Synthetic"
	d.era = "camp"
	d.category = "resources"
	d.cost = {"wood": base_wood}
	d.worker_slots = 1
	d.upgradable = true
	var t2 := TierDef.new()
	t2.display_name = "Synthetic II"
	var t3 := TierDef.new()
	t3.display_name = "Synthetic III"
	var tiers: Array[TierDef] = [t2, t3]
	d.tiers = tiers
	return d


# AC1: the default rule is the design's table row, read from data.
func test_default_rule_matches_design() -> void:
	var rule := reg.tiers
	assert_not_null(rule, "data/tiers/tiers.tres loads")
	if rule == null:
		return
	assert_eq(rule.eras, ["town", "city"])
	assert_eq(rule.output_factors, [1.5, 2.0])
	assert_eq(rule.extra_worker_slots, [1, 2])
	assert_eq(rule.cost_fractions[0], {"planks": 0.5, "cut_stone": 0.25})
	assert_eq(rule.cost_fractions[1], {"tools": 0.2, "lumen_cells": 0.1, "cut_stone": 0.25})


# AC1: costs are the fractions of the base wood + stone cost, rounded up; per-def TierDef costs win.
func test_default_costs_and_per_def_overrides() -> void:
	var d := _synthetic_def(20)
	assert_eq(reg.tiers.cost_of(d, 2), {"planks": 10, "cut_stone": 5})
	assert_eq(reg.tiers.cost_of(d, 3), {"tools": 4, "lumen_cells": 2, "cut_stone": 5})
	var odd := _synthetic_def(10)  # 50% and 25% of 10 are 5 and 2.5: whole goods round up
	assert_eq(reg.tiers.cost_of(odd, 2), {"planks": 5, "cut_stone": 3})
	# The real data overrides the rule: Quarry's 25% of 25 would be 7, the data says 6.
	var quarry := reg.get_building("quarry")
	assert_eq(quarry.tiers[0].cost, {"planks": 13, "cut_stone": 6})
	assert_eq(reg.tiers.cost_of(quarry, 2), {"planks": 13, "cut_stone": 6}, "the TierDef cost wins")
	assert_eq(reg.tiers.cost_of(_synthetic_def(25), 2), {"planks": 13, "cut_stone": 7},
			"without an override the fraction rounds up")
	assert_eq(reg.get_building("forager").tiers[0].cost, {"planks": 5, "cut_stone": 3})


# AC1: tier II gives x1.5 output and one more worker slot; tier III x2 and two more.
func test_tier_two_and_three_effects() -> void:
	var forager := _strip_building("forager", 4)
	forager.tier = 2
	s.refresh_population()
	assert_eq(forager.output_factor(reg), 1.5)
	assert_eq(forager.effective_worker_slots(reg), 3)
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	assert_almost_eq(ps.multiplier(s, forager), 1.5, 0.001, "production asks the effective tier")
	assert_eq(_workers_on(forager), 3, "the extra slot is filled")
	forager.tier = 3
	s.refresh_population()
	assert_eq(forager.output_factor(reg), 2.0)
	assert_eq(forager.effective_worker_slots(reg), 4)
	assert_almost_eq(ps.multiplier(s, forager), 2.0, 0.001)
	assert_eq(_workers_on(forager), 4)


# AC2: Tent II is the Hut and houses 4.
func test_tent_ii_is_the_hut() -> void:
	var tent := _strip_building("tent", 4)
	var beds := s.beds_total()
	assert_eq(tent.display_name(reg), "Tent")
	tent.tier = 2
	s.refresh_population()
	assert_eq(tent.display_name(reg), "Hut")
	assert_eq(tent.effective_beds(reg), 4)
	assert_eq(s.beds_total(), beds + 1, "the Hut houses one more")
	tent.tier = 3
	s.refresh_population()
	assert_eq(tent.display_name(reg), "Lodge")
	assert_eq(tent.effective_beds(reg), 5)


# AC2: tier II needs Town.
func test_tier_two_needs_town() -> void:
	var tent := _strip_building("tent", 4)
	s.era_override = "village"
	assert_eq(s.can_upgrade(tent.id)["reason"], "era_locked")
	s.era_override = "town"
	assert_true(s.can_upgrade(tent.id)["ok"])


# A real upgrade applies the Hut: the cost is delivered, builders work, the tier and the beds move up.
func test_a_real_tent_upgrade_turns_it_into_a_hut() -> void:
	var tent := _strip_building("tent", 4)
	var beds := s.beds_total()
	s.hearth.inventory.add("planks", 100.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	assert_true(s.upgrade(tent.id))
	assert_eq(tent.upgrade_cost, reg.get_building("tent").tiers[0].cost)
	for i in 6 * 24:
		if not tent.upgrading():
			break
		s.step_hours(1)
	assert_false(tent.upgrading(), "the works finished")
	assert_eq(tent.tier, 2)
	assert_eq(tent.display_name(reg), "Hut")
	assert_eq(tent.effective_beds(reg), 4)
	assert_eq(s.beds_total(), beds + 1)
	assert_eq(s.events.log_of("building_upgraded").size(), 1)
