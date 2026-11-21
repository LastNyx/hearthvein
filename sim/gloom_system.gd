class_name GloomSystem
extends SimSystem
## Gloom (ticket 149, spec N8): in a Dimming night, gloom starts on the forest tiles and creeps one tile an hour
## (LogisticsDef.gloom_spread_per_hour) over unlit, non-water land. Lit means a fuelled lamp or a Night Watch route
## (Settlement.is_tile_lit, ticket 133; the glow river of ticket 151 joins the same rule later). Gloom never enters a
## lit tile, and a tile that lights is cleared on the next hour. All gloom clears at dawn (LogisticsDef.lamp_light_end)
## and whenever no Dimming is running.
##
## State: tiles maps Vector2i -> depth, 0 for a forest tile and one more per hour of creep. The frontier is the set of
## tiles at the deepest depth only, so a spread hour costs the front, never a scan of the map (the map is scanned once
## a night, when the forest is seeded). Tiles are visited in sorted order: no RNG, the same map gives the same gloom.
##
## A building with any footprint tile in gloom stops (ProductionSystem sets its halt to "gloom"); walkers take gloom
## tiles at a higher path cost (WalkerSystem.set_gloom_tiles), so they go around when a detour is short.

const SAVE_KEY := "gloom"
## The four orthogonal neighbours the creep follows (4-neighbour, as the mockup draws it).
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Tile -> depth (0 = a forest tile, 1 the first ring, ...). Runtime state, saved.
var tiles: Dictionary = {}

## Tiles of the deepest ring, sorted. Rebuilt when the set changes, never saved.
var _frontier: Array[Vector2i] = []
var _depth: int = -1
## Night identity seen at the last seed (Settlement.moon_days): a night without forest does not rescan the map hourly.
var _seeded_night: int = -1
## Settlement.light_version at the last lit-tile sweep (lamps only move then).
var _light_seen: int = -1
## Bumps whenever the tile set changes; the render and the walker weights read it.
var _version: int = 0
var _pushed_version: int = -1


func save_state() -> Dictionary:
	var keys: Array = tiles.keys()
	keys.sort()
	var out: Array = []
	for t: Vector2i in keys:
		out.append([t.x, t.y, int(tiles[t])])
	return {"tiles": out}


func load_state(d: Dictionary, settlement: Settlement) -> void:
	tiles.clear()
	for e in d.get("tiles", []):
		tiles[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	_rebuild_frontier()
	_light_seen = settlement.light_version if settlement != null else -1
	_seeded_night = -1  # an empty loaded night reseeds on its next hour; a loaded set is already there
	_version += 1
	# The walker weights follow on the next hour: WalkerSystem may not be loaded yet here (system load order).


## True when `tile` is covered by gloom right now.
static func is_gloom(s: Settlement, tile: Vector2i) -> bool:
	var g := s.get_system(GloomSystem) as GloomSystem
	return g != null and g.tiles.has(tile)


## True when any of `b`'s footprint tiles is gloom: the building stops.
static func building_in_gloom(s: Settlement, b: Building) -> bool:
	var g := s.get_system(GloomSystem) as GloomSystem
	if g == null or g.tiles.is_empty() or b == null:
		return false
	for t in b.tiles():
		if g.tiles.has(t):
			return true
	return false


## Deepest gloom ring (-1 when there is no gloom). The render draws this front ragged.
func max_depth() -> int:
	return _depth


## Bumps whenever the tile set changes (a render cache key).
func version() -> int:
	return _version


func on_hour(s: Settlement) -> void:
	if not DimmingSystem.is_active(s) or not s.is_lamp_hour():
		if not tiles.is_empty():
			_clear_all(s)
		_light_seen = s.light_version
		return
	if tiles.is_empty():
		if _seeded_night != s.moon_days():
			_seed(s)
	else:
		_clear_lit(s)
	_spread(s)
	_push_walkers(s)


## Seeds every forest-edge tile (a forest tile beside non-forest land) that is not lit, at depth 0. Runs once a night;
## the map scan is the only full scan. Forest interiors stay out: nothing could stand or walk there, and the trees are
## already dark; gloom only matters where it reaches land.
func _seed(s: Settlement) -> void:
	_seeded_night = s.moon_days()
	var forest := s.map.terrain_index("forest")
	var lit := _lit(s)
	var found := {}
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.get_terrain(x, y) != forest:
				continue
			var t := Vector2i(x, y)
			if not _forest_edge(s, t, forest):
				continue
			if lit.has(t):
				continue
			found[t] = 0
	if found.is_empty():
		return
	tiles = found
	_rebuild_frontier()
	_version += 1


static func _forest_edge(s: Settlement, t: Vector2i, forest: int) -> bool:
	for o: Vector2i in NEIGHBOURS:
		var n := t + o
		if MapState.in_bounds(n.x, n.y) and s.map.get_terrain(n.x, n.y) != forest:
			return true
	return false


## The lit-tile set tonight (a LightingSystem is always registered beside this one), read once per spread step.
func _lit(s: Settlement) -> Dictionary:
	var ls := s.get_system(LightingSystem) as LightingSystem
	return ls.lit_tiles(s) if ls != null else {}


## Spreads the front `gloom_spread_per_hour` rings (data; 1 by default). Only the front's 4-neighbours are looked at.
func _spread(s: Settlement) -> void:
	var per := 1
	var lg := s.registry.logistics if s.registry != null else null
	if lg != null:
		per = maxi(1, lg.gloom_spread_per_hour)
	for i in per:
		if _frontier.is_empty():
			return
		_spread_step(s)


func _spread_step(s: Settlement) -> void:
	var next: Array[Vector2i] = []
	var seen := {}
	var nd := _depth + 1
	var water := s.map.terrain_index("water")
	var lit := _lit(s)
	for t: Vector2i in _frontier:
		for o: Vector2i in NEIGHBOURS:
			var n := t + o
			if tiles.has(n) or seen.has(n):
				continue
			if not MapState.in_bounds(n.x, n.y):
				continue
			if s.map.get_terrain(n.x, n.y) == water:
				continue
			if lit.has(n):
				continue
			seen[n] = true
			next.append(n)
	if next.is_empty():
		return
	next.sort()
	for n in next:
		tiles[n] = nd
	_frontier = next
	_depth = nd
	_version += 1


## Drops every gloom tile that is lit now. Runs only when a lamp lit or went dark (light_version moved), so a night
## without light changes costs nothing here.
func _clear_lit(s: Settlement) -> void:
	if s.light_version == _light_seen:
		return
	_light_seen = s.light_version
	var keep := {}
	for t: Vector2i in tiles:
		if not s.is_tile_lit(t):
			keep[t] = tiles[t]
	if keep.size() == tiles.size():
		return
	tiles = keep
	_rebuild_frontier()
	_version += 1


func _clear_all(s: Settlement) -> void:
	tiles.clear()
	_frontier.clear()
	_depth = -1
	_version += 1
	_push_walkers(s)


## Recomputes the deepest ring from the tile set (after a load or a lit-tile clear).
func _rebuild_frontier() -> void:
	_frontier.clear()
	_depth = -1
	for t: Vector2i in tiles:
		var d := int(tiles[t])
		if d > _depth:
			_depth = d
			_frontier = [t]
		elif d == _depth:
			_frontier.append(t)
	_frontier.sort()


## Hands the current set to WalkerSystem so paths prefer routes around it.
func _push_walkers(s: Settlement) -> void:
	if s == null or _version == _pushed_version:
		return
	_pushed_version = _version
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws != null:
		ws.set_gloom_tiles(tiles)
