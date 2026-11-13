extends GutTest
## Ticket 18: 600 citizens stay cheap (design.md section 21, D46).
## Ticket 55: no commute tick above 8 ms and batched prop drawing.

const SEED := 42
## Game seconds in one frame at 1x, 60 fps (one game hour is 2.5 game seconds).
const CHUNK := GameClock.REAL_SECONDS_PER_HOUR / 150.0

var s: Settlement
var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()
	s = PerfFixture.build(reg, SEED, 600)


func test_fixture_has_600_housed_working_citizens() -> void:
	assert_eq(s.citizens.size(), 600)
	assert_eq(s.homeless_count(), 0)
	assert_eq(s.idle_citizens().size(), 0, "every citizen has a job")


func test_one_day_of_600_citizens_under_two_seconds() -> void:
	s.step_hours(5)  # up to 05:00 so the day below holds both commutes
	var t0 := Time.get_ticks_usec()
	s.step_hours(GameClock.HOURS_PER_DAY)
	var sec := (Time.get_ticks_usec() - t0) / 1e6
	print("PERF one in-game day, 600 citizens, step_hours(24): %.3f s" % sec)
	assert_lt(sec, 2.0, "one in-game day of 600 citizens steps in under 2 s")


func test_frame_sized_steps_stay_cheap_over_the_morning_commute() -> void:
	var guard := 0
	while s.clock.hour() != 5 and guard < 48:
		s.step_hours(1)
		guard += 1
	var frames := 150  # one game hour at 1x in 1/60 s frames
	var t0 := Time.get_ticks_usec()
	for i in frames:
		s.step_seconds(GameClock.REAL_SECONDS_PER_HOUR / frames)
	s.step_hours(1)
	var per_call_ms := (Time.get_ticks_usec() - t0) / 1000.0 / (frames + 1)
	print("PERF commute hour 05-07, %d frame steps: %.2f ms per step_seconds call" % [frames + 1, per_call_ms])
	assert_lt(per_call_ms, 12.0, "a sim step must fit well inside a 16 ms frame")


func test_walkers_hidden_only_at_the_farthest_zoom() -> void:
	assert_false(WalkerView.shown_at_zoom(CameraController.ZOOM_STEPS[0]), "farthest step hides walkers")
	for i in range(1, CameraController.ZOOM_STEPS.size()):
		assert_true(WalkerView.shown_at_zoom(CameraController.ZOOM_STEPS[i]), "step %d shows walkers" % i)
	assert_true(CameraController.is_farthest_zoom(CameraController.ZOOM_STEPS[0]))
	assert_false(CameraController.is_farthest_zoom(CameraController.ZOOM_STEPS[1]))


# ---------------------------------------------------------------- ticket 55: commute spikes
func _world() -> Settlement:
	return PerfFixture.build(reg, SEED, 600)


func _to_hour(world: Settlement, hour: int) -> void:
	var guard := 0
	while world.clock.hour() != hour and guard < 96:
		world.step_hours(1)
		guard += 1


## Worst single step_seconds tick between two hours, in ms. Frame-sized chunks, like the game at 1x.
func _worst_tick(world: Settlement, from_hour: int, to_hour: int) -> float:
	_to_hour(world, from_hour)
	var worst := 0.0
	var guard := 0
	while world.clock.hour() != to_hour and guard < 2000:
		var t0 := Time.get_ticks_usec()
		world.step_seconds(CHUNK)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		guard += 1
	return worst


func test_no_sim_tick_above_eight_ms_at_either_commute() -> void:
	var world := _world()
	var morning := _worst_tick(world, 5, 9)
	print("PERF worst tick at the 06:00 commute: %.2f ms" % morning)
	assert_lt(morning, 8.0, "no morning-commute tick above 8 ms with 600 citizens")
	var evening := _worst_tick(world, 17, 21)
	print("PERF worst tick at the 18:00 commute: %.2f ms" % evening)
	assert_lt(evening, 8.0, "no evening-commute tick above 8 ms with 600 citizens")


## Everyone with a job leaves home inside the hour before the shift (05:00-06:00), spread over many ticks, and the ones whose whole
## commute fits in two game hours are at work by then (perf_fixture walk times are up to 16 game hours, so the
## fixture cannot assert everybody does; see the ticket Result).
func test_departures_are_staggered_over_the_first_game_hour() -> void:
	var world := _world()
	var ws := world.get_system(WalkerSystem) as WalkerSystem
	_to_hour(world, 5)
	assert_eq(world.clock.hour(), 5, "reached 05:00")
	var at_home := {}  # standing at home when the workday starts: their walk starts at the home door
	for id in ws.walkers:
		var c0: Citizen = world.citizens[id]
		var w0: Walker = ws.walkers[id]
		if c0.job_id >= 0 and c0.home_id >= 0 and w0.path.is_empty() and w0.at_building == c0.home_id:
			at_home[id] = true
	var depart: Dictionary = {}  # citizen id -> seconds into hour 5 when the walk to work started
	var frames := 0
	while world.clock.hour() == 5 and frames < 400:
		world.step_seconds(CHUNK)
		frames += 1
		var elapsed := float(frames) * CHUNK
		for id in ws.walkers:
			if depart.has(id):
				continue
			var w: Walker = ws.walkers[id]
			var c: Citizen = world.citizens[id]
			if c.job_id >= 0 and w.dest_building == c.job_id:  # rerouted from wherever it was to the job
				depart[id] = elapsed
	assert_eq(depart.size(), world.citizens.size(), "everyone with a job left home in the first game hour")
	var first := INF
	var last := 0.0
	var ticks := {}
	for id in depart:
		first = minf(first, depart[id])
		last = maxf(last, depart[id])
		ticks[int(depart[id] / CHUNK)] = true
	print("PERF departures: first %.2f s, last %.2f s, %d different ticks" % [first, last, ticks.size()])
	assert_lt(first, 0.2, "somebody leaves at once")
	assert_gt(last, GameClock.REAL_SECONDS_PER_HOUR * 0.7, "departures spread over most of the hour")
	assert_gte(ticks.size(), 100, "departures do not clump into a few ticks")

	# Two game hours after 05:00, everyone whose offset + walk fits has arrived.
	_to_hour(world, 7)
	assert_eq(world.clock.hour(), 7, "reached 07:00")
	var qualify := {}
	for id in at_home:
		var c: Citizen = world.citizens[id]
		var p := ws.find_path(ws.door_tile(world.buildings[c.home_id]), ws.door_tile(world.buildings[c.job_id]))
		if p.is_empty():
			continue
		var need := ws.path_seconds(p) + WalkerSystem.depart_offset(world.map.seed_used, id)
		if need <= 2.0 * GameClock.REAL_SECONDS_PER_HOUR - 4.0 * CHUNK:  # frame-sized departure slack
			qualify[id] = true
	var late: Array = []
	for id in qualify:
		if not ws.is_at_work(id):
			late.append(id)
	print("PERF %d of 600 started at home with a two-hour commute; %d late" % [qualify.size(), late.size()])
	assert_gt(qualify.size(), 2, "the fixture has some two-hour commutes from home")
	assert_eq(late, [], "short commutes still arrive at work within two game hours")


# ---------------------------------------------------------------- ticket 55: batched props
func _mapview() -> MapView:
	var map := MapGen.generate(SEED, reg)
	var v := MapView.new()
	add_child_autofree(v)
	v.setup(map)
	return v


func test_prop_batch_matches_the_old_per_sprite_count() -> void:
	var v := _mapview()
	var expected := 0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			expected += ArtLibrary.scatter(v.map.terrain_id_at(x, y), x, y, PropBatch.open_dir(v.map, x, y)).size()
	print("PERF props: %d instances in %d bands" % [v._prop_batch.prop_count(), v._prop_batch.band_count()])
	assert_gt(expected, 1000, "the map has thousands of props")
	assert_eq(v._prop_batch.prop_count(), expected, "every scattered prop is one batched instance")
	assert_lt(v._prop_batch.band_count(), expected / 2, "props are batched, not one node per sprite")


## World-space sprite centre of a prop record, the Transform2D origin a Sprite2D would give it.
func _prop_center(p: Dictionary) -> Vector2:
	var e := ArtLibrary.prop_entry(p["name"])
	return Vector2(p["pos"]) - Vector2(e["base"][0], e["base"][1]) + Vector2(e["w"], e["h"]) * 0.5


## Headless runs use the dummy renderer, which keeps no MultiMesh instance data, so read the transforms PropBatch
## pushed (band_transforms) and the node's own position.
func _has_instance(v: MapView, prop_name: String, center: Vector2) -> bool:
	for key in v._prop_batch._bands:
		var inst: MultiMeshInstance2D = v._prop_batch._bands[key]
		var xs := v._prop_batch.band_transforms(key)
		var names := v._prop_batch.band_names(key)
		for i in xs.size():
			if names[i] == prop_name and (inst.position + (xs[i] as Transform2D).origin).is_equal_approx(center):
				return true
	return false


func _band_snapshot(v: MapView) -> Array:
	var out: Array = []
	for key in v._prop_batch._bands:
		var inst: MultiMeshInstance2D = v._prop_batch._bands[key]
		var xs: Array = v._prop_batch.band_transforms(key).duplicate()
		assert_eq(inst.multimesh.instance_count, xs.size(), "band %d uploads every transform it keeps" % key)
		out.append([key, inst.position.y, xs])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


func test_refresh_tile_updates_the_batched_instance_data() -> void:
	var v := _mapview()
	var tile := Vector2i(-1, -1)
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 2):
			if v.map.terrain_id_at(x, y) == "forest" and v.map.terrain_id_at(x, y + 1) != "forest" \
					and ArtLibrary.scatter("forest", x, y, PropBatch.open_dir(v.map, x, y)).size() > 0:
				tile = Vector2i(x, y)
				break
		if tile.x >= 0:
			break
	assert_gt(tile.x, -1, "found a forest tile with trees")
	var old_props := ArtLibrary.scatter("forest", tile.x, tile.y, PropBatch.open_dir(v.map, tile.x, tile.y))
	var before := _band_snapshot(v)
	var before_count := v._prop_batch.prop_count()
	v.map.set_terrain(tile.x, tile.y, v.map.terrain_index("stump"))
	v.refresh_tile(tile)
	assert_ne(_band_snapshot(v), before, "refresh_tile changed the batched instance data")
	assert_eq(v._prop_batch.prop_count(), before_count - old_props.size() + 1, "trees gone, one stump added")
	var stump := ArtLibrary.scatter("stump", tile.x, tile.y, PropBatch.open_dir(v.map, tile.x, tile.y))
	assert_eq(stump.size(), 1, "a stump scatters exactly one prop")
	assert_true(_has_instance(v, stump[0]["name"], _prop_center(stump[0])),
			"the stump is in the batch")
	for p in old_props:
		assert_false(_has_instance(v, p["name"], _prop_center(p)),
				"the felled %s is gone from the batch" % p["name"])


func test_set_props_visible_updates_the_batch() -> void:
	var v := _mapview()
	var tile := Vector2i(-1, -1)
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 2):
			if v.map.terrain_id_at(x, y) == "forest" and ArtLibrary.scatter("forest", x, y, PropBatch.open_dir(v.map, x, y)).size() > 0:
				tile = Vector2i(x, y)
				break
		if tile.x >= 0:
			break
	assert_gt(tile.x, -1)
	var n := ArtLibrary.scatter("forest", tile.x, tile.y, PropBatch.open_dir(v.map, tile.x, tile.y)).size()
	var total := v._prop_batch.prop_count()
	v.set_props_visible(tile, false)
	assert_true(v._prop_batch.is_hidden(tile), "road/building hides the tile's props")
	assert_eq(v._prop_batch.prop_count(), total - n, "batched instances of the tile are gone")
	for node in v._props.get(tile, []):
		assert_false((node as CanvasItem).visible, "the tile's shadows and glows are hidden too")
	v.set_props_visible(tile, true)
	assert_eq(v._prop_batch.prop_count(), total, "props come back")



# ---------------------------------------------------------------- ticket 57: production cadence
func test_batched_production_matches_per_frame_within_one_percent() -> void:
	var fast := _world()
	var exact := _world()
	(exact.get_system(ProductionSystem) as ProductionSystem).batch_seconds = 0.0
	for w in [fast, exact]:
		_to_hour(w, 5)
		for i in int(GameClock.HOURS_PER_DAY * 150):
			w.step_seconds(CHUNK)
	var a := (fast.get_system(ProductionSystem) as ProductionSystem).produced_total
	var b := (exact.get_system(ProductionSystem) as ProductionSystem).produced_total
	print("PERF one game day of production: batched %.2f, per frame %.2f" % [a, b])
	assert_gt(b, 10.0, "the fixture produces something")
	assert_almost_eq(a, b, b * 0.01, "daily totals within 1%")


# ---------------------------------------------------------------- ticket 57b: far-zoom draw items
## Draw items a map view issues at the farthest zoom, counted from its nodes (the headless dummy renderer reports 0
## draw calls): batched prop bands, visible object and glow sprites, and the texture runs of the Base layer's
## 16x16-tile quadrants read in row order (every change of atlas source breaks a batch).
func _base_runs(v: MapView) -> int:
	var runs := 0
	var q := 16
	for qy in range(0, MapState.HEIGHT, q):
		for qx in range(0, MapState.WIDTH, q):
			var last := -2
			for y in range(qy, mini(qy + q, MapState.HEIGHT)):
				for x in range(qx, mini(qx + q, MapState.WIDTH)):
					var src := v._base.get_cell_source_id(Vector2i(x, y))
					if src != last:
						runs += 1
						last = src
	return runs


func test_far_zoom_draw_items_at_least_halve() -> void:
	var v := _mapview()
	# Before 57b: one multimesh per (texture, base row), and one atlas source per terrain id in Base.
	var old_bands := {}
	var old_runs := 0
	var ids: Array[String] = ArtLibrary.terrain_ids()
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			for p in ArtLibrary.scatter(v.map.terrain_id_at(x, y), x, y, PropBatch.open_dir(v.map, x, y)):
				old_bands[[p["name"], floori(p["pos"].y / float(ArtLibrary.TILE))]] = true
	var q := 16
	for qy in range(0, MapState.HEIGHT, q):
		for qx in range(0, MapState.WIDTH, q):
			var last := -2
			for y in range(qy, mini(qy + q, MapState.HEIGHT)):
				for x in range(qx, mini(qx + q, MapState.WIDTH)):
					var src := ids.find(v.map.terrain_id_at(x, y))
					if src != last:
						old_runs += 1
						last = src
	var before := old_bands.size() + old_runs
	var after := v._prop_batch.band_count() + _base_runs(v)
	print("PERF far-zoom map draw items: before %d (%d prop bands + %d base runs), after %d (%d + %d)" % [
			before, old_bands.size(), old_runs, after, v._prop_batch.band_count(), _base_runs(v)])
	assert_lte(after * 2, before, "at least halved")


func test_props_of_different_textures_are_strictly_y_sorted_within_a_band() -> void:
	var v := _mapview()
	var checked := 0
	for key in v._prop_batch.band_rows():
		var xs := v._prop_batch.band_transforms(key)
		var names := v._prop_batch.band_names(key)
		var inst: MultiMeshInstance2D = v._prop_batch._bands[key]
		var last := -INF
		for i in xs.size():
			var e := ArtLibrary.prop_entry(names[i])
			# base y = sprite centre y + (base_y - h/2)
			var by: float = inst.position.y + (xs[i] as Transform2D).origin.y + float(e["base"][1]) - float(e["h"]) * 0.5
			assert_gte(by, last - 0.001, "band %d instance %d is not behind an earlier one" % [key, i])
			last = by
			checked += 1
	assert_gt(checked, 1000)


# ---------------------------------------------------------------- ticket 57c: hour and day boundary
## Milliseconds each system's hook takes when called directly on a world that stands at 05:00 (probe numbers).
func _hook_ms(world: Settlement, hook: String) -> Dictionary:
	var out := {}
	for sys in world.systems:
		var t0 := Time.get_ticks_usec()
		sys.call(hook, world)
		out[sys.get_script().get_global_name()] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


func test_hour_and_day_hooks_cost() -> void:
	var world := _world()
	_to_hour(world, 5)
	for i in 30:
		world.step_seconds(CHUNK)
	var hour := _hook_ms(world, "on_hour")
	var day := _hook_ms(world, "on_day")
	print("PERF on_hour ms per system: %s" % [hour])
	print("PERF on_day ms per system: %s" % [day])
	var h := 0.0
	var d := 0.0
	for k in hour:
		h += hour[k]
	for k in day:
		d += day[k]
	print("PERF on_hour total %.2f ms, on_day total %.2f ms" % [h, d])
	assert_lt(h, 8.0, "all on_hour hooks together under 8 ms")
	assert_lt(d, 8.0, "all on_day hooks together under 8 ms")


## Worst frame-sized step_seconds call that crosses an hour boundary, and the worst one that crosses midnight.
func test_boundary_frames_under_eight_ms() -> void:
	var world := _world()
	_to_hour(world, 4)
	var worst_hour := 0.0
	var worst_day := 0.0
	var worst_plain := 0.0
	var frames := 0
	while frames < 150 * 52:  # a bit over two game days
		var h0 := world.clock.total_hours
		var t0 := Time.get_ticks_usec()
		world.step_seconds(CHUNK)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if world.clock.total_hours != h0:
			if world.clock.is_day_start():
				worst_day = maxf(worst_day, ms)
			else:
				worst_hour = maxf(worst_hour, ms)
		else:
			worst_plain = maxf(worst_plain, ms)
		frames += 1
	print("PERF worst frame: hour end %.2f ms, day end %.2f ms, no boundary %.2f ms" % [worst_hour, worst_day, worst_plain])
	assert_lt(worst_hour, 8.0, "the frame that ends an hour")
	assert_lt(worst_day, 8.0, "the frame that ends a day")


class DayCounter extends SimSystem:
	var days := 0
	var seasons := 0

	func on_day(_s: Settlement) -> void:
		days += 1

	func on_season(_s: Settlement) -> void:
		seasons += 1


## Frame-sized steps spread the day hooks over the following steps; coarse steps and flush_deferred run them at once.
func test_day_hooks_spread_over_frames_and_flush_on_demand() -> void:
	var world := _world()
	var counter := DayCounter.new()
	world.add_system(counter)  # last: runs after every default system's day hook
	_to_hour(world, 23)
	var guard := 0
	while not world.clock.is_day_start() and guard < 1000:
		world.step_seconds(CHUNK)
		guard += 1
	assert_true(world.clock.is_day_start(), "crossed midnight")
	assert_eq(counter.days, 0, "the frame that ends the day has not run the day hooks of the last system yet")
	var frames := 0
	while counter.days == 0 and frames < 100:
		world.step_seconds(CHUNK)
		frames += 1
	print("PERF the last day hook ran %d frames after midnight" % frames)
	assert_eq(counter.days, 1, "day hook ran once")
	assert_lte(frames, world.systems.size() + 2, "all day work done within a few frames")
	# Same again, flushed at once.
	_to_hour(world, 23)
	while not world.clock.is_day_start() and guard < 2000:
		world.step_seconds(CHUNK)
		guard += 1
	world.flush_deferred()
	assert_eq(counter.days, 2, "flush_deferred runs what is pending")
	world.step_seconds(GameClock.REAL_SECONDS_PER_HOUR * 24.0)  # a coarse step: no hook is left pending
	assert_eq(counter.days, 3)
