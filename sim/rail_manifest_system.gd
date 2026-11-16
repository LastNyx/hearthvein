class_name RailManifestSystem
extends ManifestBase
## Cargo rail manifests (design.md section 8, ticket 37b). The player never edits a manifest: once a day, for every rail
## network (RailSystem), the staffed Rail Depots of its regions trade goods.
##
## Per region and good: stock = everything in the region's storages (the depot is a storage too), demand = a day's Lumen
## upkeep and recipe inputs of its finished buildings at their current staffing, plus food for the citizens homed there
## (all food goods count as one "food" demand). target = demand x LogisticsDef.manifest_cover_days; surplus = stock -
## target, need = target - stock. Needs are filled largest first from the linked depot with the largest surplus, each
## depot sending at most LogisticsDef.train_capacity units a day. A good nobody demands is never moved.
##
## A depot needs at least one hauler assigned to send or receive. Loading takes goods straight out of the source region's
## storages. The shipment is in transit for (track tiles of the shortest path) / LogisticsDef.train_speed hours, then
## lands in the destination depot; what does not fit goes to other storages of that region, and what still has no room
## stays in transit and retries every hour. A shipment whose depots are no longer linked waits; one whose depot is gone
## goes back to its source region when there is room (else it is lost). Haulers never leave their region for rail.

const SAVE_KEY := "rail_manifest"

## depot pair -> Array[Vector2i] track path (empty when no path). A cache, dropped when track or buildings change.
var _paths: Dictionary = {}
var _paths_version: Vector2i = Vector2i(-1, -1)

func save_state() -> Dictionary:
	return {"ships": _save_ships()}

func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_load_ships(d["ships"])
	_paths.clear()
	_paths_version = Vector2i(-1, -1)

## Trains in flight for the renderer: [{from_depot, to_depot, goods, depart_hour, arrive_hour, progress 0..1,
## path: Array[Vector2i]}]. The path
## runs from the track tile beside the from depot to the one beside the to depot; progress is the share of the trip
## done (1.0 while waiting to unload). The path is empty when the track is broken.
func shipments(s: Settlement) -> Array:
	var now := float(s.clock.total_hours) + s._hour_acc / GameClock.REAL_SECONDS_PER_HOUR
	var out := []
	for sh: Dictionary in _ships:
		var span := maxf(float(sh["arrive"]) - float(sh["depart"]), 0.000001)
		out.append({
			"from_depot": sh["from"], "to_depot": sh["to"], "goods": (sh["goods"] as Dictionary).duplicate(),
			"depart_hour": float(sh["depart"]), "arrive_hour": float(sh["arrive"]),
			"progress": clampf((now - float(sh["depart"])) / span, 0.0, 1.0),
			"path": _path(s, int(sh["from"]), int(sh["to"])),
		})
	return out

## Allocation-free reads for the train renderer (one call per shipment per frame): same numbers as shipments().
func ship_count() -> int:
	return _ships.size()

func ship_progress(s: Settlement, i: int) -> float:
	var sh: Dictionary = _ships[i]
	var now := float(s.clock.total_hours) + s._hour_acc / GameClock.REAL_SECONDS_PER_HOUR
	var span := maxf(float(sh["arrive"]) - float(sh["depart"]), 0.000001)
	return clampf((now - float(sh["depart"])) / span, 0.0, 1.0)

func ship_path(s: Settlement, i: int) -> Array[Vector2i]:
	var sh: Dictionary = _ships[i]
	return _path(s, int(sh["from"]), int(sh["to"]))

# ---------------------------------------------------------------- arrivals (hourly)

func on_hour(s: Settlement) -> void:
	var rail := s.get_system(RailSystem) as RailSystem
	_land_ships(s, func(from: int, to: int) -> bool: return rail.linked(s, from, to))

# ---------------------------------------------------------------- manifests (daily)

func on_day(s: Settlement) -> void:
	var lg := s.registry.logistics
	var rail := s.get_system(RailSystem) as RailSystem
	if lg == null or rail == null or lg.train_capacity <= 0.0:
		return
	var nets := rail.network_ids(s)
	if nets.is_empty():
		return
	var staffed := _staffed_depots(s, rail)
	if staffed.size() < 2:
		return
	var table := _region_table(s)
	var food_goods := GrowthSystem.food_goods(s.registry)
	var now := float(s.clock.total_hours)
	var sent := {}  # depot -> units sent today
	for net in nets:
		var depots: Array[int] = []
		for d in rail.depots_of_network(s, net):
			if staffed.has(d):
				depots.append(d)
		if depots.size() < 2:
			continue
		var keys := {}
		for d in depots:
			var region := _region(s, s.buildings[d])
			for k in table["demand"].get(region, {}):
				keys[k] = true
		var key_list: Array = keys.keys()
		key_list.sort()
		var pairs := {}  # Vector2i(from, to) -> goods
		for k: String in key_list:
			_plan_key(s, lg, table, depots, k, food_goods, sent, pairs, lg.train_capacity)
		_dispatch(s, pairs, now, func(from: int, to: int) -> float:
			var path := _path(s, from, to)
			return -1.0 if path.is_empty() else float(path.size()) / lg.train_speed)

func _staffed_depots(s: Settlement, rail: RailSystem) -> Dictionary:
	var out := {}
	for d in rail.depot_ids(s):
		out[d] = false
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_HAUL and out.has(c.job_id):
			out[c.job_id] = true
	for d in out.keys():
		if not out[d]:
			out.erase(d)
	return out

# ---------------------------------------------------------------- track paths

## Shortest track path between two depots: from a track tile beside `from` to one beside `to`, 4-connected over track.
## Empty when there is none. Cached per pair until track, roads or buildings change.
func _path(s: Settlement, from: int, to: int) -> Array[Vector2i]:
	var key := Vector2i(s.structure_version, s.completion_version)
	if key != _paths_version:
		_paths.clear()
		_paths_version = key
	var pk := Vector2i(from, to)
	if _paths.has(pk):
		return _paths[pk]
	var out: Array[Vector2i] = []
	var a: Building = s.buildings.get(from)
	var b: Building = s.buildings.get(to)
	if a != null and b != null:
		out = _bfs(s, a, b)
	_paths[pk] = out
	return out

func _bfs(s: Settlement, a: Building, b: Building) -> Array[Vector2i]:
	var goal := {}
	for t in s._ring(b):
		if s.track_at(t):
			goal[t] = true
	var parent := {}
	var queue: Array[Vector2i] = []
	for t in s._ring(a):
		if s.track_at(t) and not parent.has(t):
			parent[t] = t
			queue.append(t)
	var head := 0
	var hit := Vector2i(-1, -1)
	var found := false
	while head < queue.size():
		var c := queue[head]
		head += 1
		if goal.has(c):
			hit = c
			found = true
			break
		for d in Placement.DIRS:
			var n: Vector2i = c + d
			if not parent.has(n) and s.track_at(n):
				parent[n] = c
				queue.append(n)
	var out: Array[Vector2i] = []
	if not found:
		return out
	var c := hit
	while parent[c] != c:
		out.append(c)
		c = parent[c]
	out.append(c)
	out.reverse()
	return out
