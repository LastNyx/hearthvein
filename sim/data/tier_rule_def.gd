class_name TierRuleDef
extends Resource
## The default upgrade tier rule (design.md section 10). A building's TierDef overrides any field for itself.
## Index 0 is tier II and index 1 is tier III in every array here.
## All numbers come from data/tiers/tiers.tres; this class only turns them into answers.

## Era each tier unlocks in ("" = no gate).
@export var eras: Array[String] = []
## Output (or beds) multiplier relative to the base building.
@export var output_factors: Array[float] = []
## Extra worker slots over the base building.
@export var extra_worker_slots: Array[int] = []
## good id -> fraction of the building's base wood + stone cost.
@export var cost_fractions: Array[Dictionary] = []


## TierDef of `def` for `tier` (2 or 3), or null.
static func tier_def_of(def: BuildingDef, tier: int) -> TierDef:
	var i := tier - 2
	if def == null or i < 0 or i >= def.tiers.size():
		return null
	return def.tiers[i]


func era_for(tier: int) -> String:
	var i := tier - 2
	return eras[i] if i >= 0 and i < eras.size() else ""


## TierDef's multiplier when it carries one, else the default for that tier.
func output_factor(def: BuildingDef, tier: int) -> float:
	var td := tier_def_of(def, tier)
	if td != null and td.multiplier > 0.0:
		return td.multiplier
	var i := tier - 2
	return output_factors[i] if i >= 0 and i < output_factors.size() else 1.0


## TierDef's extra slots when it carries them, else the default for that tier.
func extra_slots(def: BuildingDef, tier: int) -> int:
	var td := tier_def_of(def, tier)
	if td != null and td.extra_worker_slots >= 0:
		return td.extra_worker_slots
	var i := tier - 2
	return extra_worker_slots[i] if i >= 0 and i < extra_worker_slots.size() else 0


## Whole-good cost of `tier`: the TierDef's cost when it has one (per-def override wins), else each fraction of
## the default rule times the base wood + stone cost, rounded up.
func cost_of(def: BuildingDef, tier: int) -> Dictionary:
	var td := tier_def_of(def, tier)
	if td != null and not td.cost.is_empty():
		return td.cost.duplicate()
	var i := tier - 2
	if def == null or i < 0 or i >= cost_fractions.size():
		return {}
	var base := float(def.cost.get("wood", 0)) + float(def.cost.get("stone", 0))
	var out := {}
	for g in cost_fractions[i]:
		var amount := int(ceil(base * float(cost_fractions[i][g]) - 0.000001))
		if amount > 0:
			out[g] = amount
	return out
