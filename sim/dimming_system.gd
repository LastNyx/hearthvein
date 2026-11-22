class_name DimmingSystem
extends SimSystem
## The Dimming (design.md section 14, D37, D43). One a year, starting day 1 of winter (PlanetDef.dimming_start_season).
##
## Forecast: on the first day of the season forecast_lead() seasons before (autumn by default, summer with an
## Observatory), the length is fixed:
## round(era base x (2 - health / 100)), era base = EraDef.dimming_base_days of Settlement.era_id(), health =
## Settlement.planet_health() at that moment. Events: dimming_forecast {start_day, length} (start_day is the 0-based
## total day number, GameClock.total_days()), dimming_started, dimming_ended, darkness_started, darkness_ended.
##
## Vein surge (ticket 150, spec N8): when a Dimming ends (a regular one, or the Great Dimming too: it rewards the
## win), every vein extractor makes PlanetDef.vein_surge_factor of its output for PlanetDef.vein_surge_days days,
## through the ProductionSystem modifier vein_surge_modifier. A regular Dimming that yields to the Great one does not
## start a surge. Events: vein_surge_started {days, factor}, vein_surge_ended.
##
## During the Dimming: ProductionSystem modifier output_modifier (vein extractors x BuildingDef.dimming_vein_factor,
## or PlanetDef.dimming_vein_factor when the def leaves it 0; others x BuildingDef.dimming_factor), and each day every
## citizen needs light_per_citizen Lumen from storage in
## the region of their home (the Hearth's when homeless): raw Lumen first, then Lumen cells (lumen_per_cell Lumen
## each), then starlight (ticket 151, starlight_lumen each). Any citizen short = darkness for that day: Spirit hook
## "darkness" (PlanetDef.darkness_spirit) and
## GrowthSystem blocks growth and immigration (DimmingSystem.is_dark). Darkness clears when the Dimming ends.
##
## The Great Dimming (GreatDimmingSystem) replaces it: while that is on, the regular one ends, none starts or is
## forecast inside its window, is_active / is_dark stay true and status() reports it with "great": true.
##
## HUD query: status(s) -> {state: "none"|"forecast"|"active", start_day, length, days_until, days_left, dark}.

const SAVE_KEY := "dimming"

var _start_day: int = -1
var _length: int = 0
var _active: bool = false
var _dark: bool = false
## Vein surge timer (ticket 150): on while _surge_on, from the day it started (1-based day N of the HUD) until the
## start of _surge_until, a day count. _surge_on, not the day arithmetic, is what the modifier reads: the day hooks
## run after the boundary hour has been produced, so the last surge hour still counts and the first normal hour not.
var _surge_on: bool = false
var _surge_from: int = -1
var _surge_until: int = -1
## Last day's light report: need, drawn_lumen, drawn_cells, short.
var last_light: Dictionary = {}


func save_state() -> Dictionary:
	return {
		"start_day": _start_day,
		"length": _length,
		"active": _active,
		"dark": _dark,
		"surge_on": _surge_on,
		"surge_from": _surge_from,
		"surge_until": _surge_until,
		"last_light": last_light.duplicate(true),
	}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_start_day = int(d["start_day"])
	_length = int(d["length"])
	_active = bool(d["active"])
	_dark = bool(d["dark"])
	_surge_on = bool(d.get("surge_on", false))
	_surge_from = int(d.get("surge_from", -1))
	_surge_until = int(d.get("surge_until", -1))
	last_light = d["last_light"].duplicate(true)


static func is_dark(s: Settlement) -> bool:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	return d != null and d._dark


## True during a regular Dimming and during the Great Dimming (which replaces it, GreatDimmingSystem).
static func is_active(s: Settlement) -> bool:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	return (d != null and d._active) or GreatDimmingSystem.is_active(s)


## True while the vein surge runs after a Dimming (ticket 150).
static func vein_surge(s: Settlement) -> bool:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	return d != null and d._surge_on


## 1-based day of the surge ("day 1 of 2"), 0 outside it.
static func vein_surge_day(s: Settlement) -> int:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null or not d._surge_on:
		return 0
	return s.clock.total_days() - d._surge_from + 1


## Length of the surge in days (PlanetDef.vein_surge_days).
static func vein_surge_days(s: Settlement) -> int:
	return s.registry.planet.vein_surge_days


## ProductionSystem modifier: a vein extractor makes PlanetDef.vein_surge_factor while the surge runs, 1.0 otherwise.
static func vein_surge_modifier(s: Settlement, b: Building) -> float:
	if b == null or not b.def.vein_extractor or not vein_surge(s):
		return 1.0
	return s.registry.planet.vein_surge_factor


## ProductionSystem modifier: output factor while a Dimming is on.
static func output_modifier(s: Settlement, b: Building) -> float:
	if not is_active(s):
		return 1.0
	if GreatDimmingSystem.is_active(s):
		var pd := s.registry.planet
		if b.def.vein_extractor:
			return pd.great_dimming_vein_factor
		if b.def.category == "food" and not b.def.great_dimming_immune:
			return pd.great_dimming_food_factor
		return b.def.dimming_factor
	if b.def.vein_extractor:
		return b.def.dimming_vein_factor if b.def.dimming_vein_factor > 0.0 \
				else s.registry.planet.dimming_vein_factor
	return b.def.dimming_factor


## Spirit hook "darkness": PlanetDef.darkness_spirit while dark, scaled by the mean per-home share of the housed
## citizens (home_darkness_share): homes covered by a working Hall of Seasons take half. Homeless citizens count in full.
static func darkness_factor(s: Settlement) -> float:
	if not is_dark(s):
		return 0.0
	var full := s.registry.planet.darkness_spirit
	var halls := _darkness_halls(s)
	if halls.is_empty() or s.citizens.is_empty():
		return full
	var total := 0.0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		total += _share_for(s, halls, s.buildings.get(c.home_id))
	return full * total / float(s.citizens.size())


## Share of the darkness penalty a home takes (1.0 = all, 0.5 = a working Hall of Seasons covers it).
static func home_darkness_share(s: Settlement, home: Building) -> float:
	return _share_for(s, _darkness_halls(s), home)


static func _share_for(s: Settlement, halls: Array[Building], home: Building) -> float:
	var share := 1.0
	if home == null or home.site:
		return share
	for hall in halls:
		if hall.def.darkness_factor < share and CoverageSystem.coverage_reaches(s, hall, home):
			share = hall.def.darkness_factor
	return share


## Finished, unpaused buildings with darkness_factor < 1 that have an assigned worker and are not on a still island.
static func _darkness_halls(s: Settlement) -> Array[Building]:
	var halls: Array[Building] = []
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.def.darkness_factor < 1.0 and not b.site and not b.paused and not IslandSystem.is_still_building(s, b):
			halls.append(b)
	if halls.is_empty():
		return halls
	var assigned := MarketSystem.assigned_workers(s)
	return halls.filter(func(b: Building) -> bool: return int(assigned.get(b.id, 0)) > 0)


## Seasons of warning: PlanetDef.dimming_forecast_seasons, or the longest BuildingDef.forecast_lead_seasons among
## finished, unpaused, staffed buildings that are not on a still island (Observatory, ticket 41d).
static func forecast_lead(s: Settlement) -> int:
	var lead := s.registry.planet.dimming_forecast_seasons
	var cands := {}
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.def.forecast_lead_seasons > lead and not b.site and not b.paused and not IslandSystem.is_still_building(s, b):
			cands[id] = b.def.forecast_lead_seasons
	if cands.is_empty():
		return lead
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK and cands.has(c.job_id):
			lead = maxi(lead, int(cands[c.job_id]))
	return lead


static func length_for(s: Settlement, era_id: String, health: float) -> int:
	var era := s.registry.get_era(era_id)
	var base := era.dimming_base_days if era != null else 2
	var years := CampaignSystem.endless_years(s)
	if years > 0:
		base += years / maxi(1, s.registry.planet.endless_years_per_day)
	return roundi(float(base) * (2.0 - health / 100.0))


func status(s: Settlement) -> Dictionary:
	var today := s.clock.total_days()
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	if g != null and g.start_day() >= 0:
		var gl := s.registry.planet.great_dimming_days
		if GreatDimmingSystem.is_active(s):
			return {"state": "active", "great": true, "start_day": g.start_day(), "length": gl, "days_until": 0,
					"days_left": g.start_day() + gl - today, "dark": _dark}
		return {"state": "forecast", "great": true, "start_day": g.start_day(), "length": gl,
				"days_until": g.start_day() - today, "days_left": gl, "dark": false}
	if _start_day < 0:
		return {"state": "none", "dark": false}
	if _active:
		return {"state": "active", "start_day": _start_day, "length": _length, "days_until": 0,
				"days_left": _start_day + _length - today, "dark": _dark}
	return {"state": "forecast", "start_day": _start_day, "length": _length, "days_until": _start_day - today,
			"days_left": _length, "dark": false}


func on_day(s: Settlement) -> void:
	var today := s.clock.total_days()
	var great_on := GreatDimmingSystem.is_active(s)
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	if _surge_on and today >= _surge_until:
		_end_vein_surge(s)
	if g != null and _start_day >= 0 and not _active and g.blocks_regular(s, _start_day):
		_start_day = -1  # a forecast Dimming that the Great one swallows
	if _active and (great_on or today >= _start_day + _length):
		_active = false
		if _dark and not great_on:
			_dark = false
			s.events.emit("darkness_ended", {})
		s.events.emit("dimming_ended", {"start_day": _start_day, "length": _length})
		_start_day = -1
		if not great_on:  # yielding to the Great Dimming is no reward
			_start_vein_surge(s)
	if _dark and not _active and not great_on:
		_dark = false
		s.events.emit("darkness_ended", {})
	if not _active and not great_on and _start_day >= 0 and today >= _start_day:
		_active = true
		s.events.emit("dimming_started", {"start_day": _start_day, "length": _length})
	if _active or great_on:
		_light(s)


## The Great Dimming ended too: it rewards the win with the same surge (ticket 150). Wired in
## Settlement.add_default_systems on the great_dimming_ended event (the callback takes the log entry, then the bound
## settlement, like the other bus handlers).
func on_great_dimming_ended(_e: Dictionary, s: Settlement) -> void:
	_start_vein_surge(s)


func _start_vein_surge(s: Settlement) -> void:
	var pd := s.registry.planet
	_surge_on = true
	_surge_from = s.clock.total_days()
	_surge_until = _surge_from + pd.vein_surge_days
	s.events.emit("vein_surge_started", {"days": pd.vein_surge_days, "factor": pd.vein_surge_factor})


func _end_vein_surge(s: Settlement) -> void:
	_surge_on = false
	_surge_from = -1
	_surge_until = -1
	s.events.emit("vein_surge_ended", {})


func on_season(s: Settlement) -> void:
	var pd := s.registry.planet
	var spy := GameClock.SEASONS_PER_YEAR
	var ahead := posmod(pd.dimming_start_season - s.clock.season(), spy)
	# The forecast fires on the first season change inside the lead, so an Observatory finished late still forecasts.
	if ahead < 1 or ahead > forecast_lead(s) % spy or _active or _start_day >= 0:
		return
	var start := s.clock.total_days() + ahead * GameClock.DAYS_PER_SEASON
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	if g != null and g.blocks_regular(s, start):
		return
	_start_day = start
	_length = length_for(s, s.era_id(), s.planet_health())
	s.events.emit("dimming_forecast", {"start_day": _start_day, "length": _length})


## Per-citizen light need: PlanetDef.light_per_citizen, or the lowest BuildingDef.light_need_per_citizen among finished
## buildings (the Dawn Beacon, 0.35). A landmark has no workers or upkeep, so a finished one counts at once.
static func light_per_citizen(s: Settlement) -> float:
	if GreatDimmingSystem.is_active(s):
		return s.registry.planet.great_dimming_light
	var need := s.registry.planet.light_per_citizen
	for b: Building in s.buildings.values():
		if not b.site and b.def.light_need_per_citizen > 0.0:
			need = minf(need, b.def.light_need_per_citizen)
	return need


## Light the whole settlement needs each day: light_per_citizen x citizens (the HUD's "needs N Lumen/day").
static func light_need(s: Settlement) -> float:
	return light_per_citizen(s) * float(s.citizens.size())


## Lumen a day the finished, unpaused buildings with Lumen upkeep ask for (nominal, no grid discount).
static func lumen_upkeep(s: Settlement) -> float:
	var total := 0.0
	for b: Building in s.buildings.values():
		if not b.site and not b.paused and b.def.upkeep_lumen > 0.0 and not IslandSystem.is_still_building(s, b):
			total += b.def.upkeep_lumen
	return total


## Estimated Lumen a day the staffed Lumen buildings make in a Dimming (assigned workers x recipe x tier x the
## Dimming factor of the def: a vein extractor's dimming_vein_factor or the planet's, any other def's dimming_factor),
## scaled by the share of the nominal output the town really made yesterday (supply_realised, ticket 186).
static func dimming_supply(s: Settlement) -> float:
	var staffed := MarketSystem.assigned_workers(s)
	var total := 0.0
	for b: Building in s.buildings.values():
		if b.site or b.paused or b.def.recipe == null or not b.def.recipe.outputs.has("lumen"):
			continue
		var workers := mini(int(staffed.get(b.id, 0)), ProductionSystem.worker_slots_for(s, b))
		var f := b.def.dimming_factor
		if b.def.vein_extractor:
			f = b.def.dimming_vein_factor if b.def.dimming_vein_factor > 0.0 else s.registry.planet.dimming_vein_factor
		total += float(b.def.recipe.outputs["lumen"]) * float(workers) * b.output_factor(s.registry) * f
	return total * supply_realised(s)


## Nominal Lumen a day of the staffed Lumen buildings outside a Dimming (assigned workers x recipe x tier).
static func nominal_supply(s: Settlement) -> float:
	var staffed := MarketSystem.assigned_workers(s)
	var total := 0.0
	for b: Building in s.buildings.values():
		if b.site or b.paused or b.def.recipe == null or not b.def.recipe.outputs.has("lumen"):
			continue
		var workers := mini(int(staffed.get(b.id, 0)), ProductionSystem.worker_slots_for(s, b))
		total += float(b.def.recipe.outputs["lumen"]) * float(workers) * b.output_factor(s.registry)
	return total


## Share (0..1) of the nominal Lumen output (nominal_supply) the town really made in the last full day: halted nights,
## blighted veins, unpaid upkeep and full doors make the real output a fraction of the nominal one (184 saw 1/6 to 1/3).
## 1 while no day is recorded yet or nothing is staffed.
static func supply_realised(s: Settlement) -> float:
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	if ledger == null or ledger.history("lumen").is_empty():
		return 1.0
	var nominal := nominal_supply(s)
	if nominal <= Inventory.EPS:
		return 1.0
	return clampf(float(ledger.yesterday("lumen")["made"]) / nominal, 0.0, 1.0)


func _light(s: Settlement) -> void:
	var pd := s.registry.planet
	var need_by_region := {}
	var per_citizen := light_per_citizen(s)
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		var b: Building = s.buildings.get(c.home_id)
		var t: Vector2i = b.origin if b != null else (s.hearth.origin if s.hearth != null else Vector2i.ZERO)
		var r := s.map.get_region(t.x, t.y)
		need_by_region[r] = float(need_by_region.get(r, 0.0)) + per_citizen
	var short := 0.0
	var need_total := 0.0
	var lumen := 0.0
	var cells := 0.0
	var star := 0.0
	for r in need_by_region:
		var need: float = need_by_region[r]
		need_total += need
		var stores: Array[Building] = []
		var ids: Array = s.buildings.keys()
		ids.sort()
		for id in ids:
			var b: Building = s.buildings[id]
			if b.inventory != null and s.map.get_region(b.origin.x, b.origin.y) == r:
				stores.append(b)
		for b in stores:
			if need <= Inventory.EPS:
				break
			var took := b.inventory.remove("lumen", need)
			need -= took
			lumen += took
			ResourceLedgerSystem.record_used(s, "lumen", took, "light")
		for b in stores:
			if need <= Inventory.EPS:
				break
			var took := b.inventory.remove("lumen_cells", need / pd.lumen_per_cell)
			need -= took * pd.lumen_per_cell
			cells += took
			ResourceLedgerSystem.record_used(s, "lumen_cells", took, "light")
		# Starlight caught by an Observatory (ticket 151) covers a short light need at starlight_lumen a unit.
		if pd.starlight_lumen > 0.0:
			for b in stores:
				if need <= Inventory.EPS:
					break
				var took := b.inventory.remove("starlight", need / pd.starlight_lumen)
				need -= took * pd.starlight_lumen
				star += took * pd.starlight_lumen
				ResourceLedgerSystem.record_used(s, "starlight", took, "light")
		if need > Inventory.EPS:
			short += need
	var reservoir := 0.0
	if short > Inventory.EPS and SkyheartSystem.can_pour(s):
		var sky := s.get_system(SkyheartSystem) as SkyheartSystem
		if sky != null:
			reservoir = sky.take(s, short)
			short -= reservoir
	last_light = {"need": need_total, "drawn_lumen": lumen, "drawn_cells": cells, "drawn_starlight": star,
			"drawn_reservoir": reservoir, "short": short}
	var dark := short > Inventory.EPS
	if dark != _dark:
		_dark = dark
		s.events.emit("darkness_started" if dark else "darkness_ended", {})
