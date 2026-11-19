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
## is not part of GridSystem.supply() or the battery totals. Only during the Great Dimming (ticket 45b) it pours, as a
## last resort, through take(): GridSystem.draw after batteries, and the nightly light draw. It does not fill then.

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


## True when the reservoir may pour now: during the Great Dimming, and (ticket 46) during a regular Dimming once the
## Great Dimming is over or in an endless start. Before the Great Dimming in a campaign run it only fills.
static func can_pour(s: Settlement) -> bool:
	if GreatDimmingSystem.is_active(s):
		return true
	return DimmingSystem.is_active(s) and (GreatDimmingSystem.is_done(s) or CampaignSystem.is_endless_start(s))


## Takes up to `amount` Lumen out of reservoirs, only while can_pour(). grid_id >= 0 limits it to the
## Skyhearts on that grid; -1 takes from any. Returns what was taken.
func take(s: Settlement, amount: float, grid_id: int = -1) -> float:
	if not can_pour(s):
		return 0.0
	var gs := s.get_system(GridSystem) as GridSystem
	var got := 0.0
	var ids: Array = _charge.keys()
	ids.sort()
	for bid: int in ids:
		if got >= amount - Inventory.EPS:
			break
		if grid_id >= 0 and (gs == null or gs.grid_of(s, bid) != grid_id):
			continue
		var have := float(_charge[bid])
		var t := minf(have, amount - got)
		if t > 0.0:
			_charge[bid] = have - t
			got += t
	return got


## Ids (in id order) of the buildings this hour pass can act on: a staged landmark (owes stage gold) or a reservoir.
## Every other building is skipped by the pass whatever its state, so the list is cached on the layout key instead of
## sorting and walking all buildings every hour (ticket 89b).
var _cand: Array = []
var _cand_key := Vector3i(-1, -1, -1)


func _candidates(s: Settlement) -> Array:
	var key := Vector3i(s.buildings.size(), s.grid_version, s.completion_version)
	if key != _cand_key:
		_cand_key = key
		_cand = []
		for bid: int in s.buildings:
			var d := (s.buildings[bid] as Building).def
			if not d.stages.is_empty() or d.reservoir_capacity > 0.0:
				_cand.append(bid)
		_cand.sort()
	return _cand


func on_hour(s: Settlement) -> void:
	for bid: int in _charge.keys():
		if not s.buildings.has(bid):
			_charge.erase(bid)
	var pouring := can_pour(s)
	var gs := s.get_system(GridSystem) as GridSystem
	for bid: int in _candidates(s):
		var b: Building = s.buildings[bid]
		if b.site:
			s.pay_stage_gold(b)
			continue
		if b.def.reservoir_capacity <= 0.0 or b.paused or gs == null or pouring:
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
