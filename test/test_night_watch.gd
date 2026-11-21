extends GutTest
## Ticket 143: the Night Watch (spec .scratch/v1/night-shift-spec.md N10).
##
## A Village night building whose one night worker walks the roads within 8 tiles in a loop. Those patrolled tiles
## count as lit (radius 1) for the night, so small night buildings on the route work without a lamp. It burns one
## charcoal a night; with no fuel or no worker the route stays dark.

const SEED := 42

var reg: DataRegistry
var _small_town_pop: int = 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the night fill, not the small-town first-hand rule, is under test


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


## A fresh settlement with the growth system off and a clear road strip east of the Hearth (x +2 .. +21).
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 22):
		for y in range(hs.y - 4, hs.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places `id` with its footprint at `origin` and returns the building.
func _put(s: Settlement, id: String, origin: Vector2i) -> Building:
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	return s.buildings.get(bid)


## Steps the clock to `hour` (0-23) the same day or the next one.
func _step_to(s: Settlement, hour: int) -> void:
	s.step_hours(posmod(hour - s.clock.hour(), 24))


func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Citizens working `b`'s night shift.
func _night_workers(s: Settlement, b: Building) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK and c.shift == Citizen.SHIFT_NIGHT:
			n += 1
	return n


## Criterion 1: the patrol route is every road tile within 8 tiles of the building, the same on every call.
func test_patrol_route_is_the_road_tiles_within_8_deterministic() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var watch := _put(s, "night_watch", Vector2i(hs.x + 4, hs.y - 1))
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var route := ws.patrol_route(s, watch)
	# The roads run along y = hs.y from hs.x + 2 eastwards; within 8 tiles of the watch (Chebyshev) that is
	# hs.x + 2 .. hs.x + 12, in a stable y then x order.
	var expected: Array[Vector2i] = []
	for x in range(hs.x + 2, hs.x + 13):
		expected.append(Vector2i(x, hs.y))
	assert_eq(route, expected, "route = the road tiles within 8")
	assert_false(route.has(Vector2i(hs.x + 13, hs.y)), "a road 9 tiles away is off the route")
	assert_eq(ws.patrol_route(s, watch), expected, "the same roads give the same route")


## Criterion 2: with a night worker and charcoal the route and the tiles beside it are lit from dusk; a small night
## building on the route works without a lamp; with no fuel or no worker nothing is lit.
func test_route_tiles_lit_radius_1_at_night_when_staffed_and_fuelled() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var watch := _put(s, "night_watch", Vector2i(hs.x + 4, hs.y - 1))
	watch.input_buffer.add("charcoal", 2.0)  # a full buffer: two nights of patrol fuel
	_keep_citizens(s, 4)
	var road := Vector2i(hs.x + 4, hs.y)
	_step_to(s, 12)
	assert_false(s.is_tile_lit(road), "nothing lit by day")
	_step_to(s, 21)
	assert_eq(_night_workers(s, watch), 1, "the watch is staffed")
	assert_almost_eq(watch.input_buffer.amount_of("charcoal"), 1.0, 0.001, "one charcoal burnt for the night")
	assert_true(s.is_tile_lit(road), "a patrolled road tile is lit")
	assert_true(s.is_tile_lit(Vector2i(hs.x + 4, hs.y + 1)), "radius 1: the tile beside the route is lit")
	assert_false(s.is_tile_lit(Vector2i(hs.x + 4, hs.y + 2)), "two tiles off the route is dark")
	# A small night building beside the route is lit by the walker, so its night slots open without a lamp.
	var kiln := _put(s, "charcoal_kiln", Vector2i(hs.x + 8, hs.y - 2))
	assert_true(s.is_lit(kiln), "a Kiln beside the route is lit without a lamp")
	# No charcoal: the watch does not walk and nothing is lit.
	var dry := _new_settlement()
	var dhs := dry.map.hearth_spot
	var dry_watch := _put(dry, "night_watch", Vector2i(dhs.x + 4, dhs.y - 1))
	_keep_citizens(dry, 4)
	_step_to(dry, 21)
	assert_almost_eq(dry_watch.input_buffer.amount_of("charcoal"), 0.0, 0.001, "no charcoal to burn")
	assert_false(dry.is_tile_lit(Vector2i(dhs.x + 4, dhs.y)), "no fuel, no light")
	# No worker: the charcoal stays in the buffer and nothing is lit.
	var alone := _new_settlement()
	var ahs := alone.map.hearth_spot
	var alone_watch := _put(alone, "night_watch", Vector2i(ahs.x + 4, ahs.y - 1))
	alone_watch.input_buffer.add("charcoal", 2.0)
	_keep_citizens(alone, 0)
	_step_to(alone, 21)
	assert_eq(_night_workers(alone, alone_watch), 0, "nobody works the watch")
	assert_almost_eq(alone_watch.input_buffer.amount_of("charcoal"), 2.0, 0.001, "nothing burnt")
	assert_false(alone.is_tile_lit(Vector2i(ahs.x + 4, ahs.y)), "no staff, no light")


## Ticket 164: NightRenderModel.lantern_walkers lists a watch only at night, staffed and fuelled, with the very route
## the sim lights; by day, unstaffed or with no charcoal it is empty.
func test_lantern_walkers_model_by_day_unstaffed_unfuelled_and_lit() -> void:
	var s := _new_settlement()
	var hs := s.map.hearth_spot
	var watch := _put(s, "night_watch", Vector2i(hs.x + 4, hs.y - 1))
	watch.input_buffer.add("charcoal", 2.0)
	_keep_citizens(s, 4)
	_step_to(s, 12)
	assert_eq(NightRenderModel.lantern_walkers(s), [], "nobody walks by day")
	_step_to(s, 21)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var walkers := NightRenderModel.lantern_walkers(s)
	assert_eq(walkers.size(), 1, "one lit watch, one lantern walker")
	assert_eq(walkers[0]["id"], watch.id)
	assert_eq(walkers[0]["route"], ws.patrol_route(s, watch), "the route is the one the sim lights")
	# No charcoal: the watch stays in.
	var dry := _new_settlement()
	var dhs := dry.map.hearth_spot
	_put(dry, "night_watch", Vector2i(dhs.x + 4, dhs.y - 1))
	_keep_citizens(dry, 4)
	_step_to(dry, 21)
	assert_eq(NightRenderModel.lantern_walkers(dry), [], "no fuel, no lantern")
	# No worker: the charcoal is kept, nobody walks.
	var alone := _new_settlement()
	var ahs := alone.map.hearth_spot
	var alone_watch := _put(alone, "night_watch", Vector2i(ahs.x + 4, ahs.y - 1))
	alone_watch.input_buffer.add("charcoal", 2.0)
	_keep_citizens(alone, 0)
	_step_to(alone, 21)
	assert_eq(NightRenderModel.lantern_walkers(alone), [], "no staff, no lantern")
