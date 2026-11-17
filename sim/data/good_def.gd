class_name GoodDef
extends Resource
## A physical good (or gold, the global counter). Data lives in data/goods/.

const KIND_BASE := "base"
const KIND_REFINED := "refined"

@export var id: String = ""
@export var display_name: String = ""
## "base" or "refined" (design.md section 7).
@export var kind: String = KIND_BASE
## Food variety type this good counts as, or "" when it is not a food type.
@export var food_type: String = ""
