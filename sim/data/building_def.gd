class_name BuildingDef
extends Resource
## A building type. Data lives in data/buildings/ (design.md sections 16-17).

const CATEGORIES: Array[String] = [
	"housing", "food", "materials", "lumen", "refining", "gold",
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
## True for the Forester: plants plain grass in placement_radius, and halves stump regrowth there (ForestSystem).
@export var plants_forest: bool = false
## Lumen extractors (design.md section 12): each period (days) the nearest non-blighted tile within radius turns
## blighted. 0 = no blight (Aether Collector, Heartroot Tap, every non-extractor). Tiers do not change these.
@export var blight_radius: int = 0
@export var blight_period_days: int = 0
## True for extractors that sit on a vein: their output scales with the vein yield factor (section 13).
@export var vein_extractor: bool = false
## Output factor during a Dimming (section 14): 0.5 for Forager and plain farms, 1.0 for everything unaffected.
## Vein extractors use PlanetDef.dimming_vein_factor instead.
@export var dimming_factor: float = 1.0
## Planet health per day while the building works (section 13): negative for extractors, positive for cleaners.
@export var health_per_day: float = 0.0
## True for a Farm (design.md section 9): output is multiplied by the mean fertility of the footprint / 100.
@export var fertility_output: bool = false
## Multiplier applied when the tile under the origin started as fertile soil (Farm: 1.5). 1.0 = no bonus.
@export var fertile_origin_bonus: float = 1.0
## Gold per assigned worker per day, paid into Settlement.gold (Market: 1). 0 = the building earns no gold.
## Gold is a global counter, never a recipe output or an inventory good.
@export var gold_per_worker_day: float = 0.0
## Tiles a home must be within (Chebyshev, footprint to footprint) for the Market's food variety to serve it.
## 0 = no reach (only Market uses it). design.md gives no number; ticket 23 chose 12.
@export var market_reach: int = 0
## Null for buildings that produce nothing.
@export var recipe: RecipeDef = null
@export var upgradable: bool = false
## Tier II then tier III. Empty unless upgradable.
@export var tiers: Array[TierDef] = []
