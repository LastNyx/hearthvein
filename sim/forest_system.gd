class_name ForestSystem
extends SimSystem
## Forest regrowth (design.md section 9).
##
## Woodcutters turn forest into "stump" terrain. Every season a stump ages one step while planet health is at least
## ForestDef.regrow_min_health and the tile is not blighted; once it has ForestDef.regrow_seasons it turns back into
## forest. A blighted or low-health stump does not age, so it does not regrow the season the blight is cleared or the
## health recovers. Stumps under a building, road or channel are left alone.
##
## All numbers are in data/forest/forest.tres. The old-forest region reward (ticket 25b) multiplies the seasons needed
## through `regrow_factors`: each Callable (settlement, tile) -> float, 0.5 = twice as fast.

const SAVE_KEY := "forest"

## Hooks that shorten or lengthen a stump's regrowth per tile, see the class comment.
var regrow_factors: Array[Callable] = []
## Tile index -> healthy, unblighted seasons the stump has stood. Absent means zero.
var _age: Dictionary = {}


func save_state() -> Dictionary:
	return {"age": SaveGame.pairs(_age)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_age = SaveGame.unpairs(d["age"]) if d.has("age") else {}


## The seasonal regrowth pass: age every tracked stump once, regrow the ones that are done.
func on_season(s: Settlement) -> void:
	var def := s.registry.forest
	if def == null:
		return
	var stump := s.map.terrain_index("stump")
	if stump < 0:
		return
	var healthy := s.planet_health() + 0.000001 >= def.regrow_min_health
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
			if float(age) + 0.000001 >= _seasons_needed(s, def, tile):
				s.set_terrain(tile, "forest")
				continue
		next[i] = age
	_age = next


## Seasons this stump needs before it grows back, after every `regrow_factors` hook.
func _seasons_needed(s: Settlement, def: ForestDef, tile: Vector2i) -> float:
	var need := float(def.regrow_seasons)
	for f in regrow_factors:
		need *= float(f.call(s, tile))
	return need
