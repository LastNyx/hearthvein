class_name ResourceLedgerSystem
extends SimSystem
## Resource ledger (ticket 109, D7): what the settlement made and used of each good per day, and a 60-day history
## of the stock. The Resources page (ticket 114) reads it; nothing in the sim reads it back.
##
## Made = goods added at a producer's door (ProductionSystem outputs, Market/Tax Office gold). Used = production
## inputs eaten by a recipe, food eaten by citizens, goods delivered into a construction site or an in-place upgrade,
## Lumen and Lumen cells drawn for the Dimming's light, and gold paid for placement and upgrade stages.
## Hauling a good from a door to storage or from storage to an input buffer is not a use: only the consumption is.
##
## Every day start (the day_started event, which fires before any on_day hook) rolls today's counters into
## yesterday's and appends one stock sample per good to its ring: the same totals the HUD shows (composite food,
## Lumen plus battery charge, the gold counter), plain storage totals for every other good. The ring keeps the newest
## 60 samples, oldest first.
##
## Call sites use the static record_made / record_used one-liners, so a hook never has to look the system up itself.

const SAVE_KEY := "ledger"
## Days of stock history kept per good (D7: the Resources page draws 60 days).
const HISTORY_DAYS := 60

var made_today: Dictionary = {}  # good id -> amount
var used_today: Dictionary = {}  # good id -> amount
var made_by_today: Dictionary = {}  # good id -> {building def id -> amount}
var made_yesterday: Dictionary = {}
var used_yesterday: Dictionary = {}
var made_by_yesterday: Dictionary = {}
var _history: Dictionary = {}  # good id -> Array[float], oldest first, at most HISTORY_DAYS


func save_state() -> Dictionary:
	return {
		"made_today": SaveGame.pairs(made_today),
		"used_today": SaveGame.pairs(used_today),
		"made_by_today": SaveGame.pairs(made_by_today),
		"made_yesterday": SaveGame.pairs(made_yesterday),
		"used_yesterday": SaveGame.pairs(used_yesterday),
		"made_by_yesterday": SaveGame.pairs(made_by_yesterday),
		"history": SaveGame.pairs(_history),
	}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	made_today = SaveGame.unpairs(d.get("made_today", []))
	used_today = SaveGame.unpairs(d.get("used_today", []))
	made_by_today = SaveGame.unpairs(d.get("made_by_today", []))
	made_yesterday = SaveGame.unpairs(d.get("made_yesterday", []))
	used_yesterday = SaveGame.unpairs(d.get("used_yesterday", []))
	made_by_yesterday = SaveGame.unpairs(d.get("made_by_yesterday", []))
	_history = SaveGame.unpairs(d.get("history", []))


# ---------------------------------------------------------------- recording

## One good entered the world at a producer's door/output. `def_id` is the producing building's def id, for the
## Resources page's made-by breakdown ("" when there is none).
func note_made(good: String, amount: float, def_id: String) -> void:
	if amount <= Inventory.EPS:
		return
	made_today[good] = float(made_today.get(good, 0.0)) + amount
	if def_id == "":
		return
	var by: Dictionary = made_by_today.get(good, {})
	by[def_id] = float(by.get(def_id, 0.0)) + amount
	made_by_today[good] = by


## One good left the world (eaten, consumed by a recipe, built in, burned for light, paid away). `reason` names the
## call site for a reader; the ledger groups by good only.
func note_used(good: String, amount: float, _reason: String) -> void:
	if amount <= Inventory.EPS:
		return
	used_today[good] = float(used_today.get(good, 0.0)) + amount


## One-line call site form: record at the ledger of `s` when the settlement runs one.
static func record_made(s: Settlement, good: String, amount: float, def_id: String) -> void:
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	if ledger != null:
		ledger.note_made(good, amount, def_id)


static func record_used(s: Settlement, good: String, amount: float, reason: String) -> void:
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	if ledger != null:
		ledger.note_used(good, amount, reason)


# ---------------------------------------------------------------- day roll

## Subscribed to day_started, which fires before the on_day hooks of the new day: yesterday is complete when the
## day's own eating, light and gold hooks begin to record against today.
func on_day_started(_e: Dictionary, s: Settlement) -> void:
	made_yesterday = made_today
	used_yesterday = used_today
	made_by_yesterday = made_by_today
	made_today = {}
	used_today = {}
	made_by_today = {}
	_sample_stock(s)


## Appends one stock sample per good: composite food, Lumen plus battery charge and the gold counter (the HUD's
## numbers), plain storage totals for the rest. The oldest sample drops off past HISTORY_DAYS.
func _sample_stock(s: Settlement) -> void:
	var t := s.totals()
	var food := 0.0
	for g in GrowthSystem.food_goods(s.registry):
		food += float(t.get(g, 0.0))
	var lumen := float(t.get("lumen", 0.0))
	var gs := s.get_system(GridSystem) as GridSystem
	if gs != null:
		lumen += gs.total_charge()
	for id in s.registry.goods:
		var value := 0.0
		match id:
			"food": value = food
			"lumen": value = lumen
			"gold": value = s.gold
			_: value = float(t.get(id, 0.0))
		var ring: Array = _history.get(id, [])
		ring.append(value)
		if ring.size() > HISTORY_DAYS:
			ring.pop_front()
		_history[id] = ring


# ---------------------------------------------------------------- queries

## What `good` made and used today so far, and the made-by-building breakdown: {made, used, made_by}.
func today(good: String) -> Dictionary:
	return {"made": float(made_today.get(good, 0.0)), "used": float(used_today.get(good, 0.0)),
			"made_by": (made_by_today.get(good, {}) as Dictionary).duplicate()}


## The last completed day for `good`: {made, used, made_by}.
func yesterday(good: String) -> Dictionary:
	return {"made": float(made_yesterday.get(good, 0.0)), "used": float(used_yesterday.get(good, 0.0)),
			"made_by": (made_by_yesterday.get(good, {}) as Dictionary).duplicate()}


## Stock samples for `good`, oldest first, at most HISTORY_DAYS.
func history(good: String) -> Array[float]:
	var out: Array[float] = []
	for v in _history.get(good, []):
		out.append(float(v))
	return out
