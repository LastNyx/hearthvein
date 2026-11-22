class_name BuildingDef
extends Resource
## A building type. Data lives in data/buildings/ (design.md sections 16-17).

const CATEGORIES: Array[String] = [
	"housing", "food", "resources", "lumen", "refining", "gold",
	"water", "logistics", "civic", "sky", "landmark",
]
## Categories whose buildings may upgrade in place (design.md section 10). Landmarks, civic, refiners, logistics,
## water and gold buildings never upgrade, even if their def says upgradable.
const UPGRADABLE_CATEGORIES: Array[String] = ["housing", "food", "resources", "lumen"]
## Known placement rule ids. The real checks come with the placement ticket.
##  any: any buildable tile. on_vein / on_rock: on that terrain. shore: next to water.
##  wet: any tile of the footprint is wet. on_wet: the origin tile is wet (Well, design.md section 9).
##  near_forage / near_forest: needs grass-or-forest / forest within placement_radius.
##  shade: needs SHADE_FOREST_TILES forest tiles within placement_radius (Glowcap Grove, ticket 134).
##  (min_fertility is a separate rule on top of any of these.)
##  on_river: at least one footprint tile is a river tile (Clearwater Works); river water tiles may be built on for this
##  rule only, the other footprint tiles must be ordinary buildable land.
##  river_bank: the tile must stand on land with a river tile 4-adjacent to it (Water Wheel, ticket 152).
const PLACEMENT_RULES: Array[String] = [
	"any", "on_vein", "shore", "on_rock", "wet", "on_wet", "near_forage", "near_forest", "on_river", "shade",
	"river_bank",
]
## Which layer a def may be placed on (ticket 40): "ground" (default), "island" (sky layer only) or "either".
const LAYER_RULES: Array[String] = ["ground", "island", "either"]
## Storage modes: none, per_good (cap applies to each good), total (cap shared by any mix).
const STORAGE_MODES: Array[String] = ["none", "per_good", "total"]
## Goods used by cost dictionaries as the global gold counter.
const GOLD := "gold"

@export var id: String = ""
@export var display_name: String = ""
## One plain line for a first-time player: what it makes from what, or what it does. No numbers (tooltips add those from data).
@export var description: String = ""
@export var era: String = ""
@export var category: String = "civic"
@export var size: Vector2i = Vector2i(1, 1)
## good id -> int. Gold uses good id "gold". Empty = free.
@export var cost: Dictionary = {}
@export var worker_slots: int = 0
@export var hauler_slots: int = 0
@export var builder_slots: int = 0
## Night shift (ticket 132, spec N1): worker slots worked from LogisticsDef.night_shift_start to night_shift_end by
## their own people (Citizen.shift), filled after the day slots of the same rank. 0 = no night shift. A night slot
## only works while the building is lit (Settlement.is_lit).
@export var night_worker_slots: int = 0
## Night hauler slots, staffed by night citizens (Storehouse: half its hauler_slots rounded down). 0 = none.
@export var night_hauler_slots: int = 0
## Lamp (ticket 133, spec N2): lights the tiles within lamp_radius from dusk to dawn while fuelled. Fuel is a good the
## haulers bring into the input buffer; LightingSystem burns lamp_fuel_per_night of it once at dusk. A lamp with no
## fuel is dark that night. These are the tier I values; a TierDef overrides them for its tier.
@export var lamp: bool = false
@export var lamp_radius: int = 0
@export var lamp_fuel: String = ""
@export var lamp_fuel_per_night: float = 0.0
## True for the Grid Lamp (tier IV): it draws its fuel from the Lumen grid and no hauler brings it.
@export var lamp_grid: bool = false
## Night Watch (ticket 143, spec N10): its night walker patrols the road tiles within patrol_radius tiles of the
## footprint (Chebyshev from the footprint, the "within N tiles" measure coverage uses) in a loop. Those tiles count
## as lit, radius 1, while the watch is staffed and fuelled, so a small night building on the route needs no lamp.
## 0 = not a patrol building.
@export var patrol_radius: int = 0
## Good the walker's lantern burns each night (charcoal). Haulers bring it into the input buffer like lamp fuel;
## the watch burns patrol_fuel_per_night of it at dusk, and with no worker or no fuel the route stays dark.
@export var patrol_fuel: String = ""
@export var patrol_fuel_per_night: float = 0.0
## Night-only building (ticket 134: Charcoal Kiln, Glowcap Grove): it exists for its night slots alone, so it opens no
## day work slots and ProductionSystem makes nothing by day even if a worker is somehow at its door.
@export var night_only: bool = false
## Moths come to light (ticket 144, Moonmoth Loft): at night the building only works while at least `min_lit_tiles`
## lit tiles lie within `lit_tile_radius` tiles (Chebyshev) of its footprint; below that it halts with "needs_light".
## 0 = no such rule.
@export var min_lit_tiles: int = 0
@export var lit_tile_radius: int = 0
## Goods a building drinks or eats each night while its night shift works and it is lit (Tavern: 4 crops). Unlike a
## recipe it makes no good: haulers bring the goods in like any consumer, and SpiritSystem takes one night's amount
## at the night shift start. A building that cannot pay serves nothing that night. Empty = drinks nothing.
@export var night_inputs: Dictionary = {}
## Lumen per day.
@export var upkeep_lumen: float = 0.0
## True for the Village workplaces (ticket 159): their upkeep Lumen is taken from storage at the day start, nobody hauls
## it to an input buffer. Haulers could not keep dozens of farms topped up, and every unpaid day halved a field's food.
@export var upkeep_from_storage: bool = false
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
## True for the Woodcutter and Quarry: a gain popup (ticket 137) shows "+N" with the good's icon over it when it makes
## goods. Render only; later defs may opt in.
@export var gain_popup: bool = false
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
## True for a food producer the Great Dimming leaves alone (the Fishing Dock): it keeps its regular Dimming factor.
@export var great_dimming_immune: bool = false
## True for a food producer that makes PlanetDef.winter_food_factor of its output in winter (lean winters, ticket 159):
## Forager, Farm and Fishing Dock. It stacks with the Dimming; the Glowcap Grove and the late food buildings are not
## marked.
@export var lean_winter: bool = false
## Planet health per day while the building works (section 13): negative for extractors, positive for cleaners.
@export var health_per_day: float = 0.0
## Heartroot Tap (design.md section 17): the building only works while Settlement.planet_health() is at least this
## much; below it ProductionSystem halts it with "planet_too_sick" and it resumes once health is back. 0 = no gate.
@export var min_planet_health: float = 0.0
## Bloom Orchard (design.md section 17): placement needs the mean fertility of the footprint tiles to be at least this
## (Placement reason "low_fertility"). Output does not scale with fertility. 0 = no rule.
@export var min_fertility: float = 0.0
## Hall of Seasons (design.md section 17): while a finished, staffed, unpaused building of this def covers a home
## (coverage_radius, CoverageSystem.coverage_reaches), that home takes this share of the Spirit darkness penalty
## (0.5 = half). The lowest value in reach wins; 1.0 = no effect. DimmingSystem.darkness_factor applies it.
@export var darkness_factor: float = 1.0
## Healers (design.md section 17, Ascendant), measured like clean_radius (Euclidean from the closest footprint tile),
## once a day while the building works. Verdant Spring: each day heal_blight_per_day blighted tiles within
## heal_blight_radius are cleared and turned into fertility-100 soil. 0 = no soil healing.
@export var heal_blight_radius: int = 0
@export var heal_blight_per_day: int = 0
## Rewilding Grove: each day rewild_per_day grass or stump tiles within rewild_radius turn into forest. 0 = none.
@export var rewild_radius: int = 0
@export var rewild_per_day: int = 0
## Vein Mender (design.md section 17): every vein extractor whose footprint is within drain_radius tiles (footprint gap,
## like coverage) of this building while it works has its negative health_per_day multiplied by drain_factor. Several
## menders never stack (the lowest factor in reach counts). drain_radius 0 = not a mender.
@export var drain_radius: int = 0
@export var drain_factor: float = 1.0
## Clearwater Works: while it works, river fouling does not flow downstream out of its river tile(s).
@export var stops_fouling: bool = false
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
## True for a market that buys the goods a GoodDef puts a sale_price on (Market, ticket 144): each day it sells the
## stock above the good's sale_keep for gold while it has an assigned worker.
@export var sells_goods: bool = false
## Offers a night caravan may bring to this building (Night Market, ticket 141): [{good, amount, gold}, ...]. While a
## caravan visits, one is chosen from the settlement seed and the day, and its `amount` of `good` costs `gold`.
## Empty = no caravan stops here. CaravanSystem owns the schedule and the buy.
@export var caravan_offers: Array = []
## True when a finished, staffed building counts as one more food type for the variety bonus although it never
## holds food (design.md section 16 City: the Grand Bazaar "counts as a food type"). MarketSystem reads it.
@export var counts_as_food_type: bool = false
## Tiles a home must be within (Chebyshev, footprint to footprint, measured like market_reach) to count as covered by
## this building: Shrine 6, Park 5, Observatory 8, Hall of Seasons 12 (design.md sections 11, 16-17). 0 = no coverage.
## CoverageSystem owns the query; the Spirit "coverage" factor reads it.
@export var coverage_radius: int = 0
## Tiles a home must be within (Chebyshev, footprint to footprint, measured like coverage_radius) to be cheered at
## night by this building while its night shift works and it is lit (Tavern: 4). Apart from coverage_radius so a
## Tavern never joins the Shrine/Park coverage factor; SpiritSystem's "tavern" factor owns this query. 0 = no cheer.
@export var spirit_radius: int = 0
## Dimming forecast lead in seasons while at least one finished, staffed, unpaused building of this def stands on a
## settled island or the ground (Observatory: 2, ticket 41d). The longest lead wins; 0 = no effect, the planet's
## dimming_forecast_seasons (1) applies. DimmingSystem.forecast_lead owns the query.
@export var forecast_lead_seasons: int = 0
## Per-citizen Lumen light need during a Dimming while at least one finished building of this def stands (Dawn Beacon:
## 0.35 instead of PlanetDef.light_per_citizen 0.5, ticket 42). The lowest value wins; 0 = no effect.
## DimmingSystem.light_per_citizen owns the query. Needs no workers or upkeep.
@export var light_need_per_citizen: float = 0.0
## True for housing that needs drinking water (design.md section 9: Rowhouse and every later home). From Town these
## homes must be within water_radius of a finished Well or Water Tower; the Spirit "water" factor penalises the share
## of housed citizens whose home lacks it. Tents and Cottages never need water.
@export var needs_water: bool = false
## Tiles a home needing water must be within (Chebyshev, footprint to footprint, measured like coverage_radius) to be
## served: Well 8, Water Tower 16, Cloud Cistern 10 (design.md sections 9, 16-17). 0 = provides no drinking water.
## CoverageSystem owns the water query; it is kept apart from coverage_radius so wells never count as Shrine coverage.
@export var water_radius: int = 0
## Water Wheel (ticket 152, spec N10): a finished, unpaused one drives the one 4-adjacent water-driven workshop (below):
## that workshop needs one worker fewer per shift (min 1) and its night shift works without a lamp. On fouled water
## the drive gives no worker saving and the driven workshop runs at half speed instead.
@export var drives_workshop: bool = false
## Water Wheel numbers (spec N10), read from the wheel's def: workers the drive saves per shift (min 1 slot stays) and
## the driven workshop's speed factor on fouled water (0-1).
@export var drive_worker_saving: int = 1
@export var drive_speed_factor: float = 0.5
## True for a workshop a Water Wheel can drive: the Sawmill, Mason and Bakery.
@export var water_driven: bool = false
## True for a producer that only works with water at hand (Hydroponic Hall, ticket 39c): a wet tile under any tile of the
## footprint, or a finished drinking-water source (water_radius) within reach. Otherwise it halts with "dry". The farm's
## needs_wet tier is separate and stays on WaterSystem.footprint_wet.
@export var work_needs_water: bool = false
## True for a producer that halts with "dry" unless some tile of its footprint is wet (Sky Garden, ticket 41b): unlike
## work_needs_water a drinking-water source in reach does not count, only a wet tile (on an island a Cloud Cistern's wet_radius).
@export var work_needs_wet: bool = false
## Tiles around a finished building's footprint that it makes wet (Chebyshev, WaterSystem stamps them with the water and
## channel squares): Water Tower 3 (design.md section 17, ticket 39). 0 = wets nothing.
@export var wet_radius: int = 0
## True when the building may not stand on a blighted tile (design.md section 12: Park, Shrine, Orchard).
@export var blocked_by_blight: bool = false
## Levee (spec N10, ticket 154): a finished one holds the spring flood off the tiles behind it (FloodSystem). Placed
## like a road along the bank: 1x1, on land touching the river (placement rule river_bank).
@export var levee: bool = false
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
## one per region and layer (an island dock and a ground dock of the same region form a walker link, ticket 40c).
@export var airship_dock: bool = false
## River Dock (ticket 153): two finished docks on the same river form a boat link haulers may use as one leg of a trip
## (HaulingSystem). Downstream runs at LogisticsDef.river_downstream_factor times a dirt road's walk speed, upstream at
## river_upstream_factor; the river's flow data tells which way is downstream.
@export var river_dock: bool = false
## Sky Lift (ticket 40c): one building on the GROUND layer (layers "ground") that also holds the sky tile directly
## above its tile. Placing it needs a valid ground tile and a free skystone tile of a raised island above; it writes its
## id into both occupancy grids. A finished one on a fed island carries walkers and haulers between the layers.
@export var sky_lift: bool = false
## Layer rule, one of LAYER_RULES. Lift Anchor is ground-only; later island buildings use "island" or "either".
@export var layers: String = "ground"
## Lift Anchor (ticket 40): a finished one raises a sky island over the region its origin is in (IslandSystem).
## At most one per region and LogisticsDef.island_max in all, sites count.
@export var raises_island: bool = false
## Id of a building that, once finished, makes the first placement of this def free (Lift Anchor: "sky_foundry").
## "" = never free. Settlement.cost_for answers with the effective cost.
@export var free_first_with: String = ""
## Good id for the wood dead end (ticket 121): while the stock of this good is below this def's cost of it and no site of
## this def is open, placing it costs nothing (Woodcutter and Forester: "wood"). "" = never. Settlement.cost_for answers.
@export var free_when_dry: String = ""
## True when only one building of this def may exist at a time, sites counting (Placement reason "unique").
@export var unique: bool = false
## Staged landmark (Skyheart, design.md section 18, ticket 45): [{"name": String, "cost": {good: int}}] in order. A
## def with stages is built one stage after another on the same building (Building.stage); `cost` is then unused and
## the placement cost is the first stage's. Empty = an ordinary one-step building.
@export var stages: Array[Dictionary] = []
## Skyheart reservoir (ticket 45): Lumen it can hold once finished, and the most it takes from its grid per hour.
## 0 = no reservoir. SkyheartSystem owns the charge.
@export var reservoir_capacity: float = 0.0
@export var reservoir_fill_per_hour: float = 0.0
## Nightly yield (ticket 151, spec N8): goods added to the door buffer once, at the night shift's start, while the
## building is finished, unpaused and has a night worker. Not a recipe, so the amount does not scale with the crew or
## the night's length. Empty = none. The Observatory catches starlight.
@export var night_yield: Dictionary = {}
## True when night_yield happens only during a Dimming (the Observatory's starlight).
@export var night_yield_dimming: bool = false
## Star charts (ticket 142): airship survey flights advance this much faster (0.25 = 25%) while this finished,
## unpaused building has its full night crew and is out of the gloom. The Observatory. 0 = no effect.
@export var survey_speed_bonus: float = 0.0
## True when the building makes PlanetDef.glow_river_grove_factor more while it stands within
## PlanetDef.glow_river_radius tiles of the river in a Dimming (the Glowcap Grove).
@export var glow_river_boost: bool = false
## True when the building makes DayNightDef.moon_new_glowcap more on a new-moon night (the Glowcap Grove, ticket 145).
@export var new_moon_boost: bool = false
## Null for buildings that produce nothing.
@export var recipe: RecipeDef = null
@export var upgradable: bool = false
## Tier II then tier III. Empty unless upgradable.
@export var tiers: Array[TierDef] = []


## True when the building has night slots (worker or hauler) or works at night only: the moon badge on its cards.
func works_at_night() -> bool:
	return night_worker_slots > 0 or night_hauler_slots > 0 or night_only


## What placing this def costs: the first stage's cost for a staged building, else `cost`.
func entry_cost() -> Dictionary:
	return (stages[0].get("cost", {}) as Dictionary) if not stages.is_empty() else cost
