extends SceneTree
## Early-game probe (ticket 118): godot --headless --path . -s tools/early_probe.gd [-- seed]
## The balance bot only places producers within idle hands, so it never feels "not enough workers" or "not enough
## wood". This plays the first days like an eager player: a new game as the player starts it (06:00), then the same
## fixed opening placed in order, each the hour its wood is in stock. Prints one row per in-game day 1-8 (people, beds,
## slots wanted vs filled, wood and stone stock, sites waiting on goods vs on builders), the hour each opening
## building finished, and PASS/FAIL for the targets. A tool, not a test (not in the suite). Exit code 0 unless it throws.

const L := preload("res://tools/shot_layout.gd")

const DEFAULT_SEED := 42
const DAYS := 8
const SEARCH_RADIUS := 20
## The eager player's opening, in order: placed as soon as the wood for the next one is in stock.
const OPENING: Array[String] = ["woodcutter", "forager", "tent", "tent", "lumen_tap", "storehouse", "woodcutter", "forager", "tent"]
## Placed (in order) once Village unlocks; the probe stops at day 8 whatever happened.
const VILLAGE: Array[String] = ["quarry", "builders_yard", "farm"]
const DONE_BY_DAY := 3
const WOOD_GAP_HOURS := 6
const WOOD_GAP_DAYS := 4

var s: Settlement
var _offsets: Array[Vector2i] = []
var _bad := {}  # tile -> true where a placement was taken back
var _placed: Array[int] = []  # opening building ids, in order
var _placed_at := {}  # building id -> game hour placed (from the start)
var _done_at := {}  # building id -> game hour finished
var _start_hour: int = 0
var _next: int = 0  # index into OPENING + VILLAGE
var _wood_run: int = 0
var _wood_run_max: int = 0
var _unstaffed: Array[String] = []
var _verbose: bool = false
var _seen_goods := {}
var _seen_work := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 and args[0].is_valid_int() else DEFAULT_SEED
	_verbose = args.has("v")
	var reg := DataRegistry.new()
	reg.load_all()
	s = Settlement.new_game(seed_value, reg)
	s.clock.total_hours = Settlement.PLAYER_START_HOUR  # the player path (Main.start_new_game)
	_start_hour = s.clock.total_hours
	_make_offsets()
	s.events.subscribe("building_completed", _on_built)
	print("early_probe: seed ", seed_value, ", start 06:00, ", s.citizens.size(), " people, ", s.beds_total(), " beds")
	print("day | people beds | producers  haulers  builders (filled/wanted) | wood stone | sites: goods builders | opening done")
	var end_hour := DAYS * GameClock.HOURS_PER_DAY
	while s.clock.total_hours < end_hour:
		_place_next()
		s.step_hours(1)
		_sample()
		if s.clock.total_hours % GameClock.HOURS_PER_DAY == 0:
			_row()
	_report(seed_value)
	quit(0)


func _make_offsets() -> void:
	for dy in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			_offsets.append(Vector2i(dx, dy))
	_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := a.length_squared()
		var db := b.length_squared()
		if da != db:
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)


func _rel_hour() -> int:
	return s.clock.total_hours - _start_hour


func _on_built(entry: Dictionary) -> void:
	var data: Dictionary = entry["data"]
	_done_at[int(data.get("id", -1))] = _rel_hour()


## Goods in storage minus what open sites still need (a player does not promise the same wood twice).
func _free_wood() -> float:
	var have: float = float(s.totals().get("wood", 0.0))
	for b: Building in s.buildings.values():
		if b.site:
			var need := float(b.effective_cost().get("wood", 0.0))
			var got := b.input_buffer.amount_of("wood") if b.input_buffer != null else 0.0
			have -= maxf(need - got, 0.0)
	return have


func _place_next() -> void:
	var list: Array[String] = OPENING.duplicate()
	if s.era_current != "camp":
		list.append_array(VILLAGE)
	if _next >= list.size():
		return
	var id := list[_next]
	var def := s.registry.get_building(id)
	if def == null or not _unlocked(id):
		return
	if _free_wood() + 0.001 < float(def.cost.get("wood", 0)):
		return
	if float(s.totals().get("stone", 0.0)) + 0.001 < float(def.cost.get("stone", 0)):
		return
	var b := _place(id)
	if b == null:
		return
	if _next < OPENING.size():
		_placed.append(b.id)
	_placed_at[b.id] = _rel_hour()
	if _verbose:
		print("   h%d place %s #%d at %s (%d tiles from hearth) wood %d" % [_rel_hour(), id, b.id, b.origin, (b.origin - s.hearth.origin).length(), int(s.totals().get("wood", 0))])
	_next += 1


func _unlocked(id: String) -> bool:
	return s.is_unlocked(s.registry.get_building(id))


func _place(id: String) -> Building:
	var def := s.registry.get_building(id)
	var near := s.hearth.origin
	var order: Array = _offsets
	if def.fells_forest:
		var scored: Array = []
		for off in _offsets:
			# a player takes the nearest forest edge with a decent stand, not the densest wood across the map
			scored.append([minf(float(_forest_around(near + off, 4)), 12.0) - 1.5 * float(off.length()), off])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		order = scored.map(func(row: Array) -> Vector2i: return row[1])
	var pick := Vector2i(-9999, -9999)
	if def.placement_rule == "on_vein":
		var veins: Array[Vector2i] = []
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if s.map.terrain_id_at(x, y) == "lumen_vein" and s.map.is_region_owned(s.map.get_region(x, y)):
					veins.append(Vector2i(x, y))
		veins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - near).length_squared() < (b - near).length_squared())
		for t in veins:
			if not _bad.has(t) and s.can_place(id, t)["ok"] and _dry_path(Rect2i(t, def.size)):
				pick = t
				break
		order = []
	# A player keeps the walk short: of the first valid spots in order, take the one with the shortest road route to the Hearth.
	var checks := 0
	var best := 1.0e9
	for off: Vector2i in order:
		var t := near + off
		if _bad.has(t) or not s.can_place(id, t)["ok"]:
			continue
		if not _dry_path(Rect2i(t, def.size)):
			_bad[t] = true
			continue
		var score := float(_route_len(Rect2i(t, def.size))) + float(checks) * 0.2
		if score < best:
			best = score
			pick = t
		checks += 1
		if checks >= 30:
			break
	if pick.x <= -9999:
		return null
	var bid := s.place_building(id, pick)
	if bid < 0:
		return null
	var b: Building = s.buildings[bid]
	L.connect_road(s, b)
	if not b.connected:
		s.demolish(bid)
		_bad[pick] = true
		return null
	return b


## Tiles to walk along roads (existing plus the ones a new building would add) from the Hearth's road to the footprint.
func _route_len(fp: Rect2i) -> int:
	var road := {}
	for t in L._path(s, fp):
		road[t] = true
	var start := s.hearth.origin + Vector2i(s.hearth.def.size.x, 0)
	var seen := {start: 0}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		for d in L.DIRS:
			var n: Vector2i = c + d
			if fp.has_point(n):
				return int(seen[c]) + 1
			if seen.has(n) or not MapState.in_bounds(n.x, n.y):
				continue
			if road.has(n) or s.road_at(n) != Settlement.ROAD_NONE:
				seen[n] = int(seen[c]) + 1
				queue.append(n)
	return 999


## A road to the footprint that needs no bridge: a player early on does not pay wood for a bridge.
func _dry_path(fp: Rect2i) -> bool:
	var path := L._path(s, fp)
	if path.is_empty():
		return false
	for t in path:
		if not s.bridge_cost(t, Settlement.ROAD_DIRT).is_empty():
			return false
	return true


func _forest_around(c: Vector2i, r: int) -> int:
	var n := 0
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if MapState.in_bounds(x, y) and s.map.terrain_id_at(x, y) == "forest":
				n += 1
	return n


## Hourly: the wood-gap run and the staffing check.
func _sample() -> void:
	var rel := _rel_hour()
	var wood := float(s.totals().get("wood", 0.0))
	var waiting := false
	for b: Building in s.buildings.values():
		if b.site and not b.site_delivered() and not b.paused:
			var need := float(b.effective_cost().get("wood", 0.0))
			var got := b.input_buffer.amount_of("wood") if b.input_buffer != null else 0.0
			if got < need:
				waiting = true
	if rel <= WOOD_GAP_DAYS * GameClock.HOURS_PER_DAY and wood < 0.5 and waiting:
		_wood_run += 1
		_wood_run_max = maxi(_wood_run_max, _wood_run)
	else:
		_wood_run = 0
	if _verbose:
		for b: Building in s.buildings.values():
			if b.site and b.site_delivered() and not _seen_goods.has(b.id):
				_seen_goods[b.id] = true
				print("   h%d goods all in at %s #%d" % [rel, b.def.id, b.id])
	if _verbose:
		for b: Building in s.buildings.values():
			if b.site and b.build_work > 0.0 and not _seen_work.has(b.id):
				_seen_work[b.id] = true
				print("   h%d first work on %s #%d" % [rel, b.def.id, b.id])
	if _verbose and rel == 40:
		var ws := s.get_system(WalkerSystem) as WalkerSystem
		var cs := s.get_system(ConstructionSystem) as ConstructionSystem
		for b: Building in s.buildings.values():
			if b.site:
				print("   dbg %s #%d at %s door %s trip %.1fs ready %s halt '%s' paused %s prio %s" % [b.def.id, b.id, b.origin, ws.door_tile(b), cs._trip_seconds(s, ws, s.hearth, b), ConstructionSystem.is_ready(b), b.halt, b.paused, b.priority])
		print("   dbg hearth door ", ws.door_tile(s.hearth))
	if rel >= GameClock.HOURS_PER_DAY:
		var crew := {}
		for c: Citizen in s.citizens.values():
			if c.job_kind == Citizen.JOB_WORK:
				crew[c.job_id] = int(crew.get(c.job_id, 0)) + 1
		for bid in _placed:
			var b: Building = s.buildings.get(bid)
			if b == null or b.site or b.def.worker_slots <= 0 or rel - int(_done_at.get(bid, rel)) < 2:
				continue
			if int(crew.get(bid, 0)) < 1:
				var tag := "%s#%d@h%d" % [b.def.id, bid, rel]
				if not _unstaffed.has(tag):
					_unstaffed.append(tag)


func _row() -> void:
	var day := s.clock.total_days() - _start_hour / GameClock.HOURS_PER_DAY
	var crew := {}
	var haul := 0
	var build := 0
	for c: Citizen in s.citizens.values():
		match c.job_kind:
			Citizen.JOB_WORK:
				crew[c.job_id] = int(crew.get(c.job_id, 0)) + 1
			Citizen.JOB_HAUL:
				haul += 1
			Citizen.JOB_BUILD:
				build += 1
	var pw := 0
	var pf := 0
	var hw := 0
	var bw := 0
	var goods := 0
	var wait_builders := 0
	var ready := 0
	for b: Building in s.buildings.values():
		if b.site:
			if b.site_delivered():
				wait_builders += 1
				ready += 1
			else:
				goods += 1
			continue
		if b.paused or not b.connected:
			continue
		pw += b.effective_worker_slots(s.registry)
		pf += int(crew.get(b.id, 0))
		hw += b.def.hauler_slots
		bw += b.def.builder_slots
	var bwant := mini(bw, ready * s.registry.logistics.builder_crew)
	var done := 0
	for bid in _placed:
		if _done_at.has(bid):
			done += 1
	if _verbose:
		var rows: Array[String] = []
		for b: Building in s.buildings.values():
			rows.append("%s#%d%s %d/%d%s" % [b.def.id, b.id, "(site %.2f%s)" % [b.build_progress(), "" if b.site_delivered() else " goods"] if b.site else "", int(crew.get(b.id, 0)), b.effective_worker_slots(s.registry), ":" + b.halt if b.halt != "" else ""])
		print("     ", " | ".join(rows), " | idle ", s.idle_citizens().size(), " build ", build, " haul ", haul)
	var tot := s.totals()
	print("%3d | %5d %4d | %4d/%-4d %4d/%-4d %4d/%-4d | %4d %4d | %5d %8d | %d/%d" % [day, s.citizens.size(), s.beds_total(), pf, pw,
		haul, hw, build, bwant, int(tot.get("wood", 0)), int(tot.get("stone", 0)), goods, wait_builders, done, OPENING.size()])


func _report(seed_value: int) -> void:
	var line := "finished (hour from 06:00 start):"
	for i in _placed.size():
		var b: Building = s.buildings.get(_placed[i])
		var nm := b.def.id if b != null else "?"
		line += " %d.%s placed h%d done %s;" % [i + 1, nm, int(_placed_at.get(_placed[i], -1)),
			("h" + str(_done_at[_placed[i]]) if _done_at.has(_placed[i]) else "never")]
	print(line)
	var deadline := DONE_BY_DAY * GameClock.HOURS_PER_DAY - (_start_hour % GameClock.HOURS_PER_DAY)
	var all_done := _placed.size() == OPENING.size()
	var last := 0
	for bid in _placed:
		if not _done_at.has(bid):
			all_done = false
		else:
			last = maxi(last, int(_done_at[bid]))
	var ok1 := all_done and last <= deadline
	var ok2 := _unstaffed.is_empty()
	var ok3 := _wood_run_max <= WOOD_GAP_HOURS
	print("opening finished by end of day %d: %s (last done h%d, deadline h%d, placed %d/%d)" % [DONE_BY_DAY, "PASS" if ok1 else "FAIL", last, deadline, _placed.size(), OPENING.size()])
	print("every producer staffed from day 2: %s %s" % ["PASS" if ok2 else "FAIL", ", ".join(_unstaffed)])
	print("wood never 0 for over %d h in days 1-%d while a site waits: %s (longest %d h)" % [WOOD_GAP_HOURS, WOOD_GAP_DAYS, "PASS" if ok3 else "FAIL", _wood_run_max])
	print("early_probe seed %d: %s" % [seed_value, "PASS" if ok1 and ok2 and ok3 else "FAIL"])
