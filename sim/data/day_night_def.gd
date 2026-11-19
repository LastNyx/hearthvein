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
