class_name CampaignSystem
extends SimSystem
## Win and loss rules (design.md section 18, D51, D52, ticket 45c).
##
## outcome is "" while the run is open, then:
##   "won"     the Great Dimming ended with population > 0 and planet health >= PlanetDef.win_health (50). Event campaign_won.
##   "no_win"  it ended with health below 50: no win, no loss, the run goes on as endless and the win can never be
##             taken later in this run. Event campaign_no_win.
##   "lost"    population hit 0 (checked every hour, once the run has had citizens). Event campaign_lost, once. A lost
##             run only records and emits; the UI (ticket 45d) takes it from there.
## After "won" or "no_win" the run continues. A loss after a win replaces the outcome with "lost".
##
## win_check_enabled (default true, saved): the endless start (ticket 46) turns it off; no won / no_win then, loss still
## applies. Events carry {population, planet_health}.
##
## Endless (ticket 46): endless_start (saved, set by Settlement.new_game) turns win_check_enabled off and keeps the Great
## Dimming from ever being scheduled. endless_began is the 0-based day the endless phase began (-1 = not yet): the day the
## Great Dimming ended in a campaign run, or the first day the era is Ascendant in an endless start. DimmingSystem adds
## one day of base per PlanetDef.endless_years_per_day years since then.

const SAVE_KEY := "campaign"

var outcome: String = ""
var win_check_enabled: bool = true
var endless_start: bool = false
var endless_began: int = -1
## The win has been decided (taken or refused); nothing can set "won" any more.
var _win_closed: bool = false
## The run has had at least one citizen, so an empty fixture does not lose at once.
var _had_citizens: bool = false
var _lost: bool = false


func save_state() -> Dictionary:
	return {"outcome": outcome, "win_check_enabled": win_check_enabled, "win_closed": _win_closed,
			"had_citizens": _had_citizens, "lost": _lost, "endless_start": endless_start,
			"endless_began": endless_began}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	outcome = str(d["outcome"])
	win_check_enabled = bool(d["win_check_enabled"])
	_win_closed = bool(d["win_closed"])
	_had_citizens = bool(d["had_citizens"])
	_lost = bool(d["lost"])
	endless_start = bool(d.get("endless_start", false))
	endless_began = int(d.get("endless_began", -1))


## Turns the endless start on or off (new game option): no win check, no Great Dimming.
func set_endless_start(on: bool) -> void:
	endless_start = on
	win_check_enabled = not on


static func is_endless_start(s: Settlement) -> bool:
	var c := s.get_system(CampaignSystem) as CampaignSystem
	return c != null and c.endless_start


## Whole years since the endless phase began, -1 when it has not.
static func endless_years(s: Settlement) -> int:
	var c := s.get_system(CampaignSystem) as CampaignSystem
	if c == null or c.endless_began < 0:
		return -1
	return (s.clock.total_days() - c.endless_began) / GameClock.DAYS_PER_YEAR


func is_won() -> bool:
	return outcome == "won"


func is_lost() -> bool:
	return outcome == "lost"


func on_day(s: Settlement) -> void:
	if endless_start and endless_began < 0 and s.era_id() == "ascendant":
		endless_began = s.clock.total_days()


func on_hour(s: Settlement) -> void:
	if not s.citizens.is_empty():
		_had_citizens = true
	elif _had_citizens and not _lost:
		_lose(s)


## Called by GreatDimmingSystem the moment it ends.
func on_great_dimming_ended(s: Settlement, population: int, planet_health: float) -> void:
	if endless_began < 0 and not endless_start:
		endless_began = s.clock.total_days()
	if _win_closed or _lost or not win_check_enabled:
		return
	_win_closed = true
	var data := {"population": population, "planet_health": planet_health}
	if population <= 0:
		_lose(s)
	elif planet_health >= s.registry.planet.win_health:
		outcome = "won"
		s.events.emit("campaign_won", data)
	else:
		outcome = "no_win"
		s.events.emit("campaign_no_win", data)


func _lose(s: Settlement) -> void:
	if _lost:
		return
	_lost = true
	outcome = "lost"
	s.events.emit("campaign_lost", {"population": s.citizens.size(), "planet_health": s.planet_health()})
