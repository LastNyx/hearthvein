class_name RecipeDef
extends Resource
## Production is always "inputs -> outputs per worker per day" (design.md section 21).
## Both dictionaries map good id -> amount (float) for ONE worker working ONE day at base tier.
## Recipes with no inputs (Forager, Tap) are plain extraction.

@export var inputs: Dictionary = {}
@export var outputs: Dictionary = {}
## Flexible inputs (Kitchen, design.md section 7): take `any_input_amount` units of each of `any_input_count`
## DIFFERENT goods from `any_input_goods`. The goods are picked per batch as the ones with the most in the input
## buffer (ties: list order), so the Kitchen makes meals from whichever two food types the haulers brought.
## The fixed `inputs` above are consumed as usual. `any_input_count` 0 = no flexible input.
@export var any_input_goods: Array[String] = []
@export var any_input_count: int = 0
@export var any_input_amount: float = 0.0
