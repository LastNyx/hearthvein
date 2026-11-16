class_name BuildingDef
extends Resource
## A building type. Data lives in data/buildings/ (design.md sections 16-17).

const CATEGORIES: Array[String] = [
	"housing", "food", "materials", "lumen", "refining", "gold",
	"water", "logistics", "civic", "sky", "landmark",
]
## Categories whose buildings may upgrade in place (design.md section 10). Landmarks, civic, refiners, logistics,
## water and gold buildings never upgrade, even if their def says upgradable.
const UPGRADABLE_CATEGORIES: Array[String] = ["housing", "food", "materials", "lumen"]
## Known placement rule ids. The real checks come with the placement ticket.
##  any: any buildable tile. on_vein / on_rock: on that terrain. shore: next to water.
##  wet: any tile of the footprint is wet. on_wet: the origin tile is wet (Well, design.md section 9).
##  near_forage / near_forest: needs grass-or-forest / forest within placement_radius.
const PLACEMENT_RULES: Array[String] = [
	"any", "on_vein", "shore", "on_rock", "wet", "on_wet", "near_forage", "near_forest",
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
## Cleaners (design.md section 12: Cleanser 1 tile / 2 days in r5, Purifier Tower 1/day in r8): every
## clean_interval_days working days, the nearest blighted tile within clean_radius of the footprint is cleared.
## 0 = no cleaning.
@export var clean_radius: int = 0
@export var clean_interval_days: int = 0
## Shields (design.md section 12: the Purifier Tower blocks new blight in r4): a tile within this many tiles of the
## footprint (Euclidean, the same measure blight_radius uses) is never chosen by BlightSystem while the building
## works. 0 = blocks nothing.
@export var blight_block_radius: int = 0
## True for the Park (design.md section 12): a finished building's own footprint is never chosen by BlightSystem.
## Unlike blight_block_radius this needs no workers or upkeep; the land itself is blight-proof.
@export var blight_proof: bool = false
## True for extractors that sit on a vein: their output scales with the vein yield factor (section 13).
@export var vein_extractor: bool = false
## Output factor during a Dimming (section 14): 0.5 for Forager and plain farms, 1.0 for everything unaffected.
## Vein extractors use dimming_vein_factor instead.
@export var dimming_factor: float = 1.0
## Dimming output factor for a vein extractor (section 14, D37/D43): 0 = PlanetDef.dimming_vein_factor (0.25,
## Lumen Tap and Lumen Pump). The Lumen Reactor uses 0.6 and the Vein Bore 0.4; the def overrides the planet value.
@export var dimming_vein_factor: float = 0.0
## Planet health per day while the building works (section 13): negative for extractors, positive for cleaners.
@export var health_per_day: float = 0.0
## True for a Farm (design.md section 9): output is multiplied by the mean fertility of the footprint / 100.
@export var fertility_output: bool = false
## Multiplier applied when the tile under the origin started as fertile soil (Farm: 1.5). 1.0 = no bonus.
@export var fertile_origin_bonus: float = 1.0
## Gold per assigned worker per day, paid into Settlement.gold (Market: 1). 0 = the building earns no gold.
## Gold is a global counter, never a recipe output or an inventory good.
@export var gold_per_worker_day: float = 0.0
## Gold per citizen per day, paid into Settlement.gold while this building has at least one assigned worker
## (Tax Office: 0.2). Each such building adds its own rate, so two Tax Offices pay 0.4 per citizen. 0 = none.
@export var gold_per_citizen_day: float = 0.0
## Tiles a home must be within (Chebyshev, footprint to footprint) for the Market's food variety to serve it.
## 0 = no reach (only Market uses it). design.md gives no number; ticket 23 chose 12.
@export var market_reach: int = 0
## True when a finished, staffed building counts as one more food type for the variety bonus although it never
## holds food (design.md section 16 City: the Grand Bazaar "counts as a food type"). MarketSystem reads it.
@export var counts_as_food_type: bool = false
## Tiles a home must be within (Chebyshev, footprint to footprint, measured like market_reach) to count as covered by
## this building: Shrine 6, Park 5, Observatory 8, Hall of Seasons 12 (design.md sections 11, 16-17). 0 = no coverage.
## CoverageSystem owns the query; the Spirit "coverage" factor reads it.
@export var coverage_radius: int = 0
## True for housing that needs drinking water (design.md section 9: Rowhouse and every later home). From Town these
## homes must be within water_radius of a finished Well or Water Tower; the Spirit "water" factor penalises the share
## of housed citizens whose home lacks it. Tents and Cottages never need water.
@export var needs_water: bool = false
## Tiles a home needing water must be within (Chebyshev, footprint to footprint, measured like coverage_radius) to be
## served: Well 8, Water Tower 16, Cloud Cistern 10 (design.md sections 9, 16-17). 0 = provides no drinking water.
## CoverageSystem owns the water query; it is kept apart from coverage_radius so wells never count as Shrine coverage.
@export var water_radius: int = 0
## Tiles around a finished building's footprint that it makes wet (Chebyshev, WaterSystem stamps them with the water and
## channel squares): Water Tower 3 (design.md section 17, ticket 39). 0 = wets nothing.
@export var wet_radius: int = 0
## True when the building may not stand on a blighted tile (design.md section 12: Park, Shrine, Orchard).
@export var blocked_by_blight: bool = false
## Tiles around the footprint where blight cuts this building's output (the Greenhouse, 1 = its own tiles and the
## ring next to them) and the output factor then (blight_output_factor, like farm fertility counted half). A tier with
## TierDef.ignores_blight (Greenhouse III) is not cut. 0 = blight does not touch its output.
@export var blight_reach: int = 0
@export var blight_output_factor: float = 1.0
## Region-wide hauler carry from a completed building (Handcart Shed, design.md section 8): haulers whose job
## building is in the same region carry this many units instead of LogisticsDef.haul_load. 0 = no effect.
@export var region_haul_load: float = 0.0
## Speed multiplier for those haulers on paved tiles (Handcart Shed: 1.25, so design.md section 6's 2.5 tiles/s).
## 1.0 = no effect.
@export var paved_haul_speed_factor: float = 1.0
## Lumen grid node (design.md sections 7 and 17, ticket 36): a finished building with grid_feed_radius > 0 feeds every
## building within that many tiles (Chebyshev, footprint to footprint, the Building.footprint_gap measure) and links
## to other nodes within grid_link_range tiles (Lumen Pylon 8 and 12, Lumen Nexus 12 and 12). 0 = not a grid node.
@export var grid_feed_radius: int = 0
@export var grid_link_range: int = 0
## Grid Battery (ticket 36b): Lumen this building holds for its grid, lossless. 0 = not a battery.
@export var battery_capacity: float = 0.0
## Rail Depot (ticket 37): a cargo rail station. At most one per region (by the region of the footprint origin);
## depots joined by track tiles form a rail network (RailSystem).
@export var rail_depot: bool = false
## Airship Dock (ticket 38): a staffed dock joins the air freight network (AirshipSystem) and can fly surveys. At most
## one per region.
@export var airship_dock: bool = false
## Null for buildings that produce nothing.
@export var recipe: RecipeDef = null
@export var upgradable: bool = false
## Tier II then tier III. Empty unless upgradable.
@export var tiers: Array[TierDef] = []
