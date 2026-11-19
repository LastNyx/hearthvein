class_name RoadDef
extends Resource
## A road surface. `level` matches Settlement.ROAD_* (1 dirt, 2 paved). Data lives in data/roads/.

@export var id: String = ""
@export var display_name: String = ""
@export var level: int = 1
## Walking speed in tiles per second at 1x (design.md section 6).
@export var walk_speed: float = 1.0
## Era id needed to build this road ("" = every era). design.md section 6: paved roads need Town.
@export var era: String = ""
## Cost per tile, good id -> amount. Empty = free (dirt). paved is 1 wood + 0.2 cut stone.
@export var cost: Dictionary = {}
## Extra cost per water tile when this road crosses the river as a bridge (ticket 91), good id -> amount. Charged on top of
## `cost`; paving a bridge tile pays the paved cost and this again. The road tile still counts as water underneath.
@export var bridge_cost: Dictionary = {}
