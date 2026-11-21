extends GutTest
## Ticket 134: Charcoal Kiln and Glowcap Grove (night-only buildings).
##
## The Kiln burns wood into charcoal only at night, with a night worker and lit; by day it makes nothing. The Grove
## needs shade (two forest tiles within two tiles) and makes food at night. Both stand in the build grid under their
## categories with their cards.

const SEED := 42

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the night fill, not the small-town first-hand rule, is under test


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


## A fresh settlement with the growth system off and a road strip east of the Hearth with clear land north of it.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 20):
		for y in range(hs.y - 3, hs.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places a building on the north side of the road strip, `dx` tiles east of the Hearth, and returns it.
func _put(s: Settlement, id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var hs := s.map.hearth_spot
	var bid := s.place_building_instant(id, Vector2i(hs.x + dx, hs.y - def.size.y))
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings.get(bid)


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Citizens in a `kind` job at `b`, split by shift.
func _staff(s: Settlement, b: Building, kind: String, night: bool) -> Array:
	var out: Array = []
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == kind and (c.shift == "night") == night:
			out.append(c)
	return out


## Criterion 1: the Kiln makes charcoal at night with its night workers and nothing by day.
func test_kiln_makes_charcoal_only_at_night() -> void:
	var s := _new_settlement()
	var kiln := _put(s, "charcoal_kiln", 4)
	assert_true(kiln.def.night_only, "the Kiln is a night-only building")
	_keep_citizens(s, 4)  # two Hearth day haulers, then the Kiln's two night slots
	s.refresh_population()
	assert_eq(_staff(s, kiln, Citizen.JOB_WORK, false).size(), 0, "no day slots in a night-only building")
	assert_eq(_staff(s, kiln, Citizen.JOB_WORK, true).size(), 2, "two night slots")
	(kiln.input_buffer as Inventory).add("wood", 40.0)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	s.step_hours(21)
	assert_true(s.is_night(), "21:00 is the night shift")
	assert_true(ws.is_at_work((_staff(s, kiln, Citizen.JOB_WORK, true)[0] as Citizen).id), "a night worker is at the door")
	var made_total := (s.get_system(ProductionSystem) as ProductionSystem).produced_total
	s.step_hours(6)  # 21:00 -> 03:00, inside the night shift
	# 2 workers for 6 h of a 12 h work day at the night rate (4 wood -> 2 charcoal): 2 * 6/12 * 2 = 2 charcoal.
	var at_dawn := (s.get_system(ProductionSystem) as ProductionSystem).produced_total
	assert_almost_eq(at_dawn - made_total, 2.0, 0.02, "the Kiln made charcoal at night")
	s.step_hours(4)  # 03:00 -> 07:00, the rest of the night
	var at_day := (s.get_system(ProductionSystem) as ProductionSystem).produced_total
	s.step_hours(12)  # 07:00 -> 19:00, the whole day
	assert_almost_eq((s.get_system(ProductionSystem) as ProductionSystem).produced_total, at_day, 0.001,
			"nothing by day")


## Criterion 2: the Grove needs two forest tiles within two tiles (refused with the reason on open grass) and makes
## food at night.
func test_grove_needs_shade_and_makes_food_at_night() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var origin := Vector2i(hs.x + 8, hs.y - 2)
	for y in range(origin.y - 2, origin.y + 4):
		for x in range(origin.x - 2, origin.x + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")  # open grass: no shade at all
	var open := s.can_place("glowcap_grove", origin, true)
	assert_false(open["ok"], "open grass has no shade")
	assert_eq(open["reason"], "needs_shade", "the refusal says shade")
	s.set_terrain(Vector2i(origin.x - 1, origin.y), "forest")
	s.set_terrain(Vector2i(origin.x - 1, origin.y + 1), "forest")  # two forest tiles within 2
	assert_true(s.can_place("glowcap_grove", origin, true)["ok"], "two forest tiles within 2 tiles are shade")
	var grove := _put(s, "glowcap_grove", 8)
	_keep_citizens(s, 4)
	s.refresh_population()
	assert_eq(_staff(s, grove, Citizen.JOB_WORK, true).size(), 2, "two night slots")
	s.step_hours(21)
	var made_total := (s.get_system(ProductionSystem) as ProductionSystem).produced_total
	s.step_hours(6)  # 21:00 -> 03:00
	# 2 workers for 6 h of a 12 h work day at 5 food per worker: 2 * 6/12 * 5 = 5 food.
	assert_almost_eq((s.get_system(ProductionSystem) as ProductionSystem).produced_total - made_total, 5.0, 0.02,
			"the Grove made food at night")


## Criterion 3: both stand in the build grid under their categories with their cards.
func test_both_are_in_the_build_grid_with_cards() -> void:
	var hud := await _hud("village")
	var kiln := _entry(hud, "refining", "charcoal_kiln")
	assert_false(kiln.is_empty(), "the Kiln is under Refining")
	assert_eq(kiln["label"], "Charcoal Kiln")
	assert_eq(_cost(kiln, "wood")["need"], 20)
	var grove := _entry(hud, "food", "glowcap_grove")
	assert_false(grove.is_empty(), "the Grove is under Food")
	assert_eq(grove["label"], "Glowcap Grove")
	assert_eq(_cost(grove, "wood")["need"], 14)
	var refining_ids: Array = hud.model.grid("refining").map(func(c: Dictionary) -> String: return str(c["id"]))
	var food_ids: Array = hud.model.grid("food").map(func(c: Dictionary) -> String: return str(c["id"]))
	assert_true(refining_ids.has("charcoal_kiln"), "a Refining grid cell")
	assert_true(food_ids.has("glowcap_grove"), "a Food grid cell")
	hud.open_category("refining")
	await wait_process_frames(2)
	assert_not_null(hud.build_button("charcoal_kiln"), "the Kiln card opens")
	hud.open_category("food")
	await wait_process_frames(2)
	assert_not_null(hud.build_button("glowcap_grove"), "the Grove card opens")


func _hud(era: String) -> Hud:
	var main: Node = load("res://ui/main.tscn").instantiate()
	var tmp := OS.get_environment("TMPDIR")
	main.settings_path = (tmp if tmp != "" else "/tmp").path_join("hearthvein_night134_%d.cfg" % OS.get_process_id())
	main.saves_dir = main.settings_path + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	var s: Settlement = main.settlement
	s.era_override = era
	s.hearth.inventory.add("wood", 100.0)
	s.hearth.inventory.add("stone", 100.0)
	s.hearth.inventory.add("planks", 100.0)
	return main.get_node("Hud")


func _entry(hud: Hud, cat_id: String, id: String) -> Dictionary:
	for cat in hud.model.build_bar():
		if cat["id"] == cat_id:
			for e: Dictionary in cat["entries"]:
				if e["id"] == id:
					return e
	return {}


func _cost(e: Dictionary, good: String) -> Dictionary:
	for c: Dictionary in e.get("costs", []):
		if c["good"] == good:
			return c
	return {}
