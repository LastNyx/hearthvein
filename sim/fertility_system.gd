class_name FertilitySystem
extends SimSystem
## Soil fertility (design.md section 9). Every tile carries fertility 0-100 in MapState.fertility (start values
## come from TerrainDef.fertility_start via MapGen). A Farm (BuildingDef.fertility_output) produces
## x (mean footprint fertility / 100), times its fertile-origin bonus when the tile under the origin started as
## fertile soil. A blighted tile's fertility counts at SoilDef.blight_factor (half) in that mean.
##
## Once per season (ticket 20b, design.md section 3) the soil drifts: every footprint tile of a working Farm loses
## SoilDef.wear_per_season, and every other tile regains SoilDef.recovery_per_season up to the fertility its terrain
## started with. "Working" = the Farm is finished, not paused, and at least one citizen holds a work job there at the
## season hook (jobs are persistent, so that is its staffing at the end of the season that just ended). A staffed
## Terraced Farm (tier III) neither wears nor recovers. All numbers come from data/soil/soil.tres.

const SAVE_KEY := "fertility"
## Quarter points the 0-100 byte cannot hold, per tile (tile index -> 0..3). Sparse: only tiles on a farmed
## footprint that went through a season ever have one (a fallow season gains 2.5 points).
const QUARTERS := 4

var _extra: Dictionary = {}


## The fractional quarter points are real state: a save at 52.5 fertility must resume at 52.5, not 52.
func save_state() -> Dictionary:
	return {"extra": SaveGame.pairs(_extra)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_extra = SaveGame.unpairs(d["extra"]) if d.has("extra") else {}


## ProductionSystem modifier: (Settlement, Building) -> float. 1.0 for everything that is not a farm, so it is safe
## to append to ProductionSystem.modifiers for every producer. A farm that is at least half wet (WaterSystem) also
## gets the WaterDef.farm_wet_bonus here, so the wet and soil rules live in one factor.
static func output_modifier(s: Settlement, b: Building) -> float:
	if not b.def.fertility_output:
		return 1.0
	var sys := s.get_system(FertilitySystem) as FertilitySystem
	var mean := sys.mean_fertility(s, b) if sys != null else plain_mean_fertility(s, b)
	return mean * origin_bonus(s, b) * WaterSystem.wet_bonus(s, b)


## Fertility of one tile now, 0..100, including the quarter points kept outside the byte.
func fertility_at(s: Settlement, tile: Vector2i) -> float:
	var i := MapState.idx(tile.x, tile.y)
	return float(s.map.fertility[i]) + float(_extra.get(i, 0)) / float(QUARTERS)


## Mean fertility of the footprint's tiles as a 0..1 factor (a 2x2 Farm averages all four tiles, so one worn tile
## dilutes the whole farm). A blighted tile counts at SoilDef.blight_factor.
func mean_fertility(s: Settlement, b: Building) -> float:
	var tiles := b.tiles()
	if tiles.is_empty() or b.layer != Building.LAYER_GROUND:
		return 0.0  # skystone has no soil (ticket 40)
	var blight := blight_factor(s.registry)
	var sum := 0.0
	for t in tiles:
		var f := fertility_at(s, t)
		if s.map.is_blighted(t.x, t.y):
			f *= blight
		sum += f
	return sum / (100.0 * float(tiles.size()))


## The same mean from the byte grid alone, for a settlement with no FertilitySystem registered (fixtures).
static func plain_mean_fertility(s: Settlement, b: Building) -> float:
	var tiles := b.tiles()
	if tiles.is_empty():
		return 0.0
	var sum := 0.0
	var m := s.map_for_layer(b.layer)
	for t in tiles:
		sum += float(m.get_fertility(t.x, t.y))
	return sum / (100.0 * float(tiles.size()))


## A blighted tile's output factor (half by default data); 1.0 when the registry has no soil definition.
static func blight_factor(reg: DataRegistry) -> float:
	return reg.soil.blight_factor if reg.soil != null else 1.0


## The terrain's starting fertility, 0..1. "Started as fertile soil" is read from the terrain still on the origin
## tile: farming lowers the fertility number, never the terrain.
static func start_fertility(reg: DataRegistry, map: MapState, tile: Vector2i) -> float:
	var tdef := reg.get_terrain(map.terrain_id_at(tile.x, tile.y))
	return tdef.fertility_start if tdef != null else 0.0


## Fertile-origin bonus of a building: its def's multiplier when the terrain under the origin started fully
## fertile (fertility_start == 1.0, i.e. fertile soil), otherwise 1.0.
static func origin_bonus(s: Settlement, b: Building) -> float:
	return b.def.fertile_origin_bonus if start_fertility(s.registry, s.map, b.origin) >= 1.0 else 1.0


## True when the building's current tier carries the Terraced Farm rule (no seasonal fertility loss).
static func tier_stops_loss(b: Building) -> bool:
	var i := b.tier - 2  # tiers[0] is tier II
	return i >= 0 and i < b.def.tiers.size() and b.def.tiers[i].stops_fertility_loss


## The seasonal soil drift (design.md section 3: soil changes once per season). The 12k-tile pass is cut into row bands
## (ticket 89b): a frame step queues them behind the other season hooks (Settlement.defer_work, so they run one or two per
## frame with the clock held and before the autosave takes its snapshot), a coarse step or a direct call does them all now.
## Tiles do not depend on each other, so the result is the same whichever way it runs.
func on_season(s: Settlement) -> void:
	var soil := s.registry.soil
	if soil == null:
		return
	var farms := _farms_this_season(s)
	var worked: Dictionary = farms["worked"]   # footprint tile -> true, under a working Farm
	var wearing: Dictionary = farms["wearing"]  # footprint tile -> true, under a working Farm that loses fertility
	var starts := _start_points(s)
	for y0 in range(0, MapState.HEIGHT, SEASON_BAND_ROWS):
		var y1 := mini(y0 + SEASON_BAND_ROWS, MapState.HEIGHT)
		var band := func() -> void: _drift_rows(s, soil, worked, wearing, starts, y0, y1)
		if s.is_spreading():
			s.defer_work(band)
		else:
			band.call()


## Map rows per drift band: 12 rows is 1536 tiles, about half a millisecond.
const SEASON_BAND_ROWS := 12


## The drift of the tiles in rows y0 up to y1.
func _drift_rows(s: Settlement, soil: SoilDef, worked: Dictionary, wearing: Dictionary, starts: PackedFloat32Array,
		y0: int, y1: int) -> void:
	var lo := y0 * MapState.WIDTH
	var hi := y1 * MapState.WIDTH
	for i: int in worked:  # tiles under a working Farm: wear (or hold, for a staffed Terraced Farm)
		if i < lo or i >= hi or not wearing.has(i):
			continue
		var now := float(s.map.fertility[i]) + float(_extra.get(i, 0)) / float(QUARTERS)
		var after := maxf(0.0, now - soil.wear_per_season)
		if not is_equal_approx(after, now):
			_write_points(s.map, i, after)
	var fert := s.map.fertility
	var terr := s.map.terrain
	for i in range(lo, hi):  # every other tile regains fertility up to its terrain's start
		var st := starts[terr[i]]
		if fert[i] >= st or worked.has(i):  # whole points at or above the start: nothing to regain (st is a whole number)
			continue
		var now := float(fert[i]) + float(_extra.get(i, 0)) / float(QUARTERS)
		var after := minf(st, now + soil.recovery_per_season)
		if not is_equal_approx(after, now):
			_write_points(s.map, i, after)


## {worked: {tile -> true}, wearing: {tile -> true}} for the season that just ended.
func _farms_this_season(s: Settlement) -> Dictionary:
	var staffed := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id >= 0 and c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = true
	var worked := {}
	var wearing := {}
	for bid in staffed:
		var b: Building = s.buildings.get(bid)
		if b == null or not b.def.fertility_output or b.paused or b.site:
			continue
		var stops := tier_stops_loss(b)
		for t in b.tiles():
			var i := MapState.idx(t.x, t.y)
			worked[i] = true
			if not stops:
				wearing[i] = true
	return {"worked": worked, "wearing": wearing}


## Starting fertility in points (0-100) per terrain byte, in MapState.terrain_ids order. Same rounding as MapGen.
static func _start_points(s: Settlement) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(s.map.terrain_ids.size())
	for i in s.map.terrain_ids.size():
		var tdef := s.registry.get_terrain(s.map.terrain_ids[i])
		out[i] = float(roundi(tdef.fertility_start * 100.0)) if tdef != null else 0.0
	return out


## Silt a drained spring flood leaves on a tile (ticket 154): `points` fertility more, up to 100. The quarter points
## survive when a FertilitySystem is registered (a plain byte write otherwise).
static func add_silt(s: Settlement, tile: Vector2i, points: float) -> void:
	if points <= 0.0 or not MapState.in_bounds(tile.x, tile.y):
		return
	var i := MapState.idx(tile.x, tile.y)
	var sys := s.get_system(FertilitySystem) as FertilitySystem
	var now := sys.fertility_at(s, tile) if sys != null else float(s.map.get_fertility(tile.x, tile.y))
	var after := minf(100.0, now + points)
	if sys != null:
		sys.set_points(s.map, i, after)
	else:
		s.map.set_fertility(tile.x, tile.y, roundi(after))


## Set one tile's fertility to an exact point value, quarter points included (the Verdant Spring writes 100).
func set_points(map: MapState, i: int, v: float) -> void:
	_write_points(map, i, v)


## Split an exact point value back into the byte and its quarter points (0..3).
func _write_points(map: MapState, i: int, v: float) -> void:
	var whole := int(v)
	var q := int(roundf((v - float(whole)) * float(QUARTERS)))
	if q >= QUARTERS:
		whole += 1
		q = 0
	map.fertility[i] = clampi(whole, 0, 100)
	if q == 0:
		_extra.erase(i)
	else:
		_extra[i] = q
