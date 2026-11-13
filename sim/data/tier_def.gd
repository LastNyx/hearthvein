class_name TierDef
extends Resource
## One upgrade tier above base (design.md section 10). A building's `tiers` array holds II then III.
## Cost amounts are whole numbers; fractions of the default rule are rounded up.

@export var display_name: String = ""
## Output (or beds) multiplier relative to the base building. 0 = use the default rule (TierRuleDef).
@export var multiplier: float = 0.0
## Extra worker slots compared with the base building. -1 = use the default rule (TierRuleDef).
@export var extra_worker_slots: int = -1
## True for the Terraced Farm (design.md section 9): this tier stops the seasonal fertility loss.
@export var stops_fertility_loss: bool = false
## good id -> int. Empty = use the default costs (TierRuleDef): fractions of the base materials cost.
@export var cost: Dictionary = {}
