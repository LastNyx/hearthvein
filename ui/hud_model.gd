class_name HudModel
extends RefCounted
## Everything the HUD shows, as plain data and strings (no scene tree), so it is unit-tested headless. The Control
## scenes (ui/hud.gd) only copy these values onto labels. Reads the Settlement; its only commands are the building
## priority and pause the selected-building panel offers.

const OVERLAYS: Array[String] = ["blight", "roads", "water", "coverage", "grid"]
const CATEGORY_ORDER: Array[String] = ["roads", "housing", "food", "materials", "lumen", "refining", "gold",
		"water", "logistics", "civic", "sky", "landmark"]
const RESOURCES: Array[String] = ["food", "materials", "lumen", "gold"]
const REWARD_LABELS := {"rich_vein": "Rich vein", "ruins": "Ruins", "fertile_valley": "Fertile valley",
		"old_forest": "Old forest", "spring": "Spring"}
const COST_ORDER: Array[String] = ["materials", "planks", "cut_stone", "tools", "lumen_cells"]
const PRIORITY_LABELS := {"low": "Low", "normal": "Normal", "high": "High"}

var s: Settlement
var notifications: NotificationCenter
var selected_id: int = -1
var overlays := {"blight": false, "roads": false, "water": false, "coverage": false, "grid": false}
## Active layer (ticket 40d): Building.LAYER_GROUND or LAYER_SKY. The one place the UI (placement, build bar, HUD tag)
## and the render (MapView.set_active_layer, via layer_changed) read. Tab toggles it; sky only while an island exists.
var active_layer: int = Building.LAYER_GROUND
signal layer_changed(layer: int)
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
	var lumen := float(t.get("lumen", 0.0))
	var gs := s.get_system(GridSystem) as GridSystem
	if gs != null:
		lumen += gs.total_charge()  # battery charge is Lumen the player owns, even though it is not in storage
	return {"food": food, "materials": float(t.get("materials", 0.0)), "lumen": lumen, "gold": s.gold}


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
			var label := "Great Dimming" if st.get("great", false) else "Dimming"
			return "%s %s - lasts %d" % [label, "today" if n <= 0 else ("tomorrow" if n == 1 else "in %d days" % n), st["length"]]
		"active":
			var total: int = st["length"]
			if st.get("great", false):
				return "GREAT DIMMING - day %d of %d%s" % [total - int(st["days_left"]) + 1, total, " (dark)" if st["dark"] else ""]
			return "DIMMING - day %d of %d%s" % [total - int(st["days_left"]) + 1, total, " (dark)" if st["dark"] else ""]
	return "No Dimming expected"


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


## Tab: ground <-> sky. With no island it stays on the ground and raises a short toast. Returns the layer now active.
func toggle_layer() -> int:
	if active_layer == Building.LAYER_SKY:
		set_layer(Building.LAYER_GROUND)
	elif has_islands():
		set_layer(Building.LAYER_SKY)
	else:
		notifications.clear("no_islands")
		notifications.raise("no_islands", "info", "No islands yet")
	return active_layer


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


## "Halted: waiting for input" for a halted building, "" when it works.
func halt_text(b: Building) -> String:
	match b.halt:
		"door_full": return "Halted: output buffer full"
		"no_input": return "Halted: waiting for input"
		"no_forest": return "Halted: no forest in range"
		"island_still": return "Halted: the island is still"
		"planet_too_sick": return "Halted: planet health below %d%%" % int(b.def.min_planet_health)
		"dry": return "Halted: no water in reach"
		"too_far": return "Halted: too far from a builders' yard"
	return ""


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


## Panel data of the selected building or {} : title, lines (strings), halt text, priority, paused, site progress.
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
		if b.effective_worker_slots(s.registry) > 0:
			lines.append("Workers %d/%d" % [_workers(b), b.effective_worker_slots(s.registry)])
		if b.effective_beds(s.registry) > 0:
			lines.append("Beds %d" % b.effective_beds(s.registry))
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
	var halt_text := halt_text(b)
	var bl := _blight_near(b)
	if bl > 0:
		lines.append("Blight: %d tiles" % bl)
	var clean: Array[String] = []
	for l in lines:
		if l != "":
			clean.append(l)
	var out := {"id": b.id, "title": b.display_name(s.registry), "lines": clean, "halt": halt_text, "warn": warn,
			"priority": b.priority, "paused": b.paused, "site": b.site, "progress": b.build_progress()}
	out.merge(upgrade_info(b))
	return out


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
func upgrade_reason_text(reason: String, next_tier: int = 0) -> String:
	if reason == "era_locked":
		var rule := s.registry.tiers
		var e := s.registry.get_era(rule.era_for(next_tier)) if rule != null else null
		return "Needs %s era" % e.display_name if e != null else "Needs a later era"
	return UPGRADE_REASONS.get(reason, reason.capitalize().replace("_", " "))


## "3 Planks, 2 Cut Stone": real good names, materials first then by id.
func goods_cost_text(cost: Dictionary) -> String:
	var ids: Array = cost.keys()
	ids.sort_custom(func(a: String, c: String) -> bool:
		var ra := COST_ORDER.find(a) if COST_ORDER.has(a) else COST_ORDER.size()
		var rc := COST_ORDER.find(c) if COST_ORDER.has(c) else COST_ORDER.size()
		return ra < rc if ra != rc else a < c)
	var parts: Array[String] = []
	for g in ids:
		var gd := s.registry.get_good(g)
		parts.append("%d %s" % [int(cost[g]), gd.display_name if gd != null else str(g)])
	return ", ".join(parts)


## Upgrade part of the panel: tier, next_tier (0 = none), next_name, next_cost (text, materials first), can_upgrade,
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
	info["upgrade_reason"] = upgrade_reason_text(can["reason"], nxt)
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


## "6 Materials, 2 Lumen" from a recipe side (good id -> float, per worker per day).
func _amounts_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	for g in d:
		parts.append("%s %s" % [num_text(float(d[g])), _good_name(g)])
	return ", ".join(parts)


## The data lines of a def (cost, jobs, recipe, upkeep, reach, beds, storage). `b` (or null) scales slots and beds by tier.
func _def_tooltip_lines(def: BuildingDef, b: Building) -> Array[String]:
	var lines: Array[String] = []
	if b == null or b.site:
		var cost := goods_cost_text(def.entry_cost())
		lines.append("Cost: %s" % (cost if cost != "" else "free"))
	var workers := b.effective_worker_slots(s.registry) if b != null else def.worker_slots
	var jobs: Array[String] = []
	if workers > 0 and b == null:
		jobs.append("Workers %d" % workers)
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
		if b.effective_worker_slots(s.registry) > 0:
			status.append("Workers %d/%d" % [_workers(b), b.effective_worker_slots(s.registry)])
		var halt := halt_text(b)
		if halt != "":
			status.append(halt)
		if not b.connected:
			status.append("Not connected to the Hearth by road")
	return _tooltip(b.display_name(s.registry), b.def, status, _def_tooltip_lines(b.def, b))


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
				"cost": goods_cost_text(def.entry_cost()), "size": "%dx%d" % [def.size.x, def.size.y],
				"reason": layer_block_reason(def), "enabled": layer_block_reason(def) == ""})
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


## What an Irrigation Channel does, from WaterDef ("" without it).
func channel_help_text() -> String:
	return s.registry.water.channel_help() if s.registry.water != null else ""


## "1 Materials" per channel tile, from WaterDef.
func channel_cost_text() -> String:
	var c := s.registry.water.channel_cost_materials if s.registry.water != null else 0.0
	return goods_cost_text({"materials": roundi(c)}) if c > 0.0 else ""


## "2 Materials, 1 Cut stone" per track tile, from LogisticsDef.
func track_cost_text() -> String:
	var lg := s.registry.logistics
	if lg == null:
		return ""
	var c := {}
	if lg.track_cost_materials > 0.0:
		c["materials"] = lg.track_cost_materials
	if lg.track_cost_cut_stone > 0.0:
		c["cut_stone"] = lg.track_cost_cut_stone
	return goods_cost_text(c)


## "5 Materials" extra for one water tile of road at `level` (a bridge), "" when the road has no bridge cost.
func bridge_cost_text(level: int) -> String:
	var rd := s.registry.get_road_by_level(level)
	return goods_cost_text(rd.bridge_cost) if rd != null and not rd.bridge_cost.is_empty() else ""


## "6 Materials, 3 Cut stone" for one rail bridge tile (track on water).
func track_bridge_cost_text() -> String:
	var lg := s.registry.logistics
	if lg == null:
		return ""
	var c := {}
	if lg.track_cost_materials > 0.0:
		c["materials"] = lg.track_cost_materials * lg.track_bridge_multiplier
	if lg.track_cost_cut_stone > 0.0:
		c["cut_stone"] = lg.track_cost_cut_stone * lg.track_bridge_multiplier
	return goods_cost_text(c)


## Player-facing reason a track tile cannot be laid.
static func track_refusal_text(reason: String) -> String:
	return {"materials": "Not enough materials", "cut_stone": "Not enough cut stone", "locked_region": "Region not owned",
			"water": "Cannot lay track on water", "out_of_bounds": "Off the map", "blocked_terrain": "Blocked",
			"road": "A road is here", "overlap": "A building is here", "channel": "A channel is here",
			"track": "Already laid"}.get(reason, "Blocked")


## "1 Materials, 0.2 Cut Stone" for one paved tile, from the paved RoadDef (stone shown per whole tile as the data
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
	return {"materials": "Not enough materials", "cut_stone": "Not enough cut stone", "era_locked": "Needs the Town era",
			"already_paved": "Already paved", "locked_region": "Region not owned", "water": "Cannot pave water",
			"out_of_bounds": "Off the map", "blocked_terrain": "Blocked", "overlap": "A building is here",
			"channel": "A channel is here"}.get(reason, "Blocked")


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
