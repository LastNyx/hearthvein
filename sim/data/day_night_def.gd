class_name DayNightDef
extends Resource
## The numbers of the day and night tint (design.md section 14 / D4, ticket 107). One resource:
## data/daynight/day_night.tres. Hours are the hour of day (0-24); the tint itself is render-side (render/day_night.gd).

## The darkest tint, used flat from night_start to dawn_start.
@export var night_color: Color = Color(0.50, 0.55, 0.78)
## Dusk starts: white before this hour, blending to night_color until night_start.
@export var dusk_start: int = 19
## Full night starts here.
@export var night_start: int = 21
## Dawn starts: night_color until this hour, blending back to white until day_start.
@export var dawn_start: int = 5
## Full day starts here (white).
@export var day_start: int = 7

## The long nights of a Dimming (ticket 148, spec N8): while a Dimming is on, the night runs from
## dimming_night_start to dimming_night_end (16 to 9) for the night shift, the lamps, the tint and the walker
## schedule, and the day shift shrinks to the hours between them (9 to 16). Normal nights keep the hours above and
## the LogisticsDef shift/lamp hours.
@export var dimming_night_start: int = 16
@export var dimming_night_end: int = 9

## Moon phases (ticket 145, spec N9): an 8-day cycle, one phase a day. Day moon_new_day is the new moon, day
## moon_full_day the full moon. Full moon: lamps light moon_full_lamp_bonus more tiles and Spirit gains moon_full_spirit
## that night. New moon: Glowcap Grove output x moon_new_glowcap. Other phases are neutral.
@export var moon_cycle_days: int = 8
@export var moon_new_day: int = 1
@export var moon_full_day: int = 5
@export var moon_full_lamp_bonus: int = 1
@export var moon_full_spirit: float = 2.0
@export var moon_new_glowcap: float = 1.25
