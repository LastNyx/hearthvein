extends GutTest
## Ticket 151: Dim blooms, glow river and starlight (spec .scratch/v1/night-shift-spec.md N8, N10).
##
## A Glowcap Grove makes double food in a Dimming (stacking with the new moon's +25%) and another +25% while it stands
## within two tiles of the glowing river. In a Dimming the river tiles count as lit radius 1 at night and the render
## model lists a speck per river tile. A staffed Observatory night crew catches 1 starlight a night in a Dimming, and
## starlight covers light need at 5 Lumen each.

const SEED := 42

var reg: DataRegistry
var _small_town_pop := 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the slots under test, not the small-town first-hand rule


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


## A fresh settlement with the growth system off, every region owned and a road strip east of the Hearth with clear
## land north of it.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	var hs := s.map.hearth_spot
	for x in range(hs.x + 2, hs.x + 22):
		for y in range(hs.y - 5, hs.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		if s.road_at(Vector2i(x, hs.y)) == Settlement.ROAD_NONE:
			s.place_road(Vector2i(x, hs.y))
	return s


## Places a finished building on the north side of the road strip, `dx` tiles east of the Hearth.
func _put(s: Settlement, id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var hs := s.map.hearth_spot
	var at := Vector2i(hs.x + dx, hs.y - def.size.y)
	var why := s.can_place(id, at, true)
	var bid := s.place_building_instant(id, at)
	assert_true(bid >= 0, "%s placed at %s: %s" % [id, at, why])
	return s.buildings.get(bid)


## A regular Dimming starting today for `length` days (the fixture the systems read; no stepping needed).
func _dimming(s: Settlement, length: int = 4) -> void:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	d._start_day = s.clock.total_days()
	d._length = length
	d._active = true


## Puts the clock at `total_days` days plus `hour` (not stepping the sim, so no hooks run).
func _set_day(s: Settlement, total_days: int, hour: int) -> void:
	s.clock.total_hours = total_days * GameClock.HOURS_PER_DAY + hour


## Citizens in a `kind` job at `b` on the night shift.
func _night_crew(s: Settlement, b: Building) -> Array:
	var out: Array = []
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK and c.shift == Citizen.SHIFT_NIGHT:
			out.append(c)
	return out


# ---------------------------------------------------------------- map helpers

func _land(s: Settlement, t: Vector2i) -> bool:
	if not MapState.in_bounds(t.x, t.y) or s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE:
		return false
	var tid := s.map.terrain_id_at(t.x, t.y)
	var td := reg.get_terrain(tid)
	return td != null and td.buildable and tid != "water" and not s.map.is_river(t.x, t.y)


func _footprint_ok(s: Settlement, origin: Vector2i) -> bool:
	for y in range(origin.y, origin.y + 2):
		for x in range(origin.x, origin.x + 2):
			if not _land(s, Vector2i(x, y)):
				return false
	return true


## True when a river tile lies within `r` tiles (Euclidean) of `t`.
func _near_river(s: Settlement, t: Vector2i, r: int) -> bool:
	for y in range(t.y - r, t.y + r + 1):
		for x in range(t.x - r, t.x + r + 1):
			if MapState.in_bounds(x, y) and s.map.is_river(x, y) \
					and (x - t.x) * (x - t.x) + (y - t.y) * (y - t.y) <= r * r:
				return true
	return false


func _footprint_near_river(s: Settlement, origin: Vector2i, r: int) -> bool:
	for y in range(origin.y, origin.y + 2):
		for x in range(origin.x, origin.x + 2):
			if _near_river(s, Vector2i(x, y), r):
				return true
	return false


## Plants two forest tiles within the shade radius (Euclidean 2) of the 2x2 footprint at `origin`.
func _shade(s: Settlement, origin: Vector2i) -> bool:
	var need := 2
	for y in range(origin.y - 2, origin.y + 4):
		for x in range(origin.x - 2, origin.x + 4):
			var t := Vector2i(x, y)
			if t.x >= origin.x and t.x < origin.x + 2 and t.y >= origin.y and t.y < origin.y + 2:
				continue  # the footprint itself
			if not _near_footprint(origin, t):
				continue
			if not _land(s, t):
				continue
			s.set_terrain(t, "forest")
			need -= 1
			if need <= 0:
				return true
	return false


func _near_footprint(origin: Vector2i, t: Vector2i) -> bool:
	for y in range(origin.y, origin.y + 2):
		for x in range(origin.x, origin.x + 2):
			if (x - t.x) * (x - t.x) + (y - t.y) * (y - t.y) <= 4:
				return true
	return false


## Places a Glowcap Grove on the first free 2x2 that is (or is not) within two tiles of a river.
func _place_grove(s: Settlement, near_river: bool) -> Building:
	var r := reg.planet.glow_river_radius
	for y in range(2, MapState.HEIGHT - 3):
		for x in range(2, MapState.WIDTH - 3):
			var origin := Vector2i(x, y)
			if not _footprint_ok(s, origin):
				continue
			if _footprint_near_river(s, origin, r) != near_river:
				continue
			if not _shade(s, origin):
				continue
			var bid := s.place_building_instant("glowcap_grove", origin)
			if bid >= 0:
				return s.buildings[bid]
	return null


## A river tile whose +2 tile has no river within radius 1: proof that the glow is radius 1, not wider.
func _radius_pair(s: Settlement) -> Array:
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(2, MapState.WIDTH - 2):
			if not s.map.is_river(x, y):
				continue
			var two := Vector2i(x + 2, y)
			if _near_river(s, two, 1):
				continue
			return [Vector2i(x, y), two]
	return []


func _river_count(s: Settlement) -> int:
	var n := 0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_river(x, y):
				n += 1
	return n


# ---------------------------------------------------------------- criterion 1

## Criterion 1: the Grove makes double food in a Dimming (new moon stacks), a Grove within two tiles of the glowing
## river grows +25% faster, and the river tiles count as lit radius 1 only in a Dimming at night.
func test_grove_doubles_in_a_dimming_and_the_river_lights_r1() -> void:
	var s := _new_settlement()
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	var grove := _place_grove(s, false)
	assert_not_null(grove, "an inland Glowcap Grove with shade placed")

	_set_day(s, 9, 23)  # neutral moon, 23:00
	var base := prod.multiplier(s, grove)
	var d := s.get_system(DimmingSystem) as DimmingSystem
	_dimming(s)
	assert_almost_eq(DimmingSystem.output_modifier(s, grove), 2.0, 0.0001, "Glowcap x2 in a Dimming")
	assert_almost_eq(prod.multiplier(s, grove), base * 2.0, 0.0001, "the multiplier doubles")
	_set_day(s, 8, 23)  # cycle day 1, the new moon
	assert_true(Moon.is_new(8, reg.day_night), "day 8 of the clock is a new moon")
	assert_almost_eq(prod.multiplier(s, grove), base * 2.5, 0.0001, "the new moon's +25% stacks")

	var wet := _place_grove(s, true)
	assert_not_null(wet, "a Glowcap Grove within two tiles of the river placed")
	assert_almost_eq(ProductionSystem.glow_river_modifier(s, wet), 1.25, 0.0001, "river +25% in a Dimming")
	d._active = false
	_set_day(s, 9, 23)
	var wet_base := prod.multiplier(s, wet)
	_dimming(s)
	_set_day(s, 9, 23)
	assert_almost_eq(prod.multiplier(s, wet), wet_base * 2.0 * 1.25, 0.0001, "x2 and the river's +25%")

	# The river tiles count as lit radius 1 at night only in a Dimming.
	var pair := _radius_pair(s)
	assert_false(pair.is_empty(), "the map has a river tile with open ground two tiles away")
	var river: Vector2i = pair[0]
	var two: Vector2i = pair[1]
	d._active = false
	_set_day(s, 20, 22)  # an ordinary night
	assert_true(s.is_lamp_hour(22), "22:00 is a lamp hour")
	assert_false(s.is_tile_lit(river), "an ordinary night leaves the river dark")
	_dimming(s)
	_set_day(s, 20, 22)  # a Dimming night
	assert_true(s.is_tile_lit(river), "the river tile is lit in a Dimming")
	assert_true(s.is_tile_lit(river + Vector2i(1, 0)), "radius 1 reaches the tile beside it")
	assert_false(s.is_tile_lit(two), "two tiles away stays dark (radius 1, not wider)")
	_set_day(s, 20, 12)  # the short Dimming day
	assert_false(s.is_tile_lit(river), "the river is dark by day")
	_set_day(s, 20, 22)
	assert_eq((NightRenderModel.river_specks(s) as Array).size(), _river_count(s),
			"the render model lists a speck per river tile at night")
	d._active = false
	assert_eq((NightRenderModel.river_specks(s) as Array).size(), 0, "no specks outside a Dimming")


# ---------------------------------------------------------------- criterion 2

## Criterion 2: a staffed Observatory night crew catches 1 starlight a night in a Dimming, and starlight covers that
## day's light need at 5 Lumen each.
func test_observatory_catches_starlight_and_it_covers_light() -> void:
	var s := _new_settlement()
	var obs := _put(s, "observatory", 8)
	var lamp := _put(s, "lamp", 6)
	lamp.input_buffer.add("wood", 3.0)
	_set_day(s, 20, 15)
	_dimming(s)
	s.step_hours(1)  # 15:00 -> 16:00, the Dimming dusk

	assert_true(s.is_lit(obs), "the lamp lights the Observatory")
	assert_eq(_night_crew(s, obs).size(), 2, "two night slots staffed")
	assert_not_null(obs.door_buffer, "the Observatory has a door buffer for its starlight")
	assert_almost_eq(obs.door_buffer.amount_of("starlight"), 1.0, 0.01, "1 starlight a night")

	# Move the catch to storage and spend every Lumen: the next day's light draw must use the starlight.
	var caught := obs.door_buffer.remove("starlight", 10.0)
	s.hearth.inventory.add("starlight", caught)
	s.hearth.inventory.remove("lumen", 1000.0)
	_set_day(s, 20, 23)
	s.step_hours(1)  # 23:00 -> 00:00, the Dimming day's light draw
	var ll := (s.get_system(DimmingSystem) as DimmingSystem).last_light
	assert_almost_eq(float(ll["need"]), 4.0, 0.001, "eight citizens need 4 Lumen (0.5 each)")
	assert_almost_eq(float(ll.get("drawn_starlight", 0.0)), 4.0, 0.01, "starlight covered the need")
	assert_almost_eq(float(ll["short"]), 0.0, 0.001, "nothing short")
	assert_false(DimmingSystem.is_dark(s), "the town is not dark")
	assert_almost_eq(s.hearth.inventory.amount_of("starlight"), 0.2, 0.01, "0.8 starlight spent for 4 Lumen")
