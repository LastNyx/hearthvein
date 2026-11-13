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
## materials, because a site only starts once haulers have delivered, and building is what makes everything below
## it possible. Builder slots only open while sites are ready to build (see _cap_builders).
const CATEGORY_ORDER: Array[String] = [
	"food", "water", "lumen", "logistics", "build", "materials", "refining", "gold", "civic",
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


static func category_rank(category: String) -> int:
	var r := CATEGORY_ORDER.find(category)
	return r if r >= 0 else CATEGORY_ORDER.size()


## Houses first, then jobs.
static func refresh(s: Settlement) -> void:
	_assign_homes(s)
	_assign_jobs(s)


static func _sorted_citizen_ids(s: Settlement) -> Array:
	var ids: Array = s.citizens.keys()
	ids.sort()
	return ids


static func _sorted_building_ids(s: Settlement) -> Array:
	var ids: Array = s.buildings.keys()
	ids.sort()
	return ids


## Keep valid homes, then fill free beds (lowest building id first) with homeless citizens (lowest id first).
static func _assign_homes(s: Settlement) -> void:
	var free := {}  # building id -> free beds
	for bid in _sorted_building_ids(s):
		var b: Building = s.buildings[bid]
		if b.def.housing_beds > 0 and not b.site:
			free[bid] = b.def.housing_beds
	var homeless: Array = []
	for cid in _sorted_citizen_ids(s):
		var c: Citizen = s.citizens[cid]
		if free.get(c.home_id, 0) > 0:
			free[c.home_id] -= 1
		else:
			c.home_id = -1
			homeless.append(c)
	var order: Array = free.keys()
	order.sort()
	for c: Citizen in homeless:
		for bid in order:
			if free[bid] > 0:
				free[bid] -= 1
				c.home_id = bid
				break


## Slot entries {building, kind, slots} in fill order: category rank, priority, building id, then kind.
## Each entry gets one int sort key (rank, priority, id, kind) so a plain int sort does the ordering.
static func _job_entries(s: Settlement) -> Array:
	var by_key := {}
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.paused or not b.connected or b.site:
			continue
		var pr := PRIORITY_ORDER.find(b.priority)
		if pr < 0:
			pr = PRIORITY_ORDER.find("normal")
		if b.def.worker_slots > 0:
			by_key[_order_key(category_rank(b.def.category), pr, bid, 2)] = {"building": b, "kind": Citizen.JOB_WORK,
				"slots": b.def.worker_slots}
		if b.def.hauler_slots > 0:
			by_key[_order_key(category_rank(HAUL_CATEGORY), pr, bid, 1)] = {"building": b, "kind": Citizen.JOB_HAUL,
				"slots": b.def.hauler_slots}
		if b.def.builder_slots > 0:
			by_key[_order_key(category_rank(BUILD_CATEGORY), pr, bid, 0)] = {"building": b, "kind": Citizen.JOB_BUILD,
				"slots": b.def.builder_slots}
	var keys: Array = by_key.keys()
	keys.sort()
	var entries: Array = []
	for k in keys:
		entries.append(by_key[k])
	return _cap_builders(s, entries)


## Sort key: rank, then priority, then building id, then kind code (build 0 < haul 1 < work 2, alphabetical).
static func _order_key(rank: int, pr: int, bid: int, kind_code: int) -> int:
	return (((rank * 4 + pr) << 24) + bid) * 4 + kind_code


## Builders are only wanted while sites are ready to build (full cost delivered, not paused): crew size per such
## site. Surplus builder slots stay closed, so those citizens work somewhere useful instead of standing around.
static func _cap_builders(s: Settlement, entries: Array) -> Array:
	var demand := ConstructionSystem.builders_wanted(s)
	var out: Array = []
	for e in entries:
		if e["kind"] == Citizen.JOB_BUILD:
			e["slots"] = mini(e["slots"], demand)
			demand -= e["slots"]
			if e["slots"] <= 0:
				continue
		out.append(e)
	return out


## Int key of a (building, job kind) slot; cheaper than a formatted string.
static func _slot_key(building_id: int, kind: String) -> int:
	return building_id * 4 + (1 if kind == Citizen.JOB_WORK else (2 if kind == Citizen.JOB_HAUL else (3 if kind == Citizen.JOB_BUILD else 0)))


## Slots are allotted in priority order until citizens run out. Citizens already in an allotted slot keep it
## (no churn), everyone else goes idle, then idle citizens (lowest id first) fill what is left.
static func _assign_jobs(s: Settlement) -> void:
	var entries := _job_entries(s)
	var left := s.citizens.size()
	for e in entries:
		var n := mini(e["slots"], left)
		e["want"] = n
		left -= n
	var by_slot := {}
	for e in entries:
		by_slot[_slot_key(e["building"].id, e["kind"])] = e
	var idle: Array = []
	for cid in _sorted_citizen_ids(s):
		var c: Citizen = s.citizens[cid]
		var e = by_slot.get(_slot_key(c.job_id, c.job_kind)) if c.job_id >= 0 else null
		if e != null and e["want"] > 0:
			e["want"] -= 1
		else:
			if c.job_id >= 0:
				s.events.emit("citizen_job_changed", {"id": c.id, "job": -1})
			c.job_id = -1
			c.job_kind = Citizen.JOB_NONE
			idle.append(c)
	var i := 0
	for e in entries:
		while e["want"] > 0 and i < idle.size():
			var c: Citizen = idle[i]
			i += 1
			e["want"] -= 1
			c.job_id = e["building"].id
			c.job_kind = e["kind"]
			s.events.emit("citizen_job_changed", {"id": c.id, "job": c.job_id})
