class_name TutorialSeedCheck
extends RefCounted
## What the guided tutorial needs near the Hearth (ticket 79). Used by tools/find_tutorial_seed.gd to pick
## MapGenDef.tutorial_seed and by test_new_game_panel.gd to re-check it. Distances are Euclidean, in tiles.

const FOREST_RADIUS := 4.0       # the Woodcutter's placement radius
const WOODCUTTER_SPOT_MAX := 6.0 # a spot for it must be this close to the road start
const VEIN_MAX := 8.0
const RIVER_MAX := 12.0
const TENT_SPOTS := 6
const TENT_RANGE := 5.0
const SCAN := 14


## {forest, vein, river, tent_spots, market_spot, ok}: forest is the nearest forest tile to the best woodcutter spot (a
## buildable non-forest tile within WOODCUTTER_SPOT_MAX of the road start), vein and river the nearest such tile to the
## Hearth, tent_spots the grass/soil tiles within TENT_RANGE of the road start, market_spot a free 2x2 within 6.
static func measure(map: MapState, reg: DataRegistry) -> Dictionary:
	var h := map.hearth_spot
	var hs: Vector2i = reg.get_building("hearth").size
	var centre := Vector2(h) + Vector2(hs) * 0.5
	var road := Vector2(h + Vector2i(hs.x, 0)) + Vector2(0.5, 0.5)
	var forest := INF
	var vein := INF
	var river := INF
	var tents := 0
	var market := false
	for y in range(maxi(0, h.y - SCAN), mini(MapState.HEIGHT, h.y + SCAN + 1)):
		for x in range(maxi(0, h.x - SCAN), mini(MapState.WIDTH, h.x + SCAN + 1)):
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var t := map.terrain_id_at(x, y)
			if t == "lumen_vein":
				vein = minf(vein, p.distance_to(centre))
			if map.is_river(x, y):
				river = minf(river, p.distance_to(centre))
			var dr := p.distance_to(road)
			if _plain(reg, t) and not _on_hearth(Vector2i(x, y), h, hs):
				if dr <= TENT_RANGE and t != "lumen_vein":
					tents += 1
				if dr <= WOODCUTTER_SPOT_MAX:
					forest = minf(forest, _forest_near(map, x, y))
				if dr <= 6.0 and not market and _free_2x2(map, reg, Vector2i(x, y), h, hs):
					market = true
	return {"forest": forest, "vein": vein, "river": river, "tent_spots": tents, "market_spot": market,
		"ok": forest <= FOREST_RADIUS and vein <= VEIN_MAX and river <= RIVER_MAX and tents >= TENT_SPOTS and market}


static func _plain(reg: DataRegistry, terrain: String) -> bool:
	return terrain == "grass" or terrain == "fertile_soil"


static func _on_hearth(p: Vector2i, h: Vector2i, hs: Vector2i) -> bool:
	return Rect2i(h, hs).has_point(p) or p == h + Vector2i(hs.x, 0)  # the Hearth and its first road tile


static func _forest_near(map: MapState, x: int, y: int) -> float:
	var best := INF
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var qx := x + dx
			var qy := y + dy
			if MapState.in_bounds(qx, qy) and map.terrain_id_at(qx, qy) == "forest":
				best = minf(best, Vector2(dx, dy).length())
	return best


static func _free_2x2(map: MapState, reg: DataRegistry, o: Vector2i, h: Vector2i, hs: Vector2i) -> bool:
	for dy in 2:
		for dx in 2:
			var p := o + Vector2i(dx, dy)
			if not MapState.in_bounds(p.x, p.y) or not _plain(reg, map.terrain_id_at(p.x, p.y)) \
					or _on_hearth(p, h, hs) or map.is_river(p.x, p.y):
				return false
	return true
