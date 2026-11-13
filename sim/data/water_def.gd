class_name WaterDef
extends Resource
## The numbers of the wet/dry map (design.md section 9). One resource: data/water/water.tres.
## The per-tile wetness itself is in MapState.wet (0/1); these are the radii and the farm bonus.

## A tile is wet within this many tiles of a water tile (river, lake or pond). Chebyshev distance.
@export var wet_radius_water: int = 2
## A tile is wet within this many tiles of a channel that flows. Chebyshev distance.
@export var wet_radius_channel: int = 1
## A Farm gets the wet bonus when at least this share of its footprint is wet (design.md: half).
@export var farm_wet_fraction: float = 0.5
## Farm output multiplier when the wet share is met (design.md: x1.25).
@export var farm_wet_bonus: float = 1.25
## Materials one Irrigation Channel tile costs, taken from storage when it is dug (design.md: 1 materials/tile).
@export var channel_cost_materials: float = 0.0
