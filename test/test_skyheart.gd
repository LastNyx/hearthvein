extends GutTest
## Ticket 45: the Skyheart's four stages (data, order, gold, events) and its grid-fed 3000 L reservoir.

const SEED := 42
const UP_ID := "test_sky_consumer"

var reg: DataRegistry
var s: Settlement
var sys: SkyheartSystem
var gs: GridSystem
var h: Vector2i
var events: Array[Dictionary] = []


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	var u := BuildingDef.new()
	u.id = UP_ID
	u.display_name = "Test sky consumer"
	u.era = "town"
	u.category = "resources"
	u.size = Vector2i(1, 1)
	u.upkeep_lumen = 8.0
	reg.buildings[u.id] = u


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "ascendant"
	sys = s.get_system(SkyheartSystem)
	gs = s.get_system(GridSystem)
	h = s.map.hearth_spot
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	events.clear()
	for kind in ["skyheart_stage", "skyheart_finished"]:
		s.events.subscribe(kind, func(e: Dictionary) -> void: events.append(e))


## Nearest free origin to the Hearth for a def.
func _spot(def_id: String, skip: Array[Vector2i] = []) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(h.y - 14, h.y + 14):
		for x in range(h.x - 14, h.x + 14):
			var o := Vector2i(x, y)
			if skip.has(o) or not s.can_place(def_id, o, true)["ok"]:
				continue
			var d := absi(x - h.x) + absi(y - h.y)
			if d < best_d:
				best_d = d
				best = o
	return best


func _site() -> Building:
	s.gold = 5000.0
	var id := s.place_building("skyheart", _spot("skyheart"))
	assert_true(id >= 0, "placed")
	return s.buildings[id]


## Delivers the current stage's goods and finishes its work.
func _finish_stage(b: Building) -> void:
	var cost := b.effective_cost()
	for g in cost:
		if g != BuildingDef.GOLD:
			b.input_buffer.add(g, float(cost[g]))
	b.build_work = b.build_work_needed
	s.complete_site(b)


func _finished() -> Building:
	var id := s.place_building_instant("skyheart", _spot("skyheart"))
	assert_true(id >= 0, "placed")
	return s.buildings[id]


## A finished Skyheart, a pylon beside it (so the Hearth store is on the grid too). Returns the Skyheart.
func _grid_heart() -> Building:
	var b := _finished()
	var p := s.place_building_instant("lumen_pylon", _spot("lumen_pylon"))
	assert_true(p >= 0, "pylon placed")
	assert_true(GridSystem.on_grid(s, b), "skyheart on the grid")
	assert_true(GridSystem.on_grid(s, s.hearth), "hearth on the grid")
	return b


func _hours(n: int, lumen_in_hearth: float = -1.0) -> void:
	for i in n:
		if lumen_in_hearth >= 0.0:
			var have := s.hearth.inventory.amount_of("lumen")
			s.hearth.inventory.add("lumen", maxf(0.0, lumen_in_hearth - have))
		sys.on_hour(s)


func test_row_matches_the_design() -> void:
	var d := reg.get_building("skyheart")
	assert_eq(d.era, "ascendant")
	assert_eq(d.category, "landmark")
	assert_eq(d.size, Vector2i(4, 4))
	assert_eq(d.layers, "ground")
	assert_eq(d.worker_slots, 0)
	assert_eq(d.upkeep_lumen, 0.0)
	assert_eq(d.stages.size(), 4)
	assert_eq(d.stages[0]["cost"], {"wood": 320, "stone": 480, "cut_stone": 300})
	assert_eq(d.stages[1]["cost"], {"planks": 300, "tools": 200})
	assert_eq(d.stages[2]["cost"], {"lumen_cells": 400, "lumen": 1000})
	assert_eq(d.stages[3]["cost"], {"gold": 1500, "tools": 200, "lumen_cells": 200})
	assert_eq(d.reservoir_capacity, 3000.0)
	assert_eq(d.reservoir_fill_per_hour, 40.0)


func test_only_one_skyheart_per_map() -> void:
	_site()
	var r := s.can_place("skyheart", _spot("skyheart"), true)
	assert_false(r["ok"])
	assert_eq(r["reason"], "unique")
	assert_eq(s.place_building("skyheart", _spot("skyheart")), -1)
	assert_eq(s.place_building_instant("skyheart", _spot("skyheart")), -1)


func test_stage_one_cost_is_the_site_cost() -> void:
	assert_eq(s.cost_for("skyheart"), {"wood": 320, "stone": 480, "cut_stone": 300})
	var b := _site()
	assert_true(b.site)
	assert_eq(b.stage, 0)
	assert_eq(b.effective_cost(), {"wood": 320, "stone": 480, "cut_stone": 300})
	assert_eq(HaulingSystem.need_of(reg, b), {"wood": 320.0, "stone": 480.0, "cut_stone": 300.0})
	assert_false(b.site_delivered())


func test_stages_open_in_order_with_their_own_cost() -> void:
	var b := _site()
	var want := [{"planks": 300, "tools": 200}, {"lumen_cells": 400, "lumen": 1000}]
	var names := ["Foundation", "Lattice", "Core", "Crown"]
	for i in 3:
		_finish_stage(b)
		assert_true(b.site, "still a site after stage %d" % (i + 1))
		assert_eq(b.stage, i + 1)
		assert_eq(events.size(), i + 1)
		assert_eq(events[i]["data"]["stage"], i + 1)
		assert_eq(events[i]["data"]["name"], names[i])
		assert_eq(b.build_work, 0.0)
		assert_false(b.site_delivered(), "the old stage's goods do not count")
		assert_eq(b.input_buffer.amount_of("wood"), 0.0)
		if i < 2:
			assert_eq(b.effective_cost(), want[i])
	assert_eq(b.effective_cost(), {"gold": 1500, "tools": 200, "lumen_cells": 200})
	assert_eq(HaulingSystem.need_of(reg, b), {"tools": 200.0, "lumen_cells": 200.0}, "gold is not hauled")
	assert_false(events.any(func(e: Dictionary) -> bool: return e["kind"] == "skyheart_finished"))


func test_finished_only_after_stage_four_and_emits_the_event() -> void:
	var b := _site()
	s.gold = 5000.0
	for i in 4:
		assert_true(b.site, "a site until the last stage is done")
		assert_false(s.era_gate().get("landmark_built", false))
		assert_eq(b.stage, i)
		_finish_stage(b)
		sys.on_hour(s)  # pays the Crown's gold
	assert_false(b.site)
	assert_eq(b.stage, 4)
	assert_eq(s.gold, 3500.0, "the Crown's 1500 gold was paid when its stage opened or on the next hour")
	var kinds: Array = events.map(func(e: Dictionary) -> String: return e["kind"])
	assert_eq(kinds.count("skyheart_stage"), 4)
	assert_eq(kinds.count("skyheart_finished"), 1)
	assert_eq(kinds.back(), "skyheart_finished")


func test_crown_gold_waits_for_the_treasury() -> void:
	var b := _site()
	s.gold = 0.0
	_finish_stage(b)
	_finish_stage(b)
	_finish_stage(b)
	assert_eq(b.stage, 3)
	assert_eq(b.gold_due, 1500)
	b.input_buffer.add("tools", 200.0)
	b.input_buffer.add("lumen_cells", 200.0)
	assert_false(b.site_delivered(), "goods are there but the gold is not paid")
	assert_false(ConstructionSystem.is_ready(b))
	s.gold = 1600.0
	sys.on_hour(s)
	assert_eq(b.gold_due, 0)
	assert_eq(s.gold, 100.0)
	assert_true(b.site_delivered())


func test_demolish_refunds_only_the_current_stage() -> void:
	var b := _site()
	_finish_stage(b)
	b.input_buffer.add("planks", 100.0)
	s.gold = 0.0
	var id := b.id
	var mats := float(s.totals().get("wood", 0.0))
	var planks := float(s.totals().get("planks", 0.0))
	assert_true(s.demolish(id))
	# no stage-1 refund: only the 100 planks delivered for stage 2 come back at 50%
	assert_almost_eq(float(s.totals().get("planks", 0.0)) - planks, 50.0, 0.001)
	assert_almost_eq(float(s.totals().get("wood", 0.0)) - mats, 0.0, 0.001)


func test_badge_text_in_the_hud_model() -> void:
	var hud := HudModel.new(s)
	var b := _site()
	hud.select(b.id)
	var lines: Array = hud.selection()["lines"]
	assert_true(lines.has("Stage 1 of 4: Foundation"), str(lines))
	_finish_stage(b)
	lines = hud.selection()["lines"]
	assert_true(lines.has("Stage 2 of 4: Lattice"), str(lines))
	var f := _grid_heart_after(b)
	hud.select(f.id)
	assert_true((hud.selection()["lines"] as Array).has("Reservoir 0 / 3000 L"))
	sys._charge[f.id] = 123.9
	assert_true((hud.selection()["lines"] as Array).has("Reservoir 123 / 3000 L"))


func _grid_heart_after(b: Building) -> Building:
	s.demolish(b.id)
	return _finished()


func test_reservoir_fills_from_grid_surplus_at_forty_an_hour() -> void:
	var b := _grid_heart()
	_hours(1, 150.0)
	assert_almost_eq(sys.reservoir_charge(b.id), 40.0, 0.001)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 110.0, 0.001, "taken out of the hearth store")
	_hours(2, 150.0)
	assert_almost_eq(sys.reservoir_charge(b.id), 120.0, 0.001)
	assert_almost_eq(sys.total_reservoir_charge(), 120.0, 0.001)


func test_reservoir_keeps_one_day_of_upkeep_back() -> void:
	var b := _grid_heart()
	var gid := gs.grid_of(s, b.id)
	var c := s.place_building_instant(UP_ID, _spot(UP_ID))
	assert_true(c >= 0)
	assert_true(gs.grid_of(s, c) >= 0)
	var keep := 8.0 * reg.logistics.grid_upkeep_factor
	assert_almost_eq(SkyheartSystem.daily_need(s, gid), keep, 0.001)
	s.hearth.inventory.add("lumen", 30.0)
	_hours(5)
	assert_almost_eq(sys.reservoir_charge(b.id), 30.0 - keep, 0.001)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), keep, 0.001, "one day of upkeep stays")
	var c2: Building = s.buildings[c]
	c2.paused = true  # a paused consumer needs nothing, so the keep-back drops
	_hours(1)
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 0.0, 0.001)


func test_reservoir_stops_at_capacity_and_is_not_supply() -> void:
	var b := _grid_heart()
	var gid := gs.grid_of(s, b.id)
	_hours(80, 150.0)
	assert_almost_eq(sys.reservoir_charge(b.id), 3000.0, 0.001)
	var before := s.hearth.inventory.amount_of("lumen")
	_hours(1, 150.0)
	assert_almost_eq(sys.reservoir_charge(b.id), 3000.0, 0.001, "never past 3000")
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), 150.0, 0.001, "nothing taken when full")
	assert_almost_eq(gs.supply(s, gid), 150.0, 0.001, "the reservoir is not supply")
	assert_almost_eq(gs.battery_charge(s, gid), 0.0, 0.001, "nor battery charge")
	assert_almost_eq(gs.total_charge(), 0.0, 0.001)
	assert_gt(before, -1.0)


func test_reservoir_loses_nothing_with_no_draw() -> void:
	var b := _grid_heart()
	_hours(3, 150.0)
	s.hearth.inventory.remove("lumen", s.hearth.inventory.amount_of("lumen"))
	var held := sys.reservoir_charge(b.id)
	assert_almost_eq(held, 120.0, 0.001)
	s.step_days(10)
	assert_almost_eq(sys.reservoir_charge(b.id), held, 0.0001, "no decay")
	for i in 24 * 20:
		sys.on_hour(s)
	assert_almost_eq(sys.reservoir_charge(b.id), held, 0.0001)


func test_paused_or_off_grid_skyheart_does_not_fill() -> void:
	var b := _finished()
	s.hearth.inventory.add("lumen", 100.0)
	_hours(3)
	assert_eq(sys.reservoir_charge(b.id), 0.0, "off the grid")
	var p := s.place_building_instant("lumen_pylon", _spot("lumen_pylon"))
	assert_true(p >= 0)
	assert_true(GridSystem.on_grid(s, b))
	b.paused = true
	_hours(3, 150.0)
	assert_eq(sys.reservoir_charge(b.id), 0.0, "paused")
	b.paused = false
	_hours(1, 150.0)
	assert_almost_eq(sys.reservoir_charge(b.id), 40.0, 0.001)


func test_a_site_does_not_fill() -> void:
	var b := _site()
	s.place_building_instant("lumen_pylon", _spot("lumen_pylon"))
	_hours(3, 150.0)
	assert_eq(sys.reservoir_charge(b.id), 0.0)


func test_save_round_trip_mid_way() -> void:
	var b := _site()
	_finish_stage(b)
	_finish_stage(b)
	b.input_buffer.add("lumen_cells", 123.0)
	var r := Settlement.from_dict(s.to_dict(), reg)
	var rb: Building = r.buildings[b.id]
	assert_true(rb.site)
	assert_eq(rb.stage, 2)
	assert_eq(rb.effective_cost(), {"lumen_cells": 400, "lumen": 1000})
	assert_eq(rb.input_buffer.amount_of("lumen_cells"), 123.0)
	# a finished one with charge
	r.demolish(rb.id)
	var fid := r.place_building_instant("skyheart", rb.origin)
	assert_true(fid >= 0)
	(r.get_system(SkyheartSystem) as SkyheartSystem)._charge[fid] = 777.5
	var r2 := Settlement.from_dict(r.to_dict(), reg)
	var r2b: Building = r2.buildings[fid]
	assert_false(r2b.site)
	assert_eq(r2b.stage, 4, "an instant placement is past every stage")
	assert_almost_eq((r2.get_system(SkyheartSystem) as SkyheartSystem).reservoir_charge(fid), 777.5, 0.001)
