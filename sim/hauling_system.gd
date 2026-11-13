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

var trips: Dictionary = {}  # citizen id -> Trip
var _reserved: Dictionary = {}  # "kind:building:good" -> float; kinds d (door out), s (storage out), i (input in), r (storage in)


## good id -> amount a consumer should hold: its recipe inputs for all worker slots over input_buffer_days.
static func input_need(reg: DataRegistry, def: BuildingDef) -> Dictionary:
	var out := {}
	if def.recipe == null or reg.logistics == null:
		return out
	for g in def.recipe.inputs:
		out[g] = float(def.recipe.inputs[g]) * def.worker_slots * reg.logistics.input_buffer_days
	return out


func on_seconds(s: Settlement, _seconds: float) -> void:
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
	for cid in ids:
		var c: Citizen = s.citizens[cid]
		if c.job_kind != Citizen.JOB_HAUL or trips.has(cid) or not in_shift:
			continue
		var w := ws.walker_of(cid)
		if w == null or w.controlled or not w.path.is_empty() or w.at_building != c.job_id:
			continue
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


func _in_shift(s: Settlement) -> bool:
	var h := s.clock.hour()
	return h >= WalkerSystem.WORK_START_HOUR and h < WalkerSystem.WORK_END_HOUR


# ---------------------------------------------------------------- planning

func _res(kind: String, bid: int, good: String) -> float:
	return _reserved.get("%s:%d:%s" % [kind, bid, good], 0.0)


func _reserve(kind: String, bid: int, good: String, amount: float) -> void:
	var key := "%s:%d:%s" % [kind, bid, good]
	var left: float = _reserved.get(key, 0.0) + amount
	if left <= Inventory.EPS:
		_reserved.erase(key)
	else:
		_reserved[key] = left


## Walking seconds between two building doors, INF when unreachable.
func _walk(ws: WalkerSystem, a: Building, b: Building) -> float:
	var p := ws.find_path(ws.door_tile(a), ws.door_tile(b))
	return INF if p.is_empty() else ws.path_seconds(p)


## Nearest storage (by walking time from `from`, ties lowest id) with room for `amount` of `good`.
func nearest_storage_with_room(s: Settlement, ws: WalkerSystem, from: Building, good: String, amount: float) -> Building:
	var best: Building = null
	var best_t := INF
	var ids: Array = s.buildings.keys()
	ids.sort()
	for id in ids:
		var b: Building = s.buildings[id]
		if b.inventory == null or b.inventory.free_for(good) - _res("r", b.id, good) < amount - Inventory.EPS:
			continue
		var t := 0.0 if b == from else _walk(ws, from, b)
		if t < best_t:
			best = b
			best_t = t
	return best


func _plan(s: Settlement, ws: WalkerSystem, _cid: int) -> Trip:
	var lg := s.registry.logistics
	var ids: Array = s.buildings.keys()
	ids.sort()
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
			if dst == null or (dst != b and _walk(ws, b, dst) == INF):
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
		var need := input_need(s.registry, b.def)
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
	var best: Building = null
	var best_t := INF
	var ids: Array = s.buildings.keys()
	ids.sort()
	for id in ids:
		var b: Building = s.buildings[id]
		if b.inventory == null or b.inventory.amount_of(good) - _res("s", b.id, good) < min_amount - Inventory.EPS:
			continue
		var t := _walk(ws, b, consumer)
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
