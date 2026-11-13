class_name SoilDef
extends Resource
## The numbers of soil fertility (design.md section 9). One resource: data/soil/soil.tres.
## The per-tile fertility itself is in MapState.fertility (0-100); these are the drift rates and the one factor.

## Points a Farm's footprint tiles lose each season while the Farm works (design.md: -4 a year, 4 seasons a year).
@export var wear_per_season: float = 1.0
## Points a fallow tile regains each season, up to the fertility its terrain started with (+10 a year).
@export var recovery_per_season: float = 2.5
## A blighted tile's fertility counts at this factor in a Farm's output (design.md: half, until cleared).
@export var blight_factor: float = 0.5
