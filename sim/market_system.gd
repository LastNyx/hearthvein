class_name MarketSystem
extends SimSystem
## Markets (design.md sections 11 and 16, ticket 23): the day's gold income and the reach that decides which homes
## may count the settlement's food variety. Numbers live in BuildingDef (gold_per_worker_day, market_reach).
##
## Gold: every day each finished, unpaused Market adds gold_per_worker_day for every citizen the JobSystem assigned
## to work there. Assigned workers are used, not only the ones standing at the door, because the day hook runs at
## midnight when nobody is at work. Gold goes to the global counter Settlement.gold, never into an inventory.
## The day's earnings are scaled by UpkeepSystem.output_modifier (x0.5 while the building's Lumen upkeep is unpaid).
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
	var assigned := {}  # building id -> assigned workers
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK and c.job_id >= 0:
			assigned[c.job_id] = int(assigned.get(c.job_id, 0)) + 1
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or b.def.gold_per_worker_day <= 0.0:
			continue
		# Gold is not a recipe output, so the Lumen-upkeep factor is applied here (a Market has no upkeep in data,
		# but a gold building with one would run at x0.5 while unpaid).
		var made := b.def.gold_per_worker_day * float(assigned.get(bid, 0)) * UpkeepSystem.output_modifier(s, b)
		if made > Inventory.EPS:
			s.gold += made


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
## citizens, the one number the old eaten-types bonus used.
func available_food_types(s: Settlement) -> int:
	var types := stored_food_types(s)
	if types.is_empty() or s.citizens.is_empty():
		return 0
	_ensure_reach(s)
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.home_id >= 0 and _in_reach.get(c.home_id, false):
			return types.size()
	return 1


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
