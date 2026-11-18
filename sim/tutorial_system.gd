class_name TutorialSystem
extends SimSystem
## Guided goals (D59a, D66, D69, ticket 82). The goal list is data (data/tutorial/*.tres, TutorialDef); this system
## knows how to check each kind. Off unless Settlement.new_game(..., tutorial = true) starts it. One goal is current;
## a goal that is already met when it becomes current completes at once, so a player who is ahead sees no stale goal.
##
## Checked on the events that can change a goal (building_completed, road_changed, building_connection_changed,
## citizen_added / born / immigrated, dimming_forecast, dimming_ended; wired in Settlement.add_default_systems) and
## once per hour (stock and instant placements have no event).
##
## Events: tutorial_goal_completed {id, index} per goal, tutorial_finished {skipped} once (after the last goal, or from
## skip()). An inactive tutorial (never started, skipped, finished, or an old save) emits nothing.
##
## The Dimming goal needs the forecast and then stock: Lumen (raw plus cells at PlanetDef.lumen_per_cell) of at least
## citizens x DimmingSystem.light_per_citizen x length, and food of at least citizens x GrowthDef.food_per_citizen x
## length. stock_targets() gives the numbers for the UI. If the Dimming starts before the stock is ready the goal is
## dropped (too late to prepare) instead of blocking the last one.

const SAVE_KEY := "tutorial"

var _active: bool = false
var _finished: bool = false
var _index: int = 0
var _done: Array[String] = []
var _camera_moved: bool = false
var _ended_seen: bool = false
## The goal rows in order (data, not saved; Settlement.add_default_systems hands them over).
var _goals: Array[TutorialDef] = []


func setup(goals: Array[TutorialDef]) -> void:
	_goals = goals


func save_state() -> Dictionary:
	return {"active": _active, "finished": _finished, "index": _index, "done": _done.duplicate(),
			"camera_moved": _camera_moved, "ended_seen": _ended_seen}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_active = bool(d.get("active", false))
	_finished = bool(d.get("finished", false))
	_index = int(d.get("index", 0))
	_done.assign(d.get("done", []))
	_camera_moved = bool(d.get("camera_moved", false))
	_ended_seen = bool(d.get("ended_seen", false))


## The tutorial is running (started and not finished or skipped).
func is_active() -> bool:
	return _active


## It ran to the end, was skipped, or the save is from before the tutorial (D69).
func is_finished() -> bool:
	return _finished


## 0-based index of the current goal; the goal count once finished.
func goal_index() -> int:
	return _index


## Ids of the goals completed so far, in order.
func done_ids() -> Array[String]:
	return _done


func is_done(goal_id: String) -> bool:
	return _done.has(goal_id)


## The current goal's data row, or null when the tutorial is not active.
func current_goal() -> TutorialDef:
	if not _active:
		return null
	var goals := _goals
	return goals[_index] if _index < goals.size() else null


## True while the tutorial is active and its current goal covers the hint `hint_id` (TutorialDef.covers_hints): the
## hint system (ticket 84) stays quiet, the goal panel already says it.
func covers_hint(hint_id: String) -> bool:
	var g := current_goal()
	return g != null and g.covers_hints.has(hint_id)


## Turns the tutorial on (new game option) and completes whatever is already met.
func start(s: Settlement) -> void:
	_active = not _goals.is_empty()
	_finished = false
	_index = 0
	_done.clear()
	_check(s)


## Ends the tutorial at once (the skip button).
func skip(s: Settlement) -> void:
	if not _active:
		return
	_active = false
	_finished = true
	s.events.emit("tutorial_finished", {"skipped": true})


## The UI moved the camera (goal 1).
func report_camera_moved(s: Settlement) -> void:
	if _camera_moved:
		return
	_camera_moved = true
	_check(s)


## Lumen and food the coming Dimming needs and what the settlement holds: {ready (a forecast exists), length,
## lumen_target, lumen_have, food_target, food_have, enough}. Targets are 0 until a Dimming is forecast.
func stock_targets(s: Settlement) -> Dictionary:
	var st := (s.get_system(DimmingSystem) as DimmingSystem).status(s)
	var length := int(st.get("length", 0)) if st["state"] != "none" else 0
	var pop := float(s.citizens.size())
	var lumen_target := pop * DimmingSystem.light_per_citizen(s) * length
	var food_target := pop * s.registry.growth.food_per_citizen * length
	var lumen_have := 0.0
	var food_have := 0.0
	var food_goods := GrowthSystem.food_goods(s.registry)
	for b: Building in s.buildings.values():
		if b.inventory == null:
			continue
		lumen_have += b.inventory.amount_of("lumen") + b.inventory.amount_of("lumen_cells") * s.registry.planet.lumen_per_cell
		for g in food_goods:
			food_have += b.inventory.amount_of(g)
	return {"ready": st["state"] == "forecast", "length": length, "lumen_target": lumen_target,
			"lumen_have": lumen_have, "food_target": food_target, "food_have": food_have,
			"enough": lumen_have + Inventory.EPS >= lumen_target and food_have + Inventory.EPS >= food_target}


func on_hour(s: Settlement) -> void:
	_check(s)


## EventBus handler (the Settlement is bound as the last argument).
func on_event(e: Dictionary, s: Settlement) -> void:
	if e["kind"] == "dimming_ended":
		_ended_seen = true
	_check(s)


func _check(s: Settlement) -> void:
	while _active and _index < _goals.size():
		var g := _goals[_index]
		if not _met(g, s):
			return
		_done.append(g.id)
		_index += 1
		s.events.emit("tutorial_goal_completed", {"id": g.id, "index": _index - 1})
	if _active:
		_active = false
		_finished = true
		s.events.emit("tutorial_finished", {"skipped": false})


func _met(g: TutorialDef, s: Settlement) -> bool:
	match g.kind:
		"camera_moved":
			return _camera_moved
		"road_to_hearth":
			return s.connected_road_count() >= 2
		"built":
			return _count(s, g.def_id, false) >= g.amount
		"built_connected":
			return _count(s, g.def_id, true) >= g.amount
		"population":
			return s.citizens.size() >= g.amount
		"dimming_stock":
			var state: String = (s.get_system(DimmingSystem) as DimmingSystem).status(s)["state"]
			if state == "active":
				return true
			return state == "forecast" and bool(stock_targets(s)["enough"])
		"dimming_ended":
			return _ended_seen
	return false


func _count(s: Settlement, def_id: String, connected: bool) -> int:
	var n := 0
	for b: Building in s.buildings.values():
		if b.def.id == def_id and not b.site and (b.connected or not connected):
			n += 1
	return n
