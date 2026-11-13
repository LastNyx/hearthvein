class_name ConstructionSystem
extends SimSystem
## Builders and construction sites (design.md section 6, D48).
##
## A site (Building.site) first waits for haulers to deliver its whole cost (HaulingSystem treats it as a consumer).
## Only then is it "ready": ready sites are what builders work on. Builders are citizens with Citizen.JOB_BUILD, a slot
## of the Hearth (4) or a Builder's Yard (BuildingDef.builder_slots) that JobSystem fills automatically; slots only
## open while ready sites exist (crew size per site).
##
## During the work shift (WalkerSystem 06-18) builders are spread over ready sites in site order, up to
## LogisticsDef.builder_crew per site; site order is priority high, normal, low, then lowest id (paused sites get
## nobody). So the highest-priority site gets builders first. Each builder is a controlled walker sent to the
## site's door. Work counts only while a builder stands at the site door (not walking), pro-rated over time like
## production: a builder at the door for the whole shift does one builder-day. A site needs build_days x crew
## builder-days (Settlement.build_days), so a full crew finishes in build_days and fewer builders take longer.
## Outside the shift builders are released to the normal schedule.

var crews: Dictionary = {}  # citizen id -> site building id the builder was sent to


## Sites with the whole cost delivered and not paused, best first (priority, then id).
static func ready_sites(s: Settlement) -> Array[Building]:
	var out: Array[Building] = []
	var ids: Array = s.buildings.keys()
	ids.sort()
	for id in ids:
		var b: Building = s.buildings[id]
		if b.site and not b.paused and b.site_delivered():
			out.append(b)
	out.sort_custom(func(a: Building, b: Building) -> bool:
		var pa := JobSystem.PRIORITY_ORDER.find(a.priority)
		var pb := JobSystem.PRIORITY_ORDER.find(b.priority)
		return pa < pb if pa != pb else a.id < b.id)
	return out


static func builders_wanted(s: Settlement) -> int:
	if s.registry.logistics == null:
		return 0
	return ready_sites(s).size() * s.registry.logistics.builder_crew


func on_seconds(s: Settlement, seconds: float) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null or s.registry.logistics == null:
		return
	var h := s.clock.hour()
	var in_shift := h >= WalkerSystem.WORK_START_HOUR and h < WalkerSystem.WORK_END_HOUR
	var builders: Array = []
	var ids: Array = s.citizens.keys()
	ids.sort()
	for cid in ids:
		if (s.citizens[cid] as Citizen).job_kind == Citizen.JOB_BUILD:
			builders.append(cid)
	var wanted := {}  # citizen id -> site
	var sites: Array[Building] = []
	if in_shift:
		sites = ready_sites(s)
	var i := 0
	for site in sites:
		for k in s.registry.logistics.builder_crew:
			if i < builders.size():
				wanted[builders[i]] = site
				i += 1
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
			work[site.id] = work.get(site.id, 0.0) + seconds / shift
	var done: Array[Building] = []
	for sid in work:
		var site: Building = s.buildings[sid]
		site.build_work += work[sid]
		if site.build_work >= site.build_work_needed - Inventory.EPS:
			done.append(site)
	for site in done:
		site.build_work = site.build_work_needed
		for cid in crews.keys():
			if crews[cid] == site.id:
				_release(s, ws, cid, in_shift)
		s.complete_site(site)


## Hand the builder back to the schedule (walk home, or to the Hearth when homeless).
func _release(s: Settlement, ws: WalkerSystem, cid: int, _in_shift: bool) -> void:
	crews.erase(cid)
	var w := ws.walker_of(cid)
	var c: Citizen = s.citizens.get(cid)
	if w == null or c == null:
		return
	w.controlled = false
	var target := c.home_id if s.buildings.has(c.home_id) else (s.hearth.id if s.hearth != null else -1)
	if _in_shift and c.job_id >= 0 and s.buildings.has(c.job_id) and c.job_kind == Citizen.JOB_BUILD:
		target = c.job_id
	if target >= 0:
		ws.walk_to_building(cid, target)
