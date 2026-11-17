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
## Rail track (design.md section 8, ticket 37): cost of one track tile, paid at once from storage. Whole units.
@export var track_cost_materials: float = 0.0
@export var track_cost_cut_stone: float = 0.0
## Cargo rail manifests (design.md section 8, ticket 37b). A region's target stock of a good is its daily demand times
## this many days; a depot's train moves at most train_capacity units out per day, at train_speed track tiles per hour.
@export var manifest_cover_days: float = 0.0
@export var train_capacity: float = 0.0
@export var train_speed: float = 1.0
## Airship freight (design.md sections 8 and 17, ticket 38): a staffed dock's airship moves at most airship_capacity units
## out per day, at airship_speed tiles per hour in a straight line between docks.
@export var airship_capacity: float = 0.0
@export var airship_speed: float = 1.0
## Sky islands (design.md section 17, ticket 40): a Lift Anchor raises an island_width x island_height island centred
## over its region, at most island_max islands.
@export var island_width: int = 16
@export var island_height: int = 12
@export var island_max: int = 4
## Lumen per day each raised island draws through the grid of its Lift Anchor (ticket 40b); drawn hourly pro rata.
@export var island_upkeep_lumen: float = 20.0
## Game seconds (1x) a walker spends riding a Sky Lift or crossing between a ground and an island Airship Dock
## (ticket 40c). Entering the other layer costs this instead of 1 / tile speed.
@export var lift_ride_seconds: float = 3.0
@export var dock_ride_seconds: float = 6.0
