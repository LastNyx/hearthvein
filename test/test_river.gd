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


## Lays the road and the wheel on `lay`, then a `shop_id` workshop beside it (the 2x1 shops may need the tile to the
## left of the layout's shop tile as their origin). Returns the workshop, or null when none fits.
func _driven(s: Settlement, lay: Dictionary, shop_id: String) -> Building:
	_lay_road(s, lay["path"])
	assert_true(s.place_building_instant("water_wheel", lay["bank"]) >= 0, "wheel on the bank")
	for o in [lay["shop"], lay["shop"] + Vector2i(-1, 0)]:
		var bid := s.place_building_instant(shop_id, o)
		if bid >= 0:
			return s.buildings[bid]
	return null


## Ticket 174: a driven Sawmill, Mason or Bakery has one slot fewer per shift (never below 1, and a shift with no
## slots stays at none).
func test_a_driven_workshop_has_one_day_slot_fewer_never_below_one() -> void:
	var expect := {"sawmill": [1, 1], "mason": [1, 1], "bakery": [0, 1]}  # [day, night] slots with the wheel
	var plain := {"sawmill": [2, 1], "mason": [2, 1], "bakery": [0, 2]}  # without it
	for id in expect:
		var s := _new_settlement()
		var lay := _layout(s)
		var shop := _driven(s, lay, id)
		assert_not_null(shop, "%s placed beside the wheel" % id)
		if shop == null:
			continue
		assert_eq([ProductionSystem.worker_slots_for(s, shop), ProductionSystem.night_slots_for(s, shop)],
				expect[id], "%s slots with a clean wheel" % id)
		assert_eq([shop.def.worker_slots, shop.def.night_worker_slots], plain[id], "%s slots in data" % id)


## Ticket 174: the selected driven workshop says what drives it, and says so when the water is fouled.
func test_the_selection_line_names_the_wheel_and_the_fouled_water() -> void:
	var s := _new_settlement()
	var lay := _layout(s)
	var shop := _driven(s, lay, "bakery")
	assert_not_null(shop)
	var m := HudModel.new(s)
	m.select(shop.id)
	assert_has(m.selection()["extra"], "Water Wheel: -1 worker, runs at night")
	var wheel := ProductionSystem.wheel_driving(s, shop)
	assert_true(s.set_fouled(_river_neighbour(s, wheel), true), "the river beside the wheel fouls")
	assert_has(m.selection()["extra"], "Water Wheel: fouled water, half speed")


## Ticket 175: the fouled-water speed factor comes from the Water Wheel's def.
func test_the_fouled_speed_factor_comes_from_the_wheel_def() -> void:
	var wheel_def := reg.get_building("water_wheel")
	wheel_def.drive_speed_factor = 0.25
	var clean := _new_settlement()
	var lay := _layout(clean)
	var clean_bread := _night_run(clean, lay, false)
	var foul := _new_settlement()
	var foul_bread := _night_run(foul, _layout(foul), true)
	wheel_def.drive_speed_factor = 0.5
	assert_gt(clean_bread, 0.0)
	assert_almost_eq(foul_bread / clean_bread, 0.25, 0.06, "the bread ratio follows the data factor")


## Ticket 175: the worker saving comes from the Water Wheel's def (0 = no saving, 2 = two fewer, never below 1).
func test_the_worker_saving_comes_from_the_wheel_def() -> void:
	var wheel_def := reg.get_building("water_wheel")
	wheel_def.drive_worker_saving = 0
	var s := _new_settlement()
	var shop := _driven(s, _layout(s), "sawmill")
	assert_eq(ProductionSystem.worker_slots_for(s, shop), 2, "saving 0: both day slots")
	wheel_def.drive_worker_saving = 5
	assert_eq(ProductionSystem.worker_slots_for(s, shop), 1, "a big saving still leaves one")
	wheel_def.drive_worker_saving = 1


# ---------------------------------------------------------------- ticket 153: River Docks and boats

## River tiles 4-adjacent to a tile.
func _rivers_beside(s: Settlement, t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Placement.DIRS:
		var n: Vector2i = t + d
		if MapState.in_bounds(n.x, n.y) and s.map.is_river(n.x, n.y):
			out.append(n)
	return out


## A free bank tile within `r` of `c`, nearest ring first (stable y then x): land with a river beside it.
func _bank_near(s: Settlement, c: Vector2i, r: int) -> Vector2i:
	for rad in range(0, r + 1):
		for y in range(c.y - rad, c.y + rad + 1):
			for x in range(c.x - rad, c.x + rad + 1):
				if absi(x - c.x) != rad and absi(y - c.y) != rad:
					continue
				var t := Vector2i(x, y)
				if MapState.in_bounds(t.x, t.y) and _free_land(s, t) and _bank(s, t):
					return t
	return Vector2i(-1, -1)


## Steps along river water between two river tiles (4-neighbour BFS); -1 when the water does not join them.
func _river_steps(s: Settlement, a: Vector2i, b: Vector2i) -> int:
	var dist := {a: 0}
	var q: Array[Vector2i] = [a]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == b:
			return int(dist[c])
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if dist.has(n) or not MapState.in_bounds(n.x, n.y) or not s.map.is_river(n.x, n.y):
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	return -1


## The shortest water distance between two bank tiles, over their river neighbours; -1 when they are not joined.
func _water_between(s: Settlement, a: Vector2i, b: Vector2i) -> int:
	var best := -1
	for ra in _rivers_beside(s, a):
		for rb in _rivers_beside(s, b):
			var d := _river_steps(s, ra, rb)
			if d >= 0 and (best < 0 or d < best):
				best = d
	return best


## A land-only road route between two bank tiles: the tiles from a neighbour of `a` to a neighbour of `b`, or [].
## The two dock tiles stay free.
func _land_road(s: Settlement, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var parent := {}
	var q: Array[Vector2i] = []
	for d in Placement.DIRS:
		var n: Vector2i = a + d
		if n != b and _road_ok(s, n) and not parent.has(n):
			parent[n] = n
			q.append(n)
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if absi(c.x - b.x) + absi(c.y - b.y) == 1:
			var out: Array[Vector2i] = []
			var t := c
			while parent[t] != t:
				out.push_front(t)
				t = parent[t]
			out.push_front(t)
			return out
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if n == a or n == b or parent.has(n) or not _road_ok(s, n):
				continue
			parent[n] = c
			q.append(n)
	return []


## Two free bank tiles on one river (a upstream, b downstream) with a land road between them no longer than the water
## by much, so an upstream boat is slower than that road. {"a", "b", "road"} or {}.
func _dock_layout(s: Settlement) -> Dictionary:
	var path := s.map.river_path
	for gap in [32, 24, 18, 14]:
		var i := 0
		while i + gap < path.size():
			var a := _bank_near(s, path[i], 4)
			var b := _bank_near(s, path[i + gap], 4)
			i += 4
			if a.x < 0 or b.x < 0:
				continue
			var water := _water_between(s, a, b)
			if water <= 0:
				continue
			var road := _land_road(s, a, b)
			if road.is_empty() or float(road.size()) > 1.2 * float(water):
				continue
			return {"a": a, "b": b, "road": road}
	return {}


## AC: two finished docks on the same river form a link (and the dock needs a bank).
func test_two_docks_on_one_river_form_a_link() -> void:
	var s := _new_settlement()
	s.era_override = "town"
	var lay := _dock_layout(s)
	assert_false(lay.is_empty(), "seed %d has two bank tiles a land road joins" % SEED)
	var a: Vector2i = lay["a"]
	var b: Vector2i = lay["b"]
	var off := _off_bank(s)
	assert_true(off.x >= 0)
	assert_eq(s.can_place("river_dock", off)["reason"], "needs_river_bank", "dry land only")
	assert_true(s.can_place("river_dock", a)["ok"], "a bank tile takes the dock")
	var da: Building = s.buildings[s.place_building_instant("river_dock", a)]
	var db: Building = s.buildings[s.place_building_instant("river_dock", b)]
	assert_not_null(da)
	assert_not_null(db)
	var link := HaulingSystem.river_link(s, da, db)
	assert_true(link["ok"], "the two docks on one river are linked")
	assert_gt((link["path"] as Array).size(), 1, "the boat route runs along the water")


## AC: the downstream trip is faster than the road; upstream is slower than the road, so only the downstream leg is
## chosen.
func test_the_river_leg_is_faster_downstream_and_slower_upstream() -> void:
	var s := _new_settlement()
	s.era_override = "town"
	var lay := _dock_layout(s)
	assert_false(lay.is_empty(), "seed %d has two bank tiles a land road joins" % SEED)
	var a: Vector2i = lay["a"]
	var b: Vector2i = lay["b"]
	var da: Building = s.buildings[s.place_building_instant("river_dock", a)]
	var db: Building = s.buildings[s.place_building_instant("river_dock", b)]
	assert_not_null(da)
	assert_not_null(db)
	_lay_road(s, lay["road"])
	_staff_docks({"s": s, "da": da, "db": db})  # a dock with no worker forms no link (ticket 179)
	s.step_seconds(0.01)  # binds the walker system to the settlement (tests use its path queries directly)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var road := ws.path_seconds(ws.find_path(ws.door_tile(da), ws.door_tile(db)))
	assert_gt(road, 0.0, "a road joins the two docks")
	var down := hs.journey(s, ws, da, db)
	assert_true(down["river"], "downstream the boat is chosen")
	assert_lt(float(down["seconds"]), road, "downstream beats the road")
	var down_link := HaulingSystem.river_link(s, da, db)
	var up_link := HaulingSystem.river_link(s, db, da)
	assert_gt(float(up_link["seconds"]), float(down_link["seconds"]), "upstream is slower than downstream")
	var up := hs.journey(s, ws, db, da)
	assert_false(up["river"], "upstream is slower than the road, so the road is used")
	assert_almost_eq(float(up["seconds"]), road, 0.001, "the road's time")


# ---------------------------------------------------------------- ticket 179: the boat ride end to end

## A free spot for a `id` building whose footprint touches `road` tile `t` (so its door stands on the road).
func _place_by(s: Settlement, id: String, t: Vector2i) -> Building:
	for r in range(1, 4):
		for y in range(t.y - r, t.y + r + 1):
			for x in range(t.x - r, t.x + r + 1):
				var o := Vector2i(x, y)
				if absi(x - t.x) != r and absi(y - t.y) != r:
					continue
				if not s.can_place(id, o, true)["ok"]:
					continue
				var bid := s.place_building_instant(id, o)
				if bid < 0:
					continue
				var b: Building = s.buildings[bid]
				if b.connected:
					return b
				s.demolish(bid)
	return null


## Everything a boat trip needs: two docks (a upstream, b downstream) joined by a land road, the Hearth joined to the
## first road tile, a storehouse of crops beside dock a and a Bakery (which wants crops) beside dock b.
## {"s", "da", "db", "store", "bakery"}; "docks" false leaves the docks out.
func _boat_world(with_docks: bool = true) -> Dictionary:
	var s := _new_settlement()
	s.era_override = "town"
	var lay := _dock_layout(s)
	assert_false(lay.is_empty(), "seed %d has two bank tiles a land road joins" % SEED)
	var out := {"s": s}
	if with_docks:
		out["da"] = s.buildings[s.place_building_instant("river_dock", lay["a"])]
		out["db"] = s.buildings[s.place_building_instant("river_dock", lay["b"])]
	_lay_road(s, lay["road"])
	var reach := _road_reach(s)
	var road: Array[Vector2i] = lay["road"]
	assert_true(reach.has(road[0]), "the Hearth's roads can reach the dock road")
	if reach.has(road[0]):
		_lay_road(s, _path(reach, road[0]))
	out["store"] = _place_by(s, "storehouse", road[0])
	out["bakery"] = _place_by(s, "bakery", road[road.size() - 1])
	return out



## Takes every worker off the docks (the job system staffs them on its own when it can).
func _unstaff_docks(w: Dictionary) -> void:
	var s: Settlement = w["s"]
	for key in ["da", "db"]:
		var dock: Building = w.get(key)
		for cid in s.citizens:
			var c: Citizen = s.citizens[cid]
			if dock != null and c.job_kind == Citizen.JOB_WORK and c.job_id == dock.id:
				c.job_kind = ""
				c.job_id = -1


## Gives every dock exactly one worker (a citizen off whatever job they had) and a full Lumen buffer, so no hauler is
## sent with upkeep.
func _staff_docks(w: Dictionary) -> void:
	var s: Settlement = w["s"]
	_unstaff_docks(w)
	var taken := {}
	for key in ["da", "db"]:
		var dock: Building = w.get(key)
		if dock == null:
			continue
		for cid in s.citizens:
			var c: Citizen = s.citizens[cid]
			if taken.has(cid) or c.job_kind == Citizen.JOB_HAUL:
				continue
			c.job_kind = Citizen.JOB_WORK
			c.job_id = dock.id
			taken[cid] = true
			break
		dock.input_buffer.add("lumen", 10.0)


## Starts the Bakery's crop haul at 06:00 and steps seconds until a crop delivery lands. {"seconds", "rode", "boat"}:
## seconds = -1 when nothing arrived in 90 s; rode = a boat carried the hauler; boat = the Trip's dock state at the ride.
func _haul_crops(w: Dictionary) -> Dictionary:
	var s: Settlement = w["s"]
	var store: Building = w["store"]
	s.step_hours(posmod(6 - s.clock.hour(), 24))
	store.inventory.add("crops", 10.0)
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var rode := false
	var placed := {}
	for sec in 90:
		s.step_seconds(1.0)
		# The hauler that takes the crop trip starts at the storehouse: the shift is shorter than the walk from the
		# Hearth to the docks.
		for cid in hs.trips:
			var t: HaulingSystem.Trip = hs.trips[cid]
			if t.good == "crops" and not placed.has(cid):
				placed[cid] = true
				ws.place_walker(cid, ws.door_tile(store))
				ws.walk_to_building(cid, store.id)
		if hs.has_boats():
			rode = true
		for e in s.events.log_of("haul_delivered"):
			if e["data"]["good"] == "crops" and e["data"]["to"] == (w["bakery"] as Building).id:
				return {"seconds": sec + 1, "rode": rode}
	return {"seconds": -1, "rode": rode}






## Steps one second at a time until a crop delivery to the Bakery lands (after `from_log` earlier ones); the seconds it
## took, or -1 after `limit`.
func _until_crops_land(s: Settlement, bakery: Building, limit: int) -> int:
	var seen := 0
	for e in s.events.log_of("haul_delivered"):
		if e["data"]["good"] == "crops" and e["data"]["to"] == bakery.id:
			seen += 1
	for sec in limit:
		s.step_seconds(1.0)
		var now := 0
		for e in s.events.log_of("haul_delivered"):
			if e["data"]["good"] == "crops" and e["data"]["to"] == bakery.id:
				now += 1
		if now > seen:
			return sec + 1
	return -1


## AC: a hauler carries a good downstream over the link, arrives sooner than the same trip with no docks, and the
## good lands in the destination.
func test_a_hauler_rides_the_boat_and_the_good_lands_sooner_than_by_road() -> void:
	var w := _boat_world()
	_staff_docks(w)
	var by_boat := _haul_crops(w)
	var road := _haul_crops(_boat_world(false))
	assert_true(by_boat["rode"], "a boat carried the hauler")
	assert_false(road["rode"], "no docks, no boat")
	assert_gt(int(by_boat["seconds"]), 0, "the crops landed")
	assert_gt(int(road["seconds"]), 0, "the crops landed by road too")
	assert_lt(int(by_boat["seconds"]), int(road["seconds"]), "the boat trip is faster than the road")
	var bakery: Building = w["bakery"]
	assert_gt(bakery.input_buffer.amount_of("crops"), 0.0, "the good is in the destination's input buffer")


## AC: a save while the hauler is on the water resumes the ride and the delivery lands at the same time.
func test_a_save_mid_ride_resumes_the_trip_and_delivers_at_the_same_time() -> void:
	var w := _boat_world()
	_staff_docks(w)
	var s: Settlement = w["s"]
	var store: Building = w["store"]
	var bakery: Building = w["bakery"]
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	s.step_hours(posmod(6 - s.clock.hour(), 24))
	store.inventory.add("crops", 10.0)
	var placed := {}
	var riding := false
	for sec in 90:
		s.step_seconds(1.0)
		for cid in hs.trips:
			var t: HaulingSystem.Trip = hs.trips[cid]
			if t.good == "crops" and not placed.has(cid):
				placed[cid] = true
				ws.place_walker(cid, ws.door_tile(store))
				ws.walk_to_building(cid, store.id)
		for boat in hs.active_boats():
			if float(boat["progress"]) > 0.2:  # well out on the water
				riding = true
		if riding:
			break
	assert_true(riding, "a hauler is on the water")
	var live: HaulingSystem.Trip = null
	for cid in hs.trips:
		if (hs.trips[cid] as HaulingSystem.Trip).boat_started:
			live = hs.trips[cid]
	assert_not_null(live)
	assert_gt(live.boat_elapsed, 0.0, "the boat has been under way for a while")
	var r := Settlement.from_dict(s.to_dict(), reg)
	var rhs := r.get_system(HaulingSystem) as HaulingSystem
	var loaded: HaulingSystem.Trip = rhs.trips[live.citizen_id]
	assert_true(loaded.boat_started and not loaded.boat_done, "the loaded hauler is still on the water")
	assert_eq([loaded.dock_a, loaded.dock_b, loaded.boat_path, loaded.boat_seconds, loaded.boat_elapsed],
			[live.dock_a, live.dock_b, live.boat_path, live.boat_seconds, live.boat_elapsed], "the ride state survives")
	assert_gt(live.dock_a, -1)
	assert_gt(loaded.boat_path.size(), 1)
	var rbakery: Building = r.buildings[bakery.id]
	var left := _until_crops_land(s, bakery, 60)
	var left_loaded := _until_crops_land(r, rbakery, 60)
	assert_gt(left, 0, "the original delivers")
	assert_eq(left_loaded, left, "the loaded settlement delivers after the same time")
	assert_gt(rbakery.input_buffer.amount_of("crops"), 0.0, "the good landed after the load")


## AC: a dock with no worker forms no link.
func test_a_dock_with_no_worker_forms_no_link() -> void:
	var w := _boat_world()
	var s: Settlement = w["s"]
	for key in ["da", "db"]:
		(w[key] as Building).input_buffer.add("lumen", 10.0)
	_unstaff_docks(w)
	s.step_seconds(0.01)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	assert_false(hs.journey(s, ws, w["store"], w["bakery"])["river"], "two unstaffed docks: no boat")
	_staff_docks(w)
	var one: Citizen = null
	for cid in s.citizens:  # take the second dock's worker away again
		var c: Citizen = s.citizens[cid]
		if c.job_id == (w["db"] as Building).id:
			one = c
	assert_not_null(one)
	one.job_kind = ""
	one.job_id = -1
	s.step_seconds(0.01)
	assert_false(hs.journey(s, ws, w["store"], w["bakery"])["river"], "one staffed dock is no link")


## AC: a dock that did not get its Lumen forms no link.
func test_a_dock_with_no_lumen_forms_no_link() -> void:
	var w := _boat_world()
	var s: Settlement = w["s"]
	_staff_docks(w)
	for key in ["da", "db"]:
		(w[key] as Building).input_buffer.remove("lumen", 100.0)
	s.hearth.inventory.remove("lumen", 10000.0)  # nothing to haul to them either
	s.step_seconds(0.01)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	assert_true(hs.journey(s, ws, w["store"], w["bakery"])["river"], "staffed and not yet due: linked")
	s.step_hours(GameClock.HOURS_PER_DAY)  # the day's upkeep cannot be paid
	var ups := s.get_system(UpkeepSystem) as UpkeepSystem
	assert_false(ups.is_paid((w["da"] as Building).id), "the dock went unpaid")
	s.step_seconds(0.01)
	assert_false(hs.journey(s, ws, w["store"], w["bakery"])["river"], "unpaid docks form no link")


## The estimate cache follows the docks: staffing them changes the trip time at once, with no grid change.
func test_staffing_the_docks_refreshes_the_trip_estimates() -> void:
	var w := _boat_world()
	var s: Settlement = w["s"]
	for key in ["da", "db"]:
		(w[key] as Building).input_buffer.add("lumen", 10.0)
	_unstaff_docks(w)
	s.step_seconds(0.01)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var hs := s.get_system(HaulingSystem) as HaulingSystem
	var by_road := hs._walk(s, ws, w["store"], w["bakery"])
	_staff_docks(w)
	s.step_seconds(0.01)
	var by_boat := hs._walk(s, ws, w["store"], w["bakery"])
	assert_lt(by_boat, by_road, "the cached road time was replaced when the docks got workers")
