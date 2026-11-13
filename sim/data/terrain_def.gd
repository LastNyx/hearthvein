class_name TerrainDef
extends Resource
## A terrain type for the tile-state grid.

@export var id: String = ""
@export var display_name: String = ""
## Whether buildings may stand on it at all (specific rules are the building's placement rule).
@export var buildable: bool = true
## Fertility a freshly generated tile of this terrain starts with, 0..1.
@export var fertility_start: float = 0.0
## Walking speed in tiles per second at 1x on this terrain without a road. 0 = impassable (design.md section 6).
@export var walk_speed: float = 1.0
