extends SceneTree
## Windowed bridge shot: godot --path . -s tools/bridges_shot.gd [-- seed]
## Ticket 91: three crossings of the river side by side: a dirt (plank) bridge, a paved (stone) bridge and a rail
## trestle, each with a few land tiles of road or track at both ends so the deck meets the bank. Writes
## /tmp/hv_91_bridges.png at zoom step 3 and /tmp/hv_91_bridges_wide.png (zoom step 2, 1x map feel).


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


## Rows y (any x) with a short straight water run along x between two land tiles: [y, x of the first water tile, length].
func _runs(s: Settlement, near: Vector2i) -> Array:
	var out: Array = []
	for y in range(2, MapState.HEIGHT - 2):
		for x in range(6, MapState.WIDTH - 12):
			if s.map.terrain_id_at(x, y) != "water" or s.map.terrain_id_at(x - 1, y) == "water":
				continue
			var n := 0
			while s.map.terrain_id_at(x + n, y) == "water" and n < 8:
				n += 1
			if n > 6 or s.map.terrain_id_at(x + n, y) == "water":
				continue
			out.append([y, x, n, absi(x - near.x) + absi(y - near.y)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[3] < b[3])
	return out


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	for r in MapState.REGION_COUNT:
		s.map.region_owned[r] = 1
	s.era_override = "conflux"
	s.hearth.inventory.add("materials", 800.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	var runs := _runs(s, s.map.hearth_spot)
	if runs.is_empty():
		print("BRIDGES no crossing found")
		quit()
		return
	# Three rows from the nearest crossing's area: the nearest run, then the next runs on different rows 2+ apart.
	var picks: Array = [runs[0]]
	for r: Array in runs:
		if picks.size() < 3 and absi(int(r[0]) - int(picks[picks.size() - 1][0])) >= 2 and absi(int(r[1]) - int(picks[0][1])) <= 14:
			picks.append(r)
	var kinds := ["dirt", "paved", "rail"]
	var laid := 0
	for k in picks.size():
		var y: int = picks[k][0]
		var x0: int = picks[k][1]
		var n: int = picks[k][2]
		for x in range(x0 - 3, x0 + n + 3):
			var t := Vector2i(x, y)
			match kinds[k]:
				"dirt":
					laid += 1 if s.place_road(t) else 0
				"paved":
					laid += 1 if s.pave_road(t) else 0
				"rail":
					laid += 1 if s.place_track(t) else 0
	print("BRIDGES picks=%s tiles laid=%d" % [str(picks), laid])
	var hud: Hud = main.get_node("Hud")
	var cam: CameraController = main.get_node("Camera")
	var c: Array = picks[picks.size() / 2]
	cam.position = (Vector2(int(c[1]) + int(c[2]) / 2.0, c[0]) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	cam.set_zoom_step(3)
	await _shoot("/tmp/hv_91_bridges.png")
	cam.set_zoom_step(2)
	await _shoot("/tmp/hv_91_bridges_wide.png")
	quit()
