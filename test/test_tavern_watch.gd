extends GutTest
## Ticket 139: the Tavern and the moon badge (spec .scratch/v1/night-shift-spec.md N11, N12).
##
## The Tavern drinks crops once at the night shift's start while staffed and lit, and cheers the homes inside 4 tiles
## that night. Night buildings (night slots or night only) carry a moon flag on their build card and grid cell; day
## buildings do not.

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


## A fresh settlement with the growth system off and a clear road strip east of the Hearth.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 22):
		for y in range(hs.y - 4, hs.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places `id` with its footprint bottom-left at `origin` and returns the building.
func _put(s: Settlement, id: String, origin: Vector2i) -> Building:
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	return s.buildings.get(bid)


## Steps the clock to `hour` (0-23) the same day or the next one.
func _step_to(s: Settlement, hour: int) -> void:
	s.step_hours(posmod(hour - s.clock.hour(), 24))


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Criterion 1: the Tavern drinks 4 crops at night with its night workers and a lamp, and cheers only the homes in
## its radius that night. Without workers or light it drinks nothing and cheers nobody.
func test_tavern_drinks_crops_at_night_and_cheers_homes_in_radius() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var tavern := _put(s, "tavern", Vector2i(hs.x + 4, hs.y - 1))  # the Hearth is 3 tiles away, inside r4
	var lamp := _put(s, "lamp", Vector2i(hs.x + 4, hs.y + 1))
	lamp.input_buffer.add("wood", 3.0)
	tavern.input_buffer.add("crops", 8.0)  # hauling keeps two nights' drinks (4 x input_buffer_days)
	_keep_citizens(s, 4)
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	assert_eq(tavern.input_buffer.amount_of("crops"), 8.0, "nothing drunk by day")
	assert_eq(sp.factor_value(s, "tavern"), 0.0, "no Spirit bonus by day")
	_step_to(s, 19)  # dusk: the lamp burns its fuel
	assert_true(s.is_lit(tavern), "the lamp lights the Tavern")
	assert_eq(SpiritSystem.night_workers(s, tavern), 2, "two night slots")
	_step_to(s, 21)  # crosses the 20:00 night shift start
	assert_almost_eq(tavern.input_buffer.amount_of("crops"), 4.0, 0.001, "the Tavern drank 4 crops for the night")
	assert_almost_eq(sp.factor_value(s, "tavern"), 5.0, 0.001, "the Hearth inside 4 tiles is cheered")
	# A home outside the radius is not cheered: of two homes, only the covered one counts.
	_put(s, "tent", Vector2i(hs.x + 12, hs.y - 1))
	assert_almost_eq(sp.factor_value(s, "tavern"), 5.0 * 1.0 / 2.0, 0.001,
			"the far home is outside the radius")
	# By day there is no bonus and nothing is drunk.
	_step_to(s, 12)
	assert_false(s.is_night(), "noon")
	assert_eq(sp.factor_value(s, "tavern"), 0.0, "no bonus by day")
	assert_almost_eq(tavern.input_buffer.amount_of("crops"), 4.0, 0.001, "nothing drunk by day")
	# With no workers, the next night drinks nothing and cheers nobody.
	_keep_citizens(s, 0)
	_step_to(s, 21)
	assert_eq(SpiritSystem.night_workers(s, tavern), 0, "no night workers")
	assert_almost_eq(tavern.input_buffer.amount_of("crops"), 4.0, 0.001, "no workers, no drinks")
	assert_eq(sp.factor_value(s, "tavern"), 0.0, "no workers, no Spirit bonus")
	# An unlit Tavern also drinks nothing: the night slots stay closed without a lamp.
	var dark := _new_settlement()
	var dhs := dark.map.hearth_spot
	var dark_tavern := _put(dark, "tavern", Vector2i(dhs.x + 4, dhs.y - 1))
	dark_tavern.input_buffer.add("crops", 8.0)
	_keep_citizens(dark, 4)
	_step_to(dark, 21)
	assert_false(dark.is_lit(dark_tavern), "no lamp, no light")
	assert_almost_eq(dark_tavern.input_buffer.amount_of("crops"), 8.0, 0.001, "an unlit Tavern drinks nothing")
	assert_eq((dark.get_system(SpiritSystem) as SpiritSystem).factor_value(dark, "tavern"), 0.0,
			"an unlit Tavern cheers nobody")


## Criterion 2: build cards and grid cells carry the moon flag exactly for buildings with night slots or night only.
func test_moon_badge_flags_night_buildings_in_grid_and_cards() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_override = "village"
	var m := HudModel.new(s)
	assert_true(_card(m, "civic", "tavern")["night"], "the Tavern card carries the moon")
	assert_true(_card(m, "refining", "charcoal_kiln")["night"], "the Kiln card carries the moon")
	assert_true(_card(m, "logistics", "storehouse")["night"], "the Storehouse card carries the moon for its night haulers")
	assert_false(_card(m, "food", "farm")["night"], "a day building's card has no moon")
	assert_true(_cell(m, "civic", "tavern")["night"], "the Tavern grid cell carries the moon")
	assert_true(_cell(m, "refining", "charcoal_kiln")["night"], "the Kiln grid cell carries the moon")
	assert_false(_cell(m, "food", "farm")["night"], "a day building's grid cell has no moon")
	assert_true(m.detail_for("tavern")["night"], "the Tavern detail card carries the moon")
	assert_false(m.detail_for("farm")["night"], "a day building's detail card has no moon")


func _card(m: HudModel, cat_id: String, id: String) -> Dictionary:
	for cat in m.build_bar():
		if str(cat["id"]) != cat_id:
			continue
		for e: Dictionary in cat["entries"]:
			if str(e["id"]) == id:
				return e
	return {}


func _cell(m: HudModel, cat_id: String, id: String) -> Dictionary:
	for c: Dictionary in m.grid(cat_id):
		if str(c["id"]) == id:
			return c
	return {}
