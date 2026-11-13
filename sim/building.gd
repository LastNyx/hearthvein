class_name Building
extends RefCounted
## A placed building instance. Plain data; later tickets add fields (tier, workers, buffers, construction).

var id: int = -1
var def: BuildingDef
## Top-left tile of the footprint.
var origin: Vector2i = Vector2i.ZERO
## True when a road path links it to the Hearth (design.md section 6, D22). The Hearth itself is always connected.
var connected: bool = false
var tier: int = 1
var paused: bool = false
var priority: String = "normal"
## Null unless def.storage_mode != "none".
var inventory: Inventory = null
## Producers (recipe != null): output waits here until a hauler carries it off (ProductionSystem makes it).
var door_buffer: Inventory = null
## Consumers (recipe with inputs): hauled-in inputs, per good.
var input_buffer: Inventory = null
## Construction site (D48): true until the full cost is delivered and the work is done. A site has no jobs, no
## housing, no storage and makes nothing; input_buffer holds the goods delivered so far (and only those).
var site: bool = false
## Builder-days of work done so far and needed (build days x crew), see ConstructionSystem.
var build_work: float = 0.0
var build_work_needed: float = 0.0
## Why production stopped: "" running, "door_full", "no_input", "no_forest".
var halt: String = ""


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
	b.halt = str(d["halt"])
	return b
