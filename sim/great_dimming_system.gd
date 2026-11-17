class_name GreatDimmingSystem
extends SimSystem
## The Great Dimming (design.md sections 14 and 18, D33, D51, ticket 45b). Once per run.
##
## (In an endless start, ticket 46, it is never scheduled.) Finishing the Skyheart (Settlement.complete_site calls schedule) announces it: event great_dimming_forecast
## {start_day} and a toast. It starts on day 1 of the first season that begins at least one full season after the
## completion day (one to two seasons of warning) and lasts PlanetDef.great_dimming_days (16) whatever the health.
##
## While it is active it replaces the regular Dimming: DimmingSystem.is_active / is_dark stay true, the regular one ends
## if it was on and none starts or is forecast inside the window. Output factors: vein extractors x
## PlanetDef.great_dimming_vein_factor (0.1), food producers x great_dimming_food_factor (0.5) except defs with
## great_dimming_immune (Fishing Dock), anything else keeps its dimming_factor (DimmingSystem.output_modifier). Light
## need is great_dimming_light (0.75, no Beacon discount). Planet health takes PlanetDef.great_dimming_day (-0.5) a day
## through PlanetHealthSystem.extra_sources. The Skyheart reservoir pours as a last resort (GridSystem.draw and the
## nightly light draw) and stops filling.
##
## Events: great_dimming_forecast {start_day}, great_dimming_started {start_day}, great_dimming_ended {population,
## planet_health} (ticket 45c reads the last one).

const SAVE_KEY := "great_dimming"

var _start_day: int = -1
var _active: bool = false
var _done: bool = false


func save_state() -> Dictionary:
	return {"start_day": _start_day, "active": _active, "done": _done}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_start_day = int(d["start_day"])
	_active = bool(d["active"])
	_done = bool(d["done"])


static func is_active(s: Settlement) -> bool:
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	return g != null and g._active


## True from the announcement until it has ended (scheduled or active).
static func is_pending(s: Settlement) -> bool:
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	return g != null and (g._active or g._start_day >= 0)


## True once the Great Dimming has run its course.
static func is_done(s: Settlement) -> bool:
	var g := s.get_system(GreatDimmingSystem) as GreatDimmingSystem
	return g != null and g._done


## First day of the scheduled or active Great Dimming (0-based total day), -1 when none.
func start_day() -> int:
	return _start_day


## True when a regular Dimming starting on `day` would fall inside the Great Dimming's window (or the Great one is on).
func blocks_regular(s: Settlement, day: int) -> bool:
	if _active:
		return true
	if _start_day < 0:
		return false
	return day >= _start_day and day < _start_day + s.registry.planet.great_dimming_days


## First day of the first season that begins at least one full season after `day`.
static func start_for(completion_day: int) -> int:
	var spd := GameClock.DAYS_PER_SEASON
	var earliest := completion_day + spd
	return ((earliest + spd - 1) / spd) * spd


## Called when the Skyheart is finished. Only the first call per run counts.
func schedule(s: Settlement) -> void:
	if _done or _active or _start_day >= 0 or CampaignSystem.is_endless_start(s):
		return
	_start_day = start_for(s.clock.total_days())
	s.events.emit("great_dimming_forecast", {"start_day": _start_day})


## PlanetHealthSystem.extra_sources entry: percent points per day while active.
static func planet_source(s: Settlement) -> float:
	return s.registry.planet.great_dimming_day if is_active(s) else 0.0


func on_day(s: Settlement) -> void:
	var today := s.clock.total_days()
	var days := s.registry.planet.great_dimming_days
	if _active and today >= _start_day + days:
		_active = false
		_done = true
		var pop := s.citizens.size()
		var health := s.planet_health()
		s.events.emit("great_dimming_ended", {"population": pop, "planet_health": health})
		var cs := s.get_system(CampaignSystem) as CampaignSystem
		if cs != null:
			cs.on_great_dimming_ended(s, pop, health)
		_start_day = -1
	if not _active and not _done and _start_day >= 0 and today >= _start_day:
		_active = true
		s.events.emit("great_dimming_started", {"start_day": _start_day})
