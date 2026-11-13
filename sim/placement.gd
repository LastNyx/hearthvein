class_name Placement
extends RefCounted
## Pure placement-rule checks (design.md section 6). Era unlocks and costs are not handled here.

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## Terrain-only rule check for a footprint (bounds, ownership, overlap are checked by Settlement).
## Returns "" when the rule holds, otherwise a reason id.
static func check_rule(map: MapState, reg: DataRegistry, def: BuildingDef, origin: Vector2i) -> String:
	var tiles: Array[Vector2i] = []
	for y in range(origin.y, origin.y + def.size.y):
		for x in range(origin.x, origin.x + def.size.x):
			tiles.append(Vector2i(x, y))
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
		"shore":
			for t in tiles:
				for d in DIRS:
					var n := t + d
					if MapState.in_bounds(n.x, n.y) and map.terrain_id_at(n.x, n.y) == "water":
						return ""
			return "needs_shore"
		"near_forage":
			return "" if _near(map, tiles, def.placement_radius, ["grass", "forest"]) else "needs_forage"
		"near_forest":
			return "" if _near(map, tiles, def.placement_radius, ["forest"]) else "needs_forest"
	return "unknown_rule"


static func _any_terrain(map: MapState, tiles: Array[Vector2i], ids: Array[String]) -> bool:
	for t in tiles:
		if map.terrain_id_at(t.x, t.y) in ids:
			return true
	return false


static func _near(map: MapState, tiles: Array[Vector2i], radius: int, ids: Array[String]) -> bool:
	var r2 := radius * radius
	for t in tiles:
		for y in range(t.y - radius, t.y + radius + 1):
			for x in range(t.x - radius, t.x + radius + 1):
				if MapState.in_bounds(x, y) and (x - t.x) * (x - t.x) + (y - t.y) * (y - t.y) <= r2 \
						and map.terrain_id_at(x, y) in ids:
					return true
	return false
