class_name MarketSystem
extends SimSystem
## Markets (design.md sections 11 and 16, ticket 23): the day's gold income and the reach that decides which homes
## may count the settlement's food variety. Numbers live in BuildingDef (gold_per_worker_day, market_reach).
##
## Gold: every day each finished, unpaused Market adds gold_per_worker_day for every citizen the JobSystem assigned
## to work there. Assigned workers are used, not only the ones standing at the door, because the day hook runs at
## midnight when nobody is at work. A Tax Office (design.md section 16) is paid the same way: while it has at least
## one assigned worker, each office adds gold_per_citizen_day (0.2) for every citizen in the settlement, so two
## offices pay 0.4 per citizen. Gold goes to the global counter Settlement.gold, never into an inventory.
## The day's earnings are scaled by UpkeepSystem.output_modifier (x0.5 while the building's Lumen upkeep is unpaid).
##
## Luxury goods: a finished, unpaused Market with at least one assigned worker (BuildingDef.sells_goods) also sells
## the stock of every good a GoodDef puts a sale_price on, down to the good's sale_keep. The sold units leave storage
## (all or nothing, `spend_good`) and pay sale_price gold each; the day's take is scaled like the Market's own income.
##
## Reach: a home inside a finished Market's reach can get every food type in storage, so its citizens count the full
## variety; a home with no Market in reach counts at most one type and can never earn a variety bonus on its own.
## The inside/outside flags are cached per home and rebuilt only when roads or buildings change (structure_version),
## so the day hook and the Spirit factor pay one lookup per citizen, not one scan per Market per citizen.
##
## Reach is the longest of the axis gaps between the Market's footprint and the home's footprint (Chebyshev, tile
## edge to tile edge). design.md gives no number; ticket 23 chose 12 tiles from the Market footprint.

## Caches, rebuilt from the layout (left out of saves via test_save's SKIP). The system keeps no runtime state of its
## own: gold lives on the Settlement, and everything else is derived.
var _reach_version: int = -1
var _in_reach: Dictionary = {}  # home building id -> true when a finished Market's reach covers the home


func on_day(s: Settlement) -> void:
	_ensure_reach(s)
	var assigned := assigned_workers(s)
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused:
			continue
		var made := b.def.gold_per_worker_day * float(assigned.get(bid, 0))
		# Tax Office: paid only while its collector (at least one assigned worker) works there. One worker is
		# enough for the whole office; the rate is per citizen, not per worker.
		if b.def.gold_per_citizen_day > 0.0 and int(assigned.get(bid, 0)) > 0:
			made += b.def.gold_per_citizen_day * float(s.citizens.size())
		if made <= Inventory.EPS:
			continue
		# Gold is not a recipe output, so the Lumen-upkeep factor is applied here (neither a Market nor a Tax
		# Office has upkeep in data, but a gold building with one would run at x0.5 while unpaid).
		var paid := made * UpkeepSystem.output_modifier(s, b)
		s.gold += paid
		ResourceLedgerSystem.record_made(s, BuildingDef.GOLD, paid, b.def.id)
	_sell_surplus(s, assigned)


## Each market sells the priced goods' stock above their keep level. Stock is read once per good and reduced as the
## markets sell, so a second market never sells the same units again. Gold is not a stored good, so the take is
## applied through the same Lumen-upkeep factor as a gold rate.
func _sell_surplus(s: Settlement, assigned: Dictionary) -> void:
	var totals := s.totals()
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or not b.def.sells_goods or int(assigned.get(bid, 0)) <= 0:
			continue
		var factor := UpkeepSystem.output_modifier(s, b)
		for gid in s.registry.goods:
			var gd := s.registry.get_good(gid)
			if gd == null or gd.sale_price <= 0.0:
				continue
			var stock := float(totals.get(gid, 0.0))
			var units := stock - gd.sale_keep
			if units <= Inventory.EPS or not s.spend_good(gid, units):
				continue
			var paid := units * gd.sale_price * factor
			s.gold += paid
			totals[gid] = stock - units
			ResourceLedgerSystem.record_used(s, gid, units, "market", b.def.id)
			ResourceLedgerSystem.record_made(s, BuildingDef.GOLD, paid, b.def.id)


## Building id -> number of citizens the JobSystem assigned to it as workers (assigned JOB_WORK, whether or not they
## are standing at the door; the day hook runs at midnight). Shared by the gold rates and the food-type flags.
static func assigned_workers(s: Settlement) -> Dictionary:
	var out := {}  # building id -> assigned workers
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK and c.job_id >= 0:
			out[c.job_id] = int(out.get(c.job_id, 0)) + 1
	return out


## Food types contributed by buildings that stock no food themselves but count as one while staffed (design.md
## section 16 City: the Grand Bazaar "counts as a food type"). A site, a paused building or one with no assigned
## worker contributes nothing. Market reach does not gate it: the flag is the whole rule, in data.
static func extra_food_types(s: Settlement) -> int:
	var assigned := assigned_workers(s)
	var n := 0
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or not b.def.counts_as_food_type:
			continue
		if int(assigned.get(bid, 0)) > 0:
			n += 1
	return n


## Distinct food types currently held anywhere in the settlement's storage (amount above the inventory epsilon).
## Uses GrowthSystem's food-good list and type rule, so a new food good joins variety by its data alone.
static func stored_food_types(s: Settlement) -> Dictionary:
	var out := {}
	var totals := s.totals()
	for g in GrowthSystem.food_goods(s.registry):
		if float(totals.get(g, 0.0)) <= Inventory.EPS:
			continue
		out[GrowthSystem.food_type_of(s.registry, g)] = true
	return out


## How many distinct food types the settlement's citizens can get today. A citizen whose home is in a Market's reach
## counts every type in storage; anyone else (including the homeless) counts at most one. The count is the union over
## citizens, the one number the old eaten-types bonus used. Staffed buildings flagged counts_as_food_type (the Grand
## Bazaar) add one type each on top, because design counts them as a food type without them stocking any food.
func available_food_types(s: Settlement) -> int:
	var types := stored_food_types(s)
	if types.is_empty() or s.citizens.is_empty():
		return 0
	_ensure_reach(s)
	var n := 1
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.home_id >= 0 and _in_reach.get(c.home_id, false):
			n = types.size()
			break
	return n + extra_food_types(s)


## True when any finished Market's reach covers this home building (false for a site or a home with no Market).
func home_covered(s: Settlement, home_id: int) -> bool:
	_ensure_reach(s)
	return _in_reach.get(home_id, false)


## True when a Market's footprint is within its reach of the home's footprint (Chebyshev between rectangles, the
## shared Building.footprint_gap measure CoverageSystem uses too). Static so the geometry can be tested without
## placing anything.
static func market_covers(market: Building, home: Building) -> bool:
	var reach := market.def.market_reach
	return reach > 0 and Building.footprint_gap(market, home) <= reach


## Rebuild the per-home flags when roads or buildings changed (a Market or a home placed or demolished).
func _ensure_reach(s: Settlement) -> void:
	if _reach_version == s.structure_version:
		return
	_reach_version = s.structure_version
	_in_reach.clear()
	var markets: Array[Building] = []
	var homes: Array[Building] = []
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site:
			continue
		if b.def.market_reach > 0:
			markets.append(b)
		if b.def.housing_beds > 0:
			homes.append(b)
	if markets.is_empty():
		return
	for h in homes:
		for m in markets:
			if market_covers(m, h):
				_in_reach[h.id] = true
				break
