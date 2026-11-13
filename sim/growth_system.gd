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
## The first day only records the food stock, so it never counts as surplus.

## Growth bar content in food units.
var bar: float = 0.0
## Days since the last immigration check.
var days_since_immigration: int = 0
## Report of the last day: eaten, hungry, left, surplus, grown, immigrated.
var last_day: Dictionary = {}

var _food_mark: float = -1.0
var _map: MapState = null


## Food goods in eating order: "food" first, then every other good with a food_type, sorted by id.
## (Ticket 23 may replace this with variety rules.)
static func food_goods(reg: DataRegistry) -> Array[String]:
	var out: Array[String] = []
	var rest: Array[String] = []
	for id in reg.goods:
		var g: GoodDef = reg.goods[id]
		if g.id == "food":
			out.append("food")
		elif g.food_type != "":
			rest.append(g.id)
	rest.sort()
	out.append_array(rest)
	return out


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
	var report := {"eaten": 0.0, "hungry": 0, "left": 0, "surplus": 0.0, "grown": 0, "immigrated": 0}

	# 1. eating
	var stores := _food_stores(s, goods)
	var ids: Array = s.citizens.keys()
	ids.sort()
	var hungry := 0
	for id in ids:
		var c: Citizen = s.citizens[id]
		var from := _home_tile(s, c)
		var region := s.map.get_region(from.x, from.y)
		var need := gd.food_per_citizen
		while need > Inventory.EPS:
			var st := _nearest(stores, goods, from, region)
			if st == null:
				break
			for g in goods:
				if need <= Inventory.EPS:
					break
				var took := st.inventory.remove(g, need)
				need -= took
				report["eaten"] += took
		if need > Inventory.EPS:
			hungry += 1
	report["hungry"] = hungry

	# 2. starvation
	if hungry > 0:
		for i in gd.leave_per_day:
			var who := _leaver(s)
			if who >= 0 and s.remove_citizen(who):
				report["left"] += 1

	# 3. growth bar
	var stock := _food_total(s, goods)
	var surplus := 0.0
	if hungry == 0:
		surplus = maxf(0.0, stock - _food_mark)
	_food_mark = stock
	report["surplus"] = surplus
	var pop := s.citizens.size()
	var size := bar_size(s.registry, pop)
	bar = minf(bar + surplus, size)
	if bar >= size - Inventory.EPS and _free_beds(s) > 0 and s.homeless_count() == 0:
		bar -= size
		s.add_citizen()
		report["grown"] = 1
		s.events.emit("citizen_born", {"bar_size": size})

	# 4. immigration
	days_since_immigration += 1
	if days_since_immigration >= gd.immigration_days:
		days_since_immigration = 0
		if s.spirit() >= gd.immigration_spirit and s.citizens.size() <= gd.soft_cap and _free_beds(s) > 0:
			s.add_citizen()
			report["immigrated"] = 1
			s.events.emit("citizen_immigrated", {})
	last_day = report


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
func _nearest(stores: Array[Building], goods: Array[String], from: Vector2i, region: int) -> Building:
	var best: Building = null
	var best_d := 0
	for b in stores:
		if s_region(b) != region or _food_in(b, goods) <= Inventory.EPS:
			continue
		var r := b.footprint()
		var dx := maxi(maxi(r.position.x - from.x, from.x - (r.end.x - 1)), 0)
		var dy := maxi(maxi(r.position.y - from.y, from.y - (r.end.y - 1)), 0)
		var d := dx + dy
		if best == null or d < best_d:
			best = b
			best_d = d
	return best


func s_region(b: Building) -> int:
	return _map.get_region(b.origin.x, b.origin.y)


## Homeless first, then the highest id.
func _leaver(s: Settlement) -> int:
	var best := -1
	var best_homeless := false
	for id in s.citizens:
		var h := (s.citizens[id] as Citizen).is_homeless()
		if best < 0 or (h and not best_homeless) or (h == best_homeless and id > best):
			best = id
			best_homeless = h
	return best
