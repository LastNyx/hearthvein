class_name SpiritSystem
extends SimSystem
## Spirit (design.md section 11, D18): one meter 0-100 that moves `step_per_day` towards a target each day.
## Numbers: SpiritDef (data/spirit/spirit.tres). Read it only through Settlement.spirit().
##
## Target = base + the sum of the factor table below (clamped 0-100). Every factor is an entry {id, fn} where
## fn(settlement) -> signed float; entries not built yet return 0 and a later ticket fills them with set_hook(id, fn):
## coverage (shrine/park/hall), water, blight (ticket 14), darkness (15), planet_grief. Order of the table is the
## order of breakdown().
##
## Effects: work_multiplier() feeds ProductionSystem.modifiers (registered in Settlement.add_default_systems) and
## ConstructionSystem (builders work faster/slower too); growth_multiplier() scales the growth-bar surplus
## (GrowthSystem); immigration is gated in GrowthSystem. Below leave_below for leave_after_days days in a row,
## one citizen leaves every leave_every_days days (homeless first, then highest id, like starvation).
##
## Runs after GrowthSystem each day: hunger comes from GrowthSystem.last_day. Food variety is market-gated (ticket
## 23): MarketSystem says how many food types the citizens' homes can reach, and only that many count.
##
## Night drinks (ticket 139): at the night shift's start, every finished, lit Tavern with a night worker drinks its
## BuildingDef.night_inputs. Those that drank cheer the homes inside their spirit_radius that night ("tavern" factor).

const SAVE_KEY := "spirit"

var value: float = -1.0
## Days in a row spent below SpiritDef.leave_below.
var low_days: int = 0
var _days_since_leave: int = 0
var _hooks: Dictionary = {}  # factor id -> Callable
var _order: Array[String] = ["food_types", "coverage", "hunger", "homeless", "blight", "water", "darkness",
		"tax_office", "planet_grief", "light", "tavern"]
## Tavern building ids that drank their night_inputs at this night's start, low to high (ticket 139). Runtime state,
## saved so a load in the middle of a night keeps the Taverns' cheer.
var _serving: Array[int] = []


func _init() -> void:
	for id in _order:
		_hooks[id] = Callable()


## The two meters and their bookkeeping. The factor hooks are Callables wired in add_default_systems (by ticket),
## not data, so they are not saved; the loaded system is built by add_default_systems and has the same ones.
func save_state() -> Dictionary:
	return {"value": value, "low_days": low_days, "days_since_leave": _days_since_leave,
			"serving": _serving.duplicate()}


func load_state(d: Dictionary, _settlement: Settlement) -> void:
	value = float(d["value"])
	low_days = int(d["low_days"])
	_days_since_leave = int(d["days_since_leave"])
	_serving.clear()
	for id in d.get("serving", []):
		_serving.append(int(id))


## Replace a factor's function (settlement) -> float (signed: negative lowers Spirit). Returns false for unknown ids.
func set_hook(id: String, fn: Callable) -> bool:
	if not _hooks.has(id):
		return false
	_hooks[id] = fn
	return true


func current(s: Settlement) -> float:
	if value < 0.0:
		value = s.registry.spirit.start
	return value


## Value of one factor now.
func factor_value(s: Settlement, id: String) -> float:
	var sd := s.registry.spirit
	var gs := s.get_system(GrowthSystem) as GrowthSystem
	match id:
		"food_types":
			var ms := s.get_system(MarketSystem) as MarketSystem
			var n := ms.available_food_types(s) if ms != null else 0
			return food_type_factor(sd, n)
		"hunger":
			var h: int = gs.last_day.get("hungry", 0) if gs != null else 0
			return -sd.hunger_penalty if h > 0 else 0.0
		"homeless":
			return -sd.homeless_penalty if s.homeless_count() > 0 else 0.0
		"tax_office":
			for bid in s.buildings:
				var b: Building = s.buildings[bid]
				if not b.site and b.def.id == "tax_office":
					return -sd.tax_office_penalty
			return 0.0
		"light":
			# Lit houses at night (ticket 133): the share of finished homes inside a lit lamp's radius.
			if not s.is_night():
				return 0.0
			var homes := 0
			var lit := 0
			for bid in s.buildings:
				var hb: Building = s.buildings[bid]
				if hb.site or hb.def.housing_beds <= 0:
					continue
				homes += 1
				if s.is_lit(hb):
					lit += 1
			if homes == 0:
				return 0.0
			return minf(sd.light_bonus * float(lit) / float(homes), sd.light_bonus_max)
		"tavern":
			# Taverns at night (ticket 139): the share of finished homes inside the spirit_radius of a Tavern that
			# drank its night_inputs and is staffed and lit (the same footprint measure as Shrine coverage).
			if not s.is_night() or _serving.is_empty():
				return 0.0
			var homes := 0
			var served := 0
			for bid in s.buildings:
				var hb: Building = s.buildings[bid]
				if hb.site or hb.def.housing_beds <= 0:
					continue
				homes += 1
				for tid in _serving:
					var tb: Building = s.buildings.get(tid)
					if tb != null and cheers(tb, hb):
						served += 1
						break
			if homes == 0:
				return 0.0
			return minf(sd.tavern_bonus * float(served) / float(homes), sd.tavern_bonus)
	var fn: Callable = _hooks.get(id, Callable())
	return float(fn.call(s)) if fn.is_valid() else 0.0


## +food_type_bonus per type beyond the first, capped at food_type_max. `n` is the number of food types the citizens'
## homes can reach (MarketSystem.available_food_types).
static func food_type_factor(sd: SpiritDef, n: int) -> float:
	return minf(float(maxi(n - 1, 0)) * sd.food_type_bonus, sd.food_type_max)


## The sum of base and every factor, 0-100.
func target(s: Settlement) -> float:
	var t := s.registry.spirit.base
	for id in _order:
		t += factor_value(s, id)
	return clampf(t, 0.0, 100.0)


## For the UI: {"factors": {name: value} in stable order (starts with "base"), "target": float, "current": float}.
func breakdown(s: Settlement) -> Dictionary:
	var f := {"base": s.registry.spirit.base}
	for id in _order:
		f[id] = factor_value(s, id)
	return {"factors": f, "target": target(s), "current": current(s)}


static func work_multiplier(s: Settlement) -> float:
	var sd := s.registry.spirit
	var v := s.spirit()
	if v >= sd.high_at:
		return 1.0 + sd.work_high
	if v <= sd.low_at:
		return 1.0 + sd.work_low
	return 1.0


static func growth_multiplier(s: Settlement) -> float:
	var sd := s.registry.spirit
	return 1.0 + sd.growth_high if s.spirit() >= sd.high_at else 1.0


## ProductionSystem modifier.
static func work_modifier(s: Settlement, _b: Building) -> float:
	return work_multiplier(s)


## At the night shift's start every finished, lit Tavern with a night worker drinks its night_inputs, and those that
## cannot pay stay dry that night (ticket 139). The serving list clears at dawn.
func on_hour(s: Settlement) -> void:
	var lg := s.registry.logistics
	if lg == null:
		return
	var h := s.clock.hour()
	if h == lg.night_shift_start:
		_drink(s)
	elif h == lg.night_shift_end:
		_serving.clear()


func _drink(s: Settlement) -> void:
	_serving.clear()
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or b.def.night_inputs.is_empty():
			continue
		if not s.is_lit(b) or night_workers(s, b) <= 0:
			continue
		var paid := true
		for g in b.def.night_inputs:
			if b.input_buffer == null \
					or b.input_buffer.amount_of(g) < float(b.def.night_inputs[g]) - Inventory.EPS:
				paid = false
				break
		if not paid:
			continue
		for g in b.def.night_inputs:
			var got := b.input_buffer.remove(g, float(b.def.night_inputs[g]))
			ResourceLedgerSystem.record_used(s, g, got, "production", b.def.id)
		_serving.append(b.id)


## True when `source` cheers homes within its spirit_radius (the Tavern's night cheer, measured like coverage).
static func cheers(source: Building, home: Building) -> bool:
	return source.def.spirit_radius > 0 and source.layer == home.layer \
			and Building.footprint_gap(source, home) <= source.def.spirit_radius


## Citizens on this building's night work shift.
static func night_workers(s: Settlement, b: Building) -> int:
	var n := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.job_id == b.id and c.job_kind == Citizen.JOB_WORK and c.shift == Citizen.SHIFT_NIGHT:
			n += 1
	return n


func on_day(s: Settlement) -> void:
	var sd := s.registry.spirit
	var cur := current(s)
	var t := target(s)
	value = clampf(move_toward(cur, t, sd.step_per_day), 0.0, 100.0)
	if value < sd.leave_below:
		low_days += 1
	else:
		low_days = 0
		_days_since_leave = 0
	if low_days >= sd.leave_after_days:
		_days_since_leave += 1
		# The 5th day leaves at once; after that one every leave_every_days days.
		if low_days == sd.leave_after_days or _days_since_leave >= sd.leave_every_days:
			_days_since_leave = 0
			var who := GrowthSystem.leaver(s)
			if who >= 0 and s.remove_citizen(who):
				s.events.emit("citizen_left_unhappy", {"id": who})
