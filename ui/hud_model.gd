class_name HudModel
extends RefCounted
## Everything the HUD shows, as plain data and strings (no scene tree), so it is unit-tested headless. The Control
## scenes (ui/hud.gd) only copy these values onto labels. Reads the Settlement; its only commands are the building
## priority and pause the selected-building panel offers.

const OVERLAYS: Array[String] = ["blight", "roads", "water", "coverage", "grid"]
const CATEGORY_ORDER: Array[String] = ["roads", "housing", "food", "resources", "lumen", "refining", "gold",
		"water", "logistics", "civic", "sky", "landmark"]
## Command grid (ticket 129, hud-rts-spec H2-H4): 5x3 cells at the bottom-right. A grid category gathers the building
## categories listed here (Gold buildings under Civic, Sky buildings under Logistics; BuildingDef.category unchanged).
const GRID_GROUPS := {"roads": ["roads"], "housing": ["housing"], "food": ["food"], "water": ["water"],
		"lumen": ["lumen"], "logistics": ["logistics", "sky"], "resources": ["resources"],
		"refining": ["refining"], "civic": ["civic", "gold"], "landmark": ["landmark"]}
## Top-level cells, in reading order: id, label, key, icon.
const GRID_TOP := [
		["roads", "Roads", "R", "stone"], ["housing", "Housing", "N", "pop"],
		["food", "Food", "F", "food"], ["water", "Water", "W", "water"], ["lumen", "Lumen", "I", "lumen"],
		["logistics", "Logistics", "K", "planks"], ["resources", "Resources", "S", "wood"],
		["refining", "Refining", "D", "tools"], ["civic", "Civic", "A", "spirit"],
		["landmark", "Landmark", "O", "obelisk"],
		["demolish", "Demolish", "X", "cut_stone"], ["upgrade", "Upgrade", "U", "gold"],
		["clear", "Clear", "Z", "wood"], ["plant", "Plant", "Y", "wood"], ["region", "Region", "M", "planet"]]
## Positional keys of a category pane, cell 0 first; the last cell (index 14) is More (B) or Back (Esc).
const GRID_KEYS: Array[String] = ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V"]
## Building cells a pane page holds before its last cell turns into More.
const GRID_PAGE := 14
## Top bar order (ticket 112, build_menu.png): food, bread, wood, charcoal, stone, planks, cut stone, tools, lumen,
## cells, gold; people follow in their own box.
const RESOURCES: Array[String] = ["food", "bread", "wood", "charcoal", "stone", "planks", "cut_stone", "tools", "lumen",
		"cells", "gold"]
## The fixed top-right entries (ticket 125, hud-rts-spec H5): people then the five core goods, before the pins.
const CORE_TOP: Array[String] = ["people", "food", "wood", "stone", "lumen", "gold"]
## Pinned goods shown beside the six fixed entries (ticket 125); a fourth pin drops the oldest.
const PIN_LIMIT := 3
const REWARD_LABELS := {"rich_vein": "Rich vein", "ruins": "Ruins", "fertile_valley": "Fertile valley",
		"old_forest": "Old forest", "spring": "Spring"}
const COST_ORDER: Array[String] = ["wood", "stone", "planks", "cut_stone", "tools", "lumen_cells"]
const PRIORITY_LABELS := {"low": "Low", "normal": "Normal", "high": "High"}

var s: Settlement
var notifications: NotificationCenter
## User settings hold the pinned goods (ticket 125); null in plain model tests, pins then live in memory only.
var settings: GameSettings
## Objectives panel collapsed to one line (ticket 126); read from and written to the user settings.
var _objectives_collapsed: bool = false
var _pins: Array[String] = []
var selected_id: int = -1
var overlays := {"blight": false, "roads": false, "water": false, "coverage": false, "grid": false}
## Active layer (ticket 40d): Building.LAYER_GROUND or LAYER_SKY. The one place the UI (placement, build bar, HUD tag)
## and the render (MapView.set_active_layer, via layer_changed) read. Tab toggles it; sky only while an island exists.
var active_layer: int = Building.LAYER_GROUND
signal layer_changed(layer: int)
var _deltas: Dictionary = {}
var _mark: Dictionary = {}


func _init(settlement: Settlement, game_settings: GameSettings = null) -> void:
	s = settlement
	settings = game_settings
	notifications = NotificationCenter.new(s)
	for k in RESOURCES:
		_deltas[k] = 0
	_mark = _stock()
	if settings != null:
		_objectives_collapsed = settings.objectives_collapsed
		for g in settings.pinned_goods:
			_add_pin(g)
	s.events.subscribe("day_started", _on_day)


# ---------------------------------------------------------------- top-right pins (ticket 125)

## The top-right order: the six fixed entries, then the pinned goods oldest first.
func top_goods() -> Array[String]:
	var out: Array[String] = CORE_TOP.duplicate()
	out.append_array(_pins)
	return out


## The pinned goods, oldest first.
func pinned() -> Array[String]:
	return _pins.duplicate()


func is_pinned(id: String) -> bool:
	return _pins.has(id)


## Whether `id` is a good that the pinned row can take: a top-bar good that is not one of the five fixed ones.
func can_pin(id: String) -> bool:
	return RESOURCES.has(id) and not CORE_TOP.has(id)


## Pin or unpin `id`; a fourth pin drops the oldest. Returns whether it is pinned now. A fixed entry or an unknown id
## cannot be pinned and returns false.
func toggle_pin(id: String) -> bool:
	if not can_pin(id):
		return false
	if _pins.has(id):
		_pins.erase(id)
	else:
		while _pins.size() >= PIN_LIMIT:
			_pins.pop_front()
		_pins.append(id)
	_save_pins()
	return _pins.has(id)


func _add_pin(id: String) -> void:
	if not can_pin(id) or _pins.has(id) or _pins.size() >= PIN_LIMIT:
		return
	_pins.append(id)


func _save_pins() -> void:
	if settings == null:
		return
	settings.pinned_goods = _pins.duplicate()
	settings.save()


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
	var lumen := float(t.get("lumen", 0.0))
	var gs := s.get_system(GridSystem) as GridSystem
	if gs != null:
		lumen += gs.total_charge()  # battery charge is Lumen the player owns, even though it is not in storage
	return {"food": food, "bread": float(t.get("bread", 0.0)), "wood": float(t.get("wood", 0.0)),
			"charcoal": float(t.get("charcoal", 0.0)),
			"stone": float(t.get("stone", 0.0)), "planks": float(t.get("planks", 0.0)),
			"cut_stone": float(t.get("cut_stone", 0.0)), "tools": float(t.get("tools", 0.0)), "lumen": lumen,
			"cells": float(t.get("lumen_cells", 0.0)), "gold": s.gold}


# ---------------------------------------------------------------- top bar

## [{id, icon, value, delta, value_text, delta_text, text}] for the goods in RESOURCES. delta = change over the last
## full day; the top bar draws value and delta as two lines (ticket 112) and `text` keeps the old one-line form.
func resources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now := _stock()
	for k in RESOURCES:
		var d: int = _deltas[k]
		out.append({"id": k, "icon": k, "value": floori(now[k]), "delta": d,
				"value_text": "%d" % floori(now[k]), "delta_text": delta_text(d),
				"text": "%d %s" % [floori(now[k]), delta_text(d)]})
	return out


# ---------------------------------------------------------------- Resources page (ticket 114)

## Top-bar goods whose ledger id differs.
const LEDGER_GOOD := {"cells": "lumen_cells"}


func _ledger() -> ResourceLedgerSystem:
	return s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem


## One row per good in RESOURCES: {id, name, icon, stock, change, made, used} (made/used are yesterday's).
func resource_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now := _stock()
	var ledger := _ledger()
	for k in RESOURCES:
		var y: Dictionary = ledger.yesterday(LEDGER_GOOD.get(k, k)) if ledger != null else {"made": 0.0, "used": 0.0}
		out.append({"id": k, "name": _good_name(LEDGER_GOOD.get(k, k)), "icon": k, "stock": floori(now[k]), "change": _deltas[k],
				"made": roundi(y["made"]), "used": roundi(y["used"])})
	return out


## What made `id` yesterday: [{label, amount}] biggest first. Buildings show with how many of them stand ("Woodcutter
## x3"); a Clear-tool yield reads "Clearing forest".
func made_breakdown(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ledger := _ledger()
	if ledger == null:
		return out
	var by: Dictionary = ledger.yesterday(LEDGER_GOOD.get(id, id))["made_by"]
	for def_id: String in by:
		var label := def_id.capitalize()
		if def_id.begins_with(ConstructionSystem.CLEAR_PREFIX):
			var t := s.registry.get_terrain(def_id.trim_prefix(ConstructionSystem.CLEAR_PREFIX))
			label = "Clearing %s" % (t.display_name.to_lower() if t != null else "land")
		elif def_id == "ruins":
			label = "Ruins"
		else:
			var def := s.registry.get_building(def_id)
			if def != null:
				label = def.display_name
				var n := 0
				for b: Building in s.buildings.values():
					if b.def.id == def_id and not b.site:
						n += 1
				if n > 1:
					label += " x%d" % n
		out.append({"label": label, "amount": roundi(by[def_id]), "raw": float(by[def_id])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["raw"] > b["raw"])
	return out


## Player words for the reasons a good is used (ticket 124); a "production:<def id>" key reads as the building's name.
const USED_LABELS := {"eaten": "Eaten", "construction": "Building", "light": "Light", "placement": "Placing",
		"region": "Land"}


## What used `id` yesterday: [{label, amount, raw}] biggest first, zero rows hidden. Production reads as the building
## that consumed it ("Sawmill"), the rest as the player's word for the reason ("Eaten").
func used_breakdown(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ledger := _ledger()
	if ledger == null:
		return out
	var by: Dictionary = ledger.used_breakdown(LEDGER_GOOD.get(id, id))
	for key: String in by:
		var amount := float(by[key])
		if roundi(amount) <= 0:
			continue
		out.append({"label": _used_label(key), "amount": roundi(amount), "raw": amount})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["raw"] > b["raw"])
	return out


func _used_label(key: String) -> String:
	if USED_LABELS.has(key):
		return USED_LABELS[key]
	if key.begins_with("production:"):
		var def := s.registry.get_building(key.trim_prefix("production:"))
		if def != null:
			return def.display_name
		return key.trim_prefix("production:").capitalize()
	return key.capitalize()


## The chart series for `id`: the day-start stock samples (oldest first) and today's stock last, at most 60 values.
func resource_history(id: String) -> Array[float]:
	var ledger := _ledger()
	var out: Array[float] = ledger.history(LEDGER_GOOD.get(id, id)) if ledger != null else ([] as Array[float])
	out.append(float(_stock()[id]))
	while out.size() > ResourceLedgerSystem.HISTORY_DAYS:
		out.pop_front()
	return out


static func delta_text(d: int) -> String:
	return ("+%d" % d) if d >= 0 else ("%d" % d)


func population() -> Dictionary:
	var pop := s.citizens.size()
	var beds := s.beds_total()
	var idle := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id < 0 or not s.buildings.has(c.job_id):
			idle += 1
	var g := s.get_system(GrowthSystem) as GrowthSystem
	var size := g.bar_size_now(s) if g != null else 0.0
	return {"pop": pop, "beds": beds, "idle": idle, "homeless": s.homeless_count(), "text": "%d / %d" % [pop, beds],
			"tooltip": people_text(),
			"growth": clampf(g.bar / size, 0.0, 1.0) if g != null and size > 0.0 else 0.0}


const FACTOR_NAMES := {"base": "Base", "food_types": "Food variety", "coverage": "Coverage", "hunger": "Hunger",
		"homeless": "Homeless", "blight": "Blight", "water": "Water", "darkness": "Darkness",
		"tax_office": "Tax Office", "planet_grief": "Planet grief", "light": "Lit homes"}


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


## The clock bar of the era panel (ticket 113, design D4): "Day 3, 06:40". The sim clock has whole hours only, so the
## minutes come from the fraction already simulated inside the current hour (render-side; the sim does not change).
## The last minute shown is 59, so a nearly finished hour never reads ":60".
static func clock_bar_text(day: int, hours_f: float) -> String:
	var of_day := fposmod(hours_f, 24.0)
	var hour := int(floorf(of_day))
	var minute := mini(int((of_day - float(hour)) * 60.0), 59)
	return "Day %d, %02d:%02d" % [day, hour, minute]


# ---------------------------------------------------------------- era and Dimming panel

func era_name() -> String:
	var e := s.registry.get_era(s.era_id())
	return e.display_name if e != null else s.era_id()


## "Year 1, Spring": the date line the clock panel shows.
func date_text() -> String:
	return "Year %d, %s" % [s.clock.year(), s.clock.season_name().capitalize()]


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
			"dimming_state": dimming_state(), "light": dimming_light_text(), "light_short": dimming_short_text(),
			"output": dimming_output_text(), "stock": dimming_stock_text(),
			"date": date_text()}


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
			var label := "Great Dimming" if st.get("great", false) else "Dimming"
			return "%s %s - lasts %d" % [label, "today" if n <= 0 else ("tomorrow" if n == 1 else "in %d days" % n), st["length"]]
		"active":
			var total: int = st["length"]
			if st.get("great", false):
				return "GREAT DIMMING - day %d of %d%s" % [total - int(st["days_left"]) + 1, total, " (dark)" if st["dark"] else ""]
			return "DIMMING - day %d of %d%s" % [total - int(st["days_left"]) + 1, total, " (dark)" if st["dark"] else ""]
	return "No Dimming expected"


## "x0.5" for an output factor: two decimals at most, no trailing zeros (0.25 -> "0.25", 0.5 -> "0.5").
static func factor_text(f: float) -> String:
	return ("%.2f" % f).rstrip("0").rstrip(".")


## "Light: needs 4 Lumen/day, have 10 Lumen + 0 cells (about 2 days)" during a Dimming, "" otherwise. The days are
## floor((Lumen + cells x lumen_per_cell) / need); "enough" when that covers the rest of the Dimming.
func dimming_light_text() -> String:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null:
		return ""
	var st := d.status(s)
	if st["state"] != "active":
		return ""
	var need := DimmingSystem.light_need(s)
	var t := s.totals()
	var lumen := floori(float(t.get("lumen", 0.0)))
	var cells := floori(float(t.get("lumen_cells", 0.0)))
	var per_cell := s.registry.planet.lumen_per_cell
	var days := 0
	if need > 0.0:
		days = floori((float(lumen) + float(cells) * per_cell) / need)
	var left := int(st["days_left"])
	var have := "enough" if days >= left else "about %d days" % days
	return "Light: needs %s Lumen/day, have %d Lumen + %d cells (%s)" % [num_text(need), lumen, cells, have]


## "Light short: Spirit falls" while the last day's light fell short (or the settlement is dark), "" otherwise.
func dimming_short_text() -> String:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null:
		return ""
	var st := d.status(s)
	if st["state"] != "active":
		return ""
	if bool(st["dark"]) or float(d.last_light.get("short", 0.0)) > 0.0:
		return "Light short: Spirit falls"
	return ""


## "Output: Farm x0.5, Forager x0.5, Lumen Tap x0.25" listing each finished building def a Dimming lowers today
## (at most 4 names, then "+N more"), "" outside a Dimming or when nothing is affected.
func dimming_output_text() -> String:
	if not DimmingSystem.is_active(s):
		return ""
	var affected := {}
	for id in s.buildings:
		var b: Building = s.buildings[id]
		if b.site:
			continue
		var f := DimmingSystem.output_modifier(s, b)
		if f >= 1.0:
			continue
		affected[b.display_name(s.registry)] = f
	if affected.is_empty():
		return ""
	var names: Array = affected.keys()
	names.sort()
	var parts: Array[String] = []
	for i in mini(4, names.size()):
		parts.append("%s x%s" % [names[i], factor_text(float(affected[names[i]]))])
	if names.size() > 4:
		parts.append("+%d more" % (names.size() - 4))
	return "Output: " + ", ".join(parts)


## "Stock before it: ~12 Lumen for 3 days" for a forecast Dimming (plus " and food" when the food stock, at the daily
## eating rate, would not last the wait and the Dimming), "" otherwise.
func dimming_stock_text() -> String:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null:
		return ""
	var st := d.status(s)
	if st["state"] != "forecast":
		return ""
	var length := int(st["length"])
	var target := DimmingSystem.light_need(s) * float(length)
	var line := "Stock before it: ~%s Lumen for %d days" % [num_text(target), length]
	var eat := float(s.citizens.size()) * s.registry.growth.food_per_citizen
	if eat <= 0.0:
		eat = 1.0
	var food := 0.0
	var t := s.totals()
	for g in GrowthSystem.food_goods(s.registry):
		food += float(t.get(g, 0.0))
	if food / eat < float(int(st["days_until"]) + length):
		line += " and food"
	return line


## "x0.5 Dimming" while a Dimming lowers this building's output, "" otherwise.
func dimming_building_text(b: Building) -> String:
	if b == null or b.site:
		return ""
	var f := DimmingSystem.output_modifier(s, b)
	return "" if f >= 1.0 else "x%s Dimming" % factor_text(f)


# ---------------------------------------------------------------- objectives panel (ticket 126)

## The panel's subtitle: "Town -> City: gate parts", or "Ascendant: win objectives" at the last era.
func objectives_header() -> String:
	var gate := s.era_gate()
	if gate["next"] == "":
		return "%s: win objectives" % era_name()
	var nxt := s.registry.get_era(gate["next"])
	return "%s -> %s: gate parts" % [era_name(), nxt.display_name if nxt != null else str(gate["next"])]


## The rows of the objectives panel: one per gate part of the next era (People, Gold and its landmark), or the win
## objectives at the last era. Plain data (label, value, max, done, kind) so it is testable without nodes; the HUD
## draws a bar from value/max and the text from kind.
func objectives() -> Array[Dictionary]:
	var gate := s.era_gate()
	if gate["next"] == "":
		return _win_objectives()
	var rows: Array[Dictionary] = []
	var pop_have := int(gate["pop"])
	var pop_need := int(gate["pop_need"])
	rows.append({"label": "People", "value": pop_have, "max": pop_need, "done": pop_have >= pop_need, "kind": "pop"})
	var gold_have := floori(float(gate["gold"]))
	var gold_need := int(gate["gold_need"])
	rows.append({"label": "Gold", "value": gold_have, "max": gold_need, "done": gold_have >= gold_need, "kind": "gold"})
	var lm := s.registry.get_building(gate["landmark"])
	var built := bool(gate["landmark_built"])
	rows.append({"label": lm.display_name if lm != null else str(gate["landmark"]), "value": 1 if built else 0,
			"max": 1, "done": built, "kind": "landmark"})
	return rows


## The win objectives of the last era: the Skyheart's stages, surviving the Great Dimming, and planet health at or
## above PlanetDef.win_health (the campaign's win line).
func _win_objectives() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var stage := 0
	var stages := 4
	var sky_def := s.registry.get_building("skyheart")
	if sky_def != null:
		stages = sky_def.stages.size()
	for b: Building in s.buildings.values():
		if b.def.id == "skyheart":
			stages = b.def.stages.size()
			stage = mini(b.stage, stages)
			break
	rows.append({"label": "Skyheart", "value": stage, "max": stages, "done": stage >= stages, "kind": "skyheart"})
	var gd_done := GreatDimmingSystem.is_done(s)
	rows.append({"label": "Great Dimming", "value": 1 if gd_done else 0, "max": 1, "done": gd_done,
			"kind": "great_dimming"})
	var health := roundi(s.planet_health())
	var need := roundi(s.registry.planet.win_health)
	rows.append({"label": "Planet health >= %d%%" % need, "value": health, "max": 100,
			"done": float(health) >= float(need), "kind": "planet"})
	return rows


## One line for the collapsed panel: "Objectives: City 2/3, Dimming in 2 days".
func objectives_collapsed_text() -> String:
	var rows := objectives()
	var done := 0
	for r in rows:
		if bool(r["done"]):
			done += 1
	var label := era_name()
	var gate := s.era_gate()
	if gate["next"] != "":
		var nxt := s.registry.get_era(gate["next"])
		label = nxt.display_name if nxt != null else str(gate["next"])
	return "Objectives: %s %d/%d, %s" % [label, done, rows.size(), dimming_summary()]


## The short Dimming phrase the collapsed line carries: "Dimming in 2 days", "Dimming day 1 of 3", "No Dimming
## expected".
func dimming_summary() -> String:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null:
		return "No Dimming expected"
	var st := d.status(s)
	var label := "Great Dimming" if st.get("great", false) else "Dimming"
	match st["state"]:
		"forecast":
			var n: int = st["days_until"]
			return "%s %s" % [label, "today" if n <= 0 else ("tomorrow" if n == 1 else "in %d days" % n)]
		"active":
			return "%s day %d of %d" % [label, int(st["length"]) - int(st["days_left"]) + 1, int(st["length"])]
	return "No Dimming expected"


## The Dimming lines of the objectives panel: a forecast gives "Dimming in N days, lasts M" and "Lumen output halves.
## Stock: N days."; an active Dimming gives "Dimming: day N of M" plus the light-short warning when it is short.
## Empty outside both. The numbers are the ones the old era panel gathered.
func objectives_dimming_lines() -> Array[String]:
	var d := s.get_system(DimmingSystem) as DimmingSystem
	if d == null:
		return []
	var st := d.status(s)
	var label := "Great Dimming" if st.get("great", false) else "Dimming"
	var lines: Array[String] = []
	if st["state"] == "forecast":
		var n: int = st["days_until"]
		lines.append("%s %s, lasts %d" % [label, "today" if n <= 0 else ("tomorrow" if n == 1 else "in %d days" % n),
				int(st["length"])])
		lines.append("Lumen output halves. Stock: %d days." % dimming_stock_days())
	elif st["state"] == "active":
		lines.append("%s: day %d of %d" % [label, int(st["length"]) - int(st["days_left"]) + 1, int(st["length"])])
		var short := dimming_short_text()
		if short != "":
			lines.append(short)
	return lines


## Days the Lumen stock covers the settlement's light need, the "about N days" the old panel showed: floor((Lumen +
## cells x lumen_per_cell) / need).
func dimming_stock_days() -> int:
	var need := DimmingSystem.light_need(s)
	if need <= 0.0:
		return 0
	var t := s.totals()
	var lumen := floori(float(t.get("lumen", 0.0)))
	var cells := floori(float(t.get("lumen_cells", 0.0)))
	return floori((float(lumen) + float(cells) * s.registry.planet.lumen_per_cell) / need)


## True when the objectives panel is collapsed (the one-line form); stored in the user settings.
func objectives_collapsed() -> bool:
	return _objectives_collapsed


## Collapses or expands the objectives panel and saves the state to the user settings.
func toggle_objectives_collapsed() -> bool:
	_objectives_collapsed = not _objectives_collapsed
	if settings != null:
		settings.objectives_collapsed = _objectives_collapsed
		settings.save()
	return _objectives_collapsed


# ---------------------------------------------------------------- layer (ticket 40d)

func has_islands() -> bool:
	var isys := s.get_system(IslandSystem) as IslandSystem
	return isys != null and not isys.islands.is_empty()


func layer_name() -> String:
	return "Sky" if active_layer == Building.LAYER_SKY else "Ground"


func set_layer(layer: int) -> void:
	if layer == active_layer:
		return
	active_layer = layer
	selected_id = -1
	layer_changed.emit(layer)


## Tab: ground <-> sky. With no island it stays on the ground and does nothing (ticket 98: the button is hidden
## then too). Returns the layer now active.
func toggle_layer() -> int:
	if active_layer == Building.LAYER_SKY:
		set_layer(Building.LAYER_GROUND)
	elif has_islands():
		set_layer(Building.LAYER_SKY)
	return active_layer


## The top-bar Ground/Sky button shows only once a sky island exists (or while the sky is shown).
func layer_tag_visible() -> bool:
	return has_islands() or active_layer == Building.LAYER_SKY


## Falls back to the ground when the last island is gone while the sky is shown.
func sync_layer() -> void:
	if active_layer == Building.LAYER_SKY and not has_islands():
		set_layer(Building.LAYER_GROUND)


## Why a build bar entry cannot be placed from the active layer ("" when it can). The Sky Lift always goes through the
## ground API, so it is placeable from either view.
func layer_block_reason(def: BuildingDef) -> String:
	if def.sky_lift:
		return ""
	if active_layer == Building.LAYER_SKY and def.layers == "ground":
		return "Ground only (Tab to the ground view)"
	if active_layer == Building.LAYER_GROUND and def.layers == "island":
		return "Island only (Tab to the sky view)"
	return ""


# ---------------------------------------------------------------- selection

func select(id: int) -> void:
	selected_id = id if s.buildings.has(id) else -1


func select_at(tile: Vector2i) -> void:
	var b := s.building_at(tile, active_layer)
	selected_id = b.id if b != null else -1


func clear_selection() -> void:
	selected_id = -1


func selected() -> Building:
	if selected_id >= 0 and not s.buildings.has(selected_id):
		selected_id = -1
	return s.buildings.get(selected_id)


## Citizens whose job is a slot of building b, of one kind (Citizen.JOB_WORK / JOB_HAUL / JOB_BUILD), and of `shift`
## when one is given (Citizen.SHIFT_DAY / SHIFT_NIGHT).
func _filled(b: Building, kind: String, shift: String = "") -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == kind and (shift == "" or c.shift == shift):
			n += 1
	return n


## "Workers 1/2, Haulers 1/2, Builders 3/4": filled/slots of every job kind a finished building has ("" when none).
func jobs_text(b: Building) -> String:
	var parts: Array[String] = []
	var w := b.effective_worker_slots(s.registry)
	if w > 0:
		parts.append("Workers %d/%d" % [_filled(b, Citizen.JOB_WORK), w])
	if b.def.hauler_slots > 0:
		parts.append("Haulers %d/%d" % [_filled(b, Citizen.JOB_HAUL), b.def.hauler_slots])
	if b.def.builder_slots > 0:
		parts.append("Builders %d/%d" % [_filled(b, Citizen.JOB_BUILD), b.def.builder_slots])
	return ", ".join(parts)


## Whether a finished building has a job of any kind (the work priority and Pause buttons only mean something then).
func has_jobs(b: Building) -> bool:
	return b.effective_worker_slots(s.registry) > 0 or b.def.hauler_slots > 0 or b.def.builder_slots > 0


## The Workforce page (Q): {"header": {workers, idle, haulers, builders}, "groups": [{id, label, rows}]}. One pass over
## the citizens counts the header and every building's filled slots. The first group is the construction sites
## ("sites"), then the buildings by category in build bar order. A row: {id, name, site, filled, slots, count_text
## ("3/3", "builders 4/4"), day_filled, day_slots, day_text, night_filled, night_slots, night_text, short, ok,
## has_jobs, priority, paused, no_road, note}; rows without jobs get no buttons. day_* is the day shift, night_* the
## night one: night_text is "-" without night slots and "Needs a lamp" while no lamp reaches the building (ticket 136).
## A building with no road to the Hearth (JobSystem skips it) gets "no road" instead of "N short" and stays out of the
## header's short total; paused rows keep their own text.
func workforce() -> Dictionary:
	var header := {"workers": 0, "idle": 0, "haulers": 0, "builders": 0, "short": 0}
	var filled := {}  # building id -> shift -> {work, haul, build} citizens with a job there
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id < 0 or not s.buildings.has(c.job_id):
			header["idle"] += 1  # same test as role_of, so it matches the people tooltip
			continue
		if not filled.has(c.job_id):
			filled[c.job_id] = {}
		var by_shift: Dictionary = filled[c.job_id]
		if not by_shift.has(c.shift):
			by_shift[c.shift] = {Citizen.JOB_WORK: 0, Citizen.JOB_HAUL: 0, Citizen.JOB_BUILD: 0}
		by_shift[c.shift][c.job_kind] += 1
	var crew := {}  # site id -> builders on its crew
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	if cs != null:
		for cid in cs.crews:
			crew[cs.crews[cid]] = int(crew.get(cs.crews[cid], 0)) + 1
	var crew_size := s.registry.logistics.builder_crew if s.registry.logistics != null else 0
	var sites: Array = []
	var by_cat := {}
	var lamp_tiles := _lamp_tiles()  # computed once: the night column of every row asks the same question
	var ids := s.buildings.keys()
	ids.sort()
	for id in ids:
		var b: Building = s.buildings[id]
		if not b.site and b.def.category == "housing":
			continue  # houses have no jobs and no row
		var row := {"id": b.id, "name": b.display_name(s.registry), "site": b.site, "priority": b.priority,
				"paused": b.paused, "has_jobs": b.site or has_jobs(b), "filled": 0, "slots": 0, "short": 0,
				"day_filled": 0, "day_slots": 0, "day_text": "-", "night_filled": 0, "night_slots": 0,
				"night_text": "-", "ok": true, "no_road": false, "note": "", "count_text": "", "work": 0}
		if b.site:
			row["name"] += " (site)"
			row["filled"] = int(crew.get(b.id, 0))
			row["slots"] = crew_size
			row["short"] = maxi(0, crew_size - row["filled"])
			row["count_text"] = "builders %d/%d" % [row["filled"], crew_size]
			row["day_filled"] = row["filled"]
			row["day_slots"] = crew_size
			row["day_text"] = row["count_text"]
			row["ok"] = row["short"] == 0
			row["note"] = wait_text(b)
			if not b.connected and not b.paused:
				row["no_road"] = true
				row["ok"] = false
				row["note"] = "no road"
			elif not b.paused:
				header["short"] += row["short"]
			sites.append(row)
			continue
		var by_shift: Dictionary = filled.get(b.id, {})
		var day: Dictionary = by_shift.get(Citizen.SHIFT_DAY, {})
		var night: Dictionary = by_shift.get(Citizen.SHIFT_NIGHT, {})
		var f := {
			Citizen.JOB_WORK: int(day.get(Citizen.JOB_WORK, 0)) + int(night.get(Citizen.JOB_WORK, 0)),
			Citizen.JOB_HAUL: int(day.get(Citizen.JOB_HAUL, 0)) + int(night.get(Citizen.JOB_HAUL, 0)),
			Citizen.JOB_BUILD: int(day.get(Citizen.JOB_BUILD, 0)) + int(night.get(Citizen.JOB_BUILD, 0))}
		var w := b.effective_worker_slots(s.registry)
		var kinds := [["workers", w, mini(f[Citizen.JOB_WORK], w)],
				["haulers", b.def.hauler_slots, mini(f[Citizen.JOB_HAUL], b.def.hauler_slots)],
				["builders", b.def.builder_slots, mini(f[Citizen.JOB_BUILD], b.def.builder_slots)]]
		var parts: Array[String] = []
		var only := kinds.filter(func(k: Array) -> bool: return k[1] > 0)
		for k: Array in only:
			row["slots"] += k[1]
			row["filled"] += k[2]
			parts.append(("%d/%d" if only.size() == 1 and k[0] == "workers" else {"workers": "work", "haulers": "haul", "builders": "build"}[k[0]] + " %d/%d") % [k[2], k[1]])
		header["workers"] += kinds[0][2]
		header["haulers"] += kinds[1][2]
		header["builders"] += kinds[2][2]
		row["work"] = kinds[0][2]
		row["short"] = row["slots"] - row["filled"]
		row["ok"] = row["short"] == 0
		row["count_text"] = ", ".join(parts) if not parts.is_empty() else "0/0"
		var day_w := w if not b.def.night_only else 0
		var day_kinds := [["workers", day_w, mini(int(day.get(Citizen.JOB_WORK, 0)), day_w)],
				["haulers", b.def.hauler_slots, mini(int(day.get(Citizen.JOB_HAUL, 0)), b.def.hauler_slots)],
				["builders", b.def.builder_slots, mini(int(day.get(Citizen.JOB_BUILD, 0)), b.def.builder_slots)]]
		var night_kinds := [["workers", b.def.night_worker_slots,
				mini(int(night.get(Citizen.JOB_WORK, 0)), b.def.night_worker_slots)],
				["haulers", b.def.night_hauler_slots, mini(int(night.get(Citizen.JOB_HAUL, 0)), b.def.night_hauler_slots)]]
		row["day_slots"] = _kind_total(day_kinds, 1)
		row["day_filled"] = _kind_total(day_kinds, 2)
		row["day_text"] = "-" if row["day_slots"] == 0 else _count_text(day_kinds)
		row["night_slots"] = _kind_total(night_kinds, 1)
		row["night_filled"] = _kind_total(night_kinds, 2)
		if row["night_slots"] == 0:
			row["night_text"] = "-"
		elif not _lamp_reaches(b, lamp_tiles):
			row["night_text"] = "Needs a lamp"
		else:
			row["night_text"] = _count_text(night_kinds)
		var notes: Array[String] = []
		if row["slots"] == 0:
			notes.append("no workers needed")
		if b.paused:
			notes.append("paused")
		elif not b.connected:
			row["no_road"] = true
			row["ok"] = false
			notes.append("no road")
		else:
			header["short"] += row["short"]
			if row["short"] > 0:
				notes.append("%d short" % row["short"])
		var dim := dimming_building_text(b)
		if dim != "":
			notes.append(dim)
		row["note"] = ", ".join(notes)
		if not by_cat.has(b.def.category):
			by_cat[b.def.category] = []
		by_cat[b.def.category].append(row)
	var groups: Array = []
	if not sites.is_empty():
		groups.append({"id": "sites", "label": "Construction sites", "rows": sites})
	var cats: Array = CATEGORY_ORDER.filter(func(c: String) -> bool: return by_cat.has(c))
	var rest: Array = by_cat.keys().filter(func(c: String) -> bool: return not CATEGORY_ORDER.has(c))
	rest.sort()
	for cat: String in cats + rest:
		groups.append({"id": cat, "label": category_label(cat), "rows": by_cat[cat]})
	return {"header": header, "groups": groups}


## Sum of a shift's kinds by column: 1 = slots, 2 = filled.
static func _kind_total(kinds: Array, idx: int) -> int:
	var n := 0
	for k: Array in kinds:
		n += int(k[idx])
	return n


## A shift's worker text: "3/3" for a lone worker kind, else "work 3/3, haul 4/4" like count_text.
static func _count_text(kinds: Array) -> String:
	var parts: Array[String] = []
	var only := kinds.filter(func(k: Array) -> bool: return int(k[1]) > 0)
	for k: Array in only:
		parts.append(("%d/%d" if only.size() == 1 and k[0] == "workers"
				else {"workers": "work", "haulers": "haul", "builders": "build"}[k[0]] + " %d/%d") % [k[2], k[1]])
	return ", ".join(parts)


## Every tile inside a finished lamp's radius, whatever the hour and its fuel. The night column asks coverage: a night
## building outside every lamp needs one before its slots can open (spec N2), a question that has an answer by day too.
func _lamp_tiles() -> Dictionary:
	var out := {}
	for id in s.buildings:
		var o: Building = s.buildings[id]
		if o.site or not o.def.lamp:
			continue
		var r := o.lamp_radius(s.registry)
		for lt in o.tiles():
			for y in range(lt.y - r, lt.y + r + 1):
				for x in range(lt.x - r, lt.x + r + 1):
					var d := Vector2i(x, y) - lt
					if d.x * d.x + d.y * d.y <= r * r:
						out[Vector2i(x, y)] = true
	return out


## Whether any tile of `b` is in the lamp set.
static func _lamp_reaches(b: Building, lamp_tiles: Dictionary) -> bool:
	for t in b.tiles():
		if lamp_tiles.has(t):
			return true
	return false


## The role of one citizen: "hauler", "builder", the lower-case name of the workplace ("woodcutter"), or "idle".
func role_of(c: Citizen) -> String:
	if c.job_id < 0 or not s.buildings.has(c.job_id):
		return "idle"
	match c.job_kind:
		Citizen.JOB_HAUL: return "hauler"
		Citizen.JOB_BUILD: return "builder"
	return (s.buildings[c.job_id] as Building).def.display_name.to_lower()


static func _plural(role: String, n: int) -> String:
	if n == 1 or role == "idle":
		return role
	if role.ends_with("y") and not role.right(2).left(1) in ["a", "e", "i", "o", "u"]:
		return role.left(role.length() - 1) + "ies"
	return role + "s"


## "1 hauler, 2 builders, 1 idle": counts per role, haulers and builders first, then workplaces by name, idle last.
func roles_text(citizen_ids: Array) -> String:
	var counts := {}
	for cid in citizen_ids:
		var r := role_of(s.citizens[cid])
		counts[r] = int(counts.get(r, 0)) + 1
	var order: Array = counts.keys()
	order.sort_custom(func(a: String, c: String) -> bool:
		var ra := 0 if a == "hauler" else (1 if a == "builder" else (3 if a == "idle" else 2))
		var rc := 0 if c == "hauler" else (1 if c == "builder" else (3 if c == "idle" else 2))
		return ra < rc if ra != rc else a < c)
	var parts: Array[String] = []
	for r in order:
		parts.append("%d %s" % [counts[r], _plural(r, counts[r])])
	return ", ".join(parts)


## "8 people: 2 haulers, 3 builders, 2 foragers, 1 idle" (the top-bar people tooltip).
func people_text() -> String:
	var n := s.citizens.size()
	if n == 0:
		return "No people yet"
	return "%d %s: %s" % [n, "person" if n == 1 else "people", roles_text(s.citizens.keys())]


## Citizen ids whose home is building b.
func residents_of(b: Building) -> Array:
	var out: Array = []
	for cid in s.citizens:
		if (s.citizens[cid] as Citizen).home_id == b.id:
			out.append(cid)
	return out


## "Residents 2/2" plus, when somebody lives there, one roles line ("1 hauler, 1 woodcutter" or "idle").
func resident_lines(b: Building) -> Array[String]:
	var out: Array[String] = []
	var beds := b.effective_beds(s.registry)
	if beds <= 0:
		return out
	var ids := residents_of(b)
	out.append("Residents %d/%d" % [ids.size(), beds])
	if not ids.is_empty():
		var roles := roles_text(ids)
		out.append("idle" if roles.ends_with(" idle") and not roles.contains(",") else roles)
	return out


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


## "Makes: Wood" (the real good names of the recipe outputs), "" for buildings without a recipe.
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


## "Halted: waiting for input" for a halted building, "" when it works.
func halt_text(b: Building) -> String:
	match b.halt:
		"door_full": return "Output full: no hauler has picked it up"
		"no_input": return "Halted: waiting for input"
		"no_forest": return "Halted: no forest in range"
		"island_still": return "Halted: the island is still"
		"planet_too_sick": return "Halted: planet health below %d%%" % int(b.def.min_planet_health)
		"dry": return "Halted: no water in reach"
		"too_far": return "Halted: too far from a builders' yard"
		"unlit": return "Needs a lamp"
	return ""


## One advice line for a building halted on a full door ("" for any other halt), chosen from the real state: no storage
## building in reach, hauler slots not filled, else the haulers are simply busy.
func halt_advice(b: Building) -> String:
	if b.halt != "door_full":
		return ""
	var near := s.registry.logistics.storage_near_tiles if s.registry.logistics != null else 0
	var has_storage := false
	for id in s.buildings:
		var o: Building = s.buildings[id]
		if o != b and not o.site and o.def.storage_mode != "none" and Building.footprint_gap(b, o) <= near:
			has_storage = true
			break
	if not has_storage:
		var sh := s.registry.get_building("storehouse")
		return "Build a Storehouse nearby (%d more haulers, shorter trips)" % (sh.hauler_slots if sh != null else 2)
	var slots := 0
	var filled := 0
	for id in s.buildings:
		var o: Building = s.buildings[id]
		if o.def.hauler_slots > 0 and not o.site and not o.paused and o.connected:
			slots += o.def.hauler_slots
			filled += _filled(o, Citizen.JOB_HAUL)
	if filled < slots:
		return "Haulers short: %d of %d filled (people are busy elsewhere)" % [filled, slots]
	return "Haulers are busy: add a Storehouse or a Handcart Shed"


## One line on why a construction site waits ("" when it is being built or is not a site): missing goods, builders (place
## in ready_works order), paused, no Builder's Yard in reach.
func wait_text(b: Building) -> String:
	if not b.site:
		return ""
	if b.paused:
		return "Paused"
	if b.halt == "too_far":
		return "No Builder's Yard can reach it"
	if not b.site_delivered():
		var cost := b.effective_cost()
		var parts: Array[String] = []
		for g in cost:
			if g == BuildingDef.GOLD:
				continue
			var have := b.input_buffer.amount_of(g) if b.input_buffer != null else 0.0
			if have < float(cost[g]) - Inventory.EPS:
				var gd := s.registry.get_good(g)
				parts.append("%d/%d %s" % [floori(have), int(cost[g]), (gd.display_name if gd != null else g).to_lower()])
		return "Waiting for materials: %s" % ", ".join(parts) if not parts.is_empty() else ""
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	if cs != null and cs.crews.values().has(b.id):
		return ""  # a builder is on its way or at work
	var place := ConstructionSystem.ready_works(s).find(b) + 1
	if place <= 0:
		return ""
	return "Waiting for builders (%s in line)" % _ordinal(place)


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


## Roman numerals for the tier badge (ticket 128): "Tier II".
const TIER_ROMAN: Array[String] = ["", "I", "II", "III", "IV"]
## The town summary's fixed strings (ticket 128): the settlement has no player-given name yet.
const TOWN_NAME := "Hearthvein"
const TOWN_HINT := "Click a building to see it here."  # Esc is in the help screen (ticket 130b)

## Panel data of the selected building or {} : title, lines (strings), halt text, priority, paused, site progress.
## Ticket 128 adds the rows of the fixed bottom-centre panel: tier_text, subtitle ("Refining, village era"),
## workers_text and pips, makes/uses per day, the In/Out buffer bars, the status line and "extra" (the old lines the
## panel still shows under the rows: sites, residents, reservoir, Stored, Dimming, blight). Ticket 136 puts the day
## workers in that row and adds a night row (show_night, night_filled, night_slots, night_text) where the building
## has night worker slots.
func selection() -> Dictionary:
	var b := selected()
	if b == null:
		return {}
	var lines: Array[String] = []
	var warn := ""
	if b.def.upgradable:
		lines.append("Tier %d" % b.tier)
	if b.upgrading():
		lines.append("Upgrading to Tier %d: %d%%" % [b.upgrade_tier, roundi(b.upgrade_progress() * 100.0)])
		lines.append(_goods_line("Delivered", b.upgrade_buffer))
	if b.site:
		if not b.def.stages.is_empty():
			lines.append("Stage %d of %d: %s" % [b.stage + 1, b.def.stages.size(), skyheart_stage_name(b)])
		lines.append("Under construction: %d%%" % roundi(b.build_progress() * 100.0))
		lines.append(wait_text(b))
		lines.append(_goods_line("Delivered", b.input_buffer))
	else:
		lines.append(jobs_text(b))
		lines.append_array(resident_lines(b))
		if b.def.reservoir_capacity > 0.0:
			lines.append(reservoir_text(b))
		lines.append(_goods_line("Input", b.input_buffer))
		var made := _makes_line(b)
		lines.append(made)
		lines.append(_goods_line("Output", b.door_buffer, true))
		if b.inventory != null:
			lines.append(_goods_line("Stored", b.inventory))
		if not b.connected:
			warn = "Not connected to the Hearth by road"
	var dim := dimming_building_text(b)
	if dim != "":
		lines.append(dim)
	var halt_text := halt_text(b)
	var bl := _blight_near(b)
	if bl > 0:
		lines.append("Blight: %d tiles" % bl)
	var clean: Array[String] = []
	for l in lines:
		if l != "":
			clean.append(l)
	var out := {"id": b.id, "title": b.display_name(s.registry), "lines": clean, "halt": halt_text, "warn": warn,
			"advice": halt_advice(b), "priority": b.priority, "paused": b.paused, "site": b.site,
			"progress": b.build_progress(), "show_priority": b.site or has_jobs(b),
			"priority_label": "Build priority" if b.site else "Work priority"}
	out.merge(upgrade_info(b))
	out.merge(_panel_rows(b), true)
	return out


## The fixed panel's own rows (ticket 128). Sites keep the construction lines instead of makes/workers/buffers.
func _panel_rows(b: Building) -> Dictionary:
	var workers := b.effective_worker_slots(s.registry)
	var night_slots: int = b.def.night_worker_slots
	var day_filled := mini(_filled(b, Citizen.JOB_WORK, Citizen.SHIFT_DAY), workers) if not b.site else 0
	var night_filled := mini(_filled(b, Citizen.JOB_WORK, Citizen.SHIFT_NIGHT), night_slots) if not b.site else 0
	var era := s.registry.get_era(b.def.era)
	var category := category_label(b.def.category)
	var out := {
		"tier_text": "Tier " + (TIER_ROMAN[b.tier] if b.tier >= 0 and b.tier < TIER_ROMAN.size() else str(b.tier)),
		"subtitle": "%s, %s era" % [category, (era.display_name if era != null else b.def.era).to_lower()],
		"show_workers": not b.site and workers > 0,
		"workers_filled": day_filled,
		"workers_slots": workers if not b.site else 0,
		"workers_text": "%d/%d" % [day_filled, workers] if not b.site else "",
		"show_night": not b.site and night_slots > 0,
		"night_filled": night_filled,
		"night_slots": night_slots if not b.site else 0,
		"night_text": "%d/%d" % [night_filled, night_slots] if not b.site and night_slots > 0 else "",
		"makes": "" if b.site else _per_day_text(b, b.def.recipe.outputs if b.def.recipe != null else {}, true),
		"uses": "" if b.site else _per_day_text(b, b.def.recipe.inputs if b.def.recipe != null else {}, false),
		"in_value": 0.0, "in_max": 0.0, "in_text": "",
		"out_value": 0.0, "out_max": 0.0, "out_text": "",
		"status": halt_text(b) if not b.site and halt_text(b) != "" else ("Working" if not b.site else ""),
		"extra": [],
	}
	if b.site:
		out["extra"] = (selection_lines(b) as Array).duplicate()
		out["status"] = ""  # the site rows already say what it waits for
		return out
	if b.input_buffer != null:
		var need := HaulingSystem.need_for(s.registry, b)
		out.merge(_buffer_row("in", b.input_buffer, maxi(1, need.size())), true)
	if b.door_buffer != null:
		out.merge(_buffer_row("out", b.door_buffer, 1), true)
	var extra: Array[String] = []
	extra.append_array(resident_lines(b))
	extra.append(reservoir_text(b))
	extra.append(_goods_line("Stored", b.inventory))
	extra.append(dimming_building_text(b))
	var bl := _blight_near(b)
	extra.append("Blight: %d tiles" % bl if bl > 0 else "")
	out["extra"] = extra.filter(func(l: String) -> bool: return l != "")
	return out


## "6 planks / day" (outputs) or "uses 12 wood" (inputs): one worker's recipe times the building's worker slots and
## tier output factor, the nominal daily flow the panel shows.
func _per_day_text(b: Building, amounts: Dictionary, is_output: bool) -> String:
	if amounts.is_empty():
		return ""
	var f := float(b.effective_worker_slots(s.registry)) * b.output_factor(s.registry)
	var parts: Array[String] = []
	for g in amounts:
		parts.append("%s %s" % [num_text(float(amounts[g]) * f), _good_name(g).to_lower()])
	var text := ", ".join(parts)
	return "%s / day" % text if is_output else "uses %s" % text


## One buffer bar: {prefix_value, prefix_max, prefix_text} with "22 / 40". `needed` is the good count of a per-good
## buffer, so its capacity reads as the room for all of them.
func _buffer_row(prefix: String, inv: Inventory, needed: int) -> Dictionary:
	var cap := inv.cap if inv.mode == "total" else inv.cap * float(needed)
	var amount := inv.total()
	return {prefix + "_value": amount, prefix + "_max": cap,
			prefix + "_text": "%s / %s" % [num_text(amount), num_text(cap)]}


## The old text lines of a selected building (what the panel's extra rows and the site rows come from).
func selection_lines(b: Building) -> Array:
	var lines: Array[String] = []
	if b.def.upgradable:
		lines.append("Tier %d" % b.tier)
	if b.upgrading():
		lines.append("Upgrading to Tier %d: %d%%" % [b.upgrade_tier, roundi(b.upgrade_progress() * 100.0)])
		lines.append(_goods_line("Delivered", b.upgrade_buffer))
	if b.site:
		if not b.def.stages.is_empty():
			lines.append("Stage %d of %d: %s" % [b.stage + 1, b.def.stages.size(), skyheart_stage_name(b)])
		lines.append("Under construction: %d%%" % roundi(b.build_progress() * 100.0))
		lines.append(wait_text(b))
		lines.append(_goods_line("Delivered", b.input_buffer))
	else:
		lines.append(jobs_text(b))
		lines.append_array(resident_lines(b))
		if b.def.reservoir_capacity > 0.0:
			lines.append(reservoir_text(b))
		lines.append(_goods_line("Input", b.input_buffer))
		lines.append(_makes_line(b))
		lines.append(_goods_line("Output", b.door_buffer, true))
		if b.inventory != null:
			lines.append(_goods_line("Stored", b.inventory))
	var dim := dimming_building_text(b)
	if dim != "":
		lines.append(dim)
	var bl := _blight_near(b)
	if bl > 0:
		lines.append("Blight: %d tiles" % bl)
	return lines.filter(func(l: String) -> bool: return l != "")


## The town summary the panel shows when nothing is selected (ticket 128): name, era and date, the big population
## numbers, Spirit and planet health with their trend, and the hint line. Ticket 136 adds the people on the night
## shift ("N on nights").
func town_summary() -> Dictionary:
	var pop := population()
	var sp := spirit()
	var pl := planet()
	var nights := 0
	for cid in s.citizens:
		if (s.citizens[cid] as Citizen).shift == Citizen.SHIFT_NIGHT:
			nights += 1
	return {"name": TOWN_NAME, "era": era_name(), "date": date_text(),
			"people": pop["pop"], "beds": pop["beds"], "idle": pop["idle"],
			"nights": nights, "nights_text": "%d on nights" % nights,
			"spirit": roundi(sp["value"]), "spirit_state": sp["state"], "spirit_text": "%d / 100" % roundi(sp["value"]),
			"spirit_tooltip": sp["tooltip"],
			"planet": roundi(pl["value"]), "planet_text": "%d / 100" % roundi(pl["value"]),
			"planet_trend": "%s%.1f / yr" % ["+" if pl["trend"] >= 0.0 else "-", absf(pl["trend"])],
			"hint": TOWN_HINT}


## Name of the stage a staged building is on ("" for an ordinary one or a finished one).
func skyheart_stage_name(b: Building) -> String:
	if b.def.stages.is_empty() or b.stage >= b.def.stages.size():
		return ""
	return str(b.def.stages[b.stage].get("name", ""))


## "Reservoir 120 / 3000 L" for a finished building with a reservoir (ticket 45), "" otherwise.
func reservoir_text(b: Building) -> String:
	if b.site or b.def.reservoir_capacity <= 0.0:
		return ""
	var sys := s.get_system(SkyheartSystem) as SkyheartSystem
	var held := sys.reservoir_charge(b.id) if sys != null else 0.0
	return "Reservoir %d / %d L" % [floori(held), roundi(b.def.reservoir_capacity)]


const UPGRADE_REASONS := {"unknown_building": "No building", "site": "Still under construction",
		"category": "Cannot be upgraded", "not_upgradable": "Cannot be upgraded", "in_progress": "Upgrade in progress",
		"max_tier": "Fully upgraded", "needs_wet": "Needs wet ground"}


## Short player-facing text for a Settlement.can_upgrade reason ("" for no reason).
func upgrade_reason_text(reason: String, next_tier: int = 0, def: BuildingDef = null) -> String:
	if reason == "era_locked":
		var rule := s.registry.tiers
		var td := TierRuleDef.tier_def_of(def, next_tier)
		var req_id := td.era if td != null and td.era != "" else (rule.era_for(next_tier) if rule != null else "")
		var e := s.registry.get_era(req_id)
		return "Needs %s era" % e.display_name if e != null else "Needs a later era"
	return UPGRADE_REASONS.get(reason, reason.capitalize().replace("_", " "))


## The good id whose display name (any case) or id is `name`, "" when there is none. Used to find the goods in a HUD
## line so the icon rows can draw before their numbers (ticket 112).
func good_id(name: String) -> String:
	var key := name.strip_edges().to_lower()
	for g in s.registry.goods:
		var gd := s.registry.goods[g] as GoodDef
		if key == g or key == gd.display_name.to_lower():
			return g
	return ""


## Splits a line that is all goods, like "Cost: 14 Wood, 21 Stone", "Waiting for materials: 0/10 lumen" or "Delivered:
## 12 Wood", into [{text: "Cost: "}, {good: "wood", text: "14"}, {text: ", "}, ...] so the HUD can draw each good's icon
## (ticket 112). [] when the line is not all goods (including "Cost: free" or a recipe's "6 Wood -> 3 Planks"): the HUD
## then draws it as plain text.
func line_segments(line: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cut := line.find(": ")
	if cut < 0:
		return out
	out.append({"text": line.substr(0, cut + 2)})
	var items := line.substr(cut + 2).split(", ")
	for i in items.size():
		var it := (items[i] as String).strip_edges()
		var sp := it.find(" ")
		if sp <= 0:
			return [] as Array[Dictionary]
		var num := it.substr(0, sp)
		if not num.replace("/", "").is_valid_int():
			return [] as Array[Dictionary]
		var g := good_id(it.substr(sp + 1))
		if g == "":
			return [] as Array[Dictionary]
		if i > 0:
			out.append({"text": ", "})
		out.append({"good": g, "text": num})
	return out


## "3 Planks, 2 Cut Stone": real good names, wood and stone first then by id.
func goods_cost_text(cost: Dictionary) -> String:
	var ids := _sorted_goods(cost.keys())
	var parts: Array[String] = []
	for g in ids:
		var gd := s.registry.get_good(g)
		parts.append("%d %s" % [int(cost[g]), gd.display_name if gd != null else str(g)])
	return ", ".join(parts)


## Upgrade part of the panel: tier, next_tier (0 = none), next_name, next_cost (text, wood and stone first), can_upgrade,
## upgrade_reason (text), upgrading, upgrade_progress, show_upgrade (whether the panel offers the button).
func upgrade_info(b: Building) -> Dictionary:
	var info := {"tier": b.tier, "next_tier": 0, "next_name": "", "next_cost": "", "can_upgrade": false,
			"upgrade_reason": "", "upgrading": b.upgrading(), "upgrade_progress": b.upgrade_progress(),
			"show_upgrade": false}
	if b.site or not b.def.upgradable or b.def.tiers.is_empty():
		return info
	var can := s.can_upgrade(b.id)
	var nxt := b.upgrade_tier if b.upgrading() else b.tier + 1
	if nxt > 1 + b.def.tiers.size():
		info["upgrade_reason"] = upgrade_reason_text("max_tier")
		return info
	var td := b.tier_def(s.registry, nxt)
	info["next_tier"] = nxt
	info["next_name"] = td.display_name if td != null and td.display_name != "" else \
			"%s %s" % [b.def.display_name, "I".repeat(nxt)]
	info["next_cost"] = goods_cost_text(b.tier_cost(s.registry, nxt))
	info["can_upgrade"] = can["ok"]
	info["upgrade_reason"] = upgrade_reason_text(can["reason"], nxt, b.def)
	info["show_upgrade"] = not b.upgrading()
	return info


## Command: upgrade the selected building (U key / Upgrade button). False when it is refused.
func upgrade() -> bool:
	return selected() != null and s.upgrade(selected_id)


func set_priority(p: String) -> bool:
	return selected() != null and s.set_building_priority(selected_id, p)


func toggle_pause() -> bool:
	var b := selected()
	if b == null:
		return false
	return s.set_building_priority(b.id, "normal" if b.paused else "paused")


# ---------------------------------------------------------------- tooltips

## "4.5" or "8": whole numbers without a decimal point.
static func num_text(v: float) -> String:
	return "%d" % roundi(v) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).rstrip("0").rstrip(".")


func _good_name(g: String) -> String:
	var gd := s.registry.get_good(g)
	return gd.display_name if gd != null else g


## "6 Wood, 2 Lumen" from a recipe side (good id -> float, per worker per day).
func _amounts_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	for g in d:
		parts.append("%s %s" % [num_text(float(d[g])), _good_name(g)])
	return ", ".join(parts)


## The data lines of a def (cost, jobs, recipe, upkeep, reach, beds, storage). `b` (or null) scales slots and beds by tier.
func _def_tooltip_lines(def: BuildingDef, b: Building) -> Array[String]:
	var lines: Array[String] = []
	if b == null or b.site:
		var cost := goods_cost_text(s.cost_for(def.id) if b == null else def.entry_cost())
		lines.append("Cost: %s" % (cost if cost != "" else "free"))
	var jobs: Array[String] = []
	if b != null and not b.site:
		pass  # a placed building shows filled/slots in its status (jobs_text)
	else:
		if def.worker_slots > 0 and b == null:
			jobs.append("Workers %d" % def.worker_slots)
		if def.hauler_slots > 0:
			jobs.append("Haulers %d" % def.hauler_slots)
		if def.builder_slots > 0:
			jobs.append("Builders %d" % def.builder_slots)
	if not jobs.is_empty():
		lines.append(", ".join(jobs))
	var r := def.recipe
	if r != null:
		var ins := _amounts_text(r.inputs)
		if r.any_input_count > 0:
			var any := "%s each of any %d foods" % [num_text(r.any_input_amount), r.any_input_count]
			ins = any if ins == "" else "%s, %s" % [ins, any]
		var outs := _amounts_text(r.outputs)
		if b != null:
			outs = _amounts_text(_scaled(r.outputs, b.output_factor(s.registry)))
		lines.append(("Per worker per day: %s -> %s" % [ins, outs]) if ins != "" else "Per worker per day: %s" % outs)
	if def.gold_per_worker_day > 0.0:
		lines.append("Earns %s Gold per worker per day" % num_text(def.gold_per_worker_day))
	if def.gold_per_citizen_day > 0.0:
		lines.append("Earns %s Gold per citizen per day" % num_text(def.gold_per_citizen_day))
	if def.upkeep_lumen > 0.0:
		lines.append("Upkeep: %s Lumen per day" % num_text(def.upkeep_lumen))
	for pair in [[def.coverage_radius, "Cheers homes within %d tiles"], [def.water_radius, "Waters homes within %d tiles"],
			[def.market_reach, "Serves homes within %d tiles"], [def.clean_radius, "Cleans blight within %d tiles"],
			[def.blight_block_radius, "Keeps new blight off within %d tiles"],
			[def.grid_feed_radius, "Feeds Lumen to buildings within %d tiles"],
			[def.heal_blight_radius, "Heals land within %d tiles"], [def.rewild_radius, "Regrows forest within %d tiles"],
			[def.drain_radius, "Eases extractor damage within %d tiles"]]:
		if int(pair[0]) > 0:
			lines.append(str(pair[1]) % int(pair[0]))
	if def.placement_radius > 0 and (def.fells_forest or def.plants_forest or def.placement_rule.begins_with("near_")):
		lines.append("Works within %d tiles" % def.placement_radius)
	if def.placement_rule == "shade":
		lines.append("Needs %d forest tiles within %d tiles" % [Placement.SHADE_FOREST_TILES, def.placement_radius])
	var beds := b.effective_beds(s.registry) if b != null else def.housing_beds
	if beds > 0:
		lines.append("Beds %d" % beds)
	match def.storage_mode:
		"total": lines.append("Stores %d goods in all" % def.storage_cap)
		"per_good": lines.append("Stores %d of each good" % def.storage_cap)
	if def.battery_capacity > 0.0:
		lines.append("Holds %s Lumen" % num_text(def.battery_capacity))
	return lines


func _scaled(d: Dictionary, f: float) -> Dictionary:
	var out := {}
	for g in d:
		out[g] = float(d[g]) * f
	return out


func _tooltip(title: String, def: BuildingDef, status: Array[String], lines: Array[String]) -> Dictionary:
	var parts: Array[String] = [title, def.description]
	parts.append_array(status)
	parts.append_array(lines)
	var clean: Array[String] = []
	for p in parts:
		if p != "":
			clean.append(p)
	return {"title": title, "description": def.description, "status": status, "lines": lines, "text": "\n".join(clean)}


## Tooltip of a build button: {title, description, status (empty), lines, text}. {} for an unknown id.
func tooltip_for(def_id: String) -> Dictionary:
	var def := s.registry.get_building(def_id)
	if def == null:
		return {}
	return _tooltip(def.display_name, def, [] as Array[String], _def_tooltip_lines(def, null))


## Tooltip of a placed building: the same, plus its status (tier, site progress, workers filled n/m, halt reason).
func tooltip_for_building(b: Building) -> Dictionary:
	var status: Array[String] = []
	if b.def.upgradable and not b.site:
		status.append("Tier %d" % b.tier)
	if b.site:
		status.append("Under construction: %d%%" % roundi(b.build_progress() * 100.0))
		var wait := wait_text(b)
		if wait != "":
			status.append(wait)
	else:
		var jt := jobs_text(b)
		if jt != "":
			status.append(jt)
		status.append_array(resident_lines(b))
		var halt := halt_text(b)
		if halt != "":
			status.append(halt)
			var adv := halt_advice(b)
			if adv != "":
				status.append(adv)
		if not b.connected:
			status.append("Not connected to the Hearth by road")
	var dim := dimming_building_text(b)
	if dim != "":
		status.append(dim)
	return _tooltip(b.display_name(s.registry), b.def, status, _def_tooltip_lines(b.def, b))


## Tooltip of a tile marked for clearing: {title, description, status, lines, text}, {} when the tile is not marked. Says
## what it gives and how long it takes, and that no Builder's Yard reaches it when that is so (like a site's wait line).
func clear_tooltip(tile: Vector2i) -> Dictionary:
	if not s.is_clear_marked(tile):
		return {}
	var tdef := s.registry.get_terrain(s.map.terrain_id_at(tile.x, tile.y))
	var gd := s.registry.get_good(tdef.clear_good) if tdef != null else null
	var what := tdef.display_name if tdef != null else "Tile"
	var desc := ""
	if tdef != null:
		desc = "Builders clear it in %d work hours and bring %d %s to storage." % [roundi(tdef.clear_hours),
				roundi(tdef.clear_amount), (gd.display_name if gd != null else tdef.clear_good).to_lower()]
		if tdef.id == "rock":
			desc += " Cleared rock is no longer a quarry spot."
	var status: Array[String] = []
	var cs := s.get_system(ConstructionSystem) as ConstructionSystem
	if cs != null and cs.clear_far.has(MapState.idx(tile.x, tile.y)):
		status.append("No Builder's Yard can reach it")
	elif cs != null and tdef != null:
		status.append("Cleared: %d%%" % roundi(float(cs.clear_marks.get(MapState.idx(tile.x, tile.y), 0.0)) / tdef.clear_hours * 100.0))
	var title := "Marked for clearing: %s" % what
	var lines: Array[String] = []
	var parts: Array[String] = [title, desc]
	parts.append_array(status)
	return {"title": title, "description": desc, "status": status, "lines": lines, "text": "\n".join(parts)}


## Tooltip of a tile marked for planting: {title, description, status, lines, text}, {} when it is not marked.
func plant_tooltip(tile: Vector2i) -> Dictionary:
	if not s.is_plant_marked(tile):
		return {}
	var title := "Marked for planting"
	var desc := "A Forester in reach plants this tile before any other grass."
	var status: Array[String] = []
	if s.plant_mark_unreached(tile):
		status.append("No Forester reaches it")
	return _tile_tip(title, desc, status)


## Tooltip of a stump: when it regrows into forest, or why it will not (from ForestSystem's real timer and rules).
## {} when the tile is not a stump.
func stump_tooltip(tile: Vector2i) -> Dictionary:
	var fs := s.get_system(ForestSystem) as ForestSystem
	if fs == null:
		return {}
	var info := fs.regrow_info(s, tile)
	var line := ""
	match str(info["state"]):
		"grows":
			var d := int(info["days"])
			line = "Regrows in about %d %s" % [d, "day" if d == 1 else "days"]
		"blighted": line = "Won't regrow: blighted"
		"health": line = "Won't regrow: planet health below %d" % roundi(s.registry.forest.regrow_min_health)
		"covered": line = "Won't regrow: something is built on it"
		_: return {}
	var status: Array[String] = [line]
	return _tile_tip("Stump", "Felled forest.", status)


func _tile_tip(title: String, desc: String, status: Array[String]) -> Dictionary:
	var lines: Array[String] = []
	var parts: Array[String] = [title]
	if desc != "":
		parts.append(desc)
	parts.append_array(status)
	return {"title": title, "description": desc, "status": status, "lines": lines, "text": "\n".join(parts)}


# ---------------------------------------------------------------- build bar

static func category_label(id: String) -> String:
	return id.capitalize()


## What the player owns of each good, for the "have N" numbers: storage totals plus the gold purse.
func _have_all() -> Dictionary:
	var t := s.totals()
	t["gold"] = s.gold
	return t


## The cost of `def` per good for a build card: [{good, icon, name, need, have, short}], wood and stone first.
## `have` is _have_all() (computed when left out). The icon is "" for a good with no icon of its own.
func cost_rows(def: BuildingDef, have: Dictionary = {}) -> Array[Dictionary]:
	if have.is_empty():
		have = _have_all()
	var cost := s.cost_for(def.id, have)
	var out: Array[Dictionary] = []
	for g: String in _sorted_goods(cost.keys()):
		var need := int(cost[g])
		var own := int(floorf(float(have.get(g, 0.0))))
		out.append({"good": g, "icon": icon_id(g), "name": _good_name(g), "need": need, "have": own, "short": own < need})
	return out


func _sorted_goods(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a: String, c: String) -> bool:
		var ra := COST_ORDER.find(a) if COST_ORDER.has(a) else COST_ORDER.size()
		var rc := COST_ORDER.find(c) if COST_ORDER.has(c) else COST_ORDER.size()
		return ra < rc if ra != rc else a < c)
	return out


## The HUD icon id of a good ("cells" for lumen cells, "food" for any food good), "" when it has none.
func icon_id(good: String) -> String:
	var icons: Dictionary = ArtLibrary.manifest()["icons"]
	if good == "lumen_cells":
		return "cells"
	if icons.has(good):
		return good
	if GrowthSystem.food_goods(s.registry).has(good):
		return "food"
	return ""


## The detail panel of a build card (ticket 117), {} for an unknown id: title, kind ("Refining, Village era"),
## description, costs (cost_rows, with have), workers, size ("2 x 1 tiles"), inputs / outputs of the recipe per worker per
## day ([{good, icon, name, amount}]), extra (other data lines: reach, beds, storage...), unlock ("Village era
## (unlocked)" / "Needs City era"), locked and reason (why the button is off, "" when it is not).
func detail_for(def_id: String) -> Dictionary:
	var def := s.registry.get_building(def_id)
	if def == null:
		return {}
	var era := s.registry.get_era(def.era)
	var era_name := era.display_name if era != null else def.era
	var locked := not s.is_unlocked(def)
	var inputs: Array[Dictionary] = []
	var outputs: Array[Dictionary] = []
	var r := def.recipe
	if r != null:
		for g: String in r.inputs:
			inputs.append(_flow_row(g, float(r.inputs[g])))
		if r.any_input_count > 0:
			inputs.append({"good": "", "icon": "food", "name": "any %d foods" % r.any_input_count,
					"amount": num_text(r.any_input_amount)})
		for g: String in r.outputs:
			outputs.append(_flow_row(g, float(r.outputs[g])))
	var extra: Array[String] = []
	for l in _def_tooltip_lines(def, null):
		if not (l.begins_with("Cost:") or l.begins_with("Workers ") or l.begins_with("Per worker per day")):
			extra.append(l)
	return {"id": def.id, "title": def.display_name, "kind": "%s, %s era" % [category_label(def.category), era_name],
			"description": def.description, "costs": cost_rows(def), "workers": def.worker_slots,
			"size": "%d x %d tiles" % [def.size.x, def.size.y], "inputs": inputs, "outputs": outputs, "extra": extra,
			"unlock": "Needs %s era" % era_name if locked else "%s era (unlocked)" % era_name, "locked": locked,
			"reason": layer_block_reason(def)}


func _flow_row(good: String, amount: float) -> Dictionary:
	return {"good": good, "icon": icon_id(good), "name": _good_name(good), "amount": num_text(amount)}


## Defs of the era right after the current one (shown locked in the build menu), by era order then id.
func _next_era_defs() -> Array[BuildingDef]:
	var cur := s.registry.get_era(s.era_id())
	var out: Array[BuildingDef] = []
	if cur == null:
		return out
	for d: BuildingDef in s.registry.buildings.values():
		var e := s.registry.get_era(d.era)
		if e != null and e.order == cur.order + 1:
			out.append(d)
	out.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool: return a.id < b.id)
	return out


## "Needs City era" for a def the current era has not reached, "" otherwise.
func unlock_text(def: BuildingDef) -> String:
	if s.is_unlocked(def):
		return ""
	var e := s.registry.get_era(def.era)
	return "Needs %s era" % (e.display_name if e != null else def.era)


## [{id, label, entries: [{kind: road|demolish|building, id, label, cost}]}] in design order; categories without an
## unlocked building are left out (Roads always stays). Re-ask after era_changed.
func build_bar() -> Array[Dictionary]:
	var by_cat := {}
	var have := _have_all()
	for def in s.unlocked_buildings():
		if def.id == "hearth":
			continue
		if not by_cat.has(def.category):
			by_cat[def.category] = []
		var block := layer_block_reason(def)
		var costs := cost_rows(def, have)
		by_cat[def.category].append({"kind": "building", "id": def.id, "label": def.display_name,
				"cost": goods_cost_text(s.cost_for(def.id, have)), "size": "%dx%d" % [def.size.x, def.size.y],
				"reason": block, "enabled": block == "", "locked": false, "unlock": "", "costs": costs,
				"short": costs.any(func(c: Dictionary) -> bool: return c["short"])})
	# Ticket 116: the next era's buildings show locked (greyed, with the reason) next to the unlocked ones of their category.
	for def in _next_era_defs():
		if def.id != "hearth" and by_cat.has(def.category):
			by_cat[def.category].append({"kind": "building", "id": def.id, "label": def.display_name,
					"cost": goods_cost_text(def.entry_cost()), "size": "%dx%d" % [def.size.x, def.size.y],
					"reason": unlock_text(def), "enabled": false, "locked": true, "unlock": unlock_text(def),
					"costs": cost_rows(def, have), "short": false})
	var out: Array[Dictionary] = []
	for cat in CATEGORY_ORDER:
		if cat == "roads":
			var road_entries: Array = [
					{"kind": "road", "id": "road", "label": "Dirt road (R)", "cost": "", "size": ""}]
			if s.channels_unlocked():
				road_entries.append({"kind": "channel", "id": "channel", "label": "Irrigation channel (C)",
						"cost": channel_cost_text(), "size": "", "tip": channel_help_text()})
			if s.paved_roads_unlocked():
				road_entries.append({"kind": "paved", "id": "paved", "label": "Paved road (P)",
						"cost": paved_cost_text(), "size": ""})
			if s.track_unlocked():
				road_entries.append({"kind": "track", "id": "track", "label": "Rail track (J)",
						"cost": track_cost_text(), "size": ""})
			road_entries.append({"kind": "demolish", "id": "demolish", "label": "Demolish (X)", "cost": "", "size": ""})
			out.append({"id": "roads", "label": "Roads", "entries": road_entries})
		elif by_cat.has(cat):
			out.append({"id": cat, "label": category_label(cat), "entries": by_cat[cat]})
	var rest: Array = by_cat.keys().filter(func(c: String) -> bool: return not CATEGORY_ORDER.has(c))
	rest.sort()
	for cat: String in rest:
		out.append({"id": cat, "label": category_label(cat), "entries": by_cat[cat]})
	return out


# ---------------------------------------------------------------- command grid (ticket 129)

## The 15 cells of the command grid. page is "" for the top level, a grid category id for its pane, and
## "<category>:<n>" for page n of a pane that has more than GRID_PAGE entries. Each cell is
## {id, label, key, icon, state: ok|locked|unaffordable|empty, reason}; the last cell is More (key B) or Back (key
## Esc). An empty cell is a free grid slot or a category with nothing unlocked.
func grid(page: String) -> Array[Dictionary]:
	var bar := build_bar()
	if page == "" or page == "top":
		return _grid_top(bar)
	var bits := page.split(":")
	var cat := bits[0]
	var no := maxi(1, int(bits[1])) if bits.size() > 1 else 1
	return _grid_pane(cat, no, bar)


## The pane title: "Build" at the top level, else the category's name.
func grid_title(page: String) -> String:
	if page == "" or page == "top":
		return "Build"
	return category_label(page.split(":")[0])


## The grid category a building category is shown under (Gold under Civic, Sky under Logistics; others themselves).
static func grid_group(category: String) -> String:
	for g: String in GRID_GROUPS:
		if (GRID_GROUPS[g] as Array).has(category):
			return g
	return category


## Whether id names a top-level category cell (as opposed to an action cell).
static func is_grid_category(id: String) -> bool:
	return GRID_GROUPS.has(id)


func _grid_top(bar: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell: Array in GRID_TOP:
		var id := str(cell[0])
		var st := _top_state(id, bar)
		out.append({"id": id, "label": cell[1], "key": cell[2], "icon": cell[3],
				"state": st["state"], "reason": st["reason"]})
	return out


## ok when the category has something to build, locked when all it has is locked, empty when it has nothing.
func _top_state(id: String, bar: Array) -> Dictionary:
	if not GRID_GROUPS.has(id):
		return {"state": "ok", "reason": ""}
	var entries := _pane_entries(id, bar)
	if entries.is_empty():
		return {"state": "empty", "reason": ""}
	for e: Dictionary in entries:
		if str(e["state"]) != "locked":
			return {"state": "ok", "reason": ""}
	return {"state": "locked", "reason": str(entries[0]["reason"])}


func _grid_pane(cat: String, no: int, bar: Array) -> Array[Dictionary]:
	var all := _pane_entries(cat, bar)
	var start := (no - 1) * GRID_PAGE
	var out: Array[Dictionary] = []
	for i in range(start, start + GRID_PAGE):
		if i < all.size():
			var c: Dictionary = all[i].duplicate()
			c["key"] = GRID_KEYS[out.size()]
			out.append(c)
		else:
			out.append({"id": "", "label": "", "key": GRID_KEYS[out.size()], "icon": "", "state": "empty",
					"reason": ""})
	if start + GRID_PAGE < all.size():
		out.append({"id": "more", "label": "More", "key": "B", "icon": "", "state": "ok", "reason": ""})
	else:
		out.append({"id": "back", "label": "Back", "key": "Esc", "icon": "", "state": "ok", "reason": ""})
	return out


## The category's cells, unlocked then next-era locked (ticket 116), in build_bar order. Roads keeps its road tools
## (Demolish has its own top-level cell now).
func _pane_entries(cat: String, bar: Array = []) -> Array[Dictionary]:
	if bar.is_empty():
		bar = build_bar()
	var groups: Array = GRID_GROUPS.get(cat, [cat])
	var out: Array[Dictionary] = []
	for group: Dictionary in bar:
		if not groups.has(group["id"]):
			continue
		for e: Dictionary in group["entries"]:
			if cat == "roads" and str(e["kind"]) == "demolish":
				continue
			out.append(_grid_cell(e))
	return out


## One build_bar entry as a grid cell: an unlocked building is ok or unaffordable (some good short), a locked one
## says why on hover, and a building blocked by the active layer counts as locked with its block reason.
func _grid_cell(e: Dictionary) -> Dictionary:
	var locked := bool(e.get("locked", false))
	var state := "ok"
	var reason := ""
	if locked or not bool(e.get("enabled", true)):
		state = "locked"
		reason = str(e.get("unlock", "")) if locked else str(e.get("reason", ""))
		if reason == "":
			reason = str(e.get("reason", ""))
	elif bool(e.get("short", false)):
		state = "unaffordable"
		reason = _short_reason(e.get("costs", []))
	var label := str(e["label"])
	if str(e["kind"]) != "building":
		label = label.get_slice(" (", 0)  # the positional key replaces the old hotkey hint
	return {"id": str(e["id"]), "label": label, "key": "", "icon": "", "state": state, "reason": reason,
			"tip": str(e.get("tip", ""))}


## "Not enough Wood, Stone" for the goods a cost is short of, "" when nothing is short.
func _short_reason(costs: Array) -> String:
	var names: Array[String] = []
	for c: Dictionary in costs:
		if bool(c.get("short", false)):
			names.append(str(c.get("name", c.get("good", ""))))
	return "Not enough %s" % ", ".join(names) if not names.is_empty() else ""


## What an Irrigation Channel does, from WaterDef ("" without it).
func channel_help_text() -> String:
	return s.registry.water.channel_help() if s.registry.water != null else ""


## "1 Stone" per channel tile, from WaterDef.
func channel_cost_text() -> String:
	var c := s.registry.water.channel_cost_stone if s.registry.water != null else 0.0
	return goods_cost_text({"stone": roundi(c)}) if c > 0.0 else ""


## "1 Wood, 1 Stone, 1 Cut stone" per track tile, from LogisticsDef.
func track_cost_text() -> String:
	var lg := s.registry.logistics
	if lg == null:
		return ""
	var c := {}
	if lg.track_cost_wood > 0.0:
		c["wood"] = lg.track_cost_wood
	if lg.track_cost_stone > 0.0:
		c["stone"] = lg.track_cost_stone
	if lg.track_cost_cut_stone > 0.0:
		c["cut_stone"] = lg.track_cost_cut_stone
	return goods_cost_text(c)


## "5 Wood" extra for one water tile of road at `level` (a bridge), "" when the road has no bridge cost.
func bridge_cost_text(level: int) -> String:
	var rd := s.registry.get_road_by_level(level)
	return goods_cost_text(rd.bridge_cost) if rd != null and not rd.bridge_cost.is_empty() else ""


## "3 Wood, 3 Stone, 3 Cut stone" for one rail bridge tile (track on water).
func track_bridge_cost_text() -> String:
	var lg := s.registry.logistics
	if lg == null:
		return ""
	var c := {}
	if lg.track_cost_wood > 0.0:
		c["wood"] = lg.track_cost_wood * lg.track_bridge_multiplier
	if lg.track_cost_stone > 0.0:
		c["stone"] = lg.track_cost_stone * lg.track_bridge_multiplier
	if lg.track_cost_cut_stone > 0.0:
		c["cut_stone"] = lg.track_cost_cut_stone * lg.track_bridge_multiplier
	return goods_cost_text(c)


## Player-facing reason a track tile cannot be laid.
static func track_refusal_text(reason: String) -> String:
	return {"wood": "Not enough wood", "stone": "Not enough stone", "cut_stone": "Not enough cut stone", "locked_region": "Region not owned",
			"water": "Cannot lay track on water", "out_of_bounds": "Off the map", "blocked_terrain": "Blocked",
			"road": "A road is here", "overlap": "A building is here", "channel": "A channel is here",
			"track": "Already laid"}.get(reason, "Blocked")


## "1 Wood, 0.2 Cut Stone" for one paved tile, from the paved RoadDef (stone shown per whole tile as the data
## states it, e.g. 0.2).
func paved_cost_text() -> String:
	var rd := s.registry.get_road_by_level(Settlement.ROAD_PAVED)
	if rd == null or rd.cost.is_empty():
		return ""
	var ids: Array = rd.cost.keys()
	ids.sort_custom(func(a: String, c: String) -> bool:
		var ra := COST_ORDER.find(a) if COST_ORDER.has(a) else COST_ORDER.size()
		var rc := COST_ORDER.find(c) if COST_ORDER.has(c) else COST_ORDER.size()
		return ra < rc if ra != rc else a < c)
	var parts: Array[String] = []
	for g in ids:
		var v := float(rd.cost[g])
		var gd := s.registry.get_good(g)
		var nm: String = gd.display_name if gd != null else str(g)
		parts.append(("%d %s" % [int(v), nm]) if is_equal_approx(v, roundf(v)) else ("%s %s" % [str(v), nm]))
	return ", ".join(parts)


## Player-facing reason a paved tile cannot be laid ("" is never asked for).
static func paved_refusal_text(reason: String) -> String:
	return {"wood": "Not enough wood", "stone": "Not enough stone", "cut_stone": "Not enough cut stone", "era_locked": "Needs the Town era",
			"already_paved": "Already paved", "locked_region": "Region not owned", "water": "Cannot pave water",
			"out_of_bounds": "Off the map", "blocked_terrain": "Blocked", "overlap": "A building is here",
			"channel": "A channel is here"}.get(reason, "Blocked")


## Player-facing reason a tile cannot be marked for clearing.
static func clear_refusal_text(reason: String) -> String:
	return {"not_clearable": "only forest, stumps and rock can be cleared", "locked_region": "Region not owned",
			"out_of_bounds": "Off the map", "overlap": "A building is here", "road": "A road is here"}.get(reason, "Blocked")


## Player-facing reason a tile cannot be marked for planting.
static func plant_refusal_text(reason: String) -> String:
	return {"not_plantable": "only plain grass can be planted", "locked_region": "Region not owned",
			"out_of_bounds": "Off the map", "overlap": "A building is here", "road": "A road is here",
			"blighted": "Blighted", "clear_marked": "Marked for clearing"}.get(reason, "Blocked")


## Player-facing reason a channel cannot be dug on a tile ("" when it can).
static func channel_refusal_text(reason: String) -> String:
	return {"stone": "Not enough stone", "locked_region": "Region not owned", "water": "Cannot dig in water",
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
		var r := b.def.market_reach
		if kind == "coverage":
			r = b.def.coverage_radius
		elif kind == "water":
			r = b.def.water_radius
		if r > 0:
			out.append(b.footprint().grow(r).intersection(bounds))
	return out


## Every fouled tile as a Vector2i, row by row (the water overlay marks them). Reads the sim's fouled mask.
func fouled_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f := s.map.fouled
	for i in f.size():
		if f[i] != 0:
			out.append(Vector2i(i % MapState.WIDTH, i / MapState.WIDTH))
	return out


## [{id, watered}] for every finished home that needs drinking water: served by a Well-type source. The water overlay's
## check / cross marks.
func water_homes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sys := s.get_system(CoverageSystem) as CoverageSystem
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or not b.def.needs_water:
			continue
		out.append({"id": bid, "watered": sys != null and sys.home_has_water(s, bid)})
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


# ---------------------------------------------------------------- Lumen grid overlay (ticket 36c)

## One entry per grid: {id, nodes (building ids), tiles (Array[Vector2i] the grid feeds), supply, charge, capacity}.
## Empty before any Lumen Pylon or Nexus is finished.
func grid_ranges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gs := s.get_system(GridSystem) as GridSystem
	if gs == null:
		return out
	for gid in gs.grid_ids(s):
		var tiles: Array[Vector2i] = []
		tiles.assign(gs.covered_tiles(s, gid).keys())
		out.append({"id": gid, "nodes": gs.nodes_of(s, gid), "tiles": tiles, "supply": gs.supply(s, gid),
				"charge": gs.battery_charge(s, gid), "capacity": gs.battery_capacity(s, gid)})
	return out


## Pylon / Nexus links as [from, to] tile-centre pairs in tile units (a tile (x, y) has its centre at x + 0.5, y + 0.5;
## a node's centre is the middle of its footprint).
func grid_links() -> Array[Array]:
	var out: Array[Array] = []
	var gs := s.get_system(GridSystem) as GridSystem
	if gs == null:
		return out
	for l: Array in gs.links(s):
		var a: Building = s.buildings[l[0]]
		var b: Building = s.buildings[l[1]]
		out.append([Vector2(a.origin) + Vector2(a.def.size) * 0.5, Vector2(b.origin) + Vector2(b.def.size) * 0.5, l[0], l[1]])
	return out


## [{id, fed, grid}] for every finished building that pays Lumen upkeep or takes Lumen as a recipe input. fed = it is on a
## grid that holds supply or battery charge. The overlay's check / cross marks.
func grid_consumers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gs := s.get_system(GridSystem) as GridSystem
	var cache := {}
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site:
			continue
		var takes := b.def.upkeep_lumen > 0.0 or (b.def.recipe != null and b.def.recipe.inputs.has("lumen"))
		if not takes:
			continue
		var gid := gs.grid_of(s, bid) if gs != null else -1
		var fed := false
		if gid >= 0:
			if not cache.has(gid):
				cache[gid] = gs.supply(s, gid) > Inventory.EPS or gs.battery_charge(s, gid) > Inventory.EPS
			fed = cache[gid]
		out.append({"id": bid, "fed": fed, "grid": gid})
	return out


## [{id, charge, capacity, fraction}] for every finished Grid Battery (any building with battery_capacity).
func grid_batteries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gs := s.get_system(GridSystem) as GridSystem
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.def.battery_capacity <= 0.0:
			continue
		var c := gs.charge_of(bid) if gs != null else 0.0
		out.append({"id": bid, "charge": c, "capacity": b.def.battery_capacity, "fraction": c / b.def.battery_capacity})
	return out


## A small number that changes when what the grid overlay shows changes between building events (charge, supply, fed
## state), so the view redraws only then.
func grid_stamp() -> int:
	var gs := s.get_system(GridSystem) as GridSystem
	if gs == null:
		return 0
	var n := 0
	for gid in gs.grid_ids(s):
		n = n * 31 + floori(gs.battery_charge(s, gid) / 5.0) + int(gs.supply(s, gid) > Inventory.EPS) * 7
	return n


# ---------------------------------------------------------------- region map

## One row per region (index = row * 4 + col) for the region map (key M): {region, col, row, rect (tiles), owned, start,
## state (owned|buyable|locked), price (gold, buyable regions only, else 0), can_buy, reason (Settlement.can_buy_region),
## note (player text: "Owned", "Home", "Locked", "Need 50 gold" or ""), reward (id or ""; the marker, always shown),
## reward_label, reward_pos, revealed (owned or surveyed by an Airship Dock, ticket 38), reward_detail (exact type
## detail like "Yield x1.5" or "100 gold"; "" until revealed), surveying (a flight is out), survey_days_left (hours
## left / 24, 0 when none), can_survey (a staffed idle dock could fly it now), survey_reason (AirshipSystem.survey_refusal)}.
func region_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m := s.map
	var price := s.next_region_price()
	var air := s.get_system(AirshipSystem) as AirshipSystem
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
		var revealed := air != null and air.is_revealed(s, r)
		var flight: Dictionary = air.survey_of(r) if air != null else {}
		var sreason: String = air.survey_refusal(s, r) if air != null else "no_dock"
		out.append({"region": r, "col": r % MapState.REGION_COLS, "row": r / MapState.REGION_COLS,
				"rect": MapState.region_rect(r), "owned": owned, "start": r == m.start_region, "state": state,
				"price": price if buyable else 0, "can_buy": can["ok"], "reason": reason, "note": note,
				"reward": reward, "reward_label": REWARD_LABELS.get(reward, ""), "reward_pos": m.region_reward_pos[r],
				"revealed": revealed, "reward_detail": reward_detail(reward) if revealed else "",
				"surveying": not flight.is_empty(),
				"survey_days_left": maxf(float(flight["done"]) - float(s.clock.total_hours), 0.0) / GameClock.HOURS_PER_DAY if not flight.is_empty() else 0.0,
				"can_survey": sreason == "", "survey_reason": sreason})
	return out


## What a revealed reward is exactly, from the data ("" for no reward).
func reward_detail(reward: String) -> String:
	var rd := s.registry.regions
	match reward:
		MapState.REWARD_RICH_VEIN:
			return "Vein yield x%s" % str(snappedf(rd.rich_vein_factor, 0.01)) if rd != null else ""
		MapState.REWARD_RUINS:
			var parts: Array[String] = []
			if rd != null and rd.ruins_gold > 0:
				parts.append("%d gold" % rd.ruins_gold)
			if rd != null:
				for g in rd.ruins_goods:
					parts.append("%d %s" % [int(rd.ruins_goods[g]), str(g).replace("_", " ")])
			return ", ".join(parts)
		MapState.REWARD_FERTILE_VALLEY:
			return "Large fertile soil patch"
		MapState.REWARD_OLD_FOREST:
			var fd := s.registry.forest
			return "Forest regrows x%s faster" % str(snappedf(1.0 / fd.old_forest_regrow_factor, 0.1)) if fd != null and fd.old_forest_regrow_factor > 0.0 else ""
		MapState.REWARD_SPRING:
			return "Water source, 2x2"
	return ""


## Player text for AirshipSystem.survey_refusal ("" for none).
static func survey_reason_text(reason: String) -> String:
	match reason:
		"no_dock": return "Needs a staffed dock"
		"busy": return "All airships are out"
		"surveying": return "Already being surveyed"
		"revealed": return "Already surveyed"
		"no_reward": return "Nothing to find here"
		"owned": return "Your own land"
		"unknown": return "No such region"
	return ""


## The one-line survey state of a region_rows() entry: "Surveying, N days" while a flight is out (N rounds up), the
## revealed reward detail once surveyed, else "".
static func survey_status_text(row: Dictionary) -> String:
	if row["surveying"]:
		var d := maxi(ceili(float(row["survey_days_left"])), 1)
		return "Surveying, %d day%s" % [d, "" if d == 1 else "s"]
	if row["revealed"] and not row["owned"]:
		return row["reward_detail"]
	return ""


## Command: send a staffed dock on a survey flight over locked region r (ticket 38). False when none can.
func survey_region(r: int) -> bool:
	return s.survey_region(r)


## Command: buy region r through the Settlement.
func buy_region(r: int) -> bool:
	return s.buy_region(r)
