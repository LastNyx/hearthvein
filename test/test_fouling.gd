extends GutTest
## Ticket 29b: river fouling spread (design.md section 9, D42).
## A river tile 4-adjacent to blight is a source; the front moves one river tile downstream per hour until the map
## edge, and a fouled stretch clears two days after the blight that fed it is gone.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket29b_save.dat"

var reg: DataRegistry
var s: Settlement
var _src := Vector2i(-1, -1)  # river tile next to the blight
var _land := Vector2i(-1, -1)  # the blighted land tile
var _path: Array[Vector2i] = []  # src, then its downstream chain


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	assert_true(_find_source(), "the generated river has a land tile beside a downstream run")


## Picks a blightable land tile whose river neighbour has a clear downstream run: the next three river tiles must
## not touch that land tile, so they are not sources themselves and the one-tile-per-hour assertions are exact.
func _find_source() -> bool:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if not s.map.is_river(x, y):
				continue
			var chain := _chain(t, 3)
			if chain.size() < 3:
				continue
			for d in Placement.DIRS:
				var l := t + d
				if not MapState.in_bounds(l.x, l.y) or s.map.terrain_id_at(l.x, l.y) == "water":
					continue
				var clear := true
				for i in range(1, chain.size()):  # the source itself touches the blight by definition
					if _adjacent(chain[i], l):
						clear = false
						break
				if clear:
					_src = t
					_land = l
					_path = chain
					return true
	return false


## The downstream run from `t`, at most `n` tiles.
func _chain(t: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [t]
	var at := t
	for i in n:
		var next := s.map.downstream(at.x, at.y)
		if not MapState.in_bounds(next.x, next.y) or not s.map.is_river(next.x, next.y):
			break
		out.append(next)
		at = next
	return out


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _fouled_count() -> int:
	return s.map.fouled.count(1)


# The numbers are the design's: one river tile per hour, cleared two days after the source.
func test_fouling_numbers_come_from_data() -> void:
	var wd := reg.water
	assert_eq(wd.foul_spread_tiles_per_hour, 1)
	assert_eq(wd.foul_clear_hours, 48)


# AC1: the river tile beside the blight fouls; nothing else does in that first hour.
func test_a_river_tile_next_to_blight_fouls() -> void:
	s.set_blighted(_land, true)
	s.step_hours(1)
	assert_true(s.map.is_fouled(_src.x, _src.y), "the source tile is fouled")
	assert_false(s.map.is_fouled(_path[1].x, _path[1].y), "the front has not moved yet after one hour")
	# Only the river tiles adjacent to the blight are sources.
	var expected := 0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_river(x, y) and _adjacent(Vector2i(x, y), _land):
				expected += 1
	assert_eq(_fouled_count(), expected, "only the sources are fouled")


# AC1: the front moves exactly one downstream tile per hour, never upstream and never two at once.
func test_fouling_travels_downstream_one_tile_per_hour() -> void:
	s.set_blighted(_land, true)
	s.step_hours(1)  # the first hour fouls the source itself
	for i in range(1, _path.size()):
		s.step_hours(1)
		assert_true(s.map.is_fouled(_path[i].x, _path[i].y), "tile %d downstream fouls after %d hours" % [i, i + 1])
		if i + 1 < _path.size():
			assert_false(s.map.is_fouled(_path[i + 1].x, _path[i + 1].y), "tile %d is not fouled yet" % [i + 1])
	# The tile upstream of the source stays clean: fouling never runs against the flow.
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if s.map.is_river(x, y) and s.map.downstream(x, y) == _src:
				assert_false(s.map.is_fouled(x, y), "an upstream river tile stays clean")


# The front keeps going while the blight stays, until it leaves the map at the edge.
func test_the_front_runs_to_the_map_edge() -> void:
	s.set_blighted(_land, true)
	var chain := _chain(_src, MapState.WIDTH + MapState.HEIGHT)
	assert_gt(chain.size(), 3, "the river runs for more than three tiles")
	s.step_hours(chain.size() + 1)
	for i in range(1, chain.size()):
		assert_true(s.map.is_fouled(chain[i].x, chain[i].y), "tile %d of the run is fouled" % i)
	var beyond := s.map.downstream(chain[chain.size() - 1].x, chain[chain.size() - 1].y)
	assert_true(not MapState.in_bounds(beyond.x, beyond.y) or not s.map.is_river(beyond.x, beyond.y),
			"the run ends at the map edge")


# AC2: once the source blight is gone the stretch stops growing, and it clears exactly 48 hours later.
func test_fouling_clears_two_days_after_the_source() -> void:
	s.set_blighted(_land, true)
	s.step_hours(5)
	var spread := _fouled_count()
	assert_gt(spread, 0, "the river fouled while the source was there")
	s.set_blighted(_land, false)
	s.step_hours(47)
	assert_eq(_fouled_count(), spread, "still fouled 47 hours after the source went (and no new tiles)")
	s.step_hours(1)
	assert_eq(_fouled_count(), 0, "cleared 48 hours after the source went")


# Removing the source early stops the spread at once instead of letting the stretch grow for two days.
func test_no_spread_after_the_source_is_gone() -> void:
	s.set_blighted(_land, true)
	s.step_hours(2)
	s.set_blighted(_land, false)
	var reached := _fouled_count()
	s.step_hours(20)
	assert_eq(_fouled_count(), reached, "the front did not advance after the blight was removed")


# The countdown is runtime state: a save mid-spread resumes it, and the fouled map comes back with the save.
func test_fouling_survives_a_save() -> void:
	s.set_blighted(_land, true)
	s.step_hours(3)
	s.set_blighted(_land, false)
	s.step_hours(10)  # part-way through the 48-hour countdown
	assert_gt(_fouled_count(), 0)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	assert_eq(loaded.map.fouled, s.map.fouled, "the fouled tiles came back")
	s.step_hours(38)
	loaded.step_hours(38)
	assert_eq(loaded.map.fouled, s.map.fouled, "the countdown resumed where it was saved")
	s.step_hours(2)
	loaded.step_hours(2)
	assert_eq(loaded.map.fouled, s.map.fouled, "and keeps counting at the same pace")
