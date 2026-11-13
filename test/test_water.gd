extends GutTest
## Ticket 21: water map and irrigation channels (design.md section 9).
##
## WaterSystem rebuilds MapState.wet every day: a tile is wet within WaterDef.wet_radius_water (Chebyshev) of a water
## tile, or within WaterDef.wet_radius_channel of a channel that flows (4-connected to water through channels).
## Channels are dug like roads and stored in Settlement.channels; they block buildings but not walking.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket21_save.dat"

var reg: DataRegistry
var s: Settlement
var _water := PackedByteArray()  # 1 on water terrain, for the test geometry only


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	_water.resize(MapState.WIDTH * MapState.HEIGHT)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			_water[MapState.idx(x, y)] = 1 if s.map.terrain_id_at(x, y) == "water" else 0


func _owned(t: Vector2i) -> bool:
	return s.map.is_region_owned(s.map.get_region(t.x, t.y))


func _no_water_within(t: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := t + Vector2i(dx, dy)
			if MapState.in_bounds(n.x, n.y) and _water[MapState.idx(n.x, n.y)] == 1:
				return false
	return true


## Top-left tile of an owned, empty w x h grass block with no water within `gap` of any of its tiles: a dry stage a
## test can dig a pond and channels on without the real river interfering.
func _dry_block(w: int, h: int, gap: int = 2) -> Vector2i:
	for y in range(0, MapState.HEIGHT - h + 1):
		for x in range(0, MapState.WIDTH - w + 1):
			var ok := true
			for dy in h:
				for dx in w:
					var t := Vector2i(x + dx, y + dy)
					if not _owned(t) or s.map.terrain_id_at(t.x, t.y) != "grass" \
							or s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE \
							or not _no_water_within(t, gap):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## An owned, empty land tile 4-adjacent to water that can take a channel (forest is cleared to grass).
func _shore_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.terrain_id_at(x, y) != "water":
				continue
			var w := Vector2i(x, y)
			for d in Placement.DIRS:
				var c := w + d
				if not MapState.in_bounds(c.x, c.y) or not _owned(c):
					continue
				if s.map.terrain_id_at(c.x, c.y) == "water":
					continue
				if s.building_at(c) != null or s.road_at(c) != Settlement.ROAD_NONE:
					continue
				s.set_terrain(c, "grass")
				if s.can_place_channel(c):
					return c
	return Vector2i(-1, -1)


# AC1: a channel connected to the river flows; a disconnected one does not.
func test_a_channel_dug_beside_the_river_flows() -> void:
	var c := _shore_spot()
	assert_ne(c, Vector2i(-1, -1), "an owned shore tile that can take a channel")
	if c == Vector2i(-1, -1):
		return
	assert_true(s.place_channel(c))
	var flow := WaterSystem.flowing_channels(s)
	assert_eq(flow[MapState.idx(c.x, c.y)], 1, "a channel touching water flows")


# AC1: a flowing channel wets its neighbours on the daily pass; two tiles out stays dry.
func test_connected_channel_wets_its_neighbours() -> void:
	var b := _dry_block(5, 1)
	assert_ne(b, Vector2i(-1, -1), "a dry grass run")
	if b == Vector2i(-1, -1):
		return
	var pond := b
	var c1 := b + Vector2i(1, 0)
	var c2 := b + Vector2i(2, 0)
	var beside := b + Vector2i(3, 0)  # one tile from c2
	var beyond := b + Vector2i(4, 0)  # two from c2, four from the pond
	s.set_terrain(pond, "water")
	assert_true(s.place_channel(c1))
	assert_true(s.place_channel(c2))
	assert_false(s.map.is_wet(beside.x, beside.y), "nothing is wet before the daily pass")
	s.step_days(1)
	assert_true(s.map.is_wet(pond.x, pond.y), "the water tile is wet")
	assert_true(s.map.is_wet(c1.x, c1.y), "the channel touching water is wet")
	assert_true(s.map.is_wet(c2.x, c2.y), "the chain's second channel is wet")
	assert_true(s.map.is_wet(beside.x, beside.y), "one tile from a flowing channel is wet")
	assert_true(s.map.is_wet(beside.x, beside.y + 1), "the channel radius is Chebyshev")
	assert_false(s.map.is_wet(beyond.x, beyond.y), "two tiles from the channel and away from water is dry")


# AC1: a channel that never reaches water stays dry, and so do its neighbours.
func test_a_disconnected_channel_does_not_wet() -> void:
	var b := _dry_block(2, 1, 3)
	assert_ne(b, Vector2i(-1, -1), "a dry grass pair")
	if b == Vector2i(-1, -1):
		return
	var beside := b + Vector2i(1, 0)
	assert_true(s.place_channel(b))
	assert_eq(WaterSystem.flowing_channels(s)[MapState.idx(b.x, b.y)], 0, "not connected to water")
	s.step_days(1)
	assert_false(s.map.is_wet(b.x, b.y), "a dry channel is not wet")
	assert_false(s.map.is_wet(beside.x, beside.y), "nor are its neighbours")


# The map is wet from the first day, not only after the first day hook.
func test_new_game_starts_with_a_wet_map() -> void:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.terrain_id_at(x, y) == "water":
				assert_true(s.map.is_wet(x, y), "water is wet at new game")
				return
	fail_test("the map has no water")


# AC2: the farm wet bonus applies at exactly half a wet footprint and not below it.
func test_farm_wet_bonus_needs_half_the_footprint() -> void:
	var b := _dry_block(2, 2)
	assert_ne(b, Vector2i(-1, -1), "a dry grass 2x2")
	if b == Vector2i(-1, -1):
		return
	var bid := s.place_building_instant("farm", b)
	assert_true(bid >= 0, "farm placed")
	if bid < 0:
		return
	var farm: Building = s.buildings[bid]
	var dry := FertilitySystem.output_modifier(s, farm)
	assert_almost_eq(dry, 0.6, 0.001, "grass fertility only")
	s.map.set_wet(b.x, b.y, true)
	assert_almost_eq(FertilitySystem.output_modifier(s, farm), dry, 0.001, "one wet tile is below half")
	s.map.set_wet(b.x + 1, b.y, true)
	assert_almost_eq(FertilitySystem.output_modifier(s, farm), dry * 1.25, 0.001, "two of four is half")
	s.map.set_wet(b.x, b.y + 1, true)
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 1.25, 0.001, "three of four still gets it")


# AC3: channels block buildings but not walking.
func test_channels_block_buildings_but_not_walking() -> void:
	var b := _dry_block(3, 3)
	assert_ne(b, Vector2i(-1, -1), "a dry grass 3x3")
	if b == Vector2i(-1, -1):
		return
	var c := b + Vector2i(1, 1)
	assert_true(s.place_channel(c))
	assert_eq(s.can_place("tent", c)["reason"], "channel")
	assert_eq(s.place_building_instant("tent", c), -1)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	ws.on_seconds(s, 0.0)  # wires the system to the settlement and builds its grid, as a real step would
	var path := ws.find_path(c + Vector2i(-1, 0), c + Vector2i(1, 0))
	assert_true(path.has(c), "walkers cross a channel tile (a footbridge)")
	assert_gt(ws.tile_speed(c), 0.0, "a channel tile keeps its terrain speed")
	assert_false(s.can_place_road(c), "a road and a channel do not share a tile")
	assert_true(s.remove_channel(c))
	assert_true(s.can_place("tent", c)["ok"], "removing the channel frees the tile")


# Channels are saved with the settlement.
func test_channels_survive_a_save() -> void:
	var b := _dry_block(2, 1)
	assert_ne(b, Vector2i(-1, -1), "a dry grass pair")
	if b == Vector2i(-1, -1):
		return
	assert_true(s.place_channel(b))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	assert_true(loaded.channel_at(b), "the channel came back")
	assert_false(loaded.channel_at(b + Vector2i(1, 0)))
	assert_eq(loaded.channels, s.channels)
