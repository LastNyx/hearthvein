class_name GrowthSystem
extends SimSystem
## Daily eating, growth bar, immigration and starvation (design.md section 5, D17, D46). Numbers: GrowthDef.
##
## Once per day (on_day):
##  1. Every citizen eats `food_per_citizen` from the nearest storage building with food IN THE SAME REGION as the
##     citizen (home building's region, the Hearth's when homeless). Food in another region is out of reach, so a
##     region's people can starve beside a full storehouse elsewhere. Goods eaten: see food_goods().
##  2. Citizens who could not eat are hungry. With any hungry citizen (food 0 with a deficit), `leave_per_day`
##     citizens leave: homeless first, then the highest id.
##  3. Surplus = how much the total food stock rose over the day (after eating); with a deficit it is 0. It fills the
##     growth bar. Bar full + a free bed + nobody homeless = one new citizen (appears at the Hearth).
##  4. Every `immigration_days` days: Spirit >= immigration_spirit, a free bed, population not above soft_cap =
##     one newcomer, on top of growth.
## Night arrivals (ticket 146, on_hour at the night shift's start): the same conditions add night_arrival_share to a
## waiting bar; at 1.0 one more newcomer arrives, but only when the arrival point (the Hearth and the tiles around it,
## where roads reach the town) is lit. Dark, the newcomer waits and `night_arrival_blocked` is emitted.
## The first day only records the food stock, so it never counts as surplus.

const SAVE_KEY := "growth"

## Growth bar content in food units.
var bar: float = 0.0
## Days since the last immigration check.
var days_since_immigration: int = 0
## Report of the last day: eaten, hungry, left, surplus, grown, immigrated, types (distinct food types eaten).
var last_day: Dictionary = {}

## Night newcomers waiting at the gate, 0 to 1 (ticket 146).
var night_bar: float = 0.0

var _food_mark: float = -1.0
var _map: MapState = null


func save_state() -> Dictionary:
	return {
		"bar": bar,
		"days_since_immigration": days_since_immigration,
		"last_day": last_day.duplicate(true),
		"food_mark": _food_mark,
		"night_bar": night_bar,
	}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	bar = float(d["bar"])
	days_since_immigration = int(d["days_since_immigration"])
	last_day = d["last_day"].duplicate(true)
	_food_mark = float(d["food_mark"])
	night_bar = float(d.get("night_bar", 0.0))
	_map = null  # set at the start of the next on_day


## Food goods in eating order: highest food_priority first (bread, ticket 140), then "food", then every other good
## with a food_type, sorted by id.
static func food_goods(reg: DataRegistry) -> Array[String]:
	var out: Array[String] = []
	for id in reg.goods:
		var g: GoodDef = reg.goods[id]
		if g.id == "food" or g.food_type != "":
			out.append(g.id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = (reg.goods[a] as GoodDef).food_priority
		var pb: int = (reg.goods[b] as GoodDef).food_priority
		if pa != pb:
			return pa > pb
		if a == "food" or b == "food":
			return a == "food"
		return a < b)
	return out


## Food type of a good for Spirit variety: its food_type, or its own id for plain food.
static func food_type_of(reg: DataRegistry, good: String) -> String:
	var g: GoodDef = reg.goods[good]
	return g.food_type if g.food_type != "" else g.id


## Growth bar size for a population (design.md section 5 plus the D46 soft cap multiplier).
static func bar_size(reg: DataRegistry, pop: int) -> float:
	var gd := reg.growth
	var size := gd.bar_base + float(pop) / gd.bar_pop_divisor
	if pop > gd.soft_cap:
		size *= 1.0 + float(pop - gd.soft_cap) / gd.soft_cap_span
	return size


func bar_size_now(settlement: Settlement) -> float:
	return bar_size(settlement.registry, settlement.citizens.size())


func on_day(settlement: Settlement) -> void:
	var s := settlement
	_map = s.map
	var gd := s.registry.growth
	var goods := food_goods(s.registry)
	if _food_mark < 0.0:
		_food_mark = _food_total(s, goods)
	var report := {"eaten": 0.0, "hungry": 0, "left": 0, "surplus": 0.0, "grown": 0, "immigrated": 0, "types": 0}

	# 1. eating
	var stores := _food_stores(s, goods)
	var store_regions: Array[int] = []  # region of each store, same order (regions do not change while eating)
	for b in stores:
		store_regions.append(s_region(b))
	var ids: Array = s.citizens.keys()
	ids.sort()
	var hungry := 0
	var types := {}
	var spots := {}  # home tile -> region (citizens of one home share it)
	for n in ids.size():
		if stores.is_empty():  # no food left anywhere: everybody still to eat goes hungry
			hungry += ids.size() - n
			break
		var c: Citizen = s.citizens[ids[n]]
		var from := _home_tile(s, c)
		if not spots.has(from):
			spots[from] = s.map.get_region(from.x, from.y)
		var region: int = spots[from]
		var need := gd.food_per_citizen
		while need > Inventory.EPS:
			var si := _nearest(stores, store_regions, goods, from, region)
			if si < 0:
				break
			var st := stores[si]
			for g in goods:
				if need <= Inventory.EPS:
					break
				var took := st.inventory.remove(g, need)
				need -= took
				report["eaten"] += took
				ResourceLedgerSystem.record_used(s, g, took, "eaten")
				if took > Inventory.EPS:
					types[food_type_of(s.registry, g)] = true
			if _food_in(st, goods) <= Inventory.EPS:  # empty store: leave the list so nobody scans it again
				stores.remove_at(si)
				store_regions.remove_at(si)
		if need > Inventory.EPS:
			hungry += 1
	report["hungry"] = hungry
	report["types"] = types.size()

	# 2. starvation
	if hungry > 0:
		for i in gd.leave_per_day:
			var who := leaver(s)
			if who >= 0 and s.remove_citizen(who):
				report["left"] += 1

	# 3. growth bar
	var stock := _food_total(s, goods)
	var surplus := 0.0
	var dark := DimmingSystem.is_dark(s)  # darkness (ticket 15): no growth, no immigration
	if hungry == 0 and not dark:
		surplus = maxf(0.0, stock - _food_mark) * SpiritSystem.growth_multiplier(s)
	_food_mark = stock
	report["surplus"] = surplus
	var pop := s.citizens.size()
	var size := bar_size(s.registry, pop)
	bar = minf(bar + surplus, size)
	if not dark and bar >= size - Inventory.EPS and _free_beds(s) > 0 and s.homeless_count() == 0:
		bar -= size
		s.add_citizen()
		report["grown"] = 1
		s.events.emit("citizen_born", {"bar_size": size})

	# 4. immigration
	days_since_immigration += 1
	if days_since_immigration >= gd.immigration_days:
		days_since_immigration = 0
		if _can_arrive(s, gd):
			s.add_citizen()
			report["immigrated"] = 1
			s.events.emit("citizen_immigrated", {})
	last_day = report


## Whether a newcomer may arrive now: no darkness, Spirit high enough, under the soft cap, a free bed.
func _can_arrive(s: Settlement, gd: GrowthDef) -> bool:
	return not DimmingSystem.is_dark(s) and s.spirit() >= gd.immigration_spirit and s.citizens.size() <= gd.soft_cap \
			and _free_beds(s) > 0


## At the night shift's start: a night newcomer is ready once the share has added up to 1, and arrives if lit.
func on_hour(s: Settlement) -> void:
	var gd := s.registry.growth
	if s.clock.hour() != s.night_window().x or gd.night_arrival_share <= 0.0 or s.hearth == null:
		return
	if not _can_arrive(s, gd):
		return
	night_bar = minf(night_bar + gd.night_arrival_share, 1.0)
	if night_bar < 1.0 - Inventory.EPS:
		return
	if not _arrival_lit(s):
		s.events.emit("night_arrival_blocked", {})
		return
	night_bar = 0.0
	s.add_citizen()
	s.events.emit("citizen_immigrated", {"night": true})


## True when the Hearth or a tile touching it (where the road enters the town) is lit tonight.
func _arrival_lit(s: Settlement) -> bool:
	var r := s.hearth.footprint()
	for x in range(r.position.x - 1, r.end.x + 1):
		for y in range(r.position.y - 1, r.end.y + 1):
			if s.is_tile_lit(Vector2i(x, y)):
				return true
	return false


func _free_beds(s: Settlement) -> int:
	return s.beds_total() - s.citizens.size()


func _home_tile(s: Settlement, c: Citizen) -> Vector2i:
	var home: Building = s.buildings.get(c.home_id)
	if home != null:
		return home.origin
	return s.hearth.origin if s.hearth != null else Vector2i.ZERO


## Finished storage buildings that hold any food right now.
func _food_stores(s: Settlement, goods: Array[String]) -> Array[Building]:
	var out: Array[Building] = []
	var bids: Array = s.buildings.keys()
	bids.sort()
	for bid in bids:
		var b: Building = s.buildings[bid]
		if b.inventory != null and _food_in(b, goods) > Inventory.EPS:
			out.append(b)
	return out


func _food_in(b: Building, goods: Array[String]) -> float:
	var n := 0.0
	for g in goods:
		n += b.inventory.amount_of(g)
	return n


func _food_total(s: Settlement, goods: Array[String]) -> float:
	var n := 0.0
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.inventory != null:
			n += _food_in(b, goods)
	return n


## Nearest (Manhattan, footprint) store in `region` that still has food; ties lowest id (stores are id-sorted).
## Returns its index in `stores`, or -1.
func _nearest(stores: Array[Building], regions: Array[int], _goods: Array[String], from: Vector2i, region: int) -> int:
	var best := -1
	var best_d := 0
	for i in stores.size():
		if regions[i] != region:
			continue
		var r := stores[i].footprint()
		var dx := maxi(maxi(r.position.x - from.x, from.x - (r.end.x - 1)), 0)
		var dy := maxi(maxi(r.position.y - from.y, from.y - (r.end.y - 1)), 0)
		var d := dx + dy
		if best < 0 or d < best_d:
			best = i
			best_d = d
	return best


func s_region(b: Building) -> int:
	return _map.get_region(b.origin.x, b.origin.y)


## Homeless first, then the highest id.
static func leaver(s: Settlement) -> int:
	var best := -1
	var best_homeless := false
	for id in s.citizens:
		var h: bool = (s.citizens[id] as Citizen).home_id < 0  # is_homeless()
		if best < 0 or (h and not best_homeless) or (h == best_homeless and id > best):
			best = id
			best_homeless = h
	return best
