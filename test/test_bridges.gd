extends GutTest
## Ticket 91: roads and track cross the river as bridges (design.md sections 8, 9, 12). A road on a water tile costs
## RoadDef.bridge_cost on top of its own cost, a paved bridge pays both again, track on water costs 3x. The tile stays
## water underneath (wet, fouling, shore rule), buildings and bridges never share a tile, walkers cross.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var west := Vector2i(-1, -1)  # land bank tile
var river := Vector2i(-1, -1)  # the first water tile between (next to `west`)
var run: Array[Vector2i] = []  # every water tile between west and east
var east := Vector2i(-1, -1)  # land bank tile opposite
var dir := Vector2i.RIGHT


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "conflux"
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	s.hearth.inventory.add("wood", 500.0)
	s.hearth.inventory.add("stone", 500.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	assert_true(_find_crossing(), "the generated river has a one-tile-wide crossing between two land tiles")


func _land(t: Vector2i) -> bool:
	if not MapState.in_bounds(t.x, t.y):
		return false
	var d := reg.get_terrain(s.map.terrain_id_at(t.x, t.y))
	return d != null and d.buildable and s.building_at(t) == null and s.road_at(t) == 0


## The shortest straight water run between two land tiles, nearest the Hearth.
func _find_crossing() -> bool:
	var best := 1 << 30
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				if not _land(t) or not _water(t + d):
					continue
				var tiles: Array[Vector2i] = []
				var c: Vector2i = t + d
				while _water(c) and tiles.size() < 12:
					tiles.append(c)
					c += d
				if tiles.is_empty() or not _land(c) or not s.map.is_river(tiles[0].x, tiles[0].y):
					continue
				var score := tiles.size() * 1000 + absi(x - s.map.hearth_spot.x) + absi(y - s.map.hearth_spot.y)
				if score < best:
					best = score
					west = t
					river = tiles[0]
					run = tiles
					east = c
					dir = d
	return best < (1 << 30)


func _water(t: Vector2i) -> bool:
	return MapState.in_bounds(t.x, t.y) and s.map.terrain_id_at(t.x, t.y) == "water" and s.building_at(t) == null


func _mat() -> float:
	return float(s.totals().get("wood", 0.0))


func _stn() -> float:
	return float(s.totals().get("stone", 0.0))


func _stone() -> float:
	return float(s.totals().get("cut_stone", 0.0))


# AC1: dragging a road over the river lays a bridge tile and charges RoadDef.bridge_cost for it only.
func test_road_on_water_is_a_bridge_and_charges_the_bridge_cost() -> void:
	var cost: float = reg.get_road("dirt").bridge_cost["wood"]
	assert_eq(cost, 5.0, "data: 5 wood per water tile")
	var m0 := _mat()
	assert_true(s.can_place_road(river))
	assert_true(s.place_road(west))
	assert_eq(_mat(), m0, "a land tile of dirt road is free")
	assert_true(s.place_road(river))
	assert_eq(s.road_at(river), Settlement.ROAD_DIRT)
	assert_true(s.is_bridge(river))
	assert_almost_eq(m0 - _mat(), cost, 0.0001, "the water tile cost the bridge cost")
	assert_false(s.is_bridge(west), "the bank is land, not a bridge")
	assert_true(s.place_road(east))
	assert_almost_eq(m0 - _mat(), cost, 0.0001, "the far bank is free again")


func test_unaffordable_bridge_is_refused_and_spends_nothing() -> void:
	var inv := s.hearth.inventory
	inv.remove("wood", inv.amount_of("wood"))
	inv.add("wood", 4.0)
	assert_false(s.can_place_road(river))
	assert_false(s.place_road(river))
	assert_eq(s.road_at(river), Settlement.ROAD_NONE)
	assert_almost_eq(_mat(), 4.0, 0.0001)


# Paving a bridge tile: paved cost plus the bridge cost again; a dirt bridge pays the bridge cost again on upgrade.
func test_paving_a_bridge_pays_paved_and_bridge_cost() -> void:
	var m0 := _mat()
	var st0 := _stone()
	var sn0 := _stn()
	assert_true(s.can_pave_road(river)["ok"])
	assert_true(s.pave_road(river))
	assert_eq(s.road_at(river), Settlement.ROAD_PAVED)
	assert_almost_eq(m0 - _mat(), 1.0 + 4.0, 0.0001, "paved 1 wood + bridge 4 wood")
	assert_almost_eq(sn0 - _stn(), 1.0, 0.0001, "the bridge takes 1 stone")
	assert_almost_eq(st0 - _stone(), 0.0, 0.0001, "the cut stone debt of one tile is below a whole cut stone")
	var s2 := Settlement.new_game(SEED, reg)  # a dirt bridge, then paved over
	s2.era_override = "town"
	for r in MapState.REGION_COUNT:
		s2.map.set_region_owned(r, true)
	s2.hearth.inventory.add("wood", 100.0)
	s2.hearth.inventory.add("stone", 100.0)
	assert_true(s2.place_road(river))
	var m1: float = s2.totals()["wood"]
	assert_true(s2.pave_road(river))
	assert_almost_eq(m1 - float(s2.totals()["wood"]), 5.0, 0.0001, "upgrading pays paved + bridge again")


func test_paved_bridge_needs_wood_and_stone_for_both() -> void:
	s.era_override = "town"
	var inv := s.hearth.inventory
	inv.remove("wood", inv.amount_of("wood"))
	inv.remove("stone", inv.amount_of("stone"))
	inv.add("wood", 4.5)
	inv.add("stone", 5.0)
	assert_eq(s.can_pave_road(river)["reason"], "wood", "4.5 is under paved 1 + bridge 4")
	inv.add("wood", 1.0)
	inv.remove("stone", 5.0)
	inv.add("stone", 0.5)
	assert_eq(s.can_pave_road(river)["reason"], "stone", "0.5 is under the bridge's 1 stone")
	inv.add("stone", 1.0)
	assert_true(s.can_pave_road(river)["ok"])


# AC2: the bridge tile walks at its road's speed, and the far bank is unreachable without one.
func test_walkers_cross_only_by_bridge() -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	s.step_seconds(0.01)
	assert_true(ws.find_path(west, east).is_empty(), "no bridge: the far bank is unreachable")
	assert_true(s.place_road(west))
	var m0 := _mat()
	for t in run:
		assert_true(s.place_road(t), "bridge tile %s" % t)
	assert_almost_eq(m0 - _mat(), 5.0 * run.size(), 0.0001, "5 wood per water tile")
	assert_true(s.place_road(east))
	assert_false(ws.find_path(west, east).is_empty(), "a bridge joins the banks")
	assert_almost_eq(ws.tile_speed(river), reg.get_road("dirt").walk_speed, 0.0001)
	assert_true(s.pave_road(river))
	assert_almost_eq(ws.tile_speed(river), reg.get_road("paved").walk_speed, 0.0001, "paved bridge speed")
	assert_true(s.remove_road(river))
	assert_true(ws.find_path(west, east).is_empty(), "demolished: the river blocks again")


# AC3: track on water is a rail bridge at 3x the track cost, and depots either side are linked across it.
func test_rail_bridge_costs_three_times_and_links_depots() -> void:
	var lg := reg.logistics
	assert_eq(lg.track_bridge_multiplier, 3.0)
	var m0 := _mat()
	var st0 := _stone()
	assert_true(s.can_place_track(river)["ok"])
	assert_true(s.place_track(river))
	assert_true(s.track_at(river))
	assert_true(s.is_bridge(river))
	assert_almost_eq(m0 - _mat(), lg.track_cost_wood * 3.0, 0.0001)
	assert_almost_eq(st0 - _stone(), lg.track_cost_cut_stone * 3.0, 0.0001)
	m0 = _mat()
	assert_true(s.place_track(west))
	assert_almost_eq(m0 - _mat(), lg.track_cost_wood, 0.0001, "land track costs the plain price")
	m0 = _mat()
	assert_true(s.remove_track(river))
	assert_almost_eq(_mat() - m0, lg.track_cost_wood * 3.0 * lg.demolish_refund, 0.0001, "refund is of the 3x cost")
	assert_false(s.track_at(river))


func test_trains_cross_a_rail_bridge() -> void:
	var rail := s.get_system(RailSystem) as RailSystem
	# Like test_rail: two depots either side of a region boundary, joined by track, with the middle two tiles water.
	var h := s.map.hearth_spot
	var r1 := MapState.region_at(h.x, h.y)
	var left := (r1 / MapState.REGION_COLS) * MapState.REGION_COLS + mini(r1 % MapState.REGION_COLS, 1)
	var rect := MapState.region_rect(left)
	var bx := rect.end.x
	var y0 := h.y + 8 if h.y + 8 < rect.end.y - 4 else h.y - 8
	for x in range(bx - 12, bx + 8):
		for y in range(y0 - 2, y0 + 4):
			s.set_terrain(Vector2i(x, y), "grass")
	var gap := Vector2i(bx - 1, y0)
	s.set_terrain(gap, "water")
	s.set_terrain(Vector2i(bx, y0), "water")
	var a := s.place_building_instant("rail_depot", Vector2i(bx - 5, y0))
	var b := s.place_building_instant("rail_depot", Vector2i(bx + 2, y0))
	assert_true(a >= 0 and b >= 0, "both depots placed")
	var m0 := _mat()
	for x in range(bx - 2, bx + 2):
		assert_true(s.place_track(Vector2i(x, y0)), "track at x=%d" % x)
	assert_almost_eq(m0 - _mat(), reg.logistics.track_cost_wood * (2.0 + 2.0 * 3.0), 0.0001, "two land + two water tiles")
	assert_true(s.is_bridge(gap))
	assert_true(rail.linked(s, a, b), "the depots are linked across the rail bridge")
	assert_true(s.remove_track(gap))
	assert_false(rail.linked(s, a, b), "lifting the bridge tile breaks the link")


# AC4: the water underneath is unchanged: still water, river, wet, can foul, still satisfies the shore rule.
func test_water_stays_water_under_a_bridge() -> void:
	var wet0 := s.map.is_wet(river.x, river.y)
	assert_true(s.place_road(river))
	assert_true(s.place_track(river))
	assert_eq(s.map.terrain_id_at(river.x, river.y), "water")
	assert_true(s.map.is_river(river.x, river.y))
	assert_eq(s.map.is_wet(river.x, river.y), wet0)
	assert_true(s.set_fouled(river, true), "fouling still lands on a bridged tile")
	assert_true(s.map.is_fouled(river.x, river.y))
	assert_true(s.set_fouled(river, false))
	WaterSystem.recompute(s)
	assert_eq(s.map.is_wet(river.x, river.y), wet0, "wetness recomputed the same")
	# The shore rule (Fishing Dock reach) looks at the terrain, not at what stands on it.
	var shore := river - dir
	var before := Placement.check_rule(s.map, reg, reg.get_building("fishing_dock"), shore)
	s.remove_road(river)
	s.remove_track(river)
	var after := Placement.check_rule(s.map, reg, reg.get_building("fishing_dock"), shore)
	assert_eq(before, after)


# Buildings never stand on a bridge tile, and a bridge never goes under a building (including on_river ones).
func test_buildings_and_bridges_refuse_each_other() -> void:
	assert_true(s.place_road(river))
	var w := reg.get_building("fishing_dock")
	assert_eq(s.can_place("fishing_dock", river)["ok"], false, "no building on a bridge tile")
	assert_eq(s.can_place("clearwater_works", river)["ok"], false, "no on_river building on a bridge tile")
	s.remove_road(river)
	var r := s.can_place("clearwater_works", river)
	if r["ok"]:  # a weir may stand in the river; then the bridge refuses it back
		var id := s.place_building_instant("clearwater_works", river)
		assert_true(id >= 0)
		assert_false(s.can_place_road(river))
		assert_false(s.can_place_track(river)["ok"])
	assert_not_null(w)


# Save: the bridge is just a road/track tile, so a round trip keeps it.
func test_save_round_trip_keeps_bridges() -> void:
	assert_true(s.place_road(river))
	assert_true(s.place_track(river))
	var s2 := Settlement.from_dict(s.to_dict(), reg)
	assert_eq(s2.road_at(river), Settlement.ROAD_DIRT)
	assert_true(s2.track_at(river))
	assert_true(s2.is_bridge(river))


# Art: a road on water draws on the Bridges layer (plank for dirt, stone for paved) and not on Roads; track on water
# uses the trestle source; land keeps the old layers.
func test_bridge_art_layers() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = SEED
	add_child_autofree(main)
	main.start_new_game()
	await get_tree().process_frame
	var st: Settlement = main.settlement
	st.era_override = "conflux"
	st.hearth.inventory.add("wood", 200.0)
	st.hearth.inventory.add("stone", 200.0)
	st.hearth.inventory.add("cut_stone", 50.0)
	for r in MapState.REGION_COUNT:
		st.map.set_region_owned(r, true)
	var land := west
	var water := river
	assert_true(st.place_road(land))
	assert_true(st.place_road(water))
	var v: MapView = main.map_view
	assert_eq(v.bridges.get_cell_source_id(water), 1, "dirt bridge: plank source")
	assert_eq(v.roads.get_cell_source_id(water), -1, "no road art under the deck")
	assert_eq(v.roads.get_cell_source_id(land), 1, "the bank keeps its road tile")
	assert_eq(v.bridges.get_cell_source_id(land), -1)
	assert_true(st.pave_road(water))
	assert_eq(v.bridges.get_cell_source_id(water), 2, "paved bridge: stone source")
	assert_true(st.remove_road(water))
	assert_eq(v.bridges.get_cell_source_id(water), -1, "demolished: deck erased")
	assert_true(st.place_track(water))
	assert_eq(v.track.get_cell_source_id(water), ArtLibrary.BRIDGE_TRESTLE, "rail bridge: trestle source")
	assert_true(st.place_road(water))
	assert_eq(v.track.get_cell_source_id(water), 1, "road and track share the deck: crossing art over the plank")
