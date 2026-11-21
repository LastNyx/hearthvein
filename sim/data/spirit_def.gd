class_name SpiritDef
extends Resource
## The numbers of the Spirit meter (design.md section 11, D18). One resource: data/spirit/spirit.tres.

@export var start: float = 60.0
@export var base: float = 50.0
## Points moved per day towards the target.
@export var step_per_day: float = 2.0
@export var food_type_bonus: float = 5.0
@export var food_type_max: float = 20.0
## +coverage_bonus when more than coverage_min_share of the housed citizens live in a covered home (CoverageSystem).
## "Most" is strict: exactly this share is not enough. design.md section 11: "+10 if most homes are inside coverage".
@export var coverage_bonus: float = 10.0
@export var coverage_min_share: float = 0.5
@export var hunger_penalty: float = 15.0
@export var homeless_penalty: float = 10.0
@export var blight_max: float = 15.0
@export var water_max: float = 10.0
@export var darkness_penalty: float = 20.0
@export var tax_office_penalty: float = 5.0
## Lit houses at night (ticket 133): +light_bonus times the share of finished homes inside a lamp's light, capped at
## light_bonus_max. 0 = no bonus.
@export var light_bonus: float = 1.0
@export var light_bonus_max: float = 3.0
## Tavern (ticket 139): +tavern_bonus times the share of finished homes within a staffed, lit Tavern's coverage
## radius, at night only. 0 = no bonus.
@export var tavern_bonus: float = 5.0
@export var grief_max: float = 10.0
## Planet grief = (grief_below - health) / grief_divisor when health (0-100) is below grief_below.
@export var grief_below: float = 60.0
@export var grief_divisor: float = 6.0
## Effects. High: work and growth bonus, immigration on (GrowthDef.immigration_spirit). Low: work malus.
@export var high_at: float = 70.0
@export var low_at: float = 30.0
@export var work_high: float = 0.15
@export var work_low: float = -0.20
@export var growth_high: float = 0.20
## Below leave_below for leave_after_days days in a row: one citizen leaves every leave_every_days days.
@export var leave_below: float = 20.0
@export var leave_after_days: int = 5
@export var leave_every_days: int = 2
