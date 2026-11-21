class_name ConstructionSystem
extends SimSystem
## Builders and construction sites (design.md section 6, D48).
##
## A site (Building.site) first waits for haulers to deliver its whole cost (HaulingSystem treats it as a consumer).
## Only then is it "ready": ready sites are what builders work on. Builders are citizens with Citizen.JOB_BUILD, a slot
## of the Hearth (4) or a Builder's Yard (BuildingDef.builder_slots) that JobSystem fills automatically; slots only
## open while ready sites exist (crew size per site).
##
## In-place upgrades (design.md section 10) are worked the same way: once the tier's cost is delivered, builders work
## Building.upgrade_work while the building keeps running at its old tier; completion calls Settlement.complete_upgrade.
## Both kinds are "works" below; sites sort before upgrades at the same priority (they still take a spot in the world).
##
## During the builder shift (LogisticsDef.builder_shift_start/end, 06-20) builders are spread over ready works in site order, up to
## LogisticsDef.builder_crew per site; site order is priority high, normal, low, then lowest id (paused sites get
## nobody). So the highest-priority site gets builders first. Each builder is a controlled walker sent to the
## site's door. Work counts only while a builder stands at the site door (not walking), pro-rated over time like
## production: a builder at the door for the whole shift does one builder-day. A site needs build_days x crew
## builder-days (Settlement.build_days), so a full crew finishes in build_days and fewer builders take longer.
## A crew walks to its work once and stays there until the work is done (ticket 105): at night it rests at the site
## (standing at the door, no work) and carries on at shift start; it goes back to the yard only when the work is finished,
## paused, demolished or no longer wanted, or the builder loses the job. Needs (food, Spirit) do not depend on where a
## citizen stands in the sim, so staying out overnight costs nothing else.
##
## Clear jobs (ticket 100): a tile the player marked with the Clear tool (Settlement.mark_clear) is a small work of one
## builder. It ranks after the ready sites and upgrades of Normal priority (before Low ones), is worked standing on the
## tile for TerrainDef.clear_hours of work, and then the tile becomes grass and the yield goes to the nearest storage.
## Marks no Builder's Yard can reach (round trip longer than the shift) are flagged in clear_far and get nobody.

const SAVE_KEY := "construction"
## Ledger def id prefix for a Clear-tool yield (ticket 114): "clear_forest", "clear_rock".
const CLEAR_PREFIX := "clear_"

var crews: Dictionary = {}  # citizen id -> work id: a site's building id, or a clear job's clear_work_id
## Marked tile index (MapState.idx) -> builder work hours done on it.
var clear_marks: Dictionary = {}
## Marked tile index -> true while no builders' yard is close enough (set hourly, like the "too_far" halt of a site).
var clear_far: Dictionary = {}
## Bumped whenever clear_marks or clear_far change (ticket 157): with Settlement.grid_version it keys the clear job cache.
var clear_rev: int = 0
var _clear_key := Vector2i(-1, -1)
var _clear_list: Array[int] = []  # the clear job tile indexes, sorted
var _clear_entries: Array = []  # _work_list entries, parallel to _clear_list
var _clear_by_wid: Dictionary = {}  # work id -> entry
var _building_by_id: Dictionary = {}  # work id -> entry of the building works in the last _work_list
var _far_pending: Array = []  # tiles flagged far during a step: their events fire once the step is done
const FAR_CHECK_TRIPS := 3  # most A* trips one hourly far check may ask for (a trip already cached counts too)
const CHECK_MARKS_PER_HOUR := 100  # most marks the hourly check looks at (the rest follow in the next hours)
const CLEAR_SHORTLIST := 4  # a builder runs A* on this many of the nearest marks (straight line), never on every mark


## Which builder was sent to which site. The builders' walkers are saved by WalkerSystem; this pairs them up so a
## loaded builder keeps walking to the same site instead of being sent again.
func save_state() -> Dictionary:
	return {"crews": SaveGame.pairs(crews), "clear": SaveGame.pairs(clear_marks), "far": SaveGame.pairs(clear_far)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	crews = SaveGame.unpairs(d["crews"])
	clear_marks = SaveGame.unpairs(d.get("clear", []))  # a save from before the Clear tool has no marks
	clear_far = SaveGame.unpairs(d.get("far", []))
	clear_rev += 1


## Work id of the clear job on tile index `idx` (building ids are >= 0, -1 means none).
static func clear_work_id(idx: int) -> int:
	return -2 - idx


## Tile indexes of the clear jobs builders may take now: marked, still clearable, nothing built on it, in reach. In
## index order. Cached (ticket 157): the same array until marks, terrain, roads or buildings change, so do not edit it.
static func clear_job_indices(s: Settlement) -> Array[int]:
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	if cs == null:
		var none: Array[int] = []
		return none
	return cs._clear_jobs(s)


func _key_of(s: Settlement) -> Vector2i:
	return Vector2i(clear_rev, s.grid_version)


func _clear_jobs(s: Settlement) -> Array[int]:
	if _clear_key != _key_of(s):
		_clear_list.clear()
		_clear_entries.clear()
		_clear_by_wid.clear()
		var idxs: Array[int] = []
		for idx: int in clear_marks:
			if not clear_far.has(idx) and clear_valid(s, idx):
				idxs.append(idx)
		idxs.sort()
		for idx in idxs:
			_clear_list.append(idx)
			var e := _clear_entry(idx)
			_clear_entries.append(e)
			_clear_by_wid[e["id"]] = e
		_clear_key = _key_of(s)
	return _clear_list


static func _clear_entry(idx: int) -> Dictionary:
	return {"id": clear_work_id(idx), "b": null, "tile": Vector2i(idx % MapState.WIDTH, idx / MapState.WIDTH), "tier": "clear"}


## The cache stays valid across one mark added or removed (a drag of 2,000 marks must not rebuild it 2,000 times):
## call after the change to clear_marks / clear_far.
func note_mark_added(s: Settlement, idx: int) -> void:
	var fresh := _clear_key == Vector2i(clear_rev, s.grid_version)
	clear_rev += 1
	if fresh:
		if not clear_far.has(idx) and clear_valid(s, idx):
			var pos := _clear_list.bsearch(idx)
			var e := _clear_entry(idx)
			_clear_list.insert(pos, idx)
			_clear_entries.insert(pos, e)
			_clear_by_wid[e["id"]] = e
		_clear_key = _key_of(s)


func note_mark_removed(s: Settlement, idx: int) -> void:
	var fresh := _clear_key == Vector2i(clear_rev, s.grid_version)
	clear_rev += 1
	if fresh:
		_drop_clear(idx)
		_clear_key = _key_of(s)


func _drop_clear(idx: int) -> void:
	var pos := _clear_list.bsearch(idx)
	if pos < _clear_list.size() and _clear_list[pos] == idx:
		_clear_list.remove_at(pos)
		_clear_entries.remove_at(pos)
		_clear_by_wid.erase(clear_work_id(idx))


## True when tile index `idx` can still be cleared: its terrain has clear hours and nothing stands or runs over it.
func clear_valid(s: Settlement, idx: int) -> bool:
	var x := idx % MapState.WIDTH
	var y := idx / MapState.WIDTH
	var def := s.registry.get_terrain(s.map.terrain_id_at(x, y))
	return def != null and def.clear_hours > 0.0 and s.occupancy[idx] < 0 and s.roads[idx] == Settlement.ROAD_NONE \
			and s.channels[idx] == Settlement.CHANNEL_NONE and s.track[idx] == 0


## True when a building is a work item: a construction site or an in-place upgrade whose whole cost has arrived.
static func is_ready(b: Building) -> bool:
	if b.paused:
		return false
	if b.site:
		return b.site_delivered()
	return b.upgrading() and b.upgrade_delivered()


## Sites and upgrades with the whole cost delivered and not paused, best first (priority, then id; a site before an
## upgrade of the same priority).
static func ready_works(s: Settlement) -> Array[Building]:
	var out: Array[Building] = []
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if is_ready(b):
			out.append(b)
	if out.is_empty():
		return out
	out.sort_custom(func(a: Building, b: Building) -> bool:
		var pa := JobSystem.PRIORITY_ORDER.find(a.priority)
		var pb := JobSystem.PRIORITY_ORDER.find(b.priority)
		if pa != pb:
			return pa < pb
		if a.site != b.site:
			return a.site
		return a.id < b.id)
	return out


static func builders_wanted(s: Settlement) -> int:
	if s.registry.logistics == null:
		return 0
	var n := 0
	for id in s.buildings:  # same test as is_ready, inlined: this runs on every population refresh
		var b: Building = s.buildings[id]
		if not b.site and b.upgrade_tier <= 0:
			continue
		if is_ready(b):
			n += 1
	return n * s.registry.logistics.builder_crew + clear_job_indices(s).size()


func on_seconds(s: Settlement, seconds: float) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null or s.registry.logistics == null:
		return
	var lg := s.registry.logistics
	var h := s.clock.hour()
	var in_shift := h >= lg.builder_shift_start and h < lg.builder_shift_end
	var builders: Array = []
	for cid in s.citizen_ids_of_kind(Citizen.JOB_BUILD):
		if s.citizens.has(cid) and (s.citizens[cid] as Citizen).job_kind == Citizen.JOB_BUILD:
			builders.append(cid)
	if builders.is_empty() and crews.is_empty():
		return  # nobody builds and nobody is on a crew: nothing below would do anything
	var wanted := {}  # citizen id -> work entry (see _work_list)
	if in_shift:
		wanted = _assign_crews(s, builders, _work_list(s))
	elif not crews.is_empty():
		wanted = _keep_crews(builders, _work_list(s))  # at night: whoever is on a crew rests at the site, nobody new goes
	for cid in crews.keys():
		if not wanted.has(cid) or wanted[cid]["id"] != crews[cid]:
			_release(s, ws, cid, in_shift)
	var shift := builder_shift_seconds(lg)
	var work := {}  # work id -> work done this tick: builder-days on a building, builder hours on a clear job
	for cid in wanted:
		var e: Dictionary = wanted[cid]
		var w := ws.walker_of(cid)
		if w == null:
			continue
		var is_clear: bool = e["b"] == null
		var here: bool = w.path.is_empty() and (w.tile == e["tile"] if is_clear else w.at_building == e["id"])
		if not crews.has(cid) or not w.controlled or (not here and w.path.is_empty()):
			crews[cid] = e["id"]
			w.controlled = true
			if not here:
				if is_clear:
					ws.walk_to_tile(cid, e["tile"])
				else:
					ws.walk_to_building(cid, e["id"])
		elif here and in_shift:
			var done_now := seconds / GameClock.REAL_SECONDS_PER_HOUR if is_clear else seconds / shift
			work[e["id"]] = work.get(e["id"], 0.0) + done_now * SpiritSystem.work_multiplier(s)
	var done: Array[Building] = []
	var cleared: Array[int] = []
	for wid: int in work:
		if wid < -1:
			var idx := -2 - wid
			if not clear_marks.has(idx):
				continue
			clear_marks[idx] = float(clear_marks[idx]) + work[wid]
			var def := s.registry.get_terrain(s.map.terrain_id_at(idx % MapState.WIDTH, idx / MapState.WIDTH))
			if def != null and float(clear_marks[idx]) >= def.clear_hours - Inventory.EPS:
				cleared.append(idx)
			continue
		var b: Building = s.buildings[wid]
		if b.upgrading():
			b.upgrade_work += work[wid]
			if b.upgrade_work >= b.upgrade_work_needed - Inventory.EPS:
				done.append(b)
		else:
			b.build_work += work[wid]
			if b.build_work >= b.build_work_needed - Inventory.EPS:
				done.append(b)
	var freed: Array = []  # builders whose work just ended: they go straight to the next waiting work (below)
	for b in done:
		for cid in crews.keys():
			if crews[cid] == b.id:
				crews.erase(cid)
				freed.append(cid)
		if b.upgrading():
			b.upgrade_work = b.upgrade_work_needed
			s.complete_upgrade(b)
		else:
			b.build_work = b.build_work_needed
			s.complete_site(b)
	for idx in cleared:
		for cid in crews.keys():
			if crews[cid] == clear_work_id(idx):
				crews.erase(cid)
				freed.append(cid)
		_finish_clear(s, idx)
	_hand_on(s, ws, freed, builders, in_shift)
	# a builder left controlled with no crew (nothing for them to do) goes back to the yard
	for cid in builders:
		var bw := ws.walker_of(cid)
		if bw != null and bw.controlled and not crews.has(cid) and not wanted.has(cid):
			_release(s, ws, cid, in_shift)
	_flush_far(s)


## Events for the marks flagged far during this step (kept to the end so no job slot moves in the middle of it).
func _flush_far(s: Settlement) -> void:
	if _far_pending.is_empty():
		return
	var pending := _far_pending
	_far_pending = []
	for tile: Vector2i in pending:
		s.events.emit("clear_marks_changed", {"tile": tile, "marked": true, "cleared": false})
	s.refresh_population()


## Real seconds of one builder-day (the builder shift).
static func builder_shift_seconds(lg: LogisticsDef) -> float:
	return float(lg.builder_shift_end - lg.builder_shift_start) * GameClock.REAL_SECONDS_PER_HOUR


## Builders whose work just finished walk straight to the next waiting work (same pick as _assign_crews: priority tier,
## then the nearest to the yard, far sites already filtered by the hourly too_far halt); when nothing waits, or the
## shift is over, they go back to the yard as before (ticket 118).
func _hand_on(s: Settlement, ws: WalkerSystem, freed: Array, builders: Array, in_shift: bool) -> void:
	if freed.is_empty():
		return
	var next := {}
	if in_shift:
		next = _assign_crews(s, builders, _work_list(s))
	for cid in freed:
		if not s.citizens.has(cid):
			continue
		var e: Dictionary = next.get(cid, {})
		var w := ws.walker_of(cid)
		if e.is_empty() or w == null:
			_release(s, ws, cid, in_shift)
			continue
		crews[cid] = e["id"]
		w.controlled = true
		if e["b"] == null:
			ws.walk_to_tile(cid, e["tile"])
		else:
			ws.walk_to_building(cid, e["id"])


## Night: builders on a crew whose work is still on the list keep it (citizen id -> entry); the rest get nothing.
func _keep_crews(builders: Array, _works: Array) -> Dictionary:
	var out := {}
	for cid in builders:
		if crews.has(cid):
			var e := _entry_by_id(crews[cid])
			if not e.is_empty():
				out[cid] = e
	return out


## The tile is cleared: it becomes grass, the mark goes and the yield (TerrainDef.clear_good) goes to the nearest storage.
func _finish_clear(s: Settlement, idx: int) -> void:
	var tile := Vector2i(idx % MapState.WIDTH, idx / MapState.WIDTH)
	var def := s.registry.get_terrain(s.map.terrain_id_at(tile.x, tile.y))
	var fresh := _clear_key == _key_of(s)
	var version := s.grid_version
	clear_marks.erase(idx)
	clear_far.erase(idx)
	clear_rev += 1
	s.set_terrain(tile, "grass")
	if fresh and s.grid_version == version + 1:  # only this tile changed: the cache just loses it
		_drop_clear(idx)
		_clear_key = _key_of(s)
	if def != null and def.clear_good != "" and def.clear_amount > 0.0:
		s.store_goods({def.clear_good: def.clear_amount}, tile)
		ResourceLedgerSystem.record_made(s, def.clear_good, def.clear_amount, CLEAR_PREFIX + def.id)
	s.events.emit("clear_marks_changed", {"tile": tile, "marked": false, "cleared": true})
	s.refresh_population()  # one builder less is wanted


## Everything builders can work now, best first, as entries {id, b (the building, null for a clear job), tile (a clear
## job's tile), tier}: ready_works order, with the clear jobs after the Normal priority works and before Low ones.
func _work_list(s: Settlement) -> Array:
	_clear_jobs(s)
	_building_by_id.clear()
	var clears := _clear_entries
	var out: Array = []
	var normal := JobSystem.PRIORITY_ORDER.find("normal")
	var placed := clears.is_empty()
	for b in ready_works(s):
		if not placed and JobSystem.PRIORITY_ORDER.find(b.priority) > normal:
			out.append_array(clears)
			placed = true
		var e := {"id": b.id, "b": b, "tile": Vector2i.ZERO, "tier": "%s%s" % [b.priority, b.site]}
		_building_by_id[b.id] = e
		out.append(e)
	if not placed:
		out.append_array(clears)
	return out


## The entry of work id `wid` in the last _work_list: a building's, or a clear job's from the clear job cache (the
## entries in the list are the cache's own, so this needs no dictionary of every mark per step).
func _entry_by_id(wid: int) -> Dictionary:
	return _clear_by_wid.get(wid, {}) if wid < -1 else _building_by_id.get(wid, {})


## Builder -> work. Builders already on a crew keep their work while it is still wanted and not full (no flip-flopping
## between works); the others take, within the best tier that still has room, the nearest work (walking time from the
## builder's yard, ties to the lower id). A building takes builder_crew builders, a clear job one. `works` is in
## _work_list order. Returns citizen id -> entry.
func _assign_crews(s: Settlement, builders: Array, works: Array) -> Dictionary:
	var out := {}
	if works.is_empty():
		return out
	var cap := s.registry.logistics.builder_crew
	var count := {}  # work id -> builders on it
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var rest: Array = []
	for cid in builders:
		var e: Dictionary = _entry_by_id(crews.get(cid, -1))
		if not e.is_empty() and int(count.get(e["id"], 0)) < (cap if e["b"] != null else 1):
			out[cid] = e
			count[e["id"]] = int(count.get(e["id"], 0)) + 1
		else:
			rest.append(cid)
	for cid in rest:
		var c: Citizen = s.citizens[cid]
		var yard: Building = s.buildings.get(c.job_id)
		var best: Dictionary = {}
		var best_d := 0.0
		var tier := ""
		var near: Array = []  # [straight-line distance, entry] of the nearest clear jobs, best first
		var from := ws.door_tile(yard) if ws != null and yard != null else Vector2i.ZERO
		var k := 0
		while k < works.size():
			var e: Dictionary = works[k]
			k += 1
			if e["b"] == null:  # the clear jobs are one block of the list (the cache's own, sorted by tile index)
				if (not best.is_empty() or not near.is_empty()) and tier != "clear":
					break
				tier = "clear"
				_nearest_clear_jobs(near, count, from)
				k += _clear_entries.size() - 1
				continue
			if int(count.get(e["id"], 0)) >= cap:
				continue
			var t: String = e["tier"]
			if (not best.is_empty() or not near.is_empty()) and t != tier:
				break  # the best tier with room is settled (works are sorted by tier)
			tier = t
			var d := _trip_cached(s, ws, yard, e["id"], e["b"], e["tile"])
			if best.is_empty() or d < best_d:
				best = e
				best_d = d
		for pair: Array in near:  # A* only on the shortlist
			var e: Dictionary = pair[1]
			var d := _clear_trip(s, ws, yard, from, e["tile"])
			if 2.0 * d > builder_shift_seconds(s.registry.logistics) and _clear_unreachable(s, ws, e["tile"]):
				continue  # no yard reaches it: flagged far, a later pass skips it
			if best.is_empty() or d < best_d:
				best = e
				best_d = d
		if not best.is_empty():
			out[cid] = best
			count[best["id"]] = int(count.get(best["id"], 0)) + 1
	return out


## Fills `near` with the CLEAR_SHORTLIST clear jobs with room nearest to `from` by straight line. The cached list is
## in tile index order, row by row, so the search walks away from the row of `from` and stops once a row is farther
## than the shortlist's worst: a few rows of a big mark set, never all of it.
func _nearest_clear_jobs(near: Array, count: Dictionary, from: Vector2i) -> void:
	var n := _clear_list.size()
	var start := _clear_list.bsearch(from.y * MapState.WIDTH + from.x)
	for dir in [1, -1]:
		var k: int = start if dir == 1 else start - 1
		while k >= 0 and k < n:
			var idx := _clear_list[k]
			var dy := absi(idx / MapState.WIDTH - from.y)
			if near.size() >= CLEAR_SHORTLIST and dy > int(near.back()[0]):
				break
			k += dir
			var e: Dictionary = _clear_entries[k - dir]
			if int(count.get(e["id"], 0)) < 1:
				_shortlist(near, e, dy + absi(idx % MapState.WIDTH - from.x))


## Keeps the CLEAR_SHORTLIST nearest (by straight line, then lower tile index) in `near`, best first.
func _shortlist(near: Array, e: Dictionary, dist: int) -> void:
	var i := near.size()
	while i > 0 and (dist < int(near[i - 1][0]) or (dist == int(near[i - 1][0]) and int(e["id"]) > int(near[i - 1][1]["id"]))):
		i -= 1
	if i < CLEAR_SHORTLIST:
		near.insert(i, [dist, e])
		if near.size() > CLEAR_SHORTLIST:
			near.pop_back()


## True (and the mark flagged far for the whole settlement) when no builders' yard reaches the tile within a shift.
func _clear_unreachable(s: Settlement, ws: WalkerSystem, tile: Vector2i) -> bool:
	var idx := MapState.idx(tile.x, tile.y)
	var shift := builder_shift_seconds(s.registry.logistics)
	for y in _yards(s):
		if 2.0 * _clear_trip(s, ws, y, ws.door_tile(y), tile) <= shift:
			return false
	clear_far[idx] = true
	clear_rev += 1
	var fresh := _clear_key == Vector2i(clear_rev - 1, s.grid_version)
	_far_pending.append(tile)
	if fresh:
		_drop_clear(idx)
		_clear_key = _key_of(s)
	return true


## _trip_cached to a clear job's tile, except that a tile too far in a straight line is not searched for: the
## straight-line time is returned (it already is more than a shift, and so is the real trip).
func _clear_trip(s: Settlement, ws: WalkerSystem, yard: Building, door: Vector2i, tile: Vector2i) -> float:
	if ws == null or yard == null:
		return 0.0
	var bound := ws.min_walk_seconds(door, tile)
	if 2.0 * bound > builder_shift_seconds(s.registry.logistics):
		return bound
	return _trip_cached(s, ws, yard, clear_work_id(MapState.idx(tile.x, tile.y)), null, tile)


func _yards(s: Settlement) -> Array[Building]:
	var yards: Array[Building] = []
	for id in s.buildings:
		var y: Building = s.buildings[id]
		if not y.site and y.def.builder_slots > 0:
			yards.append(y)
	return yards


var _trip_cache: Dictionary = {}  # yard id * 1000003 + work id -> seconds, dropped when the road layout changes
var _trip_version: int = -1


## Walking seconds from a builders' yard door to a work's door (INF without a path). Cached per road layout.
func _trip_seconds(s: Settlement, ws: WalkerSystem, yard: Building, work: Building) -> float:
	return _trip_cached(s, ws, yard, work.id, work, Vector2i.ZERO)


## _trip_seconds for a work id that is a building (`work` set, its door) or a clear job (`work` null, `tile`).
func _trip_cached(s: Settlement, ws: WalkerSystem, yard: Building, work_id: int, work: Building, tile: Vector2i) -> float:
	if ws == null or yard == null:
		return 0.0
	if _trip_version != s.grid_version:
		_trip_cache.clear()
		_trip_version = s.grid_version
	var key := yard.id * 1000003 + work_id
	if not _trip_cache.has(key):
		var p := ws.find_path(ws.door_tile(yard), ws.door_tile(work) if work != null else tile)
		_trip_cache[key] = ws.path_seconds(p) if not p.is_empty() else INF
	return _trip_cache[key]


## Sites no builders' yard (the Hearth counts) is close enough to: builders sleep at their yard and walk to the site
## every shift, so a round trip longer than the work day leaves no time to build. Such a site shows the "too_far" halt
## until a yard is built closer. Walking time of the real path (cached per road layout); no path counts as too far.
func on_hour(s: Settlement) -> void:
	if s.registry.logistics == null or s.hearth == null:
		return
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null:
		return
	var shift := builder_shift_seconds(s.registry.logistics)
	var yards: Array[Building] = []
	for id in s.buildings:
		var y: Building = s.buildings[id]
		if not y.site and y.def.builder_slots > 0:
			yards.append(y)
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if not b.site:
			if b.halt == "too_far":
				_set_halt(s, b, "")
			continue
		var far := true
		for y in yards:
			if 2.0 * _trip_seconds(s, ws, y, b) <= shift:  # INF (no path) never fits
				far = false
				break
		if far and b.halt == "":
			_set_halt(s, b, "too_far")
		elif not far and b.halt == "too_far":
			_set_halt(s, b, "")
	_check_clear_marks(s, ws, yards, shift)


## Hourly: drop marks that can no longer be cleared (a building went up, the stump grew back to grass) and flag the
## ones no yard reaches, like a site's "too_far" halt.
func _check_clear_marks(s: Settlement, ws: WalkerSystem, yards: Array[Building], shift: float) -> void:
	if clear_marks.is_empty():
		return
	# A big mark set is checked a window at a time (ticket 157): CHECK_MARKS_PER_HOUR marks per hour, the window moving
	# on with the clock, and at most FAR_CHECK_TRIPS marks that need a path (not already ruled out by their straight-
	# line distance); the others keep their flag until the window comes round again. Builders also test the nearest
	# marks for themselves before they walk out (_clear_unreachable), and the job list skips marks that cannot be cleared.
	var idxs: Array = clear_marks.keys()
	idxs.sort()
	var doors: Array[Vector2i] = []
	for y in yards:
		doors.append(ws.door_tile(y))
	var n := idxs.size()
	var first := (s.clock.total_hours * CHECK_MARKS_PER_HOUR) % n
	var asks := 0
	var flipped: Array[Vector2i] = []  # all flips of one check are announced together: each would rebuild the job list
	for w in mini(n, CHECK_MARKS_PER_HOUR):
		var idx: int = idxs[(first + w) % n]
		var tile := Vector2i(idx % MapState.WIDTH, idx / MapState.WIDTH)
		if not clear_valid(s, idx):  # a building went up, the stump grew back to grass
			clear_marks.erase(idx)
			clear_far.erase(idx)
			note_mark_removed(s, idx)
			s.events.emit("clear_marks_changed", {"tile": tile, "marked": false, "cleared": false})
			s.refresh_population()
			continue
		var far := true
		var undecided := false
		for k in yards.size():
			if 2.0 * ws.min_walk_seconds(doors[k], tile) > shift:
				continue  # too far in a straight line: no path search needed
			if asks >= FAR_CHECK_TRIPS:
				undecided = true
				continue
			asks += 1
			if 2.0 * _trip_cached(s, ws, yards[k], clear_work_id(idx), null, tile) <= shift:
				far = false
				break
		if undecided and far:
			continue
		if far != clear_far.has(idx):
			if far:
				clear_far[idx] = true
			else:
				clear_far.erase(idx)
			flipped.append(tile)
	if flipped.is_empty():
		return
	clear_rev += 1
	for tile in flipped:
		s.events.emit("clear_marks_changed", {"tile": tile, "marked": true, "cleared": false})
	s.refresh_population()


func _set_halt(s: Settlement, b: Building, why: String) -> void:
	b.halt = why
	s.events.emit("production_halted" if why != "" else "production_resumed", {"id": b.id, "why": why})


## Hand the builder back to the schedule (walk home, or to the Hearth when homeless).
func _release(s: Settlement, ws: WalkerSystem, cid: int, _in_shift: bool) -> void:
	crews.erase(cid)
	var w := ws.walker_of(cid)
	var c: Citizen = s.citizens.get(cid)
	if w == null or c == null:
		return
	w.controlled = false
	var target := c.home_id if s.buildings.has(c.home_id) else (s.hearth.id if s.hearth != null else -1)
	if c.job_id >= 0 and s.buildings.has(c.job_id) and c.job_kind == Citizen.JOB_BUILD:
		target = c.job_id  # back to the builders' yard (WalkerSystem keeps them there overnight)
	if target >= 0:
		ws.walk_to_building(cid, target)
