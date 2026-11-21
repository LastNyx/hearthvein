class_name Placement
extends RefCounted
## Pure placement-rule checks (design.md section 6). Era unlocks and costs are not handled here.

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Forest tiles the "shade" rule needs inside placement_radius (Glowcap Grove, ticket 134).
const SHADE_FOREST_TILES := 2


## Terrain-only rule check for a footprint (bounds, ownership, overlap are checked by Settlement).
## Returns "" when the rule holds, otherwise a reason id.
static func check_rule(map: MapState, reg: DataRegistry, def: BuildingDef, origin: Vector2i) -> String:
	var tiles: Array[Vector2i] = []
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			tiles.append(Vector2i(x, y))
	# design.md section 12: blighted ground cannot hold a Park, Shrine or Orchard (BuildingDef.blocked_by_blight).
	if def.blocked_by_blight:
		for t in tiles:
			if map.is_blighted(t.x, t.y):
				return "blighted"
	# Bloom Orchard: the mean fertility of the footprint must reach def.min_fertility.
	if def.min_fertility > 0.0:
		var sum := 0.0
		for t in tiles:
			sum += float(map.get_fertility(t.x, t.y))
		if sum / float(tiles.size()) < def.min_fertility - 0.000001:
			return "low_fertility"
	match def.placement_rule:
		"any":
			return ""
		"on_vein":
			return "" if _any_terrain(map, tiles, ["lumen_vein"]) else "needs_vein"
		"on_rock":
			return "" if _any_terrain(map, tiles, ["rock"]) else "needs_rock"
		"wet":
			for t in tiles:
				if map.is_wet(t.x, t.y):
					return ""
			return "needs_wet"
		"on_wet":
			# The Well must stand on a wet tile (design.md section 9): the origin tile, not just any footprint tile.
			return "" if map.is_wet(origin.x, origin.y) else "needs_wet"
		"shore":
			for t in tiles:
				for d in DIRS:
					var n := t + d
					if MapState.in_bounds(n.x, n.y) and map.terrain_id_at(n.x, n.y) == "water":
						return ""
			return "needs_shore"
		"on_river":
			for t in tiles:
				if map.is_river(t.x, t.y):
					return ""
			return "needs_river"
		"river_bank":
			# The Water Wheel stands on land (Settlement refuses water for every other rule) and must touch a river
			# tile orthogonally, so it sits on the bank, not on the far end of a footprint.
			for t in tiles:
				for d in DIRS:
					var n := t + d
					if MapState.in_bounds(n.x, n.y) and map.is_river(n.x, n.y):
						return ""
			return "needs_river_bank"
		"near_forage":
			return "" if _near(map, tiles, def.placement_radius, ["grass", "forest"]) else "needs_forage"
		"near_forest":
			return "" if _near(map, tiles, def.placement_radius, ["forest"]) else "needs_forest"
		"shade":
			return "" if _count_near(map, tiles, def.placement_radius, ["forest"]) >= SHADE_FOREST_TILES else "needs_shade"
	return "unknown_rule"


static func _any_terrain(map: MapState, tiles: Array[Vector2i], ids: Array[String]) -> bool:
	for t in tiles:
		if map.terrain_id_at(t.x, t.y) in ids:
			return true
	return false


## Distinct terrain tiles of the `ids` within `radius` of any footprint tile (the circle the other near_ rules use).
static func _count_near(map: MapState, tiles: Array[Vector2i], radius: int, ids: Array[String]) -> int:
	var seen := {}
	var r2 := radius * radius
	for t in tiles:
		for y in range(t.y - radius, t.y + radius + 1):
			for x in range(t.x - radius, t.x + radius + 1):
				if MapState.in_bounds(x, y) and (x - t.x) * (x - t.x) + (y - t.y) * (y - t.y) <= r2 \
						and map.terrain_id_at(x, y) in ids:
					seen[Vector2i(x, y)] = true
	return seen.size()


static func _near(map: MapState, tiles: Array[Vector2i], radius: int, ids: Array[String]) -> bool:
	var r2 := radius * radius
	for t in tiles:
		for y in range(t.y - radius, t.y + radius + 1):
			for x in range(t.x - radius, t.x + radius + 1):
				if MapState.in_bounds(x, y) and (x - t.x) * (x - t.x) + (y - t.y) * (y - t.y) <= r2 \
						and map.terrain_id_at(x, y) in ids:
					return true
	return false
