class_name PlanetHealthSystem
extends SimSystem
## Planet health (design.md section 13, D30): one map-wide meter 0-100, starts at PlanetDef.start, changes once a day
## by the sum of daily_delta()'s sources (numbers: data/planet/planet.tres and BuildingDef.health_per_day). A year is
## 32 days, so the table's rates give the "4-5% a year" of the rough check. Read it through Settlement.planet_health().
##
## Sources: blighted tiles, forest tiles, every finished unpaused building with health_per_day != 0 that works (it has
## at least one assigned worker, or no worker slots at all, like a Park), plus `extra_sources` Callables
## (settlement) -> float for things not built yet (Great Dimming days, ticket 45).
##
## Effects: vein_factor() = vein_base + health / vein_divisor, applied to vein extractors by vein_modifier (a
## ProductionSystem modifier registered in Settlement.add_default_systems). Each season below dieback_below,
## (60 - health) / 10 percent of forest tiles (rounded to a whole tile) become dieback_terrain, chosen by a seeded
## hash of (map seed, season number, tile). Spirit grief: grief_factor (hook "planet_grief"). Dimming length (15) and
## the Heartroot Tap threshold (44) read planet_health().

const SAVE_KEY := "planet_health"

var value: float = -1.0
var extra_sources: Array[Callable] = []
## Health at the start of each of the last trend_days days, oldest first (see trend()).
var _history: Array[float] = []


func save_state() -> Dictionary:
	return {"value": value, "history": _history.duplicate()}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	value = float(d["value"])
	_history.assign(d["history"])


func current(s: Settlement) -> float:
	if value < 0.0:
		value = s.registry.planet.start
	return value


## Change over the last trend_days days (a year); over the time so far while the game is younger.
func trend(s: Settlement) -> float:
	if _history.is_empty():
		return 0.0
	return current(s) - _history[0]


## Is this building contributing to health right now (works, or needs no workers)? A building with Lumen upkeep
## that could not pay it for the day is not working (ticket 27).
static func is_working(s: Settlement, b: Building, staffed: Dictionary = {}) -> bool:
	if b.site or b.paused or b.def.health_per_day == 0.0:
		return false
	if b.def.upkeep_lumen > 0.0:
		var us := s.get_system(UpkeepSystem) as UpkeepSystem
		if us != null and not us.is_paid(b.id):
			return false
	if b.def.worker_slots <= 0:
		return true
	if not staffed.is_empty():
		return staffed.has(b.id)
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			return true
	return false


## Vein Mender (design.md section 17): the lowest drain_factor among the working menders within drain_radius of the
## extractor (footprint gap), 1.0 when none reaches it. Menders never stack.
static func drain_factor_for(b: Building, menders: Array[Building]) -> float:
	var f := 1.0
	for m in menders:
		if m.layer == b.layer and Building.footprint_gap(m, b) <= m.def.drain_radius:
			f = minf(f, m.def.drain_factor)
	return f


## {"blight": x, "forest": x, "buildings": x, "extra": x, "total": x} for today (percent points).
func daily_breakdown(s: Settlement) -> Dictionary:
	var pd := s.registry.planet
	var fi := s.map.terrain_index("forest")
	var forest := s.map.terrain.count(fi) if fi >= 0 else 0
	var staffed := {}  # building ids with at least one working citizen, one pass instead of one per building
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_kind == Citizen.JOB_WORK:
			staffed[c.job_id] = true
	var bld := 0.0
	var working: Array[Building] = []
	var menders: Array[Building] = []
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if is_working(s, b, staffed):
			working.append(b)
			if b.def.drain_radius > 0 and b.layer == Building.LAYER_GROUND:
				menders.append(b)
	for b in working:
		var hp := b.def.health_per_day
		if hp < 0.0 and b.def.vein_extractor:
			hp *= drain_factor_for(b, menders)
		bld += hp
	var extra := 0.0
	for f in extra_sources:
		extra += float(f.call(s))
	var blight := float(BlightSystem.count(s)) * pd.per_blight_tile
	var forest_gain := float(forest) * pd.per_forest_tile
	return {"blight": blight, "forest": forest_gain, "buildings": bld, "extra": extra,
			"total": blight + forest_gain + bld + extra}


func daily_delta(s: Settlement) -> float:
	return daily_breakdown(s)["total"]


func on_day(s: Settlement) -> void:
	var cur := current(s)
	_history.append(cur)
	while _history.size() > s.registry.planet.trend_days:
		_history.remove_at(0)
	value = clampf(cur + daily_delta(s), 0.0, 100.0)


func on_season(s: Settlement) -> void:
	var pd := s.registry.planet
	var h := current(s)
	if h >= pd.dieback_below:
		return
	var pct := (pd.dieback_below - h) / pd.dieback_divisor
	var fi := s.map.terrain_index("forest")
	var keys: Array[int] = []
	var season := s.clock.total_days() / GameClock.DAYS_PER_SEASON
	for i in s.map.terrain.size():
		if s.map.terrain[i] == fi:
			keys.append(_hash(s.map.seed_used, season, i % MapState.WIDTH, i / MapState.WIDTH) * 16384 + i)
	var n := mini(roundi(float(keys.size()) * pct / 100.0), keys.size())
	if n <= 0:
		return
	keys.sort()
	for k in n:
		var i := keys[k] % 16384
		s.set_terrain(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH), pd.dieback_terrain)
	s.events.emit("forest_dieback", {"tiles": n, "health": h})


static func _hash(seed: int, season: int, x: int, y: int) -> int:
	var h := ((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791) ^ (season * 2654435761)) & 0x7fffffff
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0x7fffffff
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0x7fffffff
	return h ^ (h >> 15)


## Vein yield factor at a health value.
static func vein_factor_at(s: Settlement, health: float) -> float:
	var pd := s.registry.planet
	return pd.vein_base + health / pd.vein_divisor


## ProductionSystem modifier: vein extractors only.
static func vein_modifier(s: Settlement, b: Building) -> float:
	return vein_factor_at(s, s.planet_health()) if b.def.vein_extractor else 1.0


## Spirit hook "planet_grief": -(60 - health) / 6 below 60, at most grief_max.
static func grief_factor(s: Settlement) -> float:
	var sd := s.registry.spirit
	var h := s.planet_health()
	if h >= sd.grief_below:
		return 0.0
	return -minf((sd.grief_below - h) / sd.grief_divisor, sd.grief_max)
