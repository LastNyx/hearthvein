extends GutTest
## Ticket 152: the Water Wheel (spec .scratch/v1/night-shift-spec.md N10).
## A Village 1x1 building on a river bank that drives the one Sawmill, Mason or Bakery beside it: that workshop needs
## one worker fewer per shift (min 1) and its night shift needs no lamp. On fouled water the drive halves (x0.5
## output instead of the worker saving).

const SEED := 42

var reg: DataRegistry
var _small_town_pop := 0


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_small_town_pop = reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the same-rank ordering is what these tests check, not the first-hand rule


func after_each() -> void:
	reg.logistics.small_town_pop = _small_town_pop


## A fresh settlement with growth off (the citizen count stays what a test sets), every region owned, and the Village
## era so the Water Wheel is unlocked.
func _new_settlement() -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.systems.erase(s.get_system(GrowthSystem))
	s.era_override = "village"
	for r in MapState.REGION_COUNT:
		s.map.set_region_owned(r, true)
	return s


## Buildable land no building or road stands on.
func _free_land(s: Settlement, t: Vector2i) -> bool:
	if not MapState.in_bounds(t.x, t.y) or s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE:
		return false
	var td := reg.get_terrain(s.map.terrain_id_at(t.x, t.y))
	return td != null and td.buildable


## A land tile whose 4-neighbour is a river tile: the bank the Water Wheel needs.
func _bank(s: Settlement, t: Vector2i) -> bool:
	for d in Placement.DIRS:
		var n: Vector2i = t + d
		if MapState.in_bounds(n.x, n.y) and s.map.is_river(n.x, n.y):
			return true
	return false


## The tiles around a footprint (the road-connection ring).
func _ring_tiles(b: Building) -> Array[Vector2i]:
	var r := b.footprint()
	var out: Array[Vector2i] = []
	for t in b.tiles():
		for d in Placement.DIRS:
			var n: Vector2i = t + d
			if not r.has_point(n):
				out.append(n)
	return out


## Tiles a dirt road can run over: any buildable land, plus forest (cleared before the road goes down), never water
## and never under a building.
func _road_ok(s: Settlement, t: Vector2i) -> bool:
	if not MapState.in_bounds(t.x, t.y) or s.building_at(t) != null:
		return false
	var tid := s.map.terrain_id_at(t.x, t.y)
	if tid == "forest":
		return true
	var td := reg.get_terrain(tid)
	return td != null and td.buildable


## Tiles reached by a dirt road from the Hearth ring: {tile: parent tile}, a seed's parent is itself.
func _road_reach(s: Settlement) -> Dictionary:
	var parent := {}
	var q: Array[Vector2i] = []
	for t in _ring_tiles(s.hearth):
		if _road_ok(s, t) and not parent.has(t):
			parent[t] = t
			q.append(t)
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if parent.has(n) or not _road_ok(s, n):
				continue
			parent[n] = c
			q.append(n)
	return parent


## The road route from the Hearth ring to `t`, seed first.
func _path(parent: Dictionary, t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	while parent[t] != t:
		out.push_front(t)
		t = parent[t]
	out.push_front(t)
	return out


## The free bank tile nearest the Hearth with a free land tile for a workshop beside it and a free road tile beside
## that: {"bank", "shop", "path"}. Empty when the seed has none (it always does).
func _layout(s: Settlement) -> Dictionary:
	var reach := _road_reach(s)
	var best := {}
	var best_len := 1 << 30
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var bank := Vector2i(x, y)
			if not _free_land(s, bank) or not _bank(s, bank) or not reach.has(bank):
				continue
			for d in Placement.DIRS:
				var shop: Vector2i = bank + d
				if not _free_land(s, shop):
					continue
				for e in Placement.DIRS:
					var road: Vector2i = shop + e
					if road == bank or not reach.has(road):
						continue
					var path := _path(reach, road)
					if path.has(bank) or path.has(shop):
						continue
					if path.size() < best_len:
						best_len = path.size()
						best = {"bank": bank, "shop": shop, "road": road, "path": path}
	return best


## Lays the dirt road, clearing any forest in its way.
func _lay_road(s: Settlement, path: Array[Vector2i]) -> void:
	for t in path:
		if s.map.terrain_id_at(t.x, t.y) == "forest":
			s.set_terrain(t, "grass")
		if s.road_at(t) == Settlement.ROAD_NONE:
			assert_true(s.place_road(t), "dirt road at %s" % t)


## A free land tile that is not a bank (for the placement refusal).
func _off_bank(s: Settlement) -> Vector2i:
	for t in _road_reach(s):
		if _free_land(s, t) and not _bank(s, t):
			return t
	return Vector2i(-1, -1)


## The river tiles 4-adjacent to a footprint's tiles.
func _river_neighbour(s: Settlement, b: Building) -> Vector2i:
	for t in b.tiles():
		for d in Placement.DIRS:
			var n: Vector2i = t + d
			if MapState.in_bounds(n.x, n.y) and s.map.is_river(n.x, n.y):
				return n
	return Vector2i(-1, -1)


## Keeps the lowest `n` citizens (the rest leave).
func _keep_citizens(s: Settlement, n: int) -> void:
	while s.citizens.size() > n:
		s.remove_citizen(s.citizens.keys().max())


## Steps the clock to the next dusk (19:00).
func _dusk(s: Settlement) -> void:
	s.step_hours(posmod(19 - s.clock.hour(), 24))


## Citizens in a `kind` job at `b`, on one shift.
func _staff(s: Settlement, b: Building, kind: String, night: bool) -> Array:
	var out: Array = []
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == kind and (c.shift == "night") == night:
			out.append(c)
	return out


## Places a lamp within its tier I radius (3) of `b` and fuels it.
func _light(s: Settlement, b: Building) -> Building:
	for y in range(b.origin.y - 3, b.origin.y + 4):
		for x in range(b.origin.x - 3, b.origin.x + 4):
			var t := Vector2i(x, y)
			if t == b.origin or Vector2i(x - b.origin.x, y - b.origin.y).length() > 3.0:
				continue
			if not _free_land(s, t):
				continue
			var lid := s.place_building_instant("lamp", t)
			if lid < 0:
				continue
			var lamp: Building = s.buildings[lid]
			lamp.input_buffer.add("wood", 2.0)
			return lamp
	return null


## Stages wheel + bakery on a layout and runs one night shift: bread made in the bakery's door buffer.
func _night_run(s: Settlement, layout: Dictionary, fouled: bool) -> float:
	_lay_road(s, layout["path"])
	var wid := s.place_building_instant("water_wheel", layout["bank"])
	assert_true(wid >= 0, "wheel on the bank")
	var bid := s.place_building_instant("bakery", layout["shop"])
	assert_true(bid >= 0, "bakery beside the wheel")
	var shop: Building = s.buildings[bid]
	assert_not_null(_light(s, shop), "a fuelled lamp lights the bakery")
	if fouled:
		assert_true(s.set_fouled(_river_neighbour(s, s.buildings[wid]), true), "the river beside the wheel fouls")
	_keep_citizens(s, 1)  # one worker: any second slot stays empty in both runs
	_dusk(s)
	s.refresh_population()
	shop.input_buffer.add("crops", 20.0)
	shop.input_buffer.add("charcoal", 20.0)
	s.step_hours(9)  # through the night shift
	return shop.door_buffer.amount_of("bread")


## AC1: placement on a bank only; the driven building has one slot fewer, and its night shift works unlit.
func test_the_wheel_stands_on_a_bank_and_drives_a_workshop_with_one_worker_fewer_unlit() -> void:
	var s := _new_settlement()
	var lay := _layout(s)
	assert_false(lay.is_empty(), "seed %d has a free bank near the Hearth" % SEED)
	var off := _off_bank(s)
	assert_true(off.x >= 0)
	assert_eq(s.can_place("water_wheel", off)["reason"], "needs_river_bank", "dry land only")
	assert_true(s.can_place("water_wheel", lay["bank"])["ok"], "the bank beside the river takes the wheel")
	_lay_road(s, lay["path"])
	assert_true(s.place_building_instant("water_wheel", lay["bank"]) >= 0, "wheel placed on the bank")
	var bid := s.place_building_instant("bakery", lay["shop"])
	assert_true(bid >= 0, "bakery placed beside the wheel")
	var shop: Building = s.buildings[bid]
	assert_true(shop.connected, "the bakery has a road to the Hearth")
	_keep_citizens(s, 3)
	_dusk(s)
	s.refresh_population()
	assert_false(s.is_lit(shop), "no lamp anywhere: the bakery would be dark without the wheel")
	assert_eq(_staff(s, shop, Citizen.JOB_WORK, true).size(), 1, "the drive halves the bay's 2 night slots to 1")
	shop.input_buffer.add("crops", 20.0)
	shop.input_buffer.add("charcoal", 20.0)
	s.step_hours(9)  # through the night shift, unlit
	assert_gt(shop.door_buffer.amount_of("bread"), 0.0, "the driven bakery baked in the dark")


## AC2: fouled water weakens the drive: no worker saving, and the driven output runs at half speed.
func test_fouled_water_halves_the_drive() -> void:
	var clean := _new_settlement()  # clean water levels the run for the worker count
	var lay := _layout(clean)
	assert_false(lay.is_empty(), "seed %d has a free bank near the Hearth" % SEED)
	var clean_bread := _night_run(clean, lay, false)
	var foul := _new_settlement()
	var foul_lay := _layout(foul)
	assert_false(foul_lay.is_empty())
	var foul_bread := _night_run(foul, foul_lay, true)
	assert_gt(clean_bread, 0.0, "the clean wheel drove the bakery")
	assert_almost_eq(foul_bread / clean_bread, 0.5, 0.06, "fouled water drives the bakery at half speed")
