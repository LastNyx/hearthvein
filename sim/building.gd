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
## Why production stopped: "" running, "door_full", "no_input", "no_forest".
var halt: String = ""


func footprint() -> Rect2i:
	return Rect2i(origin, def.size)


func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			out.append(Vector2i(x, y))
	return out
