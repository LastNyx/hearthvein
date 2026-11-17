class_name MilestoneSystem
extends SimSystem
## Milestones (design.md section 19, D41, ticket 46b). The list is data (data/milestones/*.tres, MilestoneDef): this
## system knows how to check each kind. Each milestone fires once per run: the earned ids (in the order earned) are
## saved with the run, and a fire emits event "milestone" {id, name} (NotificationCenter toasts "Milestone: <name>").
##
## When checked: state kinds (population, era, tier III, regions, rail, island, planet health) once a day, cheap loops
## only; event kinds on their events (dimming_ended, skyheart_finished, campaign_won, wired in
## Settlement.add_default_systems). A regular Dimming that ends with population > 0 is "First Dimming survived" and
## counts toward the streak; any day of darkness inside a regular Dimming resets the streak (the Great Dimming does
## not count either way). Planet recovery needs the dip first: fell_below_50 is saved.
##
## Lifetime list: outside the save, in a JSON file {id: {date: in-game date label, seed: run seed}} at the static lifetime_path (Main sets
## user://milestones.json; "" = not recorded, the default so tests stay out of the real file). A first-time-ever
## milestone is appended with the in-game date and the run seed; loading a run never removes entries. Endless-start runs earn them too.

const SAVE_KEY := "milestones"

## Where the lifetime list lives. Static so every Settlement of a session shares it; tests point it at /tmp.
static var lifetime_path: String = ""

var _earned: Array[String] = []
var _fell_below: bool = false
var _streak: int = 0
## A regular Dimming is on and has had a dark day so far.
var _dark_seen: bool = false


func save_state() -> Dictionary:
	return {"earned": _earned.duplicate(), "fell_below": _fell_below, "streak": _streak, "dark_seen": _dark_seen}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_earned.assign(d["earned"])
	_fell_below = bool(d["fell_below"])
	_streak = int(d["streak"])
	_dark_seen = bool(d["dark_seen"])


## Ids earned this run, in the order earned.
func earned() -> Array[String]:
	return _earned


func has(id: String) -> bool:
	return _earned.has(id)


## Consecutive regular Dimmings with no darkness day so far.
func streak() -> int:
	return _streak


## Lifetime list: id -> {date, seed} of the first time earned. Empty when no path is set or the file is missing.
static func lifetime() -> Dictionary:
	if lifetime_path == "" or not FileAccess.file_exists(lifetime_path):
		return {}
	var f := FileAccess.open(lifetime_path, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}


static func _record_lifetime(id: String, s: Settlement) -> void:
	if lifetime_path == "":
		return
	var all := lifetime()
	if all.has(id):
		return
	all[id] = {"date": s.clock.label(), "seed": s.map.seed_used}
	var f := FileAccess.open(lifetime_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all, "\t"))


## EventBus handler (the Settlement is bound as the last argument).
func on_event(e: Dictionary, s: Settlement) -> void:
	match e["kind"]:
		"dimming_ended":
			if GreatDimmingSystem.is_active(s):
				_dark_seen = false
				return  # the Great Dimming swallowed it
			if s.citizens.size() > 0:
				_fire_kind(s, "dimming_survived")
			_streak = 0 if _dark_seen else _streak + 1
			_dark_seen = false
			for m in s.registry.milestones_in_order():
				if m.kind == "dimming_streak_no_dark" and _streak >= int(m.amount):
					_fire(s, m)
		"skyheart_finished":
			_fire_kind(s, "skyheart_finished")
		"campaign_won":
			_fire_kind(s, "great_dimming_won")


func on_day(s: Settlement) -> void:
	if DimmingSystem.is_dark(s) and not GreatDimmingSystem.is_active(s):
		_dark_seen = true
	var health := s.planet_health()
	var pop := s.citizens.size()
	var era_order := _era_order(s)
	var regions := -1
	var rail := -1
	for m in s.registry.milestones_in_order():
		if _earned.has(m.id):
			continue
		match m.kind:
			"population":
				if pop >= int(m.amount):
					_fire(s, m)
			"era":
				var e := s.registry.get_era(m.text)
				if e != null and era_order >= e.order:
					_fire(s, m)
			"tier3":
				for b: Building in s.buildings.values():
					if not b.site and b.tier >= 3:
						_fire(s, m)
						break
			"regions_owned":
				if regions < 0:
					regions = _owned_regions(s)
				if regions >= int(m.amount):
					_fire(s, m)
			"rail_regions":
				if rail < 0:
					rail = _rail_regions(s)
				if rail >= int(m.amount):
					_fire(s, m)
			"first_island":
				var isl := s.get_system(IslandSystem) as IslandSystem
				if isl != null and not isl.islands.is_empty():
					_fire(s, m)
			"planet_recovered":
				if health < m.dip:
					_fell_below = true
				elif _fell_below and health > m.amount:
					_fire(s, m)
	# the dip is tracked even once nothing else is left to do
	for m in s.registry.milestones_in_order():
		if m.kind == "planet_recovered" and health < m.dip:
			_fell_below = true


func _era_order(s: Settlement) -> int:
	var e := s.registry.get_era(s.era_id())
	return e.order if e != null else 1


static func _owned_regions(s: Settlement) -> int:
	var n := 0
	for r in MapState.REGION_COUNT:
		if s.map.is_region_owned(r):
			n += 1
	return n


## The most distinct regions one rail network has a depot in.
static func _rail_regions(s: Settlement) -> int:
	var rs := s.get_system(RailSystem) as RailSystem
	if rs == null:
		return 0
	var best := 0
	for nid in rs.network_ids(s):
		var seen := {}
		for did in rs.depots_of_network(s, nid):
			var b: Building = s.buildings[did]
			seen[s.map.get_region(b.origin.x, b.origin.y)] = true
		best = maxi(best, seen.size())
	return best


func _fire_kind(s: Settlement, kind: String) -> void:
	for m in s.registry.milestones_in_order():
		if m.kind == kind:
			_fire(s, m)


func _fire(s: Settlement, m: MilestoneDef) -> void:
	if _earned.has(m.id):
		return
	_earned.append(m.id)
	_record_lifetime(m.id, s)
	s.events.emit("milestone", {"id": m.id, "name": m.display_name})
