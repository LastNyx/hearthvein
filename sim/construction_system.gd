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
## During the work shift (WalkerSystem 06-18) builders are spread over ready works in site order, up to
## LogisticsDef.builder_crew per site; site order is priority high, normal, low, then lowest id (paused sites get
## nobody). So the highest-priority site gets builders first. Each builder is a controlled walker sent to the
## site's door. Work counts only while a builder stands at the site door (not walking), pro-rated over time like
## production: a builder at the door for the whole shift does one builder-day. A site needs build_days x crew
## builder-days (Settlement.build_days), so a full crew finishes in build_days and fewer builders take longer.
## Outside the shift builders are released to the normal schedule.
##
## Clear jobs (ticket 100): a tile the player marked with the Clear tool (Settlement.mark_clear) is a small work of one
## builder. It ranks after the ready sites and upgrades of Normal priority (before Low ones), is worked standing on the
## tile for TerrainDef.clear_hours of work, and then the tile becomes grass and the yield goes to the nearest storage.
## Marks no Builder's Yard can reach (round trip longer than the shift) are flagged in clear_far and get nobody.

const SAVE_KEY := "construction"

var crews: Dictionary = {}  # citizen id -> work id: a site's building id, or a clear job's clear_work_id
## Marked tile index (MapState.idx) -> builder work hours done on it.
var clear_marks: Dictionary = {}
## Marked tile index -> true while no builders' yard is close enough (set hourly, like the "too_far" halt of a site).
var clear_far: Dictionary = {}


## Which builder was sent to which site. The builders' walkers are saved by WalkerSystem; this pairs them up so a
## loaded builder keeps walking to the same site instead of being sent again.
func save_state() -> Dictionary:
	return {"crews": SaveGame.pairs(crews), "clear": SaveGame.pairs(clear_marks), "far": SaveGame.pairs(clear_far)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	crews = SaveGame.unpairs(d["crews"])
	clear_marks = SaveGame.unpairs(d.get("clear", []))  # a save from before the Clear tool has no marks
	clear_far = SaveGame.unpairs(d.get("far", []))


## Work id of the clear job on tile index `idx` (building ids are >= 0, -1 means none).
static func clear_work_id(idx: int) -> int:
	return -2 - idx


## Tile indexes of the clear jobs builders may take now: marked, still clearable, nothing built on it, in reach. In
## index order.
static func clear_job_indices(s: Settlement) -> Array[int]:
	var out: Array[int] = []
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	if cs == null or cs.clear_marks.is_empty():
		return out
	for idx: int in cs.clear_marks:
		if not cs.clear_far.has(idx) and cs.clear_valid(s, idx):
			out.append(idx)
	out.sort()
	return out


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
	var h := s.clock.hour()
	var in_shift := h >= WalkerSystem.WORK_START_HOUR and h < WalkerSystem.WORK_END_HOUR
	var builders: Array = []
	for cid in s.citizen_ids_of_kind(Citizen.JOB_BUILD):
		if s.citizens.has(cid) and (s.citizens[cid] as Citizen).job_kind == Citizen.JOB_BUILD:
			builders.append(cid)
	if builders.is_empty() and crews.is_empty():
		return  # nobody builds and nobody is on a crew: nothing below would do anything
	var wanted := {}  # citizen id -> work entry (see _work_list)
	if in_shift:
		wanted = _assign_crews(s, builders, _work_list(s))
	for cid in crews.keys():
		if not wanted.has(cid) or wanted[cid]["id"] != crews[cid]:
			_release(s, ws, cid, in_shift)
	var shift := float(WalkerSystem.WORK_END_HOUR - WalkerSystem.WORK_START_HOUR) * GameClock.REAL_SECONDS_PER_HOUR
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
		elif here:
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
	for b in done:
		for cid in crews.keys():
			if crews[cid] == b.id:
				_release(s, ws, cid, in_shift)
		if b.upgrading():
			b.upgrade_work = b.upgrade_work_needed
			s.complete_upgrade(b)
		else:
			b.build_work = b.build_work_needed
			s.complete_site(b)
	for idx in cleared:
		for cid in crews.keys():
			if crews[cid] == clear_work_id(idx):
				_release(s, ws, cid, in_shift)
		_finish_clear(s, idx)


## The tile is cleared: it becomes grass, the mark goes and the yield (TerrainDef.clear_good) goes to the nearest storage.
func _finish_clear(s: Settlement, idx: int) -> void:
	var tile := Vector2i(idx % MapState.WIDTH, idx / MapState.WIDTH)
	var def := s.registry.get_terrain(s.map.terrain_id_at(tile.x, tile.y))
	clear_marks.erase(idx)
	clear_far.erase(idx)
	s.set_terrain(tile, "grass")
	if def != null and def.clear_good != "" and def.clear_amount > 0.0:
		s.store_goods({def.clear_good: def.clear_amount}, tile)
	s.events.emit("clear_marks_changed", {"tile": tile, "marked": false, "cleared": true})
	s.refresh_population()  # one builder less is wanted


## Everything builders can work now, best first, as entries {id, b (the building, null for a clear job), tile (a clear
## job's tile), tier}: ready_works order, with the clear jobs after the Normal priority works and before Low ones.
func _work_list(s: Settlement) -> Array:
	var clears: Array = []
	for idx in clear_job_indices(s):
		clears.append({"id": clear_work_id(idx), "b": null, "tile": Vector2i(idx % MapState.WIDTH, idx / MapState.WIDTH),
				"tier": "clear"})
	var out: Array = []
	var normal := JobSystem.PRIORITY_ORDER.find("normal")
	var placed := clears.is_empty()
	for b in ready_works(s):
		if not placed and JobSystem.PRIORITY_ORDER.find(b.priority) > normal:
			out.append_array(clears)
			placed = true
		out.append({"id": b.id, "b": b, "tile": Vector2i.ZERO, "tier": "%s%s" % [b.priority, b.site]})
	if not placed:
		out.append_array(clears)
	return out


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
	var by_id := {}
	for e: Dictionary in works:
		by_id[e["id"]] = e
	var rest: Array = []
	for cid in builders:
		var e: Dictionary = by_id.get(crews.get(cid, -1), {})
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
		for e: Dictionary in works:
			if int(count.get(e["id"], 0)) >= (cap if e["b"] != null else 1):
				continue
			var t: String = e["tier"]
			if not best.is_empty() and t != tier:
				break  # the best tier with room is settled (works are sorted by tier)
			tier = t
			var d := _trip_cached(s, ws, yard, e["id"], e["b"], e["tile"])
			if best.is_empty() or d < best_d:
				best = e
				best_d = d
		if not best.is_empty():
			out[cid] = best
			count[best["id"]] = int(count.get(best["id"], 0)) + 1
	return out


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
	var shift := float(WalkerSystem.WORK_END_HOUR - WalkerSystem.WORK_START_HOUR) * GameClock.REAL_SECONDS_PER_HOUR
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
	for idx: int in clear_marks.keys():
		var tile := Vector2i(idx % MapState.WIDTH, idx / MapState.WIDTH)
		if not clear_valid(s, idx):
			clear_marks.erase(idx)
			clear_far.erase(idx)
			s.events.emit("clear_marks_changed", {"tile": tile, "marked": false, "cleared": false})
			s.refresh_population()
			continue
		var far := true
		for y in yards:
			if 2.0 * _trip_cached(s, ws, y, clear_work_id(idx), null, tile) <= shift:
				far = false
				break
		if far != clear_far.has(idx):
			if far:
				clear_far[idx] = true
			else:
				clear_far.erase(idx)
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
