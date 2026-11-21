class_name GainPopupModel
extends RefCounted
## The spawn rules of the gain popup (ticket 137): a "+N" over a building or a cleared tile when whole goods are
## made. One entry per key (a building id, or a clear tile): amounts merge while the key is throttled and at most one
## popup per key shows every INTERVAL seconds. Only whole units show; a fraction stays held for the next popup.
##
## Pure render state: nothing here reads or writes the sim. The view feeds it ledger deltas (GainPopupView) and draws
## the popups it returns.

## Seconds between two popups of the same key; gains inside the window merge into the next one.
const INTERVAL := 3.0
## Seconds a popup stays on screen: full for the first third, then fading out.
const LIFE := 1.0
## Pixels a popup rises over its whole life.
const RISE := 10.0

## Render-only master switch (the Settings panel's "Gain popups").
var enabled: bool = true
## The settings object the view syncs `enabled` from; when given, its switch gates the popups too.
var settings: GameSettings = null
## Seconds since the view started, advanced by tick().
var now: float = 0.0
## Popups spawned so far (the tests' throttle counter; a popped one is gone after LIFE).
var spawned: int = 0

var _pending: Dictionary = {}  # key -> {good: String, amount: float, at: Vector2, last_spawn: float}
var _popups: Array[Dictionary] = []


## True while popups may spawn: the view's switch and the Settings panel's are both on.
func allowed() -> bool:
	return enabled and (settings == null or settings.gain_popups)


## A gain of `amount` of `good` at `at` (tile coordinates) for `key`. Fractions merge until a whole unit is due.
func note(key: Variant, good: String, amount: float, at: Vector2) -> void:
	if not allowed() or amount <= Inventory.EPS or good == "":
		return
	var rec: Dictionary = _pending.get(key,
			{"good": good, "amount": 0.0, "at": at, "last_spawn": -1.0e9})
	rec["good"] = good
	rec["at"] = at
	rec["amount"] = float(rec["amount"]) + amount
	_pending[key] = rec
	_spawn_if_ready(key)


## Ages the popups (dropping the ones past LIFE) and lets a throttled key show its merged amount once the window
## opens, even when no new gain arrived.
func tick(delta: float) -> void:
	now += delta
	for p in _popups:
		p["age"] = float(p["age"]) + delta
	_popups = _popups.filter(func(p: Dictionary) -> bool: return float(p["age"]) < LIFE)
	for key in _pending.keys():
		_spawn_if_ready(key)


## The popups on screen: [{key, good, units, at, age}], oldest first.
func popups() -> Array[Dictionary]:
	return _popups.duplicate(true)


func _spawn_if_ready(key: Variant) -> void:
	if not allowed() or not _pending.has(key):
		return
	var rec: Dictionary = _pending[key]
	var units := floori(float(rec["amount"]) + Inventory.EPS)
	if units < 1 or now - float(rec["last_spawn"]) < INTERVAL - Inventory.EPS:
		return
	rec["amount"] = float(rec["amount"]) - float(units)
	rec["last_spawn"] = now
	_popups.append({"key": key, "good": rec["good"], "units": units, "at": rec["at"], "age": 0.0})
	spawned += 1
