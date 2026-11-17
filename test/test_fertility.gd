extends GutTest
## Ticket 20b: soil fertility wear and recovery (design.md section 9).
##
## Rates come from data/soil/soil.tres: a working Farm wears its footprint 1 point a season (4 a year), a fallow
## tile regains 2.5 a season (10 a year) up to the fertility its terrain started with.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket20b_save.dat"

var reg: DataRegistry
var s: Settlement
var h: Vector2i
var fs: FertilitySystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	h = s.map.hearth_spot
	fs = s.get_system(FertilitySystem) as FertilitySystem
	assert_not_null(fs, "a new game registers the FertilitySystem")


## A cleared, road-connected strip east of the Hearth (the patch test_village_farm uses), so a Farm there is
## connected and gets workers.
func _strip() -> void:
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## A finished, staffed Farm with the four footprint tiles' fertilities in row-major order. Its origin sits north
## (side -1) or south (side 1) of the strip road.
func _farm(side: int, fertilities: Array) -> Building:
	var o := Vector2i(h.x + 4, h.y - 2 if side < 0 else h.y + 1)
	var i := 0
	for y in 2:
		for x in 2:
			var t := o + Vector2i(x, y)
			s.set_terrain(t, "grass")
			s.map.set_fertility(t.x, t.y, int(fertilities[i]))
			i += 1
	var bid := s.place_building_instant("farm", o)
	assert_true(bid >= 0, "farm placed at %s" % o)
	return s.buildings.get(bid)


func _workers(bid: int) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == bid and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


## A grass tile away from the strip roads and buildings, for the fallow cases.
func _fallow() -> Vector2i:
	var tile := h + Vector2i(0, 8)
	s.set_terrain(tile, "grass")
	assert_null(s.building_at(tile), "the fallow tile is free")
	return tile


# AC1a: a working Farm wears its footprint 4 points a year (-1 a season).
func test_working_farm_wears_one_point_a_season() -> void:
	_strip()
	var farm := _farm(1, [60, 60, 60, 60])
	assert_gt(_workers(farm.id), 0, "the farm is staffed")
	fs.on_season(s)
	for t in farm.tiles():
		assert_almost_eq(fs.fertility_at(s, t), 59.0, 0.001, "one season of wear at %s" % t)
	for i in 3:
		fs.on_season(s)
	for t in farm.tiles():
		assert_almost_eq(fs.fertility_at(s, t), 56.0, 0.001, "a year of wear at %s" % t)


# AC1b: a fallow tile recovers 10 points a year (+2.5 a season), capped at its start value.
func test_fallow_recovers_to_its_start_value() -> void:
	var tile := _fallow()
	s.map.set_fertility(tile.x, tile.y, 50)
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, tile), 52.5, 0.001, "half a point above the byte survives in quarters")
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, tile), 55.0, 0.001)
	for i in 4:
		fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, tile), 60.0, 0.001, "grass starts at 60 and never recovers past it")
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, tile), 60.0, 0.001)


# AC1c: the season hook fires once per season through the normal step seam.
func test_one_season_of_steps_applies_one_season_of_drift() -> void:
	_strip()
	var tile := _fallow()
	s.map.set_fertility(tile.x, tile.y, 50)
	var farm := _farm(1, [100, 100, 100, 100])
	s.step_hours(GameClock.HOURS_PER_DAY * GameClock.DAYS_PER_SEASON)
	assert_almost_eq(fs.fertility_at(s, tile), 52.5, 0.001, "one fallow season")
	for t in farm.tiles():
		assert_almost_eq(fs.fertility_at(s, t), 99.0, 0.001, "one season of wear at %s" % t)


# A Farm with no workers is fallow land: its tiles recover instead of wearing.
func test_unstaffed_farm_is_fallow() -> void:
	_strip()
	var farm := _farm(1, [60, 60, 60, 60])
	s.map.set_fertility(farm.origin.x, farm.origin.y, 50)
	assert_true(s.set_building_priority(farm.id, "paused"))
	assert_eq(_workers(farm.id), 0, "a paused farm keeps no workers")
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, farm.origin), 52.5, 0.001)


# AC2: a blighted tile's fertility counts half in the Farm's output.
func test_blighted_tiles_count_half_in_farm_output() -> void:
	_strip()
	var farm := _farm(1, [60, 60, 60, 60])
	assert_almost_eq(FertilitySystem.output_modifier(s, farm), 0.6, 0.001, "60 fertility, plain grass origin")
	for t in farm.tiles():
		s.set_blighted(t, true)
	assert_almost_eq(FertilitySystem.output_modifier(s, farm), 0.3, 0.001, "blight halves every tile")
	s.set_blighted(farm.tiles()[0], false)
	assert_almost_eq(FertilitySystem.output_modifier(s, farm), 0.375, 0.001, "three half tiles and one whole")


# Terraced Farm (design.md section 9): tier III stops the yearly loss.
func test_terraced_farm_stops_the_loss() -> void:
	_strip()
	var farm := _farm(1, [60, 60, 60, 60])
	assert_true(reg.get_building("farm").tiers[1].stops_fertility_loss, "the tier III data carries the rule")
	farm.tier = 3
	fs.on_season(s)
	for t in farm.tiles():
		assert_almost_eq(fs.fertility_at(s, t), 60.0, 0.001, "no loss at tier III")
	s.map.set_fertility(farm.origin.x, farm.origin.y, 55)
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, farm.origin), 55.0, 0.001, "a working terrace holds its worn soil")
	farm.tier = 1
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, farm.origin), 54.0, 0.001)


# The quarter points are saved: a reloaded settlement resumes a half-point season exactly.
func test_quarter_points_survive_a_save() -> void:
	var tile := _fallow()
	s.map.set_fertility(tile.x, tile.y, 50)
	fs.on_season(s)
	assert_almost_eq(fs.fertility_at(s, tile), 52.5, 0.001)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	var lfs := loaded.get_system(FertilitySystem) as FertilitySystem
	assert_not_null(lfs)
	assert_almost_eq(lfs.fertility_at(loaded, tile), 52.5, 0.001, "the half point came back")
