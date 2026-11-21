class_name FloodSystem
extends SimSystem
## Spring floods and the Levee (spec N10, ticket 154).
##
## Each spring, on a day picked from the map seed and the year, the river floods the low land beside it for
## WaterDef.flood_days days: ground tiles up to WaterDef.flood_radius 4-connected steps from a river tile. Raised
## ground (rock, skystone) and water do not flood, and a finished Levee (BuildingDef.levee) is a wall the flood cannot
## pass, so the land behind a continuous run of levees stays dry. Buildings standing on a flooded tile stop
## (ProductionSystem halts them with "flooded") and walkers avoid the water. When the flood drains each tile gains
## WaterDef.flood_silt_fertility soil (the silt), marked until the next spring.
##
## The day is deterministic: flood_start_day(seed, year). Nothing else about the schedule is stored; the running
## flood (the active mask, its start day and the silt) is saved so a load mid-flood resumes exactly.

const SAVE_KEY := "flood"
## ProductionSystem halt reason while a building stands on flood water.
const HALT := "flooded"

## Flooded ground tiles, 1 per tile (y * MapState.WIDTH + x), while a flood runs; all 0 otherwise.
var flooded := PackedByteArray()
## Tiles the last drained flood silted, 1 per tile; cleared when the next spring flood starts.
var silt := PackedByteArray()
## True between the flood's first and last day.
var active: bool = false
## Absolute day (GameClock.total_days) the current or last flood began; -1 before the first one.
var start_day: int = -1


func _init() -> void:
	# Sized from the start (all dry, nothing silted), so a fresh game and a loaded one hold the same arrays.
	flooded.resize(MapState.WIDTH * MapState.HEIGHT)
	silt.resize(MapState.WIDTH * MapState.HEIGHT)


func on_day(s: Settlement) -> void:
	var water := s.registry.water
	if water == null or water.flood_days <= 0 or water.flood_radius <= 0:
		return
	var today := s.clock.total_days()
	if active:
		if today >= start_day + water.flood_days:
			_drain(s)
		return
	var start := flood_start_day(s, s.clock.year())
	if today == start:
		_begin(s, start, water)
	elif today == start - 1:
		s.events.emit("flood_forecast", {"start_day": start, "days": water.flood_days})


## Absolute day (GameClock.total_days) of the spring flood in `year`: after the first day, so there is always one day
## of warning, and early enough that the whole flood fits in spring. A pure function of the seed and the year.
func flood_start_day(s: Settlement, year: int) -> int:
	var water := s.registry.water
	var days := water.flood_days if water != null else 0
	var window := maxi(1, GameClock.DAYS_PER_SEASON - days - 2)
	var index := 2 + posmod(s.map.seed_used * 7919 + year * 104729, window)
	return (year - 1) * GameClock.DAYS_PER_YEAR + index


## True while the ground tile is under flood water.
func is_flooded(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y):
		return false
	var i := MapState.idx(tile.x, tile.y)
	return i < flooded.size() and flooded[i] != 0


## True when the tile carries the silt of the last drained flood.
func is_silted(tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y):
		return false
	var i := MapState.idx(tile.x, tile.y)
	return i < silt.size() and silt[i] != 0


## Every flooded ground tile now, in row-major order.
func flooded_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in flooded.size():
		if flooded[i] != 0:
			out.append(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH))
	return out


## True when any tile of the building's ground footprint is flooded. Sky buildings never flood.
static func flooded_at(s: Settlement, b: Building) -> bool:
	if b == null or b.layer != Building.LAYER_GROUND:
		return false
	var fs := s.get_system(FloodSystem) as FloodSystem
	if fs == null or not fs.active:
		return false
	for t in b.tiles():
		if fs.is_flooded(t):
			return true
	return false


## The flood mask of the map now: every land tile within WaterDef.flood_radius 4-connected steps of a river tile, with
## water, raised terrain and finished levees blocking the flow.
static func flood_mask(s: Settlement) -> PackedByteArray:
	var n := MapState.WIDTH * MapState.HEIGHT
	var out := PackedByteArray()
	out.resize(n)
	var water := s.registry.water
	if water == null or water.flood_radius <= 0:
		return out
	var blocked := levee_mask(s)
	var rock := s.map.terrain_index("rock")
	var skystone := s.map.terrain_index("skystone")
	var water_terrain := s.map.terrain_index("water")
	var dist := PackedByteArray()
	dist.resize(n)
	dist.fill(255)
	var frontier: Array[int] = []
	for i in n:
		if s.map.river_flow[i] != MapState.FLOW_NONE:
			dist[i] = 0
			frontier.append(i)
	var step := 0
	while step < water.flood_radius and not frontier.is_empty():
		step += 1
		var next: Array[int] = []
		for i in frontier:
			var x := i % MapState.WIDTH
			var y := i / MapState.WIDTH
			for d in Placement.DIRS:
				var nx := x + d.x
				var ny := y + d.y
				if not MapState.in_bounds(nx, ny):
					continue
				var j := MapState.idx(nx, ny)
				if dist[j] <= step:
					continue
				var tid := s.map.terrain[j]
				if tid == water_terrain or tid == rock or tid == skystone or blocked[j] != 0:
					dist[j] = step
					continue
				dist[j] = step
				out[j] = 1
				next.append(j)
		frontier = next
	return out


## 1 on every tile under a finished Levee, 0 elsewhere.
static func levee_mask(s: Settlement) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(MapState.WIDTH * MapState.HEIGHT)
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if not b.def.levee or b.site or b.layer != Building.LAYER_GROUND:
			continue
		for t in b.tiles():
			out[MapState.idx(t.x, t.y)] = 1
	return out


func _begin(s: Settlement, day: int, water: WaterDef) -> void:
	active = true
	start_day = day
	flooded = flood_mask(s)
	silt = PackedByteArray()
	silt.resize(MapState.WIDTH * MapState.HEIGHT)
	_apply_walkers(s)
	s.events.emit("flood_started", {"start_day": day, "days": water.flood_days})


func _drain(s: Settlement) -> void:
	var water := s.registry.water
	var points := water.flood_silt_fertility if water != null else 0.0
	for i in flooded.size():
		if flooded[i] == 0:
			continue
		silt[i] = 1
		if points > 0.0:
			FertilitySystem.add_silt(s, Vector2i(i % MapState.WIDTH, i / MapState.WIDTH), points)
	flooded = PackedByteArray()
	flooded.resize(MapState.WIDTH * MapState.HEIGHT)
	active = false
	_apply_walkers(s)
	s.events.emit("flood_ended", {"start_day": start_day})


## Tells WalkerSystem which tiles are under water so walkers plan around them.
func _apply_walkers(s: Settlement) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null:
		return
	var tiles := {}
	if active:
		for i in flooded.size():
			if flooded[i] != 0:
				tiles[Vector2i(i % MapState.WIDTH, i / MapState.WIDTH)] = true
	ws.set_flood_tiles(tiles)


func save_state() -> Dictionary:
	return {"active": active, "start_day": start_day, "flooded": flooded.duplicate(), "silt": silt.duplicate()}


func load_state(d: Dictionary, settlement: Settlement) -> void:
	active = bool(d.get("active", false))
	start_day = int(d.get("start_day", -1))
	flooded = d.get("flooded", PackedByteArray())
	silt = d.get("silt", PackedByteArray())
	var n := MapState.WIDTH * MapState.HEIGHT
	if flooded.size() != n:
		flooded = PackedByteArray()
		flooded.resize(n)
	if silt.size() != n:
		silt = PackedByteArray()
		silt.resize(n)
	_apply_walkers(settlement)
