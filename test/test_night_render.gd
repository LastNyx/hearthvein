extends GutTest
## Ticket 135: the night render model (light pools, lit windows) and the HUD layer staying out of the night tint.

const SEED := 42

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the render model, not the small-town rule, is under test


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


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
	var why := s.can_place(id, at, true)
	var bid := s.place_building_instant(id, at)
	assert_true(bid >= 0, "%s placed at %s: %s" % [id, at, why])
	return s.buildings.get(bid)


## Steps the clock to the next occurrence of `hour` (0-23), wrapping over midnight.
func _step_to(s: Settlement, hour: int) -> void:
	s.step_hours(posmod(hour - s.clock.hour(), 24))


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Criterion 1: the render model lists a pool for every fuelled, lit lamp only, with the lamp's radius.
func test_pools_only_for_fuelled_lamps_with_radius() -> void:
	var s := _new_settlement()
	var fuelled := _put(s, "lamp", 5, 1)
	fuelled.input_buffer.add("wood", 2.0)
	var empty := _put(s, "lamp", 12, 1)  # no fuel
	_put(s, "cottage", 7)  # a building, not a lamp
	s.hearth.inventory.remove("wood", 1000.0)  # no hauler can refuel the empty lamp
	_step_to(s, 18)
	assert_eq(NightRenderModel.pools(s), [] as Array[Dictionary], "no pools before dusk")
	_step_to(s, 19)
	var pools := NightRenderModel.pools(s)
	assert_eq(pools.size(), 1, "one pool: the fuelled lamp only")
	assert_eq(int(pools[0]["id"]), fuelled.id, "the pool names its lamp")
	assert_eq(int(pools[0]["radius"]), 3, "the radius comes from the lamp tier (the Brazier lights 3)")
	assert_ne(int(pools[0]["id"]), empty.id, "an unfuelled lamp shows no pool")


## Criterion 1: windows go to lit homes and working buildings only, never to a dark home or a lit idle building.
func test_windows_only_for_lit_homes_and_working_buildings() -> void:
	var s := _new_settlement()
	var home := _put(s, "cottage", 2)  # in the first lamp's light
	var dark_home := _put(s, "cottage", 8)  # between the two pools, in the dark
	var store := _put(s, "storehouse", 5)  # lit, but a storehouse is neither a home nor staffed
	var mill := _put(s, "sawmill", 10)  # in the second lamp's light, with a night worker
	mill.input_buffer.add("wood", 20.0)
	var first := _put(s, "lamp", 4, 1)
	var second := _put(s, "lamp", 12, 1)
	for lamp in [first, second]:
		lamp.input_buffer.add("wood", 3.0)
	s.hearth.inventory.remove("wood", 1000.0)
	_keep_citizens(s, 8)
	_step_to(s, 18)
	assert_eq(NightRenderModel.windows(s), [] as Array[Dictionary], "no windows by day")
	_step_to(s, 19)
	_step_to(s, 22)  # the night shift: the mill's worker reaches its door
	var ids: Array = NightRenderModel.windows(s).map(func(e: Dictionary) -> int: return int(e["id"]))
	ids.sort()
	assert_true(s.is_lit(home), "the first lamp lights the near home")
	assert_false(s.is_lit(dark_home), "the home between the pools stays dark")
	assert_true(s.is_lit(store), "the storehouse is inside a pool")
	assert_eq(ids, [home.id, mill.id], "windows on the lit home and the working mill only, never the storehouse")


## Criterion 2: the night tint is a world CanvasModulate on the map's canvas layer; the HUD is its own CanvasLayer
## above it and the night render sits in the map, never in the HUD.
func test_the_hud_layer_is_not_tinted_at_night() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	var tmp := OS.get_environment("TMPDIR")
	main.settings_path = (tmp if tmp != "" else "/tmp").path_join("hearthvein_night135_%d.cfg" % OS.get_process_id())
	main.saves_dir = main.settings_path + ".saves"
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(SEED)
	await wait_process_frames(2)
	var tint := main.dim_tint as CanvasModulate
	assert_not_null(tint, "the world tint is a CanvasModulate")
	assert_eq(tint.get_parent(), main, "the tint is a plain world node: it darkens canvas layer 0")
	var hud := main.get_node("Hud") as CanvasLayer
	assert_not_null(hud, "the HUD is a CanvasLayer")
	assert_ne(hud.layer, 0, "the HUD sits on its own canvas layer, out of the CanvasModulate's reach")
	assert_ne(hud.get_parent(), tint, "the tint never wraps the HUD")
	main.settlement.clock.total_hours = 22
	main._update_tint()
	assert_eq(tint.color, reg.day_night.night_color, "22:00 darkens the map with the night colour")
	var night := main.map_view.fx.get_node_or_null("NightView") as Node2D
	assert_not_null(night, "the light pools and lit windows draw in the map")
	assert_false(hud.is_ancestor_of(night), "the night render is not part of the HUD")
	DirAccess.remove_absolute(main.settings_path)
