class_name DimmingSystem
extends SimSystem
## The Dimming (design.md section 14, D37, D43). One a year, starting day 1 of winter (PlanetDef.dimming_start_season).
##
## Forecast: on the first day of the season `dimming_forecast_seasons` before (autumn), the length is fixed:
## round(era base x (2 - health / 100)), era base = EraDef.dimming_base_days of Settlement.era_id(), health =
## Settlement.planet_health() at that moment. Events: dimming_forecast {start_day, length} (start_day is the 0-based
## total day number, GameClock.total_days()), dimming_started, dimming_ended, darkness_started, darkness_ended.
##
## During the Dimming: ProductionSystem modifier output_modifier (vein extractors x BuildingDef.dimming_vein_factor,
## or PlanetDef.dimming_vein_factor when the def leaves it 0; others x BuildingDef.dimming_factor), and each day every
## citizen needs light_per_citizen Lumen from storage in
## the region of their home (the Hearth's when homeless): raw Lumen first, then Lumen cells (lumen_per_cell Lumen
## each). Any citizen short = darkness for that day: Spirit hook "darkness" (PlanetDef.darkness_spirit) and
## GrowthSystem blocks growth and immigration (DimmingSystem.is_dark). Darkness clears when the Dimming ends.
##
## HUD query: status(s) -> {state: "none"|"forecast"|"active", start_day, length, days_until, days_left, dark}.

const SAVE_KEY := "dimming"

var _start_day: int = -1
var _length: int = 0
var _active: bool = false
var _dark: bool = false
## Last day's light report: need, drawn_lumen, drawn_cells, short.
var last_light: Dictionary = {}


func save_state() -> Dictionary:
	return {
		"start_day": _start_day,
		"length": _length,
		"active": _active,
		"dark": _dark,
		"last_light": last_light.duplicate(true),
	}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_start_day = int(d["start_day"])
	_length = int(d["length"])
	_active = bool(d["active"])
	_dark = bool(d["dark"])
	last_light = d["last_light"].duplicate(true)


static func is_dark(s: Settlement) -> bool:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	return d != null and d._dark


static func is_active(s: Settlement) -> bool:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	return d != null and d._active


## ProductionSystem modifier: output factor while a Dimming is on.
static func output_modifier(s: Settlement, b: Building) -> float:
	if not is_active(s):
		return 1.0
	if b.def.vein_extractor:
		return b.def.dimming_vein_factor if b.def.dimming_vein_factor > 0.0 \
				else s.registry.planet.dimming_vein_factor
	return b.def.dimming_factor


## Spirit hook "darkness".
static func darkness_factor(s: Settlement) -> float:
	return s.registry.planet.darkness_spirit if is_dark(s) else 0.0


static func length_for(s: Settlement, era_id: String, health: float) -> int:
	var era := s.registry.get_era(era_id)
	var base := era.dimming_base_days if era != null else 2
	return roundi(float(base) * (2.0 - health / 100.0))


func status(s: Settlement) -> Dictionary:
	var today := s.clock.total_days()
	if _start_day < 0:
		return {"state": "none", "dark": false}
	if _active:
		return {"state": "active", "start_day": _start_day, "length": _length, "days_until": 0,
				"days_left": _start_day + _length - today, "dark": _dark}
	return {"state": "forecast", "start_day": _start_day, "length": _length, "days_until": _start_day - today,
			"days_left": _length, "dark": false}


func on_day(s: Settlement) -> void:
	var today := s.clock.total_days()
	if _active and today >= _start_day + _length:
		_active = false
		if _dark:
			_dark = false
			s.events.emit("darkness_ended", {})
		s.events.emit("dimming_ended", {"start_day": _start_day, "length": _length})
		_start_day = -1
	if not _active and _start_day >= 0 and today >= _start_day:
		_active = true
		s.events.emit("dimming_started", {"start_day": _start_day, "length": _length})
	if _active:
		_light(s)


func on_season(s: Settlement) -> void:
	var pd := s.registry.planet
	var spy := GameClock.SEASONS_PER_YEAR
	var ahead := posmod(pd.dimming_start_season - s.clock.season(), spy)
	if ahead != pd.dimming_forecast_seasons % spy or _active or _start_day >= 0:
		return
	_start_day = s.clock.total_days() + ahead * GameClock.DAYS_PER_SEASON
	_length = length_for(s, s.era_id(), s.planet_health())
	s.events.emit("dimming_forecast", {"start_day": _start_day, "length": _length})


func _light(s: Settlement) -> void:
	var pd := s.registry.planet
	var need_by_region := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		var b: Building = s.buildings.get(c.home_id)
		var t: Vector2i = b.origin if b != null else (s.hearth.origin if s.hearth != null else Vector2i.ZERO)
		var r := s.map.get_region(t.x, t.y)
		need_by_region[r] = float(need_by_region.get(r, 0.0)) + pd.light_per_citizen
	var short := 0.0
	var need_total := 0.0
	var lumen := 0.0
	var cells := 0.0
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
		for b in stores:
			if need <= Inventory.EPS:
				break
			var took := b.inventory.remove("lumen_cells", need / pd.lumen_per_cell)
			need -= took * pd.lumen_per_cell
			cells += took
		if need > Inventory.EPS:
			short += need
	last_light = {"need": need_total, "drawn_lumen": lumen, "drawn_cells": cells, "short": short}
	var dark := short > Inventory.EPS
	if dark != _dark:
		_dark = dark
		s.events.emit("darkness_started" if dark else "darkness_ended", {})
