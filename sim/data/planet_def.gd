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
## The Great Dimming (design.md sections 14 and 18, D33, ticket 45b): length in days (not scaled by health), vein
## extractor and food producer output factors, light need per citizen (the Dawn Beacon's lower need does not apply).
@export var great_dimming_days: int = 16
@export var great_dimming_vein_factor: float = 0.1
@export var great_dimming_food_factor: float = 0.5
@export var great_dimming_light: float = 0.75
## Planet health the Great Dimming must end at or above for the win (design.md section 18, ticket 45c).
@export var win_health: float = 50.0
## Endless (design.md section 19, ticket 46): the regular Dimming's base grows by one day every this many years after
## the endless phase began (the Great Dimming ended, or Ascendant was reached in an endless start). No cap.
@export var endless_years_per_day: int = 2
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
## The Dimming (design.md section 14, D37, D43). It starts on day 1 of season index `dimming_start_season` (3 =
## winter), forecast `dimming_forecast_seasons` seasons earlier. Length uses EraDef.dimming_base_days.
@export var dimming_start_season: int = 3
@export var dimming_forecast_seasons: int = 1
## Vein extractor output factor during a Dimming (other buildings use BuildingDef.dimming_factor).
@export var dimming_vein_factor: float = 0.25
## Light need per citizen per Dimming day, in Lumen. 1 Lumen cell = lumen_per_cell Lumen.
@export var light_per_citizen: float = 0.5
@export var lumen_per_cell: float = 5.0
## Output factor of the lean_winter food producers during winter (ticket 159).
@export var winter_food_factor: float = 0.5
## Spirit target change while dark (negative).
@export var darkness_spirit: float = -20.0
## Glow river (spec N10, ticket 151): during a Dimming the river tiles count as lit radius 1 at night. A Glowcap Grove
## whose footprint lies within glow_river_radius tiles (Euclidean, the placement_radius measure) of a river tile makes
## glow_river_grove_factor of its output.
@export var glow_river_radius: int = 2
@export var glow_river_grove_factor: float = 1.25
## Starlight (ticket 151): Lumen one starlight covers when the day's light draw runs short, after raw Lumen and cells.
@export var starlight_lumen: float = 5.0
