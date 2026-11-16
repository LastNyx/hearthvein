class_name IslandSystem
extends SimSystem
## Sky islands (design.md section 17, ticket 40). A finished Lift Anchor (BuildingDef.raises_island) raises one
## island: the LogisticsDef.island_width x island_height rect centred in the anchor's region is written as skystone into
## Settlement.sky_map. The island list lives here (id, region, rect, anchor building id); ticket 40b adds the Lumen
## supply and still state per island. An island is removed (tiles back to void) when its anchor is demolished, which
## Settlement.demolish only allows while nothing stands on it. No hooks yet.

const SAVE_KEY := "islands"

var islands: Array[Island] = []
var _next_id: int = 0


func save_state() -> Dictionary:
	var out := []
	for i in islands:
		out.append(i.to_dict())
	return {"islands": out, "next_id": _next_id}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	islands.clear()
	for e in d["islands"]:
		islands.append(Island.from_dict(e))
	_next_id = int(d["next_id"])


## The island rect for a region: centred in it, sizes from LogisticsDef.
static func rect_for_region(reg: DataRegistry, region: int) -> Rect2i:
	var lg := reg.logistics
	var rr := MapState.region_rect(region)
	var size := Vector2i(lg.island_width, lg.island_height)
	return Rect2i(rr.position + (rr.size - size) / 2, size)


## Raises the island for a finished anchor. Null when its region already has one.
func raise(s: Settlement, anchor: Building) -> Island:
	var region := s.map.get_region(anchor.origin.x, anchor.origin.y)
	if island_of_region(region) != null:
		return null
	var isl := Island.new()
	isl.id = _next_id
	_next_id += 1
	isl.region = region
	isl.rect = rect_for_region(s.registry, region)
	isl.anchor_id = anchor.id
	islands.append(isl)
	for y in range(isl.rect.position.y, isl.rect.end.y):
		for x in range(isl.rect.position.x, isl.rect.end.x):
			s.sky_map.set_terrain_id(x, y, MapState.SKY_STONE)
	s.structure_version += 1
	s.grid_version += 1
	s.events.emit("island_raised", {"id": isl.id, "region": region, "rect": isl.rect, "anchor": anchor.id})
	return isl


## Removes an island: its tiles go back to void and any sky road on it is lifted. The caller checks it is empty.
func remove(s: Settlement, isl: Island) -> void:
	islands.erase(isl)
	for y in range(isl.rect.position.y, isl.rect.end.y):
		for x in range(isl.rect.position.x, isl.rect.end.x):
			s.sky_map.set_terrain_id(x, y, MapState.SKY_VOID)
			s.sky_roads[MapState.idx(x, y)] = Settlement.ROAD_NONE
	s.structure_version += 1
	s.grid_version += 1
	s.events.emit("island_removed", {"id": isl.id, "region": isl.region})


func island_of_region(region: int) -> Island:
	for i in islands:
		if i.region == region:
			return i
	return null


func island_of_anchor(building_id: int) -> Island:
	for i in islands:
		if i.anchor_id == building_id:
			return i
	return null


func island_at(tile: Vector2i) -> Island:
	for i in islands:
		if i.rect.has_point(tile):
			return i
	return null


## Sky-layer buildings (sites included) standing on the island.
func buildings_on(s: Settlement, isl: Island) -> Array[Building]:
	var out: Array[Building] = []
	for b: Building in s.buildings.values():
		if b.layer == Building.LAYER_SKY and isl.rect.intersects(b.footprint()):
			out.append(b)
	return out


## Island of a settlement, or null (no IslandSystem registered, or none raised there).
static func island_at_tile(s: Settlement, tile: Vector2i) -> Island:
	var sys := s.get_system(IslandSystem) as IslandSystem
	return sys.island_at(tile) if sys != null else null
