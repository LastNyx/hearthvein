class_name MapGenDef
extends Resource
## Map generation numbers for the river, lakes and ponds (ticket 52). One resource: data/mapgen/mapgen.tres.

## River width in tiles. Varies smoothly along the river between these (tile cross-sections are 2..4).
@export var river_width_min: float = 0.0
@export var river_width_max: float = 0.0
## Width noise frequency per centreline tile (lower = longer swells).
@export var river_width_freq: float = 0.0
## The 4-connected walk is smoothed by a moving average of +-this many tiles, so bends are round.
@export var river_smooth_window: int = 0
## Waypoint spacing along the river (tiles of progress) and the random sideways jitter of each waypoint.
@export var river_meander_spacing: int = 0
@export var river_meander_jitter: int = 0
## Distance of the river's flat reach from the start region centre (towards the map edge).
@export var river_start_offset: int = 0

## Lakes the river passes through (centred on the river, so they have flow like the river).
@export var lake_count_min: int = 0
@export var lake_count_max: int = 0
@export var lake_radius_min: float = 0.0
@export var lake_radius_max: float = 0.0
## Lakes and ponds keep at least this many tiles from the Hearth.
@export var water_hearth_clear: float = 0.0

## Standalone ponds (no flow), away from the river.
@export var pond_count_min: int = 0
@export var pond_count_max: int = 0
@export var pond_radius_min: float = 0.0
@export var pond_radius_max: float = 0.0
## Ponds keep at least this many tiles from river and lake water.
@export var pond_river_gap: float = 0.0
## How uneven lake and pond shores are, 0 = round, 0.3 = strongly lobed.
@export var shore_wobble: float = 0.0
