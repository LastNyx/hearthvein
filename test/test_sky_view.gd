extends GutTest
## Ticket 40d: Tab toggles the active layer (only with an island), placement targets the active layer, the build bar
## greys out defs of the other layer, and MapView draws the islands on their own sky group.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var m: HudModel
var h: Vector2i
var isl: Island


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	var d := BuildingDef.new()
	d.id = "test_sky_farm"
	d.display_name = "Sky farm"
	d.era = "camp"
	d.category = "food"
	d.size = Vector2i(2, 2)
	d.layers = "island"
	d.cost = {"materials": 10}
	reg.buildings[d.id] = d


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "skyborne"
	h = s.map.hearth_spot
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 6, h.y + 8):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
	m = HudModel.new(s)


func _raise_island() -> void:
	var aid := s.place_building_instant("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	assert_true(aid >= 0, "anchor placed")
	isl = (s.get_system(IslandSystem) as IslandSystem).island_of_anchor(aid)
	assert_not_null(isl)


func _controller() -> BuildController:
	var c := BuildController.new()
	add_child_autofree(c)
	var ghost := GhostView.new()
	add_child_autofree(ghost)
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	c.setup(s, ghost, layer)
	c.model = m
	return c


func _free_ground_tile() -> Vector2i:
	for y in range(h.y + 3, h.y + 7):
		for x in range(h.x + 8, h.x + 18):
			if s.can_place("lumen_pylon", Vector2i(x, y), true)["ok"] and not isl.rect.has_point(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_tab_does_nothing_without_an_island() -> void:
	assert_eq(m.active_layer, Building.LAYER_GROUND)
	assert_eq(m.toggle_layer(), Building.LAYER_GROUND)
	assert_eq(m.active_layer, Building.LAYER_GROUND)
	assert_true(m.notifications.items.any(func(it: Dictionary) -> bool: return it["text"] == "No islands yet"), "a short toast")
	assert_eq(m.layer_name(), "Ground")


func test_tab_toggles_the_layer_with_an_island() -> void:
	_raise_island()
	var seen: Array[int] = []
	m.layer_changed.connect(func(l: int) -> void: seen.append(l))
	assert_eq(m.toggle_layer(), Building.LAYER_SKY)
	assert_eq(m.layer_name(), "Sky")
	assert_eq(m.toggle_layer(), Building.LAYER_GROUND)
	assert_eq(seen, [Building.LAYER_SKY, Building.LAYER_GROUND])


func test_sky_view_falls_back_to_ground_when_the_last_island_goes() -> void:
	_raise_island()
	m.toggle_layer()
	assert_true(s.demolish(isl.anchor_id))
	m.sync_layer()
	assert_eq(m.active_layer, Building.LAYER_GROUND)


func test_placement_follows_the_active_layer() -> void:
	_raise_island()
	s.hearth.inventory.add("materials", 200.0)
	var c := _controller()
	var sky_tile := isl.rect.position + Vector2i(8, 6)
	# Sky view: the island building goes on layer 1 at the clicked tile.
	m.toggle_layer()
	c.set_build("test_sky_farm")
	c._click(sky_tile)
	var b := s.building_at(sky_tile, Building.LAYER_SKY)
	assert_not_null(b, "placed on the island")
	assert_eq(b.layer, Building.LAYER_SKY)
	assert_ne(s.building_at(sky_tile, Building.LAYER_GROUND), b, "not the same building on the ground below")
	# A ground-only def is refused from the sky view.
	c.set_build("lumen_pylon")
	var g := _free_ground_tile()
	assert_true(g.x >= 0)
	c._click(g)
	assert_null(s.building_at(g), "ground def not placed from the sky view")
	# Ground view: the same click lands on layer 0.
	m.toggle_layer()
	c._click(g)
	var gb := s.building_at(g)
	assert_not_null(gb)
	assert_eq(gb.layer, Building.LAYER_GROUND)


func test_roads_follow_the_active_layer() -> void:
	_raise_island()
	var c := _controller()
	var t := isl.rect.position + Vector2i(2, 2)
	m.toggle_layer()
	c.set_mode(BuildController.Mode.ROAD)
	c._click(t)
	assert_eq(s.sky_roads[MapState.idx(t.x, t.y)], Settlement.ROAD_DIRT, "sky road")
	assert_eq(s.road_at(t), Settlement.ROAD_NONE, "no ground road")
	m.toggle_layer()
	c._click(t)
	assert_eq(s.road_at(t), Settlement.ROAD_DIRT, "ground road in the ground view")


func test_sky_lift_places_through_the_ground_api_from_the_sky_view() -> void:
	_raise_island()
	s.hearth.inventory.add("materials", 200.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	s.hearth.inventory.add("tools", 50.0)
	s.gold = 500.0
	var t := Vector2i(-1, -1)
	for x in range(isl.rect.position.x + 2, isl.rect.end.x - 2):
		var cand := Vector2i(x, isl.rect.position.y + 2)
		if s.can_place("sky_lift", cand, true)["ok"]:
			t = cand
			break
	assert_true(t.x >= 0, "a lift tile exists")
	var c := _controller()
	m.toggle_layer()
	assert_eq(m.layer_block_reason(reg.get_building("sky_lift")), "")
	c.set_build("sky_lift")
	c._click(t)
	var lift := s.building_at(t)
	assert_not_null(lift, "lift stands on the ground")
	assert_eq(lift.layer, Building.LAYER_GROUND)
	assert_eq(s.building_at(t, Building.LAYER_SKY), lift, "and fills the sky tile")


func _entry(cat_id: String, id: String) -> Dictionary:
	for cat in m.build_bar():
		if cat["id"] == cat_id:
			for e: Dictionary in cat["entries"]:
				if e["id"] == id:
					return e
	return {}


func test_build_bar_greys_out_the_other_layer() -> void:
	_raise_island()
	var anchor := _entry("sky", "lift_anchor")
	assert_true(anchor["enabled"], "ground view: ground def enabled")
	assert_true(_entry("sky", "sky_lift")["enabled"])
	m.toggle_layer()
	anchor = _entry("sky", "lift_anchor")
	assert_false(anchor["enabled"], "sky view greys out a ground-only def")
	assert_ne(anchor["reason"], "")
	assert_true(_entry("sky", "sky_lift")["enabled"], "the Sky Lift is placeable from either view")
	assert_true(_entry("logistics", "airship_dock")["enabled"], "either-layer defs stay enabled")
	m.toggle_layer()
	var farm := _entry("food", "test_sky_farm")
	assert_false(farm["enabled"], "ground view greys out an island-only def")
	assert_true(String(farm["reason"]).contains("Island only"))


func test_map_view_draws_islands_on_the_sky_group() -> void:
	_raise_island()
	var v := MapView.new()
	add_child_autofree(v)
	v.setup(s.map)
	assert_false(v.sky_group.visible, "no islands: nothing drawn")
	v.refresh_sky(s.sky_map, [isl.rect])
	assert_true(v.sky_group.visible)
	assert_eq(v.sky_base.get_used_cells().size(), isl.rect.size.x * isl.rect.size.y - 4,
			"one batched cell per island tile, but the four corner tiles (drawn as rounded caps)")
	assert_eq(v.sky_corners.get_child_count(), 4, "four corner caps")
	assert_eq(v.sky_cap_rims.get_child_count(), 4, "and their cliff bands")
	assert_gt(v.sky_rim.get_used_cells().size(), 0, "the rim runs round the edge")
	assert_gt(v.sky_under.get_used_cells().size(), isl.rect.size.x, "the kit (underside, side masses, lumps) hangs round the island")
	var corner_tiles: Array[Vector2i] = [isl.rect.position, Vector2i(isl.rect.end.x - 1, isl.rect.position.y),
			Vector2i(isl.rect.end.x - 1, isl.rect.end.y - 1), Vector2i(isl.rect.position.x, isl.rect.end.y - 1)]
	var deepest := 0
	for c in v.sky_under.get_used_cells():
		if isl.rect.has_point(c):
			assert_true(corner_tiles.has(c), "the kit only reaches into the island at the bitten corner tiles")
		deepest = maxi(deepest, c.y - isl.rect.end.y + 1)
	assert_gte(deepest, 3, "the underside hangs at least three tiles below the south edge")
	assert_true(v.sky_edge.visible and v.sky_under.visible)
	assert_almost_eq(v.sky_group.modulate.a, MapView.GROUND_VIEW_SKY_ALPHA, 0.001, "translucent from the ground")
	v.set_active_layer(Building.LAYER_SKY)
	assert_eq(v.sky_group.modulate.a, 1.0, "solid from the sky")
	v.set_active_layer(Building.LAYER_GROUND)
	v.refresh_sky(s.sky_map, [])
	assert_false(v.sky_group.visible)
	assert_eq(v.sky_base.get_used_cells().size(), 0)


func test_sky_buildings_and_lifts_draw_in_their_own_nodes() -> void:
	_raise_island()
	s.place_road(Vector2i(h.x + 3, h.y + 1), Settlement.ROAD_DIRT)
	var v := MapView.new()
	add_child_autofree(v)
	v.setup(s.map)
	v.refresh_sky(s.sky_map, [isl.rect])
	var pv := PlacementView.new()
	add_child_autofree(pv)
	pv.setup(s, v)
	var ground_before := v.objects.get_child_count()
	var roads_before := v.roads.get_used_cells().size()
	var sky_tile := isl.rect.position + Vector2i(8, 6)
	assert_true(s.place_building_instant("airship_dock", sky_tile, Building.LAYER_SKY) >= 0)
	assert_eq(v.sky_objects.get_child_count(), 1, "sky building sits in the sky group")
	assert_eq(v.objects.get_child_count(), ground_before, "not among the ground objects")
	s.place_road(sky_tile + Vector2i(-1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	assert_eq(v.sky_roads.get_used_cells().size(), 1, "sky road on the sky road layer")
	assert_eq(v.roads.get_used_cells().size(), roads_before, "ground roads untouched")
	var lt := Vector2i(-1, -1)
	for x in range(isl.rect.position.x + 1, isl.rect.end.x - 1):
		var cand := Vector2i(x, isl.rect.position.y + 1)
		if s.can_place("sky_lift", cand, true)["ok"]:
			lt = cand
			break
	assert_true(lt.x >= 0)
	assert_true(s.place_building_instant("sky_lift", lt) >= 0)
	assert_eq(v.lifts.get_child_count(), 1, "the lift is drawn solid in its own node")
	assert_eq(v.objects.get_child_count(), ground_before, "and not among the translucent or dimmed objects")


func test_walkers_decode_their_global_tile_to_a_layer_and_local_position() -> void:
	var w := Walker.new()
	w.tile = MapState.to_global(Vector2i(10, 4), Building.LAYER_SKY)
	assert_eq(MapState.layer_of(w.tile), Building.LAYER_SKY)
	assert_eq(WalkerView._local_position(w, Building.LAYER_SKY), Vector2(10.5, 4.5))
	var g := Walker.new()
	g.tile = Vector2i(3, 5)
	assert_eq(WalkerView._local_position(g, Building.LAYER_GROUND), Vector2(3.5, 5.5))
	# A lift ride (the step changes layer) stays on its tile and does not animate.
	var r := Walker.new()
	r.tile = Vector2i(6, 6)
	r.path = [MapState.to_global(Vector2i(6, 6), Building.LAYER_SKY)]
	r.progress = 0.5
	assert_true(WalkerView._riding(r))
	assert_eq(WalkerView._local_position(r, Building.LAYER_GROUND), Vector2(6.5, 6.5))
	assert_eq(WalkerView.move_vector(r), Vector2.ZERO)
