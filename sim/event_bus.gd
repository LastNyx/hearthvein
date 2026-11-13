class_name EventBus
extends RefCounted
## One event bus per Settlement. Events are logged (kind, data, hour stamp) and delivered to subscribers.

var log: Array[Dictionary] = []
## Stamped onto each log entry; the Settlement keeps this equal to the clock's total hours.
var now_hours: int = 0
var _subs: Dictionary = {}  # kind -> Array[Callable]; "" subscribes to every kind


func emit(kind: String, data: Dictionary = {}) -> void:
	var entry := {"hour": now_hours, "kind": kind, "data": data}
	log.append(entry)
	for key in [kind, ""]:
		if _subs.has(key):
			for c: Callable in _subs[key].duplicate():
				c.call(entry)


## Callable receives the log entry Dictionary. Empty kind = all events.
func subscribe(kind: String, callback: Callable) -> void:
	if not _subs.has(kind):
		_subs[kind] = []
	_subs[kind].append(callback)


## Drops every subscriber (a swapped-out Settlement's bus: nothing wired to it may fire again).
func clear_subscribers() -> void:
	_subs.clear()


func unsubscribe(kind: String, callback: Callable) -> void:
	if _subs.has(kind):
		_subs[kind].erase(callback)


func log_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log:
		if e["kind"] == kind:
			out.append(e)
	return out


## Only the newest entries of the log are saved (ticket 19c): walker_arrived fires on every arrival, so an untrimmed
## log would make the save grow with years of play. The in-memory log is not trimmed; the loaded one is just shorter.
const SAVED_LOG_LIMIT := 500

## The log and its clock stamp, for a save. Subscribers are views: they attach again after a load.
func to_dict() -> Dictionary:
	var start := maxi(0, log.size() - SAVED_LOG_LIMIT)
	return {"now_hours": now_hours, "log": log.slice(start).duplicate(true)}


static func from_dict(d: Dictionary) -> EventBus:
	var e := EventBus.new()
	e.now_hours = int(d["now_hours"])
	e.log.assign(d["log"])
	return e
