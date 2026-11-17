extends GutTest
## Ticket 40c: Sky Lift and island pathing. Walkers and haulers cross between the ground and an island only through a
## finished Sky Lift (or an island dock paired with the ground dock of its region). Settlement API plus step_hours.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ws: WalkerSystem
var h: Vector2i
var anchor: Building
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
	d.worker_slots = 2
	d.cost = {"materials": 10}
	d.recipe = RecipeDef.new()
	d.recipe.outputs = {"food": 2.0}
	reg.buildings[d.id] = d


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "skyborne"
	ws = s.get_system(WalkerSystem) as WalkerSystem
	h = s.map.hearth_spot
	for x in range(h.x - 2, h.x + 20):
		for y in range(h.y - 5, h.y + 6):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if x >= h.x + 2:
			s.place_road(Vector2i(x, h.y))
	s.place_building_instant("lumen_pylon", Vector2i(h.x + 3, h.y - 1))
	var aid := s.place_building_instant("lift_anchor", Vector2i(h.x + 4, h.y - 3))
	assert_true(aid >= 0, "anchor placed")
	anchor = s.buildings[aid]
	isl = _isl().island_of_anchor(aid)
	assert_not_null(isl)
	s.hearth.inventory.add("lumen", 400.0)
	s.step_seconds(0.01)  # binds the walker system to the settlement
	JobSystem.refresh(s)


func _isl() -> IslandSystem:
	return s.get_system(IslandSystem) as IslandSystem


## A ground tile just south of the road that has skystone above it (the island covers the Hearth's surroundings).
func _lift_spot() -> Vector2i:
	for x in range(h.x + 2, h.x + 5):
		var t := Vector2i(x, h.y + 1)
		if isl.rect.has_point(t) and isl.rect.has_point(t + Vector2i(3, 1)) and s.can_place("sky_lift", t, true)["ok"]:
			return t
	return Vector2i(-1, -1)


func _lift() -> Building:
	var t := _lift_spot()
	assert_true(t.x >= 0, "a lift spot exists")
	var id := s.place_building_instant("sky_lift", t)
	assert_true(id >= 0, "lift placed")
	return s.buildings[id]


## A sky farm two tiles east of the lift tile, joined to it by a sky road tile. Returns the farm.
func _farm_by(lift: Building, instant: bool = true) -> Building:
	var o := lift.origin
	s.place_road(o + Vector2i(1, 0), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	var id := s.place_building_instant("test_sky_farm", o + Vector2i(2, 0), Building.LAYER_SKY) if instant \
			else s.place_building("test_sky_farm", o + Vector2i(2, 0), Building.LAYER_SKY)
	assert_true(id >= 0, "sky farm placed")
	return s.buildings[id]


func _worker_of(b: Building) -> int:
	for c: Citizen in s.citizens.values():
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			return c.id
	return -1


func test_data_row_and_ride_numbers() -> void:
	var d := reg.get_building("sky_lift")
	assert_eq(d.era, "skyborne")
	assert_eq(d.size, Vector2i(1, 1))
	assert_eq(d.cost, {"materials": 80, "gold": 30, "cut_stone": 20, "tools": 10})
	assert_eq(d.upkeep_lumen, 2.0)
	assert_eq(d.worker_slots, 0)
	assert_true(d.sky_lift)
	assert_eq(d.layers, "ground")
	assert_gt(reg.logistics.lift_ride_seconds, 0.0)
	assert_gt(reg.logistics.dock_ride_seconds, 0.0)


func test_tile_encoding_helpers() -> void:
	var t := Vector2i(7, 9)
	assert_eq(MapState.to_global(t, Building.LAYER_GROUND), t)
	var g := MapState.to_global(t, Building.LAYER_SKY)
	assert_eq(g, Vector2i(7, 9 + MapState.HEIGHT))
	assert_eq(MapState.layer_of(g), Building.LAYER_SKY)
	assert_eq(MapState.layer_of(t), Building.LAYER_GROUND)
	assert_eq(MapState.local_of(g), t)
	assert_eq(MapState.local_of(t), t)


func test_lift_placement_needs_skystone_and_fills_both_layers() -> void:
	# Away from the island there is no skystone above: refused.
	var far := Vector2i(h.x + 10, h.y + 1)
	assert_false(isl.rect.has_point(far))
	assert_eq(s.can_place("sky_lift", far, true)["reason"], "no_island")
	assert_eq(s.place_building_instant("sky_lift", far), -1)
	# Not placeable on the sky layer: it is a ground building.
	var t := _lift_spot()
	assert_eq(s.can_place("sky_lift", t, true, Building.LAYER_SKY)["reason"], "wrong_layer")
	# A sky building on the tile above blocks it.
	assert_true(s.place_building_instant("test_sky_farm", t, Building.LAYER_SKY) >= 0)
	assert_eq(s.can_place("sky_lift", t, true)["reason"], "overlap")
	s.demolish(s.building_at(t, Building.LAYER_SKY).id)
	# A sky road does too.
	s.place_road(t, Settlement.ROAD_DIRT, Building.LAYER_SKY)
	assert_eq(s.can_place("sky_lift", t, true)["reason"], "road")
	s.remove_road(t, Building.LAYER_SKY)
	var lift := _lift()
	assert_eq(s.building_at(lift.origin), lift, "on the ground")
	assert_eq(s.building_at(lift.origin, Building.LAYER_SKY), lift, "and in the sky tile above")
	assert_eq(lift.layer, Building.LAYER_GROUND)
	assert_eq(s.can_place("sky_lift", lift.origin, true)["reason"], "overlap")


func test_demolish_frees_both_layers_and_a_lift_pins_the_anchor() -> void:
	var lift := _lift()
	var o := lift.origin
	assert_false(s.demolish(anchor.id), "an island with a lift on it cannot be dropped")
	assert_true(s.demolish(lift.id))
	assert_null(s.building_at(o))
	assert_null(s.building_at(o, Building.LAYER_SKY))
	assert_true(s.can_place("sky_lift", o, true)["ok"])
	assert_true(s.demolish(anchor.id), "empty island goes")


func test_without_a_lift_the_island_is_unreachable() -> void:
	var farm := _farm_by(Building.new() if false else _fake_lift_tile())
	assert_false(farm.connected, "no lift: the island building is not connected")
	var from := ws.door_tile(s.hearth)
	assert_true(ws.find_path(from, ws.door_tile(farm)).is_empty(), "and no path reaches it")
	step_days_for_jobs()
	assert_eq(_worker_of(farm), -1, "nobody is given a job there")


## A stand-in with the lift's origin, so the farm helper can lay its road and building without a lift.
func _fake_lift_tile() -> Building:
	var b := Building.new()
	b.origin = _lift_spot()
	return b


func step_days_for_jobs() -> void:
	s.step_hours(2)
	JobSystem.refresh(s)


func test_walker_reaches_an_island_job_through_the_lift() -> void:
	var lift := _lift()
	var farm := _farm_by(lift)
	assert_true(lift.connected, "the lift stands beside the ground road")
	assert_true(farm.connected, "the sky road joins the farm to the lift")
	var cid := _worker_of(farm)
	assert_gt(cid, -1, "a citizen is given the island job")
	var door := ws.door_tile(farm)
	assert_eq(MapState.layer_of(door), Building.LAYER_SKY, "a sky door is encoded on the sky layer")
	var p := ws.find_path(ws.door_tile(s.hearth), door)
	assert_false(p.is_empty(), "a path exists with a lift")
	var i := p.find(lift.origin)
	assert_gt(i, -1, "the path goes through the lift's ground tile")
	assert_eq(p[i + 1], MapState.to_global(lift.origin, Building.LAYER_SKY), "straight onto the sky tile above it")
	assert_eq(p[p.size() - 1], door)
	for k in range(i + 1, p.size()):
		assert_eq(MapState.layer_of(p[k]), Building.LAYER_SKY, "then it stays in the sky")
	for k in range(0, i + 1):
		assert_eq(MapState.layer_of(p[k]), Building.LAYER_GROUND, "and before it stays on the ground")
	var ride := reg.logistics.lift_ride_seconds
	var walk_only := ws.path_seconds(ws.find_path(ws.door_tile(s.hearth), lift.origin)) \
			+ ws.path_seconds(ws.find_path(MapState.to_global(lift.origin, Building.LAYER_SKY), door))
	assert_almost_eq(ws.path_seconds(p), walk_only + ride, 0.001, "the ride costs lift_ride_seconds")
	# The walker gets there during the working day.
	var arrived := false
	var on_sky := false
	for hour in 30:
		s.step_hours(1)
		var w := ws.walker_of(cid)
		if w.path.is_empty() and w.at_building == farm.id:
			arrived = true
			on_sky = MapState.layer_of(w.tile) == Building.LAYER_SKY
			break
	assert_true(arrived, "the citizen arrives at the island job")
	assert_true(on_sky, "standing on the sky layer")


func test_a_site_demolished_or_unfinished_lift_carries_nobody() -> void:
	s.gold = 100.0
	var t := _lift_spot()
	var sid := s.place_building("sky_lift", t)
	assert_true(sid >= 0, "a lift site is placed")
	var farm := _farm_by(s.buildings[sid])
	assert_true(ws.find_path(ws.door_tile(s.hearth), ws.door_tile(farm)).is_empty(), "a lift site is no link")
	assert_false(farm.connected)
	s.demolish(sid)
	var lift := _lift()
	assert_false(ws.find_path(ws.door_tile(s.hearth), ws.door_tile(farm)).is_empty())
	s.demolish(lift.id)
	assert_true(ws.find_path(ws.door_tile(s.hearth), ws.door_tile(farm)).is_empty(), "demolishing the lift cuts the island")
	assert_false(farm.connected)


func test_a_still_island_lift_carries_nobody() -> void:
	var lift := _lift()
	var farm := _farm_by(lift)
	var from := ws.door_tile(s.hearth)
	var door := ws.door_tile(farm)
	assert_false(ws.find_path(from, door).is_empty())
	_isl()._set_still(s, isl, "short_lumen")
	assert_true(ws.find_path(from, door).is_empty(), "still island: no path up")
	assert_true(ws.find_path(door, from).is_empty(), "and none down")
	_isl()._set_still(s, isl, "")
	assert_false(ws.find_path(from, door).is_empty(), "fed again: the lift carries")


func test_sky_to_ground_path_and_two_lifts_pick_the_nearer() -> void:
	var lift := _lift()
	var farm := _farm_by(lift)
	var far_t := Vector2i(isl.rect.end.x - 1, h.y + 1)
	assert_true(isl.rect.has_point(far_t), "second lift spot on the island")
	var second := s.place_building_instant("sky_lift", far_t)
	assert_gt(second, -1)
	var door := ws.door_tile(farm)
	var down := ws.find_path(door, ws.door_tile(s.hearth))
	assert_false(down.is_empty())
	assert_eq(down[0], door)
	assert_true(down.has(lift.origin), "the near lift is used")
	assert_false(down.has(far_t), "not the far one")
	s.demolish(lift.id)
	var via_far := ws.find_path(MapState.to_global(farm.origin, Building.LAYER_SKY), ws.door_tile(s.hearth))
	assert_true(via_far.is_empty() or via_far.has(far_t), "with the near lift gone the other one serves")


func test_walker_reaches_an_island_job_through_a_dock_pair() -> void:
	var gd := s.place_building_instant("airship_dock", Vector2i(h.x + 12, h.y + 1))
	assert_gt(gd, -1, "ground dock beside the road")
	var ground_dock: Building = s.buildings[gd]
	assert_eq(s.map.get_region(ground_dock.origin.x, ground_dock.origin.y), isl.region)
	# One dock per region and layer: a second ground dock is refused, the island one is not.
	assert_eq(s.can_place("airship_dock", Vector2i(h.x + 8, h.y + 1), true)["reason"], "region_dock")
	var o := isl.rect.position + Vector2i(1, 1)
	assert_true(s.can_place("airship_dock", o, true, Building.LAYER_SKY)["ok"], "an island dock may stand in the region")
	var did := s.place_building_instant("airship_dock", o, Building.LAYER_SKY)
	assert_gt(did, -1)
	var island_dock: Building = s.buildings[did]
	assert_eq(s.can_place("airship_dock", o + Vector2i(6, 6), true, Building.LAYER_SKY)["reason"], "region_dock")
	# A sky road from the island dock to a farm.
	for x in range(o.x + 3, o.x + 6):
		s.place_road(Vector2i(x, o.y + 1), Settlement.ROAD_DIRT, Building.LAYER_SKY)
	var fid := s.place_building_instant("test_sky_farm", Vector2i(o.x + 6, o.y), Building.LAYER_SKY)
	assert_gt(fid, -1)
	var farm: Building = s.buildings[fid]
	assert_true(ground_dock.connected, "the ground dock stands beside the road")
	assert_true(island_dock.connected, "the island dock is reached through its ground twin")
	assert_true(farm.connected)
	var door := ws.door_tile(farm)
	var p := ws.find_path(ws.door_tile(s.hearth), door)
	assert_false(p.is_empty(), "a dock pair carries walkers")
	assert_true(p.has(ws.door_tile(ground_dock)))
	assert_true(p.has(ws.door_tile(island_dock)))
	var gi := p.find(ws.door_tile(ground_dock))
	assert_eq(p[gi + 1], ws.door_tile(island_dock), "straight across from dock door to dock door")
	var legs := ws.path_seconds(ws.find_path(ws.door_tile(s.hearth), ws.door_tile(ground_dock))) \
			+ ws.path_seconds(ws.find_path(ws.door_tile(island_dock), door))
	assert_almost_eq(ws.path_seconds(p), legs + reg.logistics.dock_ride_seconds, 0.001)
	# And somebody gets to work there (more hands, so the docks do not leave the anchor unstaffed and the island still).
	for i in 8:
		s.add_citizen()
	var cid := _worker_of(farm)
	assert_gt(cid, -1)
	var arrived := false
	for hour in 30:
		s.step_hours(1)
		var w := ws.walker_of(cid)
		if w.path.is_empty() and w.at_building == farm.id:
			arrived = true
			break
	assert_true(arrived, "the citizen arrives at the island job over the docks")
	# Without the ground dock the island dock links nothing.
	s.demolish(gd)
	assert_true(ws.find_path(ws.door_tile(s.hearth), door).is_empty())
	assert_false(farm.connected)


func test_hauler_carries_materials_to_a_sky_site_over_the_lift() -> void:
	var lift := _lift()
	var farm := _farm_by(lift, false)  # a construction site on the island needing 10 materials
	assert_true(farm.site)
	var delivered := []
	s.events.subscribe("haul_delivered", func(e: Dictionary) -> void:
		if int(e["data"]["to"]) == farm.id:
			delivered.append(e["data"]))
	s.hearth.inventory.add("materials", 50.0)
	for hour in 48:
		s.step_hours(1)
		if farm.site_delivered():
			break
	assert_true(farm.site_delivered(), "the site got its materials")
	assert_gt(delivered.size(), 0, "a hauler delivered across the lift")
	assert_almost_eq(farm.input_buffer.amount_of("materials"), 10.0, 0.001)


func test_no_lift_no_delivery_to_a_sky_site() -> void:
	var farm := _farm_by(_fake_lift_tile(), false)
	s.hearth.inventory.add("materials", 50.0)
	s.step_days(3)
	assert_almost_eq(farm.input_buffer.amount_of("materials"), 0.0, 0.001, "nothing crosses without a lift")


func test_hauler_carries_island_output_down_to_storage() -> void:
	var lift := _lift()
	var farm := _farm_by(lift)
	s.set_storage_filter(s.hearth.id, ["food", "lumen", "materials"])
	var food0 := float(s.totals().get("food", 0.0))
	var best := 0.0
	for hour in 96:
		s.step_hours(1)
		best = maxf(best, farm.door_buffer.amount_of("food") if farm.door_buffer != null else 0.0)
	assert_gt(best, 0.0, "the island farm produced")
	assert_gt(float(s.totals().get("food", 0.0)), food0, "its food came down to the Hearth")


func test_storage_distance_goes_through_the_lift() -> void:
	var lift := _lift()
	# A sky storage stand-in: distance from a ground tile is by way of the lift, unreachable without one.
	var a := h + Vector2i(2, 0)
	var b := MapState.to_global(lift.origin + Vector2i(3, 0), Building.LAYER_SKY)
	var d := ws.estimate_distance(s, a, b)
	var expect := float(absi(a.x - lift.origin.x) + absi(a.y - lift.origin.y)) + reg.logistics.lift_ride_seconds + 3.0
	assert_almost_eq(d, expect, 0.001)
	s.demolish(lift.id)
	assert_eq(ws.estimate_distance(s, a, b), INF)
