class_name ProductionSystem
extends SimSystem
## Production (design.md sections 8 and 21). A building with a recipe makes its recipe amounts per worker per
## work day. Only workers who are at work count (WalkerSystem.is_at_work), pro-rated over time: a work day is the
## 06:00-18:00 shift, so a worker standing at the door for the whole shift makes exactly the recipe amount and the
## walk to work costs a little. At night the workers at the door are the building's night slots (ticket 132); the
## hourly rate is the same, so a night hour makes its share of the recipe. A night-shift building only works while
## it is lit: dark, it halts with "unlit" (Settlement.is_lit, ticket 133). Output goes to the
## building's door buffer (cap from LogisticsDef); a full buffer stops production and sets Building.halt =
## "door_full" (events production_halted / production_resumed).
## Recipes with inputs eat from the input buffer that haulers fill; an empty one halts with "no_input".
## A building with fells_forest (Woodcutter) turns the nearest forest tile in its radius into a stump per
## LogisticsDef.units_per_felled_tile produced; no forest left = halt "no_forest".
## A farm tier that only works on wet ground (the Irrigated Farm, WaterSystem.dry_halt) halts with "dry" when its
## footprint is not half wet. A Greenhouse below tier III makes half when its tiles or the ring around them are
## blighted (BlightSystem.output_modifier); Greenhouse III ignores blight.
##
## Modifiers: `modifiers` is a list of Callables (settlement, building) -> float. Their product multiplies output
## (and input use). Later tickets append here (tiers, Spirit, health, Dimming); nothing else needs to change.

const SAVE_KEY := "production"

var modifiers: Array[Callable] = []
## Production runs in batches (ticket 57). The producers are dealt into SLICES groups; each tick of a frame-sized
## step works one group, with all the game time that passed since that group last ran (so a tick costs 1/SLICES of
## a full pass, and a group runs every SLICES ticks, about 5 game minutes at 60 fps and 1x). A step of at least
## `batch_seconds` (step_hours) and the end of every hour run all groups, so the on_hour hooks of later systems
## (hauling, growth) see the output. Workers at work are counted once per full cycle. batch_seconds 0 = every
## group every call, like before. The pending times are runtime state; a save in the middle of an hour loses at
## most 5 game minutes of production.
const SLICES := 12
var batch_seconds: float = GameClock.REAL_SECONDS_PER_HOUR / 12.0
var _acc: PackedFloat64Array = PackedFloat64Array()
var _cursor: int = 0
## Single-group ticks since every group last ran. At SLICES the rotation has covered all groups, so the hour end has
## nothing left to flush (ticket 57c: the flush cost about 1.2 ms in the frame that ends an hour).
var _ticks_since_full: int = 0
var _counts: Dictionary = {}
## Units made since the game started (all goods); a statistic for tests and the HUD, not needed to resume a save.
var produced_total: float = 0.0
var _felled_acc: Dictionary = {}  # building id -> units made since the last felled tile
var _forest_cache: Dictionary = {}  # building id -> nearest forest tile, see _forest_of
var _forest_version: int = -1
var _producer_list: Array[Building] = []
var _producers_version: int = -1
var _producers_count: int = -1
var _producers_completion: int = -1
var _first_out: Dictionary = {}  # recipe -> first output good id
## Water Wheel drives (ticket 152): driven building id -> wheel id, rebuilt when the layout moves.
const WHEEL_SPEED_FACTOR := 0.5
var _drive_key: Array = []
var _drive_from: Dictionary = {}


## Per-group collected time, the rotation cursor and the counters (ticket 19). Without the times a save in the
## middle of an hour would drop up to a full cycle of production and break a 3-day identical run.
func save_state() -> Dictionary:
	return {
		"acc": _acc.duplicate(),
		"cursor": _cursor,
		"ticks_since_full": _ticks_since_full,
		"counts": SaveGame.pairs(_counts),
		"produced_total": produced_total,
		"felled_acc": SaveGame.pairs(_felled_acc),
	}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_acc = d["acc"]
	_cursor = int(d["cursor"])
	_ticks_since_full = int(d["ticks_since_full"])
	_counts = SaveGame.unpairs(d["counts"])
	produced_total = float(d["produced_total"])
	_felled_acc = SaveGame.unpairs(d["felled_acc"])
	# Caches: rebuilt from the loaded buildings, the layout and the map.
	_forest_cache.clear()
	_forest_version = -1
	_producer_list.clear()
	_producers_version = -1
	_producers_count = -1
	_producers_completion = -1
	_first_out.clear()
	_drive_key.clear()
	_drive_from.clear()


func on_seconds(s: Settlement, seconds: float) -> void:
	if _acc.size() != SLICES:
		_acc.resize(SLICES)
		_acc.fill(0.0)
	for k in SLICES:
		_acc[k] += seconds
	if seconds + 0.000001 >= batch_seconds:
		_run(s, 0, SLICES)
		return
	_run(s, _cursor, 1)
	_cursor = (_cursor + 1) % SLICES
	_ticks_since_full += 1


func on_hour(s: Settlement) -> void:
	if _acc.size() == SLICES and _ticks_since_full < SLICES:
		_run(s, 0, SLICES)


## Work `n` groups starting at `first` with the time each has collected.
func _run(s: Settlement, first: int, n: int) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null or s.registry.logistics == null:
		return
	var shift := float(WalkerSystem.WORK_END_HOUR - WalkerSystem.WORK_START_HOUR) * GameClock.REAL_SECONDS_PER_HOUR
	if n == SLICES:
		_ticks_since_full = 0
	if n == SLICES or first == 0:
		_counts = ws.work_counts()
	var list := _producers(s)
	for g in n:
		var k := (first + g) % SLICES
		var seconds := _acc[k]
		_acc[k] = 0.0
		if seconds <= 0.0:
			continue
		var part := seconds / shift
		var i := k
		while i < list.size():
			var b: Building = list[i]
			i += SLICES
			if not b.paused:
				_produce(s, b, _counts.get(b.id, 0), part)


## Buildings with a door buffer, in id order. Rebuilt when the set of buildings changes (grid_version moves on
## every placement and demolition).
func _producers(s: Settlement) -> Array[Building]:
	# a finished site gets its door buffer without a grid change or a new building: completion_version moves then
	if _producers_version != s.grid_version or _producers_count != s.buildings.size() or _producers_completion != s.completion_version:
		_producers_version = s.grid_version
		_producers_completion = s.completion_version
		_producers_count = s.buildings.size()
		_producer_list.clear()
		var ids: Array = s.buildings.keys()
		ids.sort()
		for bid in ids:
			var b: Building = s.buildings[bid]
			if b.door_buffer != null:
				_producer_list.append(b)
	return _producer_list


## Upgrade tier output factor (design.md section 10): tier II x1.5, tier III x2 of base, from the tier data.
static func tier_modifier(s: Settlement, b: Building) -> float:
	return b.output_factor(s.registry)


## Lean winters (ticket 159): the lean_winter food producers make PlanetDef.winter_food_factor of their output while
## the season is winter. Derived from the clock, nothing is saved.
static func winter_modifier(s: Settlement, b: Building) -> float:
	if not b.def.lean_winter or s.clock.season_name() != "winter" or s.registry.planet == null:
		return 1.0
	return s.registry.planet.winter_food_factor


## Multiplier of every modifier for one building.
func multiplier(s: Settlement, b: Building) -> float:
	var m := 1.0
	for f in modifiers:
		m *= float(f.call(s, b))
	return m


# ---------------------------------------------------------------- Water Wheel (ticket 152)

## Rebuilds the drive map: each finished, unpaused Water Wheel drives the one 4-adjacent water-driven workshop with
## the lowest id that no lower-id wheel already drives, so the answer is deterministic and no workshop is driven
## twice. Keyed per layout change like the other caches.
func _ensure_drive(s: Settlement) -> void:
	var key := [s.structure_version, s.completion_version, Building.layout_rev, s.buildings.size()]
	if key == _drive_key:
		return
	_drive_key = key
	_drive_from = {}
	var ids: Array = s.buildings.keys()
	ids.sort()
	for wid in ids:
		var w: Building = s.buildings[wid]
		if not w.def.drives_workshop or w.site or w.paused:
			continue
		for bid in ids:
			var b: Building = s.buildings[bid]
			if b.def.water_driven and not b.site and not _drive_from.has(b.id) and footprints_touch(w, b):
				_drive_from[b.id] = w.id
				break


## The Water Wheel driving `b` (ticket 152), or null when `b` is not a water-driven workshop or no wheel touches it.
static func wheel_driving(s: Settlement, b: Building) -> Building:
	if s == null or b == null or not b.def.water_driven:
		return null
	var ps := s.get_system(ProductionSystem) as ProductionSystem
	if ps == null:
		return null
	ps._ensure_drive(s)
	var wid: int = ps._drive_from.get(b.id, -1)
	return s.buildings.get(wid) if wid >= 0 else null


## True when `b` is driven and the wheel's water is clean: one worker fewer per shift and a night shift without a lamp.
static func wheel_active(s: Settlement, b: Building) -> bool:
	var w := wheel_driving(s, b)
	return w != null and not FoulingSystem.wheel_on_foul_water(s, w)


## Day worker slots of `b` after the wheel's saving (never below 1 when the def has any slots).
static func worker_slots_for(s: Settlement, b: Building) -> int:
	var n := b.effective_worker_slots(s.registry)
	return maxi(1, n - 1) if n > 0 and wheel_active(s, b) else n


## Night worker slots of `b` after the wheel's saving (never below 1 when the def has any slots).
static func night_slots_for(s: Settlement, b: Building) -> int:
	var n := b.def.night_worker_slots
	return maxi(1, n - 1) if n > 0 and wheel_active(s, b) else n


## Production modifier: a driven workshop whose wheel stands on fouled water runs at WHEEL_SPEED_FACTOR instead of
## getting the worker saving; clean water and every other building are 1.0.
static func wheel_speed_modifier(s: Settlement, b: Building) -> float:
	var w := wheel_driving(s, b)
	if w != null and FoulingSystem.wheel_on_foul_water(s, w):
		return WHEEL_SPEED_FACTOR
	return 1.0


## True when two footprints share a tile edge (4-adjacent, not diagonal).
static func footprints_touch(a: Building, b: Building) -> bool:
	var ra := a.footprint()
	var rb := b.footprint()
	var rows_overlap := ra.position.y < rb.end.y and rb.position.y < ra.end.y
	var cols_overlap := ra.position.x < rb.end.x and rb.position.x < ra.end.x
	return (rows_overlap and (ra.end.x == rb.position.x or rb.end.x == ra.position.x)) \
			or (cols_overlap and (ra.end.y == rb.position.y or rb.end.y == ra.position.y))


func _produce(s: Settlement, b: Building, workers: int, shift_part: float) -> void:
	if IslandSystem.is_still_building(s, b):
		_set_halt(s, b, "island_still")
		return
	if GloomSystem.building_in_gloom(s, b):
		_set_halt(s, b, "gloom")  # a Dimming night's gloom stops the building until it is lit (ticket 149)
		return
	if b.def.min_planet_health > 0.0 and s.planet_health() < b.def.min_planet_health:
		_set_halt(s, b, "planet_too_sick")
		return
	if b.def.night_only and not s.is_night():
		_set_halt(s, b, "")  # a night-only building makes nothing by day (ticket 134)
		return
	if b.def.night_worker_slots > 0 and s.is_night() and not s.is_lit(b) and not wheel_active(s, b):
		_set_halt(s, b, "unlit")  # a dark night-shift building keeps its night slots closed (spec N2)
		return
	if b.def.min_lit_tiles > 0 and s.is_night():  # moths come to light: enough lit tiles within reach (ticket 144)
		var lighting := s.get_system(LightingSystem) as LightingSystem
		if lighting != null and lighting.lit_tiles_near(s, b, b.def.lit_tile_radius) < b.def.min_lit_tiles:
			_set_halt(s, b, "needs_light")
			return
	var dry := WaterSystem.dry_halt(s, b)
	if dry != "":
		_set_halt(s, b, dry)
		return
	var recipe := b.def.recipe
	if not _first_out.has(recipe):
		_first_out[recipe] = recipe.outputs.keys()[0]
	var first_out: String = _first_out[recipe]
	if b.door_buffer.free_for(first_out) <= Inventory.EPS:
		_set_halt(s, b, "door_full")
		return
	var forest: Vector2i = Vector2i(-1, -1)
	if b.def.fells_forest:
		forest = _forest_of(s, b)
		if forest.x < 0:
			_set_halt(s, b, "no_forest")
			return
	if workers == 0:
		_set_halt(s, b, "")
		return
	if recipe.inputs.has("lumen"):
		var gs := s.get_system(GridSystem) as GridSystem
		if gs != null:
			gs.feed_inputs(s, b)  # an on-grid building takes its Lumen from the grid supply, no hauler trip
	var f := float(workers) * shift_part * multiplier(s, b)  # worker-days of work done this tick
	var flex := flexible_inputs(recipe, b.input_buffer)
	if recipe.any_input_count > 0 and flex.size() < recipe.any_input_count:
		_set_halt(s, b, "no_input")
		return
	for g in recipe.inputs:
		f = minf(f, b.input_buffer.amount_of(g) / float(recipe.inputs[g])) if b.input_buffer != null else 0.0
	for g in flex:
		f = minf(f, b.input_buffer.amount_of(g) / float(recipe.any_input_amount))
	if f <= Inventory.EPS:
		_set_halt(s, b, "no_input" if not recipe.inputs.is_empty() or not flex.is_empty() else "")
		return
	var out_total := 0.0
	for g in recipe.outputs:
		out_total += float(recipe.outputs[g]) * f
	f *= minf(1.0, b.door_buffer.free_for(first_out) / out_total)  # never overfill the buffer
	_set_halt(s, b, "")
	for g in recipe.inputs:
		ResourceLedgerSystem.record_used(s, g, b.input_buffer.remove(g, float(recipe.inputs[g]) * f), "production", b.def.id)
	for g in flex:
		ResourceLedgerSystem.record_used(s, g, b.input_buffer.remove(g, float(recipe.any_input_amount) * f), "production", b.def.id)
	var made := 0.0
	for g in recipe.outputs:
		var put := b.door_buffer.add(g, float(recipe.outputs[g]) * f)
		made += put
		ResourceLedgerSystem.record_made(s, g, put, b.def.id)
	produced_total += made
	if b.def.fells_forest:
		_fell(s, b, made)
	if b.door_buffer.free_for(first_out) <= Inventory.EPS:
		_set_halt(s, b, "door_full")


## Goods a flexible-input recipe takes this batch (Kitchen): the `any_input_count` goods from `any_input_goods`
## with the most in the input buffer, ties in list order. Fewer than `any_input_count` when too few have any.
static func flexible_inputs(recipe: RecipeDef, buffer: Inventory) -> Array[String]:
	var out: Array[String] = []
	if recipe == null or buffer == null or recipe.any_input_count <= 0:
		return out
	var used := {}
	for i in recipe.any_input_count:
		var best := ""
		var best_n := Inventory.EPS
		for g in recipe.any_input_goods:
			if used.has(g):
				continue
			var n := buffer.amount_of(g)
			if n > best_n:
				best = g
				best_n = n
		if best == "":
			break
		used[best] = true
		out.append(best)
	return out


func _fell(s: Settlement, b: Building, made: float) -> void:
	var per := s.registry.logistics.units_per_felled_tile
	var acc: float = _felled_acc.get(b.id, 0.0) + made
	while acc >= per:
		var t := _forest_of(s, b)
		if t.x < 0:
			acc = 0.0
			break
		s.set_terrain(t, "stump")
		acc -= per
	_felled_acc[b.id] = acc


## nearest_forest, remembered per building. The answer only changes when the remembered tile stops being forest or
## a tile becomes forest (Settlement.forest_gain_version), so a felling elsewhere does not force a rescan.
func _forest_of(s: Settlement, b: Building) -> Vector2i:
	if _forest_version != s.forest_gain_version:
		_forest_cache.clear()
		_forest_version = s.forest_gain_version
	if _forest_cache.has(b.id):
		var t: Vector2i = _forest_cache[b.id]
		if t.x < 0 or s.map.terrain_id_at(t.x, t.y) == "forest":
			return t
	var found := nearest_forest(s, b)
	_forest_cache[b.id] = found
	return found


func _set_halt(s: Settlement, b: Building, why: String) -> void:
	if b.halt == why:
		return
	b.halt = why
	s.events.emit("production_halted" if why != "" else "production_resumed", {"id": b.id, "why": why})


## Nearest forest tile within the building's placement radius (same circle as the placement rule), measured from
## the closest footprint tile; ties go to the lower y then lower x. (-1, -1) when there is none.
static func nearest_forest(s: Settlement, b: Building) -> Vector2i:
	var r := b.def.placement_radius
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for ft in b.tiles():
		for y in range(ft.y - r, ft.y + r + 1):
			for x in range(ft.x - r, ft.x + r + 1):
				var d := (x - ft.x) * (x - ft.x) + (y - ft.y) * (y - ft.y)
				if d > r * r or not MapState.in_bounds(x, y) or s.map.terrain_id_at(x, y) != "forest":
					continue
				if d < best_d or (d == best_d and (y < best.y or (y == best.y and x < best.x))):
					best = Vector2i(x, y)
					best_d = d
	return best
