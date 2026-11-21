class_name JobSystem
extends SimSystem
## Housing and automatic job assignment (design.md sections 5-6, D15). The player never assigns a person.
## Settlement.refresh_population() runs this after every change (placement, demolish, road, priority, citizens)
## and the system also runs it every hour, so the result is always current and fully deterministic.

## Job priority order, highest first. Single mapping table from BuildingDef.category to a rank.
## "logistics" is the design's "hauling"; "refining" is "refined goods". There is no gold-producing category yet,
## when one is added put it in at its place between refining and civic. Categories not listed (housing, sky,
## landmark) rank last.
## "build" (design.md section 6 gives no rank, ticket 11 decided): builder slots rank right after hauling and before
## resources, because a site only starts once haulers have delivered, and building is what makes everything below
## it possible. Builder slots only open while sites are ready to build (see _cap_builders).
const CATEGORY_ORDER: Array[String] = [
	"food", "water", "lumen", "logistics", "build", "resources", "refining", "gold", "civic",
]
## Builder slots (def.builder_slots) always rank as the building tier, whatever the building's own category.
const BUILD_CATEGORY := "build"
## Hauler slots (def.hauler_slots) always rank as the hauling tier, whatever the building's own category.
const HAUL_CATEGORY := "logistics"
## Within a category: high first, then normal, then low. Paused buildings get no workers at all.
const PRIORITY_ORDER: Array[String] = ["high", "normal", "low"]


## The hourly refresh is a cheap idempotent pass, but it costs a few ms at 600 citizens (ticket 55), so skip it
## when nothing that feeds it changed since the last hourly run: the citizen and building sets and the road/building
## layout (structure_version, not terrain). Every other change (pausing, priorities, sites finishing) calls refresh_population itself.
var _citizens: int = -1
var _buildings: int = -1
var _grid: int = -1


func on_hour(settlement: Settlement) -> void:
	if settlement.citizens.size() == _citizens and settlement.buildings.size() == _buildings \
			and settlement.structure_version == _grid:
		return
	_citizens = settlement.citizens.size()
	_buildings = settlement.buildings.size()
	_grid = settlement.structure_version
	refresh(settlement)


## Same ranks as CATEGORY_ORDER / PRIORITY_ORDER as dictionary lookups (the refresh runs per building).
const _CATEGORY_RANK := {"food": 0, "water": 1, "lumen": 2, "logistics": 3, "build": 4, "resources": 5, "refining": 6,
	"gold": 7, "civic": 8}
## Shift of a slot entry. Night slots fill after the day slots of the same rank (ticket 132 fills them); each
## (rank, priority, shift) is a fair-share group.
const SHIFT_DAY := 0
const SHIFT_NIGHT := 1
const _KIND_CODE := {Citizen.JOB_WORK: 1, Citizen.JOB_HAUL: 2, Citizen.JOB_BUILD: 3}
const _PRIORITY_RANK := {"high": 0, "normal": 1, "low": 2}


static func category_rank(category: String) -> int:
	var r := CATEGORY_ORDER.find(category)
	return r if r >= 0 else CATEGORY_ORDER.size()


## Houses first, then jobs.
static func refresh(s: Settlement) -> void:
	var c := s.get_system(JobSystem) as JobSystem
	if c == null:
		c = JobSystem.new()  # no system registered: a one-off cache
	c._sync(s)
	_assign_homes(s, c)
	_assign_jobs(s, c)


## Layout cache: what housing and job assignment read from the buildings (bed counts, slot entries, works), rebuilt
## when the building set, structure/completion versions or any layout field (Building.layout_rev) moved. Runtime only.
var _lc_key: Array = []
var _lc_free: Dictionary = {}  # building id -> beds, finished housing only
var _lc_order: Array = []  # ids of _lc_free, ascending
var _lc_entries: Array = []  # slot entries before the builder cap, in fill order
var _lc_works: Array = []  # buildings that are sites or in-place upgrades


func _sync(s: Settlement) -> void:
	var key := [s.buildings.size(), s.structure_version, s.completion_version, Building.layout_rev]
	if key == _lc_key:
		return
	_lc_key = key
	_lc_free = {}
	for bid in _sorted_building_ids(s):
		var b: Building = s.buildings[bid]
		if b.site or b.def.housing_beds <= 0:
			continue
		var beds := b.effective_beds(s.registry)
		if beds > 0 and (b.layer == Building.LAYER_GROUND or b.connected):  # a sky home needs a lift route to work
			_lc_free[bid] = beds
	_lc_order = _lc_free.keys()
	_lc_entries = _job_entries(s)
	_lc_works = []
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.upgrade_tier > 0:
			_lc_works.append(b)


static func _sorted_citizen_ids(s: Settlement) -> Array:
	var ids: Array = s.citizens.keys()
	ids.sort()
	return ids


static func _sorted_building_ids(s: Settlement) -> Array:
	var ids: Array = s.buildings.keys()
	ids.sort()
	return ids


## Keep valid homes, then fill free beds (lowest building id first) with homeless citizens (lowest id first).
static func _assign_homes(s: Settlement, c: JobSystem) -> void:
	var free: Dictionary = c._lc_free.duplicate()
	var homeless: Array = []
	for cid in _sorted_citizen_ids(s):
		var z: Citizen = s.citizens[cid]
		if free.get(z.home_id, 0) > 0:
			free[z.home_id] -= 1
		else:
			z.home_id = -1
			homeless.append(z)
	var order: Array = c._lc_order
	for h: Citizen in homeless:
		for bid in order:
			if free[bid] > 0:
				free[bid] -= 1
				h.home_id = bid
				break


## Slot entries {building, kind, slots, group, shift} in fill order: category rank, priority, shift (day before
## night), building id, then kind. Each entry gets one int sort key so a plain int sort does the ordering.
static func _job_entries(s: Settlement) -> Array:
	var by_key := {}
	var haul_rank := category_rank(HAUL_CATEGORY)
	var build_rank := category_rank(BUILD_CATEGORY)
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		var d := b.def
		if d.worker_slots <= 0 and d.hauler_slots <= 0 and d.builder_slots <= 0 and b.tier <= 1 \
				and d.night_worker_slots <= 0 and d.night_hauler_slots <= 0:
			continue  # no slot of any kind (a tier can add worker slots, tier I cannot)
		if b.paused or not b.connected or b.site:
			continue
		var pr: int = _PRIORITY_RANK.get(b.priority, 1)
		var lit := s.is_lit(b)  # a night slot stays closed while its building is dark (ticket 132, spec N2)
		var slots := b.effective_worker_slots(s.registry)
		var rank: int = _CATEGORY_RANK.get(b.def.category, CATEGORY_ORDER.size())
		if slots > 0 and not d.night_only:
			_add_entry(by_key, b, Citizen.JOB_WORK, slots, rank, pr, 2, SHIFT_DAY)
		if d.night_worker_slots > 0 and lit:
			_add_entry(by_key, b, Citizen.JOB_WORK, d.night_worker_slots, rank, pr, 2, SHIFT_NIGHT)
		if d.hauler_slots > 0:
			_add_entry(by_key, b, Citizen.JOB_HAUL, d.hauler_slots, haul_rank, pr, 1, SHIFT_DAY)
		if d.night_hauler_slots > 0 and lit:
			_add_entry(by_key, b, Citizen.JOB_HAUL, d.night_hauler_slots, haul_rank, pr, 1, SHIFT_NIGHT)
		if d.builder_slots > 0:
			_add_entry(by_key, b, Citizen.JOB_BUILD, d.builder_slots, build_rank, pr, 0, SHIFT_DAY)
	var keys: Array = by_key.keys()
	keys.sort()
	var entries: Array = []
	for k in keys:
		entries.append(by_key[k])
	return entries


## One slot entry, keyed by group, building id and kind code (build 0 < haul 1 < work 2, alphabetical).
static func _add_entry(by_key: Dictionary, b: Building, kind: String, slots: int, rank: int, pr: int,
		kind_code: int, shift: int) -> void:
	var group := _group_key(rank, pr, shift)
	by_key[_order_key(group, b.id, kind_code)] = {"building": b, "kind": kind, "slots": slots, "group": group,
		"shift": shift}


## Fair-share group: one (rank, priority, shift). Shift sorts day before night, so night slots come after the day
## slots of the same rank and each group is shared the same way.
static func _group_key(rank: int, pr: int, shift: int) -> int:
	return (rank * 4 + pr) * 2 + shift


## Sort key: group, then building id, then kind code.
static func _order_key(group: int, bid: int, kind_code: int) -> int:
	return ((group << 24) + bid) * 4 + kind_code


## Builders are only wanted while sites are ready to build (full cost delivered, not paused): crew size per such
## site. Surplus builder slots stay closed, so those citizens work somewhere useful instead of standing around.
static func _cap_builders(s: Settlement, c: JobSystem, entries: Array) -> Array:
	var demand := 0
	if s.registry.logistics != null:
		for b: Building in c._lc_works:
			if ConstructionSystem.is_ready(b):
				demand += s.registry.logistics.builder_crew
		demand += ConstructionSystem.clear_job_indices(s).size()  # one builder per marked tile (ticket 100)
	var out: Array = []
	for e in entries:
		if e["kind"] == Citizen.JOB_BUILD:
			e["slots"] = mini(e["slots"], demand)
			demand -= e["slots"]
			if e["slots"] <= 0:
				continue
		out.append(e)
	return out


## Int key of a (building, job kind, shift) slot; cheaper than a formatted string. A building's day and night slots
## are different slots, so the night bit keeps them apart.
static func _slot_key(building_id: int, kind: String, night: bool) -> int:
	return building_id * 8 + _KIND_CODE.get(kind, 0) * 2 + (1 if night else 0)


## One slot each for the group's entries [from, to), in entry order, round after round, until every slot is filled
## or the citizens run out. Returns the citizens still free.
static func _fill_shared(entries: Array, from: int, to: int, left: int) -> int:
	while left > 0:
		var gave := false
		for k in range(from, to):
			var e = entries[k]
			if e["want"] < e["slots"]:
				e["want"] += 1
				left -= 1
				gave = true
				if left <= 0:
					break
		if not gave:
			break
	return left


## Slots are allotted in priority order until citizens run out. Inside one (rank, priority) group the slots are
## shared round-robin across its buildings (one each in building-id order, repeat) so the last-built are not left
## empty. Citizens already in an allotted slot keep it (no churn), everyone else goes idle, then idle citizens
## (lowest id first) fill what is left. Deterministic, no RNG.
static func _assign_jobs(s: Settlement, sys: JobSystem) -> void:
	var entries: Array = []
	for e in sys._lc_entries:
		entries.append(e.duplicate())
	entries = _cap_builders(s, sys, entries)
	var left := s.citizens.size()
	# Hauler reserve first (data: min_hauler_share), then every slot in rank order.
	var reserve := 0
	if s.registry.logistics != null:
		reserve = floori(left * s.registry.logistics.min_hauler_share)
	for e in entries:
		var n := 0
		if e["kind"] == Citizen.JOB_HAUL:
			n = mini(mini(e["slots"], reserve), left)
			reserve -= n
		e["want"] = n
		left -= n
	# A small town (under small_town_pop people) gives every workplace its first hand, then the builders their crews,
	# before any second hand: the opening is a dozen people and one woodcutter hand pays for the next site (ticket 118).
	if s.registry.logistics != null and s.citizens.size() < s.registry.logistics.small_town_pop:
		for e in entries:
			if e["kind"] == Citizen.JOB_WORK and e["shift"] == SHIFT_DAY and left > 0:
				e["want"] += 1
				left -= 1
		for e in entries:
			if e["kind"] == Citizen.JOB_BUILD:
				var n := mini(e["slots"], left)
				e["want"] += n
				left -= n
	var g := 0
	while g < entries.size() and left > 0:
		var end := g + 1
		while end < entries.size() and entries[end]["group"] == entries[g]["group"]:
			end += 1
		left = _fill_shared(entries, g, end, left)
		g = end
	var by_slot := {}
	for e in entries:
		by_slot[_slot_key(e["building"].id, e["kind"], e["shift"] == SHIFT_NIGHT)] = e
	var idle: Array = []
	for cid in _sorted_citizen_ids(s):
		var c: Citizen = s.citizens[cid]
		var e = by_slot.get(_slot_key(c.job_id, c.job_kind, c.shift == Citizen.SHIFT_NIGHT)) if c.job_id >= 0 else null
		if e != null and e["want"] > 0:
			e["want"] -= 1
		else:
			if c.job_id >= 0:
				s.events.emit("citizen_job_changed", {"id": c.id, "job": -1})
			c.job_id = -1
			c.job_kind = Citizen.JOB_NONE
			c.shift = Citizen.SHIFT_DAY
			idle.append(c)
	var i := 0
	for e in entries:
		while e["want"] > 0 and i < idle.size():
			var c: Citizen = idle[i]
			i += 1
			e["want"] -= 1
			c.job_id = e["building"].id
			c.job_kind = e["kind"]
			c.shift = Citizen.SHIFT_NIGHT if e["shift"] == SHIFT_NIGHT else Citizen.SHIFT_DAY
			s.events.emit("citizen_job_changed", {"id": c.id, "job": c.job_id})
