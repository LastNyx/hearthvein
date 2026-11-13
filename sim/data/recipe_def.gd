class_name RecipeDef
extends Resource
## Production is always "inputs -> outputs per worker per day" (design.md section 21).
## Both dictionaries map good id -> amount (float) for ONE worker working ONE day at base tier.
## Recipes with no inputs (Forager, Tap) are plain extraction.

@export var inputs: Dictionary = {}
@export var outputs: Dictionary = {}
