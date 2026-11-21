extends GutTest
## Ticket 31: upgrade tiers, core rules (design.md section 10). Only housing/food/resources/Lumen buildings upgrade;
## an upgrade is a construction job on a running building, which keeps its old tier until the work is done.

const SEED := 42
const SAVE_PATH := "/tmp/nyx-flash/hearthvein_ticket31_save.dat"

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


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## A cleared, road-connected strip east of the Hearth (the same patch the other tests use).
func _strip() -> void:
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## First tile where the def can stand, placed finished and free (debug/test path).
func _place_any(id: String) -> Building:
	for y in range(MapState.HEIGHT):
		for x in range(MapState.WIDTH):
			var t := Vector2i(x, y)
			var was := s.map.terrain_id_at(x, y)
			if was == "forest":
				s.set_terrain(t, "grass")  # tests place on cleared land; no rule needs the trees except near_forest
			if s.can_place(id, t, true)["ok"]:
				var bid := s.place_building_instant(id, t)
				if bid >= 0:
					return s.buildings[bid]
			elif was == "forest":
				s.set_terrain(t, was)
	return null


## A finished, road-connected building on the strip, `dx` tiles east of the Hearth.
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


# AC1: only housing, food, resources and Lumen buildings can upgrade.
func test_only_the_four_categories_can_upgrade() -> void:
	# One of each allowed category, placed wherever its rule allows (the Lumen Tap needs a vein).
	for id in ["tent", "forager", "woodcutter", "lumen_tap"]:
		var b := _place_any(id)
		assert_not_null(b, "%s placed" % id)
		if b == null:
			continue
		var r := s.can_upgrade(b.id)
		assert_true(r["ok"], "%s (%s) may upgrade: %s" % [id, b.def.category, r["reason"]])
	# Every other category refuses with a reason.
	for id in ["storehouse", "meeting_hall", "mason", "well", "market", "shrine"]:
		var b := _place_any(id)
		assert_not_null(b, "%s placed" % id)
		if b == null:
			continue
		var r := s.can_upgrade(b.id)
		assert_false(r["ok"], "%s (%s) must not upgrade" % [id, b.def.category])
		assert_eq(r["reason"], "category", "%s is refused by category" % id)


func test_can_upgrade_reasons() -> void:
	assert_eq(s.can_upgrade(9999)["reason"], "unknown_building")
	# A construction site cannot upgrade yet.
	var def := reg.get_building("tent")
	var site_id := s.place_building("tent", Vector2i(h.x + 10, h.y - def.size.y))
	assert_true(site_id >= 0)
	assert_eq(s.can_upgrade(site_id)["reason"], "site")
	# A finished one can, and cannot start twice.
	var tent := _strip_building("tent", 4)
	assert_eq(s.can_upgrade(tent.id), {"ok": true, "reason": ""})
	assert_true(s.upgrade(tent.id))
	assert_eq(s.can_upgrade(tent.id)["reason"], "in_progress")
	# At tier III there is no tier IV.
	var other := _strip_building("tent", 8)
	other.tier = 3
	assert_eq(s.can_upgrade(other.id)["reason"], "max_tier")


# AC1 (era gate): tier II opens in Town, tier III in City; the eras live in data.
func test_tier_era_gate() -> void:
	var tent := _strip_building("tent", 4)
	s.era_override = "village"
	assert_eq(s.can_upgrade(tent.id)["reason"], "era_locked", "tier II needs Town")
	s.era_override = "town"
	assert_true(s.can_upgrade(tent.id)["ok"], "tier II in Town")
	tent.tier = 2
	assert_eq(s.can_upgrade(tent.id)["reason"], "era_locked", "tier III needs City")
	s.era_override = "city"
	assert_true(s.can_upgrade(tent.id)["ok"], "tier III in City")
	assert_eq(reg.tiers.era_for(2), "town")
	assert_eq(reg.tiers.era_for(3), "city")


# AC2: the building keeps working at its old tier while the upgrade runs.
func test_building_keeps_working_at_its_old_tier() -> void:
	var forager := _strip_building("forager", 4)
	var tent := _strip_building("tent", 8)
	var beds := s.beds_total()
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	var made_before := ps.produced_total
	assert_true(s.upgrade(forager.id))
	assert_true(s.upgrade(tent.id))
	assert_false(forager.site, "an upgrading building is not a site")
	assert_false(tent.site)
	assert_eq(forager.tier, 1)
	assert_eq(tent.tier, 1)
	assert_eq(s.beds_total(), beds, "beds stay at the old tier until the work is done")
	# No goods for the works yet: haulers cannot deliver, so builders never start and both keep running.
	s.step_days(2)
	assert_true(forager.upgrading() and tent.upgrading())
	assert_eq(forager.tier, 1)
	assert_eq(tent.tier, 1)
	assert_eq(forager.effective_worker_slots(reg), 2, "worker slots at the old tier")
	assert_gt(ps.produced_total, made_before, "the forager kept producing at tier I")
	assert_eq(s.beds_total(), beds)
	assert_true(s.can_upgrade(forager.id)["reason"] == "in_progress")
	# Deliver the costs: the works finish and the tiers move up.
	s.hearth.inventory.add("planks", 100.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	for i in 8 * 24:
		if not forager.upgrading() and not tent.upgrading():
			break
		s.step_hours(1)
	assert_false(forager.upgrading(), "the forager upgrade finished")
	assert_false(tent.upgrading(), "the tent upgrade finished")
	assert_eq(forager.tier, 2)
	assert_eq(tent.tier, 2)
	assert_null(forager.upgrade_buffer)
	assert_eq(tent.effective_beds(reg), 4, "Tent II is the Hut: 4 beds")
	assert_eq(s.beds_total(), beds + 1)
	assert_eq(s.events.log_of("building_upgraded").size(), 2)


# Pending-upgrade state is part of a save (reflective compare in test_save walks these fields).
func test_pending_upgrade_round_trips_through_a_save() -> void:
	var forager := _strip_building("forager", 4)
	s.hearth.inventory.add("planks", 1.0)
	s.hearth.inventory.add("cut_stone", 1.0)
	assert_true(s.upgrade(forager.id))
	s.step_hours(36)  # haulers deliver part of the tier II cost
	assert_true(forager.upgrading())
	assert_gt(forager.upgrade_buffer.amount_of("planks"), 0.0)
	assert_eq(SaveGame.save(s, SAVE_PATH), OK)
	var loaded := SaveGame.load(SAVE_PATH, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	var b: Building = loaded.buildings[forager.id]
	assert_eq(b.upgrade_tier, 2)
	assert_eq(b.upgrade_cost, forager.upgrade_cost)
	assert_eq(b.upgrade_work, forager.upgrade_work)
	assert_eq(b.upgrade_work_needed, forager.upgrade_work_needed)
	assert_eq(b.upgrade_buffer.to_dict(), forager.upgrade_buffer.to_dict())
	assert_false(b.site)


func test_demolish_mid_upgrade_refunds_delivered_upgrade_goods() -> void:
	var forager := _strip_building("forager", 4)
	assert_true(s.upgrade(forager.id))
	for g in forager.upgrade_cost:
		forager.upgrade_buffer.add(g, float(forager.upgrade_cost[g]))
	var share := reg.logistics.demolish_refund
	var refund := s._refund_for(forager)
	for g in forager.upgrade_cost:
		var base := float(forager.def.cost.get(g, 0.0)) * share
		assert_almost_eq(float(refund.get(g, 0.0)), base + float(forager.upgrade_cost[g]) * share, 0.001,
				"%s delivered for the upgrade comes back at the refund share" % g)
