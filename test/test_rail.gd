extends GutTest
## Ticket 37: rail track tiles and Rail Depots. One depot per region, depots joined by 4-connected track are linked
## (a gap breaks the link), and a building road-connected to a depot is connected to everything road-connected to a
## depot on the same network.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var rail: RailSystem
var h: Vector2i
var y0: int  # row of both depots and the track
var bx: int  # first tile of the right-hand region (the region boundary)


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "conflux"
	rail = s.get_system(RailSystem)
	h = s.map.hearth_spot
	var r1 := MapState.region_at(h.x, h.y)
	var left := (r1 / MapState.REGION_COLS) * MapState.REGION_COLS + mini(r1 % MapState.REGION_COLS, 1)
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var rect := MapState.region_rect(left)
	bx = rect.end.x
	y0 = h.y + 8 if h.y + 8 < rect.end.y - 4 else h.y - 8
	for x in range(bx - 12, bx + 8):
		for y in range(y0 - 2, y0 + 4):
			s.set_terrain(Vector2i(x, y), "grass")
	s.hearth.inventory.add("materials", 500.0)
	s.hearth.inventory.add("cut_stone", 100.0)


func _depot(x: int) -> int:
	var id := s.place_building_instant("rail_depot", Vector2i(x, y0))
	assert_true(id >= 0, "depot placed at x=%d" % x)
	return id


## Left depot A at bx-5..bx-3, right depot B at bx+2..bx+4 (two regions); track tiles bx-2..bx+1 join them.
func _two_depots() -> Array[int]:
	return [_depot(bx - 5), _depot(bx + 2)]


func _lay_track(from_x: int, to_x: int) -> void:
	for x in range(from_x, to_x + 1):
		assert_true(s.place_track(Vector2i(x, y0)), "track at x=%d" % x)


func test_second_depot_in_region_is_rejected() -> void:
	assert_true(s.can_place("rail_depot", Vector2i(bx - 5, y0))["ok"], "the first depot is fine")
	var a := _depot(bx - 5)
	var r := s.can_place("rail_depot", Vector2i(bx - 9, y0))
	assert_false(r["ok"], "a second depot in the same region is refused")
	assert_eq(r["reason"], "region_depot")
	assert_eq(s.place_building("rail_depot", Vector2i(bx - 9, y0)), -1, "place_building refuses it too")
	assert_true(s.can_place("rail_depot", Vector2i(bx + 2, y0))["ok"], "the next region may have its own")
	s.demolish(a)
	assert_true(s.can_place("rail_depot", Vector2i(bx - 9, y0))["ok"], "demolishing frees the region")
	# A construction site holds the region too.
	s.gold = 1000.0
	assert_true(s.place_building("rail_depot", Vector2i(bx - 9, y0)) >= 0, "a site is placed")
	assert_eq(s.can_place("rail_depot", Vector2i(bx - 5, y0))["reason"], "region_depot", "a site counts")


func test_depots_joined_by_track_are_linked_and_a_gap_breaks_it() -> void:
	var d := _two_depots()
	assert_false(rail.linked(s, d[0], d[1]), "no track, no link")
	assert_ne(rail.network_of(s, d[0]), rail.network_of(s, d[1]))
	_lay_track(bx - 2, bx + 1)
	assert_true(rail.linked(s, d[0], d[1]), "track joins the depots")
	assert_eq(rail.network_of(s, d[1]), d[0], "network id is the lowest depot id")
	assert_eq(rail.depots_of_network(s, d[0]), [d[0], d[1]] as Array[int])
	assert_eq(rail.network_ids(s), [d[0]] as Array[int])
	assert_true(s.remove_track(Vector2i(bx, y0)), "lift a middle tile")
	assert_false(rail.linked(s, d[0], d[1]), "a gap breaks the link")
	assert_true(s.place_track(Vector2i(bx, y0)))
	assert_true(rail.linked(s, d[0], d[1]), "mending the gap restores it")


func test_links_are_transitive() -> void:
	var rect := MapState.region_rect(MapState.region_at(bx, y0) + 1)
	var bx2 := rect.position.x
	for x in range(bx - 12, bx2 + 8):
		s.set_terrain(Vector2i(x, y0), "grass")
	var d := _two_depots()
	var c := s.place_building_instant("rail_depot", Vector2i(bx2 + 2, y0))
	assert_true(c >= 0, "third depot placed")
	_lay_track(bx - 2, bx + 1)
	assert_false(rail.linked(s, d[0], c), "C is not on the network yet")
	for x in range(bx + 5, bx2 + 2):
		assert_true(s.place_track(Vector2i(x, y0)))
	assert_true(rail.linked(s, d[0], c), "A to C through B")
	assert_eq(rail.depots_of_network(s, d[0]).size(), 3)


func test_building_connected_to_a_depot_counts_as_connected() -> void:
	var d := _two_depots()
	# A is the depot on the Hearth's side of the boundary (it gets the road), B the far one.
	var a := 1 if h.x >= bx else 0
	var b := 1 - a
	var ax := bx + 3 if a == 1 else bx - 4  # middle tile under each depot, on the row below it
	var bmid := bx + 3 if b == 1 else bx - 4
	var rx := h.x + s.hearth.def.size.x
	for y in range(mini(h.y, y0 + 1), maxi(h.y, y0 + 1) + 1):
		s.set_terrain(Vector2i(rx, y), "grass")
		assert_true(s.place_road(Vector2i(rx, y)) or s.road_at(Vector2i(rx, y)) != 0)
	for x in range(mini(rx, ax), maxi(rx, ax) + 1):
		s.set_terrain(Vector2i(x, y0 + 1), "grass")
		assert_true(s.place_road(Vector2i(x, y0 + 1)) or s.road_at(Vector2i(x, y0 + 1)) != 0)
	assert_true(s.buildings[d[a]].connected, "depot A is road-connected to the Hearth")
	# Road beside depot B, with a tent next to it; nothing links it to the Hearth by road.
	for x in range(bmid - 1, bmid + 2):
		assert_true(s.place_road(Vector2i(x, y0 + 1)), "road beside B at x=%d" % x)
	var t := s.place_building_instant("tent", Vector2i(bmid, y0 + 2))
	assert_true(t >= 0, "tent placed")
	assert_false(s.buildings[d[b]].connected, "depot B alone is not connected")
	assert_false(s.buildings[t].connected, "the tent is not connected without rail")
	assert_false(rail.connected_via_rail(s, s.hearth.id, t))
	_lay_track(bx - 2, bx + 1)
	assert_true(s.buildings[d[b]].connected, "depot B is connected through the rail")
	assert_true(s.buildings[t].connected, "so is the tent beside B's road")
	assert_true(rail.connected_via_rail(s, s.hearth.id, t), "connected_via_rail agrees")
	assert_eq(rail.depots_reaching(s, t), [d[b]] as Array[int])
	s.remove_track(Vector2i(bx - 1, y0))
	assert_false(s.buildings[t].connected, "cutting the track disconnects it again")
	assert_false(rail.connected_via_rail(s, s.hearth.id, t))
	s.place_track(Vector2i(bx - 1, y0))
	assert_true(s.buildings[t].connected)
	s.demolish(d[a])
	assert_false(s.buildings[t].connected, "losing depot A disconnects it")


func test_track_cost_and_rules() -> void:
	var lg := reg.logistics
	assert_eq(lg.track_cost_materials, 2.0)
	assert_eq(lg.track_cost_cut_stone, 1.0)
	var m0 := float(s.totals()["materials"])
	var c0 := float(s.totals()["cut_stone"])
	assert_true(s.place_track(Vector2i(bx, y0)))
	assert_almost_eq(float(s.totals()["materials"]), m0 - 2.0, 0.001)
	assert_almost_eq(float(s.totals()["cut_stone"]), c0 - 1.0, 0.001)
	assert_eq(s.can_place_track(Vector2i(bx, y0))["reason"], "track", "no double track")
	assert_eq(s.can_place("tent", Vector2i(bx, y0))["reason"], "track", "nor a building")
	assert_eq(s.can_place_channel(Vector2i(bx, y0))["reason"], "track", "nor a channel")
	s.remove_track(Vector2i(bx, y0))
	assert_almost_eq(float(s.totals()["materials"]), m0 - 1.0, 0.001, "half the materials come back")
	# Short of cut stone: refused and nothing spent.
	s.spend_good("cut_stone", float(s.totals()["cut_stone"]))
	assert_eq(s.can_place_track(Vector2i(bx, y0))["reason"], "cut_stone")
	var m1 := float(s.totals()["materials"])
	assert_false(s.place_track(Vector2i(bx, y0)))
	assert_almost_eq(float(s.totals()["materials"]), m1, 0.001)


func test_depot_def_numbers() -> void:
	var def := reg.get_building("rail_depot")
	assert_eq(def.era, "conflux")
	assert_eq(def.size, Vector2i(3, 1))
	assert_eq(def.cost, {"materials": 120, "gold": 60, "cut_stone": 30, "tools": 15})
	assert_eq(def.hauler_slots, 2)
	assert_eq(def.upkeep_lumen, 1.0)


func test_track_survives_save_round_trip() -> void:
	var d := _two_depots()
	_lay_track(bx - 2, bx + 1)
	var s2 := Settlement.from_dict(s.to_dict(), reg)
	assert_not_null(s2)
	assert_eq(s2.track, s.track, "track tiles are saved")
	var rail2: RailSystem = s2.get_system(RailSystem)
	assert_true(rail2.linked(s2, d[0], d[1]), "the link is rebuilt from the loaded track")
	assert_true(s2.track_at(Vector2i(bx, y0)))


# ---- ticket 67: level crossings

func test_track_on_road_is_a_crossing_for_both_layers() -> void:
	var d := _two_depots()
	var t := Vector2i(bx, y0 + 1)  # a road tile beside the track row, then the track runs through it
	_lay_track(bx - 2, bx - 1)
	assert_true(s.place_road(Vector2i(bx, y0)), "a road may cover track")
	assert_true(s.place_road(t))
	assert_true(s.place_road(Vector2i(bx, y0 - 1)))
	var m0 := float(s.totals()["materials"])
	assert_true(s.can_place_track(Vector2i(bx, y0 + 1))["ok"], "track may cross a road")
	assert_true(s.place_track(Vector2i(bx, y0 + 1)))
	assert_almost_eq(float(s.totals()["materials"]), m0 - 2.0, 0.001, "the added layer is charged")
	assert_true(s.track_at(t) and s.road_at(t) > 0, "both layers stay set")
	assert_true(s.place_track(Vector2i(bx + 1, y0)) and s.place_track(Vector2i(bx, y0)))
	assert_true(s.road_at(Vector2i(bx, y0)) > 0 and s.track_at(Vector2i(bx, y0)), "road laid first then track")
	assert_true(rail.linked(s, d[0], d[1]), "a crossing counts as track for the depot link")
	assert_eq(s.can_place_track(Vector2i(bx, y0))["reason"], "track")
	assert_false(s.can_place("tent", t)["ok"], "no building on a crossing")


func test_lifting_one_layer_leaves_the_other() -> void:
	var d := _two_depots()
	_lay_track(bx - 2, bx + 1)
	var t := Vector2i(bx, y0)
	assert_true(s.place_road(t))
	assert_true(s.remove_track(t))
	assert_true(s.road_at(t) > 0, "road stays")
	assert_false(rail.linked(s, d[0], d[1]), "the link breaks with the track gone")
	assert_true(s.place_track(t))
	assert_true(s.remove_road(t))
	assert_true(s.track_at(t), "track stays")
	assert_true(rail.linked(s, d[0], d[1]))
	assert_eq(s.road_at(t), 0)


func test_crossing_keeps_road_connectivity_and_survives_save() -> void:
	var d := _two_depots()
	_lay_track(bx - 2, bx + 1)
	var t := Vector2i(bx, y0)
	for x in range(bx - 1, bx + 2):
		s.place_road(Vector2i(x, y0 + 1))
	assert_true(s.place_road(t))
	assert_true(s.road_at(t) > 0)
	var s2 := Settlement.from_dict(s.to_dict(), reg)
	assert_not_null(s2)
	assert_true(s2.track_at(t) and s2.road_at(t) > 0, "crossing survives the round trip")
	assert_eq(s2.track, s.track)
	assert_eq(s2.roads, s.roads)
	assert_true((s2.get_system(RailSystem) as RailSystem).linked(s2, d[0], d[1]))


func test_crossing_art_in_manifest() -> void:
	var r: Dictionary = ArtLibrary.manifest()["rail"]
	assert_true(r.has("crossing") and r.has("track"), "track and crossing atlases are exported")
	assert_eq(ArtLibrary.track_tileset().get_source_count(), 3, "plain track, crossing and the bridge trestle (ticket 91)")
