class_name LogisticsDef
extends Resource
## The numbers of production and hauling (design.md section 8, D39). One resource: data/logistics/logistics.tres.

## Units a producer's door buffer holds (all goods together). Full = production stops.
@export var door_buffer_cap: float = 0.0
## Units one hauler carries on foot.
@export var haul_load: float = 0.0
## A consumer's input buffer holds this many days of its recipe need (per good, at all worker slots).
@export var input_buffer_days: float = 0.0
## A hauler does not set out for less than this much.
@export var min_pickup: float = 0.0
## A woodcutter (BuildingDef.fells_forest) turns one forest tile into a stump per this many units produced.
@export var units_per_felled_tile: float = 0.0
