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


func unsubscribe(kind: String, callback: Callable) -> void:
	if _subs.has(kind):
		_subs[kind].erase(callback)


func log_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log:
		if e["kind"] == kind:
			out.append(e)
	return out
