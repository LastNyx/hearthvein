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


func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			out.append(Vector2i(x, y))
	return out
