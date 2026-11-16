class_name IslandSystem
extends SimSystem
## Sky islands (design.md section 17, ticket 40). A finished Lift Anchor (BuildingDef.raises_island) raises one
## island: the LogisticsDef.island_width x island_height rect centred in the anchor's region is written as skystone into
## Settlement.sky_map. The island list lives here (id, region, rect, anchor building id); ticket 40b adds the Lumen
## supply and still state per island (see on_hour). An island is removed (tiles back to void) when its anchor is demolished, which
## Settlement.demolish only allows while nothing stands on it.
##
## Lumen (ticket 40b): every hour each island draws island_upkeep_lumen / 24 from the grid of its Lift Anchor
## (registered after GridSystem, so the grid's hourly Lumen shuffle has run). Still causes, checked in this order:
## "no_grid" (anchor unfinished or off every grid), "anchor_unstaffed" (fewer citizens working at the anchor than its
## worker slots, or paused), "short_lumen" (the grid cannot cover the hour's share: nothing is drawn). A still island
## stops every building on it (is_still_building: production halts "island_still", it serves no water, coverage or
## grid), keeps its homes' residents and loses nothing. Events: island_still {island, why} when the cause changes to
## a non-empty one, island_resumed {island} when fed again.

const SAVE_KEY := "islands"

var islands: Array[Island] = []
var _next_id: int = 0


## Hourly Lumen draw and still state of every island.
func on_hour(s: Settlement) -> void:
	if islands.is_empty():
		return
	var gs := s.get_system(GridSystem) as GridSystem
	var staffed := {}
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id >= 0 and c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = int(staffed.get(c.job_id, 0)) + 1
	var share := s.registry.logistics.island_upkeep_lumen / float(GameClock.HOURS_PER_DAY)
	for isl in islands:
		var why := ""
		var anchor: Building = s.buildings.get(isl.anchor_id)
		var gid := -1
		if anchor != null and not anchor.site and gs != null:
			gid = gs.grid_of(s, anchor.id)
		if gid < 0:
			why = "no_grid"
		elif anchor.paused or int(staffed.get(anchor.id, 0)) < anchor.effective_worker_slots(s.registry):
			why = "anchor_unstaffed"
		elif gs.supply(s, gid) + gs.battery_charge(s, gid) < share - Inventory.EPS:
			why = "short_lumen"
		else:
			gs.draw(s, gid, share)
		_set_still(s, isl, why)


func _set_still(s: Settlement, isl: Island, why: String) -> void:
	if isl.still_why == why:
		return
	isl.still_why = why
	# Still buildings stop being water, coverage and grid sources: those caches key on structure_version.
	s.structure_version += 1
	if why != "":
		s.events.emit("island_still", {"island": isl.id, "why": why, "region": isl.region})
	else:
		s.events.emit("island_resumed", {"island": isl.id, "region": isl.region})


## True for a sky building on an island that is still. Ground buildings answer false at once.
static func is_still_building(s: Settlement, b: Building) -> bool:
	if b.layer != Building.LAYER_SKY:
		return false
	var sys := s.get_system(IslandSystem) as IslandSystem
	if sys == null:
		return false
	var isl := sys.island_at(b.origin)
	return isl != null and isl.still_why != ""


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
