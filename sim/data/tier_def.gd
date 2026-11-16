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
## True for Greenhouse III (design.md section 10): production ignores blight (BuildingDef.blight_halt_reach).
@export var ignores_blight: bool = false
## True for the Irrigated Farm (design.md section 10): this tier only works on wet ground, and its wet multiplier is
## wet_bonus instead of the plain farm wet bonus. A dry footprint halts production with "dry".
@export var needs_wet: bool = false
## Farm output multiplier when needs_wet is set and at least half the footprint is wet (Irrigated Farm: 1.5, which
## replaces the plain wet x1.25 of design.md section 9 -- the two do not stack). 1.0 = no extra bonus.
@export var wet_bonus: float = 1.0
## art_manifest building id drawn for this tier (e.g. "cottage_shingle"). "" or an id without art = the base sprite.
@export var art_id: String = ""
## good id -> int. Empty = use the default costs (TierRuleDef): fractions of the base materials cost.
@export var cost: Dictionary = {}
