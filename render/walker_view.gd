class_name WalkerView
extends Node2D
## Draws every citizen outside a building in one _draw pass (no node per walker), from the walker atlas exported by
## tools/export_art.py. Facing follows the movement vector and the walk cycle runs only while the walker has a
## path. Walkers standing at a building door are inside it and not drawn, except a builder on a crew standing at its
## site, upgrade or Clear tile (ConstructionSystem.crews, ticket 105): it stays visible, standing around the door. Haulers carrying goods show a bundle.
## Reads the sim only; the only state kept here is the last facing per citizen (render state, not sim).

const STEP_SECONDS := 0.16  # per frame of the 4-beat cycle: step A, stand, step B, stand
const CYCLE := [0, 2, 1, 2]

var settlement: Settlement
var _system: WalkerSystem
var _hauling: HaulingSystem
var _atlas: Texture2D
var _shadow: Texture2D
var _bundles: Dictionary = {}
var _facing: Dictionary = {}  # citizen id -> DIR_*
var _time: float = 0.0
var _construction: ConstructionSystem
var _sky: SkyWalkers  # draws the walkers whose tile is on the sky layer, above the sky group (ticket 40d)


func setup(s: Settlement) -> void:
	settlement = s
	_system = s.get_system(WalkerSystem)
	_hauling = s.get_system(HaulingSystem)
	_construction = s.get_system(ConstructionSystem) as ConstructionSystem
	var e := ArtLibrary.walker_entry()
	_atlas = ArtLibrary.texture(e["file"])
	_shadow = ArtLibrary.texture(e["shadow"])
	for k in e["bundle"]:
		_bundles[k] = ArtLibrary.texture(e["bundle"][k])
	z_index = 10  # above the y-sorted objects, below the no-road icons
	_sky = SkyWalkers.new()
	_sky.owner_view = self
	_sky.z_index = 22  # above the sky group (z 30 relative to the map, this node adds to the parent's 10)
	_sky.visible = false
	add_child(_sky)


## D46: walkers are hidden at the farthest zoom step (CameraController.ZOOM_STEPS[0]).
static func shown_at_zoom(zoom_value: float) -> bool:
	return not CameraController.is_farthest_zoom(zoom_value)


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var show_walkers := cam == null or shown_at_zoom(cam.zoom.x)
	# Ground walkers show in the ground view, sky walkers in the sky view; the other layer's are hidden.
	var sky_view := _active_layer() == 1
	if show_walkers != visible:
		visible = show_walkers
	var ground_on := show_walkers and not sky_view
	var sky_on := show_walkers and sky_view
	if _sky.visible != sky_on:
		_sky.visible = sky_on
	if ground_on:
		queue_redraw()
	if sky_on:
		_sky.queue_redraw()


func _active_layer() -> int:
	var mv := get_parent() as MapView
	return mv.active_layer if mv != null else 0


## Walker.position() is in global tile space (sky y offset by MapState.HEIGHT): back to the layer's own coordinates.
static func _local_position(w: Walker, layer: int) -> Vector2:
	if _riding(w):  # the lift or dock ride: it stays on its tile until the step ends
		return Vector2(MapState.local_of(w.tile)) + Vector2(0.5, 0.5)
	return w.position() - Vector2(0, MapState.HEIGHT) if layer == 1 else w.position()


## True while the walker's current step crosses between the layers (a Sky Lift or dock ride).
static func _riding(w: Walker) -> bool:
	return not w.path.is_empty() and MapState.layer_of(w.path[0]) != MapState.layer_of(w.tile)


## True for a walker standing at a door that must still be drawn: a builder on a crew whose work is that building.
static func shown_at_door(w: Walker, crews: Dictionary) -> bool:
	return w.at_building >= 0 and w.path.is_empty() and crews.get(w.citizen_id, -1) == w.at_building


## Pixel offset of a standing crew member from the door tile centre, fixed per citizen id so a crew of 4 does not stack:
## spread across the tile in front of the door, outside the footprint, because the site scaffold (PlacementView, z 20)
## draws over the walkers (z 10) and would hide anyone standing on the door tile itself.
static func crew_offset(citizen_id: int) -> Vector2:
	var slot := citizen_id % 4
	return Vector2(-15.0 + 10.0 * slot, 38.0 + 4.0 * ((citizen_id / 4) % 2))


## Movement vector in tiles of a walker (zero when it has no path).
static func move_vector(w: Walker) -> Vector2:
	if w.path.is_empty() or _riding(w):
		return Vector2.ZERO
	return Vector2(w.path[0] - w.tile)


func _draw() -> void:
	if _active_layer() == 0:
		_draw_layer(self, 0)


## Inner node drawing the sky layer's walkers.
class SkyWalkers extends Node2D:
	var owner_view: WalkerView

	func _draw() -> void:
		if owner_view != null:
			owner_view._draw_layer(self, 1)


## Walkers whose current (global) tile decodes to `layer` (MapState.layer_of), drawn at their local position. One on a
## lift or dock tile shows on whichever layer its tile says.
func _draw_layer(ci: CanvasItem, layer: int) -> void:
	if _system == null:
		return
	var e := ArtLibrary.walker_entry()
	var cell: Array = e["cell"]
	var foot: Array = e["foot"]
	var cell_size := Vector2(cell[0], cell[1])
	var foot_v := Vector2(foot[0], foot[1])
	var sh_off := Vector2(e["shadow_offset"][0], e["shadow_offset"][1])
	var map_seed := settlement.map.seed_used
	var tile := float(ArtLibrary.TILE)
	# Only walkers inside the view (plus a margin) are drawn.
	var view := get_viewport_transform().affine_inverse() * get_viewport_rect()
	view = view.grow(64.0)
	var items: Array = []
	for id in _system.walkers:
		var w: Walker = _system.walkers[id]
		var moving := w.is_walking() and not _riding(w)
		var at_door := false
		if not moving and w.at_building >= 0:
			if _construction == null or not shown_at_door(w, _construction.crews):
				continue
			at_door = true
		if MapState.layer_of(w.tile) != layer:
			continue
		var local_pos := _local_position(w, layer)
		if not view.has_point(local_pos * tile):
			continue
		var dir: int = ArtLibrary.facing_for(move_vector(w), _facing.get(id, ArtLibrary.DIR_DOWN))
		_facing[id] = dir
		var p := (local_pos * tile).round()
		if at_door:
			p += crew_offset(id)
		items.append([p, id, dir, moving])
	items.sort_custom(func(a, b): return a[0].y < b[0].y)  # nearer walkers over farther ones
	for it in items:
		ci.draw_texture(_shadow, it[0] + sh_off)
	for it in items:
		var p: Vector2 = it[0]
		var id: int = it[1]
		var dir: int = it[2]
		var frame := 2
		if it[3]:
			var phase := int(_time / STEP_SECONDS) + ArtLibrary.tile_hash(map_seed, id, 31) % 4
			frame = CYCLE[phase % 4]
		var carrying := _hauling != null and _hauling.trips.has(id) and (_hauling.trips[id] as HaulingSystem.Trip).carried > 0.0
		var bundle_key := "side" if dir >= ArtLibrary.DIR_LEFT else ("back" if dir == ArtLibrary.DIR_UP else "front")
		if carrying and dir == ArtLibrary.DIR_UP:
			_draw_bundle(ci, e, bundle_key, p, dir)
		var v := ArtLibrary.walker_variant(id, map_seed)
		ci.draw_texture_rect_region(_atlas, Rect2(p - foot_v, cell_size), ArtLibrary.walker_region(v, dir, frame))
		if carrying and dir != ArtLibrary.DIR_UP:
			_draw_bundle(ci, e, bundle_key, p, dir)


func _draw_bundle(ci: CanvasItem, e: Dictionary, key: String, p: Vector2, dir: int) -> void:
	var off: Array = e["bundle_offset"][key]
	var o := Vector2(off[0], off[1])
	if key == "side":  # held on the side the walker faces
		o.x = -4.0 if dir == ArtLibrary.DIR_RIGHT else -6.0
	ci.draw_texture(_bundles[key], p + o)
