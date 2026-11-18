class_name FoulingSystem
extends SimSystem
## River fouling (design.md section 9, D42). Blight next to the river fouls it downstream: every river tile 4-adjacent
## to a blighted tile is a source, and each hour the fouling front advances
## WaterDef.foul_spread_tiles_per_hour river tiles downstream, following MapState.river_flow, until the map edge.
## Clean inflow is not modelled: the only thing that stops a front is losing its source (or the map edge).
##
## Clearing: a fouled tile that no live source feeds any more counts down; after WaterDef.foul_clear_hours hours
## (design.md: 2 days) it turns clean again. Every tile of a stretch loses its feed at the same hour, so a stretch
## that was following one blight clears together.
##
## Only river tiles are walked: the flat index list is built once (the river shape never changes in play) and every
## hourly pass visits those tiles and nothing else. Tile flags live in MapState.fouled; the per-tile countdown is
## this system's state (SAVE_KEY "fouling"), so a save mid-spread resumes exactly.
##
## Also the fouled-water production modifiers (ticket 29c): the Fishing Dock x0.5 on fouled shore water and an
## Irrigated Farm whose wetness comes only from fouled water x0.75 (see output_modifier and wet_only_from_fouled).

const SAVE_KEY := "fouling"

## River tile flat indices (MapState.river_flow != 0). Built on the first pass; a pure cache of the map.
var _tiles: Array[int] = []
## Flat index -> hours since a live source last fed it, for every fouled tile. 0 = fed this hour.
var _fouled: Dictionary = {}
## Clearwater Works candidates (buildings with stops_fouling), rebuilt when the structure changes. The hourly pass only
## asks each of these whether it works, so it never scans every building.
var _works: Array[Building] = []
var _works_version: int = -1
## Flat index -> true for the river tiles under a working Clearwater Works this hour: fouling does not flow on from them.
var _stops: Dictionary = {}
## River tiles beside blight, kept per MapState.blight_version (the blight changes a few times a day, the pass runs hourly).
var _sources_cache: Array[int] = []
var _sources_version: int = -1
## Set when a pass changed nothing and every fouled tile was fed: the next pass would change nothing either until the
## blight, the fouling flags or the working Clearwater Works change (ticket 89b: the pass took 1.3 ms every hour).
var _steady_key := ""

## Cache of "wet only from fouled water" per tile (ticket 29c), rebuilt when the map, channels or fouling change.
var _only_foul := PackedByteArray()
var _mask_water_version: int = -1
var _mask_foul_version: int = -1
var _mask_structure_version: int = -1


func save_state() -> Dictionary:
	return {"fouled": SaveGame.pairs(_fouled)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_fouled = SaveGame.unpairs(d["fouled"])
	_mask_water_version = -1  # masks are caches: rebuild from the loaded map and state
	_mask_foul_version = -1
	_mask_structure_version = -1


func on_hour(s: Settlement) -> void:
	var def := s.registry.water
	if def == null:
		return
	# Nothing blighted and nothing fouled: no source can appear and no countdown can move. One native scan of the
	# blight bytes is cheaper than walking the river.
	if _fouled.is_empty() and s.map.blight.count(1) == 0:
		return
	if _tiles.is_empty():
		_build_tiles(s)
	_refresh_stops(s)
	var key := "%d:%d:%d" % [s.map.blight_version, s.map.foul_version, _stops.hash()]
	if key == _steady_key:
		return
	_steady_key = ""
	var sources := _sources(s)
	var supplied := _supplied(s, sources, maxi(1, def.foul_spread_tiles_per_hour))
	var clear_hours := maxi(0, def.foul_clear_hours)
	var next := {}
	var steady := true
	for i: int in _fouled:
		if supplied.has(i):
			next[i] = 0
			steady = steady and int(_fouled[i]) == 0
			continue
		steady = false
		var age: int = int(_fouled[i]) + 1
		if age < clear_hours:
			next[i] = age
	for i: int in supplied:
		if not next.has(i):
			next[i] = 0
			steady = false
	# Push the difference into the map through the command, so foul_version moves and views hear about it.
	for i: int in _fouled:
		if not next.has(i):
			s.set_fouled(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH), false)
	for i: int in next:
		if not _fouled.has(i):
			s.set_fouled(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH), true)
	_fouled = next
	if steady:
		_steady_key = "%d:%d:%d" % [s.map.blight_version, s.map.foul_version, _stops.hash()]


## Flat indices of every river tile, low to high.
func _build_tiles(s: Settlement) -> void:
	_tiles.clear()
	var n := MapState.WIDTH * MapState.HEIGHT
	for i in n:
		if s.map.river_flow[i] != 0:
			_tiles.append(i)


## River tiles 4-adjacent to a blighted tile: this hour's sources.
func _sources(s: Settlement) -> Array[int]:
	if _sources_version == s.map.blight_version:
		return _sources_cache
	_sources_version = s.map.blight_version
	var out: Array[int] = []
	for i in _tiles:
		var x := i % MapState.WIDTH
		var y := i / MapState.WIDTH
		for d in Placement.DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if MapState.in_bounds(nx, ny) and s.map.is_blighted(nx, ny):
				out.append(i)
				break
	_sources_cache = out
	return out


## Tiles fouled this hour: every source, every still-fed fouled tile, and `spread` steps of the front downstream.
## A stretch only stays fed while a live source can be reached through the already fouled tiles upstream of it, so
## when the blight goes the whole stretch starts its countdown instead of spreading on forever.
func _supplied(s: Settlement, sources: Array[int], spread: int) -> Dictionary:
	var fed := {}
	var active := {}
	var queue: Array[int] = []
	for i in sources:
		fed[i] = true
		if _fouled.has(i) and not active.has(i):
			active[i] = true
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var n := _downstream(s, i)
		if n >= 0 and _fouled.has(n) and not active.has(n):
			active[n] = true
			queue.append(n)
	var frontier: Array[int] = []
	for i: int in active:
		fed[i] = true
		frontier.append(i)  # a tile that only just became a source spreads from the next hour on
	for _step in spread:
		var added: Array[int] = []
		for i in frontier:
			var n := _downstream(s, i)
			if n >= 0 and not fed.has(n):
				fed[n] = true
				added.append(n)
		frontier = added
	return fed


## Rebuilds the stop tiles: the river tiles under every working stops_fouling building. The candidate list is cached per
## structure change; staffing and upkeep are read each hour for those few buildings only.
func _refresh_stops(s: Settlement) -> void:
	if _works_version != s.structure_version:
		_works_version = s.structure_version
		_works.clear()
		for id in s.buildings:
			var b: Building = s.buildings[id]
			if b.def.stops_fouling and b.layer == Building.LAYER_GROUND:
				_works.append(b)
	_stops.clear()
	if _works.is_empty():
		return
	var staffed := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = true
	for b in _works:
		if not PlanetHealthSystem.is_working(s, b, staffed):
			continue
		for t in b.tiles():
			if MapState.in_bounds(t.x, t.y) and s.map.is_river(t.x, t.y):
				_stops[MapState.idx(t.x, t.y)] = true


## Flat index of the river tile this tile flows into, -1 when the flow leaves the map, hits a non-river tile or leaves
## a tile under a working Clearwater Works.
func _downstream(s: Settlement, i: int) -> int:
	if _stops.has(i):
		return -1
	var x := i % MapState.WIDTH
	var y := i / MapState.WIDTH
	var n: Vector2i = s.map.downstream(x, y)
	if not MapState.in_bounds(n.x, n.y):
		return -1
	var j := MapState.idx(n.x, n.y)
	return j if s.map.river_flow[j] != 0 else -1


# ---------------------------------------------------------------- fouled water effects (ticket 29c)

## True when a tile's wetness comes only from fouled water: no clean water tile within WaterDef.wet_radius_water and
## no flowing channel within WaterDef.wet_radius_channel, but a fouled water tile within wet_radius_water.
static func wet_only_from_fouled(s: Settlement, tile: Vector2i) -> bool:
	if not MapState.in_bounds(tile.x, tile.y):
		return false  # test fixtures put buildings off the map; they stand on no water at all
	var fs := _system(s)
	fs._ensure_mask(s)
	return fs._only_foul[MapState.idx(tile.x, tile.y)] != 0


## True when a building's footprint has at least one 4-adjacent water tile, and one of those is fouled (the Fishing
## Dock's shore, design.md section 9).
static func shore_fouled(s: Settlement, b: Building) -> bool:
	var water := s.map.terrain_index("water")
	if water < 0:
		return false
	for t in b.tiles():
		for d in Placement.DIRS:
			var n := t + d
			if MapState.in_bounds(n.x, n.y) and s.map.get_terrain(n.x, n.y) == water and s.map.is_fouled(n.x, n.y):
				return true
	return false


## True when `b` is an Irrigated Farm (a tier whose def needs wet, design.md section 10) getting its wet bonus and
## every wet footprint tile is wet only from fouled water. A plain farm is not penalised (design.md section 9 names
## irrigated farms only), and a farm that has any clean water or a flowing channel watering it is not fouled.
static func farm_wet_only_fouled(s: Settlement, b: Building) -> bool:
	if not WaterSystem.needs_wet(s, b) or WaterSystem.wet_bonus(s, b) <= 1.0:
		return false
	var fs := _system(s)
	fs._ensure_mask(s)
	for t in b.tiles():
		if s.map.is_wet(t.x, t.y) and fs._only_foul[MapState.idx(t.x, t.y)] == 0:
			return false
	return true


## ProductionSystem modifier (design.md section 9): the Fishing Dock runs at WaterDef.foul_dock_output_factor when
## its shore water is fouled, an Irrigated Farm whose wetness comes only from fouled water at
## WaterDef.foul_farm_output_factor, and everything else at 1.0. Safe to append to ProductionSystem.modifiers for
## every producer.
static func output_modifier(s: Settlement, b: Building) -> float:
	var def := s.registry.water
	if def == null:
		return 1.0
	if b.def.placement_rule == "shore" and shore_fouled(s, b):
		return def.foul_dock_output_factor
	if farm_wet_only_fouled(s, b):
		return def.foul_farm_output_factor
	return 1.0


## The registered system, so the mask survives between calls. A settlement built without add_default_systems gets a
## throwaway one: still correct, just without the cache.
static func _system(s: Settlement) -> FoulingSystem:
	var fs := s.get_system(FoulingSystem) as FoulingSystem
	return fs if fs != null else FoulingSystem.new()


## Rebuilds the wet-only-from-fouled mask when the water terrain, the channels or the fouling changed. WaterSystem's
## flowing-channel query is the only expensive part, and this runs on the same infrequent events as its own passes.
func _ensure_mask(s: Settlement) -> void:
	if _mask_structure_version == s.structure_version and _mask_water_version == s.map.water_version \
			and _mask_foul_version == s.map.foul_version:
		return
	_mask_structure_version = s.structure_version
	_mask_water_version = s.map.water_version
	_mask_foul_version = s.map.foul_version
	var n := MapState.WIDTH * MapState.HEIGHT
	_only_foul = PackedByteArray()
	_only_foul.resize(n)
	var def := s.registry.water
	if def == null:
		return
	var clean := PackedByteArray()
	var foul := PackedByteArray()
	clean.resize(n)
	foul.resize(n)
	var water := s.map.terrain_index("water")
	if water >= 0:
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if s.map.get_terrain(x, y) != water:
					continue
				if s.map.is_fouled(x, y):
					_stamp(foul, x, y, def.wet_radius_water)
				else:
					_stamp(clean, x, y, def.wet_radius_water)
	for i in WaterSystem.flowing_tiles(s):
		_stamp(clean, i % MapState.WIDTH, i / MapState.WIDTH, def.wet_radius_channel)
	for i in n:
		_only_foul[i] = 1 if foul[i] != 0 and clean[i] == 0 else 0


## Writes 1 into the Chebyshev square around (x, y). Packed arrays are passed by reference, so the caller's buffer is
## the one that changes (same helper WaterSystem uses for its wet base).
static func _stamp(mask: PackedByteArray, x: int, y: int, radius: int) -> void:
	var x0 := maxi(0, x - radius)
	var x1 := mini(MapState.WIDTH, x + radius + 1)
	for yy in range(maxi(0, y - radius), mini(MapState.HEIGHT, y + radius + 1)):
		var row := yy * MapState.WIDTH
		for xx in range(x0, x1):
			mask[row + xx] = 1
