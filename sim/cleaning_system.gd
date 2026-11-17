class_name CleaningSystem
extends SimSystem
## Cleaners (design.md section 12: Cleanser 1 tile / 2 days in r5; the Purifier Tower and Verdant Spring come later).
## Every finished, unpaused building with BuildingDef.clean_radius > 0 and clean_interval_days > 0 clears, every
## clean_interval_days days it works, the nearest blighted tile within its radius (distance from the closest footprint
## tile, ties: lower y then lower x). Cleaning is generic and data-driven, so later cleaners only need a data row.
##
## A cleaner "works" when it is staffed (at least one assigned worker, like PlanetHealthSystem) and powered (its Lumen
## upkeep was paid for the day, see UpkeepSystem); design.md is silent on staffing, and a site, a paused building, one
## with nobody assigned or one that could not pay its upkeep decides nothing. Its countdown is per building and saved.
##
## Clearing goes through Settlement.set_blighted(tile, false), so the "blight_changed" event, fertility, river fouling
## and the views hear about it exactly as they do for spread.

const SAVE_KEY := "cleaning"

var _days: Dictionary = {}  # building id -> working days since it last cleared a tile


func save_state() -> Dictionary:
	return {"days": SaveGame.pairs(_days)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_days = SaveGame.unpairs(d["days"])


func on_day(s: Settlement) -> void:
	var staffed := {}  # building ids with at least one working citizen, one pass instead of one per building
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = true
	var live := {}
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.def.clean_radius <= 0 or b.def.clean_interval_days <= 0 or b.layer != Building.LAYER_GROUND:
			continue  # blight is ground-only (ticket 40)
		live[bid] = true
		if not is_working(s, b, staffed):
			continue
		var d: int = _days.get(bid, 0) + 1
		if d >= b.def.clean_interval_days:
			var t := next_tile(s, b)
			if t.x >= 0:
				s.set_blighted(t, false)
				d = 0
		_days[bid] = d
	for bid in _days.keys():
		if not live.has(bid):
			_days.erase(bid)


## True when the cleaner may work today: finished and not paused, staffed (or needs no workers) and powered.
static func is_working(s: Settlement, b: Building, staffed: Dictionary = {}) -> bool:
	if b.site or b.paused or b.def.clean_radius <= 0 or b.def.clean_interval_days <= 0:
		return false
	if b.def.worker_slots > 0 and not _staffed(s, b, staffed):
		return false
	if b.def.upkeep_lumen > 0.0:
		var us := s.get_system(UpkeepSystem) as UpkeepSystem
		if us != null and not us.is_paid(b.id):
			return false
	return true


static func _staffed(s: Settlement, b: Building, staffed: Dictionary) -> bool:
	if not staffed.is_empty():
		return staffed.has(b.id)
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			return true
	return false


## The blighted tile this cleaner would clear next, (-1, -1) when none is in reach. Nearest wins; ties go to the
## lower y then the lower x, so the same map always clears in the same order.
func next_tile(s: Settlement, b: Building) -> Vector2i:
	var r := b.def.clean_radius
	var rect := b.footprint().grow(r)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, MapState.HEIGHT)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, MapState.WIDTH)):
			if not s.map.is_blighted(x, y):
				continue
			var d := _dist2(b, x, y)
			if d > r * r:
				continue
			if d < best_d or (d == best_d and (y < best.y or (y == best.y and x < best.x))):
				best = Vector2i(x, y)
				best_d = d
	return best


## Squared distance from the tile to the closest tile of the building's footprint.
static func _dist2(b: Building, x: int, y: int) -> int:
	var best := 1 << 30
	for ft in b.tiles():
		var d := (x - ft.x) * (x - ft.x) + (y - ft.y) * (y - ft.y)
		if d < best:
			best = d
	return best
