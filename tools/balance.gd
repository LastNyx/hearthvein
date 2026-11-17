extends SceneTree
## Headless balance run (ticket 47): godot --headless --path . -s tools/balance.gd [-- seed]
## A scripted "competent player" plays a settlement from the free start to the end of the Great Dimming (or 20 in-game
## years) through the normal Settlement commands only (place_building, place_road, buy_region; real hauling and
## construction, no instant placement). Once a day the bot reads the settlement, then places what it can afford.
## It prints the era timestamps (in-game year/day and the real time they take at 1x), planet health at every year end,
## each Dimming's length, the Skyheart, the Great Dimming and the campaign outcome. A run with no era change for 4 years
## prints the blocking gate parts and stops. A tool, not a test (not in the suite). Exit code 0 unless the script fails.
##
## The bot's data is at the top: SHARES (what share of the workforce each good's producers should hold), PRODUCERS
## (best building first), HOUSING, LANDMARKS and the RESERVE rules.

const L := preload("res://tools/shot_layout.gd")

const MAX_YEARS := 20
const STALL_YEARS := 4
const DEFAULT_SEED := 42

## Worker slots wanted per citizen for each good's producers (the bot builds the good that is furthest below its share).
const SHARES := {
	"food": 0.30, "materials": 0.22, "lumen": 0.07, "gold": 0.10, "planks": 0.04, "cut_stone": 0.05,
	"lumen_cells": 0.03, "tools": 0.03,
}
## Producer buildings per good, best first. The bot takes the first one that is unlocked, affordable and has room.
const PRODUCERS := {
	"food": ["bloom_orchard", "hydroponic_hall", "greenhouse", "farm", "fishing_dock", "forager"],
	"materials": ["quarry", "woodcutter"],
	"lumen": ["heartroot_tap", "lumen_reactor", "lumen_pump", "lumen_tap"],
	"gold": ["grand_bazaar", "market"],
	"planks": ["sawmill"],
	"cut_stone": ["mason"],
	"lumen_cells": ["refinery"],
	"tools": ["toolsmith"],
}
## Pause a good's producers above (per citizen, flat) stock; resume below 60% of it.
const THROTTLE := {"food": [6.0, 60.0], "lumen": [4.0, 150.0]}
## Stock above which a good stops being built for.
const STOCK_CAP := {"materials": 2500.0, "planks": 700.0, "cut_stone": 700.0, "lumen_cells": 700.0, "tools": 500.0}
## Housing, best first.
const HOUSING: Array[String] = ["lumen_arcology", "conduit_terraces", "apartment_block", "rowhouse", "cottage", "tent"]
## The landmark each era builds (the gate to the next era; the Skyheart in the last).
const LANDMARKS := {
	"camp": "meeting_hall", "village": "bell_tower", "town": "lumen_spire", "city": "lumen_nexus",
	"conflux": "sky_foundry", "skyborne": "dawn_beacon", "ascendant": "skyheart",
}
## Variety first: one of each food type (forager, farm, fishing dock) before anything else.
## Opening build order: [id, count wanted, minimum population].
const OPENING: Array = [["forager", 1, 0], ["woodcutter", 1, 0], ["forager", 2, 0], ["woodcutter", 2, 0], ["farm", 1, 0], ["lumen_tap", 1, 12],
	 ["fishing_dock", 1, 12], ["farm", 2, 14]]
## Ascendant healing buildings: id -> count wanted.
const HEALERS := {"verdant_spring": 2, "rewilding_grove": 2, "vein_mender": 2, "clearwater_works": 1}
const CLEANERS: Array[String] = ["purifier_tower", "cleanser"]
const TAX_OFFICES_MAX := 3
const SEARCH_RADIUS := 26
## Landmark saving starts at this share of the gate population.
const LANDMARK_AT := 0.8
const SAVE_AT := 0.55

var s: Settlement
var _offsets: Array[Vector2i] = []
var _cooldown := {}  # id -> day until which placement is not retried
var _blocked_today: bool = false
var _stock := {}
var _log_dimming: Array[String] = []
var _health_year: Array[String] = []
var _eras: Array[String] = []
var _last_progress_day: int = 0
var _skyheart_done_day: int = -1
var _great_end: String = ""
var _verbose: bool = false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 and args[0].is_valid_int() else DEFAULT_SEED
	_verbose = args.has("v")
	var reg := DataRegistry.new()
	reg.load_all()
	s = Settlement.new_game(seed_value, reg)
	_make_offsets()
	s.events.subscribe("era_changed", _on_era)
	s.events.subscribe("dimming_ended", _on_dimming_ended)
	s.events.subscribe("great_dimming_ended", _on_great_end)
	print("balance: seed ", seed_value, ", cap ", MAX_YEARS, " years, stall ", STALL_YEARS, " years")
	var stalled := false
	var days := MAX_YEARS * GameClock.DAYS_PER_YEAR
	var t0 := Time.get_ticks_msec()
	for d in days:
		_act()
		s.step_hours(GameClock.HOURS_PER_DAY)
		var day := s.clock.total_days()
		if _verbose and day % 4 == 0:
			var tot := s.totals()
			print("   d%d pop %d beds %d idle %d gold %d food %d mat %d lumen %d sites %d bld %d" % [day, s.citizens.size(), s.beds_total(),
				s.idle_citizens().size(), int(s.gold), int(tot.get("food", 0)), int(tot.get("materials", 0)), int(tot.get("lumen", 0)),
				_open_sites(), s.buildings.size()])
		if day % GameClock.DAYS_PER_YEAR == 0:
			print("  year %2d end: planet health %.1f%%, pop %d, gold %d, buildings %d, era %s" % [
				day / GameClock.DAYS_PER_YEAR, s.planet_health(), s.citizens.size(), int(s.gold), s.buildings.size(), s.era_id()])
		if _skyheart_done_day < 0 and _skyheart_finished():
			_skyheart_done_day = day
			_progress()
			print("Skyheart finished: ", _stamp())
		if day - _last_progress_day >= STALL_YEARS * GameClock.DAYS_PER_YEAR:
			stalled = true
			break
		if _great_end != "":
			break
		var camp := s.get_system(CampaignSystem) as CampaignSystem
		if camp.is_lost():
			print("campaign lost at ", _stamp())
			break
	_report(stalled, (Time.get_ticks_msec() - t0) / 1000.0)
	quit(0)


func _progress() -> void:
	_last_progress_day = s.clock.total_days()


func _stamp() -> String:
	var h := s.clock.total_hours
	var secs := h * GameClock.REAL_SECONDS_PER_HOUR
	var mins := int(secs / 60.0)
	return "year %d, %s day %d (day %d), real time %d:%02d at 1x" % [
		s.clock.year(), s.clock.season_name(), s.clock.day(), s.clock.total_days(), mins / 60, mins % 60]


func _on_era(entry: Dictionary) -> void:
	var data: Dictionary = entry["data"]
	_progress()
	_eras.append("%s: %s" % [str(data["to"]).capitalize(), _stamp()])
	print("Era ", _eras[-1])


func _on_dimming_ended(entry: Dictionary) -> void:
	var data: Dictionary = entry["data"]
	print("  Dimming ended, year %d: %d days" % [s.clock.year(), int(data["length"])])


func _on_great_end(entry: Dictionary) -> void:
	var data: Dictionary = entry["data"]
	var camp := s.get_system(CampaignSystem) as CampaignSystem
	_great_end = "Great Dimming over: %s, population %d, planet health %.1f%%" % [
		_stamp(), int(data["population"]), float(data["planet_health"])]
	print(_great_end)


func _skyheart_finished() -> bool:
	for b: Building in s.buildings.values():
		if b.def.id == "skyheart" and not b.site:
			return true
	return false


func _report(stalled: bool, secs: float) -> void:
	print("---- balance summary (", "%.0f" % secs, " s of wall time) ----")
	for e in _eras:
		print("  ", e)
	if stalled:
		var g := s.era_gate()
		print("STALL: no progress for ", STALL_YEARS, " years at ", _stamp(), ", era ", s.era_id())
		if g["next"] == "":
			print("  last era: the Skyheart is not finished (", _skyheart_state(), ")")
		else:
			print("  next era ", g["next"], ": pop ", g["pop"], "/", g["pop_need"], (" ok" if g["pop"] >= g["pop_need"] else " BLOCKING"),
				", gold ", int(g["gold"]), "/", g["gold_need"], (" ok" if g["gold"] >= g["gold_need"] else " BLOCKING"),
				", landmark ", g["landmark"], (" built" if g["landmark_built"] else " BLOCKING"))
	var counts := {}
	for b: Building in s.buildings.values():
		counts[b.def.id] = int(counts.get(b.def.id, 0)) + 1
	print("Buildings at the end: ", counts)
	print("Skyheart finished: ", ("day %d" % _skyheart_done_day) if _skyheart_done_day >= 0 else "no")
	print("Great Dimming: ", _great_end if _great_end != "" else "not over")
	var camp := s.get_system(CampaignSystem) as CampaignSystem
	print("Campaign outcome: ", camp.outcome if camp.outcome != "" else "open")


func _skyheart_state() -> String:
	for b: Building in s.buildings.values():
		if b.def.id == "skyheart":
			return "stage %d, site %s" % [b.stage, str(b.site)]
	return "not placed"


# ---------------------------------------------------------------- the bot

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


func _count(id: String) -> int:
	var n := 0
	for b: Building in s.buildings.values():
		if b.def.id == id:
			n += 1
	return n


func _open_sites() -> int:
	var n := 0
	for b: Building in s.buildings.values():
		if b.site:
			n += 1
	return n


func _pending_slots() -> int:
	var n := 0
	for b: Building in s.buildings.values():
		if b.site:
			n += b.def.worker_slots
	return n


func _slots_for(good: String) -> int:
	var ids: Array = PRODUCERS[good]
	var n := 0
	for b: Building in s.buildings.values():
		if ids.has(b.def.id):
			n += b.def.worker_slots
	return n


func _afford(id: String, reserve: Dictionary = {}) -> bool:
	var cost := s.cost_for(id)
	for g in cost:
		var have: float = s.gold if g == "gold" else float(_stock.get(g, 0.0))
		if have + 0.0001 < float(cost[g]) + float(reserve.get(g, 0.0)):
			return false
	return true


## Places `id` on the free spot nearest `near` that a road can reach, as a real construction site, then lays the road.
func _place(id: String, near: Vector2i, radius: int = 16) -> Building:
	if int(_cooldown.get(id, -1)) > s.clock.total_days():
		return null
	var def := s.registry.get_building(id)
	var r2 := radius * radius
	var pick := Vector2i(-9999, -9999)
	var order: Array = _offsets
	if def.fells_forest:
		# every spot in range, the most forest within the cutting radius first (near ones win ties)
		var scored: Array = []
		for off in _offsets:
			if off.length_squared() > r2:
				break
			scored.append([float(_forest_around(near + off, 4)) - 0.4 * float(off.length()), off])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		order = scored.map(func(row: Array) -> Vector2i: return row[1])
	for off: Vector2i in order:
		if not def.fells_forest and off.length_squared() > r2:
			break
		var t := near + off
		if not s.can_place(id, t)["ok"]:
			continue
		if L._path(s, Rect2i(t, def.size)).is_empty():
			continue
		pick = t
		break
	if pick.x > -9999:
		var t := pick
		var bid := s.place_building(id, t)
		if bid < 0:
			return null
		var b: Building = s.buildings[bid]
		L.connect_road(s, b)
		_refresh_stock()
		return b
	_cooldown[id] = s.clock.total_days() + 3
	_blocked_today = true
	return null


func _forest_around(c: Vector2i, r: int) -> int:
	var n := 0
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if MapState.in_bounds(x, y) and s.map.terrain_id_at(x, y) == "forest":
				n += 1
	return n


## Woodcutters that ran out of trees are pulled down (half the cost comes back) and rebuilt where the forest is.
func _relocate_woodcutters() -> void:
	for b: Building in s.buildings.values().duplicate():
		if b.def.id == "woodcutter" and not b.site and b.halt == "no_forest":
			s.demolish(b.id)


func _reserve() -> Dictionary:
	var g := s.era_gate()
	var lm := _landmark_id()
	if lm == "" or _count(lm) > 0:
		return {}
	var gate_pop := float(g.get("pop_need", 0))
	if g["next"] == "":
		gate_pop = 450.0
	if float(s.citizens.size()) < SAVE_AT * gate_pop:
		return {}
	var out := {}
	var cost := s.registry.get_building(lm).entry_cost()
	for k in cost:
		out[k] = float(cost[k])
	return out


func _landmark_id() -> String:
	return str(LANDMARKS.get(s.era_current, ""))


func _hearth_near() -> Vector2i:
	return s.hearth.origin


## Goods in storage minus what open sites still need (so the bot never promises the same materials twice).
func _refresh_stock() -> void:
	_stock = s.totals()
	for b: Building in s.buildings.values():
		if not b.site:
			continue
		var cost := b.effective_cost()
		for g in cost:
			if g == BuildingDef.GOLD:
				continue
			var have := b.input_buffer.amount_of(g) if b.input_buffer != null else 0.0
			_stock[g] = float(_stock.get(g, 0.0)) - maxf(float(cost[g]) - have, 0.0)


func _act() -> void:
	_blocked_today = false
	_refresh_stock()
	var pop := s.citizens.size()
	var reserve := _reserve()
	var placed := 0
	var site_cap := 3 + pop / 40
	_throttle(pop)
	_relocate_woodcutters()
	# 1. landmark; while the bot saves for it, only housing and gold are bought
	var saving := _landmark()
	# 2. housing
	if _storehouses_wanted(pop) > _count("storehouse") and _afford("storehouse") and _jobs_free() >= 1:
		_place("storehouse", _hearth_near(), 14)
	if _opening(pop) and s.homeless_count() == 0:
		return
	if _open_sites() < site_cap + 2:
		_housing(pop, reserve)
	if saving:
		if _slots_for("gold") < 2:
			_produce(float(pop) * 1.15 + 10.0, pop, "gold")
		return
	# 4. production by share
	var goal := float(pop) * 1.15 + 10.0
	var tries := 0
	while _open_sites() < site_cap and tries < 3:
		tries += 1
		if not _produce(goal, pop):
			break
	# 5. support
	if _open_sites() < site_cap + 1:
		_support(pop, reserve)
	# 6. regions
	if _blocked_today:
		_buy_region()


## Pauses producers of a good that is plentiful and resumes them when it runs low: a full door buffer keeps the haulers
## busy ferrying surplus and construction sites then starve (haulers always take door buffers first).
func _throttle(pop: int) -> void:
	for good in THROTTLE:
		var high: float = float(THROTTLE[good][0]) * float(pop) + float(THROTTLE[good][1])
		var stock := float(_stock.get(good, 0.0))
		var ids: Array = PRODUCERS.get(good, [])
		if good == "food":
			ids = ["forager", "farm", "fishing_dock", "greenhouse", "hydroponic_hall", "bloom_orchard"]
		for b: Building in s.buildings.values():
			if b.site or not ids.has(b.def.id):
				continue
			if stock > high and not b.paused:
				s.set_building_priority(b.id, "paused")
			elif stock < high * 0.6 and b.paused:
				s.set_building_priority(b.id, "normal")


## Places the era's landmark when it can; returns true while the bot is saving for it.
func _landmark() -> bool:
	var lm := _landmark_id()
	if lm == "" or _count(lm) > 0:
		return false
	var g := s.era_gate()
	var gate_pop: int = int(g.get("pop_need", 0)) if g["next"] != "" else 450
	if float(s.citizens.size()) < LANDMARK_AT * float(gate_pop):
		return false
	if _afford(lm) and _place(lm, _hearth_near(), 20) != null:
		return false
	return true


func _housing(pop: int, reserve: Dictionary) -> void:
	var beds := s.beds_total()
	for b: Building in s.buildings.values():
		if b.site:
			beds += b.def.housing_beds
	var want := pop + maxi(2, pop / 6)
	if beds >= want:
		return
	var urgent := s.homeless_count() > 0
	var g := s.era_gate()
	var res := {} if (urgent or pop < int(g.get("pop_need", 450))) else reserve
	for id in HOUSING:
		var def := s.registry.get_building(id)
		if not s.is_unlocked(def):
			continue
		var cost := def.entry_cost()
		if cost.get("gold", 0) > 0 and s.gold < float(cost["gold"]) * 3.0:
			continue
		if not _afford(id, res):
			continue
		if _place(id, _hearth_near(), 18) != null:
			return


## Places the next unmet row of the opening order. Returns true while the opening still holds the stock back (a row is
## waiting for materials), so nothing else is bought.
func _opening(pop: int) -> bool:
	for row in OPENING:
		var id: String = row[0]
		var def := s.registry.get_building(id)
		if not s.is_unlocked(def) or _count(id) >= int(row[1]) or pop < int(row[2]):
			continue
		if def.worker_slots > 0 and _jobs_free() < 1:
			continue
		if _afford(id):
			if _place(id, _hearth_near(), SEARCH_RADIUS) != null:
				return true
			continue
		return true
	return false


func _storehouses_wanted(pop: int) -> int:
	return (1 + pop / 20) if pop >= 9 else 0


func _jobs_free() -> int:
	return s.idle_citizens().size() - _pending_slots()


## Builds one producer for the good furthest below its share (next best if that one cannot be placed). Returns false
## when nothing was placed.
func _produce(goal: float, pop: int, only: String = "") -> bool:
	var scored: Array = []
	for good in SHARES:
		if only != "" and good != only:
			continue
		var want: float = float(SHARES[good]) * goal
		var have := float(_slots_for(good))
		if have >= want:
			continue
		var stock := float(_stock.get(good, 0.0))
		if STOCK_CAP.has(good) and stock > float(STOCK_CAP[good]):
			continue
		if THROTTLE.has(good) and stock > 0.8 * (float(THROTTLE[good][0]) * float(pop) + float(THROTTLE[good][1])):
			continue
		var score: float = (want - have) / maxf(want, 1.0)
		if good == "food" or good == "lumen":
			var tgt: float = (goal * 3.0 if good == "food" else goal * 2.0 + 60.0)
			if stock < tgt:
				score *= 1.5
		scored.append([score, good])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var reserve := _reserve()
	for row in scored:
		var good: String = row[1]
		for id: String in PRODUCERS[good]:
			var def := s.registry.get_building(id)
			if not s.is_unlocked(def):
				continue
			if _jobs_free() < 1:
				return false
			if not _afford(id, {} if (good == "food" or good == "lumen" or good == "materials" or good == "gold") else reserve):
				continue
			if _place(id, _hearth_near(), SEARCH_RADIUS) != null:
				return true
	return false


func _support(pop: int, reserve: Dictionary) -> void:
	var era := s.registry.get_era(s.era_current).order
	var res := reserve
	# builders and haulers
	if era >= 2 and _count("builders_yard") < pop / 60 and _afford("builders_yard", res):
		_place("builders_yard", _hearth_near(), 14)
	if era >= 3 and _count("handcart_shed") < 1 + pop / 150 and _afford("handcart_shed", res):
		_place("handcart_shed", _hearth_near(), 14)
	# forester keeps the woodcutters going
	if era >= 2 and _count("forester") < _count("woodcutter") / 3 and _afford("forester", res) and _jobs_free() >= 1:
		_place("forester", _hearth_near(), SEARCH_RADIUS)
	# tax offices
	if era >= 3 and _count("tax_office") < mini(TAX_OFFICES_MAX, 1 + pop / 60) and _afford("tax_office", res) and _jobs_free() >= 1:
		_place("tax_office", _hearth_near(), 14)
	# Spirit coverage
	if era >= 2:
		var cover := "park" if era >= 4 else "shrine"
		var per := 40 if cover == "park" else 25
		if _count(cover) < 1 + pop / per and _afford(cover, res):
			_place(cover, _hearth_near(), 12)
	# drinking water for Rowhouse and up
	if era >= 3 and _count("rowhouse") + _count("apartment_block") + _count("conduit_terraces") > 0:
		if _count("well") < 1 + pop / 40 and _afford("well", res):
			_place("well", _hearth_near(), 14)
		if era >= 5 and _count("water_tower") < pop / 120 and _afford("water_tower", res):
			_place("water_tower", _hearth_near(), 14)
	# kitchen for food variety
	if era >= 3 and _count("kitchen") < 1 and _afford("kitchen", res) and _jobs_free() >= 2:
		_place("kitchen", _hearth_near(), 14)
	# cleaners against blight
	var blight := 0
	for v in s.map.blight:
		blight += int(v)
	var cleaners := _count("cleanser") + _count("purifier_tower")
	if era >= 3 and cleaners < mini(10, blight / 10) and _jobs_free() >= 2:
		for id in CLEANERS:
			if s.is_unlocked(s.registry.get_building(id)) and _afford(id, res):
				if _place(id, _hearth_near(), 18) != null:
					break
	# regional storehouses
	_regional_storehouses()
	# healing in the last era
	if s.era_current == "ascendant":
		for id in HEALERS:
			if _count(id) < int(HEALERS[id]) and _afford(id, res) and _jobs_free() >= 2:
				_place(id, _hearth_near(), SEARCH_RADIUS)
	# Lumen cells and tools matter for the big landmarks: keep one refinery and toolsmith early
	if era >= 5 and _count("lumen_pylon") < 0:
		pass


## A storehouse in every region that has homes, so people can eat where they live.
func _regional_storehouses() -> void:
	var homes := {}
	var stores := {}
	for b: Building in s.buildings.values():
		if b.layer != Building.LAYER_GROUND:
			continue
		var r := s.map.get_region(b.origin.x, b.origin.y)
		if b.def.housing_beds > 0:
			if not homes.has(r):
				homes[r] = b
		if b.def.id == "storehouse" or b.def.id == "hearth":
			stores[r] = true
	for r in homes:
		if not stores.has(r) and _afford("storehouse"):
			var home: Building = homes[r]
			_place("storehouse", home.origin, 10)
			return


func _buy_region() -> void:
	var best := -1
	var best_score := -1.0
	for r in MapState.REGION_COUNT:
		if not s.can_buy_region(r)["ok"]:
			continue
		var score := 0.0
		var x0 := (r % MapState.REGION_COLS) * MapState.REGION_W
		var y0 := (r / MapState.REGION_COLS) * MapState.REGION_H
		for y in range(y0, y0 + MapState.REGION_H, 2):
			for x in range(x0, x0 + MapState.REGION_W, 2):
				if s.map.terrain_id_at(x, y) == "lumen_vein":
					score += 1.0
		if s.map.get_region_reward(r) != "":
			score += 3.0
		var c := Vector2i(x0 + 16, y0 + 12)
		score -= float((c - s.hearth.origin).length()) * 0.05
		if score > best_score:
			best_score = score
			best = r
	if best >= 0:
		s.buy_region(best)
		_cooldown.clear()
