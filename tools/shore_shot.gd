extends SceneTree
## Windowed shore/rock shots: godot --path . -s tools/shore_shot.gd [-- seed]
## Ticket 54: z1 frames a diagonal river stretch and a bend, z2 a lake and a nearby rock patch, so the rounded
## dual-grid banks can be judged at two zoom levels. Writes /tmp/hv_shore_z1.png and /tmp/hv_shore_z2.png.

const T := ArtLibrary.TILE


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	for r in MapState.REGION_COUNT:  # no locked-region dimming: these shots judge the banks, not the map state
		s.map.region_owned[r] = 1
	var river_spot := _river_shot(s.map)
	var lake_spot := _lake_shot(s.map)
	print("SHORE river=%s lake=%s" % [river_spot, lake_spot])
	var cam: CameraController = main.get_node("Camera")
	for pair in [[2, river_spot, "/tmp/hv_shore_z1.png"], [3, lake_spot, "/tmp/hv_shore_z2.png"]]:
		cam.position = (Vector2(pair[1]) + Vector2(0.5, 0.5)) * T
		cam.set_zoom_step(pair[0])
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(pair[2])
	quit()


## River centreline tile with the longest diagonal run and a bend nearby: a stretch that shows both a smooth
## diagonal bank and a curve.
func _river_shot(map: MapState) -> Vector2i:
	var path := map.river_path
	if path.is_empty():
		return map.hearth_spot
	var best := path[path.size() / 2]
	var best_score := -1000
	for i in range(3, path.size() - 3):
		var d0: Vector2i = path[i] - path[i - 1]
		var turns := 0
		for j in range(i - 2, i + 3):
			if path[j] - path[j - 1] != d0:
				turns += 1
		var diag := 0
		for k in range(-3, 4):
			var p: Vector2i = path[i] + Vector2i(k, k)
			if _is_water(map, p):
				diag += 1
			p = path[i] + Vector2i(k, -k)
			if _is_water(map, p):
				diag += 1
		var score := diag + turns * 2
		if score > best_score:
			best_score = score
			best = path[i]
	return best


## Centre between a pond (a water body other than the river) and the nearest rock patch, so one shot shows a lake
## bank and a rock edge together.
func _lake_shot(map: MapState) -> Vector2i:
	var water := _components(map, "water")
	var rock := _components(map, "rock")
	water.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var blobs: Array[Vector2i] = []
	for r in rock:
		var blob: Array = r
		if blob.size() >= 4:
			blobs.append(_centroid(blob))
	var best := map.hearth_spot
	var best_d := 1e9
	for i in range(1, water.size()):  # the largest water body is the river, already in shot z1
		var body: Array = water[i]
		if body.size() < 10:
			continue
		var c := _centroid(body)
		for b in blobs:
			var d := Vector2(c).distance_to(Vector2(b))
			if d < best_d:
				best_d = d
				best = (c + b) / 2
	if best_d == 1e9 and water.size() > 1:
		best = _centroid(water[1])
	return best


func _is_water(map: MapState, p: Vector2i) -> bool:
	return MapState.in_bounds(p.x, p.y) and map.terrain_id_at(p.x, p.y) == "water"


## 4-connected tiles of one terrain id, river-connected water included.
func _components(map: MapState, id: String) -> Array:
	var seen := {}
	var out: Array = []
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var start := Vector2i(x, y)
			if seen.has(start) or map.terrain_id_at(x, y) != id:
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				comp.append(p)
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = p + o
					if MapState.in_bounds(n.x, n.y) and not seen.has(n) and map.terrain_id_at(n.x, n.y) == id:
						seen[n] = true
						stack.append(n)
			out.append(comp)
	return out


func _centroid(tiles: Array) -> Vector2i:
	var acc := Vector2.ZERO
	for p in tiles:
		acc += Vector2(p as Vector2i)
	return Vector2i((acc / float(tiles.size())).round())
