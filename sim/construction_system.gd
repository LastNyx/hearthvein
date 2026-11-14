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
	for cid in s.citizens:
		if (s.citizens[cid] as Citizen).job_kind == Citizen.JOB_BUILD:
			builders.append(cid)
	if builders.is_empty() and crews.is_empty():
		return  # nobody builds and nobody is on a crew: nothing below would do anything
	builders.sort()
	var wanted := {}  # citizen id -> site
	var sites: Array[Building] = []
	if in_shift:
		sites = ready_works(s)
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
