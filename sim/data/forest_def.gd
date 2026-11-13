class_name ForestDef
extends Resource
## The numbers of forest regrowth and Forester planting (design.md section 9). One resource: data/forest/forest.tres.
## The stumps themselves are plain terrain (MapState); ForestSystem keeps their age.

## Seasons a stump needs to grow back to forest while planet health is high enough and the tile is not blighted.
@export var regrow_seasons: int = 2
## Seasons the same stump needs within BuildingDef.placement_radius of a staffed Forester (design: halved).
@export var forester_regrow_seasons: int = 1
## Lowest planet health at which stumps grow at all (design: 60%).
@export var regrow_min_health: float = 60.0
## Plain grass tiles a Forester plants per worker per day.
@export var plant_per_worker_day: float = 1.0
## Data hook for the old-forest region reward (ticket 25b): a regrowth factor of 0.5 halves the seasons needed, so
## that forest regrows twice as fast. ForestSystem.regrow_factors carries the Callables that apply it per tile.
@export var old_forest_regrow_factor: float = 0.5
