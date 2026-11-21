class_name NotificationCenter
extends RefCounted
## Listens on the Settlement event bus and keeps a short list of notices. Each cause (building id + reason, or a
## named condition) fires once and stays quiet until it clears: production_resumed, demolition, a worker arriving,
## health recovering, the Dimming ending. Plain sim-side code, no scene tree.

const REASON_TEXT := {
	"door_full": "%s: output buffer full, needs a hauler",
	"no_forest": "%s: no forest left in range",
	"no_workers": "%s: no workers",
	"too_far": "%s: too far from a builders' yard, build a yard closer",
}
const ISLAND_TEXT := {
	"no_grid": "no grid power",
	"anchor_unstaffed": "its Lift Anchor is unstaffed",
	"short_lumen": "not enough Lumen",
}
const LOW_HEALTH := 40.0
const LOW_HEALTH_CLEAR := 45.0

var s: Settlement
## Every notice ever raised: {text, kind, key, hour}.
var items: Array[Dictionary] = []
var _active: Dictionary = {}  # cause key -> true while the cause stands


func _init(settlement: Settlement) -> void:
	s = settlement
	for kind in ["dimming_forecast", "dimming_ended", "production_halted", "production_resumed", "building_demolished",
			"era_changed", "island_still", "island_resumed", "skyheart_stage", "skyheart_finished",
			"great_dimming_forecast", "great_dimming_started", "great_dimming_ended", "milestone", "season_started", "caravan_arrived", "caravan_left", "flood_forecast"]:
		s.events.subscribe(kind, _on_event)


func is_active(key: String) -> bool:
	return _active.has(key)


## True when a notice was raised (the cause was not already standing).
func raise(key: String, kind: String, text: String) -> bool:
	if _active.has(key):
		return false
	_active[key] = true
	items.append({"text": text, "kind": kind, "key": key, "hour": s.clock.total_hours})
	return true


func clear(key: String) -> void:
	_active.erase(key)


func _clear_building(id: int) -> void:
	for key: String in _active.keys():
		if key.begins_with("%d:" % id):
			_active.erase(key)


func _clear_island(id: int) -> void:
	for key: String in _active.keys():
		if key.begins_with("island:%d:" % id):
			_active.erase(key)


func _name_of(id: int) -> String:
	var b: Building = s.buildings.get(id)
	return b.def.display_name if b != null else "Building"


func _on_event(e: Dictionary) -> void:
	var d: Dictionary = e["data"]
	match e["kind"]:
		"dimming_forecast":
			raise("dimming:%d" % d["start_day"], "dimming",
					"Dimming forecast: lasts %d days" % int(d["length"]))
		"flood_forecast":
			raise("flood:%d" % int(d["start_day"]), "flood",
					"Flood forecast: the river floods tomorrow for %d days" % int(d["days"]))
		"great_dimming_forecast":
			raise("great_dimming:forecast", "dimming", "The Great Dimming is coming in %d days and lasts %d days" % [
					int(d["start_day"]) - s.clock.total_days(), s.registry.planet.great_dimming_days])
		"great_dimming_started":
			raise("great_dimming:started", "dimming", "The Great Dimming has begun")
		"great_dimming_ended":
			clear("great_dimming:forecast")
			clear("great_dimming:started")
		"dimming_ended":
			clear("dimming:%d" % d["start_day"])
		"production_halted":
			var why: String = d["why"]
			if REASON_TEXT.has(why):
				var id: int = d["id"]
				# a new halt reason replaces the old one's standing cause
				for r in ["door_full", "no_forest", "too_far"]:
					if r != why:
						clear("%d:%s" % [id, r])
				raise("%d:%s" % [id, why], "halt", REASON_TEXT[why] % _name_of(id))
		"production_resumed":
			for r in ["door_full", "no_forest", "too_far"]:
				clear("%d:%s" % [d["id"], r])
		"island_still":
			_clear_island(int(d["island"]))
			raise("island:%d:%s" % [d["island"], d["why"]], "halt",
					"Island over region %d is still: %s" % [int(d["region"]), ISLAND_TEXT.get(d["why"], str(d["why"]))])
		"island_resumed":
			_clear_island(int(d["island"]))
		"skyheart_stage":
			raise("skyheart:%d" % d["stage"], "milestone", "Skyheart stage %d done: %s" % [d["stage"], d["name"]])
		"skyheart_finished":
			raise("skyheart:finished", "milestone", "The Skyheart is finished")
		"milestone":
			raise("milestone:%s" % d["id"], "milestone", "Milestone: %s" % d["name"])
		"season_started":
			if d.get("season", "") == "winter":
				raise("winter:%d" % int(d.get("year", 0)), "season", "Lean winter: food x%s" % \
						str(s.registry.planet.winter_food_factor))
		"caravan_arrived":
			raise("caravan:%d" % int(d["id"]), "caravan", str(d["text"]))
		"caravan_left":
			clear("caravan:%d" % int(d["id"]))
		"building_demolished":
			_clear_building(d["id"])
		"era_changed":
			var era := s.registry.get_era(d["to"])
			raise("era:%s" % d["to"], "milestone",
					"Era reached: %s" % (era.display_name if era != null else str(d["to"])))


## Conditions without an event: call once a day. No workers (a finished, unpaused building with worker slots and
## nobody working in it) and low planet health.
func poll() -> void:
	var staffed := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id >= 0 and c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = true
	for id in s.buildings:
		var b: Building = s.buildings[id]
		var key := "%d:no_workers" % id
		if b.site or b.paused or b.def.worker_slots <= 0 or staffed.has(id):
			clear(key)
		else:
			raise(key, "workers", REASON_TEXT["no_workers"] % b.def.display_name)
	var h := s.planet_health()
	if h < LOW_HEALTH:
		raise("planet:low", "planet", "Planet health is low (%d%%)" % roundi(h))
	elif h >= LOW_HEALTH_CLEAR:
		clear("planet:low")


## Notices raised within the last `ttl_hours`, newest last. One entry per cause: a halt that clears and comes back
## (a Reactor whose buffer fills, is hauled, fills again) shows only its newest notice, not a stack of copies.
func recent(ttl_hours: int = 48) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in items:
		if s.clock.total_hours - int(it["hour"]) <= ttl_hours:
			for i in out.size():
				if out[i]["key"] == it["key"]:
					out.remove_at(i)
					break
			out.append(it)
	return out
