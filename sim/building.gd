class_name Building
extends RefCounted
## A placed building instance. Plain data; later tickets add fields (tier, workers, buffers, construction).

var id: int = -1
var def: BuildingDef:
	set(v):
		def = v
		layout_rev += 1
## Bumped whenever a field that housing or job assignment reads changes (JobSystem caches on it). Runtime only.
static var layout_rev: int = 0
## Top-left tile of the footprint.
var origin: Vector2i = Vector2i.ZERO
## True when a road path links it to the Hearth (design.md section 6, D22). The Hearth itself is always connected.
var connected: bool = false:
	set(v):
		if v != connected:
			connected = v
			layout_rev += 1
var tier: int = 1:
	set(v):
		if v != tier:
			tier = v
			layout_rev += 1
var paused: bool = false:
	set(v):
		if v != paused:
			paused = v
			layout_rev += 1
var priority: String = "normal":
	set(v):
		if v != priority:
			priority = v
			layout_rev += 1
## Null unless def.storage_mode != "none".
var inventory: Inventory = null
## Producers (recipe != null): output waits here until a hauler carries it off (ProductionSystem makes it).
var door_buffer: Inventory = null
## Consumers (recipe with inputs): hauled-in inputs, per good.
var input_buffer: Inventory = null
## Construction site (D48): true until the full cost is delivered and the work is done. A site has no jobs, no
## housing, no storage and makes nothing; input_buffer holds the goods delivered so far (and only those).
var site: bool = false:
	set(v):
		if v != site:
			site = v
			layout_rev += 1
## Builder-days of work done so far and needed (build days x crew), see ConstructionSystem.
var build_work: float = 0.0
var build_work_needed: float = 0.0
## In-place upgrade (design.md section 10). Target tier while the works run (0 = none), the whole cost and the buffer
## haulers deliver it into, and builder-days done and needed. The building stays out of `site` mode and keeps working
## at its current `tier` until the work is done.
var upgrade_tier: int = 0:
	set(v):
		if v != upgrade_tier:
			upgrade_tier = v
			layout_rev += 1
var upgrade_cost: Dictionary = {}
var upgrade_buffer: Inventory = null
var upgrade_work: float = 0.0
var upgrade_work_needed: float = 0.0
## Why production stopped: "" running, "door_full", "no_input", "no_forest", "dry", "blight".
var halt: String = ""


## True while an in-place upgrade is in flight.
func upgrading() -> bool:
	return upgrade_tier > 0


## Upgrade progress 0..1 (0 when not upgrading).
func upgrade_progress() -> float:
	if not upgrading():
		return 0.0
	return clampf(upgrade_work / upgrade_work_needed, 0.0, 1.0) if upgrade_work_needed > 0.0 else 0.0


## True when every good of the upgrade cost is in the upgrade buffer.
func upgrade_delivered() -> bool:
	if not upgrading():
		return true
	for g in upgrade_cost:
		if upgrade_buffer == null or upgrade_buffer.amount_of(g) < float(upgrade_cost[g]) - Inventory.EPS:
			return false
	return true


## The TierDef for a tier (default: the building's current one), or null.
func tier_def(reg: DataRegistry, at_tier: int = -1) -> TierDef:
	var t := at_tier if at_tier > 0 else tier
	var i := t - 2  # tiers[0] is tier II
	if i < 0 or i >= def.tiers.size():
		return null
	return def.tiers[i]


## Name shown for the building now (Tent tier II is the Hut, design.md section 10).
func display_name(reg: DataRegistry) -> String:
	var td := tier_def(reg)
	return td.display_name if td != null and td.display_name != "" else def.display_name


## art_manifest id of the sprite for the current tier ("" = use the base sprite of the def).
func tier_art_id(reg: DataRegistry) -> String:
	var td := tier_def(reg)
	return td.art_id if td != null else ""


## Output (or beds) multiplier of the current tier over base, from data (1.0 at tier I).
func output_factor(reg: DataRegistry) -> float:
	if tier <= 1:
		return 1.0
	if reg != null and reg.tiers != null:
		return reg.tiers.output_factor(def, tier)
	var td := tier_def(reg)
	return td.multiplier if td != null and td.multiplier > 0.0 else 1.0


## Worker slots now: the def's slots plus the tier's extra slots.
func effective_worker_slots(reg: DataRegistry) -> int:
	if tier <= 1:
		return def.worker_slots
	if reg != null and reg.tiers != null:
		return def.worker_slots + reg.tiers.extra_slots(def, tier)
	var td := tier_def(reg)
	return def.worker_slots + (maxi(0, td.extra_worker_slots) if td != null else 0)


## Beds now: base beds x the tier's output factor, rounded to a whole bed (Tent II = Hut, 3 beds).
func effective_beds(reg: DataRegistry) -> int:
	return roundi(float(def.housing_beds) * output_factor(reg))


## Whole-good cost of reaching `at_tier`: the per-def TierDef cost when it has one, else the default rule.
func tier_cost(reg: DataRegistry, at_tier: int) -> Dictionary:
	var td := tier_def(reg, at_tier)
	if td != null and not td.cost.is_empty():
		return td.cost.duplicate()
	if reg != null and reg.tiers != null:
		return reg.tiers.cost_of(def, at_tier)
	return {}


## Site progress 0..1 (1 for a finished building).
func build_progress() -> float:
	if not site:
		return 1.0
	return clampf(build_work / build_work_needed, 0.0, 1.0) if build_work_needed > 0.0 else 0.0


## True when every non-gold good of the cost is in the site's buffer (gold is paid on placement).
func site_delivered() -> bool:
	if not site:
		return true
	for g in def.cost:
		if g != BuildingDef.GOLD and (input_buffer == null or input_buffer.amount_of(g) < float(def.cost[g]) - Inventory.EPS):
			return false
	return true


func footprint() -> Rect2i:
	return Rect2i(origin, def.size)


## Chebyshev distance in tiles between two footprints, tile edge to tile edge (0 when they touch or overlap).
## The one measure Market reach (ticket 23) and coverage (ticket 23b) use, so both can be drawn the same way.
static func footprint_gap(a: Building, b: Building) -> int:
	var ra := a.footprint()
	var rb := b.footprint()
	var dx := maxi(maxi(ra.position.x - (rb.end.x - 1), rb.position.x - (ra.end.x - 1)), 0)
	var dy := maxi(maxi(ra.position.y - (rb.end.y - 1), rb.position.y - (ra.end.y - 1)), 0)
	return maxi(dx, dy)


func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			out.append(Vector2i(x, y))
	return out


## Plain-data snapshot for a save. The def is stored by id and resolved through DataRegistry on load.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"def": def.id,
		"origin": origin,
		"connected": connected,
		"tier": tier,
		"paused": paused,
		"priority": priority,
		"inventory": inventory.to_dict() if inventory != null else null,
		"door_buffer": door_buffer.to_dict() if door_buffer != null else null,
		"input_buffer": input_buffer.to_dict() if input_buffer != null else null,
		"site": site,
		"build_work": build_work,
		"build_work_needed": build_work_needed,
		"upgrade_tier": upgrade_tier,
		"upgrade_cost": upgrade_cost.duplicate(),
		"upgrade_buffer": upgrade_buffer.to_dict() if upgrade_buffer != null else null,
		"upgrade_work": upgrade_work,
		"upgrade_work_needed": upgrade_work_needed,
		"halt": halt,
	}


## Null when the stored def id is not in the registry (a bad or too-new save).
static func from_dict(d: Dictionary, registry: DataRegistry) -> Building:
	var b := Building.new()
	b.id = int(d["id"])
	b.def = registry.get_building(str(d["def"]))
	if b.def == null:
		push_error("Building.from_dict: unknown building def '%s'" % str(d["def"]))
		return null
	b.origin = d["origin"]
	b.connected = bool(d["connected"])
	b.tier = int(d["tier"])
	b.paused = bool(d["paused"])
	b.priority = str(d["priority"])
	if d["inventory"] != null:
		b.inventory = Inventory.from_dict(d["inventory"])
	if d["door_buffer"] != null:
		b.door_buffer = Inventory.from_dict(d["door_buffer"])
	if d["input_buffer"] != null:
		b.input_buffer = Inventory.from_dict(d["input_buffer"])
	b.site = bool(d["site"])
	b.build_work = float(d["build_work"])
	b.build_work_needed = float(d["build_work_needed"])
	b.upgrade_tier = int(d.get("upgrade_tier", 0))
	b.upgrade_cost = d.get("upgrade_cost", {}).duplicate()
	if d.get("upgrade_buffer") != null:
		b.upgrade_buffer = Inventory.from_dict(d["upgrade_buffer"])
	b.upgrade_work = float(d.get("upgrade_work", 0.0))
	b.upgrade_work_needed = float(d.get("upgrade_work_needed", 0.0))
	b.halt = str(d["halt"])
	return b
