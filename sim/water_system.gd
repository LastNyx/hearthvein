class_name WaterSystem
extends SimSystem
## The wet/dry map (design.md section 9). Once a day every tile is marked wet or dry in MapState.wet: a tile is wet
## within WaterDef.wet_radius_water tiles (Chebyshev) of a water tile (river, lake or pond), or within
## WaterDef.wet_radius_channel tiles of a channel that flows. A channel flows when it is 4-connected to a water tile
## through other channels (BFS from the channels that touch water). Numbers come from data/water/water.tres.
##
## Wetness is derived state: recompute() rebuilds the whole grid from the terrain and Settlement.channels, so the
## only thing saved is map.wet itself (already part of MapState). Ticket 21b draws the grid; the farm wet bonus
## reads it through wet_bonus().

func on_day(s: Settlement) -> void:
	recompute(s)


## Rebuilds MapState.wet for the whole map. Every water tile makes its Chebyshev square (radius
## wet_radius_water) wet; every flowing channel makes its smaller square (wet_radius_channel) wet.
static func recompute(s: Settlement) -> void:
	var def := s.registry.water
	if def == null:
		return
	var map := s.map
	var water := map.terrain_index("water")
	var flow := flowing_channels(s)
	var rw := def.wet_radius_water
	var rc := def.wet_radius_channel
	var wet := PackedByteArray()
	wet.resize(MapState.WIDTH * MapState.HEIGHT)  # zeros: dry unless stamped below
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var radius := -1
			if water >= 0 and map.get_terrain(x, y) == water:
				radius = rw
			elif flow[MapState.idx(x, y)] != 0:
				radius = rc
			if radius < 0:
				continue
			for yy in range(maxi(0, y - radius), mini(MapState.HEIGHT, y + radius + 1)):
				var row := yy * MapState.WIDTH
				for xx in range(maxi(0, x - radius), mini(MapState.WIDTH, x + radius + 1)):
					wet[row + xx] = 1
	map.wet = wet


## 1 on every channel tile that is connected to a water tile through channels, 0 elsewhere (dry channels included).
## Seeded by the channels with a water tile as a 4-neighbour, then flooded through 4-connected channels.
static func flowing_channels(s: Settlement) -> PackedByteArray:
	var flow := PackedByteArray()
	flow.resize(MapState.WIDTH * MapState.HEIGHT)
	var water := s.map.terrain_index("water")
	if water < 0:
		return flow
	var queue: Array[int] = []
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var i := MapState.idx(x, y)
			if s.channels[i] == Settlement.CHANNEL_NONE:
				continue
			for d in Placement.DIRS:
				var nx := x + d.x
				var ny := y + d.y
				if MapState.in_bounds(nx, ny) and s.map.get_terrain(nx, ny) == water:
					flow[i] = 1
					queue.append(i)
					break
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % MapState.WIDTH
		var y := i / MapState.WIDTH
		for d in Placement.DIRS:
			var nx := x + d.x
			var ny := y + d.y
			if not MapState.in_bounds(nx, ny):
				continue
			var j := MapState.idx(nx, ny)
			if s.channels[j] != Settlement.CHANNEL_NONE and flow[j] == 0:
				flow[j] = 1
				queue.append(j)
	return flow


## A Farm's wet multiplier: WaterDef.farm_wet_bonus when at least farm_wet_fraction of its footprint is wet, else 1.0.
## 1.0 for every building that is not a Farm (so callers may apply it to any producer).
static func wet_bonus(s: Settlement, b: Building) -> float:
	var def := s.registry.water
	if def == null or not b.def.fertility_output:
		return 1.0
	var tiles := b.tiles()
	if tiles.is_empty():
		return 1.0
	var n := 0
	for t in tiles:
		if s.map.is_wet(t.x, t.y):
			n += 1
	if float(n) >= def.farm_wet_fraction * float(tiles.size()):
		return def.farm_wet_bonus
	return 1.0
