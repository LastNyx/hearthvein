class_name FertilitySystem
extends SimSystem
## Soil fertility (design.md section 9). Every tile carries fertility 0-100 in MapState.fertility (start values
## come from TerrainDef.fertility_start via MapGen). A Farm (BuildingDef.fertility_output) produces
## x (mean footprint fertility / 100), times its fertile-origin bonus when the tile under the origin started as
## fertile soil.
##
## Ticket 20b adds the yearly wear and fallow recovery in this system.

## ProductionSystem modifier: (Settlement, Building) -> float. 1.0 for everything that is not a farm, so it is safe
## to append to ProductionSystem.modifiers for every producer.
static func output_modifier(s: Settlement, b: Building) -> float:
	if not b.def.fertility_output:
		return 1.0
	return mean_fertility(s, b) * origin_bonus(s, b)


## Mean fertility of the footprint's tiles as a 0..1 factor (a 2x2 Farm averages all four tiles, so one worn tile
## dilutes the whole farm).
static func mean_fertility(s: Settlement, b: Building) -> float:
	var tiles := b.tiles()
	if tiles.is_empty():
		return 0.0
	var sum := 0.0
	for t in tiles:
		sum += float(s.map.get_fertility(t.x, t.y))
	return sum / (100.0 * float(tiles.size()))


## The terrain's starting fertility, 0..1. "Started as fertile soil" is read from the terrain still on the origin
## tile: farming lowers the fertility number, never the terrain.
static func start_fertility(reg: DataRegistry, map: MapState, tile: Vector2i) -> float:
	var tdef := reg.get_terrain(map.terrain_id_at(tile.x, tile.y))
	return tdef.fertility_start if tdef != null else 0.0


## Fertile-origin bonus of a building: its def's multiplier when the terrain under the origin started fully
## fertile (fertility_start == 1.0, i.e. fertile soil), otherwise 1.0.
static func origin_bonus(s: Settlement, b: Building) -> float:
	return b.def.fertile_origin_bonus if start_fertility(s.registry, s.map, b.origin) >= 1.0 else 1.0
