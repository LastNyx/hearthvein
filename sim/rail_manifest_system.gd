class_name RailManifestSystem
extends SimSystem
## Cargo rail manifests (design.md section 8, ticket 37b). The player never edits a manifest: once a day, for every rail
## network (RailSystem), the staffed Rail Depots of its regions trade goods.
##
## Per region and good: stock = everything in the region's storages (the depot is a storage too), demand = a day's Lumen
## upkeep and recipe inputs of its finished buildings at their current staffing, plus food for the citizens homed there
## (all food goods count as one "food" demand). target = demand x LogisticsDef.manifest_cover_days; surplus = stock -
## target, need = target - stock. Needs are filled largest first from the linked depot with the largest surplus, each
## depot sending at most LogisticsDef.train_capacity units a day. A good nobody demands is never moved.
##
## A depot needs at least one hauler assigned to send or receive. Loading takes goods straight out of the source region's
## storages. The shipment is in transit for (track tiles of the shortest path) / LogisticsDef.train_speed hours, then
## lands in the destination depot; what does not fit goes to other storages of that region, and what still has no room
## stays in transit and retries every hour. A shipment whose depots are no longer linked waits; one whose depot is gone
## goes back to its source region when there is room (else it is lost). Haulers never leave their region for rail.

const SAVE_KEY := "rail_manifest"
const FOOD := "@food"

## In transit: {from, to, goods (good -> amount), depart (hour), arrive (hour)}. Plain data, saved.
var _ships: Array = []
## depot pair -> Array[Vector2i] track path (empty when no path). A cache, dropped when track or buildings change.
var _paths: Dictionary = {}
var _paths_version: Vector2i = Vector2i(-1, -1)


func save_state() -> Dictionary:
	var out := []
	for sh: Dictionary in _ships:
		out.append({"from": sh["from"], "to": sh["to"], "goods": SaveGame.pairs(sh["goods"]),
			"depart": sh["depart"], "arrive": sh["arrive"]})
	return {"ships": out}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_ships.clear()
	for e: Dictionary in d["ships"]:
		_ships.append({"from": int(e["from"]), "to": int(e["to"]), "goods": SaveGame.unpairs(e["goods"]),
			"depart": float(e["depart"]), "arrive": float(e["arrive"])})
	_paths.clear()
	_paths_version = Vector2i(-1, -1)


## Trains in flight for the renderer: [{from_depot, to_depot, goods, depart_hour, arrive_hour, progress 0..1,
## path: Array[Vector2i]}]. The path
## runs from the track tile beside the from depot to the one beside the to depot; progress is the share of the trip
## done (1.0 while waiting to unload). The path is empty when the track is broken.
func shipments(s: Settlement) -> Array:
	var now := float(s.clock.total_hours) + s._hour_acc / GameClock.REAL_SECONDS_PER_HOUR
	var out := []
	for sh: Dictionary in _ships:
		var span := maxf(float(sh["arrive"]) - float(sh["depart"]), 0.000001)
		out.append({
			"from_depot": sh["from"], "to_depot": sh["to"], "goods": (sh["goods"] as Dictionary).duplicate(),
			"depart_hour": float(sh["depart"]), "arrive_hour": float(sh["arrive"]),
			"progress": clampf((now - float(sh["depart"])) / span, 0.0, 1.0),
			"path": _path(s, int(sh["from"]), int(sh["to"])),
		})
	return out


## Units in transit of a good (all of them when good is "").
func in_transit(good: String = "") -> float:
	var sum := 0.0
	for sh: Dictionary in _ships:
		for g in sh["goods"]:
			if good == "" or g == good:
				sum += float(sh["goods"][g])
	return sum


# ---------------------------------------------------------------- arrivals (hourly)

func on_hour(s: Settlement) -> void:
	if _ships.is_empty():
		return
	var rail := s.get_system(RailSystem) as RailSystem
	var keep := []
	for sh: Dictionary in _ships:
		if float(s.clock.total_hours) + 0.000001 < float(sh["arrive"]):
			keep.append(sh)
			continue
		var goods: Dictionary = sh["goods"]
		var to: Building = s.buildings.get(int(sh["to"]))
		if to != null and rail.linked(s, int(sh["from"]), int(sh["to"])):
			_unload(s, to, goods)
		elif to == null or not s.buildings.has(int(sh["from"])):
			var back: Building = s.buildings.get(int(sh["from"]))
			if back != null:
				_unload(s, back, goods)
			goods.clear()  # nowhere to go: lost
		if not goods.is_empty():
			keep.append(sh)
		else:
			s.events.emit("shipment_arrived", {"from": sh["from"], "to": sh["to"]})
	_ships = keep


## Puts goods into the depot, then other storages of its region; whatever has no room stays in `goods`.
func _unload(s: Settlement, depot: Building, goods: Dictionary) -> void:
	var region := _region(s, depot)
	for g in goods.keys():
		var left := float(goods[g])
		for b in _region_storages(s, region, depot):
			if left <= Inventory.EPS:
				break
			left -= b.inventory.add(g, left)
		if left <= Inventory.EPS:
			goods.erase(g)
		else:
			goods[g] = left


# ---------------------------------------------------------------- manifests (daily)

func on_day(s: Settlement) -> void:
	var lg := s.registry.logistics
	var rail := s.get_system(RailSystem) as RailSystem
	if lg == null or rail == null or lg.train_capacity <= 0.0:
		return
	var nets := rail.network_ids(s)
	if nets.is_empty():
		return
	var staffed := _staffed_depots(s, rail)
	if staffed.size() < 2:
		return
	var table := _region_table(s)
	var food_goods := GrowthSystem.food_goods(s.registry)
	var now := float(s.clock.total_hours)
	var sent := {}  # depot -> units sent today
	for net in nets:
		var depots: Array[int] = []
		for d in rail.depots_of_network(s, net):
			if staffed.has(d):
				depots.append(d)
		if depots.size() < 2:
			continue
		var keys := {}
		for d in depots:
			var region := _region(s, s.buildings[d])
			for k in table["demand"].get(region, {}):
				keys[k] = true
		var key_list: Array = keys.keys()
		key_list.sort()
		var pairs := {}  # Vector2i(from, to) -> goods
		for k: String in key_list:
			_plan_key(s, lg, table, depots, k, food_goods, sent, pairs)
		var pair_list: Array = pairs.keys()
		pair_list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		for pr: Vector2i in pair_list:
			var path := _path(s, pr.x, pr.y)
			if path.is_empty():
				continue
			var loaded := {}
			var src_region := _region(s, s.buildings[pr.x])
			for g: String in (pairs[pr] as Dictionary):
				var took := _take(s, src_region, g, float(pairs[pr][g]))
				if took > Inventory.EPS:
					loaded[g] = took
			if loaded.is_empty():
				continue
			_ships.append({"from": pr.x, "to": pr.y, "goods": loaded, "depart": now,
				"arrive": now + float(path.size()) / lg.train_speed})
			s.events.emit("shipment_sent", {"from": pr.x, "to": pr.y, "goods": loaded.duplicate()})


## Matches the needs of one demand key to surpluses, largest need first, from the largest surplus first.
func _plan_key(s: Settlement, lg: LogisticsDef, table: Dictionary, depots: Array[int], key: String,
		food_goods: Array[String], sent: Dictionary, pairs: Dictionary) -> void:
	var surplus := {}
	var need := {}
	for d in depots:
		var region := _region(s, s.buildings[d])
		var target: float = float(table["demand"].get(region, {}).get(key, 0.0)) * lg.manifest_cover_days
		var stock: float = float(table["stock"].get(region, {}).get(key, 0.0))
		if stock > target + Inventory.EPS:
			surplus[d] = stock - target
		elif target > stock + Inventory.EPS:
			need[d] = target - stock
	if surplus.is_empty() or need.is_empty():
		return
	var needy: Array = need.keys()
	needy.sort_custom(func(a: int, b: int) -> bool: return need[a] > need[b] or (need[a] == need[b] and a < b))
	for to: int in needy:
		var want: float = need[to]
		while want >= lg.min_pickup - Inventory.EPS:
			var best := -1
			var best_amt := 0.0
			for from: int in surplus:
				var room := lg.train_capacity - float(sent.get(from, 0.0))
				var amt := minf(float(surplus[from]), room)
				if from != to and amt > best_amt + Inventory.EPS:
					best = from
					best_amt = amt
			if best < 0 or best_amt < lg.min_pickup - Inventory.EPS:
				break
			var qty := minf(want, best_amt)
			var src_region := _region(s, s.buildings[best])
			var plan := _split(table, src_region, key, qty, food_goods)
			if plan.is_empty():
				surplus.erase(best)
				continue
			var pr := Vector2i(best, to)
			var acc: Dictionary = pairs.get(pr, {})
			var total := 0.0
			for g: String in plan:
				acc[g] = float(acc.get(g, 0.0)) + float(plan[g])
				total += float(plan[g])
			pairs[pr] = acc
			sent[best] = float(sent.get(best, 0.0)) + total
			surplus[best] = float(surplus[best]) - total
			want -= total
			if float(surplus[best]) <= Inventory.EPS:
				surplus.erase(best)
			if surplus.is_empty():
				return


## The goods that make up `qty` of a demand key at a source region: the good itself, or for food the food goods with the
## most stock first. Uses the stock snapshot of the table.
func _split(table: Dictionary, region: int, key: String, qty: float, food_goods: Array[String]) -> Dictionary:
	if key != FOOD:
		return {key: qty}
	var have: Dictionary = table["goods"].get(region, {})
	var order: Array = []
	for g in food_goods:
		if float(have.get(g, 0.0)) > Inventory.EPS:
			order.append(g)
	order.sort_custom(func(a: String, b: String) -> bool: return have[a] > have[b])
	var out := {}
	var left := qty
	for g: String in order:
		var t := minf(left, float(have[g]))
		out[g] = t
		left -= t
		if left <= Inventory.EPS:
			break
	return out


## Stock and demand per region: {"stock": region -> key -> amount, "demand": region -> key -> per day,
## "goods": region -> good -> amount}. Keys are goods, except that every food good counts under FOOD.
func _region_table(s: Settlement) -> Dictionary:
	var food := {}
	for g in GrowthSystem.food_goods(s.registry):
		food[g] = true
	var stock := {}
	var goods := {}
	var demand := {}
	var workers := {}
	var homes := {}  # region -> citizens
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id >= 0 and c.job_kind == Citizen.JOB_WORK:
			workers[c.job_id] = int(workers.get(c.job_id, 0)) + 1
		var h: Building = s.buildings.get(c.home_id)
		if h != null:
			var r := _region(s, h)
			homes[r] = int(homes.get(r, 0)) + 1
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.site:
			continue
		var r := _region(s, b)
		if b.inventory != null:
			var st: Dictionary = stock.get(r, {})
			var gd: Dictionary = goods.get(r, {})
			for g: String in b.inventory.goods():
				var a := b.inventory.amount_of(g)
				var k := FOOD if food.has(g) else g
				st[k] = float(st.get(k, 0.0)) + a
				gd[g] = float(gd.get(g, 0.0)) + a
			stock[r] = st
			goods[r] = gd
		if b.paused:
			continue
		var dm: Dictionary = demand.get(r, {})
		if b.def.upkeep_lumen > 0.0:
			dm["lumen"] = float(dm.get("lumen", 0.0)) + b.def.upkeep_lumen
		var w := int(workers.get(id, 0))
		if b.def.recipe != null and w > 0:
			for g in b.def.recipe.inputs:
				dm[g] = float(dm.get(g, 0.0)) + float(b.def.recipe.inputs[g]) * w
		if not dm.is_empty():
			demand[r] = dm
	var per := s.registry.growth.food_per_citizen if s.registry.growth != null else 0.0
	for r in homes:
		var dm: Dictionary = demand.get(r, {})
		dm[FOOD] = float(dm.get(FOOD, 0.0)) + per * float(homes[r])
		demand[r] = dm
	return {"stock": stock, "demand": demand, "goods": goods}


func _staffed_depots(s: Settlement, rail: RailSystem) -> Dictionary:
	var out := {}
	for d in rail.depot_ids(s):
		out[d] = false
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_HAUL and out.has(c.job_id):
			out[c.job_id] = true
	for d in out.keys():
		if not out[d]:
			out.erase(d)
	return out


func _region(s: Settlement, b: Building) -> int:
	return s.map.get_region(b.origin.x, b.origin.y)


## Finished storages of a region, the depot first, then by id.
func _region_storages(s: Settlement, region: int, depot: Building = null) -> Array[Building]:
	var ids: Array = s.buildings.keys()
	ids.sort()
	var out: Array[Building] = []
	if depot != null and depot.inventory != null:
		out.append(depot)
	for id in ids:
		var b: Building = s.buildings[id]
		if b == depot or b.site or b.inventory == null or _region(s, b) != region:
			continue
		out.append(b)
	return out


## Removes up to `amount` of a good from the region's storages (depot first); returns what was taken.
func _take(s: Settlement, region: int, good: String, amount: float) -> float:
	var got := 0.0
	var rail := s.get_system(RailSystem) as RailSystem
	var first: Building = null
	for d in rail.depot_ids(s):
		if _region(s, s.buildings[d]) == region:
			first = s.buildings[d]
			break
	for b in _region_storages(s, region, first):
		if got >= amount - Inventory.EPS:
			break
		got += b.inventory.remove(good, amount - got)
	return got


# ---------------------------------------------------------------- track paths

## Shortest track path between two depots: from a track tile beside `from` to one beside `to`, 4-connected over track.
## Empty when there is none. Cached per pair until track, roads or buildings change.
func _path(s: Settlement, from: int, to: int) -> Array[Vector2i]:
	var key := Vector2i(s.structure_version, s.completion_version)
	if key != _paths_version:
		_paths.clear()
		_paths_version = key
	var pk := Vector2i(from, to)
	if _paths.has(pk):
		return _paths[pk]
	var out: Array[Vector2i] = []
	var a: Building = s.buildings.get(from)
	var b: Building = s.buildings.get(to)
	if a != null and b != null:
		out = _bfs(s, a, b)
	_paths[pk] = out
	return out


func _bfs(s: Settlement, a: Building, b: Building) -> Array[Vector2i]:
	var goal := {}
	for t in s._ring(b):
		if s.track_at(t):
			goal[t] = true
	var parent := {}
	var queue: Array[Vector2i] = []
	for t in s._ring(a):
		if s.track_at(t) and not parent.has(t):
			parent[t] = t
			queue.append(t)
	var head := 0
	var hit := Vector2i(-1, -1)
	var found := false
	while head < queue.size():
		var c := queue[head]
		head += 1
		if goal.has(c):
			hit = c
			found = true
			break
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if not parent.has(n) and s.track_at(n):
				parent[n] = c
				queue.append(n)
	var out: Array[Vector2i] = []
	if not found:
		return out
	var c := hit
	while parent[c] != c:
		out.append(c)
		c = parent[c]
	out.append(c)
	out.reverse()
	return out
