class_name RegionsDef
extends Resource
## Region buying numbers (design.md section 4). One resource: data/regions/regions.tres.
## The region grid itself is MapState; this is only the price table.

## Gold price of the 1st, 2nd, ... region bought, the start region excluded (design: 50, 100, 200, 350, 500).
@export var prices: Array[int] = [50, 100, 200, 350, 500]
## Price of every further region once `prices` runs out (design: 600 each).
@export var price_after: int = 600
