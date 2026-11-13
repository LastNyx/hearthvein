class_name ProductionSystem
extends SimSystem
## Production (design.md sections 8 and 21). A building with a recipe makes its recipe amounts per worker per
## work day. Only workers who are at work count (WalkerSystem.is_at_work), pro-rated over time: a work day is the
## 06:00-18:00 shift, so a worker standing at the door for the whole shift makes exactly the recipe amount and the
## walk to work costs a little. Output goes to the building's door buffer (cap from LogisticsDef); a full buffer
## stops production and sets Building.halt = "door_full" (events production_halted / production_resumed).
## Recipes with inputs eat from the input buffer that haulers fill; an empty one halts with "no_input".
## A building with fells_forest (Woodcutter) turns the nearest forest tile in its radius into a stump per
## LogisticsDef.units_per_felled_tile produced; no forest left = halt "no_forest".
##
## Modifiers: `modifiers` is a list of Callables (settlement, building) -> float. Their product multiplies output
## (and input use). Later tickets append here (tiers, Spirit, health, Dimming); nothing else needs to change.

var modifiers: Array[Callable] = []
var _felled_acc: Dictionary = {}  # building id -> units made since the last felled tile


func on_seconds(s: Settlement, seconds: float) -> void:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null or s.registry.logistics == null:
		return
	var shift := float(WalkerSystem.WORK_END_HOUR - WalkerSystem.WORK_START_HOUR) * GameClock.REAL_SECONDS_PER_HOUR
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.door_buffer == null or b.paused:
			continue
		_produce(s, ws, b, seconds / shift)


## Multiplier of every modifier for one building.
func multiplier(s: Settlement, b: Building) -> float:
	var m := 1.0
	for f in modifiers:
		m *= float(f.call(s, b))
	return m


func _produce(s: Settlement, ws: WalkerSystem, b: Building, shift_part: float) -> void:
	var recipe := b.def.recipe
	var first_out: String = recipe.outputs.keys()[0]
	if b.door_buffer.free_for(first_out) <= Inventory.EPS:
		_set_halt(s, b, "door_full")
		return
	var workers := 0
	for cid in ws.workers_at(b.id):
		if (s.citizens[cid] as Citizen).job_kind == Citizen.JOB_WORK:
			workers += 1
	var forest: Vector2i = Vector2i(-1, -1)
	if b.def.fells_forest:
		forest = nearest_forest(s, b)
		if forest.x < 0:
			_set_halt(s, b, "no_forest")
			return
	if workers == 0:
		_set_halt(s, b, "")
		return
	var f := float(workers) * shift_part * multiplier(s, b)  # worker-days of work done this tick
	for g in recipe.inputs:
		f = minf(f, b.input_buffer.amount_of(g) / float(recipe.inputs[g])) if b.input_buffer != null else 0.0
	if f <= Inventory.EPS:
		_set_halt(s, b, "no_input" if not recipe.inputs.is_empty() else "")
		return
	var out_total := 0.0
	for g in recipe.outputs:
		out_total += float(recipe.outputs[g]) * f
	f *= minf(1.0, b.door_buffer.free_for(first_out) / out_total)  # never overfill the buffer
	_set_halt(s, b, "")
	for g in recipe.inputs:
		b.input_buffer.remove(g, float(recipe.inputs[g]) * f)
	var made := 0.0
	for g in recipe.outputs:
		made += b.door_buffer.add(g, float(recipe.outputs[g]) * f)
	if b.def.fells_forest:
		_fell(s, b, made)
	if b.door_buffer.free_for(first_out) <= Inventory.EPS:
		_set_halt(s, b, "door_full")


func _fell(s: Settlement, b: Building, made: float) -> void:
	var per := s.registry.logistics.units_per_felled_tile
	var acc: float = _felled_acc.get(b.id, 0.0) + made
	while acc >= per:
		var t := nearest_forest(s, b)
		if t.x < 0:
			acc = 0.0
			break
		s.set_terrain(t, "stump")
		acc -= per
	_felled_acc[b.id] = acc


func _set_halt(s: Settlement, b: Building, why: String) -> void:
	if b.halt == why:
		return
	b.halt = why
	s.events.emit("production_halted" if why != "" else "production_resumed", {"id": b.id, "why": why})


## Nearest forest tile within the building's placement radius (same circle as the placement rule), measured from
## the closest footprint tile; ties go to the lower y then lower x. (-1, -1) when there is none.
static func nearest_forest(s: Settlement, b: Building) -> Vector2i:
	var r := b.def.placement_radius
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for ft in b.tiles():
		for y in range(ft.y - r, ft.y + r + 1):
			for x in range(ft.x - r, ft.x + r + 1):
				var d := (x - ft.x) * (x - ft.x) + (y - ft.y) * (y - ft.y)
				if d > r * r or not MapState.in_bounds(x, y) or s.map.terrain_id_at(x, y) != "forest":
					continue
				if d < best_d or (d == best_d and (y < best.y or (y == best.y and x < best.x))):
					best = Vector2i(x, y)
					best_d = d
	return best
