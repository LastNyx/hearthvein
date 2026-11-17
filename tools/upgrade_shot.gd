extends SceneTree
## Windowed upgrade UI shot: godot --path . -s tools/upgrade_shot.gd [-- seed]
## Ticket 31d: a Town-era settlement with three upgradable 1x1 buildings in a row: a Cottage selected with its panel
## (Upgrade to Shingled Cottage, allowed), a Forager mid-upgrade (progress bar under it) and a Cottage already at
## tier II drawn with its tier sprite (cottage_shingle, from the data)
## to show the tier sprite swap. Writes /tmp/hv_upgrade.png.


func _shoot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(s: Settlement, def_id: String, near: Vector2i) -> Vector2i:
	for r in range(0, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := near + Vector2i(dx, dy)
				if s.can_place(def_id, t)["ok"]:
					return t
	return Vector2i(-1, -1)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	main.start_new_game()
	var s: Settlement = main.settlement
	var h := s.map.hearth_spot
	for r in MapState.REGION_COUNT:
		s.map.region_owned[r] = 1
	s.era_override = "town"
	var hud: Hud = main.get_node("Hud")
	hud._rebuild_categories()
	var y := h.y + 4
	for x in range(h.x - 6, h.x + 8):
		s.place_road(Vector2i(x, y))
	var tent_a := s.place_building_instant("cottage", Vector2i(h.x - 3, y - 1))
	var worker := s.place_building_instant("forager", _spot(s, "forager", Vector2i(h.x + 1, y - 3)))
	var tent_b := s.place_building_instant("cottage", Vector2i(h.x + 3, y - 1))
	print("UPGRADE placed tent_a=%d forager=%d tent_b=%d" % [tent_a, worker, tent_b])
	# Cottage B is already tier II (Shingled Cottage, tier sprite).
	s.upgrade(tent_b)
	s.complete_upgrade(s.buildings[tent_b])
	# The Forager is halfway: part of the cost delivered, some work done.
	if worker >= 0 and s.upgrade(worker):
		var w: Building = s.buildings[worker]
		for g in w.upgrade_cost:
			w.upgrade_buffer.add(g, float(w.upgrade_cost[g]))
		w.upgrade_work = w.upgrade_work_needed * 0.5
	var cam: CameraController = main.get_node("Camera")
	cam.position = (Vector2(h.x, y - 1) + Vector2(0.5, 0.5)) * ArtLibrary.TILE
	cam.set_zoom_step(3)
	hud.model.select(tent_a)
	hud.refresh()
	print("UPGRADE panel ", hud.model.selection()["next_name"], " ", hud.model.selection()["next_cost"], " can=",
			hud.model.selection()["can_upgrade"])
	await _shoot("/tmp/hv_upgrade.png")
	quit()
