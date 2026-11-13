class_name RegionSystem
extends SimSystem
## Region rewards (design.md section 4, ticket 25b). MapGen already lays the terrain part of a reward on the map:
## a rich-vein cluster, the fertile-valley patch, the old-forest blob and the spring's 2x2 water. Buying a region
## applies the rest here, once:
##
## - rich vein: ProductionSystem modifier (rich_vein_modifier) x RegionsDef.rich_vein_factor for vein extractors
##   standing in an owned rich-vein region.
## - old forest: ForestSystem.regrow_factors hook (regrow_factor) scales the seasons a stump needs by
##   ForestDef.old_forest_regrow_factor (0.5 = twice as fast).
## - spring: writes the spring water (already there from MapGen) and rebuilds the WaterSystem wet map, so the base
##   mask includes it; MapState.water_version is bumped so the cached base is rebuilt.
## - fertile valley: nothing to apply, the fertile soil is already on the map and fertility was set at generation.
## - ruins: a one-time payout from RegionsDef (gold and/or goods). `_claimed` is saved so a save/load can never pay
##   it a second time.
##
## All numbers are in data/regions/regions.tres and data/forest/forest.tres.

const SAVE_KEY := "regions"

## Regions whose reward has been applied (region index -> true). A region is bought once in normal play; the flag
## makes applying idempotent and keeps ruins from paying again after a load.
var _claimed: Dictionary = {}


func save_state() -> Dictionary:
	return {"claimed": _claimed.keys()}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_claimed = {}
	for r in d.get("claimed", []):
		_claimed[int(r)] = true


## Applies the reward of a freshly bought region once. Returns the reward id ("" for a region without a reward, or
## when it was already applied).
func apply_rewards(s: Settlement, r: int) -> String:
	if r < 0 or r >= MapState.REGION_COUNT or _claimed.has(r):
		return ""
	var reward := s.map.get_region_reward(r)
	_claimed[r] = true
	if reward == "":
		return ""
	match reward:
		MapState.REWARD_RICH_VEIN, MapState.REWARD_OLD_FOREST, MapState.REWARD_FERTILE_VALLEY:
			pass  # the modifier hooks read the map; the terrain is already laid by MapGen
		MapState.REWARD_SPRING:
			_spring(s, r)
		MapState.REWARD_RUINS:
			pay_ruins(s, s.registry.regions, s.map.region_reward_pos[r])
	s.events.emit("region_reward", {"region": r, "reward": reward})
	return reward


## The spring: make sure its 2x2 water is water, then rebuild the derived wet map from it.
func _spring(s: Settlement, r: int) -> void:
	var pos := s.map.region_reward_pos[r]
	if pos.x < 0:
		return
	for dy in 2:
		for dx in 2:
			var t := pos + Vector2i(dx, dy)
			if MapState.in_bounds(t.x, t.y) and s.map.terrain_id_at(t.x, t.y) != "water":
				s.set_terrain(t, "water")
	s.map.water_version += 1  # invalidates WaterSystem's cached water-terrain base
	WaterSystem.recompute(s)


## The ruins payout: gold to the counter, goods into the nearest storage with room, measured from the marker.
static func pay_ruins(s: Settlement, rd: RegionsDef, from: Vector2i) -> void:
	if rd == null:
		return
	if rd.ruins_gold > 0:
		s.gold += float(rd.ruins_gold)
	if not rd.ruins_goods.is_empty():
		s.store_goods(rd.ruins_goods.duplicate(), from)


## ProductionSystem modifier: vein extractors in an owned rich-vein region yield RegionsDef.rich_vein_factor Lumen.
static func rich_vein_modifier(s: Settlement, b: Building) -> float:
	return rich_vein_factor_at(s, b.origin) if b.def.vein_extractor else 1.0


## The rich-vein factor for a building at `origin` (1.0 unless the region is owned and has that reward).
static func rich_vein_factor_at(s: Settlement, origin: Vector2i) -> float:
	if not MapState.in_bounds(origin.x, origin.y):
		return 1.0
	var r := s.map.get_region(origin.x, origin.y)
	if not s.map.is_region_owned(r) or s.map.get_region_reward(r) != MapState.REWARD_RICH_VEIN:
		return 1.0
	var rd := s.registry.regions
	return rd.rich_vein_factor if rd != null else 1.0


## ForestSystem.regrow_factors hook: stumps in an owned old-forest region need
## ForestDef.old_forest_regrow_factor times the seasons (0.5 = regrow twice as fast).
static func regrow_factor(s: Settlement, tile: Vector2i) -> float:
	if not MapState.in_bounds(tile.x, tile.y):
		return 1.0
	var r := s.map.get_region(tile.x, tile.y)
	if not s.map.is_region_owned(r) or s.map.get_region_reward(r) != MapState.REWARD_OLD_FOREST:
		return 1.0
	var fd := s.registry.forest
	return fd.old_forest_regrow_factor if fd != null else 1.0
