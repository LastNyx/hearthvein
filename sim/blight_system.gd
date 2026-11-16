class_name BlightSystem
extends SimSystem
## Blight spread (design.md section 12, D16). Blight is a tile state (MapState.blight), not a terrain, so a blighted
## tile keeps its ground and art. Every finished building with blight_radius > 0 (any extractor def) blights, each
## blight_period_days days, the nearest non-blighted tile within its radius (distance from the closest footprint tile,
## ties: lower y then lower x). Water tiles and the extractor's own footprint are never chosen. Removing the extractor
## stops the spread (its counter goes with it); existing blight stays. Sites do nothing.
##
## Hooks for later tickets: `blockers` is a list of Callables (settlement, tile) -> bool; a tile for which any returns
## true cannot be blighted (Purifier Tower r4, Park footprint: tickets 30, 33). Cleaning (tickets 30, 33, 43) calls
## Settlement.set_blighted(tile, false). River fouling (tile next to blight) is ticket 29: it reads map.blight and the
## "blight_changed" event.
##
## Also the Spirit blight factor (see spirit_factor) and blight queries.

const SAVE_KEY := "blight"

## Share of homes counted with blight "within 2 tiles" (Chebyshev, from any footprint tile).
const HOME_REACH := 2

var blockers: Array[Callable] = []
var _days: Dictionary = {}  # building id -> days since its last blight
## Staffed job buildings for the next_tile scan in progress, empty outside it (a runtime cache): a shield reads it
## instead of rescanning every citizen for every candidate tile.
var _staffed: Dictionary = {}


func _init() -> void:
	blockers.append(_shield_block)


func save_state() -> Dictionary:
	return {"days": _days.duplicate()}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_days = d["days"].duplicate()


func on_day(s: Settlement) -> void:
	var live := {}
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.site or b.def.blight_radius <= 0 or b.def.blight_period_days <= 0:
			continue
		live[bid] = true
		var d: int = _days.get(bid, 0) + 1
		if d >= b.def.blight_period_days:
			d = 0
			var t := next_tile(s, b)
			if t.x >= 0:
				s.set_blighted(t, true)
		_days[bid] = d
	for bid in _days.keys():
		if not live.has(bid):
			_days.erase(bid)


## The tile the building would blight next, (-1, -1) when its radius is full. Blocked tiles are skipped, so the
## spread picks the next eligible tile instead (the nearest one after them), and blights nothing when none is left.
func next_tile(s: Settlement, b: Building) -> Vector2i:
	_staffed = _collect_staffed(s)
	var t := _next_tile(s, b)
	_staffed.clear()
	return t


func _next_tile(s: Settlement, b: Building) -> Vector2i:
	var r := b.def.blight_radius
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for ft in b.tiles():
		for y in range(ft.y - r, ft.y + r + 1):
			for x in range(ft.x - r, ft.x + r + 1):
				var d := (x - ft.x) * (x - ft.x) + (y - ft.y) * (y - ft.y)
				if d > r * r or d > best_d or not MapState.in_bounds(x, y) or s.map.is_blighted(x, y):
					continue
				if s.map.terrain_id_at(x, y) == "water" or s.building_at(Vector2i(x, y)) == b:
					continue
				if d == best_d and (y > best.y or (y == best.y and x >= best.x)):
					continue
				if _blocked(s, Vector2i(x, y)):
					continue
				best = Vector2i(x, y)
				best_d = d
	return best


func _blocked(s: Settlement, t: Vector2i) -> bool:
	for f in blockers:
		if bool(f.call(s, t)):
			return true
	return false


## Building ids with at least one working citizen, one pass instead of one per shield and tile.
func _collect_staffed(s: Settlement) -> Dictionary:
	var out := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK:
			out[c.job_id] = true
	return out


## The default shield (design.md section 12): a finished building with blight_proof keeps its own footprint clear
## (the Park; the land itself, so pausing it changes nothing), and every working building with blight_block_radius > 0
## keeps new blight out of that radius. "Working" is the Cleanser rule (staffed and its Lumen upkeep paid, ticket 30),
## so an unstaffed, paused or unpaid Purifier Tower shields nothing.
func _shield_block(s: Settlement, t: Vector2i) -> bool:
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if not b.site and b.def.blight_proof and b.footprint().has_point(t):
			return true
		var r := b.def.blight_block_radius
		if r <= 0 or not CleaningSystem.is_working(s, b, _staffed):
			continue
		if _footprint_dist2(b, t) <= r * r:
			return true
	return false


## Squared distance from the tile to the closest tile of the building's footprint.
static func _footprint_dist2(b: Building, t: Vector2i) -> int:
	var best := 1 << 30
	for ft in b.tiles():
		var d := (t.x - ft.x) * (t.x - ft.x) + (t.y - ft.y) * (t.y - ft.y)
		if d < best:
			best = d
	return best


## Number of blighted tiles on the map.
static func count(s: Settlement) -> int:
	return s.map.blight.count(1)  # native count; blight bytes are 0/1


## True when the tile or any tile within HOME_REACH of the building's footprint is blighted.
static func near_blight(s: Settlement, b: Building) -> bool:
	var r := b.footprint().grow(HOME_REACH)
	for y in range(maxi(r.position.y, 0), mini(r.end.y, MapState.HEIGHT)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, MapState.WIDTH)):
			if s.map.is_blighted(x, y):
				return true
	return false


## True when blight stops this building's production: its def has a blight_halt_reach, the current tier does not
## ignore blight (Greenhouse III), and a tile within that reach of the footprint is blighted.
static func halts_production(s: Settlement, b: Building) -> bool:
	var reach := b.def.blight_halt_reach
	if reach <= 0:
		return false
	var td := b.tier_def(s.registry)
	if td != null and td.ignores_blight:
		return false
	var r := b.footprint().grow(reach)
	for y in range(maxi(r.position.y, 0), mini(r.end.y, MapState.HEIGHT)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, MapState.WIDTH)):
			if s.map.is_blighted(x, y):
				return true
	return false


## Spirit hook "blight": -blight_max x (share of homes with blight within 2 tiles). Homes = finished buildings with beds.
static func spirit_factor(s: Settlement) -> float:
	if count(s) == 0:  # nothing is blighted, so no home is near blight
		return 0.0
	var homes := 0
	var hit := 0
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.site or b.def.housing_beds <= 0:
			continue
		homes += 1
		if near_blight(s, b):
			hit += 1
	if homes == 0:
		return 0.0
	return -s.registry.spirit.blight_max * float(hit) / float(homes)
