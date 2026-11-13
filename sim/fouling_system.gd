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
## Also the fouled-water production modifiers (ticket 29c): the Fishing Dock x0.5 on fouled shore water and a farm
## whose wetness comes only from fouled water x0.75 (see output_modifier and wet_only_from_fouled).

const SAVE_KEY := "fouling"

## River tile flat indices (MapState.river_flow != 0). Built on the first pass; a pure cache of the map.
var _tiles: Array[int] = []
## Flat index -> hours since a live source last fed it, for every fouled tile. 0 = fed this hour.
var _fouled: Dictionary = {}

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
	var sources := _sources(s)
	var supplied := _supplied(s, sources, maxi(1, def.foul_spread_tiles_per_hour))
	var clear_hours := maxi(0, def.foul_clear_hours)
	var next := {}
	for i: int in _fouled:
		if supplied.has(i):
			next[i] = 0
			continue
		var age: int = int(_fouled[i]) + 1
		if age < clear_hours:
			next[i] = age
	for i: int in supplied:
		if not next.has(i):
			next[i] = 0
	# Push the difference into the map through the command, so foul_version moves and views hear about it.
	for i: int in _fouled:
		if not next.has(i):
			s.set_fouled(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH), false)
	for i: int in next:
		if not _fouled.has(i):
			s.set_fouled(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH), true)
	_fouled = next


## Flat indices of every river tile, low to high.
func _build_tiles(s: Settlement) -> void:
	_tiles.clear()
	var n := MapState.WIDTH * MapState.HEIGHT
	for i in n:
		if s.map.river_flow[i] != 0:
			_tiles.append(i)


## River tiles 4-adjacent to a blighted tile: this hour's sources.
func _sources(s: Settlement) -> Array[int]:
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


## Flat index of the river tile this tile flows into, -1 when the flow leaves the map or hits a non-river tile.
func _downstream(s: Settlement, i: int) -> int:
	var x := i % MapState.WIDTH
	var y := i / MapState.WIDTH
	var n: Vector2i = s.map.downstream(x, y)
	if not MapState.in_bounds(n.x, n.y):
		return -1
	var j := MapState.idx(n.x, n.y)
	return j if s.map.river_flow[j] != 0 else -1
