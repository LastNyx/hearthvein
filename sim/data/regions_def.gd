class_name RegionsDef
extends Resource
## Region buying numbers (design.md section 4). One resource: data/regions/regions.tres.
## The region grid itself is MapState; this is only the price table.

## Gold price of the 1st, 2nd, ... region bought, the start region excluded (design: 50, 100, 200, 350, 500).
@export var prices: Array[int] = [50, 100, 200, 350, 500]
## Price of every further region once `prices` runs out (design: 600 each).
@export var price_after: int = 600

## Rich vein reward (ticket 25b): Lumen yield multiplier for vein extractors in the region (design: x1.5).
@export var rich_vein_factor: float = 1.5
## Ruins reward (ticket 25b): gold paid once when the region is bought.
@export var ruins_gold: int = 0
## Ruins reward (ticket 25b): refined goods paid once into the nearest storage, good id -> amount.
@export var ruins_goods: Dictionary = {}
## Survey flight (Airship Dock, ticket 38): days a dock takes to reveal a locked region's reward.
@export var survey_days: int = 2
