class_name BuildingDef
extends Resource
## A building type. Data lives in data/buildings/ (design.md sections 16-17).

const CATEGORIES: Array[String] = [
	"housing", "food", "materials", "lumen", "refining",
	"water", "logistics", "civic", "sky", "landmark",
]
## Known placement rule ids. The real checks come with the placement ticket.
##  any: any buildable tile. on_vein / on_rock: on that terrain. shore: next to water.
##  wet: tile is wet. near_forage / near_forest: needs grass-or-forest / forest within placement_radius.
const PLACEMENT_RULES: Array[String] = [
	"any", "on_vein", "shore", "on_rock", "wet", "near_forage", "near_forest",
]
## Storage modes: none, per_good (cap applies to each good), total (cap shared by any mix).
const STORAGE_MODES: Array[String] = ["none", "per_good", "total"]
## Goods used by cost dictionaries as the global gold counter.
const GOLD := "gold"

@export var id: String = ""
@export var display_name: String = ""
@export var era: String = ""
@export var category: String = "civic"
@export var size: Vector2i = Vector2i(1, 1)
## good id -> int. Gold uses good id "gold". Empty = free.
@export var cost: Dictionary = {}
@export var worker_slots: int = 0
@export var hauler_slots: int = 0
@export var builder_slots: int = 0
## Lumen per day.
@export var upkeep_lumen: float = 0.0
@export var housing_beds: int = 0
@export var storage_mode: String = "none"
@export var storage_cap: int = 0
@export var placement_rule: String = "any"
## Radius in tiles used by rules that look around the tile (0 when unused).
@export var placement_radius: int = 0
## True for the Woodcutter: production turns forest tiles in placement_radius into stumps.
@export var fells_forest: bool = false
## Null for buildings that produce nothing.
@export var recipe: RecipeDef = null
@export var upgradable: bool = false
## Tier II then tier III. Empty unless upgradable.
@export var tiers: Array[TierDef] = []
