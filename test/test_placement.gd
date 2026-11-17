extends GutTest

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func _new() -> Settlement:
	return Settlement.new_game(SEED, reg)


## First tile (scan order) in the whole map where pred.call(tile) is true.
func _find(s: Settlement, pred: Callable) -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if pred.call(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _owned(s: Settlement, t: Vector2i) -> bool:
	return s.map.is_region_owned(s.map.get_region(t.x, t.y))


func _is(s: Settlement, t: Vector2i, id: String) -> bool:
	return s.map.terrain_id_at(t.x, t.y) == id


## A free owned grass tile whose 4 neighbours are also free grass, away from the hearth patch, far from veins.
func _free_grass(s: Settlement, skip: int = 0) -> Vector2i:
	var seen := 0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if not _owned(s, t) or not _is(s, t, "grass"):
				continue
			var ok := true
			for dy in range(-1, 3):
				for dx in range(-1, 4):
					var n := t + Vector2i(dx, dy)
					if not MapState.in_bounds(n.x, n.y) or not _is(s, n, "grass") or not _owned(s, n):
						ok = false
			if ok and t.distance_to(Vector2(s.map.hearth_spot)) > 6:
				if seen == skip:
					return t
				seen += 1
	return Vector2i(-1, -1)


func test_new_game_places_hearth_and_a_road() -> void:
	var s := _new()
	assert_not_null(s.hearth)
	assert_eq(s.hearth.origin, s.map.hearth_spot)
	assert_eq(s.building_at(s.map.hearth_spot + Vector2i(1, 1)), s.hearth)
	assert_true(s.road_at(s.map.hearth_spot + Vector2i(2, 0)) == Settlement.ROAD_DIRT)
	assert_true(s.hearth.connected)


func test_lumen_tap_only_on_vein() -> void:
	var s := _new()
	var vein := _find(s, func(t): return _owned(s, t) and _is(s, t, "lumen_vein") and s.can_place("lumen_tap", t)["ok"])
	assert_ne(vein, Vector2i(-1, -1), "an owned vein exists")
	var grass := _free_grass(s)
	var r := s.can_place("lumen_tap", grass)
	assert_false(r["ok"])
	assert_eq(r["reason"], "needs_vein")
	assert_eq(s.place_building_instant("lumen_tap", grass), -1)
	assert_true(s.place_building_instant("lumen_tap", vein) >= 0)


func test_quarry_rule_uses_rock() -> void:
	var s := _new()
	var def := BuildingDef.new()
	def.id = "test_quarry"
	def.placement_rule = "on_rock"
	var rock := _find(s, func(t): return _owned(s, t) and _is(s, t, "rock"))
	assert_ne(rock, Vector2i(-1, -1), "an owned rock tile exists")
	assert_eq(Placement.check_rule(s.map, reg, def, rock), "")
	assert_eq(Placement.check_rule(s.map, reg, def, _free_grass(s)), "needs_rock")


func test_other_rules() -> void:
	var s := _new()
	var def := BuildingDef.new()
	def.size = Vector2i(1, 1)
	def.placement_rule = "shore"
	var shore := _find(s, func(t): return _owned(s, t) and _is(s, t, "grass") and Placement.check_rule(s.map, reg, def, t) == "")
	assert_ne(shore, Vector2i(-1, -1), "shore tile exists")
	assert_eq(Placement.check_rule(s.map, reg, def, _free_grass(s)), "needs_shore")
	def.placement_rule = "wet"
	assert_eq(Placement.check_rule(s.map, reg, def, _free_grass(s)) == "", s.map.is_wet(_free_grass(s).x, _free_grass(s).y))
	def.placement_rule = "near_forest"
	def.placement_radius = 4
	var nf := _find(s, func(t): return _owned(s, t) and _is(s, t, "grass") and Placement.check_rule(s.map, reg, def, t) == "")
	assert_ne(nf, Vector2i(-1, -1))
	# Forager (near_forage r3) is placeable on plain grass.
	assert_true(s.can_place("forager", _free_grass(s))["ok"])


func test_overlap_rejected() -> void:
	var s := _new()
	var t := _free_grass(s)
	assert_true(s.place_building_instant("storehouse", t) >= 0)
	assert_eq(s.can_place("tent", t)["reason"], "overlap")
	assert_eq(s.can_place("tent", t + Vector2i(1, 0))["reason"], "overlap", "second tile of the 2x1")
	assert_eq(s.can_place("tent", s.map.hearth_spot)["reason"], "overlap", "hearth blocks")
	assert_true(s.can_place("tent", t + Vector2i(2, 0))["ok"])
	# Roads block buildings and buildings block roads.
	var rt := t + Vector2i(0, 2)
	assert_true(s.place_road(rt))
	assert_eq(s.can_place("tent", rt)["reason"], "road")
	assert_false(s.place_road(t))


func test_locked_region_and_water_and_bounds_rejected() -> void:
	var s := _new()
	var locked := _find(s, func(t): return not _owned(s, t) and _is(s, t, "grass"))
	assert_eq(s.can_place("tent", locked)["reason"], "locked_region")
	assert_false(s.place_road(locked))
	var water := _find(s, func(t): return _owned(s, t) and _is(s, t, "water"))
	assert_eq(s.can_place("tent", water)["reason"], "water")
	assert_eq(s.can_place("tent", Vector2i(-1, 5))["reason"], "out_of_bounds")
	assert_eq(s.can_place("tent", Vector2i(MapState.WIDTH, 5))["reason"], "out_of_bounds")
	# Region boundary: a 2x1 straddling an owned and a locked region is rejected.
	var edge := _find(s, func(t): return _owned(s, t) and _is(s, t, "grass") and _is(s, t + Vector2i(1, 0), "grass") \
			and MapState.in_bounds(t.x + 1, t.y) and not _owned(s, t + Vector2i(1, 0)))
	if edge.x >= 0:
		assert_eq(s.can_place("storehouse", edge)["reason"], "locked_region")


func test_connection_only_when_road_reaches_hearth() -> void:
	var s := _new()
	var h := s.map.hearth_spot
	# The 7x7 patch around the hearth is plain grass. Tent at (+3,+3); hearth road starts at (+2,0).
	var id := s.place_building_instant("tent", h + Vector2i(3, 3))
	assert_true(id >= 0)
	var b: Building = s.buildings[id]
	assert_false(b.connected, "road only at the hearth")
	s.place_road(h + Vector2i(2, 1))
	s.place_road(h + Vector2i(2, 2))
	assert_false(b.connected, "gap in the road")
	s.place_road(h + Vector2i(2, 3))
	assert_true(b.connected, "gap closed")
	s.remove_road(h + Vector2i(2, 1))
	assert_false(b.connected, "road cut")
	# A separate road touching a faraway building but not the hearth does not count.
	var far := _free_grass(s, 5)
	assert_ne(far, Vector2i(-1, -1))
	var fid := s.place_building_instant("tent", far)
	assert_true(fid >= 0)
	s.place_road(far + Vector2i(1, 0))
	assert_false((s.buildings[fid] as Building).connected)


func test_connection_event_emitted_on_change() -> void:
	var s := _new()
	var h := s.map.hearth_spot
	var id := s.place_building_instant("tent", h + Vector2i(3, 1))
	assert_true(id >= 0)
	var before := s.events.log_of("building_connection_changed").size()
	s.place_road(h + Vector2i(2, 1))
	var evs := s.events.log_of("building_connection_changed")
	assert_eq(evs.size(), before + 1)
	assert_eq(evs[-1]["data"]["id"], id)
	assert_true(evs[-1]["data"]["connected"])
	s.place_road(h + Vector2i(3, 0))
	assert_eq(s.events.log_of("building_connection_changed").size(), before + 1, "no change, no event")


func test_demolish_frees_tiles() -> void:
	var s := _new()
	var t := _free_grass(s)
	var id := s.place_building_instant("storehouse", t)
	assert_true(id >= 0)
	assert_eq(s.can_place("tent", t)["reason"], "overlap")
	assert_true(s.demolish(id))
	assert_false(s.buildings.has(id))
	assert_null(s.building_at(t))
	assert_null(s.building_at(t + Vector2i(1, 0)))
	assert_true(s.can_place("storehouse", t)["ok"])
	assert_false(s.demolish(id), "already gone")
	assert_false(s.demolish(s.hearth.id), "hearth cannot be demolished")
	assert_eq(s.events.log_of("building_demolished").size(), 1)


func test_road_remove_and_levels() -> void:
	var s := _new()
	var t := _free_grass(s)
	assert_true(s.place_road(t))
	assert_false(s.place_road(t), "already dirt")
	assert_true(s.place_road(t, Settlement.ROAD_PAVED))
	assert_eq(s.road_at(t), Settlement.ROAD_PAVED)
	assert_true(s.remove_road(t))
	assert_eq(s.road_at(t), Settlement.ROAD_NONE)
	assert_false(s.remove_road(t))


func test_ghost_validity_matches_can_place() -> void:
	# The ghost colours itself from can_place; check the pure mapping used by the UI.
	assert_eq(GhostView.color_for(true), GhostView.VALID)
	assert_eq(GhostView.color_for(false), GhostView.INVALID)
	assert_ne(GhostView.VALID, GhostView.INVALID)
