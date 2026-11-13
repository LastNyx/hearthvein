class_name WaterSystem
extends SimSystem
## The wet/dry map (design.md section 9). Once a day every tile is marked wet or dry in MapState.wet: a tile is wet
## within WaterDef.wet_radius_water tiles (Chebyshev) of a water tile (river, lake or pond), or within
## WaterDef.wet_radius_channel tiles of a channel that flows. A channel flows when it is 4-connected to a water tile
## through other channels (BFS from the channels that touch water). Numbers come from data/water/water.tres.
##
## Wetness is derived state: recompute() rebuilds the grid from the terrain and Settlement.channels, so the only
## thing saved is map.wet itself (already part of MapState). Ticket 21b draws the grid; the farm wet bonus reads it
## through wet_bonus().
##
## The water-terrain part only changes when a tile turns into or out of water, so it is stamped once into a cached
## base mask keyed on MapState.water_version. A daily pass then copies that mask and stamps the flowing channels; a
## channel dug or removed redoes only the copy and the channel stamp. The base cache lives on this system, is not
## saved, and is rebuilt on the first pass after a load.

## Wet mask from water terrain alone (no channels). Rebuilt only when MapState.water_version moves.
var _base: PackedByteArray = PackedByteArray()
## MapState.water_version _base was stamped for; -1 means "not built yet" (a new system, e.g. after a load).
var _base_version: int = -1


func on_day(s: Settlement) -> void:
	recompute(s)


## Rebuilds MapState.wet for the whole map. Every water tile makes its Chebyshev square (radius
## wet_radius_water) wet; every flowing channel makes its smaller square (wet_radius_channel) wet.
static func recompute(s: Settlement) -> void:
	_system(s).recompute_wet(s)


## The registered system, so the base mask survives between calls. A settlement built without add_default_systems
## gets a throwaway one: still correct, just without the cache.
static func _system(s: Settlement) -> WaterSystem:
	var ws := s.get_system(WaterSystem) as WaterSystem
	return ws if ws != null else WaterSystem.new()


## Copies the cached water-terrain base and stamps every flowing channel on top, then stores it in MapState.wet.
func recompute_wet(s: Settlement) -> void:
	var def := s.registry.water
	if def == null:
		return
	_ensure_base(s, def)
	var wet := _base.duplicate()
	var rc := def.wet_radius_channel
	for i in flowing_tiles(s):
		_stamp(wet, i % MapState.WIDTH, i / MapState.WIDTH, rc)
	s.map.wet = wet


## Stamps the water-terrain squares into _base when water terrain changed since it was built (or never was).
func _ensure_base(s: Settlement, def: WaterDef) -> void:
	var version := s.map.water_version
	var n := MapState.WIDTH * MapState.HEIGHT
	if _base_version == version and _base.size() == n:
		return
	_base = PackedByteArray()
	_base.resize(n)  # zeros: dry unless stamped below
	var water := s.map.terrain_index("water")
	if water >= 0:
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if s.map.get_terrain(x, y) == water:
					_stamp(_base, x, y, def.wet_radius_water)
	_base_version = version


## Writes 1 into the Chebyshev square of `radius` around (x, y), clipped to the map. Packed arrays are passed by
## reference, so the caller's buffer is the one that changes.
static func _stamp(wet: PackedByteArray, x: int, y: int, radius: int) -> void:
	var x0 := maxi(0, x - radius)
	var x1 := mini(MapState.WIDTH, x + radius + 1)
	for yy in range(maxi(0, y - radius), mini(MapState.HEIGHT, y + radius + 1)):
		var row := yy * MapState.WIDTH
		for xx in range(x0, x1):
			wet[row + xx] = 1


## 1 on every channel tile that is connected to a water tile through channels, 0 elsewhere (dry channels included).
## Seeded by the channels with a water tile as a 4-neighbour, then flooded through 4-connected channels.
static func flowing_channels(s: Settlement) -> PackedByteArray:
	var flow := PackedByteArray()
	flow.resize(MapState.WIDTH * MapState.HEIGHT)
	for i in flowing_tiles(s):
		flow[i] = 1
	return flow


## Flat indices of the flowing channel tiles, the same set flowing_channels() marks. Channels are found with the
## native PackedByteArray.find, then the flood only walks channel tiles.
static func flowing_tiles(s: Settlement) -> Array[int]:
	var out: Array[int] = []
	var water := s.map.terrain_index("water")
	if water < 0:
		return out
	var seen := PackedByteArray()
	seen.resize(MapState.WIDTH * MapState.HEIGHT)
	var i := s.channels.find(Settlement.CHANNEL_DUG)
	while i >= 0:
		var x := i % MapState.WIDTH
		var y := i / MapState.WIDTH
		for d in Placement.DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if MapState.in_bounds(nx, ny) and s.map.get_terrain(nx, ny) == water:
				seen[i] = 1
				out.append(i)
				break
		i = s.channels.find(Settlement.CHANNEL_DUG, i + 1)
	var head := 0
	while head < out.size():
		var j0 := out[head]
		head += 1
		var x := j0 % MapState.WIDTH
		var y := j0 / MapState.WIDTH
		for d in Placement.DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if not MapState.in_bounds(nx, ny):
				continue
			var j := MapState.idx(nx, ny)
			if s.channels[j] != Settlement.CHANNEL_NONE and seen[j] == 0:
				seen[j] = 1
				out.append(j)
	return out


## A Farm's wet multiplier. A plain farm gets WaterDef.farm_wet_bonus when at least farm_wet_fraction of its
## footprint is wet (design.md section 9). A tier with needs_wet (the Irrigated Farm, design.md section 10) instead
## gets that tier's wet_bonus when wet -- the irrigation x1.5 replaces the plain x1.25, they do not stack -- and 0
## when dry: it only works on wet ground. 1.0 for every building that is not a Farm (so callers may apply it to any
## producer).
static func wet_bonus(s: Settlement, b: Building) -> float:
	var def := s.registry.water
	if def == null or not b.def.fertility_output:
		return 1.0
	var wet := footprint_wet(s, b)
	var td := b.tier_def(s.registry)
	if td != null and td.needs_wet:
		return td.wet_bonus if wet else 0.0
	return def.farm_wet_bonus if wet else 1.0


## True when at least WaterDef.farm_wet_fraction of the building's footprint is wet (design.md: half). The one wet
## test the farm rules use: the plain wet bonus, the Irrigated Farm and its upgrade check.
static func footprint_wet(s: Settlement, b: Building) -> bool:
	var def := s.registry.water
	if def == null:
		return false
	var tiles := b.tiles()
	if tiles.is_empty():
		return false
	var n := 0
	for t in tiles:
		if s.map.is_wet(t.x, t.y):
			n += 1
	return float(n) >= def.farm_wet_fraction * float(tiles.size())


## True when the building's current tier only works on wet ground (the Irrigated Farm, design.md section 10).
static func needs_wet(s: Settlement, b: Building) -> bool:
	var td := b.tier_def(s.registry)
	return td != null and td.needs_wet


## ProductionSystem halt reason for a building that cannot work on dry ground: "dry" for an Irrigated Farm (a
## needs_wet tier) whose footprint is not half wet, otherwise "".
static func dry_halt(s: Settlement, b: Building) -> String:
	if s.registry.water == null or not b.def.fertility_output or not needs_wet(s, b):
		return ""
	return "" if footprint_wet(s, b) else "dry"
