class_name RoadDef
extends Resource
## A road surface. `level` matches Settlement.ROAD_* (1 dirt, 2 paved). Data lives in data/roads/.

@export var id: String = ""
@export var display_name: String = ""
@export var level: int = 1
## Walking speed in tiles per second at 1x (design.md section 6).
@export var walk_speed: float = 1.0
