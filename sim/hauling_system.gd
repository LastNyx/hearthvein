class_name HaulingSystem
extends SimSystem
## Haulers (design.md section 8, D39). Citizens with a haul job (JobSystem, Citizen.JOB_HAUL) carry goods:
##   1. producer door buffer -> nearest storage building with room (Storehouse or Hearth),
##   2. storage -> a consumer's input buffer, up to input_buffer_days of its need.
## Sites and upgrades are served before everything else (_works), then door pickups and inputs take turns. A trip moves one good, at most LogisticsDef.haul_load units (the Handcart Shed raises
## that for haulers in its region, see RegionSystem.handcart_zones), and is a walk to the
## source door, a pickup, a walk to the destination door and a drop. "Nearest" is walking time between doors.
##
## Hours: haulers only START trips during their own shift (the day shift, WORK_START_HOUR to WORK_END_HOUR, unless
## they are night citizens, ticket 132, who work the night shift) and only from their job door. A trip in progress
## always finishes. Every hauler on a trip is a controlled walker; it is released (and sent back to its job door)
## when no task is left or the shift is over, after which the normal schedule takes over.
##
## Reservations: when a trip is planned the load is reserved at the source and the room at the destination, so two
## haulers never chase the same units. A trip is aborted (reservations freed, carried goods put back if possible,
## else lost) when the hauler loses its haul job, a building vanishes or the way is blocked.
##
## Construction sites (D48) are consumers too: a site's need is its full cost (non-gold goods), delivered into its
## input buffer. When the last good arrives the Jobs are refreshed so builders can be allotted.
##
## Consumers: a building whose recipe has inputs, and (from Town) a building with Lumen upkeep. Need = input amount
## x worker slots x input_buffer_days per good, plus upkeep_lumen x input_buffer_days of Lumen (input_need).
##
## River Docks (ticket 153): two finished docks on the same river form a boat link. A trip's time is the faster of
## walking the roads and walking to a dock, riding the boat to a dock near the destination and walking on; the boat is
## chosen only when strictly faster (journey). Downstream runs at LogisticsDef.river_downstream_factor times a dirt
## road's walk speed, upstream at river_upstream_factor. A hauler on a river trip walks to the first dock, waits there
## while the boat runs (BoatView draws it along the river tiles), then walks on from the second dock. The ride is part
## of the trip state, so a save mid-river resumes it.

const SAVE_KEY := "hauling"

class Trip extends RefCounted:
	var citizen_id: int = -1
	var good: String = ""
	var src: int = -1
	var src_door: bool = true  # true: producer door buffer, false: storage inventory
	var dst: int = -1
	var dst_input: bool = false  # true: a building buffer (input or upgrade), false: storage inventory
	var dst_upgrade: bool = false  # true: the destination's upgrade buffer rather than its input buffer
	var planned: float = 0.0
	var carried: float = 0.0
	var picked_up: bool = false
	## River leg (ticket 153): when the fastest way between the doors is a boat, the hauler walks to dock_a, rides the
	## boat along the river (boat_path) to dock_b, then walks on. dock_a = -1 for a plain road trip.
	var dock_a: int = -1
	var dock_b: int = -1
	var boat_path: Array[Vector2i] = []
	var boat_seconds: float = 0.0
	var boat_elapsed: float = 0.0
	var boat_started: bool = false
	var boat_done: bool = false
	var downstream: bool = true

	func to_dict() -> Dictionary:
		return {
			"citizen_id": citizen_id, "good": good, "src": src, "src_door": src_door, "dst": dst,
			"dst_input": dst_input, "dst_upgrade": dst_upgrade, "planned": planned, "carried": carried,
			"picked_up": picked_up, "dock_a": dock_a, "dock_b": dock_b, "boat_path": boat_path,
			"boat_seconds": boat_seconds, "boat_elapsed": boat_elapsed, "boat_started": boat_started,
			"boat_done": boat_done, "downstream": downstream,
		}

	static func from_dict(d: Dictionary) -> Trip:
		var t := Trip.new()
		t.citizen_id = int(d["citizen_id"])
		t.good = str(d["good"])
		t.src = int(d["src"])
		t.src_door = bool(d["src_door"])
		t.dst = int(d["dst"])
		t.dst_input = bool(d["dst_input"])
		t.dst_upgrade = bool(d.get("dst_upgrade", false))
		t.planned = float(d["planned"])
		t.carried = float(d["carried"])
		t.picked_up = bool(d["picked_up"])
		t.dock_a = int(d.get("dock_a", -1))
		t.dock_b = int(d.get("dock_b", -1))
		t.boat_path.assign(d.get("boat_path", []))
		t.boat_seconds = float(d.get("boat_seconds", 0.0))
		t.boat_elapsed = float(d.get("boat_elapsed", 0.0))
		t.boat_started = bool(d.get("boat_started", false))
		t.boat_done = bool(d.get("boat_done", false))
		t.downstream = bool(d.get("downstream", true))
		return t

var trips: Dictionary = {}  # citizen id -> Trip
var _reserved: Dictionary = {}  # "kind:building:good" -> float; kinds d (door out), s (storage out), i (input in), r (storage in)
## Walking seconds per building pair. find_path already caches the path, but summing its tiles again was most of the
## cost of planning a trip (ticket 55: a plan scans every storage building). Doors only move when the grid changes.
var _walk_cache: Dictionary = {}  # "a:b" -> float (INF when unreachable)
var _journey_cache: Dictionary = {}  # "a:b" -> float, the same pair with a river leg when that is faster (ticket 153)
var _walk_version: int = -1


## good id -> amount a consumer should hold: its recipe inputs for all worker slots over input_buffer_days, plus
## its Lumen upkeep for the same number of days (design.md section 8: consumers keep two days of need).
static func input_need(reg: DataRegistry, def: BuildingDef) -> Dictionary:
	var out := {}
	if reg.logistics == null:
		return out
	if def.recipe != null:
		# A night-only producer works its night slots alone (ticket 134): its keep is sized off those, or it would
		# get a zero-cap input buffer and never hold the wood it burns.
		var slots := def.night_worker_slots if def.night_only else def.worker_slots
		for g in def.recipe.inputs:
			out[g] = float(def.recipe.inputs[g]) * slots * reg.logistics.input_buffer_days
		# Flexible inputs (Kitchen): every listed food type gets two days of one batch's share, so haulers keep
		# whichever two types the Kitchen picks in stock. The per-good buffer cap comes from this same need.
		if def.recipe.any_input_count > 0:
			var each := float(def.recipe.any_input_amount) * slots * reg.logistics.input_buffer_days
			for g in def.recipe.any_input_goods:
				out[g] = maxf(float(out.get(g, 0.0)), each)
	# A night-only building that drinks (Tavern) keeps a few nights of its night_inputs, like any other consumer.
	for g in def.night_inputs:
		out[g] = float(out.get(g, 0.0)) + float(def.night_inputs[g]) * reg.logistics.input_buffer_days
	if def.upkeep_lumen > 0.0 and not def.upkeep_from_storage:
		out["lumen"] = float(out.get("lumen", 0.0)) + def.upkeep_lumen * reg.logistics.input_buffer_days
	# A lamp keeps a few nights of fuel like any other consumer (ticket 133). The def carries the tier I fuel; a
	# higher tier's fuel comes from Building.lamp_fuel (need_for).
	if def.lamp and def.lamp_fuel != "" and not def.lamp_grid and def.lamp_fuel_per_night > 0.0:
		out[def.lamp_fuel] = float(out.get(def.lamp_fuel, 0.0)) + def.lamp_fuel_per_night \
				* reg.logistics.input_buffer_days
	# The Night Watch's walker burns its lantern fuel at dusk, so haulers keep a few nights of it too (ticket 143).
	if def.patrol_radius > 0 and def.patrol_fuel != "" and def.patrol_fuel_per_night > 0.0:
		out[def.patrol_fuel] = float(out.get(def.patrol_fuel, 0.0)) + def.patrol_fuel_per_night \
				* reg.logistics.input_buffer_days
	return out


## input_need for one building, with its current tier's lamp fuel (the def alone cannot tell tier I from tier IV).
static func need_for(reg: DataRegistry, b: Building) -> Dictionary:
	if b == null:
		return {}
	var out := input_need(reg, b.def)
	if not b.def.lamp or reg.logistics == null:
		return out
	if b.def.lamp_fuel != "":
		out.erase(b.def.lamp_fuel)  # the def's tier I fuel; the tier may burn another
	var fuel := b.lamp_fuel(reg)
	if fuel != "" and not b.lamp_grid(reg) and b.lamp_fuel_per_night(reg) > 0.0:
		out[fuel] = float(out.get(fuel, 0.0)) + b.lamp_fuel_per_night(reg) * reg.logistics.input_buffer_days
	return out


## What a consumer or work item should hold: a site's full cost (gold is paid on placement), else input_need.
## An upgrading building needs its normal production inputs too; the upgrade cost is a separate buffer and trip
## target (upgrade_need), so the two never starve each other.
static func need_of(reg: DataRegistry, b: Building) -> Dictionary:
	if not b.site:
		return input_need(reg, b.def)
	var out := {}
	var cost := b.effective_cost()
	for g in cost:
		if g != BuildingDef.GOLD:
			out[g] = float(cost[g])
	return out


## What an in-place upgrade still needs in Building.upgrade_buffer: its whole tier cost.
static func upgrade_need(b: Building) -> Dictionary:
	return b.upgrade_cost if b.upgrading() else {}


## Trips in flight (with their walkers) and the reservations they hold. A trip is mid-walk, mid-carry or waiting for a
## load when saved; without this a load would forget loads already picked up and reserved room.
func save_state() -> Dictionary:
	var tl := []
	for cid in trips:
		tl.append([cid, (trips[cid] as Trip).to_dict()])
	return {"trips": tl, "reserved": _reserved.duplicate(true), "retry_left": _retry_left}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	trips.clear()
	for pair in d["trips"]:
		trips[int(pair[0])] = Trip.from_dict(pair[1])
	_reserved = d["reserved"].duplicate(true)
	_retry_left = float(d.get("retry_left", 0.0))
	# Caches: rebuilt from the loaded layout and grid when first needed.
	_walk_cache.clear()
	_journey_cache.clear()
	_walk_version = -1
	_ids.clear()
	_storages.clear()
	_blds.clear()
	_door_blds.clear()
	_site_blds.clear()
	_docks.clear()
	_layout_version = -1
	_layout_count = -1
	_layout_completion = -1


func on_seconds(s: Settlement, seconds: float) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null or s.registry.logistics == null:
		return
	for cid in trips.keys():
		var t: Trip = trips[cid]
		var in_shift := _in_shift_for(s, s.citizens.get(cid))
		if t.boat_started and not t.boat_done:
			_ride(s, ws, t, seconds)
			continue
		var guard := 0
		while trips.has(cid) and guard < 8 and _advance(s, ws, t, in_shift):
			guard += 1
	_retry_left = maxf(0.0, _retry_left - seconds)
	if _retry_left > 0.0 or not (_in_shift(s) or s.is_night()):
		return
	var allowance := _plan_allowance(seconds)
	for cid in s.citizen_ids_of_kind(Citizen.JOB_HAUL):
		if allowance <= 0:
			break
		var c: Citizen = s.citizens.get(cid)
		if c == null or c.job_kind != Citizen.JOB_HAUL or trips.has(cid) or not _in_shift_for(s, c):
			continue
		var w := ws.walker_of(cid)
		if w == null or w.controlled or not w.path.is_empty() or w.at_building != c.job_id:
			continue
		allowance -= 1
		var t := _plan(s, ws, cid)
		if t == null:
			_retry_left = PLAN_RETRY_SECONDS  # nothing to haul for anybody: look again shortly, not every frame
			break
		t.citizen_id = cid
		w.controlled = true
		trips[cid] = t
		_start(s, ws, t)
		var guard := 0
		while trips.has(cid) and guard < 8 and _advance(s, ws, t, _in_shift_for(s, c)):
			guard += 1


func on_hour(_s: Settlement) -> void:
	_retry_left = 0.0


func is_hauling(citizen_id: int) -> bool:
	return trips.has(citizen_id)


## Most trips one on_seconds call may plan (ticket 55). A whole cluster of haulers finishing their trips together
## used to plan every one of them in a single frame, about 0.6 ms each at 600 citizens. The allowance grows with
## `seconds`, so a coarse step (step_hours) is not throttled; a leftover hauler is simply planned a frame later.
const PLAN_PER_SECOND := 120.0
## After a plan finds no trip, idle haulers wait this many game seconds (a tenth of a game hour: 30 frames at
## 1x) before the next plan scans every building again (ticket 89b: a failed plan took 1-5 ms and ran every frame).
## on_hour clears it, so a new hour always starts with a fresh look. Saved, so a load continues the same way.
const PLAN_RETRY_SECONDS := GameClock.REAL_SECONDS_PER_HOUR / 10.0
var _retry_left: float = 0.0


static func _plan_allowance(seconds: float) -> int:
	return maxi(1, int(seconds * PLAN_PER_SECOND))


## True during the day shift's hours (Settlement.day_window: 06-18, or the Dimming's short 09-16).
static func _in_shift(s: Settlement) -> bool:
	return Settlement.in_window(s.clock.hour(), s.day_window())


## True while this hauler's own shift runs: a night hauler starts trips during the night shift (ticket 132), a day
## hauler during the day shift.
static func _in_shift_for(s: Settlement, c: Citizen) -> bool:
	if c != null and c.shift == Citizen.SHIFT_NIGHT:
		return s.is_night()
	return _in_shift(s)


# ---------------------------------------------------------------- planning

## Building ids in id order and the buildings that have an inventory (storages), cached on the layout version like
## ProductionSystem does: planning used to rebuild and sort the 600-entry building list several times per call and
## scan all of it for storages (ticket 55).
var _ids: Array = []
var _storages: Array[Building] = []
var _layout_version: int = -1
var _layout_count: int = -1
var _layout_completion: int = -1
var _blds: Array[Building] = []  # every building in id order
var _door_blds: Array[Building] = []  # ... those with a door buffer (producers)
var _site_blds: Array[Building] = []  # ... those still under construction
var _docks: Array[Building] = []  # ... River Docks (ticket 153), the river leg's endpoints


func _layout(s: Settlement) -> void:
	if _layout_version == s.grid_version and _layout_count == s.buildings.size() \
			and _layout_completion == s.completion_version:
		return
	_layout_version = s.grid_version
	_layout_count = s.buildings.size()
	_layout_completion = s.completion_version
	_ids = s.buildings.keys()
	_ids.sort()
	_storages.clear()
	_blds.clear()
	_door_blds.clear()
	_site_blds.clear()
	_docks.clear()
	for id in _ids:
		var b: Building = s.buildings[id]
		_blds.append(b)
		if b.site:
			_site_blds.append(b)
		if b.door_buffer != null:
			_door_blds.append(b)
		if b.inventory != null:
			_storages.append(b)
		if b.def.river_dock:
			_docks.append(b)


## Nested lookups instead of a formatted key: a plan asks this once per building it scans (ticket 55).
func _res(kind: String, bid: int, good: String) -> float:
	var by_bid = _reserved.get(kind)  # no default {}: that built a Dictionary on every call
	if by_bid == null:
		return 0.0
	var by_good = by_bid.get(bid)
	if by_good == null:
		return 0.0
	return by_good.get(good, 0.0)


func _reserve(kind: String, bid: int, good: String, amount: float) -> void:
	var by_bid: Dictionary = _reserved.get(kind, {})
	var by_good: Dictionary = by_bid.get(bid, {})
	var left: float = by_good.get(good, 0.0) + amount
	if left <= Inventory.EPS:
		by_good.erase(good)
		if by_good.is_empty():
			by_bid.erase(bid)
			if by_bid.is_empty():
				_reserved.erase(kind)
		return
	by_good[good] = left
	by_bid[bid] = by_good
	_reserved[kind] = by_bid


## Walking seconds between two building doors, INF when unreachable. Cached per pair until the grid changes.
func _direct_walk(s: Settlement, ws: WalkerSystem, a: Building, b: Building) -> float:
	if _walk_version != s.grid_version:
		_walk_version = s.grid_version
		_walk_cache.clear()
		_journey_cache.clear()
	var key := Vector2i(a.id, b.id)
	if _walk_cache.has(key):
		return _walk_cache[key]
	var p := ws.find_path(ws.door_tile(a), ws.door_tile(b))
	var t := INF if p.is_empty() else ws.path_seconds(p)
	_walk_cache[key] = t
	return t


## Seconds a hauler needs between two building doors on the fastest way: walking the roads, or walking to a River
## Dock, riding the boat to a dock near the destination and walking on. Cached per pair until the grid changes.
func _walk(s: Settlement, ws: WalkerSystem, a: Building, b: Building) -> float:
	if _walk_version != s.grid_version:
		_walk_version = s.grid_version
		_walk_cache.clear()
		_journey_cache.clear()
	var key := Vector2i(a.id, b.id)
	if _journey_cache.has(key):
		return _journey_cache[key]
	var t := float(journey(s, ws, a, b)["seconds"])
	_journey_cache[key] = t
	return t


## The fastest trip between two building doors as a dict: {seconds, river, dock_a, dock_b, path, downstream,
## boat_seconds}. The river leg is picked only when it is strictly faster than the roads. seconds = INF when neither
## way reaches.
func journey(s: Settlement, ws: WalkerSystem, a: Building, b: Building) -> Dictionary:
	var best := {"seconds": _direct_walk(s, ws, a, b), "river": false, "dock_a": -1, "dock_b": -1,
			"path": [] as Array[Vector2i], "downstream": true, "boat_seconds": 0.0}
	_layout(s)
	if _docks.size() < 2:
		return best
	var docks: Array[Building] = []
	for x in _docks:
		if not x.site and not x.paused:
			docks.append(x)
	if docks.size() < 2:
		return best
	for da in docks:
		var to_dock := 0.0 if da == a else _direct_walk(s, ws, a, da)
		if to_dock == INF:
			continue
		for db in docks:
			if db == da:
				continue
			var from_dock := 0.0 if db == b else _direct_walk(s, ws, db, b)
			if from_dock == INF:
				continue
			var link := river_link(s, da, db)
			if not link["ok"]:
				continue
			var total: float = to_dock + float(link["seconds"]) + from_dock
			if total < float(best["seconds"]) - Inventory.EPS:
				best = {"seconds": total, "river": true, "dock_a": da.id, "dock_b": db.id,
						"path": link["path"], "downstream": link["downstream"],
						"boat_seconds": link["seconds"]}
	return best


## The boat leg between two finished River Docks on the same river, or {"ok": false}. Downstream runs at
## LogisticsDef.river_downstream_factor times a dirt road's walk speed, upstream at river_upstream_factor; the docks'
## places on MapState.river_path (downstream order, which follows the flow data) tell which way is which. `path` is
## the river tiles from the first dock to the second, in order of travel.
static func river_link(s: Settlement, a: Building, b: Building) -> Dictionary:
	var no := {"ok": false}
	if a == null or b == null or a == b or a.def == null or b.def == null:
		return no
	if not a.def.river_dock or not b.def.river_dock or a.site or b.site:
		return no
	var ta := _dock_river_tile(s, a)
	var tb := _dock_river_tile(s, b)
	if ta.x < 0 or tb.x < 0:
		return no
	var path := _river_walk(s, ta, tb)
	if path.is_empty():
		return no
	var downstream := _river_index(s, tb) > _river_index(s, ta)
	var road := s.registry.get_road_by_level(Settlement.ROAD_DIRT)
	var base := road.walk_speed if road != null else 1.0
	var factor := s.registry.logistics.river_downstream_factor if downstream \
			else s.registry.logistics.river_upstream_factor
	var speed := base * factor
	return {"ok": true, "downstream": downstream, "seconds": float(path.size() - 1) / speed if speed > 0.0 \
			else INF, "path": path}


## The river tile a dock stands beside: of its footprint's 4-neighbour river tiles, the one nearest the river's entry
## (the lowest river_path index). (-1, -1) when it touches no river.
static func _dock_river_tile(s: Settlement, b: Building) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_i := 1 << 30
	for t in b.tiles():
		for d in Placement.DIRS:
			var n: Vector2i = t + d
			if not MapState.in_bounds(n.x, n.y) or not s.map.is_river(n.x, n.y):
				continue
			var i := _river_index(s, n)
			if i < best_i:
				best_i = i
				best = n
	return best


## Index of a river tile's nearest centreline point on MapState.river_path (downstream order; ties lowest index).
static func _river_index(s: Settlement, tile: Vector2i) -> int:
	var best := 0
	var best_d := 1 << 30
	for i in s.map.river_path.size():
		var d: int = (s.map.river_path[i] - tile).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## Shortest path along river tiles (4-neighbour), from first to last tile included; [] when the water does not join
## them. Deterministic: neighbours are tried in Placement.DIRS order.
static func _river_walk(s: Settlement, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to:
		out.append(from)
		return out
	var parent := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if parent.has(n) or not MapState.in_bounds(n.x, n.y) or not s.map.is_river(n.x, n.y):
				continue
			parent[n] = c
			queue.append(n)
	if not parent.has(to):
		return out
	var c := to
	while c != from:
		out.push_front(c)
		c = parent[c]
	out.push_front(from)
	return out


## Nearest storage (by walking time from `from`, ties lowest id) with room for `amount` of `good`.
func nearest_storage_with_room(s: Settlement, ws: WalkerSystem, from: Building, good: String, amount: float) -> Building:
	_layout(s)
	if _room_fail.get(good, INF) <= amount:
		return null  # a smaller amount already found no storage with room this plan, and reservations have not moved
	var best: Building = null
	var best_t := INF
	for b in _storages:
		if b.inventory.free_for(good) - _res("r", b.id, good) < amount - Inventory.EPS:
			continue
		var t := 0.0 if b == from else _walk(s, ws, from, b)
		if t < best_t:
			best = b
			best_t = t
	if best == null:
		_room_fail[good] = minf(_room_fail.get(good, INF), amount)
	return best


## Units this hauler carries: LogisticsDef.haul_load on foot, or the Handcart Shed's larger load when a completed
## shed shares the region of the hauler's job building (design.md section 8).
func _haul_load(s: Settlement, cid: int) -> float:
	var lg := s.registry.logistics
	var base := lg.haul_load if lg != null else 0.0
	var c: Citizen = s.citizens.get(cid)
	if c == null or c.job_id < 0:
		return base
	var b: Building = s.buildings.get(c.job_id)
	if b == null:
		return base
	return maxf(base, RegionSystem.haul_load_in(s, s.map.get_region(b.origin.x, b.origin.y)))


## Within one _plan call: good -> smallest amount for which no storage had room / no source had stock (so any larger
## amount fails too without another scan). Cleared at the start of every plan, since a trip changes reservations.
var _room_fail: Dictionary = {}
var _src_fail: Dictionary = {}


func _plan(s: Settlement, ws: WalkerSystem, cid: int) -> Trip:
	_room_fail.clear()
	_src_fail.clear()
	var t := _plan_trip(s, ws, cid)
	_room_fail.clear()  # outside a plan (tests, other callers) nearest_storage_with_room must always scan
	_src_fail.clear()
	return t


func _plan_trip(s: Settlement, ws: WalkerSystem, cid: int) -> Trip:
	var load_cap := _haul_load(s, cid)
	_layout(s)
	# 0. construction sites and upgrades first (priority, sites before upgrades, oldest first; paused get nothing):
	# a busy settlement's door buffers and workshop inputs must not starve its builders.
	for b in _works(s):
		var t: Trip
		if b.site:
			t = _plan_for_need(s, ws, b, b.input_buffer, need_of(s.registry, b), false, load_cap)
		else:
			t = _plan_for_need(s, ws, b, b.upgrade_buffer, upgrade_need(b), true, load_cap)
		if t != null:
			return t
	# 1. and 2. take turns going first (by clock hour and hauler id), so busy producers cannot starve consumers' input buffers.
	if (int(s.clock.total_hours) + cid) % 2 == 0:
		var d := _plan_door(s, ws, load_cap)
		if d != null:
			return d
		return _plan_inputs(s, ws, load_cap)
	var i := _plan_inputs(s, ws, load_cap)
	if i != null:
		return i
	return _plan_door(s, ws, load_cap)


## Sites and in-place upgrades that still want goods, in serving order: priority high, normal, low, a site before an
## upgrade of the same priority, then lowest id (the oldest). Paused ones are left out. Sorted per plan: priority and
## pause change without a layout change, and the list is short.
func _works(s: Settlement) -> Array[Building]:
	var out: Array[Building] = []
	for b in _site_blds:
		if not b.paused and b.input_buffer != null:
			out.append(b)
	for b in _blds:
		if not b.site and not b.paused and b.upgrading() and b.upgrade_buffer != null:
			out.append(b)
	if out.size() > 1:
		out.sort_custom(func(a: Building, b: Building) -> bool:
			var pa := JobSystem.PRIORITY_ORDER.find(a.priority)
			var pb := JobSystem.PRIORITY_ORDER.find(b.priority)
			if pa != pb:
				return pa < pb
			if a.site != b.site:
				return a.site
			return a.id < b.id)
	return out


## Door buffers: the fullest pickup first.
func _plan_door(s: Settlement, ws: WalkerSystem, load_cap: float) -> Trip:
	var lg := s.registry.logistics
	var best: Trip = null
	var best_avail := 0.0
	for b in _door_blds:
		for g in b.door_buffer.goods():
			var have := b.door_buffer.amount_of(g)
			if have < lg.min_pickup - Inventory.EPS or have <= best_avail:
				continue  # reservations only lower what is available, so the checks below would skip it too
			var avail: float = have - _res("d", b.id, g)
			if avail < lg.min_pickup - Inventory.EPS or avail <= best_avail:
				continue
			var load := minf(load_cap, avail)
			var dst := nearest_storage_with_room(s, ws, b, g, load)
			if dst == null or (dst != b and _walk(s, ws, b, dst) == INF):
				continue
			if g == "lumen" and GridSystem.on_grid(s, b) and GridSystem.on_grid(s, dst):
				continue  # Lumen inside the grid is never hauled (design.md section 8): it already counts as grid supply
			best = _trip(g, b.id, true, dst.id, false, load)
			best_avail = avail
	return best


## Storage -> consumer input buffers. Sites and upgrade buffers are served first by _works, never here (a paused one
## gets nothing). Lamps come first (ticket 133): their fuel is small and time-critical (a dark night cannot be made up),
## and a busy producer earlier in id order would otherwise keep every trip for itself.
func _plan_inputs(s: Settlement, ws: WalkerSystem, load_cap: float) -> Trip:
	for lamps_only in [true, false]:
		for b in _blds:
			if b.def.lamp != lamps_only:
				continue
			if b.input_buffer != null and not b.site:
				var t := _plan_for_need(s, ws, b, b.input_buffer, _need_cached(s, b), false, load_cap)
				if t != null:
					return t
	return null


var _def_need: Dictionary = {}  # BuildingDef -> input_need (a def's need never changes while the game runs)


## need_of, with the per-def result of input_need kept: planning asks it for every building on every call.
func _need_cached(s: Settlement, b: Building) -> Dictionary:
	if b.site:
		return need_of(s.registry, b)
	if b.def.lamp:
		return need_for(s.registry, b)  # the fuel depends on the tier, so a lamp is never cached by def
	var n = _def_need.get(b.def)
	if n == null:
		n = input_need(s.registry, b.def)
		_def_need[b.def] = n
	return n


## One trip toward a buffer's deficit of `need`, or null. Upgrade deliveries reserve under their own kind "u", so a
## production input of the same good can never collide with an upgrade cost.
func _plan_for_need(s: Settlement, ws: WalkerSystem, b: Building, buf: Inventory, need: Dictionary,
		upgrade: bool, load_cap: float) -> Trip:
	if buf == null:
		return null
	var lg := s.registry.logistics
	var kind := "u" if upgrade else "i"
	var on_grid := not upgrade and need.has("lumen") and not b.site and GridSystem.on_grid(s, b)
	for g in need:
		if on_grid and g == "lumen":
			continue  # the grid feeds this building's Lumen directly
		var deficit: float = float(need[g]) - buf.amount_of(g) - _res(kind, b.id, g)
		# A site's last delivery may be smaller than min_pickup.
		var floor_amt := minf(lg.min_pickup, deficit) if b.site else lg.min_pickup
		if deficit < floor_amt - Inventory.EPS or deficit <= Inventory.EPS:
			continue
		var src := _nearest_source(s, ws, b, g, floor_amt)
		if src == null:
			continue
		var avail := src.inventory.amount_of(g) - _res("s", src.id, g)
		return _trip(g, src.id, false, b.id, true, minf(load_cap, minf(deficit, avail)), upgrade)
	return null


func _nearest_source(s: Settlement, ws: WalkerSystem, consumer: Building, good: String, min_amount: float) -> Building:
	_layout(s)
	if _src_fail.get(good, INF) <= min_amount:
		return null  # as _room_fail: a smaller amount found no source with stock in this plan
	var best: Building = null
	var best_t := INF
	for b in _storages:
		if b.inventory.amount_of(good) - _res("s", b.id, good) < min_amount - Inventory.EPS:
			continue
		var t := _walk(s, ws, b, consumer)
		if t < best_t:
			best = b
			best_t = t
	if best == null:
		_src_fail[good] = minf(_src_fail.get(good, INF), min_amount)
	return best


func _trip(good: String, src: int, src_door: bool, dst: int, dst_input: bool, load: float,
		dst_upgrade: bool = false) -> Trip:
	var t := Trip.new()
	t.good = good
	t.src = src
	t.src_door = src_door
	t.dst = dst
	t.dst_input = dst_input
	t.dst_upgrade = dst_upgrade
	t.planned = load
	return t


## Reservation kind of a trip's destination ("u" upgrade buffer, "i" input buffer, "r" storage).
static func _dst_kind(t: Trip) -> String:
	if t.dst_upgrade:
		return "u"
	return "i" if t.dst_input else "r"


# ---------------------------------------------------------------- running a trip

func _start(s: Settlement, ws: WalkerSystem, t: Trip) -> void:
	var cid := t.citizen_id
	_reserve("d" if t.src_door else "s", t.src, t.good, t.planned)
	_reserve(_dst_kind(t), t.dst, t.good, t.planned)
	var j := journey(s, ws, s.buildings[t.src], s.buildings[t.dst])
	if j["river"]:
		t.dock_a = int(j["dock_a"])
		t.dock_b = int(j["dock_b"])
		t.boat_path.assign(j["path"])
		t.boat_seconds = float(j["boat_seconds"])
		t.downstream = bool(j["downstream"])
	if not ws.walk_to_building(cid, t.src):
		_abort(s, ws, t)


## Moves a trip one step along. Returns true when its state changed and it may be advanced again at once.
func _advance(s: Settlement, ws: WalkerSystem, t: Trip, in_shift: bool) -> bool:
	var cid := t.citizen_id
	var c: Citizen = s.citizens.get(cid)
	var w := ws.walker_of(cid)
	if c == null or w == null or c.job_kind != Citizen.JOB_HAUL or not s.buildings.has(t.src) or not s.buildings.has(t.dst):
		_abort(s, ws, t)
		return false
	if not w.path.is_empty():
		return false
	var target := t.src
	if t.picked_up:
		target = t.dst if t.dock_a < 0 or t.boat_done else t.dock_a
	if w.at_building != target:
		if w.blocked or w.dest_building != target:
			_abort(s, ws, t)
			return true
		return false
	if not t.picked_up:
		var from: Inventory = (s.buildings[t.src] as Building).door_buffer if t.src_door else (s.buildings[t.src] as Building).inventory
		_reserve("d" if t.src_door else "s", t.src, t.good, -t.planned)
		t.carried = from.remove(t.good, t.planned)
		t.picked_up = true
		if t.carried <= Inventory.EPS:
			_abort(s, ws, t)
			return true
		if not ws.walk_to_building(cid, t.dst if t.dock_a < 0 else t.dock_a):
			_abort(s, ws, t)
		return true
	if t.dock_a >= 0 and not t.boat_done:
		t.boat_started = true  # standing at the first dock: the ride runs in on_seconds (_ride)
		return false
	# Drop.
	var dst: Building = s.buildings[t.dst]
	var inv: Inventory = dst.upgrade_buffer if t.dst_upgrade else (dst.input_buffer if t.dst_input else dst.inventory)
	_reserve(_dst_kind(t), t.dst, t.good, -t.planned)
	var put := inv.add(t.good, t.carried) if inv != null else 0.0
	if dst.site or t.dst_upgrade:  # goods built into a site or an upgrade are used, not moved
		ResourceLedgerSystem.record_used(s, t.good, put, "construction")
	s.events.emit("haul_delivered", {"hauler": cid, "good": t.good, "amount": put, "from": t.src, "to": t.dst})
	t.carried -= put
	if (dst.site and dst.site_delivered()) or (dst.upgrading() and dst.upgrade_delivered()):
		s.refresh_population()  # builders can be allotted now
	_refund(s, t)
	trips.erase(cid)
	_next_or_release(s, ws, cid, in_shift)
	return false


## One step of a river ride (ticket 153): the hauler waits at the first dock while the boat runs. When the ride is
## over the hauler appears at the second dock's door and walks on to the destination.
func _ride(s: Settlement, ws: WalkerSystem, t: Trip, seconds: float) -> void:
	if not s.buildings.has(t.dock_a) or not s.buildings.has(t.dock_b):
		_abort(s, ws, t)
		return
	t.boat_elapsed += seconds
	if t.boat_elapsed + Inventory.EPS < t.boat_seconds:
		return
	t.boat_done = true
	var dock: Building = s.buildings.get(t.dock_b)
	if ws.walker_of(t.citizen_id) == null or dock == null:
		_abort(s, ws, t)
		return
	ws.place_walker(t.citizen_id, ws.door_tile(dock))
	if not ws.walk_to_building(t.citizen_id, t.dst):
		_abort(s, ws, t)


## True while any hauler is riding a river link (a cheap test for the renderer).
func has_boats() -> bool:
	for cid in trips:
		var t: Trip = trips[cid]
		if t.boat_started and not t.boat_done and t.boat_seconds > 0.0:
			return true
	return false


## Boats in flight for the renderer (BoatView): one dict per hauler riding a river link,
## {path: Array[Vector2i], progress: 0..1, downstream: bool}.
func active_boats() -> Array:
	var out := []
	for cid in trips:
		var t: Trip = trips[cid]
		if not t.boat_started or t.boat_done or t.boat_seconds <= 0.0:
			continue
		out.append({"path": t.boat_path, "progress": clampf(t.boat_elapsed / t.boat_seconds, 0.0, 1.0),
				"downstream": t.downstream})
	return out


func _next_or_release(s: Settlement, ws: WalkerSystem, cid: int, in_shift: bool) -> void:
	if in_shift:
		var t := _plan(s, ws, cid)
		if t != null:
			t.citizen_id = cid
			trips[cid] = t
			_start(s, ws, t)
			return
	_release(s, ws, cid, in_shift)


func _release(s: Settlement, ws: WalkerSystem, cid: int, in_shift: bool) -> void:
	var w := ws.walker_of(cid)
	if w == null:
		return
	w.controlled = false
	var c: Citizen = s.citizens.get(cid)
	if in_shift and c != null and c.job_id >= 0:
		ws.walk_to_building(cid, c.job_id)


## Frees reservations, puts carried goods back where they came from when possible, releases the hauler.
func _abort(s: Settlement, ws: WalkerSystem, t: Trip) -> void:
	if not t.picked_up:
		_reserve("d" if t.src_door else "s", t.src, t.good, -t.planned)
	_reserve(_dst_kind(t), t.dst, t.good, -t.planned)
	_refund(s, t)
	trips.erase(t.citizen_id)
	_release(s, ws, t.citizen_id, _in_shift_for(s, s.citizens.get(t.citizen_id)))
	s.events.emit("haul_aborted", {"hauler": t.citizen_id, "good": t.good})


func _refund(s: Settlement, t: Trip) -> void:
	if t.carried <= Inventory.EPS:
		return
	var b: Building = s.buildings.get(t.src)
	if b != null:
		var inv: Inventory = b.door_buffer if t.src_door else b.inventory
		if inv != null:
			t.carried -= inv.add(t.good, t.carried)
