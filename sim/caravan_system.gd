class_name CaravanSystem
extends SimSystem
## The night caravan (ticket 141, spec N9). On a caravan night (every 4-6 nights, from the settlement seed and the day
## alone: arrival_days) a caravan parks at the first finished, unpaused, lit Night Market that has a night worker when
## the night shift starts, offers one of the market's caravan_offers (good x amount for gold, tonight only) and leaves
## at the night shift's end (06:00). One buy per visit. A night with no such market is skipped.
##
## The event "caravan_arrived" {id, text} raises the notice; "caravan_left" {id} clears it.

const SAVE_KEY := "caravan"
## Nights between two caravans: MIN_GAP plus 0 to GAP_SPREAD - 1 (4, 5 or 6).
const MIN_GAP := 4
const GAP_SPREAD := 3

## The visit: {market: building id, day, good, amount, gold, bought}. Empty while no caravan is parked.
var _visit: Dictionary = {}


func save_state() -> Dictionary:
	return {"visit": _visit.duplicate()}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_visit = (d["visit"] as Dictionary).duplicate() if d.get("visit") is Dictionary else {}


## Caravan nights (the day the night shift starts on) up to and including `last_day`, from `seed` alone. Each gap is a
## local generator seeded from the seed and the previous caravan day, never the global one.
static func arrival_days(seed: int, last_day: int) -> Array:
	var out: Array = []
	var day := 0
	while true:
		day += MIN_GAP + _roll(seed, day, GAP_SPREAD)
		if day > last_day:
			break
		out.append(day)
	return out


static func is_caravan_night(seed: int, day: int) -> bool:
	return arrival_days(seed, day).has(day)


static func _roll(seed: int, day: int, n: int) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 100003 + day
	return r.randi() % n


func visiting() -> bool:
	return not _visit.is_empty()


func market_id() -> int:
	return int(_visit.get("market", -1))


## {good, amount, gold} of the parked caravan, empty when none is here.
func offer() -> Dictionary:
	if _visit.is_empty():
		return {}
	return {"good": _visit["good"], "amount": _visit["amount"], "gold": _visit["gold"]}


func bought() -> bool:
	return bool(_visit.get("bought", false))


## "Night caravan: tools x5 for 40 gold, tonight only"; "" when none is here.
func notice_text(s: Settlement = null) -> String:
	if _visit.is_empty():
		return ""
	var name := str(_visit["good"]).replace("_", " ")
	if s != null:
		var gd := s.registry.get_good(str(_visit["good"]))
		if gd != null:
			name = gd.display_name.to_lower()
	return "Night caravan: %s x%d for %d gold, tonight only" % [name, int(_visit["amount"]), int(_visit["gold"])]


func on_hour(s: Settlement) -> void:
	var h := s.clock.hour()
	var w := s.night_window()
	if visiting() and not s.buildings.has(market_id()):
		_leave(s)  # the market was demolished while the caravan was parked
	elif h == w.y and visiting():
		_leave(s)
	elif h == w.x and is_caravan_night(s.map.seed_used, s.clock.total_days()):
		var m := _host(s)
		if m != null:
			start_visit(s, m)


## First finished, unpaused, lit Night Market (lowest id) with a night worker, or null.
func _host(s: Settlement) -> Building:
	var ids: Array = s.buildings.keys()
	ids.sort()
	for id in ids:
		var b: Building = s.buildings[id]
		if b.site or b.paused or b.def.caravan_offers.is_empty() or not s.is_lit(b):
			continue
		if SpiritSystem.night_workers(s, b) > 0:
			return b
	return null


## Parks a caravan at `market` with tonight's offer (picked from the seed and the day). Public so a test or a shot can
## open a visit on any night.
func start_visit(s: Settlement, market: Building) -> void:
	var offers: Array = market.def.caravan_offers
	if offers.is_empty():
		return
	var day := s.clock.total_days()
	var o: Dictionary = offers[_roll(s.map.seed_used, day + 7919, offers.size())]
	_visit = {"market": market.id, "day": day, "good": str(o["good"]), "amount": int(o["amount"]),
			"gold": int(o["gold"]), "bought": false}
	s.events.emit("caravan_arrived", {"id": market.id, "text": notice_text(s)})


func _leave(s: Settlement) -> void:
	var id := market_id()
	_visit = {}
	s.events.emit("caravan_left", {"id": id})


## Why a buy cannot go through right now, "" when it can: "none" (no caravan), "bought", "gold", "room".
func buy_block(s: Settlement) -> String:
	if _visit.is_empty() or not s.buildings.has(market_id()):
		return "none"
	if bought():
		return "bought"
	if s.gold + Inventory.EPS < float(_visit["gold"]):
		return "gold"
	var m: Building = s.buildings[market_id()]
	if s.find_storage_with_room(str(_visit["good"]), m.origin, float(_visit["amount"]), m.layer) == null:
		return "room"
	return ""


## Command: buy the offer. Pays the gold and stores the goods near the market; false (nothing changes) when blocked.
func buy(s: Settlement) -> bool:
	if buy_block(s) != "":
		return false
	var m: Building = s.buildings[market_id()]
	s.gold -= float(_visit["gold"])
	s.store_goods({str(_visit["good"]): float(_visit["amount"])}, m.origin)
	ResourceLedgerSystem.record_made(s, str(_visit["good"]), float(_visit["amount"]), "caravan")
	_visit["bought"] = true
	s.events.emit("caravan_bought", {"id": m.id})
	return true
