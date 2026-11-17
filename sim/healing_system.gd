class_name HealingSystem
extends SimSystem
## Ascendant planet healers (design.md section 17). Once a day, every working building (PlanetHealthSystem.is_working:
## finished, unpaused, staffed, upkeep paid) on the ground layer acts:
##  - Verdant Spring (BuildingDef.heal_blight_*): clears the nearest blighted tile in reach, through
##    Settlement.set_blighted like a Cleanser, and sets its fertility to 100. A grass or stump tile with nothing built,
##    laid or channelled on it also becomes fertile soil (so its fallow regrowth cap is 100); a tile under something
##    keeps its terrain, and water, rock, vein and forest terrain are never turned into soil.
##  - Rewilding Grove (BuildingDef.rewild_*): turns the nearest plantable grass or stump tile in reach into forest
##    (never blighted, built, road, channel, rail track or an unowned region, the Forester's rules).
## Reach is the CleaningSystem measure: Euclidean from the closest footprint tile, nearest first, ties lower y then
## lower x. The planet terms are the buildings' health_per_day, counted by PlanetHealthSystem. No state to save.

const SAVE_KEY := "healing"


func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary, _settlement: Settlement) -> void:
	pass


func on_day(s: Settlement) -> void:
	var staffed := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = true
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.layer != Building.LAYER_GROUND:
			continue
		if b.def.heal_blight_per_day <= 0 and b.def.rewild_per_day <= 0:
			continue
		if not PlanetHealthSystem.is_working(s, b, staffed):
			continue
		for n in b.def.heal_blight_per_day:
			var t := next_blight_tile(s, b)
			if t.x < 0:
				break
			heal_tile(s, t)
		for n in b.def.rewild_per_day:
			var t := next_rewild_tile(s, b)
			if t.x < 0:
				break
			s.set_terrain(t, "forest")


## The nearest blighted tile within heal_blight_radius, (-1, -1) when none.
static func next_blight_tile(s: Settlement, b: Building) -> Vector2i:
	return _nearest(s, b, b.def.heal_blight_radius, func(x: int, y: int) -> bool: return s.map.is_blighted(x, y))


## The nearest plantable tile within rewild_radius, (-1, -1) when none.
static func next_rewild_tile(s: Settlement, b: Building) -> Vector2i:
	return _nearest(s, b, b.def.rewild_radius, func(x: int, y: int) -> bool: return _can_rewild(s, x, y))


static func _can_rewild(s: Settlement, x: int, y: int) -> bool:
	var id := s.map.terrain_id_at(x, y)
	if id != "grass" and id != "stump":
		return false
	return not _covered(s, x, y) and not s.map.is_blighted(x, y) and s.map.is_region_owned(s.map.get_region(x, y))


## Something built, road, channel or rail track lies on the tile.
static func _covered(s: Settlement, x: int, y: int) -> bool:
	var i := MapState.idx(x, y)
	return s.occupancy[i] >= 0 or s.roads[i] != Settlement.ROAD_NONE \
			or s.channels[i] != Settlement.CHANNEL_NONE or s.track[i] != 0


## Clear the tile's blight and make it fertility-100 soil (see the class comment for what changes).
static func heal_tile(s: Settlement, t: Vector2i) -> void:
	s.set_blighted(t, false)
	var id := s.map.terrain_id_at(t.x, t.y)
	if id == "water" or id == "rock" or id == "lumen_vein":
		return
	if (id == "grass" or id == "stump") and not _covered(s, t.x, t.y):
		s.set_terrain(t, "fertile_soil")
	var fs := s.get_system(FertilitySystem) as FertilitySystem
	if fs != null:
		fs.set_points(s.map, MapState.idx(t.x, t.y), 100.0)
	else:
		s.map.set_fertility(t.x, t.y, 100)


static func _nearest(s: Settlement, b: Building, r: int, ok: Callable) -> Vector2i:
	var rect := b.footprint().grow(r)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, MapState.HEIGHT)):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, MapState.WIDTH)):
			var d := CleaningSystem._dist2(b, x, y)
			if d > r * r or d > best_d:
				continue
			if d == best_d and not (y < best.y or (y == best.y and x < best.x)):
				continue
			if ok.call(x, y):
				best = Vector2i(x, y)
				best_d = d
	return best
