class_name GoodDef
extends Resource
## A physical good (or gold, the global counter). Data lives in data/goods/.

const KIND_BASE := "base"
const KIND_REFINED := "refined"
## A luxury good (silk, ticket 144): made for its gold, not for a recipe. Markets sell it.
const KIND_LUXURY := "luxury"

@export var id: String = ""
@export var display_name: String = ""
## "base", "refined" or "luxury" (design.md section 7).
@export var kind: String = KIND_BASE
## Food variety type this good counts as, or "" when it is not a food type.
@export var food_type: String = ""
## Eating order among foods (ticket 140): a higher value is eaten first. Plain food itself and every other food
## default to 0, where plain food goes before the other foods; bread is 1, so it is eaten before plain food.
@export var food_priority: int = 0
## Gold a Market pays for one unit of this good when it sells the stock above `sale_keep` (MarketSystem, ticket 144).
## 0 = no market sells it.
@export var sale_price: float = 0.0
## Units of this good that stay in storage; only the stock above this is sold. 0 = sell it all.
@export var sale_keep: float = 0.0
