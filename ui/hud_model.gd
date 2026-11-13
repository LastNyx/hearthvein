class_name HudModel
extends RefCounted
## Everything the HUD shows, as plain data and strings (no scene tree), so it is unit-tested headless. The Control
## scenes (ui/hud.gd) only copy these values onto labels. Reads the Settlement; its only commands are the building
## priority and pause the selected-building panel offers.

const OVERLAYS: Array[String] = ["blight", "roads", "water", "coverage"]
const CATEGORY_ORDER: Array[String] = ["roads", "housing", "food", "materials", "lumen", "refining", "gold",
		"water", "logistics", "civic", "sky", "landmark"]
const RESOURCES: Array[String] = ["food", "materials", "lumen", "gold"]
const REWARD_LABELS := {"rich_vein": "Rich vein", "ruins": "Ruins", "fertile_valley": "Fertile valley",
		"old_forest": "Old forest", "spring": "Spring"}
const PRIORITY_LABELS := {"low": "Low", "normal": "Normal", "high": "High"}

var s: Settlement
var notifications: NotificationCenter
var selected_id: int = -1
var overlays := {"blight": false, "roads": false, "water": false, "coverage": false}
var _deltas := {"food": 0, "materials": 0, "lumen": 0, "gold": 0}
var _mark: Dictionary = {}


func _init(settlement: Settlement) -> void:
	s = settlement
	notifications = NotificationCenter.new(s)
	_mark = _stock()
	s.events.subscribe("day_started", _on_day)


func _on_day(_e: Dictionary) -> void:
	var now := _stock()
	for k in RESOURCES:
		_deltas[k] = roundi(now[k] - _mark.get(k, now[k]))
	_mark = now
	notifications.poll()


func _stock() -> Dictionary:
	var t := s.totals()
	var food := 0.0
	for g in GrowthSystem.food_goods(s.registry):
		food += float(t.get(g, 0.0))
	return {"food": food, "materials": float(t.get("materials", 0.0)), "lumen": float(t.get("lumen", 0.0)),
			"gold": s.gold}


# ---------------------------------------------------------------- top bar

## [{id, icon, value, delta, text}] for food, materials, lumen, gold. delta = change over the last full day.
func resources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now := _stock()
	for k in RESOURCES:
		var d: int = _deltas[k]
		out.append({"id": k, "icon": k, "value": floori(now[k]), "delta": d,
				"text": "%d %s" % [floori(now[k]), delta_text(d)]})
	return out


static func delta_text(d: int) -> String:
	return ("+%d" % d) if d >= 0 else ("%d" % d)


func population() -> Dictionary:
	var pop := s.citizens.size()
	var beds := s.beds_total()
	var g := s.get_system(GrowthSystem) as GrowthSystem
	var size := g.bar_size_now(s) if g != null else 0.0
	return {"pop": pop, "beds": beds, "homeless": s.homeless_count(), "text": "%d / %d" % [pop, beds],
			"growth": clampf(g.bar / size, 0.0, 1.0) if g != null and size > 0.0 else 0.0}


const FACTOR_NAMES := {"base": "Base", "food_types": "Food variety", "coverage": "Coverage", "hunger": "Hunger",
		"homeless": "Homeless", "blight": "Blight", "water": "Water", "darkness": "Darkness",
		"tax_office": "Tax Office", "planet_grief": "Planet grief"}


## {value, target, text, state (good|ok|bad), tooltip}. The tooltip lists the factors in the sim's order.
func spirit() -> Dictionary:
	var v := s.spirit()
	var sp := s.get_system(SpiritSystem) as SpiritSystem
	var lines: Array[String] = []
	var target := v
	if sp != null:
		var b := sp.breakdown(s)
		target = b["target"]
		for k in b["factors"]:
			var f: float = b["factors"][k]
			if k == "base" or absf(f) > 0.001:
				lines.append("%s %s" % [FACTOR_NAMES.get(k, k), delta_text(roundi(f)) if k != "base" else str(roundi(f))])
	lines.append("Heading to %d" % roundi(target))
	var state := "good" if v >= 70.0 else ("bad" if v <= 30.0 else "ok")
	return {"value": v, "target": target, "text": "Spirit %d" % roundi(v), "state": state,
			"tooltip": "\n".join(lines)}


## {value, trend, text}: planet health in percent and its change over the last year (32 days).
func planet() -> Dictionary:
	var ph := s.get_system(PlanetHealthSystem) as PlanetHealthSystem
	var tr := ph.trend(s) if ph != null else 0.0
	var h := s.planet_health()
	return {"value": h, "trend": tr, "text": "%d%%  %s%.1f/yr" % [roundi(h), "+" if tr >= 0.0 else "-", absf(tr)]}


func clock_text(speed_text: String = "") -> String:
	var t := s.clock.label()
	return t if speed_text == "" else "%s  %s" % [t, speed_text]


# ---------------------------------------------------------------- era and Dimming panel

func era_name() -> String:
	var e := s.registry.get_era(s.era_id())
	return e.display_name if e != null else s.era_id()


## Lines of the era panel: era title, the next-era gate, the Dimming line, the date.
func era_panel() -> Dictionary:
	var gate := s.era_gate()
	var gate_text := "Final era"
	if gate["next"] != "":
		var nxt := s.registry.get_era(gate["next"])
		var lm := s.registry.get_building(gate["landmark"])
		gate_text = "Next: %s  pop %d/%d  gold %d/%d  %s %s" % [nxt.display_name, gate["pop"], gate["pop_need"],
				floori(gate["gold"]), gate["gold_need"], lm.display_name if lm != null else str(gate["landmark"]),
				"built" if gate["landmark_built"] else "not built"]
	return {"title": "Era: %s" % era_name(), "gate": gate_text, "dimming": dimming_text(),
			"dimming_state": dimming_state(), "date": "Year %d, %s" % [s.clock.year(), s.clock.season_name().capitalize()]}


func dimming_state() -> String:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	return d.status(s)["state"] if d != null else "none"


func dimming_text() -> String:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null:
		return "No Dimming expected"
	var st := d.status(s)
	match st["state"]:
		"forecast":
			var n: int = st["days_until"]
			return "Dimming %s - lasts %d" % ["today" if n <= 0 else ("tomorrow" if n == 1 else "in %d days" % n), st["length"]]
		"active":
			var total: int = st["length"]
			return "DIMMING - day %d of %d%s" % [total - int(st["days_left"]) + 1, total, " (dark)" if st["dark"] else ""]
	return "No Dimming expected"


# ---------------------------------------------------------------- selection

func select(id: int) -> void:
	selected_id = id if s.buildings.has(id) else -1


func select_at(tile: Vector2i) -> void:
	var b := s.building_at(tile)
	selected_id = b.id if b != null else -1


func clear_selection() -> void:
	selected_id = -1


func selected() -> Building:
	if selected_id >= 0 and not s.buildings.has(selected_id):
		selected_id = -1
	return s.buildings.get(selected_id)


func _workers(b: Building) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK:
			n += 1
	return n


func _blight_near(b: Building) -> int:
	var r := b.def.blight_radius
	if r <= 0:
		return 0
	var n := 0
	for y in range(b.origin.y - r, b.origin.y + b.def.size.y + r):
		for x in range(b.origin.x - r, b.origin.x + b.def.size.x + r):
			if MapState.in_bounds(x, y) and s.map.is_blighted(x, y):
				n += 1
	return n


## "Makes: Materials" (the real good names of the recipe outputs), "" for buildings without a recipe.
func _makes_line(b: Building) -> String:
	if b.def.recipe == null or b.def.recipe.outputs.is_empty():
		return ""
	var names: Array[String] = []
	for g in b.def.recipe.outputs:
		var gd := s.registry.get_good(g)
		names.append(gd.display_name if gd != null else str(g))
	return "Makes: " + ", ".join(names)


## `skip_empty`: leave goods at 0 out (an empty output buffer says nothing; "Makes:" names the good).
func _goods_line(label: String, inv: Inventory, skip_empty: bool = false) -> String:
	if inv == null or inv.goods().is_empty():
		return ""
	var parts: Array[String] = []
	for g in inv.goods():
		if skip_empty and floori(inv.amount_of(g)) <= 0:
			continue
		var gd := s.registry.get_good(g)
		parts.append("%s %d" % [gd.display_name if gd != null else g, floori(inv.amount_of(g))])
	if parts.is_empty():
		return ""
	return "%s: %s" % [label, ", ".join(parts)]


## Panel data of the selected building or {} : title, lines (strings), halt text, priority, paused, site progress.
func selection() -> Dictionary:
	var b := selected()
	if b == null:
		return {}
	var lines: Array[String] = []
	var warn := ""
	if b.def.upgradable:
		lines.append("Tier %d" % b.tier)
	if b.site:
		lines.append("Under construction: %d%%" % roundi(b.build_progress() * 100.0))
		lines.append(_goods_line("Delivered", b.input_buffer))
	else:
		if b.def.worker_slots > 0:
			lines.append("Workers %d/%d" % [_workers(b), b.def.worker_slots])
		if b.def.housing_beds > 0:
			lines.append("Beds %d" % b.def.housing_beds)
		lines.append(_goods_line("Input", b.input_buffer))
		var made := _makes_line(b)
		lines.append(made)
		lines.append(_goods_line("Output", b.door_buffer, true))
		if b.inventory != null:
			lines.append(_goods_line("Stored", b.inventory))
		if not b.connected:
			warn = "Not connected to the Hearth by road"
	var halt_text := ""
	match b.halt:
		"door_full": halt_text = "Halted: output buffer full"
		"no_input": halt_text = "Halted: waiting for input"
		"no_forest": halt_text = "Halted: no forest in range"
	var bl := _blight_near(b)
	if bl > 0:
		lines.append("Blight: %d tiles" % bl)
	var clean: Array[String] = []
	for l in lines:
		if l != "":
			clean.append(l)
	return {"id": b.id, "title": b.def.display_name, "lines": clean, "halt": halt_text, "warn": warn,
			"priority": b.priority, "paused": b.paused, "site": b.site, "progress": b.build_progress()}


func set_priority(p: String) -> bool:
	return selected() != null and s.set_building_priority(selected_id, p)


func toggle_pause() -> bool:
	var b := selected()
	if b == null:
		return false
	return s.set_building_priority(b.id, "normal" if b.paused else "paused")


# ---------------------------------------------------------------- build bar

static func category_label(id: String) -> String:
	return id.capitalize()


## [{id, label, entries: [{kind: road|demolish|building, id, label, cost}]}] in design order; categories without an
## unlocked building are left out (Roads always stays). Re-ask after era_changed.
func build_bar() -> Array[Dictionary]:
	var by_cat := {}
	for def in s.unlocked_buildings():
		if def.id == "hearth":
			continue
		if not by_cat.has(def.category):
			by_cat[def.category] = []
		by_cat[def.category].append({"kind": "building", "id": def.id, "label": def.display_name,
				"cost": cost_text(def.cost), "size": "%dx%d" % [def.size.x, def.size.y]})
	var out: Array[Dictionary] = []
	for cat in CATEGORY_ORDER:
		if cat == "roads":
			var road_entries: Array = [
					{"kind": "road", "id": "road", "label": "Dirt road (R)", "cost": "", "size": ""}]
			if s.channels_unlocked():
				road_entries.append({"kind": "channel", "id": "channel", "label": "Irrigation channel (C)",
						"cost": channel_cost_text(), "size": ""})
			road_entries.append({"kind": "demolish", "id": "demolish", "label": "Demolish (X)", "cost": "", "size": ""})
			out.append({"id": "roads", "label": "Roads", "entries": road_entries})
		elif by_cat.has(cat):
			out.append({"id": cat, "label": category_label(cat), "entries": by_cat[cat]})
	var rest: Array = by_cat.keys().filter(func(c: String) -> bool: return not CATEGORY_ORDER.has(c))
	rest.sort()
	for cat: String in rest:
		out.append({"id": cat, "label": category_label(cat), "entries": by_cat[cat]})
	return out


## "1 materials" per channel tile, from WaterDef.
func channel_cost_text() -> String:
	var c := s.registry.water.channel_cost_materials if s.registry.water != null else 0.0
	return "%d materials" % roundi(c) if c > 0.0 else ""


## Player-facing reason a channel cannot be dug on a tile ("" when it can).
static func channel_refusal_text(reason: String) -> String:
	return {"materials": "Not enough materials", "locked_region": "Region not owned", "water": "Cannot dig in water",
			"out_of_bounds": "Off the map", "blocked_terrain": "Blocked", "road": "A road is here",
			"overlap": "A building is here", "channel": "Already a channel"}.get(reason, "Blocked")


static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	var ids: Array = cost.keys()
	ids.sort()
	for g in ids:
		parts.append("%d %s" % [int(cost[g]), str(g)])
	return " ".join(parts)


# ---------------------------------------------------------------- overlays

func toggle_overlay(id: String) -> bool:
	if not overlays.has(id):
		return false
	overlays[id] = not overlays[id]
	return overlays[id]


func overlay_on(id: String) -> bool:
	return overlays.get(id, false)


## Tile rectangles (clipped to the map) every finished building covers with `radius_of` (coverage_radius or market_reach):
## its footprint grown by the radius, which is exactly the Building.footprint_gap <= radius set. What the coverage
## overlay tints and outlines.
func reach_areas(kind: String) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var bounds := Rect2i(0, 0, MapState.WIDTH, MapState.HEIGHT)
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site:
			continue
		var r := b.def.coverage_radius if kind == "coverage" else b.def.market_reach
		if r > 0:
			out.append(b.footprint().grow(r).intersection(bounds))
	return out


## [{id, covered}] for every finished home: covered by a coverage building (Shrine now). The overlay's check / cross marks.
func coverage_homes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sys := s.get_system(CoverageSystem) as CoverageSystem
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.def.housing_beds <= 0:
			continue
		out.append({"id": bid, "covered": sys != null and sys.home_covered(s, bid)})
	return out


# ---------------------------------------------------------------- region map

## One row per region (index = row * 4 + col) for the region map (key M): {region, col, row, rect (tiles), owned, start,
## state (owned|buyable|locked), price (gold, buyable regions only, else 0), can_buy, reason (Settlement.can_buy_region),
## note (player text: "Owned", "Home", "Locked", "Need 50 gold" or ""), reward (id or ""), reward_label, reward_pos}.
func region_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m := s.map
	var price := s.next_region_price()
	for r in MapState.REGION_COUNT:
		var owned := m.is_region_owned(r)
		var can := s.can_buy_region(r)
		var reason: String = can["reason"]
		var buyable := not owned and reason != "not_adjacent" and reason != "unknown"
		var state := "owned" if owned else ("buyable" if buyable else "locked")
		var note := ""
		match state:
			"owned": note = "Home" if r == m.start_region else "Owned"
			"locked": note = "Locked"
			_: note = "" if can["ok"] else "Need %d gold" % price
		var reward := m.get_region_reward(r)
		out.append({"region": r, "col": r % MapState.REGION_COLS, "row": r / MapState.REGION_COLS,
				"rect": MapState.region_rect(r), "owned": owned, "start": r == m.start_region, "state": state,
				"price": price if buyable else 0, "can_buy": can["ok"], "reason": reason, "note": note,
				"reward": reward, "reward_label": REWARD_LABELS.get(reward, ""), "reward_pos": m.region_reward_pos[r]})
	return out


## Command: buy region r through the Settlement.
func buy_region(r: int) -> bool:
	return s.buy_region(r)
