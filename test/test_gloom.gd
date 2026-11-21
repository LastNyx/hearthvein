extends GutTest
## Ticket 149: gloom on unlit tiles in a Dimming night (spec .scratch/v1/night-shift-spec.md N8).
##
## Gloom starts on forest tiles and creeps one tile an hour over unlit, non-water land in a Dimming night. Lit tiles
## (a fuelled lamp, the Night Watch route) never take it and are cleared when they light; dawn clears it all; a
## building whose footprint holds a gloom tile stops with its reason in the panel. No gloom outside a Dimming.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket149.dat"
## Generous cap for eight spread hours: a frontier spread costs microseconds, a full-map scan per hour does not.
const SPREAD_BUDGET_MS := 100.0

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func after_each() -> void:
	DirAccess.remove_absolute(_save_path())


func _save_path() -> String:
	return SAVE_DIR.path_join(SAVE_FILE)


func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	return s


## Levels the whole starting region to grass and returns an anchor near the corner farthest from the Hearth, so no
## existing forest creeps into the test tiles for the first hours and every test building can be placed.
func _open_ground(s: Settlement) -> Vector2i:
	var h := s.map.hearth_spot
	var r := MapState.region_rect(s.map.get_region(h.x, h.y))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			s.set_terrain(Vector2i(x, y), "grass")
	var mid := r.position + r.size / 2
	var x := r.end.x - 10 if h.x < mid.x else r.position.x + 2
	var y := r.end.y - 8 if h.y < mid.y else r.position.y + 2
	return Vector2i(x, y)


## Places a finished building and returns it.
func _put(s: Settlement, id: String, at: Vector2i) -> Building:
	var bid := s.place_building_instant(id, at)
	assert_true(bid >= 0, "%s placed at %s" % [id, at])
	return s.buildings.get(bid)


## A regular Dimming that is on now (the fixture other Dimming tests use; no forecast needs stepping).
func _dimming(s: Settlement) -> DimmingSystem:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	d._start_day = s.clock.total_days()
	d._length = 5
	d._active = true
	return d


## Criterion 1: gloom spreads one tile an hour from the forest edge, never enters a lit tile or water, and clears at
## dawn and when a tile lights.
func test_gloom_spreads_from_the_forest_edge_stops_at_light_and_clears() -> void:
	var s := _new_settlement()
	var a := _open_ground(s)
	var forest := a + Vector2i(4, 2)
	s.set_terrain(forest, "forest")
	var water := a + Vector2i(4, 4)
	s.set_terrain(water, "water")
	var lamp := _put(s, "lamp", a + Vector2i(0, 2))
	lamp.input_buffer.add("wood", 1.0)
	s.hearth.inventory.remove("wood", 10000.0)
	var g := s.get_system(GloomSystem) as GloomSystem
	var lit_shield := a + Vector2i(3, 2)  # the last tile inside the lamp's radius next to the forest

	s.clock.total_hours = 15
	_dimming(s)
	s.step_hours(1)  # 16: the Dimming dusk
	assert_true(GloomSystem.is_gloom(s, forest), "the forest tile is gloom at night")
	assert_true(GloomSystem.is_gloom(s, a + Vector2i(5, 2)), "16: the first ring east is gloom")
	assert_true(GloomSystem.is_gloom(s, a + Vector2i(4, 1)), "16: gloom spreads on every side")
	assert_true(s.is_tile_lit(lit_shield), "the fuelled lamp lights the tile beside the forest")
	assert_false(GloomSystem.is_gloom(s, lit_shield), "gloom never enters a lit tile")
	assert_false(GloomSystem.is_gloom(s, water), "water is never gloom")

	s.step_hours(1)  # 17
	assert_true(GloomSystem.is_gloom(s, a + Vector2i(6, 2)), "17: one more tile")
	assert_false(GloomSystem.is_gloom(s, water), "17: the front reaches the water tile and stops")

	s.step_hours(1)  # 18
	var front := a + Vector2i(7, 2)
	assert_true(GloomSystem.is_gloom(s, front), "18: three tiles out")
	assert_false(GloomSystem.is_gloom(s, lit_shield), "the lit tile is still clear")

	# Lighting a tile that is already in gloom clears it (the lamp is made lit mid-night, as at dusk).
	var late := _put(s, "lamp", front)
	late.lit_tonight = true
	s.light_version += 1
	s.step_hours(1)  # 19
	assert_true(s.is_tile_lit(front), "the new lamp lights the tile")
	assert_false(GloomSystem.is_gloom(s, front), "lighting a tile clears its gloom")

	# Dawn (09:00 in a Dimming) clears whatever is left, not two hours earlier.
	s.step_hours(13)  # 19 -> 08
	assert_eq(s.clock.hour(), 8)
	assert_false(g.tiles.is_empty(), "the gloom is still there at 08:00")
	s.step_hours(1)
	assert_eq(s.clock.hour(), 9, "dawn")
	assert_true(g.tiles.is_empty(), "all gloom clears at 09:00")


## Criterion 2: a building with a footprint tile in gloom stops with the panel reason, and no Dimming means no gloom.
func test_a_building_in_gloom_stops_with_the_reason_and_no_dimming_has_no_gloom() -> void:
	var s := _new_settlement()
	var a := _open_ground(s)
	s.set_terrain(a + Vector2i(4, 2), "forest")
	var forager := _put(s, "forager", a + Vector2i(5, 2))
	var g := s.get_system(GloomSystem) as GloomSystem

	s.clock.total_hours = 18
	s.step_hours(1)  # 19, no Dimming
	assert_true(g.tiles.is_empty(), "outside a Dimming no gloom")
	assert_false(GloomSystem.is_gloom(s, forager.origin), "no gloom on the building")
	assert_ne(forager.halt, "gloom", "the building is not stopped by gloom")

	_dimming(s)
	s.step_hours(2)  # 19 -> 21: the 19:00 spread reaches the forager, the 20:00 work tick stops it
	assert_true(GloomSystem.is_gloom(s, forager.origin), "the building's tile is in gloom")
	assert_eq(forager.halt, "gloom", "a building with a footprint tile in gloom stops")
	var hm := HudModel.new(s)
	assert_eq(hm.halt_text(forager), "Stopped: in gloom - light it", "the panel says why and how to fix it")

	# A Dimming that ends mid-night takes the gloom with it.
	(s.get_system(DimmingSystem) as DimmingSystem)._active = false
	s.step_hours(1)  # 22
	assert_true(g.tiles.is_empty(), "no Dimming, no gloom")
	assert_false(GloomSystem.is_gloom(s, forager.origin), "the building is out of gloom")


## Criterion 3: the gloom tiles survive a save/load, and a spread hour stays cheap (a frontier set, not a map scan).
func test_gloom_saves_and_loads_and_spread_stays_cheap() -> void:
	var s := _new_settlement()
	var a := _open_ground(s)
	var forest := a + Vector2i(4, 2)
	s.set_terrain(forest, "forest")
	s.set_terrain(a + Vector2i(10, 8), "forest")
	var g := s.get_system(GloomSystem) as GloomSystem

	s.clock.total_hours = 18
	_dimming(s)
	s.step_hours(3)  # 21: a few rings
	assert_gt(g.tiles.size(), 4, "gloom has spread before the save")

	var err := SaveGame.save(s, _save_path())
	assert_eq(err, OK, "the save is written")
	var loaded := SaveGame.load(_save_path(), reg)
	assert_not_null(loaded, "the save loads")
	var lg := loaded.get_system(GloomSystem) as GloomSystem
	assert_eq(lg.tiles, g.tiles, "the loaded gloom tiles and depths match the saved ones")
	assert_true(GloomSystem.is_gloom(loaded, forest), "a known tile is still gloom after the load")

	# Eight spread hours, timed on the live settlement: the front only, never a scan of the whole map. The first hour
	# is outside the timer so the walker grid (built on the first gloom push) is not counted as spread cost.
	s.clock.total_hours += 1
	g.on_hour(s)
	var t0 := Time.get_ticks_usec()
	for i in 8:
		s.clock.total_hours += 1  # stay inside the same Dimming night (no day hook runs)
		g.on_hour(s)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("PERF gloom: 8 spread hours in %.2f ms" % ms)
	assert_lt(ms, SPREAD_BUDGET_MS, "eight spread hours stay within %.0f ms" % SPREAD_BUDGET_MS)
