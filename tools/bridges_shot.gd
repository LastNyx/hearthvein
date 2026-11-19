extends SceneTree
## Windowed bridge shot: godot --path . -s tools/bridges_shot.gd [-- seed]
## Ticket 91: three crossings of the river, bank to bank and spaced along it: a dirt (plank) bridge, a paved (stone) bridge and a rail
## trestle, each with a few land tiles of road or track at both ends so the deck meets the bank. Writes
## /tmp/hv_91_bridges.png at zoom step 3 and /tmp/hv_91_bridges_wide.png (zoom step 2, 1x map feel).


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


## Crossings of a plain stretch of the river: starting on a river tile whose bank is the next tile back, a straight run of
## river tiles across the flow (vertical for an east/west flow, horizontal for north/south) of 2..6 tiles with land at
## both ends, and the middle tile's upstream and downstream neighbours also water, so the bridge goes bank to bank at
## right angles to the flow and not along a pond edge. Each is [x, y, length, step x, step y, distance to `near`].
func _runs(s: Settlement, near: Vector2i) -> Array:
	var out: Array = []
	var m := s.map
	for y in range(4, MapState.HEIGHT - 8):
		for x in range(4, MapState.WIDTH - 8):
			if not m.is_river(x, y):
				continue
			var f := m.get_flow(x, y)
			var step := Vector2i(0, 1) if (f == MapState.FLOW_E or f == MapState.FLOW_W) else Vector2i(1, 0)
			var t := Vector2i(x, y)
			if m.terrain_id_at(t.x - step.x, t.y - step.y) == "water":
				continue  # not the first tile of the run
			var n := 0
			var ok := true
			while n < 8 and m.terrain_id_at(t.x + step.x * n, t.y + step.y * n) == "water":
				ok = ok and m.is_river(t.x + step.x * n, t.y + step.y * n)
				n += 1
			if not ok or n < 2 or n > 6 or m.terrain_id_at(t.x + step.x * n, t.y + step.y * n) == "water":
				continue
			var mid := t + step * (n / 2)
			var along := Vector2i(step.y, step.x)
			if m.terrain_id_at(mid.x + along.x, mid.y + along.y) != "water" or m.terrain_id_at(mid.x - along.x, mid.y - along.y) != "water":
				continue
			out.append([x, y, n, step.x, step.y, absi(x - near.x) + absi(y - near.y)])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[5] < b[5])
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
	s.hearth.inventory.add("wood", 800.0)
	s.hearth.inventory.add("stone", 800.0)
	s.hearth.inventory.add("cut_stone", 100.0)
	var runs := _runs(s, s.map.hearth_spot)
	if runs.is_empty():
		print("BRIDGES no crossing found")
		quit()
		return
	# The nearest crossing, then two more along the river 7..14 tiles away from the previous pick.
	var picks: Array = [runs[0]]
	for r: Array in runs:
		var d := absi(int(r[0]) - int(picks[picks.size() - 1][0])) + absi(int(r[1]) - int(picks[picks.size() - 1][1]))
		if picks.size() < 3 and d >= 7 and d <= 14:
			picks.append(r)
	var kinds := ["dirt", "paved", "rail"]
	var laid := 0
	for k in picks.size():
		var o := Vector2i(picks[k][0], picks[k][1])
		var n: int = picks[k][2]
		var step := Vector2i(picks[k][3], picks[k][4])
		for i in range(-3, n + 3):  # three land tiles of road or track on each bank, the bridge tiles between
			var t := o + step * i
			if s.map.terrain_id_at(t.x, t.y) in ["forest", "rock", "lumen_vein"]:
				s.set_terrain(t, "grass")  # clear the bank so the approach road or track can reach the deck
			var ok := false
			match kinds[k]:
				"dirt":
					ok = s.place_road(t)
				"paved":
					ok = s.pave_road(t)
				"rail":
					ok = s.place_track(t)
			laid += 1 if ok else 0
			if not ok:
				print("BRIDGES %s refused at %s (%s)" % [kinds[k], str(t), s.map.terrain_id_at(t.x, t.y)])
	print("BRIDGES picks=%s tiles laid=%d" % [str(picks), laid])
	var hud: Hud = main.get_node("Hud")
	var cam: CameraController = main.get_node("Camera")
	var c: Array = picks[0]  # the middle one along the river
	cam.position = (Vector2(int(c[0]), int(c[1])) + Vector2(int(c[3]), int(c[4])) * (int(c[2]) / 2.0) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	cam.set_zoom_step(3)
	await _shoot("/tmp/hv_91_bridges.png")
	cam.set_zoom_step(2)
	await _shoot("/tmp/hv_91_bridges_wide.png")
	quit()
