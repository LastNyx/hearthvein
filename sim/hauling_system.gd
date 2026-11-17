class_name HaulingSystem
extends SimSystem
## Haulers (design.md section 8, D39). Citizens with a haul job (JobSystem, Citizen.JOB_HAUL) carry goods:
##   1. producer door buffer -> nearest storage building with room (Storehouse or Hearth),
##   2. storage -> a consumer's input buffer, up to input_buffer_days of its need.
## Door pickups come first. A trip moves one good, at most LogisticsDef.haul_load units (the Handcart Shed raises
## that for haulers in its region, see RegionSystem.handcart_zones), and is a walk to the
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
## Consumers: a building whose recipe has inputs, and (from Town) a building with Lumen upkeep. Need = input amount
## x worker slots x input_buffer_days per good, plus upkeep_lumen x input_buffer_days of Lumen (input_need).

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

	func to_dict() -> Dictionary:
		return {
			"citizen_id": citizen_id, "good": good, "src": src, "src_door": src_door, "dst": dst,
			"dst_input": dst_input, "dst_upgrade": dst_upgrade, "planned": planned, "carried": carried,
			"picked_up": picked_up,
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
		return t

var trips: Dictionary = {}  # citizen id -> Trip
var _reserved: Dictionary = {}  # "kind:building:good" -> float; kinds d (door out), s (storage out), i (input in), r (storage in)
## Walking seconds per building pair. find_path already caches the path, but summing its tiles again was most of the
## cost of planning a trip (ticket 55: a plan scans every storage building). Doors only move when the grid changes.
var _walk_cache: Dictionary = {}  # "a:b" -> float (INF when unreachable)
var _walk_version: int = -1


## good id -> amount a consumer should hold: its recipe inputs for all worker slots over input_buffer_days, plus
## its Lumen upkeep for the same number of days (design.md section 8: consumers keep two days of need).
static func input_need(reg: DataRegistry, def: BuildingDef) -> Dictionary:
	var out := {}
	if reg.logistics == null:
		return out
	if def.recipe != null:
		for g in def.recipe.inputs:
			out[g] = float(def.recipe.inputs[g]) * def.worker_slots * reg.logistics.input_buffer_days
		# Flexible inputs (Kitchen): every listed food type gets two days of one batch's share, so haulers keep
		# whichever two types the Kitchen picks in stock. The per-good buffer cap comes from this same need.
		if def.recipe.any_input_count > 0:
			var each := float(def.recipe.any_input_amount) * def.worker_slots * reg.logistics.input_buffer_days
			for g in def.recipe.any_input_goods:
				out[g] = maxf(float(out.get(g, 0.0)), each)
	if def.upkeep_lumen > 0.0:
		out["lumen"] = float(out.get("lumen", 0.0)) + def.upkeep_lumen * reg.logistics.input_buffer_days
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
	_blds.clear()
	_door_blds.clear()
	_site_blds.clear()
	_layout_version = -1
	_layout_count = -1
	_layout_completion = -1


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
var _layout_completion: int = -1
var _blds: Array[Building] = []  # every building in id order
var _door_blds: Array[Building] = []  # ... those with a door buffer (producers)
var _site_blds: Array[Building] = []  # ... those still under construction


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
	for id in _ids:
		var b: Building = s.buildings[id]
		_blds.append(b)
		if b.site:
			_site_blds.append(b)
		if b.door_buffer != null:
			_door_blds.append(b)
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


func _plan(s: Settlement, ws: WalkerSystem, cid: int) -> Trip:
	var load_cap := _haul_load(s, cid)
	_layout(s)
	# 0. construction sites first: a busy settlement's door buffers must not starve its builders.
	for b in _site_blds:
		if b.input_buffer != null:
			var t := _plan_for_need(s, ws, b, b.input_buffer, need_of(s.registry, b), false, load_cap)
			if t != null:
				return t
	# 1. and 2. take turns going first, so busy producers cannot starve consumers' input buffers (or the reverse).
	if (int(s.clock.total_hours) + cid) % 2 == 0:
		var d := _plan_door(s, ws, load_cap)
		if d != null:
			return d
		return _plan_inputs(s, ws, load_cap)
	var i := _plan_inputs(s, ws, load_cap)
	if i != null:
		return i
	return _plan_door(s, ws, load_cap)


## Door buffers: the fullest pickup first.
func _plan_door(s: Settlement, ws: WalkerSystem, load_cap: float) -> Trip:
	var lg := s.registry.logistics
	var best: Trip = null
	var best_avail := 0.0
	for b in _door_blds:
		for g in b.door_buffer.goods():
			var avail: float = b.door_buffer.amount_of(g) - _res("d", b.id, g)
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


## Storage -> consumer input buffers and in-place upgrade buffers.
func _plan_inputs(s: Settlement, ws: WalkerSystem, load_cap: float) -> Trip:
	for b in _blds:
		if b.input_buffer != null:
			var t := _plan_for_need(s, ws, b, b.input_buffer, _need_cached(s, b), false, load_cap)
			if t != null:
				return t
		if b.upgrading():
			var t := _plan_for_need(s, ws, b, b.upgrade_buffer, upgrade_need(b), true, load_cap)
			if t != null:
				return t
	return null


var _def_need: Dictionary = {}  # BuildingDef -> input_need (a def's need never changes while the game runs)


## need_of, with the per-def result of input_need kept: planning asks it for every building on every call.
func _need_cached(s: Settlement, b: Building) -> Dictionary:
	if b.site:
		return need_of(s.registry, b)
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
	var inv: Inventory = dst.upgrade_buffer if t.dst_upgrade else (dst.input_buffer if t.dst_input else dst.inventory)
	_reserve(_dst_kind(t), t.dst, t.good, -t.planned)
	var put := inv.add(t.good, t.carried) if inv != null else 0.0
	s.events.emit("haul_delivered", {"hauler": cid, "good": t.good, "amount": put, "from": t.src, "to": t.dst})
	t.carried -= put
	if (dst.site and dst.site_delivered()) or (dst.upgrading() and dst.upgrade_delivered()):
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
	_reserve(_dst_kind(t), t.dst, t.good, -t.planned)
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
