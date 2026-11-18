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

const SAVE_KEY := "construction"

var crews: Dictionary = {}  # citizen id -> site building id the builder was sent to


## Which builder was sent to which site. The builders' walkers are saved by WalkerSystem; this pairs them up so a
## loaded builder keeps walking to the same site instead of being sent again.
func save_state() -> Dictionary:
	return {"crews": SaveGame.pairs(crews)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	crews = SaveGame.unpairs(d["crews"])


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
	return n * s.registry.logistics.builder_crew


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
	var wanted := {}  # citizen id -> site
	if in_shift:
		wanted = _assign_crews(s, builders, ready_works(s))
	for cid in crews.keys():
		if not wanted.has(cid) or wanted[cid].id != crews[cid]:
			_release(s, ws, cid, in_shift)
	var shift := float(WalkerSystem.WORK_END_HOUR - WalkerSystem.WORK_START_HOUR) * GameClock.REAL_SECONDS_PER_HOUR
	var work := {}  # site id -> builder-days done this tick
	for cid in wanted:
		var site: Building = wanted[cid]
		var w := ws.walker_of(cid)
		if w == null:
			continue
		var here := w.path.is_empty() and w.at_building == site.id
		if not crews.has(cid) or not w.controlled or (not here and w.path.is_empty()):
			crews[cid] = site.id
			w.controlled = true
			if not here:
				ws.walk_to_building(cid, site.id)
		elif here:
			work[site.id] = work.get(site.id, 0.0) + seconds / shift * SpiritSystem.work_multiplier(s)
	var done: Array[Building] = []
	for sid in work:
		var b: Building = s.buildings[sid]
		if b.upgrading():
			b.upgrade_work += work[sid]
			if b.upgrade_work >= b.upgrade_work_needed - Inventory.EPS:
				done.append(b)
		else:
			b.build_work += work[sid]
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


## Builder -> work. Builders already on a crew keep their site while it is still ready and not full (no flip-flopping
## between sites); the others take, within the best priority tier that still has room, the nearest work (walking time
## from the builder's yard, ties to the lower id). `works` is in ready_works order.
func _assign_crews(s: Settlement, builders: Array, works: Array[Building]) -> Dictionary:
	var out := {}
	if works.is_empty():
		return out
	var cap := s.registry.logistics.builder_crew
	var count := {}  # work id -> builders on it
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var by_id := {}
	for b in works:
		by_id[b.id] = b
	var rest: Array = []
	for cid in builders:
		var b: Building = by_id.get(crews.get(cid, -1))
		if b != null and int(count.get(b.id, 0)) < cap:
			out[cid] = b
			count[b.id] = int(count.get(b.id, 0)) + 1
		else:
			rest.append(cid)
	for cid in rest:
		var c: Citizen = s.citizens[cid]
		var yard: Building = s.buildings.get(c.job_id)
		var best: Building = null
		var best_d := 0.0
		var tier := ""
		for b in works:
			if int(count.get(b.id, 0)) >= cap:
				continue
			var t := "%s%s" % [b.priority, b.site]
			if best != null and t != tier:
				break  # the best tier with room is settled (works are sorted by tier)
			tier = t
			var d := _trip_seconds(s, ws, yard, b)
			if best == null or d < best_d:
				best = b
				best_d = d
		if best != null:
			out[cid] = best
			count[best.id] = int(count.get(best.id, 0)) + 1
	return out


var _trip_cache: Dictionary = {}  # yard id * 1000003 + work id -> seconds, dropped when the road layout changes
var _trip_version: int = -1


## Walking seconds from a builders' yard door to a work's door (INF without a path). Cached per road layout.
func _trip_seconds(s: Settlement, ws: WalkerSystem, yard: Building, work: Building) -> float:
	if ws == null or yard == null:
		return 0.0
	if _trip_version != s.grid_version:
		_trip_cache.clear()
		_trip_version = s.grid_version
	var key := yard.id * 1000003 + work.id
	if not _trip_cache.has(key):
		var p := ws.find_path(ws.door_tile(yard), ws.door_tile(work))
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
		var to := ws.door_tile(b)
		for y in yards:
			var p := ws.find_path(ws.door_tile(y), to)
			if not p.is_empty() and 2.0 * ws.path_seconds(p) <= shift:
				far = false
				break
		if far and b.halt == "":
			_set_halt(s, b, "too_far")
		elif not far and b.halt == "too_far":
			_set_halt(s, b, "")


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
