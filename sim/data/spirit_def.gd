class_name SpiritDef
extends Resource
## The numbers of the Spirit meter (design.md section 11, D18). One resource: data/spirit/spirit.tres.

@export var start: float = 60.0
@export var base: float = 50.0
## Points moved per day towards the target.
@export var step_per_day: float = 2.0
@export var food_type_bonus: float = 5.0
@export var food_type_max: float = 20.0
@export var coverage_bonus: float = 10.0
@export var hunger_penalty: float = 15.0
@export var homeless_penalty: float = 10.0
@export var blight_max: float = 15.0
@export var water_max: float = 10.0
@export var darkness_penalty: float = 20.0
@export var tax_office_penalty: float = 5.0
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
