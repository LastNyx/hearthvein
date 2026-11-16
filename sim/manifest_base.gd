class_name ManifestBase
extends SimSystem
## Shared freight logic of the rail manifests (RailManifestSystem, ticket 37b) and the airship freight (AirshipSystem,
## ticket 38): the regional stock/demand table, the surplus -> need matching with a per-hub daily capacity, shipments in
## transit (plain data, saved) and unloading into a region's storages. A subclass decides which hubs may trade, how long
## a trip takes and whether a shipment can land. Hubs are buildings (depots, docks); a hub stands for its region.

const FOOD := "@food"

## In transit: {from, to, goods (good -> amount), depart (hour), arrive (hour)}. Plain data, saved.
var _ships: Array = []
## Event names of a departure and a landing (the rail keeps the 37b names, the airship has its own).
var sent_event := "shipment_sent"
var arrived_event := "shipment_arrived"

func _save_ships() -> Array:
	var out := []
	for sh: Dictionary in _ships:
		out.append({"from": sh["from"], "to": sh["to"], "goods": SaveGame.pairs(sh["goods"]),
			"depart": sh["depart"], "arrive": sh["arrive"]})
	return out

func _load_ships(list: Array) -> void:
	_ships.clear()
	for e: Dictionary in list:
		_ships.append({"from": int(e["from"]), "to": int(e["to"]), "goods": SaveGame.unpairs(e["goods"]),
			"depart": float(e["depart"]), "arrive": float(e["arrive"])})

## Units in transit of a good (all of them when good is "").
func in_transit(good: String = "") -> float:
	var sum := 0.0
	for sh: Dictionary in _ships:
		for g in sh["goods"]:
			if good == "" or g == good:
				sum += float(sh["goods"][g])
	return sum

## Goods in transit toward each region: region -> {good -> amount}. Lets a second system count them as already stocked.
func incoming(s: Settlement) -> Dictionary:
	var out := {}
	for sh: Dictionary in _ships:
		var to: Building = s.buildings.get(int(sh["to"]))
		if to == null:
			continue
		var r := _region(s, to)
		var acc: Dictionary = out.get(r, {})
		for g in sh["goods"]:
			acc[g] = float(acc.get(g, 0.0)) + float(sh["goods"][g])
		out[r] = acc
	return out

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

## Matches the needs of one demand key to surpluses, largest need first, from the largest surplus first; every hub sends
## at most `capacity` units a day (`sent` counts today).
func _plan_key(s: Settlement, lg: LogisticsDef, table: Dictionary, depots: Array[int], key: String,
		food_goods: Array[String], sent: Dictionary, pairs: Dictionary, capacity: float) -> void:
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
				var room := capacity - float(sent.get(from, 0.0))
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

## Removes up to `amount` of a good from the region's storages (the hub `src` first); returns what was taken.
func _take(s: Settlement, src: Building, good: String, amount: float) -> float:
	var got := 0.0
	for b in _region_storages(s, _region(s, src), src):
		if got >= amount - Inventory.EPS:
			break
		got += b.inventory.remove(good, amount - got)
	return got

## Loads the planned pairs {Vector2i(from, to) -> goods} into shipments that arrive after `trip_hours(from, to)`.
## A pair with a negative trip time (no route) is skipped. Emits shipment_sent.
func _dispatch(s: Settlement, pairs: Dictionary, now: float, trip_hours: Callable) -> void:
	var pair_list: Array = pairs.keys()
	pair_list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for pr: Vector2i in pair_list:
		var trip: float = trip_hours.call(pr.x, pr.y)
		if trip < 0.0:
			continue
		var loaded := {}
		for g: String in (pairs[pr] as Dictionary):
			var took := _take(s, s.buildings[pr.x], g, float(pairs[pr][g]))
			if took > Inventory.EPS:
				loaded[g] = took
		if loaded.is_empty():
			continue
		_ships.append({"from": pr.x, "to": pr.y, "goods": loaded, "depart": now, "arrive": now + trip})
		s.events.emit(sent_event, {"from": pr.x, "to": pr.y, "goods": loaded.duplicate()})

## Hourly: lands every shipment whose time is up. `can_land(from, to)` says whether the route still works; a shipment
## that cannot land waits. One whose destination hub is gone goes back to its source region when there is room, else it is
## lost. What does not fit stays in transit and retries every hour.
func _land_ships(s: Settlement, can_land: Callable) -> void:
	if _ships.is_empty():
		return
	var keep := []
	for sh: Dictionary in _ships:
		if float(s.clock.total_hours) + 0.000001 < float(sh["arrive"]):
			keep.append(sh)
			continue
		var goods: Dictionary = sh["goods"]
		var to: Building = s.buildings.get(int(sh["to"]))
		if to != null and can_land.call(int(sh["from"]), int(sh["to"])):
			_unload(s, to, goods)
		elif to == null or not s.buildings.has(int(sh["from"])):
			var back: Building = s.buildings.get(int(sh["from"]))
			if back != null:
				_unload(s, back, goods)
			goods.clear()  # nowhere to go: lost
		if not goods.is_empty():
			keep.append(sh)
		else:
			s.events.emit(arrived_event, {"from": sh["from"], "to": sh["to"]})
	_ships = keep
