class_name HaulingSystem
extends SimSystem
## Haulers (design.md section 8, D39). Citizens with a haul job (JobSystem, Citizen.JOB_HAUL) carry goods:
##   1. producer door buffer -> nearest storage building with room (Storehouse or Hearth),
##   2. storage -> a consumer's input buffer, up to input_buffer_days of its need.
## Door pickups come first. A trip moves one good, at most LogisticsDef.haul_load units, and is a walk to the
## source door, a pickup, a walk to the destination door and a drop. "Nearest" is walking time between doors.
##
## Hours: haulers only START trips between WalkerSystem.WORK_START_HOUR and WORK_END_HOUR (design.md is silent, so
## they follow the work shift) and only from their job door. A trip in progress always finishes. Every hauler on a
## trip is a controlled walker; it is released (and sent back to its job door) when no task is left or the
## shift is over, after which the normal schedule takes over.
##
## Reservations: when a trip is planned the load is reserved at the source and the room at the destination, so two
## haulers never chase the same units. A trip is aborted (reservations freed, carried goods put back if possible,
## else lost) when the hauler loses its haul job, a building vanishes or the way is blocked.
##
## Construction sites (D48) are consumers too: a site's need is its full cost (non-gold goods), delivered into its
## input buffer. When the last good arrives the Jobs are refreshed so builders can be allotted.
##
## Consumers: a building whose recipe has inputs. Need = input amount x worker slots x input_buffer_days per good
## (input_need). Building upkeep (Lumen) is not hauled yet; add it to input_need when upkeep gets consumed.

class Trip extends RefCounted:
	var citizen_id: int = -1
	var good: String = ""
	var src: int = -1
	var src_door: bool = true  # true: producer door buffer, false: storage inventory
	var dst: int = -1
	var dst_input: bool = false  # true: consumer input buffer, false: storage inventory
	var planned: float = 0.0
	var carried: float = 0.0
	var picked_up: bool = false

	func to_dict() -> Dictionary:
		return {
			"citizen_id": citizen_id, "good": good, "src": src, "src_door": src_door, "dst": dst,
			"dst_input": dst_input, "planned": planned, "carried": carried, "picked_up": picked_up,
		}

	static func from_dict(d: Dictionary) -> Trip:
		var t := Trip.new()
		t.citizen_id = int(d["citizen_id"])
		t.good = str(d["good"])
		t.src = int(d["src"])
		t.src_door = bool(d["src_door"])
		t.dst = int(d["dst"])
		t.dst_input = bool(d["dst_input"])
		t.planned = float(d["planned"])
		t.carried = float(d["carried"])
		t.picked_up = bool(d["picked_up"])
		return t

var trips: Dictionary = {}  # citizen id -> Trip
var _reserved: Dictionary = {}  # "kind:building:good" -> float; kinds d (door out), s (storage out), i (input in), r (storage in)
## Walking seconds per building pair. find_path already caches the path, but summing its tiles again was most of the
## cost of planning a trip (ticket 55: a plan scans every storage building). Doors only move when the grid changes.
var _walk_cache: Dictionary = {}  # "a:b" -> float (INF when unreachable)
var _walk_version: int = -1


## good id -> amount a consumer should hold: its recipe inputs for all worker slots over input_buffer_days.
static func input_need(reg: DataRegistry, def: BuildingDef) -> Dictionary:
	var out := {}
	if def.recipe == null or reg.logistics == null:
		return out
	for g in def.recipe.inputs:
		out[g] = float(def.recipe.inputs[g]) * def.worker_slots * reg.logistics.input_buffer_days
	return out


## What a consumer should hold: a site's full cost (gold is paid on placement), else input_need of its def.
static func need_of(reg: DataRegistry, b: Building) -> Dictionary:
	if not b.site:
		return input_need(reg, b.def)
	var out := {}
	for g in b.def.cost:
		if g != BuildingDef.GOLD:
			out[g] = float(b.def.cost[g])
	return out


## Trips in flight (with their walkers) and the reservations they hold. A trip is mid-walk, mid-carry or waiting for a
## load when saved; without this a load would forget loads already picked up and reserved room.
func save_state() -> Dictionary:
	var tl := []
	for cid in trips:
		tl.append([cid, (trips[cid] as Trip).to_dict()])
	return {"trips": tl, "reserved": _reserved.duplicate(true)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	trips.clear()
	for pair in d["trips"]:
		trips[int(pair[0])] = Trip.from_dict(pair[1])
	_reserved = d["reserved"].duplicate(true)
	# Caches: rebuilt from the loaded layout and grid when first needed.
	_walk_cache.clear()
	_walk_version = -1
	_ids.clear()
	_storages.clear()
	_layout_version = -1
	_layout_count = -1


func on_seconds(s: Settlement, seconds: float) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null or s.registry.logistics == null:
		return
	var in_shift := _in_shift(s)
	for cid in trips.keys():
		var t: Trip = trips[cid]
		var guard := 0
		while trips.has(cid) and guard < 8 and _advance(s, ws, t, in_shift):
			guard += 1
	var ids: Array = s.citizens.keys()
	ids.sort()
	var allowance := _plan_allowance(seconds)
	for cid in ids:
		if allowance <= 0:
			break
		var c: Citizen = s.citizens[cid]
		if c.job_kind != Citizen.JOB_HAUL or trips.has(cid) or not in_shift:
			continue
		var w := ws.walker_of(cid)
		if w == null or w.controlled or not w.path.is_empty() or w.at_building != c.job_id:
			continue
		allowance -= 1
		var t := _plan(s, ws, cid)
		if t != null:
			t.citizen_id = cid
			w.controlled = true
			trips[cid] = t
			_start(s, ws, t)
			var guard := 0
			while trips.has(cid) and guard < 8 and _advance(s, ws, t, in_shift):
				guard += 1


func is_hauling(citizen_id: int) -> bool:
	return trips.has(citizen_id)


## Most trips one on_seconds call may plan (ticket 55). A whole cluster of haulers finishing their trips together
## used to plan every one of them in a single frame, about 0.6 ms each at 600 citizens. The allowance grows with
## `seconds`, so a coarse step (step_hours) is not throttled; a leftover hauler is simply planned a frame later.
const PLAN_PER_SECOND := 120.0


static func _plan_allowance(seconds: float) -> int:
	return maxi(1, int(seconds * PLAN_PER_SECOND))


func _in_shift(s: Settlement) -> bool:
	var h := s.clock.hour()
	return h >= WalkerSystem.WORK_START_HOUR and h < WalkerSystem.WORK_END_HOUR


# ---------------------------------------------------------------- planning

## Building ids in id order and the buildings that have an inventory (storages), cached on the layout version like
## ProductionSystem does: planning used to rebuild and sort the 600-entry building list several times per call and
## scan all of it for storages (ticket 55).
var _ids: Array = []
var _storages: Array[Building] = []
var _layout_version: int = -1
var _layout_count: int = -1


func _layout(s: Settlement) -> void:
	if _layout_version == s.grid_version and _layout_count == s.buildings.size():
		return
	_layout_version = s.grid_version
	_layout_count = s.buildings.size()
	_ids = s.buildings.keys()
	_ids.sort()
	_storages.clear()
	for id in _ids:
		var b: Building = s.buildings[id]
		if b.inventory != null:
			_storages.append(b)


## Nested lookups instead of a formatted key: a plan asks this once per building it scans (ticket 55).
func _res(kind: String, bid: int, good: String) -> float:
	var by_bid: Dictionary = _reserved.get(kind, {})
	var by_good: Dictionary = by_bid.get(bid, {})
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
func _walk(s: Settlement, ws: WalkerSystem, a: Building, b: Building) -> float:
	if _walk_version != s.grid_version:
		_walk_version = s.grid_version
		_walk_cache.clear()
	var key := Vector2i(a.id, b.id)
	if _walk_cache.has(key):
		return _walk_cache[key]
	var p := ws.find_path(ws.door_tile(a), ws.door_tile(b))
	var t := INF if p.is_empty() else ws.path_seconds(p)
	_walk_cache[key] = t
	return t


## Nearest storage (by walking time from `from`, ties lowest id) with room for `amount` of `good`.
func nearest_storage_with_room(s: Settlement, ws: WalkerSystem, from: Building, good: String, amount: float) -> Building:
	_layout(s)
	var best: Building = null
	var best_t := INF
	for b in _storages:
		if b.inventory.free_for(good) - _res("r", b.id, good) < amount - Inventory.EPS:
			continue
		var t := 0.0 if b == from else _walk(s, ws, from, b)
		if t < best_t:
			best = b
			best_t = t
	return best


func _plan(s: Settlement, ws: WalkerSystem, _cid: int) -> Trip:
	var lg := s.registry.logistics
	_layout(s)
	var ids: Array = _ids
	# 1. door buffers: fullest pickup first.
	var best: Trip = null
	var best_avail := 0.0
	for id in ids:
		var b: Building = s.buildings[id]
		if b.door_buffer == null:
			continue
		for g in b.door_buffer.goods():
			var avail: float = b.door_buffer.amount_of(g) - _res("d", b.id, g)
			if avail < lg.min_pickup - Inventory.EPS or avail <= best_avail:
				continue
			var load := minf(lg.haul_load, avail)
			var dst := nearest_storage_with_room(s, ws, b, g, load)
			if dst == null or (dst != b and _walk(s, ws, b, dst) == INF):
				continue
			best = _trip(g, b.id, true, dst.id, false, load)
			best_avail = avail
	if best != null:
		return best
	# 2. storage -> consumer input buffers.
	for id in ids:
		var b: Building = s.buildings[id]
		if b.input_buffer == null:
			continue
		var need := need_of(s.registry, b)
		for g in need:
			var deficit: float = need[g] - b.input_buffer.amount_of(g) - _res("i", b.id, g)
			if deficit < lg.min_pickup - Inventory.EPS:
				continue
			var src := _nearest_source(s, ws, b, g, lg.min_pickup)
			if src == null:
				continue
			var avail := src.inventory.amount_of(g) - _res("s", src.id, g)
			return _trip(g, src.id, false, b.id, true, minf(lg.haul_load, minf(deficit, avail)))
	return null


func _nearest_source(s: Settlement, ws: WalkerSystem, consumer: Building, good: String, min_amount: float) -> Building:
	_layout(s)
	var best: Building = null
	var best_t := INF
	for b in _storages:
		if b.inventory.amount_of(good) - _res("s", b.id, good) < min_amount - Inventory.EPS:
			continue
		var t := _walk(s, ws, b, consumer)
		if t < best_t:
			best = b
			best_t = t
	return best


func _trip(good: String, src: int, src_door: bool, dst: int, dst_input: bool, load: float) -> Trip:
	var t := Trip.new()
	t.good = good
	t.src = src
	t.src_door = src_door
	t.dst = dst
	t.dst_input = dst_input
	t.planned = load
	return t


# ---------------------------------------------------------------- running a trip

func _start(s: Settlement, ws: WalkerSystem, t: Trip) -> void:
	var cid := t.citizen_id
	_reserve("d" if t.src_door else "s", t.src, t.good, t.planned)
	_reserve("i" if t.dst_input else "r", t.dst, t.good, t.planned)
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
	var target := t.dst if t.picked_up else t.src
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
		if not ws.walk_to_building(cid, t.dst):
			_abort(s, ws, t)
		return true
	# Drop.
	var dst: Building = s.buildings[t.dst]
	var inv: Inventory = dst.input_buffer if t.dst_input else dst.inventory
	_reserve("i" if t.dst_input else "r", t.dst, t.good, -t.planned)
	var put := inv.add(t.good, t.carried) if inv != null else 0.0
	s.events.emit("haul_delivered", {"hauler": cid, "good": t.good, "amount": put, "from": t.src, "to": t.dst})
	t.carried -= put
	if dst.site and dst.site_delivered():
		s.refresh_population()  # builders can be allotted now
	_refund(s, t)
	trips.erase(cid)
	_next_or_release(s, ws, cid, in_shift)
	return false


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
	_reserve("i" if t.dst_input else "r", t.dst, t.good, -t.planned)
	_refund(s, t)
	trips.erase(t.citizen_id)
	_release(s, ws, t.citizen_id, _in_shift(s))
	s.events.emit("haul_aborted", {"hauler": t.citizen_id, "good": t.good})


func _refund(s: Settlement, t: Trip) -> void:
	if t.carried <= Inventory.EPS:
		return
	var b: Building = s.buildings.get(t.src)
	if b != null:
		var inv: Inventory = b.door_buffer if t.src_door else b.inventory
		if inv != null:
			t.carried -= inv.add(t.good, t.carried)
