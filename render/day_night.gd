class_name DayNight
extends RefCounted
## The map tint by time of day (ticket 107, D4). Static helpers only: the numbers come from DayNightDef, the clock
## from the sim. The HUD is a CanvasLayer, so the tint never touches it.

## The colour the map goes under during a Dimming (ticket 15); the night tint multiplies it.
const DIMMING_COLOR := Color(0.45, 0.48, 0.65)

## Tint for an hour of day with a fraction (0.0-24.0): white 07-19, blending to night_color 19-21, night_color
## 21-05, blending back to white 05-07. In a Dimming (ticket 148) the dark is the long night 16-09: night_color from
## 16 to 09, white from 09 to 16.
static func tint_for(hours_f: float, def: DayNightDef, dimming: bool = false) -> Color:
	if def == null:
		return Color.WHITE
	var h := fposmod(hours_f, 24.0)
	if dimming:
		var in_dark := h >= float(def.dimming_night_start) or h < float(def.dimming_night_end)
		return def.night_color if in_dark else Color.WHITE
	var day := float(def.day_start)
	var dusk := float(def.dusk_start)
	var night := float(def.night_start)
	var dawn := float(def.dawn_start)
	if h >= day and h < dusk:
		return Color.WHITE
	if h >= dusk and h < night:
		return Color.WHITE.lerp(def.night_color, (h - dusk) / maxf(night - dusk, 0.0001))
	if h >= night or h < dawn:
		return def.night_color
	return def.night_color.lerp(Color.WHITE, (h - dawn) / maxf(day - dawn, 0.0001))


## The map tint: the night tint (or white when the player turned day and night off) times the Dimming colour.
static func map_tint(hours_f: float, def: DayNightDef, dimming: bool, day_night: bool = true) -> Color:
	var tint := tint_for(hours_f, def, dimming) if day_night else Color.WHITE
	return tint * (DIMMING_COLOR if dimming else Color.WHITE)
