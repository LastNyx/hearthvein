class_name PlanetDef
extends Resource
## The numbers of planet health (design.md section 13, D30). One resource: data/planet/planet.tres.
## Health is in percent points 0-100; every "per day" is percent points per day. Per-building drains and gains live
## on BuildingDef.health_per_day.

@export var start: float = 100.0
## Per blighted tile per day (negative).
@export var per_blight_tile: float = -0.0006
## Per forest tile on the map per day.
@export var per_forest_tile: float = 0.00005
## Per active Great Dimming day (ticket 45 reports it through PlanetHealthSystem.extra_sources).
@export var great_dimming_day: float = -0.5
## Vein yield factor = vein_base + health / vein_divisor.
@export var vein_base: float = 0.5
@export var vein_divisor: float = 200.0
## Below this health each season (dieback_below - health) / dieback_divisor percent of forest tiles die back.
@export var dieback_below: float = 60.0
@export var dieback_divisor: float = 10.0
## Terrain id a dead forest tile becomes.
@export var dieback_terrain: String = "grass"
## The trend is the change over this many days (one year).
@export var trend_days: int = 32
