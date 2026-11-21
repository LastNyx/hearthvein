class_name Moon
extends RefCounted
## Moon phases (ticket 145, spec N9). A cycle of DayNightDef.moon_cycle_days days, one phase a day: day 1 is the new
## moon and day 5 the full moon (data/daynight/day_night.tres). Pure helpers, all numbers from DayNightDef.
## `total_days` is the 0-based day count (GameClock.total_days()); Settlement.moon_days() gives tonight's.

const PHASE_NAMES: Array[String] = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon",
		"Waning gibbous", "Last quarter", "Waning crescent"]


## Day within the cycle, 1..moon_cycle_days.
static func cycle_day(total_days: int, d: DayNightDef) -> int:
	return posmod(total_days, maxi(d.moon_cycle_days, 1)) + 1


## Phase index 0..cycle-1 counted from the new moon (0 = new, cycle/2 = full for an even cycle).
static func phase(total_days: int, d: DayNightDef) -> int:
	return posmod(cycle_day(total_days, d) - d.moon_new_day, maxi(d.moon_cycle_days, 1))


static func is_full(total_days: int, d: DayNightDef) -> bool:
	return cycle_day(total_days, d) == d.moon_full_day


static func is_new(total_days: int, d: DayNightDef) -> bool:
	return cycle_day(total_days, d) == d.moon_new_day


## Display name of the phase.
static func phase_name(total_days: int, d: DayNightDef) -> String:
	var n := maxi(d.moon_cycle_days, 1)
	return PHASE_NAMES[(phase(total_days, d) * PHASE_NAMES.size() / n) % PHASE_NAMES.size()]


## Fraction of the disc that is lit, 0 (new) to 1 (full).
static func lit_fraction(total_days: int, d: DayNightDef) -> float:
	var n := float(maxi(d.moon_cycle_days, 1))
	return (1.0 - cos(TAU * float(phase(total_days, d)) / n)) / 2.0


## True while the lit side grows (new to full).
static func is_waxing(total_days: int, d: DayNightDef) -> bool:
	return phase(total_days, d) * 2 < maxi(d.moon_cycle_days, 1)


## Lamp radius bonus tonight (tiles): moon_full_lamp_bonus on the full moon, else 0.
static func lamp_bonus(total_days: int, d: DayNightDef) -> int:
	return d.moon_full_lamp_bonus if is_full(total_days, d) else 0


## Spirit target bonus tonight.
static func spirit_bonus(total_days: int, d: DayNightDef) -> float:
	return d.moon_full_spirit if is_full(total_days, d) else 0.0


## ProductionSystem modifier: the Glowcap Grove makes more on a new-moon night (ticket 145).
static func output_modifier(s: Settlement, b: Building) -> float:
	if not b.def.new_moon_boost or s.registry.day_night == null:
		return 1.0
	return glowcap_factor(s.moon_days(), s.registry.day_night)


## Glowcap Grove output multiplier tonight.
static func glowcap_factor(total_days: int, d: DayNightDef) -> float:
	return d.moon_new_glowcap if is_new(total_days, d) else 1.0
