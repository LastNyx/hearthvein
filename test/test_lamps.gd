extends GutTest
## Ticket 133: lamps I-IV, the charcoal good and the lit rule (spec .scratch/v1/night-shift-spec.md N2).
##
## One lamp def upgrades by era (Brazier, Lantern Post, Lumen Lamp, Grid Lamp); a lamp burns its fuel at dusk (19) and
## lights its radius until dawn (07); a night-shift building works only inside that light.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket133.dat"

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # slot order is what these tests check, not the small-town first-hand rule


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop
	DirAccess.remove_absolute(_save_path())


## A fresh settlement with the growth system off and a road strip east of the Hearth with clear land around it.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 24):
		for y in range(hs.y - 4, hs.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places a finished building on the north side of the road strip `dx` tiles east of the Hearth (or `dy` tiles south).
func _put(s: Settlement, id: String, dx: int, dy: int = 0) -> Building:
	var def := reg.get_building(id)
	var hs := s.map.hearth_spot
	var at := Vector2i(hs.x + dx, hs.y - def.size.y) if dy == 0 else Vector2i(hs.x + dx, hs.y + dy)
	var bid := s.place_building_instant(id, at)
	assert_true(bid >= 0, "%s placed at %s" % [id, at])
	return s.buildings.get(bid)


## Steps the clock to the next occurrence of `hour` (0-23), wrapping over midnight.
func _step_to(s: Settlement, hour: int) -> void:
	s.step_hours(posmod(hour - s.clock.hour(), 24))


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Citizens in a `kind` job at `b` on the given shift.
func _staff(s: Settlement, b: Building, kind: String, night: bool) -> Array:
	var out: Array = []
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == kind and (c.shift == "night") == night:
			out.append(c)
	return out


func _save_path() -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	return SAVE_DIR.path_join(SAVE_FILE)


## Criterion 1: one lamp def, its tiers by era, radius and fuel, all from data.
func test_lamp_tiers_by_era_radius_and_fuel() -> void:
	var def := reg.get_building("lamp")
	assert_not_null(def, "the lamp def exists")
	assert_eq([def.size, def.era, def.category], [Vector2i(1, 1), "camp", "civic"])
	assert_true(bool(def.get("lamp")), "the def is a lamp")
	assert_eq([def.get("lamp_radius"), def.get("lamp_fuel"), float(def.get("lamp_fuel_per_night"))],
			[3, "wood", 1.0], "tier I Brazier: radius 3, wood, 1 a night")
	assert_eq(def.tiers.size(), 3, "tiers II, III and IV live on the one lamp def")
	var want := [
		["Lantern Post", "village", 5, "charcoal", false],
		["Lumen Lamp", "town", 7, "lumen", false],
		["Grid Lamp", "city", 9, "lumen", true],
	]
	for i in 3:
		var td: TierDef = def.tiers[i]
		assert_eq([td.display_name, td.get("era"), td.get("lamp_radius"), td.get("lamp_fuel"),
				bool(td.get("lamp_grid"))], want[i])
		# Ticket 138: priced against the leaner economy: Lantern Post 2 charcoal, Lumen Lamp 3 Lumen, Grid Lamp 1 from the grid.
		assert_almost_eq(float(td.get("lamp_fuel_per_night")), [2.0, 3.0, 1.0][i], 0.001, "fuel a night at tier %d" % (i + 2))
	# The tier's era gates the upgrade in play.
	var s := _new_settlement()
	var lamp := _put(s, "lamp", 4)
	s.era_override = "camp"
	assert_eq(s.can_upgrade(lamp.id)["reason"], "era_locked", "tier II needs the Village era")
	s.era_override = "village"
	assert_true(s.can_upgrade(lamp.id)["ok"], "tier II opens in the Village")
	lamp.tier = 2
	s.era_override = "village"
	assert_eq(s.can_upgrade(lamp.id)["reason"], "era_locked", "tier III needs the Town era")
	s.era_override = "town"
	assert_true(s.can_upgrade(lamp.id)["ok"], "tier III opens in the Town")
	lamp.tier = 3
	assert_eq(s.can_upgrade(lamp.id)["reason"], "era_locked", "tier IV needs the City era")
	s.era_override = "city"
	assert_true(s.can_upgrade(lamp.id)["ok"], "tier IV opens in the City")


## Criterion 2: a fuelled lamp lights its radius 19-07, an unfuelled one is dark, and the cache follows build and
## demolish.
func test_fuelled_lamp_lights_its_radius_from_dusk_to_dawn() -> void:
	var s := _new_settlement()
	var mill := _put(s, "sawmill", 4)
	var far := _put(s, "sawmill", 14)
	var lamp := _put(s, "lamp", 5, 1)
	lamp.input_buffer.add("wood", 2.0)  # the buffer holds two nights' fuel (input_buffer_days)
	assert_false(s.is_lit(mill), "dark in the day")
	assert_false(s.is_lit(far))
	var far_lamp := _put(s, "lamp", 15, 1)  # built after the first is_lit query: the cache must rebuild
	far_lamp.input_buffer.add("wood", 2.0)
	_step_to(s, 18)
	assert_false(s.is_lit(mill), "still dark at 18:00")
	assert_almost_eq(lamp.input_buffer.amount_of("wood"), 2.0, 0.001, "no fuel burnt before dusk")
	_step_to(s, 19)
	assert_true(s.is_lit(lamp), "lit at 19:00")
	assert_true(s.is_lit(mill), "a building inside the radius is lit")
	assert_true(s.is_lit(far), "the later-built lamp lights its own radius")
	assert_almost_eq(lamp.input_buffer.amount_of("wood"), 1.0, 0.001, "one fuel is burnt at dusk")
	_step_to(s, 7)
	assert_false(s.is_lit(mill), "dark from 07:00")
	# An unfuelled lamp stays dark even at night.
	var mill2 := _put(s, "sawmill", 8)
	_put(s, "lamp", 8, 1)
	_step_to(s, 19)
	assert_true(s.is_lit(mill), "lit the next night")
	assert_false(s.is_lit(mill2), "a lamp with no fuel is dark")
	s.demolish(lamp.id)
	assert_false(s.is_lit(mill), "demolish darkens the radius at once (cache rebuilt)")


## Criterion 3: an unlit Sawmill makes nothing at night and its panel says "Needs a lamp"; a lit one works.
func test_unlit_sawmill_makes_nothing_and_says_needs_a_lamp() -> void:
	var s := _new_settlement()
	var lit := _put(s, "sawmill", 4)
	var dark := _put(s, "sawmill", 10)
	var lamp := _put(s, "lamp", 5, 1)
	lamp.input_buffer.add("wood", 5.0)
	_keep_citizens(s, 7)
	for mill in [lit, dark]:
		(mill.input_buffer as Inventory).add("wood", 20.0)
	_step_to(s, 19)  # dusk: the lit mill's night slot opens, the dark mill's stays closed
	assert_eq(_staff(s, lit, Citizen.JOB_WORK, true).size(), 1, "the lit mill fills its night slot")
	assert_eq(_staff(s, dark, Citizen.JOB_WORK, true).size(), 0, "the dark mill's night slot stays closed")
	_step_to(s, 21)
	assert_eq(lit.halt, "", "the lit mill works")
	assert_eq(dark.halt, "unlit", "the dark mill halts on the unlit rule")
	var hm := HudModel.new(s)  # held for the test: a temporary would be freed while its day hook stays subscribed
	assert_eq(hm.halt_text(dark), "Needs a lamp", "the panel line names the need")
	var lit0: float = lit.door_buffer.amount_of("planks")
	var dark0: float = dark.door_buffer.amount_of("planks")
	s.step_hours(8)  # 21:00 -> 05:00
	assert_almost_eq(lit.door_buffer.amount_of("planks") - lit0, 2.0, 0.02,
			"one night worker at the day rate (3 planks / 12 h)")
	assert_almost_eq(dark.door_buffer.amount_of("planks"), dark0, 0.001, "unlit makes nothing")


## Criterion 4: when the lamp's fuel runs out, the next night's slot closes (the job cache is invalidated at dusk).
func test_running_out_of_fuel_closes_the_next_night_slot() -> void:
	var s := _new_settlement()
	var mill := _put(s, "sawmill", 4)
	var lamp := _put(s, "lamp", 5, 1)
	lamp.input_buffer.add("wood", 1.0)  # exactly one night
	_keep_citizens(s, 5)
	mill.input_buffer.add("wood", 40.0)
	s.hearth.inventory.remove("wood", 1000.0)  # no stock for the haulers to refuel the lamp from
	_step_to(s, 19)
	assert_true(s.is_lit(mill), "the one fuelled night is lit")
	assert_eq(_staff(s, mill, Citizen.JOB_WORK, true).size(), 1, "the night slot is open")
	s.step_hours(2)  # 21:00
	var before: float = mill.door_buffer.amount_of("planks")
	s.step_hours(8)  # -> 05:00
	assert_gt(mill.door_buffer.amount_of("planks") - before, 1.0, "the lit night worked")
	_step_to(s, 19)  # the next dusk: the lamp has no fuel left
	assert_false(s.is_lit(mill), "no fuel: dark")
	assert_eq(_staff(s, mill, Citizen.JOB_WORK, true).size(), 0, "the night slot closed with the light")
	_step_to(s, 21)
	assert_eq(mill.halt, "unlit")
	var dark0: float = mill.door_buffer.amount_of("planks")
	s.step_hours(8)  # -> 05:00
	assert_almost_eq(mill.door_buffer.amount_of("planks"), dark0, 0.001, "the dark night makes nothing")


## Criterion 5: charcoal in the ledger (reason "light") and the Resources page, pinnable, and saved with the lamp fuel.
func test_charcoal_ledger_resources_page_and_save() -> void:
	# The Resources page shows a row for charcoal and its pin puts it on the top bar.
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = SAVE_DIR.path_join("ticket133_ui")
	main.settings_path = SAVE_DIR.path_join("ticket133_ui.cfg")
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	var hm: HudModel = main.hud_model
	assert_true(HudModel.RESOURCES.has("charcoal"), "charcoal is a top-bar good")
	assert_true(hm.can_pin("charcoal"), "charcoal can be pinned")
	var ledger: ResourceLedgerSystem = main.settlement.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	ledger.made_yesterday = {"charcoal": 4.0}
	var hud: Hud = main.get_node("Hud")
	hud.resources_page.open()
	assert_not_null(hud.resources_page.row_node("charcoal"), "the Resources page lists charcoal")
	assert_eq((hud.resources_page.pin_button("charcoal") as Button).disabled, false, "the charcoal row can be pinned")
	(hud.resources_page.pin_button("charcoal") as Button).pressed.emit()
	assert_true(hm.is_pinned("charcoal"))
	assert_true(hm.top_goods().has("charcoal"), "the pin puts it on the top bar")
	DirAccess.remove_absolute(main.settings_path)

	# The ledger records lamp fuel with reason "light"; the save keeps the fuel and the night's lit state.
	var s := _new_settlement()
	var lamp := _put(s, "lamp", 5, 1)
	lamp.tier = 2  # Lantern Post: charcoal
	lamp.input_buffer.add("charcoal", 2.0)  # the buffer is sized for the Brazier's two nights of wood: room for two charcoal
	_step_to(s, 19)
	var sl := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	assert_almost_eq(sl.today("charcoal")["used"], 2.0, 0.001, "two charcoal burnt at dusk")
	assert_true((sl.used_by_today["charcoal"] as Dictionary).has("light"), "the ledger reason is light")
	assert_true(s.is_lit(lamp))
	lamp.input_buffer.add("charcoal", 1.0)  # some fuel left in the buffer to be saved
	var path := _save_path()
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	var kept: Building = loaded.buildings[lamp.id]
	assert_almost_eq(kept.input_buffer.amount_of("charcoal"), 1.0, 0.001, "the remaining fuel is saved")
	assert_true(loaded.is_lit(kept), "the lamp is still lit tonight after a load")


## A hauler brings the lamp its fuel like any other input: a Brazier left alone fills its buffer from the stock.
func test_haulers_deliver_lamp_fuel_and_the_need_follows_the_tier() -> void:
	var s := _new_settlement()
	var lamp := _put(s, "lamp", 5, 1)
	assert_almost_eq(float(HaulingSystem.need_for(reg, lamp).get("wood", 0.0)), 1.0 * reg.logistics.input_buffer_days,
			0.001, "tier I needs a few nights of wood")
	lamp.tier = 2
	var need := HaulingSystem.need_for(reg, lamp)
	assert_false(need.has("wood"), "the Lantern Post burns no wood")
	assert_gt(float(need.get("charcoal", 0.0)), 0.0, "it needs charcoal")
	lamp.tier = 4
	assert_false(HaulingSystem.need_for(reg, lamp).has("lumen"), "the Grid Lamp is never hauled")
	lamp.tier = 1
	s.hearth.inventory.add("wood", 50.0)
	s.step_hours(12)
	assert_gt(lamp.input_buffer.amount_of("wood"), 0.9, "a hauler delivered the fuel")


## The Grid Lamp draws its fuel from the grid at dusk and never from its own buffer.
func test_grid_lamp_burns_grid_lumen() -> void:
	var s := _new_settlement()
	s.era_override = "city"
	var pylon := _put(s, "lumen_pylon", 3)
	var lamp := _put(s, "lamp", 6)
	var mill := _put(s, "sawmill", 8)
	lamp.tier = 4
	assert_true(GridSystem.on_grid(s, lamp))
	assert_not_null(pylon)
	s.hearth.inventory.remove("lumen", 1000.0)  # the start stock would light the lamp
	_step_to(s, 19)
	assert_false(s.is_lit(mill), "no Lumen on the grid: dark")
	s.hearth.inventory.add("lumen", 10.0)
	_step_to(s, 18)
	var before: float = s.hearth.inventory.amount_of("lumen")
	s.step_hours(1)
	assert_true(s.is_lit(mill), "grid Lumen lights the Grid Lamp radius (9)")
	assert_almost_eq(s.hearth.inventory.amount_of("lumen"), before - 1.0, 0.01, "one Lumen drawn from the grid")
	assert_almost_eq(lamp.input_buffer.amount_of("lumen"), 0.0, 0.001, "nothing came through the buffer")
	assert_true(s.is_tile_lit(mill.origin), "the tile query agrees")
	assert_false(s.is_tile_lit(Vector2i(mill.origin.x + 20, mill.origin.y)), "outside the radius is dark")


## Lit homes at night raise Spirit: the factor is light_bonus times the lit share of homes, capped.
func test_lit_homes_give_a_spirit_bonus_at_night() -> void:
	var s := _new_settlement()
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	var home := _put(s, "cottage", 5)
	var lamp := _put(s, "lamp", 5, 1)
	lamp.input_buffer.add("wood", 2.0)
	s.hearth.inventory.remove("wood", 1000.0)  # no stock for the haulers to refuel the lamp from
	assert_eq(sp.factor_value(s, "light"), 0.0, "no bonus in the day")
	_step_to(s, 21)
	assert_true(s.is_lit(home))
	var homes := 0
	var lit := 0
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if not b.site and b.def.housing_beds > 0:
			homes += 1
			lit += 1 if s.is_lit(b) else 0
	var want := minf(reg.spirit.light_bonus * float(lit) / float(homes), reg.spirit.light_bonus_max)
	assert_gt(want, 0.0)
	assert_almost_eq(sp.factor_value(s, "light"), want, 0.001, "lit share of homes x the data bonus")
	assert_true((sp.breakdown(s)["factors"] as Dictionary).has("light"), "the breakdown lists it")
	lamp.input_buffer.remove("wood", 5.0)
	_step_to(s, 7)
	_step_to(s, 21)
	assert_eq(sp.factor_value(s, "light"), 0.0, "a dark night gives nothing")
