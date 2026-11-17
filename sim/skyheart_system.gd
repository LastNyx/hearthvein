class_name SkyheartSystem
extends SimSystem
## The Skyheart (design.md section 18, D33, ticket 45): stage gold and the reservoir.
##
## Stages: a staged landmark (BuildingDef.stages) is one building that stays a site until its last stage is done;
## Settlement.complete_site opens each next stage by itself. A stage's gold (the Crown's 1500) is not paid on placement:
## it is taken from the treasury here, every hour, as soon as the treasury holds all of it.
##
## Reservoir: a finished, unpaused Skyheart on a Lumen grid (GridSystem.on_grid) takes Lumen from that grid every hour,
## at most BuildingDef.reservoir_fill_per_hour, up to reservoir_capacity (3000), through GridSystem.draw so the take
## order (doors, storages, batteries) matches every other draw. It only takes what lies above a keep-back of one day of
## the grid's Lumen upkeep, so the city is never starved to fill it. Lossless: nothing decays or converts. The charge
## is not part of GridSystem.supply() or the battery totals. It never discharges here (ticket 45b pours it during the
## Great Dimming).

const SAVE_KEY := "skyheart"

## building id -> Lumen held in the reservoir.
var _charge: Dictionary = {}


func save_state() -> Dictionary:
	return {"charge": SaveGame.pairs(_charge)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_charge = SaveGame.unpairs(d.get("charge", []))


## Lumen one Skyheart's reservoir holds (0 for anything else).
func reservoir_charge(building_id: int) -> float:
	return float(_charge.get(building_id, 0.0))


## Lumen held by every reservoir in the settlement.
func total_reservoir_charge() -> float:
	var total := 0.0
	for v in _charge.values():
		total += float(v)
	return total


## One day of a grid's Lumen upkeep: the grid's finished, unpaused members' upkeep_lumen at the grid factor, the amount
## UpkeepSystem draws from the grid each day.
static func daily_need(s: Settlement, grid_id: int) -> float:
	var gs := s.get_system(GridSystem) as GridSystem
	if gs == null or s.registry.logistics == null:
		return 0.0
	var need := 0.0
	for bid in gs.members_of(s, grid_id):
		var b: Building = s.buildings[bid]
		if not b.site and not b.paused:
			need += b.def.upkeep_lumen
	return need * s.registry.logistics.grid_upkeep_factor


func on_hour(s: Settlement) -> void:
	for bid: int in _charge.keys():
		if not s.buildings.has(bid):
			_charge.erase(bid)
	var gs := s.get_system(GridSystem) as GridSystem
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid: int in ids:
		var b: Building = s.buildings[bid]
		if b.site:
			s.pay_stage_gold(b)
			continue
		if b.def.reservoir_capacity <= 0.0 or b.paused or gs == null:
			continue
		var gid := gs.grid_of(s, bid)
		if gid < 0:
			continue
		var held := reservoir_charge(bid)
		var room := b.def.reservoir_capacity - held
		if room <= Inventory.EPS:
			continue
		var spare := gs.supply(s, gid) + gs.battery_charge(s, gid) - daily_need(s, gid)
		var want := minf(minf(b.def.reservoir_fill_per_hour, room), spare)
		if want <= Inventory.EPS:
			continue
		_charge[bid] = held + gs.draw(s, gid, want)
