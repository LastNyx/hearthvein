extends GutTest
## Ticket 100: the Clear tool. Marked forest, stump and rock tiles are cleared by builders (wood or stone to storage, tile
## becomes grass); marks are refused where they make no sense, wait behind ready sites, and are saved.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket100_save.dat"

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var dir: String
var cfg: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.spirit_override = 50.0  # neutral work speed
	h = s.map.hearth_spot
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	dir = "/tmp/nyx-flash/hearthvein_clear_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)
	DirAccess.remove_absolute(SAVE_DIR.path_join(SAVE_FILE))


## A tile `dx`, `dy` from the Hearth with the given terrain (south of the road for dy > 0).
func _tile(dx: int, dy: int, terrain: String) -> Vector2i:
	var t := Vector2i(h.x + dx, h.y + dy)
	s.set_terrain(t, terrain)
	assert_true(s.map.is_region_owned(s.map.get_region(t.x, t.y)), "the test tile is in an owned region")
	return t


func _cs() -> ConstructionSystem:
	return s.get_system(ConstructionSystem) as ConstructionSystem


## A tile far from every yard (a round trip longer than the work day), all regions owned.
func _far_tile() -> Vector2i:
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var t := Vector2i(h.x + 40 if h.x + 40 < MapState.WIDTH - 4 else h.x - 40, h.y)
	s.set_terrain(t, "forest")
	return t


## Game hours until the tile is no longer marked (-1 when not within `max_days`).
func _hours_until_cleared(t: Vector2i, max_days: int) -> int:
	for i in max_days * 24:
		if not s.is_clear_marked(t):
			return i
		s.step_hours(1)
	return -1


func _to_six() -> void:
	while s.clock.hour() != 6:
		s.step_hours(1)


# ---------------------------------------------------------------- marking

func test_mark_and_unmark_forest_stump_and_rock_and_refuse_the_rest() -> void:
	var f := _tile(4, 1, "forest")
	var st := _tile(5, 1, "stump")
	var r := _tile(6, 1, "rock")
	for t in [f, st, r]:
		assert_true(s.can_mark_clear(t)["ok"])
		assert_true(s.mark_clear(t))
		assert_true(s.is_clear_marked(t))
	assert_false(s.mark_clear(f), "already marked")
	assert_eq(s.can_mark_clear(f)["reason"], "marked")
	assert_true(s.unmark_clear(f))
	assert_false(s.is_clear_marked(f))
	assert_false(s.unmark_clear(f), "nothing left to unmark")
	var grass := _tile(7, 1, "grass")
	assert_false(s.mark_clear(grass))
	assert_eq(s.can_mark_clear(grass)["reason"], "not_clearable")
	var water := _tile(8, 1, "water")
	assert_false(s.mark_clear(water))
	assert_eq(s.can_mark_clear(water)["reason"], "not_clearable")
	assert_false(s.mark_clear(s.hearth.origin), "a building stands there")
	assert_eq(s.can_mark_clear(s.hearth.origin)["reason"], "overlap")
	var road := Vector2i(h.x + 4, h.y)
	assert_false(s.mark_clear(road), "a road is not cleared")
	var locked := Vector2i(-1, -1)
	for r2 in MapState.REGION_COUNT:
		if locked.x < 0 and not s.map.is_region_owned(r2):
			locked = MapState.region_rect(r2).position + Vector2i(3, 3)
	assert_true(locked.x >= 0, "the map has an unowned region")
	s.set_terrain(locked, "forest")
	assert_false(s.mark_clear(locked))
	assert_eq(s.can_mark_clear(locked)["reason"], "locked_region")
	assert_eq(s.clear_marked_tiles().size(), 2, "only the stump and the rock are marked")


# ---------------------------------------------------------------- clearing

func test_a_builder_clears_a_marked_forest_tile_for_wood() -> void:
	var def := reg.get_terrain("forest")
	assert_eq([def.clear_hours, def.clear_good, def.clear_amount], [4.0, "wood", 4.0], "the numbers are data")
	var t := _tile(6, 1, "forest")
	assert_true(s.mark_clear(t))
	var wood := s.hearth.inventory.amount_of("wood")
	_to_six()
	s.step_hours(3)
	assert_true(s.is_clear_marked(t), "4 work hours cannot be done in 3")
	assert_true(_hours_until_cleared(t, 3) >= 0, "a builder clears it")
	assert_eq(s.map.terrain_id_at(t.x, t.y), "grass")
	assert_almost_eq(s.hearth.inventory.amount_of("wood"), wood + 4.0, 0.001, "wood to the nearest storage")
	assert_eq(s.clear_marked_tiles().size(), 0, "the mark is gone")


func test_clearing_rock_gives_stone_and_ends_the_quarry_spot() -> void:
	var def := reg.get_terrain("rock")
	assert_eq([def.clear_hours, def.clear_good, def.clear_amount], [8.0, "stone", 6.0])
	var stump := reg.get_terrain("stump")
	assert_eq([stump.clear_hours, stump.clear_good, stump.clear_amount], [1.0, "wood", 1.0])
	var t := _tile(6, 2, "rock")
	assert_true(s.can_place("quarry", t, true)["ok"], "a quarry fits on rock")
	assert_true(s.mark_clear(t))
	var stone := s.hearth.inventory.amount_of("stone")
	assert_true(_hours_until_cleared(t, 4) >= 0)
	assert_almost_eq(s.hearth.inventory.amount_of("stone"), stone + 6.0, 0.001)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "grass")
	var again := s.can_place("quarry", t, true)
	assert_false(again["ok"], "cleared rock is no quarry spot")
	assert_eq(again["reason"], "needs_rock")


func test_a_ready_site_of_the_same_priority_goes_before_a_clear_job() -> void:
	var crew := reg.logistics.builder_crew
	reg.logistics.builder_crew = 4  # one crew takes all four builders (the data has 2 since 118)
	var t := _tile(8, 1, "forest")
	assert_true(s.mark_clear(t))
	var bid := s.place_building("tent", Vector2i(h.x + 4, h.y - 1))
	assert_true(bid >= 0)
	var site: Building = s.buildings[bid]
	var cost := site.effective_cost()
	for g in cost:
		if g != BuildingDef.GOLD:
			site.input_buffer.add(g, float(cost[g]))
	_to_six()
	var idx := MapState.idx(t.x, t.y)
	for i in 3 * 24:
		if not site.site:
			break
		s.step_hours(1)
	assert_false(site.site, "the site was built")
	assert_true(s.is_clear_marked(t), "the clear job waited")
	assert_lt(float(_cs().clear_marks[idx]), 1.0, "and was barely started when the site finished")
	assert_true(_hours_until_cleared(t, 3) >= 0, "then the builders cleared it")
	reg.logistics.builder_crew = crew


func test_a_mark_no_yard_can_reach_is_flagged_and_left_alone() -> void:
	var model := HudModel.new(s)  # kept in a variable: it listens to the settlement's events
	var t := _far_tile()
	assert_true(s.mark_clear(t))
	s.step_hours(2)
	assert_true(_cs().clear_far.has(MapState.idx(t.x, t.y)), "too far from every yard")
	var tip := model.clear_tooltip(t)
	assert_string_contains(tip["text"], "No Builder's Yard can reach it")
	assert_eq(ConstructionSystem.builders_wanted(s), 0, "nobody is sent")
	s.step_days(2)
	assert_eq(float(_cs().clear_marks[MapState.idx(t.x, t.y)]), 0.0, "no work was done")
	var near := _tile(6, 1, "stump")
	assert_true(s.mark_clear(near))
	assert_string_contains(model.clear_tooltip(near)["text"], "Marked for clearing")
	assert_false((model.clear_tooltip(near)["text"] as String).contains("No Builder's Yard"))
	assert_eq(model.clear_tooltip(Vector2i(h.x + 9, h.y + 3)), {}, "an unmarked tile has none")


# ---------------------------------------------------------------- save

func test_marks_and_their_progress_survive_save_and_load() -> void:
	var near := _tile(6, 2, "rock")
	var far := _far_tile()
	assert_true(s.mark_clear(near))
	assert_true(s.mark_clear(far))
	_to_six()
	s.step_hours(5)  # a builder is on the rock by now
	assert_true(s.is_clear_marked(near))
	var cs := _cs()
	assert_gt(float(cs.clear_marks[MapState.idx(near.x, near.y)]), 0.0, "some work is done")
	assert_true(cs.clear_far.has(MapState.idx(far.x, far.y)))
	var path := SAVE_DIR.path_join(SAVE_FILE)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	var lcs := loaded.get_system(ConstructionSystem) as ConstructionSystem
	assert_eq(lcs.clear_marks, cs.clear_marks)
	assert_eq(lcs.clear_far, cs.clear_far)
	assert_true(loaded.is_clear_marked(near))
	assert_eq(loaded.clear_marked_tiles(), s.clear_marked_tiles())


# ---------------------------------------------------------------- 157: many marks

## Marks the grass tiles in a block east of the Hearth (made forest first), returns the tiles nearest first.
func _mark_block(w: int, hgt: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(h.x + 3, h.x + 3 + w):
		for y in range(h.y + 1, h.y + 1 + hgt):
			var t := Vector2i(x, y)
			s.set_terrain(t, "forest")
			if s.mark_clear(t):
				out.append(t)
	return out


func test_builders_take_the_nearest_marks_first() -> void:
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var near := _tile(4, 1, "forest")
	var mid := _tile(9, 1, "forest")
	var far := _tile(14, 1, "forest")
	for t in [far, mid, near]:  # marked far first: the order of marking does not matter
		assert_true(s.mark_clear(t))
	_to_six()
	var order: Array[Vector2i] = []
	var guard := 0
	while order.size() < 3 and guard < 24 * 6:
		s.step_hours(1)
		guard += 1
		for t in [near, mid, far]:
			if not s.is_clear_marked(t) and not order.has(t):
				order.append(t)
	assert_eq(order, [near, mid, far], "cleared nearest first")


func test_the_clear_job_list_is_cached_and_follows_marks_and_buildings() -> void:
	var tiles := _mark_block(5, 4)
	assert_eq(tiles.size(), 20)
	var list := ConstructionSystem.clear_job_indices(s)
	assert_eq(list.size(), 20)
	assert_same(ConstructionSystem.clear_job_indices(s), list, "no change, same cached list")
	var t: Vector2i = tiles[0]
	assert_true(s.unmark_clear(t))
	assert_eq(ConstructionSystem.clear_job_indices(s).size(), 19)
	assert_false(ConstructionSystem.clear_job_indices(s).has(MapState.idx(t.x, t.y)))
	assert_true(s.mark_clear(t))
	var sorted := ConstructionSystem.clear_job_indices(s).duplicate()
	sorted.sort()
	assert_eq(ConstructionSystem.clear_job_indices(s), sorted, "index order after a re-mark")
	var u: Vector2i = tiles[5]
	s.set_terrain(u, "grass")  # no longer clearable: the list drops it without an unmark
	assert_eq(ConstructionSystem.clear_job_indices(s).size(), 19)


func test_300_marks_and_three_builders_do_not_start_an_astar_storm() -> void:
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var tiles := _mark_block(25, 12)
	assert_gte(tiles.size(), 250, "a big mark set")
	_to_six()
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var before := ws.path_computations
	s.step_hours(1)
	var calls := ws.path_computations - before
	print("CLEAR A* runs in one hour with %d marks: %d" % [tiles.size(), calls])
	assert_lte(calls, 60, "A* runs on a shortlist per builder, not on every mark")


# ---------------------------------------------------------------- UI

func _game() -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42, false, false)
	await wait_process_frames(2)
	return main


func _on(b: Button) -> bool:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).border_color == Hud.GOLD


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func test_clear_tool_is_lit_and_marks_by_click_and_drag_and_x_unmarks() -> void:
	var main: Node = await _game()
	var ms: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var build: BuildController = main.get_node("BuildController")
	var mh := ms.map.hearth_spot
	var row: Array[Vector2i] = []
	for dx in range(3, 8):
		var t := Vector2i(mh.x + dx, mh.y + 6)
		ms.set_terrain(t, "forest")
		row.append(t)
	assert_string_contains(hud._cell_button("clear").tooltip_text, "Clear (Z)")
	assert_string_contains(hud._cell_button("clear").tooltip_text, "quarry")
	assert_false(_on(hud._cell_button("clear")))
	hud._cell_button("clear").pressed.emit()
	assert_eq(build.mode, BuildController.Mode.CLEAR)
	assert_true(_on(hud._cell_button("clear")), "lit while active")
	assert_string_contains(build.hint_text(), "Clear")
	build.cancel()
	assert_false(_on(hud._cell_button("clear")))
	build._unhandled_input(_key(KEY_Z))
	assert_eq(build.mode, BuildController.Mode.CLEAR, "Z is the key")
	build._click(row[0])
	assert_true(ms.is_clear_marked(row[0]))
	build._click(row[0])
	assert_false(ms.is_clear_marked(row[0]), "marking again unmarks")
	build._click(row[0])
	build._paint_to(row[4])
	for t in row:
		assert_true(ms.is_clear_marked(t), "a drag marks every tile it crosses")
	build._painting = false
	build.set_mode(BuildController.Mode.DEMOLISH)
	build._click(row[2])
	assert_false(ms.is_clear_marked(row[2]), "X on a marked tile unmarks it")
	assert_true(ms.is_clear_marked(row[3]))
	assert_false(_on(hud._cell_button("clear")))


func test_hover_over_an_unreachable_mark_says_no_yard_can_reach_it() -> void:
	var main: Node = await _game()
	var ms: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	for r in MapState.REGION_COUNT:
		ms.map.set_region_owned(r, true)
	var mh := ms.map.hearth_spot
	var t := Vector2i(mh.x + 40 if mh.x + 40 < MapState.WIDTH - 4 else mh.x - 40, mh.y)
	ms.set_terrain(t, "forest")
	assert_true(ms.mark_clear(t))
	ms.step_hours(2)
	hud.hover_tick(0.5, t)
	assert_true(hud.tooltip_visible())
	assert_string_contains(hud.tooltip_text(), "No Builder's Yard can reach it")
