class_name GrowthDef
extends Resource
## The numbers of eating, growth and immigration (design.md section 5, D17, D46). One resource: data/growth/growth.tres.

## Food one citizen eats per day.
@export var food_per_citizen: float = 0.0
## Growth bar size = bar_base + population / bar_pop_divisor.
@export var bar_base: float = 0.0
@export var bar_pop_divisor: float = 0.0
## Soft cap (D46): above this population the bar is multiplied by 1 + (pop - cap) / soft_cap_span and immigration stops.
@export var soft_cap: int = 0
@export var soft_cap_span: float = 0.0
## Immigration: one newcomer every immigration_days days while Spirit >= immigration_spirit and a bed is free.
@export var immigration_spirit: float = 0.0
@export var immigration_days: int = 0
## Spirit when nothing else sets it. Ticket 13 owns the real value; Settlement.spirit() reads this until then.
@export var default_spirit: float = 0.0
## Citizens that leave per day while food is 0 with a deficit.
@export var leave_per_day: int = 0
## Night arrivals (ticket 146): each night a newcomer's worth of this share waits at the gate; at 1.0 a newcomer is
## ready, and walks in at the night shift's start when the arrival point is lit. Day immigration is unchanged.
@export var night_arrival_share: float = 0.0
