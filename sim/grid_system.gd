class_name GridSystem
extends SimSystem
## The Lumen grid (design.md sections 7, 8 and 17, ticket 36). Finished buildings with BuildingDef.grid_feed_radius > 0
## (Lumen Pylon r8, Lumen Nexus r12) are grid nodes. Two nodes link when the gap between their footprints is within
## both defs' grid_link_range (12); a grid is a connected set of nodes, whether or not it holds a Nexus. All distances
## are Chebyshev tile gaps, footprint to footprint (Building.footprint_gap, like Market reach and coverage).
##
## A finished building is on a grid when its footprint is within a node's feed radius of that node; a building in reach
## of nodes of two grids belongs to the grid of the nearest node (ties: lowest node id). A node is always on its own grid.
## Sites are never on a grid.
##
## Supply of a grid = Lumen in the inventories of its storage buildings + Lumen in the door buffers of its producers.
## An on-grid producer's Lumen is supply the moment it is made (no hauler trip), and HaulingSystem neither carries
## Lumen between two on-grid buildings nor to an on-grid consumer. On-grid buildings pay upkeep at
## LogisticsDef.grid_upkeep_factor (x0.75) and take Lumen recipe inputs out of the supply (feed_inputs, draw).
##
## The membership is a cache keyed on (structure_version, completion_version), so it rebuilds only when buildings are
## placed, completed or demolished. It holds no runtime state and is left out of saves.

const SAVE_KEY := "grid"

## battery building id -> Lumen held.
var _charge: Dictionary = {}

## grid id (lowest node building id) -> {"nodes": Array[int], "members": Array[int]} both id-sorted.
var _grids: Dictionary = {}
var _of: Dictionary = {}  # building id -> grid id
var _links: Array = []  # [id_a, id_b] pairs, id_a < id_b
var _key: Vector2i = Vector2i(-1, -1)
var _count: int = -1


## Grid ids, low to high.
func grid_ids(s: Settlement) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	for g: int in _grids.keys():
		out.append(g)
	out.sort()
	return out


## Grid id of a building, or -1 when it is not on a grid.
func grid_of(s: Settlement, building_id: int) -> int:
	_ensure(s)
	return int(_of.get(building_id, -1))


## Node building ids of a grid, low to high.
func nodes_of(s: Settlement, grid_id: int) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	if _grids.has(grid_id):
		out.assign(_grids[grid_id]["nodes"])
	return out


## Every building on a grid (nodes included), low to high.
func members_of(s: Settlement, grid_id: int) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	if _grids.has(grid_id):
		out.assign(_grids[grid_id]["members"])
	return out


## Node-to-node links as [id_a, id_b] pairs (id_a < id_b), for an overlay to draw.
func links(s: Settlement) -> Array:
	_ensure(s)
	return _links.duplicate()


## Every tile within a node's feed radius that is on the map (the area an overlay shades), as Vector2i keys.
func covered_tiles(s: Settlement, grid_id: int) -> Dictionary:
	_ensure(s)
	var out := {}
	for nid in nodes_of(s, grid_id):
		var n: Building = s.buildings[nid]
		var r := n.def.grid_feed_radius
		var f := n.footprint()
		for y in range(f.position.y - r, f.end.y + r):
			for x in range(f.position.x - r, f.end.x + r):
				if MapState.in_bounds(x, y):
					out[Vector2i(x, y)] = true
	return out


## True when this building is on some grid. Cheap: a settlement with no node answers from one dictionary lookup.
static func on_grid(s: Settlement, b: Building) -> bool:
	var gs := s.get_system(GridSystem) as GridSystem
	return gs != null and gs.grid_of(s, b.id) >= 0


func save_state() -> Dictionary:
	return {"charge": SaveGame.pairs(_charge)}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_charge = SaveGame.unpairs(d.get("charge", []))


## Lumen one battery holds (0 for a building that is not a battery).
func charge_of(building_id: int) -> float:
	return float(_charge.get(building_id, 0.0))


## Lumen held by every battery in the settlement (the HUD resource bar counts it as Lumen stock).
func total_charge() -> float:
	var total := 0.0
	for v in _charge.values():
		total += float(v)
	return total


## Lumen held by the batteries of a grid. Not part of supply().
func battery_charge(s: Settlement, grid_id: int) -> float:
	var total := 0.0
	for bid in members_of(s, grid_id):
		total += float(_charge.get(bid, 0.0))
	return total


## Total capacity of a grid's batteries.
func battery_capacity(s: Settlement, grid_id: int) -> float:
	var total := 0.0
	for bid in members_of(s, grid_id):
		total += (s.buildings[bid] as Building).def.battery_capacity
	return total


## Lumen a grid holds (storage inventories plus producers' door buffers; battery charge is separate): storage inventories plus producers' door buffers.
func supply(s: Settlement, grid_id: int) -> float:
	var total := 0.0
	for bid in members_of(s, grid_id):
		var b: Building = s.buildings[bid]
		if b.inventory != null:
			total += b.inventory.amount_of("lumen")
		if b.door_buffer != null:
			total += b.door_buffer.amount_of("lumen")
	return total


## Hourly: on-grid producers' Lumen moves from their door buffers into on-grid storage with room, no hauler (the
## hauling skip leaves Lumen inside the grid alone, so without this a producer would halt on a full door). Lumen
## stays supply wherever it sits; with no storage room it simply waits in the door. A settlement with no node does
## nothing. Off-grid producers and storages are untouched.
func on_hour(s: Settlement) -> void:
	for bid: int in _charge.keys():
		if not s.buildings.has(bid):
			_charge.erase(bid)
	for gid in grid_ids(s):
		var members := members_of(s, gid)
		for pid in members:
			var p: Building = s.buildings[pid]
			if p.door_buffer == null:
				continue
			var have := p.door_buffer.amount_of("lumen")
			if have <= Inventory.EPS:
				continue
			for sid in members:
				var cap := (s.buildings[sid] as Building).def.battery_capacity
				if cap <= 0.0 or have <= Inventory.EPS:
					continue
				var held := float(_charge.get(sid, 0.0))
				var put := minf(have, cap - held)
				if put > Inventory.EPS:
					_charge[sid] = held + put
					p.door_buffer.remove("lumen", put)
					have -= put
			if have <= Inventory.EPS:
				continue
			for sid in members:
				var st: Building = s.buildings[sid]
				if st.inventory == null or not st.inventory.accepts("lumen"):
					continue
				var moved := st.inventory.add("lumen", have)
				if moved > Inventory.EPS:
					p.door_buffer.remove("lumen", moved)
					have -= moved
				if have <= Inventory.EPS:
					break


## Takes up to `amount` Lumen from a grid: door buffers first, then storages, then batteries, in building-id order.
## Returns what was taken.
func draw(s: Settlement, grid_id: int, amount: float) -> float:
	var got := 0.0
	for pass_no in 2:
		for bid in members_of(s, grid_id):
			if got >= amount - Inventory.EPS:
				return got
			var b: Building = s.buildings[bid]
			var inv: Inventory = b.door_buffer if pass_no == 0 else b.inventory
			if inv != null:
				got += inv.remove("lumen", amount - got)
	for bid in members_of(s, grid_id):
		if got >= amount - Inventory.EPS:
			break
		var have := float(_charge.get(bid, 0.0))
		if have > 0.0:
			var take := minf(have, amount - got)
			_charge[bid] = have - take
			got += take
	return got


## Tops an on-grid building's Lumen input buffer up to its two-day need from the grid's supply (the grid feeds recipe
## inputs directly, so no hauler brings them). Called by ProductionSystem before a batch.
func feed_inputs(s: Settlement, b: Building) -> void:
	if b.input_buffer == null or not b.def.recipe.inputs.has("lumen"):
		return
	var gid := grid_of(s, b.id)
	if gid < 0:
		return
	var need := float(HaulingSystem.input_need(s.registry, b.def).get("lumen", 0.0))
	var deficit := need - b.input_buffer.amount_of("lumen")
	if deficit > Inventory.EPS:
		b.input_buffer.add("lumen", draw(s, gid, minf(deficit, b.input_buffer.free_for("lumen"))))


func _ensure(s: Settlement) -> void:
	var key := Vector2i(s.structure_version, s.completion_version)
	if key == _key and _count == s.buildings.size():
		return
	_key = key
	_count = s.buildings.size()
	_rebuild(s)


func _rebuild(s: Settlement) -> void:
	_grids.clear()
	_of.clear()
	_links.clear()
	var ids: Array = s.buildings.keys()
	ids.sort()
	var nodes: Array[Building] = []
	for id in ids:
		var b: Building = s.buildings[id]
		if not b.site and b.def.grid_feed_radius > 0 and not IslandSystem.is_still_building(s, b):
			nodes.append(b)
	if nodes.is_empty():
		return
	# Union-find over nodes; the root is the lowest id because nodes are visited in id order.
	var parent: Array[int] = []
	for i in nodes.size():
		parent.append(i)
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var reach := mini(nodes[i].def.grid_link_range, nodes[j].def.grid_link_range)
			if Building.footprint_gap(nodes[i], nodes[j]) <= reach:
				_links.append([nodes[i].id, nodes[j].id])
				var a := _find(parent, i)
				var c := _find(parent, j)
				if a != c:
					parent[maxi(a, c)] = mini(a, c)
	var node_grid: Array[int] = []
	for i in nodes.size():
		var gid := nodes[_find(parent, i)].id
		node_grid.append(gid)
		if not _grids.has(gid):
			_grids[gid] = {"nodes": [], "members": []}
		_grids[gid]["nodes"].append(nodes[i].id)
		_of[nodes[i].id] = gid
	for id in ids:
		if _of.has(id):
			continue
		var b: Building = s.buildings[id]
		if b.site or IslandSystem.is_still_building(s, b):
			continue
		var best_gap := 1 << 30
		var best := -1
		for i in nodes.size():
			var gap := Building.footprint_gap(nodes[i], b)
			if gap <= nodes[i].def.grid_feed_radius and gap < best_gap:
				best_gap = gap
				best = node_grid[i]
		if best >= 0:
			_of[id] = best
	for id in ids:
		if _of.has(id):
			(_grids[_of[id]]["members"] as Array).append(id)


static func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
