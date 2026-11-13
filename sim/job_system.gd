class_name JobSystem
extends SimSystem
## Housing and automatic job assignment (design.md sections 5-6, D15). The player never assigns a person.
## Settlement.refresh_population() runs this after every change (placement, demolish, road, priority, citizens)
## and the system also runs it every hour, so the result is always current and fully deterministic.

## Job priority order, highest first. Single mapping table from BuildingDef.category to a rank.
## "logistics" is the design's "hauling"; "refining" is "refined goods". There is no gold-producing category yet,
## when one is added put it in at its place between refining and civic. Categories not listed (housing, sky,
## landmark) rank last.
const CATEGORY_ORDER: Array[String] = [
	"food", "water", "lumen", "logistics", "materials", "refining", "gold", "civic",
]
## Hauler slots (def.hauler_slots) always rank as the hauling tier, whatever the building's own category.
const HAUL_CATEGORY := "logistics"
## Within a category: high first, then normal, then low. Paused buildings get no workers at all.
const PRIORITY_ORDER: Array[String] = ["high", "normal", "low"]


func on_hour(settlement: Settlement) -> void:
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
		if b.def.housing_beds > 0:
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


## Slot entries {building, kind, slots} in fill order: category rank, priority, building id.
static func _job_entries(s: Settlement) -> Array:
	var entries: Array = []
	for bid in _sorted_building_ids(s):
		var b: Building = s.buildings[bid]
		if b.paused or not b.connected:
			continue
		var pr := PRIORITY_ORDER.find(b.priority)
		if pr < 0:
			pr = PRIORITY_ORDER.find("normal")
		if b.def.worker_slots > 0:
			entries.append({"building": b, "kind": Citizen.JOB_WORK, "slots": b.def.worker_slots,
				"key": [category_rank(b.def.category), pr, bid]})
		if b.def.hauler_slots > 0:
			entries.append({"building": b, "kind": Citizen.JOB_HAUL, "slots": b.def.hauler_slots,
				"key": [category_rank(HAUL_CATEGORY), pr, bid]})
	entries.sort_custom(func(a, b):
		for i in 3:
			if a["key"][i] != b["key"][i]:
				return a["key"][i] < b["key"][i]
		return a["kind"] < b["kind"])
	return entries


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
		by_slot["%d:%s" % [e["building"].id, e["kind"]]] = e
	var idle: Array = []
	for cid in _sorted_citizen_ids(s):
		var c: Citizen = s.citizens[cid]
		var e = by_slot.get("%d:%s" % [c.job_id, c.job_kind])
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
