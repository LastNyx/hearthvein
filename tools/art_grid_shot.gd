extends SceneTree
## Grid-overlay art audit (ticket 167, from the ticket-160 review audit): draws the 32 px tile grid, every building's
## footprint rectangle and a dot on every drawn trunk -- green when the trunk stands on its own tile, red with a line
## back to the tile centre when it does not -- then saves the forest edge, the market and the generic building row.
## Run under Xvfb: xvfb-run -a godot --path . -s tools/art_grid_shot.gd [-- <out_dir>]
## Writes .scratch/v1/shots/160-forest-edge.png, 160-market.png and 160-row.png by default.

const TILE := 32
const ZOOM_STEP := 3  # 2.0: 64 px tiles, the zoom the audit was read at
const ZOOM := 2.0
const VIEW := Vector2(1280, 720)
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DEFAULT_DIR := "res://.scratch/v1/shots/"
const RECT_COLORS := [Color(0.95, 0.35, 0.95), Color(0.25, 0.85, 0.9), Color(0.95, 0.85, 0.25),
	Color(0.95, 0.55, 0.2), Color(0.9, 0.25, 0.25), Color(0.5, 0.9, 0.4), Color(0.6, 0.5, 0.95)]


## Draws the audit marks in world space, so the camera carries them with the map.
class Audit extends Node2D:
	var settlement: Settlement
	var view_rect := Rect2()

	func _draw() -> void:
		var r := view_rect.grow(TILE)
		var x0 := floori(r.position.x / TILE)
		var x1 := ceili(r.end.x / TILE)
		var y0 := floori(r.position.y / TILE)
		var y1 := ceili(r.end.y / TILE)
		var grid := Color(1, 1, 1, 0.35)
		for gx in range(x0, x1 + 1):
			draw_line(Vector2(gx * TILE, r.position.y), Vector2(gx * TILE, r.end.y), grid, 1.0)
		for gy in range(y0, y1 + 1):
			draw_line(Vector2(r.position.x, gy * TILE), Vector2(r.end.x, gy * TILE), grid, 1.0)
		var i := 0
		for row in settlement.buildings.values():
			var b := row as Building
			var fp := b.footprint()
			draw_rect(Rect2(Vector2(fp.position) * TILE, Vector2(fp.size) * TILE),
					RECT_COLORS[i % RECT_COLORS.size()], false, 2.0)
			i += 1
		var green := Color(0.2, 0.95, 0.3)
		var red := Color(1.0, 0.15, 0.15)
		for gy in range(y0, y1):
			for gx in range(x0, x1):
				if not MapState.in_bounds(gx, gy):
					continue
				var id := settlement.map.terrain_id_at(gx, gy)
				if ArtLibrary.ground_of(id) != "forest":
					continue
				var open := PropBatch.open_dir(settlement.map, gx, gy)
				for p: Dictionary in ArtLibrary.scatter(id, gx, gy, open):
					var pos: Vector2 = p["pos"]
					var owner := Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
					if owner == Vector2i(gx, gy):
						draw_circle(pos, 3.0, green)
					else:
						draw_circle(pos, 3.0, red)
						draw_line(Vector2(gx * TILE + TILE * 0.5, gy * TILE + TILE * 0.5), pos, red, 2.0)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else DEFAULT_DIR
	if not out_dir.ends_with("/"):
		out_dir += "/"
	_make_dir(out_dir)
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	# A clear grass block near the Hearth, then the early buildings in a row (no road: they wear the no-road icon).
	var block := _find_block(s, 8, 3)
	if block.x < 0:
		push_error("art_grid_shot: no clear grass block near the Hearth")
		quit(1)
		return
	_place(s, "tent", block + Vector2i(0, 1))
	_place(s, "market", block + Vector2i(1, 1))
	_place(s, "farm", block + Vector2i(4, 1))
	_place(s, "cottage", block + Vector2i(7, 1))
	var audit := Audit.new()
	audit.settlement = s
	audit.z_index = 50
	main.add_child(audit)
	var cam := main.get_node("Camera") as CameraController
	cam.set_zoom_step(ZOOM_STEP)
	await _shoot(out_dir + "160-forest-edge.png", cam, audit, _forest_edge(s))
	await _shoot(out_dir + "160-market.png", cam, audit, _center_of(s, "market"))
	await _shoot(out_dir + "160-row.png", cam, audit, _row_center(s))
	quit()


func _shoot(path: String, cam: CameraController, audit: Audit, center: Vector2) -> void:
	cam.position = center
	var half := VIEW / (2.0 * ZOOM)
	audit.view_rect = Rect2(center - half, half * 2.0)
	audit.queue_redraw()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("art_grid_shot: wrote ", path)


func _make_dir(dir: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir
	if abs_dir != "":
		DirAccess.make_dir_recursive_absolute(abs_dir)


## First all-grass w x h block in the owned start region (buildings, roads and non-grass tiles disqualify a block).
func _find_block(s: Settlement, w: int, h: int) -> Vector2i:
	var rect := MapState.region_rect(s.map.start_region)
	for by in range(rect.position.y, rect.end.y - h + 1):
		for bx in range(rect.position.x, rect.end.x - w + 1):
			if _clear(s, Rect2i(bx, by, w, h)):
				return Vector2i(bx, by)
	return Vector2i(-1, -1)


func _clear(s: Settlement, r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not MapState.in_bounds(x, y):
				return false
			if s.map.terrain_id_at(x, y) != "grass":
				return false
			if not s.map.is_region_owned(s.map.get_region(x, y)):
				return false
			var t := Vector2i(x, y)
			if s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE:
				return false
	return true


func _place(s: Settlement, id: String, t: Vector2i) -> void:
	if s.place_building_instant(id, t) < 0:
		push_warning("art_grid_shot: could not place %s at %s" % [id, t])


## World centre of a placed building's footprint (Vector2.ZERO when it was not placed).
func _center_of(s: Settlement, id: String) -> Vector2:
	for b: Building in s.buildings.values():
		if b.def.id == id:
			var fp := b.footprint()
			return Vector2(fp.position) * TILE + Vector2(fp.size) * TILE * 0.5
	return Vector2.ZERO


## World centre of the early building row (the mean of the four footprint centres).
func _row_center(s: Settlement) -> Vector2:
	var acc := Vector2.ZERO
	var n := 0
	for id in ["tent", "market", "farm", "cottage"]:
		var c := _center_of(s, id)
		if c != Vector2.ZERO:
			acc += c
			n += 1
	return acc / maxf(1.0, float(n))


## World centre of the nearest forest tile that touches grass (the first one near the Hearth).
func _forest_edge(s: Settlement) -> Vector2:
	var spot := s.map.hearth_spot
	for radius in range(2, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t := spot + Vector2i(dx, dy)
				if not MapState.in_bounds(t.x, t.y):
					continue
				if ArtLibrary.ground_of(s.map.terrain_id_at(t.x, t.y)) != "forest":
					continue
				for d in DIRS:
					var n := t + d
					if MapState.in_bounds(n.x, n.y) and s.map.terrain_id_at(n.x, n.y) == "grass":
						return (Vector2(t) + Vector2(0.5, 0.5)) * TILE
	return Vector2(spot) * TILE
