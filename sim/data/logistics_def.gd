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

## Construction (design.md section 6, D48). Build time in days with a full crew = footprint tiles x days_per_tile
## + (era order - 1) x days_per_era, clamped to [build_days_min, build_days_max] (design: 1-6 days).
@export var build_days_per_tile: float = 0.0
@export var build_days_per_era: float = 0.0
@export var build_days_min: float = 0.0
@export var build_days_max: float = 0.0
## Builders that work one site at once. The days above are for this many; fewer builders take proportionally longer.
@export var builder_crew: int = 0
## Share of the cost (or of the goods already delivered to a site) given back on demolish.
@export var demolish_refund: float = 0.0
## Output factor of a building that could not pay the day's Lumen upkeep (design.md sections 8, 14 and 16: x0.5).
@export var unpaid_upkeep_factor: float = 0.5
## Share of its Lumen upkeep a building on the Lumen grid pays (design.md section 7: grid upkeep -25%, so 0.75).
@export var grid_upkeep_factor: float = 1.0
