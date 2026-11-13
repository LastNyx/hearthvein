class_name ForestSystem
extends SimSystem
## Forest regrowth and Forester planting (design.md section 9).
##
## Woodcutters turn forest into "stump" terrain. Every season a stump ages one step while planet health is at least
## ForestDef.regrow_min_health and the tile is not blighted; once it has ForestDef.regrow_seasons it turns back into
## forest. A stump within BuildingDef.placement_radius of a finished, unpaused Forester with a worker only needs
## ForestDef.forester_regrow_seasons (design: halved). A blighted or low-health stump does not age, so it does not
## regrow the season the blight is cleared or the health recovers. Stumps under a building, road or channel are left
## alone.
##
## A Forester (BuildingDef.plants_forest) plants ForestDef.plant_per_worker_day plain grass tiles per worker per day,
## nearest first (Euclidean within its placement_radius, ties lower y then lower x). Only plain grass is planted:
## never fertile soil, forest, rock or water, and never a tile with a building, road, channel or blight. A tree grows
## bigger than grass, so a planted or regrown tile goes through Settlement.set_terrain (render + woodcutters see it).
##
## All numbers are in data/forest/forest.tres. The old-forest region reward (ticket 25b) multiplies the seasons needed
## through `regrow_factors`: each Callable (settlement, tile) -> float, 0.5 = twice as fast.

const SAVE_KEY := "forest"

## Hooks that shorten or lengthen a stump's regrowth per tile, see the class comment.
var regrow_factors: Array[Callable] = []
## Tile index -> healthy, unblighted seasons the stump has stood. Absent means zero.
var _age: Dictionary = {}
## Forester building id -> forest tiles it has earned but not planted yet (whole tiles are planted at once).
var _plant_acc: Dictionary = {}


func save_state() -> Dictionary:
	return {"age": SaveGame.pairs(_age), "plant_acc": SaveGame.pairs(_plant_acc)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_age = SaveGame.unpairs(d["age"]) if d.has("age") else {}
	_plant_acc = SaveGame.unpairs(d["plant_acc"]) if d.has("plant_acc") else {}


## The daily Forester pass (design.md section 3: forest and soil change once a season, but a Forester plants every
## day). Only a scan over the Foresters and their r5 squares, never the whole map.
func on_day(s: Settlement) -> void:
	var def := s.registry.forest
	if def == null or def.plant_per_worker_day <= 0.0:
		return
	var workers := _workers(s)
	var live := {}
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or not b.def.plants_forest:
			continue
		var n: int = workers.get(bid, 0)
		if n <= 0:
			continue
		live[bid] = true
		var acc := float(_plant_acc.get(bid, 0.0)) + def.plant_per_worker_day * float(n)
		while acc >= 1.0:
			var t := plant_tile(s, b)
			if t.x < 0:
				acc = 0.0  # nothing plantable: drop the credit instead of bursting later
				break
			s.set_terrain(t, "forest")
			acc -= 1.0
		_plant_acc[bid] = acc
	for bid in _plant_acc.keys():
		if not live.has(bid):
			_plant_acc.erase(bid)


## The seasonal regrowth pass: age every tracked stump once, regrow the ones that are done.
func on_season(s: Settlement) -> void:
	var def := s.registry.forest
	if def == null:
		return
	var stump := s.map.terrain_index("stump")
	if stump < 0:
		return
	var healthy := s.planet_health() + 0.000001 >= def.regrow_min_health
	var foresters := _staffed_foresters(s)
	var next := {}
	for i in s.map.terrain.size():
		if s.map.terrain[i] != stump:
			continue
		# Something laid over the stump: leave its ground alone until it is cleared.
		if s.occupancy[i] >= 0 or s.roads[i] != Settlement.ROAD_NONE or s.channels[i] != Settlement.CHANNEL_NONE:
			continue
		var age := int(_age.get(i, 0))
		if healthy and s.map.blight[i] == 0:
			age += 1
			var tile := Vector2i(i % MapState.WIDTH, i / MapState.WIDTH)
			if float(age) + 0.000001 >= _seasons_needed(s, def, tile, foresters):
				s.set_terrain(tile, "forest")
				continue
		next[i] = age
	_age = next


## Finished, unpaused Foresters with at least one JOB_WORK citizen, in building-id order.
static func _staffed_foresters(s: Settlement) -> Array:
	var workers := _workers(s)
	var out: Array = []
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if not b.site and not b.paused and b.def.plants_forest and workers.get(bid, 0) > 0:
			out.append(b)
	return out


## Building id -> number of citizens holding a work job there. Jobs persist across the day, so this is the
## building's staffing at the hook.
static func _workers(s: Settlement) -> Dictionary:
	var out := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id >= 0 and c.job_kind == Citizen.JOB_WORK:
			out[c.job_id] = out.get(c.job_id, 0) + 1
	return out


## Seasons this stump needs before it grows back, after the Forester halving and every `regrow_factors` hook.
func _seasons_needed(s: Settlement, def: ForestDef, tile: Vector2i, foresters: Array) -> float:
	var need := float(def.regrow_seasons)
	for b: Building in foresters:
		if _within(b, tile, b.def.placement_radius):
			need = minf(need, float(def.forester_regrow_seasons))
			break
	for f in regrow_factors:
		need *= float(f.call(s, tile))
	return need


static func _within(b: Building, tile: Vector2i, r: int) -> bool:
	for ft in b.tiles():
		var dx := tile.x - ft.x
		var dy := tile.y - ft.y
		if dx * dx + dy * dy <= r * r:
			return true
	return false


## The plain grass tile a Forester plants next: nearest within BuildingDef.placement_radius of any footprint tile
## (Euclidean, the same circle as the placement rules), ties lower y then lower x. Only owned, plain grass with
## nothing built, laid, blighted or watered on it. (-1, -1) when there is none.
static func plant_tile(s: Settlement, b: Building) -> Vector2i:
	var r := b.def.placement_radius
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for ft in b.tiles():
		for y in range(ft.y - r, ft.y + r + 1):
			for x in range(ft.x - r, ft.x + r + 1):
				var d := (x - ft.x) * (x - ft.x) + (y - ft.y) * (y - ft.y)
				if d > r * r or not MapState.in_bounds(x, y):
					continue
				if s.map.terrain_id_at(x, y) != "grass":
					continue
				var i := MapState.idx(x, y)
				if s.occupancy[i] >= 0 or s.roads[i] != Settlement.ROAD_NONE \
						or s.channels[i] != Settlement.CHANNEL_NONE or s.map.blight[i] != 0:
					continue
				if not s.map.is_region_owned(s.map.get_region(x, y)):
					continue
				if d < best_d or (d == best_d and (y < best.y or (y == best.y and x < best.x))):
					best = Vector2i(x, y)
					best_d = d
	return best
