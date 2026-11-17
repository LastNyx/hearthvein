class_name RailSystem
extends SimSystem
## Cargo rail connectivity (design.md section 8 and 17 Conflux, ticket 37). Rail track is its own tile layer
## (Settlement.track). A finished Rail Depot (BuildingDef.rail_depot) touches a track tile when that tile is
## orthogonally next to its footprint. Two depots are linked when a 4-connected chain of track tiles touches both;
## links are transitive, so a rail network is a connected set of depots. Network id = lowest depot id in it.
##
## This is the connectivity query only. Moving goods along the rail is ticket 37b (manifests); haulers still cross
## regions on foot, so Building.connected is the only thing the rail widens (Settlement._recompute_connections calls
## extend_reach): a building road-connected to a depot counts as connected to everything road-connected to any depot
## on the same network.
##
## Everything here is a cache keyed on (structure_version, completion_version, building count): it rebuilds only when
## track, roads or buildings change, holds no runtime state and is left out of saves. Sites are not depots yet.

## depot id -> network id.
var _network_of: Dictionary = {}
## network id -> Array[int] depot ids, id-sorted.
var _networks: Dictionary = {}
## road tile -> road component id (4-connected road tiles).
var _road_comp: Dictionary = {}
## road component id -> Array[Vector2i].
var _comp_tiles: Dictionary = {}
## depot id -> Array[int] road component ids touching its footprint.
var _depot_comps: Dictionary = {}
var _key: Vector2i = Vector2i(-1, -1)
var _count: int = -1


## Every depot id (finished depots only), low to high.
func depot_ids(s: Settlement) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	for id: int in _network_of.keys():
		out.append(id)
	out.sort()
	return out


## Network ids (the lowest depot id of each), low to high.
func network_ids(s: Settlement) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	for n: int in _networks.keys():
		out.append(n)
	out.sort()
	return out


## Network id of a depot, or -1 when the building is not a finished depot.
func network_of(s: Settlement, depot_id: int) -> int:
	_ensure(s)
	return int(_network_of.get(depot_id, -1))


## Depot ids of a network, low to high. Empty for an unknown network.
func depots_of_network(s: Settlement, network_id: int) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	if _networks.has(network_id):
		out.assign(_networks[network_id])
	return out


## True when both are finished depots on the same network (a depot is linked to itself).
func linked(s: Settlement, depot_a: int, depot_b: int) -> bool:
	_ensure(s)
	return _network_of.has(depot_a) and _network_of.has(depot_b) and _network_of[depot_a] == _network_of[depot_b]


## True when building `a` is road-connected to a depot and building `b` is road-connected to a depot on the same
## network (possibly the same depot). A depot counts as road-connected to itself. This is the "connected via a depot"
## query for 37b manifests and the unconnected report; it does not say anything about walking.
func connected_via_rail(s: Settlement, a: int, b: int) -> bool:
	_ensure(s)
	var na := _networks_reaching(s, a)
	if na.is_empty():
		return false
	for n in _networks_reaching(s, b):
		if na.has(n):
			return true
	return false


## The depot ids a building is road-connected to (shares a road component with, or is itself), low to high.
func depots_reaching(s: Settlement, building_id: int) -> Array[int]:
	_ensure(s)
	var comps := _comps_of_building(s, building_id)
	var out: Array[int] = []
	for d: int in _network_of.keys():
		if d == building_id:
			out.append(d)
			continue
		for c: int in _depot_comps[d]:
			if comps.has(c):
				out.append(d)
				break
	out.sort()
	return out


## Used by Settlement._recompute_connections: adds to `reached` (road tile -> true, the roads linked to the Hearth) every
## road tile beside a depot of a network that has a depot beside an already reached road, repeated until nothing grows.
func extend_reach(s: Settlement, reached: Dictionary) -> void:
	_ensure(s)
	if _networks.is_empty():
		return
	var done := {}
	var grew := true
	while grew:
		grew = false
		for n: int in _networks.keys():
			if done.has(n):
				continue
			var touched := false
			for d: int in _networks[n]:
				for c: int in _depot_comps[d]:
					if reached.has((_comp_tiles[c] as Array)[0]):
						touched = true
						break
				if touched:
					break
			if not touched:
				continue
			done[n] = true
			grew = true
			for d: int in _networks[n]:
				for c: int in _depot_comps[d]:
					for t: Vector2i in _comp_tiles[c]:
						reached[t] = true


func _networks_reaching(s: Settlement, building_id: int) -> Dictionary:
	var out := {}
	for d in depots_reaching(s, building_id):
		out[_network_of[d]] = true
	return out


func _comps_of_building(s: Settlement, building_id: int) -> Dictionary:
	var out := {}
	var b: Building = s.buildings.get(building_id)
	if b == null:
		return out
	for t in s._ring(b):
		if _road_comp.has(t):
			out[_road_comp[t]] = true
	return out


func _ensure(s: Settlement) -> void:
	var key := Vector2i(s.structure_version, s.completion_version)
	if key == _key and _count == s.buildings.size():
		return
	_key = key
	_count = s.buildings.size()
	_rebuild(s)


func _rebuild(s: Settlement) -> void:
	_network_of.clear()
	_networks.clear()
	_road_comp.clear()
	_comp_tiles.clear()
	_depot_comps.clear()
	var ids: Array = s.buildings.keys()
	ids.sort()
	var depots: Array[Building] = []
	for id in ids:
		var b: Building = s.buildings[id]
		if not b.site and b.def.rail_depot:
			depots.append(b)
	if depots.is_empty():
		return
	# Road components (only needed to answer connection queries, but cheap: one flood of the road layer).
	var next_comp := 0
	for i in s.roads.size():
		if s.roads[i] == Settlement.ROAD_NONE:
			continue
		var t0 := Vector2i(i % MapState.WIDTH, i / MapState.WIDTH)
		if _road_comp.has(t0):
			continue
		var tiles: Array[Vector2i] = []
		_flood(t0, next_comp, tiles, func(t: Vector2i) -> bool: return s.road_at(t) != Settlement.ROAD_NONE, _road_comp)
		_comp_tiles[next_comp] = tiles
		next_comp += 1
	# Track components, flooded from the track tiles beside each depot.
	var track_comp := {}
	var n_track := 0
	var depot_tracks: Array = []  # per depot: Array of track component ids
	for b in depots:
		var comps: Array[int] = []
		for t in s._ring(b):
			if s.track_at(t) and not track_comp.has(t):
				var scratch: Array[Vector2i] = []
				_flood(t, n_track, scratch, func(p: Vector2i) -> bool: return s.track_at(p), track_comp)
				n_track += 1
			if track_comp.has(t) and not comps.has(track_comp[t]):
				comps.append(track_comp[t])
		depot_tracks.append(comps)
		var rc: Array[int] = []
		for t in s._ring(b):
			if _road_comp.has(t) and not rc.has(_road_comp[t]):
				rc.append(_road_comp[t])
		_depot_comps[b.id] = rc
	# Union-find over depots sharing a track component; the root is the lowest id (depots are in id order).
	var parent: Array[int] = []
	for i in depots.size():
		parent.append(i)
	var owner := {}  # track component -> first depot index
	for i in depots.size():
		for c: int in depot_tracks[i]:
			if owner.has(c):
				var a := _find(parent, int(owner[c]))
				var z := _find(parent, i)
				if a != z:
					parent[maxi(a, z)] = mini(a, z)
			else:
				owner[c] = i
	for i in depots.size():
		var net := depots[_find(parent, i)].id
		_network_of[depots[i].id] = net
		if not _networks.has(net):
			_networks[net] = []
		(_networks[net] as Array).append(depots[i].id)


## 4-connected flood from `start` over tiles where `ok` holds, labelling them in `label` and listing them in `out`.
static func _flood(start: Vector2i, id: int, out: Array[Vector2i], ok: Callable, label: Dictionary) -> void:
	label[start] = id
	out.append(start)
	var head := 0
	while head < out.size():
		var c := out[head]
		head += 1
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if not label.has(n) and MapState.in_bounds(n.x, n.y) and ok.call(n):
				label[n] = id
				out.append(n)


static func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
