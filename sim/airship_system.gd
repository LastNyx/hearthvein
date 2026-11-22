class_name AirshipSystem
extends ManifestBase
## Airship Dock freight and survey flights (design.md sections 4, 8 and 17, ticket 38).
##
## Freight: every finished, staffed Airship Dock (at least one citizen working there) in an owned region is a node of one
## air network; no track is needed. Once a day, after the rail manifests, the same surplus -> need matching as the rail
## (ManifestBase) runs between the docks' regions, each dock sending at most LogisticsDef.airship_capacity units a day.
## A trip takes (straight-line tiles between the dock centres) / LogisticsDef.airship_speed hours. Goods already on
## their way to a region, by rail or by air, count as stocked there, so a rail-linked pair is served by rail first and
## the air only moves the need that is left. Ships never take goods to a region without a staffed dock.
##
## Islands (ticket 70): a sky-layer dock is its own freight node. ManifestBase._region keys every sky-layer building by
## region + MapState.REGION_COUNT, so an island dock has its own stock and demand table (the island's buildings), apart
## from the ground dock under it, and trades with any dock; its flight distance is that of its position. Rail never
## reaches it (rail depots are ground only). A still island's dock is left out of the manifests.
##
## Survey: survey_region(r) from a staffed, idle dock starts a flight over a locked region whose reward is not yet
## revealed; RegionsDef.survey_days later the reward is revealed for good. Design section 4 says reward markers are shown
## on every locked region, so the marker (type) stays visible; what a survey reveals is the exact detail (is_revealed,
## HudModel.reward_detail: yield factor, gold amount, regrow speed ...). An owned region is always revealed.

const SAVE_KEY := "airship"

## Regions whose reward detail has been revealed by a survey (region -> true). Owned regions count without an entry.
var _revealed: Dictionary = {}
## Flights in progress: {dock (building id), region, start (hour), done (hour)}. One per dock.
var _surveys: Array = []


func _init() -> void:
	sent_event = "airship_sent"
	arrived_event = "airship_arrived"


func save_state() -> Dictionary:
	var surveys := []
	for sv: Dictionary in _surveys:
		surveys.append({"dock": sv["dock"], "region": sv["region"], "start": sv["start"], "done": sv["done"]})
	return {"ships": _save_ships(), "revealed": _revealed.keys(), "surveys": surveys}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	_load_ships(d["ships"])
	_revealed = {}
	for r in d["revealed"]:
		_revealed[int(r)] = true
	_surveys.clear()
	for e: Dictionary in d["surveys"]:
		_surveys.append({"dock": int(e["dock"]), "region": int(e["region"]), "start": float(e["start"]),
			"done": float(e["done"])})


# ---------------------------------------------------------------- freight: renderer API

## Airships in flight: [{from_dock, to_dock, goods, depart_hour, arrive_hour, progress 0..1, from_pos, to_pos, pos}].
## Positions are in tile units (the dock footprint centres, Vector2); pos is the airship now, straight between them.
## progress is 1.0 while a shipment waits to unload.
func shipments(s: Settlement) -> Array:
	var out := []
	for i in _ships.size():
		var sh: Dictionary = _ships[i]
		var a := _dock_pos(s, int(sh["from"]))
		var b := _dock_pos(s, int(sh["to"]), a)
		if not s.buildings.has(int(sh["from"])):
			a = b
		var p := ship_progress(s, i)
		out.append({"from_dock": sh["from"], "to_dock": sh["to"], "goods": (sh["goods"] as Dictionary).duplicate(),
			"depart_hour": float(sh["depart"]), "arrive_hour": float(sh["arrive"]), "progress": p,
			"from_pos": a, "to_pos": b, "pos": a.lerp(b, p)})
	return out


func ship_count() -> int:
	return _ships.size()


func ship_progress(s: Settlement, i: int) -> float:
	var sh: Dictionary = _ships[i]
	var now := float(s.clock.total_hours) + s._hour_acc / GameClock.REAL_SECONDS_PER_HOUR
	var span := maxf(float(sh["arrive"]) - float(sh["depart"]), 0.000001)
	return clampf((now - float(sh["depart"])) / span, 0.0, 1.0)


## Allocation-free ends of shipment i in tile units (what shipments() reports as from_pos / to_pos), for the renderer.
func ship_from(s: Settlement, i: int) -> Vector2:
	var sh: Dictionary = _ships[i]
	var b := _dock_pos(s, int(sh["to"]))
	return _dock_pos(s, int(sh["from"]), b)


func ship_to(s: Settlement, i: int) -> Vector2:
	var sh: Dictionary = _ships[i]
	return _dock_pos(s, int(sh["to"]), _dock_pos(s, int(sh["from"])))


## Centre of a dock's footprint in tile units; `fallback` when the dock is gone.
func _dock_pos(s: Settlement, id: int, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var b: Building = s.buildings.get(id)
	if b == null:
		return fallback
	return Vector2(b.origin) + Vector2(b.def.size) * 0.5


# ---------------------------------------------------------------- arrivals (hourly) and surveys

func on_hour(s: Settlement) -> void:
	_land_ships(s, func(_from: int, _to: int) -> bool: return true)  # no track to break
	_chart_surveys(s)
	_finish_surveys(s)


## Star charts (ticket 142): an hour with a fully crewed Observatory counts as 1 + its bonus hours of flight, so every
## flight out comes due that much sooner. The due hour is saved, so nothing else needs to be stored.
func _chart_surveys(s: Settlement) -> void:
	var bonus := survey_speed_bonus(s)
	if bonus <= 0.0:
		return
	for sv: Dictionary in _surveys:
		sv["done"] = float(sv["done"]) - bonus


## The best BuildingDef.survey_speed_bonus among finished, unpaused buildings (not on a still island, not in gloom)
## that have every night slot staffed; 0 when none does.
static func survey_speed_bonus(s: Settlement) -> float:
	var best := 0.0
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.def.survey_speed_bonus <= best or b.site or b.paused or IslandSystem.is_still_building(s, b):
			continue
		if GloomSystem.building_in_gloom(s, b):
			continue
		var slots := ProductionSystem.night_slots_for(s, b)
		if slots > 0 and SpiritSystem.night_workers(s, b) >= slots:
			best = b.def.survey_speed_bonus
	return best


func _finish_surveys(s: Settlement) -> void:
	if _surveys.is_empty():
		return
	var keep := []
	for sv: Dictionary in _surveys:
		if not s.buildings.has(int(sv["dock"])):
			continue  # the dock was demolished: the flight is called off
		if float(s.clock.total_hours) + 0.000001 < float(sv["done"]):
			keep.append(sv)
			continue
		var r := int(sv["region"])
		_revealed[r] = true
		s.events.emit("region_surveyed", {"region": r, "dock": sv["dock"], "reward": s.map.get_region_reward(r)})
	_surveys = keep


## Whether region r's reward detail is known: owned, or surveyed.
func is_revealed(s: Settlement, r: int) -> bool:
	return r >= 0 and r < MapState.REGION_COUNT and (_revealed.has(r) or s.map.is_region_owned(r))


## The survey in progress over region r: {dock, region, start, done} or empty.
func survey_of(r: int) -> Dictionary:
	for sv: Dictionary in _surveys:
		if int(sv["region"]) == r:
			return sv
	return {}


## All flights in progress, as copies.
func surveys() -> Array:
	var out := []
	for sv: Dictionary in _surveys:
		out.append((sv as Dictionary).duplicate())
	return out


## Why survey_region(r) would fail, "" when it can start: "unknown", "owned", "no_reward", "revealed", "surveying"
## (a flight is already out), "no_dock" (no staffed dock) or "busy" (every staffed dock is flying).
func survey_refusal(s: Settlement, r: int) -> String:
	if r < 0 or r >= MapState.REGION_COUNT:
		return "unknown"
	if s.map.is_region_owned(r):
		return "owned"
	if s.map.get_region_reward(r) == "":
		return "no_reward"
	if _revealed.has(r):
		return "revealed"
	if not survey_of(r).is_empty():
		return "surveying"
	var docks := _staffed_docks(s)
	if docks.is_empty():
		return "no_dock"
	return "" if not _idle_docks(docks).is_empty() else "busy"


## Sends the first idle staffed dock (lowest id) over region r. False when survey_refusal says no.
func start_survey(s: Settlement, r: int) -> bool:
	if survey_refusal(s, r) != "":
		return false
	var dock: int = _idle_docks(_staffed_docks(s))[0]
	var now := float(s.clock.total_hours)
	var days := s.registry.regions.survey_days if s.registry.regions != null else 1
	_surveys.append({"dock": dock, "region": r, "start": now, "done": now + float(days) * GameClock.HOURS_PER_DAY})
	s.events.emit("survey_started", {"region": r, "dock": dock})
	return true


func _idle_docks(docks: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for d in docks:
		var busy := false
		for sv: Dictionary in _surveys:
			if int(sv["dock"]) == d:
				busy = true
		if not busy:
			out.append(d)
	return out


## True when at least one finished, staffed dock stands (the HUD offers surveys then).
func has_staffed_dock(s: Settlement) -> bool:
	return not _staffed_docks(s).is_empty()


# ---------------------------------------------------------------- freight (daily)

func on_day(s: Settlement) -> void:
	var lg := s.registry.logistics
	if lg == null or lg.airship_capacity <= 0.0 or lg.airship_speed <= 0.0:
		return
	var docks := _staffed_docks(s)
	if docks.size() < 2:
		return
	var table := _region_table(s)
	_count_incoming(s, table)
	var food_goods := GrowthSystem.food_goods(s.registry)
	var keys := {}
	for d in docks:
		for k in table["demand"].get(_region(s, s.buildings[d]), {}):
			keys[k] = true
	var key_list: Array = keys.keys()
	key_list.sort()
	var sent := {}
	var pairs := {}
	for k: String in key_list:
		_plan_key(s, lg, table, docks, k, food_goods, sent, pairs, lg.airship_capacity)
	_dispatch(s, pairs, float(s.clock.total_hours), func(from: int, to: int) -> float:
		var dist := _dock_pos(s, from).distance_to(_dock_pos(s, to))
		return maxf(dist / lg.airship_speed, 0.01))


## Goods already on their way to a region (rail trains, earlier airships) count as stock there.
func _count_incoming(s: Settlement, table: Dictionary) -> void:
	var food := {}
	for g in GrowthSystem.food_goods(s.registry):
		food[g] = true
	var rail := s.get_system(RailManifestSystem) as RailManifestSystem
	for src: ManifestBase in [rail, self]:
		if src == null:
			continue
		var inc := src.incoming(s)
		for r in inc:
			var st: Dictionary = table["stock"].get(r, {})
			for g: String in inc[r]:
				var k := FOOD if food.has(g) else g
				st[k] = float(st.get(k, 0.0)) + float(inc[r][g])
			table["stock"][r] = st


## Finished docks in owned regions with at least one citizen working there, ids ascending.
func _staffed_docks(s: Settlement) -> Array[int]:
	var docks := {}
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.def.airship_dock and not b.site and s.map.is_region_owned(_real_region(s, b)) \
				and not IslandSystem.is_still_building(s, b):  # a still island's dock neither sends nor receives
			docks[id] = false
	if docks.is_empty():
		return []
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK and docks.has(c.job_id):
			docks[c.job_id] = true
	var out: Array[int] = []
	for id in docks:
		if docks[id]:
			out.append(id)
	out.sort()
	return out
