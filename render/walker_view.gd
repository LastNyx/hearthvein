class_name WalkerView
extends Node2D
## Draws every citizen outside a building in one _draw pass (no node per walker), from the walker atlas exported by
## tools/export_art.py. Facing follows the movement vector and the walk cycle runs only while the walker has a
## path. Walkers standing at a building door are inside it and not drawn. Haulers carrying goods show a bundle.
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


func setup(s: Settlement) -> void:
	settlement = s
	_system = s.get_system(WalkerSystem)
	_hauling = s.get_system(HaulingSystem)
	var e := ArtLibrary.walker_entry()
	_atlas = ArtLibrary.texture(e["file"])
	_shadow = ArtLibrary.texture(e["shadow"])
	for k in e["bundle"]:
		_bundles[k] = ArtLibrary.texture(e["bundle"][k])
	z_index = 10  # above the y-sorted objects, below the no-road icons


## D46: walkers are hidden at the farthest zoom step (CameraController.ZOOM_STEPS[0]).
static func shown_at_zoom(zoom_value: float) -> bool:
	return not CameraController.is_farthest_zoom(zoom_value)


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var show_walkers := cam == null or shown_at_zoom(cam.zoom.x)
	if show_walkers != visible:
		visible = show_walkers
	if show_walkers:
		queue_redraw()


## Movement vector in tiles of a walker (zero when it has no path).
static func move_vector(w: Walker) -> Vector2:
	if w.path.is_empty():
		return Vector2.ZERO
	return Vector2(w.path[0] - w.tile)


func _draw() -> void:
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
		var moving := w.is_walking()
		if not moving and w.at_building >= 0:
			continue
		if not view.has_point(w.position() * tile):
			continue
		var dir: int = ArtLibrary.facing_for(move_vector(w), _facing.get(id, ArtLibrary.DIR_DOWN))
		_facing[id] = dir
		var p := (w.position() * tile).round()
		items.append([p, id, dir, moving])
	items.sort_custom(func(a, b): return a[0].y < b[0].y)  # nearer walkers over farther ones
	for it in items:
		draw_texture(_shadow, it[0] + sh_off)
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
			_draw_bundle(e, bundle_key, p, dir)
		var v := ArtLibrary.walker_variant(id, map_seed)
		draw_texture_rect_region(_atlas, Rect2(p - foot_v, cell_size), ArtLibrary.walker_region(v, dir, frame))
		if carrying and dir != ArtLibrary.DIR_UP:
			_draw_bundle(e, bundle_key, p, dir)


func _draw_bundle(e: Dictionary, key: String, p: Vector2, dir: int) -> void:
	var off: Array = e["bundle_offset"][key]
	var o := Vector2(off[0], off[1])
	if key == "side":  # held on the side the walker faces
		o.x = -4.0 if dir == ArtLibrary.DIR_RIGHT else -6.0
	draw_texture(_bundles[key], p + o)
