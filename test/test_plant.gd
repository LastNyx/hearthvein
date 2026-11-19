extends GutTest
## Ticket 101: the Plant tool and the stump regrowth tooltip. Marked grass is planted by Foresters in reach before any
## other grass; with nothing marked in reach they plant as before; marks no Forester reaches are flagged; marks are
## saved. Hovering a stump says when it regrows or why it will not.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket101_save.dat"

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
	s.era_override = "village"
	s.systems.erase(s.get_system(GrowthSystem))  # nothing eats what the settlement produces
	h = s.map.hearth_spot
	for x in range(h.x + 2, h.x + 17):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	dir = "/tmp/nyx-flash/hearthvein_plant_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	get_tree().paused = false
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)
	DirAccess.remove_absolute(SAVE_DIR.path_join(SAVE_FILE))


func _forester() -> Building:
	for dx in range(3, 17):
		var o := Vector2i(h.x + dx, h.y - 1)
		if not s.can_place("forester", o)["ok"]:
			continue
		var id := s.place_building_instant("forester", o)
		if id < 0:
			continue
		var b: Building = s.buildings[id]
		if b.connected:
			return b
		s.demolish(id)
	return null


## A staffed Forester with plain grass painted over its whole circle (under buildings excepted).
func _staffed_forester() -> Building:
	var b := _forester()
	assert_not_null(b, "a Forester beside the road")
	if b == null:
		return null
	for y in range(b.origin.y - 8, b.origin.y + 9):
		for x in range(b.origin.x - 8, b.origin.x + 9):
			var t := Vector2i(x, y)
			if MapState.in_bounds(x, y) and (t - b.origin).length_squared() <= 64 and s.building_at(t) == null:
				s.set_terrain(t, "grass")
	s.step_hours(1)
	return b


## A grass tile 40 tiles from the Hearth, far from any Forester, all regions owned.
func _far_grass() -> Vector2i:
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var t := Vector2i(h.x + 40 if h.x + 40 < MapState.WIDTH - 4 else h.x - 40, h.y + 3)
	s.set_terrain(t, "grass")
	return t


func _fs() -> ForestSystem:
	return s.get_system(ForestSystem) as ForestSystem


func _forest(t: Vector2i) -> bool:
	return s.map.terrain_id_at(t.x, t.y) == "forest"


# ---------------------------------------------------------------- marking

func test_marks_go_on_plain_grass_only() -> void:
	var g := Vector2i(h.x + 5, h.y + 2)
	s.set_terrain(g, "grass")
	assert_true(s.can_mark_plant(g)["ok"])
	assert_true(s.mark_plant(g))
	assert_true(s.is_plant_marked(g))
	assert_false(s.mark_plant(g), "already marked")
	assert_eq(s.can_mark_plant(g)["reason"], "marked")
	assert_true(s.unmark_plant(g))
	assert_false(s.is_plant_marked(g))
	assert_false(s.unmark_plant(g), "nothing left to unmark")
	for kind in ["forest", "stump", "rock", "water", "fertile_soil"]:
		var t := Vector2i(h.x + 6, h.y + 2)
		s.set_terrain(t, kind)
		assert_false(s.mark_plant(t), kind + " is not plain grass")
		assert_eq(s.can_mark_plant(t)["reason"], "not_plantable")
	var bl := Vector2i(h.x + 7, h.y + 2)
	s.set_terrain(bl, "grass")
	s.set_blighted(bl, true)
	assert_false(s.mark_plant(bl))
	assert_eq(s.can_mark_plant(bl)["reason"], "blighted")
	assert_eq(s.can_mark_plant(s.hearth.origin)["reason"], "overlap")
	assert_eq(s.can_mark_plant(Vector2i(h.x + 4, h.y))["reason"], "road")
	var locked := Vector2i(-1, -1)
	for r in MapState.REGION_COUNT:
		if locked.x < 0 and not s.map.is_region_owned(r):
			locked = MapState.region_rect(r).position + Vector2i(3, 3)
	assert_true(locked.x >= 0, "the map has an unowned region")
	s.set_terrain(locked, "grass")
	assert_eq(s.can_mark_plant(locked)["reason"], "locked_region")
	assert_eq(s.plant_marked_tiles().size(), 0)


func test_a_tile_carries_one_mark_only() -> void:
	var t := Vector2i(h.x + 5, h.y + 2)
	s.set_terrain(t, "stump")
	assert_true(s.mark_clear(t))
	assert_false(s.mark_plant(t), "a clear-marked tile cannot be marked for planting")
	var g := Vector2i(h.x + 6, h.y + 2)
	s.set_terrain(g, "grass")
	assert_true(s.mark_plant(g))
	assert_false(s.mark_clear(g), "a plant-marked tile cannot be marked for clearing")


# ---------------------------------------------------------------- planting

func test_a_forester_plants_marked_tiles_before_any_other_grass() -> void:
	var b := _staffed_forester()
	if b == null:
		return
	var near := b.origin + Vector2i(0, -1)  # the nearest grass (ties go to the lower y): the automatic choice
	var m1 := b.origin + Vector2i(-3, -3)
	var m2 := b.origin + Vector2i(4, -2)
	assert_eq(ForestSystem.plant_tile(s, b), near, "unmarked, it takes the nearest grass")
	assert_true(s.mark_plant(m1) and s.mark_plant(m2))
	assert_eq(ForestSystem.plant_tile(s, b), m1, "marked first, nearest marked first")
	s.step_days(1)
	assert_true(_forest(m1))
	assert_false(_forest(near) or _forest(m2))
	assert_false(s.is_plant_marked(m1), "a planted tile drops its mark")
	s.step_days(1)
	assert_true(_forest(m2), "the second mark is next")
	assert_false(_forest(near))
	assert_eq(s.plant_marked_tiles().size(), 0)
	s.step_days(1)
	assert_true(_forest(near), "no marks left: automatic planting as before")


func test_with_no_marks_in_reach_it_plants_automatically() -> void:
	var b := _staffed_forester()
	if b == null:
		return
	var far := _far_grass()
	assert_true(((far - b.origin).length_squared()) > 25, "the mark is outside the Forester's r5")
	assert_true(s.mark_plant(far))
	var near := b.origin + Vector2i(0, -1)
	s.step_days(1)
	assert_true(_forest(near), "planted as before")
	assert_false(_forest(far))
	assert_true(s.is_plant_marked(far), "the mark waits")


func test_a_blighted_mark_in_reach_is_skipped_until_the_blight_clears() -> void:
	var b := _staffed_forester()
	if b == null:
		return
	var m := b.origin + Vector2i(3, -2)
	assert_true(s.mark_plant(m))
	s.set_blighted(m, true)
	s.step_days(1)
	assert_false(_forest(m))
	assert_true(s.is_plant_marked(m), "the mark stays under blight")
	assert_eq(s.plant_marked_tiles().size(), 1)


func test_a_mark_under_a_new_building_is_dropped() -> void:
	var t := Vector2i(h.x + 4, h.y + 3)
	s.set_terrain(t, "grass")
	assert_true(s.mark_plant(t))
	s.set_terrain(t, "forest")
	s.step_days(1)
	assert_false(s.is_plant_marked(t), "no longer grass")


# ---------------------------------------------------------------- hint and save

func test_marks_no_forester_reaches_are_flagged_and_saved() -> void:
	var model := HudModel.new(s)  # kept in a variable: it listens to the settlement's events
	var far := _far_grass()
	assert_true(s.mark_plant(far))
	assert_true(s.plant_mark_unreached(far), "no Forester at all")
	assert_string_contains(model.plant_tooltip(far)["text"], "No Forester reaches it")
	var b := _staffed_forester()
	if b == null:
		return
	var inside := b.origin + Vector2i(2, 2)
	assert_true(s.mark_plant(inside))
	assert_false(s.plant_mark_unreached(inside))
	assert_false((model.plant_tooltip(inside)["text"] as String).contains("No Forester"))
	assert_string_contains(model.plant_tooltip(inside)["text"], "Marked for planting")
	assert_eq(model.plant_tooltip(Vector2i(h.x + 9, h.y + 3)), {}, "an unmarked tile has none")
	var path := SAVE_DIR.path_join(SAVE_FILE)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.plant_marked_tiles(), s.plant_marked_tiles())
	assert_true(loaded.is_plant_marked(inside))
	assert_true(loaded.plant_mark_unreached(far))


# ---------------------------------------------------------------- stump tooltip

func test_stump_tooltip_counts_days_from_the_real_timer() -> void:
	var model := HudModel.new(s)
	var t := Vector2i(h.x + 5, h.y + 3)
	s.set_terrain(t, "stump")
	assert_string_contains(model.stump_tooltip(t)["text"], "Regrows in about 16 days")
	s.step_days(1)
	assert_string_contains(model.stump_tooltip(t)["text"], "about 15 days")
	s.step_days(14)
	assert_string_contains(model.stump_tooltip(t)["text"], "about 1 day")
	assert_eq(s.map.terrain_id_at(t.x, t.y), "stump", "still a stump with 1 day to go")
	s.step_days(1)
	assert_true(_forest(t), "and forest when the days are up")
	assert_eq(model.stump_tooltip(t), {}, "no tip on forest")


func test_stump_tooltip_knows_the_forester_and_after_one_season() -> void:
	var model := HudModel.new(s)
	var b := _staffed_forester()
	if b == null:
		return
	var near := b.origin + Vector2i(2, 0)
	s.set_terrain(near, "stump")
	var d := int(_fs().regrow_info(s, near)["days"])
	assert_true(d > 0 and d <= 8, "one season inside a staffed Forester's reach")
	s.step_days(d - 1)
	assert_false(_forest(near))
	s.step_days(1)
	assert_true(_forest(near), "regrown exactly when the tooltip said")


func test_stump_tooltip_says_why_it_will_not_regrow() -> void:
	var model := HudModel.new(s)
	var t := Vector2i(h.x + 5, h.y + 3)
	s.set_terrain(t, "stump")
	s.set_blighted(t, true)
	assert_string_contains(model.stump_tooltip(t)["text"], "Won't regrow: blighted")
	s.set_blighted(t, false)
	s.planet_health_override = 40.0
	assert_string_contains(model.stump_tooltip(t)["text"], "Won't regrow: planet health below 60")
	s.step_days(20)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "stump", "and it really does not regrow")
	s.planet_health_override = 90.0
	assert_string_contains(model.stump_tooltip(t)["text"], "Regrows in about")


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


func test_plant_tool_is_lit_and_marks_by_click_and_drag_and_x_unmarks() -> void:
	var main: Node = await _game()
	var ms: Settlement = main.settlement
	var build: BuildController = main.get_node("BuildController")
	var tab: ToolsTab = (main.get_node("Hud") as Hud).tools_tab
	tab.set_open(true)
	var mh := ms.map.hearth_spot
	var row: Array[Vector2i] = []
	for dx in range(3, 8):
		var t := Vector2i(mh.x + dx, mh.y + 6)
		ms.set_terrain(t, "grass")
		row.append(t)
	assert_string_contains(tab.button("plant").tooltip_text, "(N)")
	assert_false(_on(tab.button("plant")))
	tab.button("plant").pressed.emit()
	assert_eq(build.mode, BuildController.Mode.PLANT)
	assert_true(_on(tab.button("plant")), "lit while active")
	assert_string_contains(build.hint_text(), "Plant")
	build.cancel()
	assert_false(_on(tab.button("plant")))
	build._unhandled_input(_key(KEY_N))
	assert_eq(build.mode, BuildController.Mode.PLANT, "N is the key")
	build._click(row[0])
	assert_true(ms.is_plant_marked(row[0]))
	build._click(row[0])
	assert_false(ms.is_plant_marked(row[0]), "marking again unmarks")
	build._click(row[0])
	build._paint_to(row[4])
	for t in row:
		assert_true(ms.is_plant_marked(t), "a drag marks every tile it crosses")
	build._painting = false
	build.set_mode(BuildController.Mode.DEMOLISH)
	build._click(row[2])
	assert_false(ms.is_plant_marked(row[2]), "X on a marked tile unmarks it")
	assert_true(ms.is_plant_marked(row[3]))


func test_hovering_a_stump_shows_its_regrowth_with_no_tool_active() -> void:
	var main: Node = await _game()
	var ms: Settlement = main.settlement
	var hud: Hud = main.get_node("Hud")
	var mh := ms.map.hearth_spot
	var t := Vector2i(mh.x + 4, mh.y + 6)
	ms.set_terrain(t, "stump")
	hud.hover_tick(0.5, t)
	assert_true(hud.tooltip_visible())
	assert_string_contains(hud.tooltip_text(), "Regrows in about")
	ms.set_blighted(t, true)
	hud.hover_tick(0.5, t)
	assert_string_contains(hud.tooltip_text(), "Won't regrow: blighted")
