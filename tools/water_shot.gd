extends SceneTree
## Windowed water/channel shots: godot --path . -s tools/water_shot.gd [-- seed]
## Ticket 21b: a channel dug from the river toward a farm (flowing look, wet tint around it) and one dry
## disconnected channel (dry look, no wet tint). Writes /tmp/hv_water_off.png (overlay off) and
## /tmp/hv_water_on.png (water overlay on, the T key / Overlays menu Water entry).
## Ticket 29d: a blight patch on the bank upstream of the channel and a Well beside the channel. After the shot steps
## 12 hours the fouling front has run downstream from the blight, so the overlay shows a fouled river stretch (sickly
## green) and the Well's range (blue-teal outline). The fouled tiles also show in the overlay-off shot (fouled art).

const T := ArtLibrary.TILE
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.game_seed = int(args[0]) if args.size() > 0 else 42
	root.add_child(main)
	await process_frame
	var s: Settlement = main.settlement
	for r in MapState.REGION_COUNT:
		s.map.region_owned[r] = 1
	s.era_override = "village"
	s.registry.water.channel_cost_materials = 0.0  # the shot does not care about the stockpile
	var line := _river_line(s)
	var dry_at := _dry_spot(s, line)
	print("WATER line=%s dry=%s" % [line, dry_at])
	if line.is_empty():
		push_error("no river line found")
		quit(1)
		return
	for t: Vector2i in line:
		s.place_channel(t)
	var end: Vector2i = line[line.size() - 1]
	var farm := _farm_spot(s, end, line[0])
	if farm.x >= 0:
		s.place_building_instant("farm", farm)
	if dry_at.x >= 0:
		for i in 4:
			s.place_channel(dry_at + Vector2i(i, 0))
	var well := _well_spot(s, line)
	if well.x >= 0:
		s.place_building_instant("well", well)
	var blight := _blight_patch(s, line[0])
	print("WATER blight=%s well=%s" % [blight, well])
	for t: Vector2i in blight:
		s.set_blighted(t, true)
	s.step_hours(24)  # one daily pass, as a normal day would; the fouling front also travels downstream
	var fouled := 0
	for i in s.map.fouled.size():
		fouled += s.map.fouled[i]
	print("WATER fouled tiles=%d" % fouled)
	var mid: Vector2 = (Vector2(line[0]) + Vector2(end)) / 2.0
	if dry_at.x >= 0:
		mid = (mid + Vector2(dry_at)) / 2.0
	if not blight.is_empty():
		mid = (mid + Vector2(blight[0])) / 2.0
	var cam: CameraController = main.get_node("Camera")
	cam.position = (mid + Vector2(0.5, 0.5)) * T
	cam.set_zoom_step(3)
	var model: HudModel = main.hud_model
	for pair in [[false, "/tmp/hv_water_off.png"], [true, "/tmp/hv_water_on.png"]]:
		if model.overlay_on("water") != pair[0]:
			model.toggle_overlay("water")
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(pair[1])
	quit()


## 8 channel tiles in a straight line, the first beside river water, all diggable.
func _river_line(s: Settlement) -> Array[Vector2i]:
	for p: Vector2i in s.map.river_path:
		for d in DIRS:
			var out: Array[Vector2i] = []
			for k in range(1, 9):
				var t := p + d * k
				if not s.can_place_channel(t)["ok"]:
					break
				out.append(t)
			if out.size() == 8 and s.map.terrain_id_at(p.x, p.y) == "water" and _dist_to_water(s, out[7]) > 3:
				return out
	return []


func _dist_to_water(s: Settlement, t: Vector2i) -> int:
	var best := 99
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var p := t + Vector2i(dx, dy)
			if MapState.in_bounds(p.x, p.y) and s.map.terrain_id_at(p.x, p.y) == "water":
				best = mini(best, maxi(absi(dx), absi(dy)))
	return best


## A 4-tile horizontal stretch far from water and from the first line, so it stays dry.
func _dry_spot(s: Settlement, line: Array[Vector2i]) -> Vector2i:
	if line.is_empty():
		return Vector2i(-1, -1)
	var c: Vector2i = line[4]
	for r in range(4, 14):
		for dy in [-r, r]:
			for dx in range(-r, r + 1):
				var o := c + Vector2i(dx, dy)
				var ok := true
				for i in 4:
					var t := o + Vector2i(i, 0)
					if not s.can_place_channel(t)["ok"] or _dist_to_water(s, t) <= 3 or _near_line(t, line):
						ok = false
						break
				if ok:
					return o
	return Vector2i(-1, -1)


func _near_line(t: Vector2i, line: Array[Vector2i]) -> bool:
	for l in line:
		if maxi(absi(l.x - t.x), absi(l.y - t.y)) <= 3:
			return true
	return false


## A farm site a couple of tiles past the channel's far end.
func _farm_spot(s: Settlement, end: Vector2i, start: Vector2i) -> Vector2i:
	var d := end - start
	d = Vector2i(signi(d.x), signi(d.y))
	for k in range(1, 4):
		for off in [Vector2i.ZERO, Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var t: Vector2i = end + d * k + off
			if s.can_place("farm", t, true)["ok"]:
				return t
	return Vector2i(-1, -1)


## A 2x2 blight patch on land beside the river, a few river tiles upstream of the channel's first tile.
func _blight_patch(s: Settlement, first: Vector2i) -> Array[Vector2i]:
	var path := s.map.river_path
	var at := 0
	var best := 9999
	for i in path.size():
		var d := absi(path[i].x - first.x) + absi(path[i].y - first.y)
		if d < best:
			best = d
			at = i
	for i in range(maxi(at - 6, 0), maxi(at - 1, 0) + 1):
		for dir in DIRS:
			var o: Vector2i = path[i]
			while MapState.in_bounds(o.x, o.y) and s.map.terrain_id_at(o.x, o.y) == "water":
				o += dir  # first land tile past the river's edge, so the patch touches the water (a fouling source)
			var out: Array[Vector2i] = []
			for q in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var t: Vector2i = o + q
				if MapState.in_bounds(t.x, t.y) and s.map.terrain_id_at(t.x, t.y) != "water":
					out.append(t)
			if out.size() == 4 and MapState.in_bounds(o.x, o.y):
				return out
	return []


## A wet land tile next to the channel line that can take a Well.
func _well_spot(s: Settlement, line: Array[Vector2i]) -> Vector2i:
	for l in line:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var t := l + Vector2i(dx, dy)
				if MapState.in_bounds(t.x, t.y) and s.can_place("well", t, true)["ok"]:
					return t
	return Vector2i(-1, -1)
