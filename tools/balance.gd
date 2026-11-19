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
const STALL_YEARS_DEFAULT := 4
const DEFAULT_SEED := 42

## Worker slots wanted per citizen for each good's producers (the bot builds the good that is furthest below its share).
const SHARES := {
	"food": 0.4, "wood": 0.16, "stone": 0.07, "lumen": 0.12, "gold": 0.10, "planks": 0.04, "cut_stone": 0.05,
	"lumen_cells": 0.05, "tools": 0.03,
}
## From City on these replace the share above (the Nexus and everything after it eat Lumen: light, cells, upkeep, 47g).
const CITY_SHARES := {"lumen": 0.18}
## Producer buildings per good, best first. The bot takes the first one that is unlocked, affordable and has room.
const PRODUCERS := {
	"food": ["bloom_orchard", "hydroponic_hall", "greenhouse", "farm", "fishing_dock", "forager"],
	"wood": ["woodcutter"],
	"stone": ["quarry"],
	"lumen": ["heartroot_tap", "lumen_pump", "lumen_reactor", "lumen_tap"],
	"gold": ["grand_bazaar", "market"],
	"planks": ["sawmill"],
	"cut_stone": ["mason"],
	"lumen_cells": ["refinery"],
	"tools": ["toolsmith"],
}
## Pause a good's producers above (per citizen, flat) stock; resume below 60% of it.
const THROTTLE := {"food": [6.0, 60.0], "wood": [1.8, 120.0], "stone": [1.2, 80.0], "lumen": [4.0, 150.0], "planks": [0.0, 120.0],
	"cut_stone": [0.0, 100.0], "lumen_cells": [0.0, 60.0], "tools": [0.0, 50.0]}
## From City on, food producers pause above this many units per citizen (see _throttle).
const FOOD_THROTTLE_CITY := 12.0
const CITY_ORDER := 4
## The raw goods (ticket 99 split the old "materials" into these two).
const RAW: Array[String] = ["wood", "stone"]
## Stock above which that good's producers may give way to unstaffed Markets (City on).
const GOLD_HOLD := {"wood": 90.0, "stone": 60.0}
## From this era on a new workplace needs as many idle citizens (not promised to open sites) as it has slots (47h).
const LABOUR_ERA := 3
## Share of a landmark's goods that must be in stock before its site is placed (City on).
const NEAR_READY := 0.5
## From City on, wood and stone producers are held while a landmark good is short and the raw stock is over this share of its cost.
const REFINED_HOLD_CITY := 0.5
## Stock above which a good stops being built for.
const STOCK_CAP := {"wood": 1500.0, "stone": 1000.0, "planks": 700.0, "cut_stone": 700.0, "lumen_cells": 700.0, "tools": 500.0}
## Housing, best first.
const HOUSING: Array[String] = ["lumen_arcology", "conduit_terraces", "apartment_block", "rowhouse", "cottage", "tent"]
## The landmark each era builds (the gate to the next era; the Skyheart in the last).
const LANDMARKS := {
	"camp": "meeting_hall", "village": "bell_tower", "town": "lumen_spire", "city": "lumen_nexus",
	"conflux": "sky_foundry", "skyborne": "dawn_beacon", "ascendant": "skyheart",
}
## Variety first: one of each food type (forager, farm, fishing dock) before anything else.
## Opening build order: [id, count wanted, minimum population].
const OPENING: Array = [["forager", 1, 0], ["woodcutter", 1, 0], ["forager", 2, 0], ["woodcutter", 2, 0], ["market", 1, 9], ["lumen_tap", 1, 9],
	["woodcutter", 3, 10], ["market", 2, 13], ["farm", 1, 0], ["fishing_dock", 1, 12], ["farm", 2, 14]]
## Ascendant healing buildings: id -> count wanted.
const HEALERS := {"verdant_spring": 2, "rewilding_grove": 2, "vein_mender": 2, "clearwater_works": 1}
const CLEANERS: Array[String] = ["purifier_tower", "cleanser"]
const TAX_OFFICES_MAX := 3
## Tax Offices are built below this many times the next gate's gold and pulled down above TAX_DROP_AT times it.
const TAX_BUILD_BELOW := 0.9
const TAX_DROP_AT := 1.25
## Days a site may stay too far from every yard before the bot takes it back (102).
const FAR_SITE_DAYS := 10
## Longest one-way walk (game hours) from a yard to a site before the bot builds a yard closer to it (102).
const YARD_WALK_MAX := 1.5
const SEARCH_RADIUS := 26
## Landmark saving starts at this share of the gate population.
const LANDMARK_AT := 0.6
## Producers of the landmark's refined goods (planks, cut stone, cells, tools) are built from this share on.
const PREP_AT := 0.35
const SAVE_AT := 0.55
## New storehouses stop when the hauler slots (hauling outranks producers: each takes a citizen) pass this share of the pop.
const HAULER_SHARE_MAX := 0.3
## Regions over 100 gold are bought only while this share of the next gate's gold is left over.
const REGION_KEEP := 0.6

var s: Settlement
var _offsets: Array[Vector2i] = []
var _bad_tiles := {}  # tiles where a building was taken back (see _place)
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
var _stall_years: int = STALL_YEARS_DEFAULT  # argument stall=<years>: a run with no era change for this long stops
var _map_day: int = 150  # verbose runs print an ASCII map of the town on this day (argument map=<day>)
var _made_acc := 0.0
var _g_acc := {}
var _food_prev := 0.0
var _gold_before := 0.0
var _placed_day := {}  # building id -> day it was placed (verbose build-time lines)
var _placed_hour := {}  # building id -> clock hour it was placed (place-to-finish times)
var _finish_small: Array[int] = []  # game hours from placement to completion, 1x1 buildings
var _finish_big: Array[int] = []  # ... larger buildings
var _inc_today := 0.0
var _inc := {}  # gold income by source in the current era (an estimate from the day's staffing), and the rest spent
var _wanted_max := 0.0  # highest wanted slots / citizens seen since the last era change (47h)
var _wanted_over := 0  # days the wanted slots were above the population since the last era change
var _placed_capped := 0  # workplaces placed for the producers' shares since the last era change: within the idle hands
var _placed_exempt := 0  # ... and let through the cap (food running out, a landmark good nobody makes yet)
var _measure: bool = false  # argument m: step hour by hour and sample where site time and producer hours go (102)
var _m_site := {}  # site phase -> site-hours
var _m_deliv := {}  # site id -> clock hour its goods were all there
var _m_to_deliv: Array[int] = []  # 1x1 sites: game hours from placement to the whole cost delivered
var _m_to_done: Array[int] = []  # ... and from delivered to finished
var _m_trip: Array[int] = []  # 1x1 sites: one-way walk from the nearest yard in game minutes, taken when the goods were all there
var _m_why := {}  # "good:halt" -> staffed producer-hours halted for another reason than a full door
var _m_room := {}  # output good -> door-full hours in which some storage still had room for it (the haulers' fault)
var _m_goods := {}  # missing good -> site-hours waiting for it
var _m_prod := {}  # output good -> [staffed producer-hours, hours halted on a full door]
var _gate_seen := {}  # gate part -> [day, gold] when it was first met in the current era


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 and args[0].is_valid_int() else DEFAULT_SEED
	_verbose = args.has("v")
	_measure = args.has("m")
	for a in args:
		if a.begins_with("map="):
			_map_day = int(a.substr(4))
		if a.begins_with("stall="):
			_stall_years = int(a.substr(6))
	var reg := DataRegistry.new()
	reg.load_all()
	s = Settlement.new_game(seed_value, reg)
	_make_offsets()
	s.events.subscribe("era_changed", _on_era)
	s.events.subscribe("dimming_ended", _on_dimming_ended)
	s.events.subscribe("building_completed", _on_built)
	s.events.subscribe("great_dimming_ended", _on_great_end)
	print("balance: seed ", seed_value, ", cap ", MAX_YEARS, " years, stall ", _stall_years, " years")
	var stalled := false
	var days := MAX_YEARS * GameClock.DAYS_PER_YEAR
	var t0 := Time.get_ticks_msec()
	for d in days:
		_gold_before = s.gold
		_act()
		_track_gold_start()
		if _verbose and s.clock.total_days() % 12 == 11:
			s.step_hours(10)
			_dbg_builders()
			print("     chain (hour 10): ", _chain_state())
			s.step_hours(GameClock.HOURS_PER_DAY - 10)
		elif _measure:
			for _h in GameClock.HOURS_PER_DAY:
				s.step_hours(1)
				_sample()
		else:
			s.step_hours(GameClock.HOURS_PER_DAY)
		var day := s.clock.total_days()
		_track_gold_end()
		if _verbose:
			var fs := float(_stock.get("food", 0.0))
			var tt := s.totals()
			var now := 0.0
			for g in GrowthSystem.food_goods(s.registry):
				now += float(tt.get(g, 0.0))
			var ld := (s.get_system(GrowthSystem) as GrowthSystem).last_day
			_g_acc["surplus_days"] = int(_g_acc.get("surplus_days", 0)) + (1 if float(ld.get("surplus", 0.0)) > 0.0 else 0)
			_g_acc["grown"] = int(_g_acc.get("grown", 0)) + int(ld.get("grown", 0))
			_g_acc["immigrated"] = int(_g_acc.get("immigrated", 0)) + int(ld.get("immigrated", 0))
			_g_acc["spirit_low"] = int(_g_acc.get("spirit_low", 0)) + (1 if s.spirit() < 50.0 else 0)
			_g_acc["nobed"] = int(_g_acc.get("nobed", 0)) + (1 if s.beds_total() <= s.citizens.size() else 0)
			_made_acc += now - _food_prev + float((s.get_system(GrowthSystem) as GrowthSystem).last_day.get("eaten", 0.0))
			_food_prev = now
		if _verbose and day % 4 == 0:
			var tot := s.totals()
			print("   d%d pop %d beds %d idle %d gold %d food %d wood %d stone %d lumen %d sites %d bld %d" % [day, s.citizens.size(), s.beds_total(),
				s.idle_citizens().size(), int(s.gold), int(tot.get("food", 0) + tot.get("crops", 0) + tot.get("fish", 0)), int(tot.get("wood", 0)), int(tot.get("stone", 0)), int(tot.get("lumen", 0)),
				_open_sites(), s.buildings.size()] + " | pl %d st %d cell %d tool %d" % [int(tot.get("planks", 0)), int(tot.get("cut_stone", 0)), int(tot.get("lumen_cells", 0)), int(tot.get("tools", 0))] + _lm_short())
		if _verbose and day % 12 == 0:
			var gr := s.get_system(GrowthSystem) as GrowthSystem
			var wc := {}
			var haul := 0
			var doorfood := 0.0
			for b: Building in s.buildings.values():
				if b.door_buffer != null:
					for g in ["food", "crops", "fish"]:
						doorfood += b.door_buffer.amount_of(g)
			var buildn := 0
			for c: Citizen in s.citizens.values():
				if c.job_kind == Citizen.JOB_WORK:
					wc[c.job_id] = int(wc.get(c.job_id, 0)) + 1
				elif c.job_kind == Citizen.JOB_HAUL:
					haul += 1
				elif not c.is_idle():
					buildn += 1
			var rows: Array[String] = []
			for b: Building in s.buildings.values():
				if b.def.worker_slots > 0 and not b.site:
					rows.append("%s%d/%d%s%s" % [b.def.id.substr(0, 4), int(wc.get(b.id, 0)), b.def.worker_slots, ("P" if b.paused else ""), (":" + b.halt if b.halt != "" else "")] + (" x%.2f" % (s.get_system(ProductionSystem) as ProductionSystem).multiplier(s, b) if b.def.category == "food" else ""))
			var sh := []
			for good in SHARES:
				sh.append("%s %d/%.0f" % [good, _slots_for(good), _share(good) * (float(s.citizens.size()) * 1.15 + 10.0)])
			var sp := []
			for b: Building in s.buildings.values():
				if b.site:
					sp.append("%s#%d %.2f%s%s%s" % [b.def.id, b.id, b.build_progress(), ("" if b.site_delivered() else "(wait)"), (":" + b.halt if b.halt != "" else ""), ("" if b.connected else "(noroad)")])
			print("     sites: ", " ".join(sp), " builders ", buildn)

			print("     food made/day %.1f; shares " % (_made_acc / 12.0), " ".join(sh))
			_made_acc = 0.0
			var doormat := 0.0
			for b: Building in s.buildings.values():
				if b.door_buffer != null:
					doormat += b.door_buffer.amount_of("wood") + b.door_buffer.amount_of("stone")
			print("     door wood+stone %.0f" % doormat)
			var slots := {}
			var fill := {}
			for b: Building in s.buildings.values():
				if b.site or b.paused:
					continue
				slots[b.def.category] = int(slots.get(b.def.category, 0)) + b.def.worker_slots
				fill[b.def.category] = int(fill.get(b.def.category, 0)) + int(wc.get(b.id, 0))
			print("     spirit ", (s.get_system(SpiritSystem) as SpiritSystem).breakdown(s)["factors"])
			print("     growth 12d ", _g_acc)
			_g_acc = {}
			print("     growth ", gr.last_day, " bar ", snappedf(gr.bar, 0.1), " homeless ", s.homeless_count(), " beds ", s.beds_total(), " lumen need ", snappedf(float(s.citizens.size()) * 0.5, 0.1))
			var ln := 0
			var lfull := 0
			var ldoor := 0.0
			var lwork := 0
			for b: Building in s.buildings.values():
				if not b.site and b.def.category == "lumen" and b.door_buffer != null:
					ln += 1
					lfull += 1 if b.halt == "door_full" else 0
					ldoor += b.door_buffer.amount_of("lumen")
					lwork += int(wc.get(b.id, 0))
			print("     lumen producers %d staffed %d door_full %d door lumen %d stock %d" % [ln, lwork, lfull, int(ldoor), int(_stock.get("lumen", 0.0))])
			print("     labour wanted %d pop %d food %d" % [_wanted_slots(), s.citizens.size(), int(_stock.get("food", 0.0))])
			print("     slots/filled by category ", slots, fill, " hauler slots ", _hauler_slots(), " pop ", s.citizens.size())
			print("     doorfood %.0f; spirit %.0f haulers %d other %d bar %.1f/%.1f | %s" % [doorfood, s.spirit(), haul, buildn, gr.bar, gr.bar_size_now(s), " ".join(rows)])
		if _verbose and day == _map_day:
			_dump_map()
		if _verbose and day % 40 == 0:
			for b: Building in s.buildings.values():
				if b.site:
					var got := {}
					for g in b.effective_cost():
						got[g] = b.input_buffer.amount_of(g) if b.input_buffer != null else 0.0
					var wsd := s.get_system(WalkerSystem) as WalkerSystem
					print("     reach ", wsd.find_path(wsd.door_tile(s.hearth), wsd.door_tile(b)).size(), " hearth door ", wsd.door_tile(s.hearth), " site door ", wsd.door_tile(b), " path ", wsd.find_path(wsd.door_tile(s.hearth), wsd.door_tile(b)))
					var csd := s.get_system(ConstructionSystem) as ConstructionSystem
					for y: Building in s.buildings.values():
						if y.def.builder_slots > 0 and not y.site:
							print("       yard ", y.id, y.origin, " round trip s ", 2.0 * csd._trip_seconds(s, wsd, y, b))
					print("     site ", b.def.id, b.origin, " delivered ", b.site_delivered(), " got ", got, " need ", b.effective_cost(), " progress ", b.build_progress())
		if day % GameClock.DAYS_PER_YEAR == 0:
			print("  year %2d end: planet health %.1f%%, pop %d, gold %d, buildings %d, era %s" % [
				day / GameClock.DAYS_PER_YEAR, s.planet_health(), s.citizens.size(), int(s.gold), s.buildings.size(), s.era_id()])
		if _skyheart_done_day < 0 and _skyheart_finished():
			_skyheart_done_day = day
			_progress()
			print("Skyheart finished: ", _stamp())
		if day - _last_progress_day >= _stall_years * GameClock.DAYS_PER_YEAR:
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


## Verbose: each Sawmill / Refinery / Toolsmith with its workers at work, halt reason and input buffer (47g).
func _chain_state() -> String:
	var counts := (s.get_system(WalkerSystem) as WalkerSystem).work_counts()
	var rows: Array[String] = []
	for b: Building in s.buildings.values():
		if b.site or not ["sawmill", "refinery", "toolsmith"].has(b.def.id):
			continue
		var inp := ""
		if b.input_buffer != null:
			for g in b.def.recipe.inputs:
				inp += " %s%d" % [str(g).substr(0, 2), int(b.input_buffer.amount_of(g))]
		rows.append("%s#%d w%d%s%s [%s ] out %d" % [b.def.id.substr(0, 4), b.id, int(counts.get(b.id, 0)), ("P" if b.paused else ""), (":" + b.halt if b.halt != "" else ""), inp, int(b.door_buffer.total())])
	return " ".join(rows)


## What the era's landmark still lacks (verbose lines).
func _lm_short() -> String:
	var lm := _landmark_id()
	if lm == "" or not _lm_open():
		return ""
	var cost := s.registry.get_building(lm).entry_cost()
	var out: Array[String] = []
	for g in cost:
		var have: float = s.gold if g == "gold" else float(_stock.get(g, 0.0))
		if have < float(cost[g]):
			out.append("%s %d/%d" % [g, int(have), int(cost[g])])
	return " | lm short: " + ", ".join(out)


## Gold diagnostics (47f): what each gold source paid in the era, what was spent, and the day each gate part was met.
func _track_gold_start() -> void:
	_inc_today = 0.0
	var assigned := MarketSystem.assigned_workers(s)
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused:
			continue
		var n := int(assigned.get(bid, 0))
		var made := b.def.gold_per_worker_day * float(n)
		if b.def.gold_per_citizen_day > 0.0 and n > 0:
			made += b.def.gold_per_citizen_day * float(s.citizens.size())
		if made > 0.0:
			_inc[b.def.id] = float(_inc.get(b.def.id, 0.0)) + made
			_inc["_total"] = float(_inc.get("_total", 0.0)) + made
			_inc_today += made


func _track_gold_end() -> void:
	_inc["_spent"] = float(_inc.get("_spent", 0.0)) + _gold_before + _inc_today - s.gold
	var g := s.era_gate()
	if g["next"] == "":
		return
	var parts := {"pop": g["pop"] >= g["pop_need"], "gold": g["gold"] >= g["gold_need"], "landmark": g["landmark_built"]}
	for k in parts:
		if parts[k] and not _gate_seen.has(k):
			_gate_seen[k] = [s.clock.total_days(), int(s.gold)]


func _gate_report(from_era: String) -> String:
	var rows: Array[String] = []
	for k in ["pop", "gold", "landmark"]:
		rows.append("%s %s" % [k, ("d%d (gold %d)" % [_gate_seen[k][0], _gate_seen[k][1]]) if _gate_seen.has(k) else "never"])
	var last := ""
	var last_day := -1
	if _gate_seen.has("lm_placed"):
		rows.append("landmark placed d%d" % _gate_seen["lm_placed"][0])
	for k in _gate_seen:
		if k == "lm_placed":
			continue
		if _gate_seen[k][0] > last_day:
			last_day = _gate_seen[k][0]
			last = k
	var inc := []
	for k in _inc:
		if not k.begins_with("_"):
			inc.append("%s %d" % [k, int(_inc[k])])
	return "    gate parts met in %s: %s; last %s; gold income {%s} total %d, spent %d (regions %d)" % [from_era, ", ".join(rows), last,
		", ".join(inc), int(_inc.get("_total", 0.0)), int(_inc.get("_spent", 0.0)), int(_inc.get("_regions", 0.0))]


func _dbg_builders() -> void:
	var wsx := s.get_system(WalkerSystem) as WalkerSystem
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	var rows := []
	for c: Citizen in s.citizens.values():
		if c.job_kind == Citizen.JOB_BUILD:
			var w := wsx.walker_of(c.id)
			rows.append("b%d %s path %d at %d ctrl %s crew %d" % [c.id, str(w.tile), w.path.size(), w.at_building, str(w.controlled), int(cs.crews.get(c.id, -1))])
	var rw := ConstructionSystem.ready_works(s).map(func(b: Building) -> String: return "%s#%d" % [b.def.id, b.id])
	print("       DBG hour ", s.clock.hour(), " ready ", rw, " ", rows)


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
	_eras.append("%s: %s, gold %d, pop %d" % [str(data["to"]).capitalize(), _stamp(), int(s.gold), s.citizens.size()])
	print("Era ", _eras[-1])
	for k in ["pop", "gold", "landmark"]:
		if not _gate_seen.has(k):
			_gate_seen[k] = [s.clock.total_days(), int(s.gold)]  # met within the day the era changed
	print(_gate_report(str(data["from"])))
	print("  labour: wanted slots / citizens at most %.2f (days over %d); producers placed %d within idle hands, %d let through (food short, landmark goods)" % [_wanted_max, _wanted_over, _placed_capped, _placed_exempt])
	_wanted_max = 0.0
	_wanted_over = 0
	_placed_capped = 0
	_placed_exempt = 0
	_gate_seen.clear()
	_inc.clear()


func _dump_map() -> void:
	var h := s.hearth.origin
	var grid := {}
	for b: Building in s.buildings.values():
		var r := b.footprint()
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				grid[Vector2i(x, y)] = b.def.id.substr(0, 1).to_upper() if b.site == false else b.def.id.substr(0, 1)
	for y in range(h.y - 18, h.y + 18):
		var line := ""
		for x in range(h.x - 30, h.x + 34):
			var tt := Vector2i(x, y)
			if grid.has(tt):
				line += grid[tt]
			elif s.road_at(tt) != Settlement.ROAD_NONE:
				line += "+"
			else:
				var id := s.map.terrain_id_at(x, y)
				line += "~" if id == "water" else ("f" if id == "forest" else ".")
		print("MAP ", line)


func _on_built(entry: Dictionary) -> void:
	var data: Dictionary = entry["data"]
	var id := int(data.get("id", -1))
	if _placed_hour.has(id) and s.buildings.has(id) and LANDMARKS.values().has(s.buildings[id].def.id):
		var dh: int = int(_m_deliv.get(id, -1))
		print("  landmark %s: placed to delivered %s h, delivered to built %s h" % [s.buildings[id].def.id,
			(str(dh - int(_placed_hour[id])) if dh >= 0 else "?"), (str(s.clock.total_hours - dh) if dh >= 0 else "?")])
	if _placed_hour.has(id) and s.buildings.has(id):
		var took := s.clock.total_hours - int(_placed_hour[id])
		if s.buildings[id].def.size == Vector2i(1, 1):
			_finish_small.append(took)
			if _m_deliv.has(id):
				_m_to_deliv.append(int(_m_deliv[id]) - int(_placed_hour[id]))
				_m_to_done.append(s.clock.total_hours - int(_m_deliv[id]))
		else:
			_finish_big.append(took)
		_placed_hour.erase(id)
	if not _verbose:
		return
	if _placed_day.has(id) and s.buildings.has(id):
		print("   d%d built %s after %d days" % [s.clock.total_days(), s.buildings[id].def.id, s.clock.total_days() - int(_placed_day[id])])


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
		_refresh_stock()
		var lm := _landmark_id()
		print("  landmark ", lm, " cost ", s.registry.get_building(lm).entry_cost(), " stock ", _stock, " count ", _count(lm), " reserve ", _reserve())
		var cs := s.get_system(ConstructionSystem) as ConstructionSystem
		var rows: Array[String] = []
		for b: Building in s.buildings.values():
			if b.site:
				var crew := 0
				for cid in cs.crews:
					if cs.crews[cid] == b.id:
						crew += 1
				rows.append("%s#%d %.0f%% %s walk %.1fh crew %d%s" % [b.def.id, b.id, 100.0 * b.build_progress(), ("delivered" if b.site_delivered() else "waiting"), _walk_hours(b), crew, (" " + b.halt if b.halt != "" else "")])
		print("  open sites: ", "; ".join(rows))
		var kinds := {}
		for c: Citizen in s.citizens.values():
			kinds[c.job_kind] = int(kinds.get(c.job_kind, 0)) + 1
		print("  citizens by job kind: ", kinds, ", yards ", _count("builders_yard"), ", builder slots wanted ", ConstructionSystem.builders_wanted(s))
		print("STALL: no progress for ", _stall_years, " years at ", _stamp(), ", era ", s.era_id())
		if g["next"] == "":
			print("  last era: the Skyheart is not finished (", _skyheart_state(), ")")
		else:
			print("  next era ", g["next"], ": pop ", g["pop"], "/", g["pop_need"], (" ok" if g["pop"] >= g["pop_need"] else " BLOCKING"),
				", gold ", int(g["gold"]), "/", g["gold_need"], (" ok" if g["gold"] >= g["gold_need"] else " BLOCKING"),
				", landmark ", g["landmark"], (" built" if g["landmark_built"] else " BLOCKING"))
	var counts := {}
	for b: Building in s.buildings.values():
		counts[b.def.id] = int(counts.get(b.def.id, 0)) + 1
	print("Labour: wanted slots / citizens at most %.2f since the last era (days over %d); producers placed %d within idle hands, %d let through" % [_wanted_max, _wanted_over, _placed_capped, _placed_exempt])
	_refresh_stock()
	print("End stocks: wood %d stone %d planks %d cut_stone %d (storage)" % [int(_stock.get("wood", 0.0)), int(_stock.get("stone", 0.0)), int(_stock.get("planks", 0.0)), int(_stock.get("cut_stone", 0.0))])
	print("Place-to-finish (game hours, median / worst): 1x1 %s, bigger %s" % [_finish_text(_finish_small), _finish_text(_finish_big)])
	if _measure:
		print(_measure_text())
	print("Buildings at the end: ", counts)
	print("Skyheart finished: ", ("day %d" % _skyheart_done_day) if _skyheart_done_day >= 0 else "no")
	print("Great Dimming: ", _great_end if _great_end != "" else "not over")
	var camp := s.get_system(CampaignSystem) as CampaignSystem
	print("Campaign outcome: ", camp.outcome if camp.outcome != "" else "open")


## One hour of site and producer samples (argument m).
func _sample() -> void:
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var h := s.clock.hour()
	var in_shift := h >= WalkerSystem.WORK_START_HOUR and h < WalkerSystem.WORK_END_HOUR
	var staff := {}
	for c: Citizen in s.citizens.values():
		if c.job_kind == Citizen.JOB_WORK:
			staff[c.job_id] = int(staff.get(c.job_id, 0)) + 1
	for b: Building in s.buildings.values():
		if b.site:
			if b.paused:
				continue
			var phase := ""
			if b.site_delivered() and not _m_deliv.has(b.id):
				_m_deliv[b.id] = s.clock.total_hours
				var best := INF
				for y: Building in s.buildings.values():
					if y.def.builder_slots > 0 and not y.site:
						best = minf(best, cs._trip_seconds(s, ws, y, b))
				if best < INF and b.def.size == Vector2i(1, 1):
					_m_trip.append(int(best / GameClock.REAL_SECONDS_PER_HOUR * 60.0))
			if b.halt == "too_far":
				phase = "far"
			elif not b.site_delivered():
				phase = "goods"
				var cost := b.effective_cost()
				for g in cost:
					if g != BuildingDef.GOLD and b.input_buffer.amount_of(g) < float(cost[g]) - Inventory.EPS:
						_m_goods[g] = int(_m_goods.get(g, 0)) + 1
						break
			elif not in_shift:
				phase = "night"
			else:
				phase = "queue"
				for cid in cs.crews:
					if cs.crews[cid] == b.id:
						var w := ws.walker_of(cid)
						phase = "work" if (w != null and w.path.is_empty() and w.at_building == b.id) else "walk"
						if phase == "work":
							break
			_m_site[phase] = int(_m_site.get(phase, 0)) + 1
		elif b.def.recipe != null and b.door_buffer != null and not b.paused and int(staff.get(b.id, 0)) > 0:
			var out: String = b.def.recipe.outputs.keys()[0] if not b.def.recipe.outputs.is_empty() else "?"
			var row: Array = _m_prod.get(out, [0, 0])
			row[0] += 1
			row[1] += 1 if b.halt == "door_full" else 0
			if b.halt == "door_full" and s.find_storage_with_room(out, b.origin, 1.0) != null:
				_m_room[out] = int(_m_room.get(out, 0)) + 1
			if b.halt != "" and b.halt != "door_full":
				_m_why["%s:%s" % [out, b.halt]] = int(_m_why.get("%s:%s" % [out, b.halt], 0)) + 1
			_m_prod[out] = row


func _measure_text() -> String:
	var tot := 0
	for k in _m_site:
		tot += int(_m_site[k])
	var parts: Array[String] = []
	for k in _m_site:
		parts.append("%s %.0f%%" % [k, 100.0 * float(_m_site[k]) / float(maxi(tot, 1))])
	var out := "Site-hours %d: %s; missing goods %s\n" % [tot, ", ".join(parts), _m_goods]
	var pt := 0
	var ph := 0
	var rows: Array[String] = []
	for g in _m_prod:
		pt += int(_m_prod[g][0])
		ph += int(_m_prod[g][1])
		rows.append("%s %.1f%% of %d" % [g, 100.0 * float(_m_prod[g][1]) / float(maxi(int(_m_prod[g][0]), 1)), int(_m_prod[g][0])])
	out += "1x1 median hours placed->delivered %s, delivered->finished %s\n" % [_finish_text(_m_to_deliv), _finish_text(_m_to_done)]
	out += "1x1 one-way walk from the nearest yard (game minutes, median / worst): %s\n" % _finish_text(_m_trip)
	var room := 0
	for g in _m_room:
		room += int(_m_room[g])
	out += "Door-full hours with storage room left: %d (%.1f%% of producer-hours) %s\n" % [room, 100.0 * float(room) / float(maxi(pt, 1)), _m_room]
	out += "Other producer halts (hours): %s\n" % _m_why
	return out + "Producer-hours halted on a full door: %.1f%% of %d (%s)" % [100.0 * float(ph) / float(maxi(pt, 1)), pt, ", ".join(rows)]


func _finish_text(hours: Array[int]) -> String:
	if hours.is_empty():
		return "none built"
	var sorted := hours.duplicate()
	sorted.sort()
	return "%d / %d (%d built)" % [sorted[sorted.size() / 2], sorted[sorted.size() - 1], sorted.size()]


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


func _free_veins() -> int:
	var n := 0
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.terrain_id_at(x, y) == "lumen_vein" and s.map.is_region_owned(s.map.get_region(x, y)) and s.can_place("lumen_tap", Vector2i(x, y))["ok"]:
				n += 1
	return n


func _share(good: String) -> float:
	if CITY_SHARES.has(good) and s.registry.get_era(s.era_current).order >= CITY_ORDER:
		return float(CITY_SHARES[good])
	return float(SHARES[good])


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
	elif def.fertility_output:
		# the richest soil in range first (a mile of walking costs less than a farm at half output)
		var scored: Array = []
		for off in _offsets:
			if off.length_squared() > r2:
				break
			scored.append([12.0 * _mean_fertility(near + off, def.size) - 0.3 * float(off.length()), off])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		order = scored.map(func(row: Array) -> Vector2i: return row[1])
	if def.placement_rule == "on_vein":
		# veins anywhere in the bought regions, the ones nearest the Hearth first (a map reaches past the search radius)
		var veins: Array[Vector2i] = []
		for y in MapState.HEIGHT:
			for x in MapState.WIDTH:
				if s.map.terrain_id_at(x, y) == "lumen_vein" and s.map.is_region_owned(s.map.get_region(x, y)):
					veins.append(Vector2i(x, y))
		veins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - near).length_squared() < (b - near).length_squared())
		var looked := 0
		for t in veins:
			if int(_bad_tiles.get(t, -1)) > s.clock.total_days() or not s.can_place(id, t)["ok"]:
				continue
			looked += 1
			if looked > 12:
				break
			if not _road_affordable(Rect2i(t, def.size)):
				_bad_tiles[t] = s.clock.total_days() + 30  # no road reaches it now; look again in a month
				continue
			pick = t
			break
		order = []
	var checks := 0
	for off: Vector2i in order:
		if not def.fells_forest and not def.fertility_output and off.length_squared() > r2:
			break
		var t := near + off
		if int(_bad_tiles.get(t, -1)) > s.clock.total_days() or not s.can_place(id, t)["ok"]:
			continue
		if def.fertility_output and _mean_fertility(t, def.size) < 0.55:
			continue  # a farm on forest or stumps makes next to nothing: a player picks soil
		checks += 1
		if checks > 250:
			break  # a road search that fails floods the map: do not run it for hundreds of spots
		if not _road_affordable(Rect2i(t, def.size)):
			_bad_tiles[t] = s.clock.total_days() + 20
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
		if not _hearth_exits_joined() or not _reachable(b):
			# the building (or the road for it) shut a road tile at the Hearth in, so walkers cannot get through
			s.demolish(b.id)
			_bad_tiles[t] = s.clock.total_days() + 30
			_cooldown[id] = s.clock.total_days() + 1
			return null
		_refresh_stock()
		_placed_day[bid] = s.clock.total_days()
		_placed_hour[bid] = s.clock.total_hours
		if id == "builders_yard" or LANDMARKS.values().has(id):
			s.set_building_priority(bid, "high")  # a player raises the era's landmark and the yards that serve the work
		if _verbose:
			print("   d%d place %s pop %d idle %d jobs_free %d" % [s.clock.total_days(), id, s.citizens.size(), s.idle_citizens().size(), _jobs_free()])
		return b
	_cooldown[id] = s.clock.total_days() + 3
	_blocked_today = true
	return null


## Every road tile touching the Hearth can be walked to from every other one. A road tile boxed in by buildings next to
## the Hearth door is a dead end: the Hearth's door (first road-touching tile) leads nowhere and nobody can walk out
## (seed 3, 47e: builders stood at the Hearth, the sites never got built).
func _hearth_exits_joined() -> bool:
	if s.clock.total_hours == 0:
		return true  # the walkers have not met the settlement yet (nothing has been stepped)
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var exits: Array[Vector2i] = []
	var r := s.hearth.footprint()
	for x in range(r.position.x - 1, r.end.x + 1):
		for y in range(r.position.y - 1, r.end.y + 1):
			var t := Vector2i(x, y)
			if not r.has_point(t) and (x >= r.position.x and x < r.end.x or y >= r.position.y and y < r.end.y) \
					and s.road_at(t) != Settlement.ROAD_NONE:
				exits.append(t)
	for i in range(1, exits.size()):
		if ws.find_path(exits[0], exits[i]).is_empty():
			return false
	return true


func _reachable(b: Building) -> bool:
	if s.clock.total_hours == 0:
		return true
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	return not ws.find_path(ws.door_tile(s.hearth), ws.door_tile(b)).is_empty()


## A road to `fp` exists and its bridge tiles (water) can be paid now. A road laid only up to an unaffordable bridge
## leaves a site nobody can reach, and its woodcutter was the materials source (seed 3 never left Camp, 47e).
func _road_affordable(fp: Rect2i) -> bool:
	var path := L._path(s, fp)
	if path.is_empty():
		return false
	var need := {}
	for t in path:
		var cost := s.bridge_cost(t, Settlement.ROAD_DIRT)
		for g in cost:
			need[g] = float(need.get(g, 0.0)) + float(cost[g])
	var have := s.totals()
	for g in need:
		var got: float = s.gold if g == BuildingDef.GOLD else float(have.get(g, 0.0))
		if got < float(need[g]):
			return false
	return true


func _mean_fertility(origin: Vector2i, size: Vector2i) -> float:
	var sum := 0.0
	for y in size.y:
		for x in size.x:
			sum += float(s.map.get_fertility(origin.x + x, origin.y + y))
	return sum / (100.0 * float(size.x * size.y))


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


## True until the era's landmark is placed (a placed site is paid for from the stock; the bot stops saving then).
func _lm_open() -> bool:
	var lm := _landmark_id()
	return lm != "" and _count(lm) == 0


func _landmark_id() -> String:
	return str(LANDMARKS.get(s.era_current, ""))


func _hearth_near() -> Vector2i:
	return s.hearth.origin


## Goods in storage minus what open sites still need (so the bot never promises the same goods twice).
func _refresh_stock() -> void:
	_stock = s.totals()
	# "food" in the bot's eyes is every food good (crops and fish too), not only the forager's plain food
	var eat := 0.0
	for g in GrowthSystem.food_goods(s.registry):
		eat += float(_stock.get(g, 0.0))
	_stock["food"] = eat
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
	# sites too far from every yard hold builders for nothing (4 per ready site, walking all day): no new ones pile on
	var far_n := _far_sites()
	var site_cap := maxi(1, 3 + pop / 40 - mini(far_n, 3))
	_throttle(pop)
	_track_labour(pop)
	_chain_priority()
	_relocate_woodcutters()
	_cancel_stale_yards()
	_yards(pop, s.registry.get_era(s.era_current).order)
	# 1. landmark; while the bot saves for it, only housing and gold are bought
	var saving := _landmark()
	# 2. housing
	if _storehouses_wanted(pop) > _count("storehouse") and _afford("storehouse") and _jobs_free() >= 1 and _hauler_slots() < HAULER_SHARE_MAX * float(pop) + 4.0:
		_place("storehouse", _hearth_near(), 14)
	if _opening(pop) and s.homeless_count() == 0:
		return
	if _open_sites() < site_cap + 2 or (s.beds_total() <= pop + 2 and s.registry.get_era(s.era_current).order >= CITY_ORDER):  # stuck far sites must not hold housing back (growth stalled at full beds)
		_housing(pop, reserve)
	if saving:
		if _slots_for("gold") < 2:
			_produce(float(pop) * 1.15 + 10.0, pop, "gold")
		# also whatever refined good the landmark needs and the settlement does not make yet
		var lcost := s.registry.get_building(_landmark_id()).entry_cost()
		for good in lcost:
			var short: float = float(lcost[good]) - float(_stock.get(good, 0.0))
			# the more a good is short, the more producers it gets (Lumen is eaten by upkeep and Dimmings while saved)
			if good == "lumen" and short > 0.0 and s.clock.total_days() % 6 == 0 and _free_veins() < 3:
				_buy_region(true)  # the Lumen the landmark lacks needs veins to stand on (47g)
			if SHARES.has(good) and good != "gold" and short > 0.0 and _slots_for(good) < 2 + int(short / 15.0):
				# a landmark good nobody makes yet gets its producer even with every hand busy (the quarries give way)
				_produce(float(pop) * 1.15 + 10.0, pop, good, _slots_for(good) == 0 or good == "lumen")
		if float(_stock.get("food", 0.0)) < 2.0 * float(pop) + 40.0:
			_produce(float(pop) * 1.15 + 10.0, pop, "food")
	# 4. production by share
	var goal := float(pop) * 1.15 + 10.0
	var tries := 0
	# a falling food stock is not held back by the site limit (housing and support sites can sit waiting for goods)
	var food_low := float(_stock.get("food", 0.0)) < 2.0 * float(pop) + 40.0
	# so is a wood, stone or Lumen stock that cannot pay for the sites already open (their producers are what unblocks them)
	var low_stock := food_low or _raw_low("wood", pop) or _raw_low("stone", pop) or float(_stock.get("lumen", 0.0)) < 0.5 * float(pop)
	while _open_sites() < site_cap + (4 if (food_low or (low_stock and far_n < 2)) else 0) and tries < 3:
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
		if good == "food" and s.registry.get_era(s.era_current).order >= CITY_ORDER:
			high = FOOD_THROTTLE_CITY * float(pop) + float(THROTTLE[good][1])  # growth needs a rising stock: pausing the fields stops it (47g)
		var lm := _landmark_id()
		if lm != "" and _lm_open():
			var lcost := s.registry.get_building(lm).entry_cost()
			var want_n := float(lcost.get(good, 0))
			if good == "lumen_cells":
				want_n += maxf(float(lcost.get("tools", 0)) - float(_stock.get("tools", 0.0)), 0.0)  # every Tool still to make eats a cell
				high = want_n + 10.0  # cells cost 6 Lumen each: no more than the landmark needs (47h)
			else:
				high = maxf(high, 1.3 * want_n + 20.0)  # what the landmark needs stays wanted
		var stock := float(_stock.get(good, 0.0))
		if RAW.has(good) and _refined_short(good):
			high = minf(high, stock - 1.0)  # people are needed at the Mason and Sawmill: hold the raw producers until they have caught up
		if RAW.has(good) and stock >= float(GOLD_HOLD[good]) and _gold_unstaffed():
			high = minf(high, stock - 1.0)  # Markets rank below the raw producers: hold them while the gate's gold waits for hands (47h)
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


## True when the stock of a raw good cannot pay for the open sites: the old 0.8 * pop + 40 materials mark, split by the
## wood and stone shares (60 / 40).
func _raw_low(good: String, pop: int) -> bool:
	var share := 0.6 if good == "wood" else 0.4
	return float(_stock.get(good, 0.0)) < share * (0.8 * float(pop) + 40.0)


## Slots the settlement asks citizens for: workplaces not paused (sites count for the slots they will open), hauler slots, and
## the builder crews the open sites can use. JobSystem fills them by category rank, so a town that wants more than its
## citizens leaves the low ranks (refining, gold) empty (47g).
func _wanted_slots() -> int:
	var n := 0
	var yard := 0
	var sites := 0
	for b: Building in s.buildings.values():
		if b.paused:
			continue
		if b.site:
			n += b.def.worker_slots
			sites += 1
			continue
		n += b.effective_worker_slots(s.registry) + b.def.hauler_slots
		yard += b.def.builder_slots
	return n + mini(yard, sites * 4)


## Records the day's wanted slots against the population (the log line of the labour cap, printed at every era change).
func _track_labour(pop: int) -> void:
	if s.registry.get_era(s.era_current).order < LABOUR_ERA:
		return
	var wanted := _wanted_slots()
	_wanted_max = maxf(_wanted_max, float(wanted) / float(maxi(pop, 1)))
	if wanted > pop:
		_wanted_over += 1


## True from City on while the gate's gold is not in the treasury and a Market or Bazaar has empty slots.
func _gold_unstaffed() -> bool:
	if s.registry.get_era(s.era_current).order < CITY_ORDER:
		return false
	var g := s.era_gate()
	if g["next"] == "" or s.gold >= float(g.get("gold_need", 0)):
		return false
	var counts := (s.get_system(WalkerSystem) as WalkerSystem).work_counts()
	for b: Building in s.buildings.values():
		if not b.site and not b.paused and PRODUCERS["gold"].has(b.def.id) and int(counts.get(b.id, 0)) < b.effective_worker_slots(s.registry):
			return true
	return false


## Producers of a refined good the era's landmark still lacks (and of the planks and cells a missing Tool eats) get high
## priority: they rank behind food, Lumen, hauling, builders and the raw producers, so a busy town leaves them empty (47g).
func _chain_priority() -> void:
	var lm := _landmark_id()
	var cost := {} if lm == "" or not _lm_open() else s.registry.get_building(lm).entry_cost()
	var short := {}
	for g in ["planks", "cut_stone", "lumen_cells", "tools"]:
		short[g] = cost.has(g) and float(_stock.get(g, 0.0)) < float(cost[g])
	if short["tools"]:
		short["planks"] = true
		short["lumen_cells"] = true
	for g in short:
		for b: Building in s.buildings.values():
			if b.site or b.paused or not PRODUCERS[g].has(b.def.id):
				continue
			var want := "high" if short[g] else "normal"
			if b.priority != want:
				s.set_building_priority(b.id, want)


## True while the era's landmark waits for a refined good (planks, cut stone) and the stock of raw good `raw` (wood or
## stone) already covers what the landmark needs of it.
func _refined_short(raw: String) -> bool:
	var lm := _landmark_id()
	if lm == "" or not _lm_open():
		return false
	var cost := s.registry.get_building(lm).entry_cost()
	var raw_cost := float(cost.get(raw, 0))
	var hold := raw_cost + 50.0
	if s.registry.get_era(s.era_current).order >= CITY_ORDER:
		hold = REFINED_HOLD_CITY * raw_cost  # the refiners are what the Nexus waits for: free their hands early (47g)
	if float(_stock.get(raw, 0.0)) < hold:
		return false
	var counts := (s.get_system(WalkerSystem) as WalkerSystem).work_counts()
	for g in ["planks", "cut_stone", "lumen_cells", "tools"]:
		if not cost.has(g) or float(_stock.get(g, 0.0)) >= float(cost[g]):
			continue
		# the raw producers give way only while a producer of the short good has empty slots (47h: with every refiner staffed the
		# hold only kept the wood and stone stock under the landmark's cost)
		for b: Building in s.buildings.values():
			if not b.site and not b.paused and PRODUCERS[g].has(b.def.id) and int(counts.get(b.id, 0)) < b.effective_worker_slots(s.registry):
				return true
	return false


## Places the era's landmark when it can; returns true while the bot is saving for it.
func _landmark() -> bool:
	var lm := _landmark_id()
	if lm == "" or not _lm_open():
		return false
	var g := s.era_gate()
	var gate_pop: int = int(g.get("pop_need", 0)) if g["next"] != "" else 450
	if float(s.citizens.size()) < LANDMARK_AT * float(gate_pop):
		return float(s.citizens.size()) >= PREP_AT * float(gate_pop)  # not placed yet, but the refined goods are prepared
	# From City on the site goes down once every good is within NEAR_READY of its cost: haulers fill the rest, and what the
	# site holds is safe from the Dimmings' light draw and the upkeep (a stock of Lumen kept for the whole cost is eaten
	# away while the rest is gathered, 47g).
	var ready := _afford(lm)
	if not ready and s.registry.get_era(s.era_current).order >= CITY_ORDER:
		ready = true
		var cost := s.cost_for(lm)
		for good in cost:
			var have: float = s.gold if good == "gold" else float(_stock.get(good, 0.0))
			if have + 0.0001 < float(cost[good]) * (1.0 if good == "gold" else NEAR_READY):
				ready = false
	if ready and _place(lm, _hearth_near(), 20) != null:
		_gate_seen["lm_placed"] = [s.clock.total_days(), int(s.gold)]
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
## waiting for wood), so nothing else is bought.
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
		# a row waiting for wood or stone nobody makes yet: build that producer now (the Quarry is wood only), or the
		# opening would wait for stone for ever (ticket 99)
		var cost := s.cost_for(id)
		for g in RAW:
			if float(cost.get(g, 0.0)) > float(_stock.get(g, 0.0)) and _slots_for(g) == 0:
				_produce(float(pop) * 1.15 + 10.0, pop, g, true)
		return true
	return false


func _storehouses_wanted(pop: int) -> int:
	if pop < 9:
		return 0
	# one more when the stock fills the rooms: a full store takes no food and the producers' doors jam (a starving town)
	var held := 0.0
	for g in _stock:
		held += maxf(float(_stock[g]), 0.0)
	# and one per 60 units sitting in door buffers: more storehouses are more hauler slots (47e)
	var doors := 0.0
	for b: Building in s.buildings.values():
		if b.door_buffer != null:
			doors += b.door_buffer.total()
	return maxi(1 + pop / 20, ceili(held / 300.0)) + int(doors / 60.0)


func _jobs_free() -> int:
	return s.idle_citizens().size() - _pending_slots()


## Builds one producer for the good furthest below its share (next best if that one cannot be placed). Returns false
## when nothing was placed.
func _produce(goal: float, pop: int, only: String = "", no_hands_needed: bool = false) -> bool:
	var scored: Array = []
	for good in SHARES:
		if only != "" and good != only:
			continue
		var want: float = _share(good) * goal
		var have := float(_slots_for(good))
		var stock := float(_stock.get(good, 0.0))
		if good == "food" and stock < 2.0 * float(pop):
			want *= 1.4  # the town is eating its last food: more fields than the share says
		if have >= want:
			continue
		if STOCK_CAP.has(good) and stock > float(STOCK_CAP[good]):
			continue
		if THROTTLE.has(good) and stock > 0.8 * (float(THROTTLE[good][0]) * float(pop) + float(THROTTLE[good][1])):
			continue
		var score: float = (want - have) / maxf(want, 1.0)
		if good == "food" or good == "lumen":
			var tgt: float = (goal * 3.0 if good == "food" else goal * 2.0 + 60.0)
			if stock < tgt:
				score *= 1.5
		if RAW.has(good) and _raw_low(good, pop):
			score *= 1.5  # sites and refiners wait for it
		scored.append([score, good])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var reserve := _reserve()
	for row in scored:
		var good: String = row[1]
		for id: String in PRODUCERS[good]:
			var def := s.registry.get_building(id)
			if not s.is_unlocked(def):
				continue
			if _jobs_free() < 1 and not no_hands_needed and not (good == "food" and float(_stock.get("food", 0.0)) < 1.5 * float(pop)):  # food outranks every other job: its new hands come from them
				return false
			if _over_cap(def, good, pop, no_hands_needed):
				continue
			if not _afford(id, {} if (good == "food" or good == "lumen" or RAW.has(good) or good == "gold" or _landmark_needs(good)) else reserve):
				continue
			var through := _jobs_free() < def.worker_slots
			if _place(id, _hearth_near(), SEARCH_RADIUS) != null:
				if through:
					_placed_exempt += 1
				else:
					_placed_capped += 1
				return true
	return false


## True when a new workplace would push the slots the bot wants above the population (47h). Food in need, the landmark's
## missing goods and the opening are let through.
func _over_cap(def: BuildingDef, good: String, pop: int, no_hands_needed: bool) -> bool:
	if s.registry.get_era(s.era_current).order < LABOUR_ERA or no_hands_needed:
		return false
	if good == "food" and float(_stock.get("food", 0.0)) < 1.5 * float(pop):
		return false
	return _jobs_free() < def.worker_slots


## Hauler slots over every storehouse, yard and the Hearth: hauling outranks every producer, so each slot takes a citizen.
## True when the era's landmark (not placed yet) costs this good: its producer must not wait behind the landmark's own reserve.
func _landmark_needs(good: String) -> bool:
	var lm := _landmark_id()
	if lm == "" or _count(lm) > 0:
		return false
	return s.registry.get_building(lm).entry_cost().has(good)


func _hauler_slots() -> int:
	var n := 0
	for b: Building in s.buildings.values():
		n += b.def.hauler_slots
	return n


## A builders' yard for a site that is too far from every yard: tried from next to the site back towards the nearest yard,
## the first spot builders can reach (a yard nobody can walk to is never built, and its far site waits for it for ever).
func _place_yard_for(site: Building) -> Building:
	var best: Building = null
	var best_d := 100000
	for b: Building in s.buildings.values():
		if b.def.builder_slots > 0 and not b.site:
			var d := maxi(absi(b.origin.x - site.origin.x), absi(b.origin.y - site.origin.y))
			if d < best_d:
				best_d = d
				best = b
	if best == null:
		return null
	for f in [1.0, 0.8, 0.6, 0.4, 0.25]:
		var spot: Vector2i = best.origin + Vector2i(Vector2(site.origin - best.origin) * float(f))
		_cooldown.erase("builders_yard")
		var yard := _place("builders_yard", spot, 5)
		if yard == null:
			continue
		if _yard_reachable(yard):
			return yard
		s.demolish(yard.id)
		_bad_tiles[yard.origin] = s.clock.total_days() + 30
	return null


## True when a finished yard (the Hearth counts) is within the work day's round trip of the site (the too_far test).
func _yard_reachable(site: Building) -> bool:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	var shift := float(WalkerSystem.WORK_END_HOUR - WalkerSystem.WORK_START_HOUR) * GameClock.REAL_SECONDS_PER_HOUR
	for y: Building in s.buildings.values():
		if y.def.builder_slots > 0 and not y.site and 2.0 * cs._trip_seconds(s, ws, y, site) <= shift:
			return true
	return false


## A yard site that is itself too far to build is taken back after a while, so the bot can try a closer spot.
func _cancel_stale_yards() -> void:
	for b: Building in s.buildings.values().duplicate():
		if b.site and b.def.id == "builders_yard" and b.halt == "too_far" and s.clock.total_days() - int(_placed_day.get(b.id, s.clock.total_days())) > 25:
			s.demolish(b.id)
		# any other site no yard reaches holds a crew of builders walking all day: a player takes it back after a while (102)
		elif b.site and b.def.id != "builders_yard" and not LANDMARKS.values().has(b.def.id) and b.halt == "too_far" \
				and s.clock.total_days() - int(_placed_day.get(b.id, s.clock.total_days())) > FAR_SITE_DAYS:
			s.demolish(b.id)


## One-way walk in game hours from the nearest finished yard to a site's door (INF without a path).
func _walk_hours(site: Building) -> float:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	var best := INF
	for y: Building in s.buildings.values():
		if y.def.builder_slots > 0 and not y.site:
			best = minf(best, cs._trip_seconds(s, ws, y, site))
	return best / GameClock.REAL_SECONDS_PER_HOUR


func _far_sites() -> int:
	var n := 0
	for b: Building in s.buildings.values():
		if b.site and b.halt == "too_far" and b.def.id != "builders_yard":
			n += 1
	return n


func _yard_site_open() -> bool:
	for b: Building in s.buildings.values():
		if b.site and b.def.id == "builders_yard":
			return true
	return false


## Builders' yards: one for a site too far from every yard (its halt status), and one per 25 citizens.
func _yards(pop: int, era: int) -> void:
	# a site too far from every builders' yard (its halt status): a yard next to it
	var yard_def := s.registry.get_building("builders_yard")
	# (one at a time: sites close together share it, and a yard site waiting for its builders still shows the far status)
	if s.is_unlocked(yard_def) and _afford("builders_yard") and not _yard_site_open():
		for b: Building in s.buildings.values():
			if b.site and b.halt == "too_far" and b.def.id != "builders_yard":
				if _place_yard_for(b) != null:
					break
	# a player puts a yard next to where the work is: a site over YARD_WALK_MAX hours' walk from every yard gets one (102)
	if _count("builders_yard") < 2 + pop / 20 and s.is_unlocked(yard_def) and _afford("builders_yard") and not _yard_site_open():
		for b: Building in s.buildings.values():
			if b.site and b.def.id != "builders_yard" and b.halt != "too_far" and _walk_hours(b) > YARD_WALK_MAX:
				if _place_yard_for(b) != null:
					break
	if era >= 2 and _count("builders_yard") < pop / 25 and _afford("builders_yard") and not _yard_site_open():
		_place("builders_yard", _hearth_near(), 14)


func _support(pop: int, reserve: Dictionary) -> void:
	var era := s.registry.get_era(s.era_current).order
	var res := reserve
	if era >= 3 and _count("handcart_shed") < 1 + pop / 50 and _afford("handcart_shed", res):
		_place("handcart_shed", _hearth_near(), 14)
	# forester keeps the woodcutters going
	if era >= 2 and _count("forester") < _count("woodcutter") / 3 and _afford("forester", res) and _jobs_free() >= 1:
		_place("forester", _hearth_near(), SEARCH_RADIUS)
	# tax offices
	# (a Tax Office costs 5 Spirit while one stands, and Spirit below 50 stops immigration: only while gold is short, 47g)
	var gold_need := float(s.era_gate().get("gold_need", 0))
	if _count("tax_office") > 0 and s.gold >= TAX_DROP_AT * gold_need:
		for b: Building in s.buildings.values().duplicate():
			if b.def.id == "tax_office" and not b.site:
				s.demolish(b.id)
	if era >= 3 and s.gold < TAX_BUILD_BELOW * gold_need and _count("tax_office") < mini(TAX_OFFICES_MAX, 1 + pop / 60) and _afford("tax_office") and _jobs_free() >= 1:
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
		_wells_for_homes(res)
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
	if era >= 2 and cleaners < clampi(blight / 10, mini(1, blight), 10) and _jobs_free() >= 2:
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


## A Well beside a home that has no drinking water (Rowhouse and up): each home without water costs Spirit, and Spirit
## under 50 stops immigration. The nearest home to the Hearth first; a well is within water_radius of the spot it is put.
func _wells_for_homes(res: Dictionary) -> void:
	if not _afford("well", res) or _count("well") >= 4 + s.citizens.size() / 12:
		return
	var cs := s.get_system(CoverageSystem) as CoverageSystem
	var best: Building = null
	var best_d := 1.0e9
	for b: Building in s.buildings.values():
		if b.site or not b.def.needs_water or cs.home_has_water(s, b.id) or int(_bad_tiles.get(b.origin, -1)) > s.clock.total_days():
			continue
		var d := float((b.origin - s.hearth.origin).length_squared())
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return
	if _place("well", best.origin, 7) == null:
		_bad_tiles[best.origin] = s.clock.total_days() + 20  # no wet ground within reach of that home: try another later


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
		if not stores.has(r) and _afford("storehouse") and _hauler_slots() < HAULER_SHARE_MAX * float(s.citizens.size()) + 6.0:
			var home: Building = homes[r]
			_place("storehouse", home.origin, 10)
			return


## `any`: take the best region even when it has no veins and lies far (a plain buy needs a score over -1).
func _buy_region(any: bool = false) -> void:
	var best := -1
	var best_score := -1.0e9 if any else -1.0
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
		var price := s.next_region_price()
		var need := float(s.era_gate().get("gold_need", 0))
		if price > 100 and s.gold - float(price) < REGION_KEEP * need:
			return  # the gate's gold is not spent on land (a player saves for it too)
		if s.buy_region(best):
			_inc["_regions"] = float(_inc.get("_regions", 0.0)) + float(price)
			if _verbose:
				print("   d%d bought region %d for %d" % [s.clock.total_days(), best, price])
		_cooldown.clear()
