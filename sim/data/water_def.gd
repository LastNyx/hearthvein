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
## Stone one Irrigation Channel tile costs, taken from storage when it is dug.
@export var channel_cost_stone: float = 0.0
## Fouling (design.md section 9): a river tile next to a blighted tile is a source, and the fouling front moves this
## many river tiles downstream per hour.
@export var foul_spread_tiles_per_hour: int = 1
## Hours a fouled tile stays fouled after its source blight is gone (design.md: clears 2 days after the source).
@export var foul_clear_hours: int = 48
## Fishing Dock output multiplier when any water tile beside it is fouled (design.md: x0.5).
@export var foul_dock_output_factor: float = 0.5
## Farm output multiplier when its wetness comes only from fouled water (design.md: irrigated farms x0.75).
@export var foul_farm_output_factor: float = 0.75
## Spring floods (spec N10, ticket 154): land this many 4-connected steps from a river tile floods each spring. 0 = no
## floods.
@export var flood_radius: int = 2
## Days one spring flood lasts. 0 = no floods.
@export var flood_days: int = 3
## Fertility points a flooded tile gains when the flood drains (the silt). The silt shows until the next flood.
@export var flood_silt_fertility: float = 10.0


## One or two short lines on what an Irrigation Channel does, every number read from this resource (build tooltip,
## build hint and the Controls help page).
func channel_help() -> String:
	return "Wets the ground within %d tile%s of it while it is connected to water. Farms with at least %d%% of their tiles wet grow %d%% more; higher farm tiers need wet ground." % [
			wet_radius_channel, "" if wet_radius_channel == 1 else "s", roundi(farm_wet_fraction * 100.0),
			roundi((farm_wet_bonus - 1.0) * 100.0)]
