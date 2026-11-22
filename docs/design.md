# Hearthvein design (v1)

Source of truth for decisions: `decisions.md` (D1-D55). This doc turns them into rules and numbers.
Every number here is a first guess, meant to be tuned in playtests; they live in data files, not code.

## 1. Pitch
Grow one settlement from a camp around the Hearth into a glowing sky city on a living planet. Lumen, the cyan
planet-energy in the veins under the ground, drives everything, but pumping it sickens the land and drains the
planet. Every year the veins go quiet for a while (the Dimming), longer each era and longer still on a sick
planet. Climb seven eras, lift districts into the sky, heal the land, finish the Skyheart and survive the Great
Dimming with the planet still standing.

Original techno-fantasy city builder (Oxygen Not Included-like length and depth, Timberborn/Frostpunk-like
pressure), Godot 4 / GDScript, desktop Linux first. Campaign 6-10 hours across many sittings, plus endless.

## 2. Core loop
1. Place buildings, roads, channels and storehouses. Never handle individual citizens (D15).
2. Citizens fill free job slots automatically by priority; haulers move goods between doors and storehouses.
3. Producers turn terrain into base resources; refiners turn base resources into refined goods.
4. Food surplus fills the growth bar; housing caps the population; Spirit speeds or stalls everything.
5. Population + gold + an era landmark unlock the next era. Refined goods pay for upgrades and late buildings.
6. Every year: stockpile Lumen and food for the forecast Dimming.
7. All the time: Lumen extraction blights land and drains planet health; a sick planet makes every later
   Dimming longer, thins the veins and kills forest. Heal it or pay for it later.

Short-run tension: more Lumen = more growth. Long-run tension: more Lumen = a sicker planet = harder Dimmings,
and the campaign win needs planet health >= 50% at the very end.

## 3. Time (D35)
- 1 day = 60 s at 1x. Speeds: pause, 1x, 2x, 3x.
- Season = 8 days. Year = 4 seasons = 32 days = 32 min at 1x. 8-hour campaign is about 15 years.
- Economy settles once per in-game hour (2.5 s at 1x); walkers move every frame; Spirit, blight, planet health,
  water and fertility update once per day; forest and soil changes once per season.

### Pacing targets (at 1x, a competent first run)
| Milestone | Time | Year |
|---|---|---|
| Village | 0:30 | 1 |
| Town | 1:15 | 3 |
| City | 2:30 | 5 |
| Conflux | 3:45 | 7 |
| Skyborne | 5:00 | 10 |
| Ascendant | 6:15 | 12 |
| Skyheart finished | ~7:30 | 14 |
| Great Dimming over (win) | ~8:00 | 15 |

## 4. Map and regions (D34, D40)
- 128x96 square grid, 32x32 px tiles, top-down 3/4 view (D12, D13). Seeded generation.
- Split into a 4x4 grid of 16 regions, 32x24 tiles each. Start in one of the four central regions.
- Terrain: grass, fertile soil, forest, rock, water (river, lake), Lumen vein. Plus states that change over the
  game: stump (cut forest), blighted, wet/dry, fouled water, fertility per tile.
- Guaranteed in the start region: part of the river, 3-5 veins, forest and rock within 8 tiles of the Hearth.
  The river crosses at least 6 regions and has a flow direction (needed for fouling, section 12).
- Outer 6 tiles of the whole map: plain land only, kept for v2 neighbours (D11).
- Buying regions: any region adjacent (4-way) to an owned one. Price in gold: 50, 100, 200, 350, 500, then 600
  each. Locked regions show dimmed terrain; you can see but not build. No era locks.
- Region rewards, 4-6 per map, shown as a small marker on the locked region: rich vein (yield x1.5),
  ruins (one-time reward: gold, refined goods, or a free landmark stage), fertile valley (large fertile soil
  patch), old forest (forest that regrows 2x faster), spring (a water source away from the river).
- Sky land (Skyborne, section 17): floating districts add up to 4 islands of 16x12 tiles over owned regions.

## 5. Citizens, housing and growth (D17, D46)
- Start: Hearth (houses 8), 8 citizens, 60 food, 40 wood, 0 stone, 10 Lumen, 0 gold.
- Each citizen eats 1 food/day. Daily surplus goes into the growth bar.
- Growth bar size = 3 + pop / 6 food (tuned in 47b-47d; was 8 + pop / 3). Full bar and a free bed = one new citizen
  at the Hearth.
- Immigration: Spirit >= 40 and free beds = one newcomer every day, on top of growth (tuned in 47i; was Spirit 70,
  every 3 days: a well-run City sits at Spirit 40-49, so immigration never came).
- Food stock at 0 with a deficit: one citizen leaves per day until food balances.
- Homeless (pop above beds): Spirit penalty, no growth.
- Soft cap (D46): target ~600 citizens. Above 600 the growth bar size is multiplied by 1 + (pop - 600) / 100,
  and immigration stops.
- All citizens are simulated and drawn as walkers; walkers are hidden at the farthest zoom.
- Citizens have no age, skills or families in v1 (D29).

## 6. Jobs, walking and building
- Production buildings have worker slots, filled from idle citizens by priority:
  food > water > Lumen > hauling > building > healers (Cleanser, Purifier Tower, Vein Mender, Clearwater Works, Rewilding
  Grove, Verdant Spring) > wood and stone > gold > refined goods > civic (169). High beats Normal beats Low across every
  rank. The player can set one building's priority (low/normal/high) or pause it; never assigns a person.
- Workers walk home -> job; output counts only while at work, so distance matters.
- Walking speed (tiles/s): grass 1.0, dirt road 1.5, paved road 2.0. Handcart haulers on paved road 2.5.
- A building with no road connection to the Hearth (or, from Conflux, to a Rail Depot in its region) gets no
  workers and shows an icon (D22).
- Roads: dirt free, paved 1 wood + 0.2 cut stone per tile (Town).
- **Construction (D48):** placing a building makes a site. Haulers deliver its cost, then builders build it
  (Builder job: 4 slots at the Hearth, 4 per Builder's Yard). Build time 0.3 days per tile + 0.1 per era past Camp (0.3-6 days). The player
  can raise one site's priority. Demolish refunds 50% to the nearest storehouse. Upgrades (section 10) work the
  same way and the building keeps running at its old tier until done.

## 7. Resources and refined goods (D14, D38)
Base resources are five: food, wood, stone, Lumen, gold. Gold is a global counter (coins, never hauled).
Food, wood, stone, Lumen and every
refined good are physical goods held in storehouses and moved by haulers.

| Good | Made by | From | Era | Used for |
|---|---|---|---|---|
| Food | Forager, Farm, Fishing Dock, Greenhouse, Hydroponic Hall, Sky Garden, Bloom Orchard | land/water | Camp+ | eating, growth |
| Wood | Woodcutter | land | Camp+ | building, roads, refining |
| Stone | Quarry, Workshop | land, Lumen | Village+ | building, roads, refining |
| Lumen | Tap, Pump, Reactor, Vein Bore, Aether Collector, Heartroot Tap | veins/air | Camp+ | upkeep, light in the Dimming, landmarks |
| Gold | Market, Tax Office, Grand Bazaar | people | Village+ | regions, era gates, late buildings |
| Planks | Sawmill | 6 wood -> 3 | Village | tier II upgrades, Town+ buildings |
| Cut stone | Mason | 6 stone -> 2 | Town | tier II upgrades, paved roads, landmarks |
| Lumen cells | Refinery | 6 Lumen -> 1 cell (holds 5) | Town | lossless Lumen storage, tools |
| Meals | Kitchen | 1 food of type A + 1 of type B -> 3 meals | Town | eating (1 meal = 1 food), food variety |
| Tools | Toolsmith | 1 plank + 1 cell -> 1 | City | tier III upgrades, Conflux+ buildings |

- Storage: Hearth holds 150 of each good. Storehouse (2x1) holds 400 units in total, any mix; the player can
  set a storehouse to accept only some goods.
- Lumen leaks: raw Lumen in storage loses 3% a day (ticket 159; was 1%), counted on the first 500 of the settlement's stock only (ticket 169). Cells don't leak. When raw Lumen runs out, buildings and
  light draw on cells automatically (1 cell = 5 Lumen). This is what makes Dimming prep a choice: refine
  early and lose 1 in 6, or keep it raw and lose 3% a day.
- Hauling order (ticket 171): sites and upgrades first, then door pickups and input refills take turns; in a refill a High
  priority building comes before the rest, then the oldest. An upgrade's or a site's last delivery may be under 1 unit. A
  consumer no road reaches never hides a good's stock from the others. No number changed.
- Night shift (ticket 138): night slots run 20:00-06:00 and only inside a lamp's light. Lamps (radius, fuel a night): Brazier
  3 (1 wood), Lantern Post 5 (2 charcoal), Lumen Lamp 7 (3 Lumen), Grid Lamp 9 (1 Lumen from the grid). The Night Watch's
  walker lights radius 1 along its route (1 charcoal). Kiln: 2 charcoal per worker-day. Glowcap Grove: 3 food per night
  worker. Beds: Hut 4/3, Lodge 5/3, Cottage tiers 5, 7, 9. Fair share: slots of one rank, priority and shift are filled one
  each round-robin across the buildings, so the last built are not left empty; High priority beats Normal across categories.
- Night life (tickets 139-147): the night-only buildings are the Tavern (4 crops a night, Spirit r4), Bakery (4 crops + 2
  charcoal -> 3 bread, a better food), Charcoal Kiln (4 wood -> 2 charcoal), Night Watch (patrol, 1 charcoal a night),
  Moonmoth Loft (silk, 8 gold each above 10 kept; needs 3 lit tiles within 2) and the Night Market (2x2, 30W 20P 60G, 3 night
  workers). Night slots are filled after every day slot, so night buildings only use hands the day shift leaves idle.
- Moon (ticket 145): an 8-day cycle, one phase a day (day 1 new, day 5 full). Full moon: every lamp reaches 1 tile further
  and Spirit +2; new moon: Glowcap Grove +25%. The clock shows the phase.
- Night arrivals (ticket 146): at the night shift's start newcomers add 0.5 to a night bar under the same conditions as the
  daily immigrant (Spirit, a free bed, not in a Dimming); at 1 a newcomer arrives, but only if the Hearth or a tile touching
  it is lit tonight. Dark, the newcomer waits and a hint says why.
- Night Market (ticket 141): while lit and staffed it sells surplus priced goods once, at the night shift's start. Every 4-6
  nights (from the settlement seed and the day only) a caravan parks beside the first lit, staffed Night Market with one offer
  (tools x5 for 40 gold, or Lumen cells x6 for 45), tonight only, one buy, gone at 06:00. A night with no such market is skipped.
- Balance (ticket 147): the balance bot lights the Hearth with a Brazier, then builds the Night Watch, Night Market, Kiln,
  Loft, Bakery and Tavern only once the era's gold gate is nearly met (Village, Town) or from City on, when wood and gold
  are in surplus, and buys a caravan offer when the landmark lacks that good or the stock is low. It never forces them.
- Food types for variety: forage, fish, crops, greenhouse, meals (counts once), sky (Sky Garden), orchard.

## 8. Hauling and logistics (D39)
- Hauler is an auto-filled job. Slots: Hearth 2, each Storehouse 2, Builder's Yard 2.
- Producers drop output in a door buffer (40 units). Full buffer = production stops, icon shown.
- Haulers carry door buffers to the nearest storehouse with room, and from storehouses to consumers (refiners,
  construction sites, buildings with upkeep). Consumers keep an input buffer of 2 days of need.
- Carry: 5 units on foot. Handcart Shed (Town) gives every hauler in its region 15 units and +25% speed on
  paved roads.
- Citizens eat and take light Lumen from the nearest storehouse in their region (a walk, but no hauling).
- Cargo rail (Conflux): a Rail Depot in each region, linked by rail track (placed like road, 1 wood + 1 stone +
  1 cut stone per tile). Each depot has a manifest the player never edits: it moves surplus to regions in need.
  Without rail, goods cross regions only by hauler on foot.
- Airship Dock (Conflux): freight between any two owned regions with docks, no track needed; also serves islands.
- Lumen grid (Conflux): Lumen Pylons feed Lumen to buildings in range directly; no hauling of Lumen inside the grid,
  and grid buildings' upkeep -25%.

## 9. Water, soil and forest (D29, D42)
### Water
- Every tile is wet or dry; recomputed daily, no fluid simulation.
- Wet: within 2 tiles of river/lake/spring, or within 1 tile of a flowing channel.
- Irrigation Channel (Village): placed like road (1 stone/tile). A channel is flowing if it connects to a
  water tile through other channels. Channels block buildings but not walking (small footbridges).
- Farms: x1.25 if at least half the footprint is wet. Irrigated Farm (Farm tier II) works only when wet.
- Drinking water: from Town, housing from Rowhouse up needs a Well within 8 tiles (Water Tower: 16 tiles,
  Cloud Cistern on islands). Missing = Spirit penalty for those homes. Tents and Cottages never need wells.
- A Well must sit on a wet tile.

### River: Water Wheel, River Docks, spring floods (tickets 152-154)
- Water Wheel (Village, 12W 8St, no workers): placed on a bank tile next to the river. It drives the one 4-adjacent
  Sawmill, Mason or Bakery: that building needs 1 worker fewer per shift (never below 1) and its night shift does not need
  a lamp. On a fouled river tile the saving is lost and the building runs at x0.5 instead.
- River Dock (Town, 18W 14P 25G, 1 worker, upkeep 1 Lumen): placed on a bank tile. Two docks on the same river are a link
  that haulers may use for one leg of a trip: downstream at 3x a dirt road's speed, upstream at 0.75x (the map's river flow
  gives the direction). A boat sails between the docks. A trip takes the river only when it is faster than the roads.
- Spring flood: each spring, on a day picked from the map seed and the year (never before the third day of spring, so there is always
  one day of warning), ground within 2 steps of the river floods for 1 day (WaterDef.flood_days/flood_radius). Rock,
  skystone and sky buildings stay dry. A building on a flooded tile stops ("Flooded"), walkers wade round it. When the water
  drains each tile gets +10 fertility (the silt, marked until the next spring). A forecast notice comes the day before.
- Levee (Town, 6 stone + 2 cut stone a tile): placed like a road along the bank. The flood cannot pass a finished levee, so
  the land behind a continuous stretch stays dry.

### Fouling
- A river tile next to a blighted tile becomes fouled; fouling flows downstream 1 tile per hour until it meets
  clean inflow or the map edge, and clears 2 days after the source blight is gone.
- Fouled water: Fishing Dock x0.5, irrigated farms x0.75, wells on tiles wet only from fouled water give
  unsafe water (counts as missing).
- Clearwater Works (Ascendant) stops fouling past its tile.

### Soil fertility
- Each tile has fertility 0-100%. Fertile soil starts at 100, grass at 60, everything else 0 (can't farm).
- Farm output per tile x(fertility / 100), times x1.5 on tiles that started as fertile soil.
- Farmed tile loses 4 points a year; fallow tile regains 10 a year (up to its start value).
- Blighted tile: fertility counts as half until cleared. Verdant Spring restores to 100.
- Farm tier III (Terraced Farm) stops the yearly loss.

### Forest
- Woodcutters turn forest into stumps. A stump regrows to forest in 2 seasons if planet health >= 60% and the
  tile is not blighted. Forester (Village) plants new forest on grass in radius 5 and halves regrowth time.
- Planet health below 60%: each season (60 - health) / 10 percent of forest tiles die back to grass.
- Living forest helps the planet (section 13).

## 10. Upgrade tiers (D36)
- Tiers: base, II, III, upgraded in place (keeps spot and workers; building runs at old tier during works).
- Only housing, food, resources and Lumen buildings upgrade. Landmarks, civic, refiners, logistics don't.
- Tier II unlocks in Town, tier III in City.
- Default rule (per building data may override):

| Tier | Effect | Cost |
|---|---|---|
| II | output or beds x1.5, +1 worker slot | planks = 50% of base wood + stone cost, cut stone = 25% |
| III | output or beds x2 (of base), +2 worker slots | tools = 20% of base wood + stone cost, cells = 10%, cut stone = 25% |

- Special tiers: Tent II/III = Hut/Lodge. Farm II = Irrigated Farm (needs wet; x1.5 output on top of tier).
  Farm III = Terraced Farm (no fertility loss). Lumen extractors: tiers raise output but not blight radius or
  rate, so upgrading is cleaner than building more. Greenhouse III ignores blight.

## 11. Spirit (D18)
One meter, 0-100, starts at 60. Each day it moves 2 points towards a target:
- Base 50.
- +5 per food type eaten beyond the first (max +20).
- +10 if most homes are inside Shrine/Park/Hall of Seasons coverage.
- -15 hunger (anyone unfed today). -10 homeless.
- -up to 15 blight near homes (share of homes with blight within 2 tiles).
- -up to 10 no drinking water (share of homes that need water and lack it).
- -20 darkness during a Dimming (light Lumen short, D43).
- -5 if a Tax Office exists.
- -up to 10 planet grief: (60 - planet health) / 6 when health is below 60%.

Effects: >= 70 work +15%, growth +20%. >= 40 immigration on (section 5). <= 30 work -20%, no immigration.
Below 20 for 5 days in a row: one citizen leaves every 2 days.

## 12. Blight
- Each Lumen extractor has a blight radius and period. Each period the nearest non-blighted tile in the radius
  turns blighted. A paused extractor spreads no blight while it is paused (existing blight stays); demolishing
  it also stops the spread.

| Extractor | Radius | Every |
|---|---|---|
| Lumen Tap | 2 | 6 days |
| Lumen Pump | 4 | 3 days |
| Lumen Reactor | 6 | 2 days |
| Vein Bore | 5 | 1 day |
| Aether Collector, Heartroot Tap | none | - |

- Blighted tile: farm fertility counted half, forest doesn't regrow, can't hold Park/Shrine/Orchard, homes
  within 2 tiles lower Spirit, fouls adjacent river tiles.
- Removing the extractor stops spread; existing blight stays.
- Cleaners: Cleanser (Village, 96) 1 tile / 2 days in r5. Purifier Tower 1 tile/day in r8 and blocks new blight in r4.
  Park blocks blight in its footprint. Verdant Spring turns 1 blighted tile/day in r10 into fertile soil.
- Blight never ends the game; it costs food, Spirit and planet health.

## 13. Planet health (D30)
A map-wide meter 0-100%, starts at 100. Changes once a day by:

| Source | Per day |
|---|---|
| Each blighted tile | -0.0006 |
| Each working Lumen Tap / Pump / Reactor / Vein Bore | -0.005 / -0.012 / -0.025 / -0.05 |
| Each forest tile on the map | +0.00005 |
| Cleanser / Purifier Tower / Park | +0.01 / +0.03 / +0.005 |
| Verdant Spring / Vein Mender / Rewilding Grove / Clearwater Works | +0.08 / +0.04 / +0.03 / +0.03 |
| Each active Great Dimming day | -0.5 |

Rough check: a mid-City settlement (12 Taps, 6 Pumps, 2 Reactors, 300 blighted tiles, 3000 forest tiles,
some cleaning) loses about 4-5% a year. Careless play ends near 25-35%; healing in Conflux-Ascendant lifts it.
HUD shows the meter and its yearly trend.

Effects of low health:
- Dimming length factor = 2 - health/100 (x1.0 at 100%, x1.5 at 50%, x2.0 at 0%) (D37).
- Vein yield x(0.5 + health/200): every vein extractor makes less on a sick planet.
- Forest dieback below 60% (section 9). Spirit grief below 60% (section 11).
- Heartroot Tap only works at health >= 50%.

## 14. The Dimming (D37, D43)
- One a year, starts on day 1 of winter. Forecast one season ahead with its length (Observatory: two seasons).
- Length = round(era base x planet health factor), fixed at forecast time.
  Era base: Camp 2, Village 3, Town 4, City 5, Conflux 6, Skyborne 7, Ascendant 8 days.
- During a Dimming: vein Lumen output x0.25, Aether Collectors x0.5, Forager and plain farms x0.5 (Greenhouse,
  Hydroponic Hall, Sky Garden unaffected), Fishing unaffected. Buildings without their Lumen upkeep run at x0.5.
- Light (D43): each citizen needs 0.5 Lumen/day (Dawn Beacon: 0.35). Short = darkness: Spirit -20 target,
  no growth.
- Long nights (ticket 148): a Dimming night runs 18:00-07:00 (data, DayNightDef.dimming_night_start/end) instead of
  20:00-06:00. Night shifts, lamps, the map tint and the walker schedule all follow it, and the day shift shrinks to the
  hours between (07:00-18:00). The clock row says "Dimming: night 18-07".
- Gloom (ticket 149): in a Dimming night only, gloom starts on the forest-edge tiles and creeps 1 tile an hour (data,
  LogisticsDef.gloom_spread_per_hour) over unlit land. It never enters a lit tile (lamps, a Night Watch route, the glow
  river) and a tile that gets lit is cleared; all gloom is gone at dawn. A building with any footprint tile in gloom stops
  ("Stopped: in gloom - light it"); walkers take gloom at 6x path cost, so they detour when the way round is short. No
  combat, no damage. Lamps are the answer: keep the night buildings and the paths you need inside a lamp's light.
  Gloom is a ground state: buildings on an island stand above it and keep working (ticket 186).
- Vein surge (ticket 150): when a Dimming ends (the Great Dimming too) Lumen producers on veins make x1.5 for 2 days
  (PlanetDef.vein_surge_factor/days). The Dimming's forecast says so; the objectives show "Vein surge: day 1 of 2".
- Dim blooms (ticket 151): the Glowcap Grove makes x2 during a Dimming (stacking with the new moon's +25%), and a Grove
  within 2 tiles of the river grows +25% faster there. The glow river: in a Dimming the river tiles count as lit (radius 1)
  at night, so the banks stay free of gloom, and they shimmer cyan-white. Starlight: an Observatory with a night crew makes 1
  starlight a night in a Dimming; when the day's light is still short after raw Lumen and cells, each starlight covers 5
  Lumen (PlanetDef.starlight_lumen).
- **Great Dimming:** starts one season after the Skyheart is finished; lasts 16 days (not scaled by health,
  D51); vein output x0.1, all farms x0.5, light 0.75/citizen, planet health -0.5/day. The Skyheart's
  reservoir (section 18) is what gets you through it.
- Endless (D41): after the win, Dimming base keeps +1 day per 2 years, no cap.

## 15. Eras (D31, D32)
| Era | Gate to reach it | Landmark built here (gate to next) | Theme |
|---|---|---|---|
| Camp | start | Meeting Hall | tents, foraging, first tap |
| Village | pop 15, gold 30, Meeting Hall | Bell Tower | farms, planks, channels |
| Town | pop 40, gold 150, Bell Tower | Lumen Spire | upkeep, refining, wells, tier II |
| City | pop 100, gold 500, Lumen Spire | Lumen Nexus | reactors, tools, tier III |
| Conflux | pop 200, gold 1200, Lumen Nexus | Sky Foundry | Lumen grid, cargo rail, airships |
| Skyborne | pop 320, gold 2500, Sky Foundry | Dawn Beacon | floating districts, clean sky Lumen |
| Ascendant | pop 450, gold 4000, Dawn Beacon | Skyheart (final) | planet healing, the finale |

Reaching an era unlocks its building set. No research tree (D19).

## 16. Buildings, Camp to City
Cost shorthand: W wood, St stone, G gold, L Lumen, P planks, S cut stone, C Lumen cells, T tools.
Workers = slots. Upkeep = Lumen per day (Village on, ticket 159; Camp pays none). Lean winters: Forager, Farm and Fishing Dock make x0.5 in winter (8 days), stacking with the Dimming; the Glowcap Grove and late food buildings are not affected. Output per worker per day at tier base.

### Camp
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Hearth | 2x2 | start | 2 haul, 4 build | - | town centre, houses 8, storage 150 each |
| Tent | 1x1 | 5W | - | - | houses 3 (Hut 4, Lodge 5) |
| Forager | 1x1 | 10W | 2 | - | +4 food; x0.5 in winter; needs grass/forest in r3 |
| Woodcutter | 1x1 | 10W | 2 | - | +12 wood; cuts forest in r4 |
| Storehouse | 2x1 | 25W | 2 haul | - | 400 units any goods |
| Lumen Tap | 1x1, vein | 20W | 2 | - | +4.5 L; blight r2/6d (tooltip says so) |
| Meeting Hall* | 2x2 | 60W 10L | - | - | Village gate |

### Village
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Cottage | 1x1 | 10W 5St | - | - | houses 5 (Cottage II 7, Cottage III 9) |
| Farm | 2x2 | 21W 9St | 3 | 1 | +4 crops x fertility; x1.25 wet; x0.5 in winter |
| Fishing Dock | 1x1, shore | 14W 6St | 2 | 1 | +4 fish; x0.5 fouled; x0.5 in winter |
| Quarry | 1x1, rock | 25W | 2 | 1 | +12 St |
| Market | 2x2 | 40W | 2 | - | +1 G; food variety needs a Market in reach of homes |
| Shrine | 1x1 | 12W 18St 5L | - | - | Spirit coverage r6 |
| Sawmill | 2x1 | 14W 21St | 2 | 1 | 6 W -> 3 P, 3/worker/day |
| Forester | 1x1 | 20W | 1 | 1 | plants forest r5, halves regrowth |
| Builder's Yard | 2x1 | 21W 9St | 4 build, 2 haul | - | more builders |
| Irrigation Channel | tile | 1St | - | - | carries water |
| Cleanser | 2x1 | 24W 36St 20G 10L | 2 | 2 | 1 blight tile/2d r5; planet +0.01; Village (96) |
| Water Wheel | 1x1, bank | 12W 8St | - | 0 | drives an adjacent Sawmill, Mason or Bakery: 1 worker fewer, runs at night |
| Glowcap Grove | 2x2, shade | 14W 10St 16P | 2 night | 0 | 3 food a night; x2 in a Dimming |
| Bell Tower* | 1x1 | 48W 72St 20G 20L 20P | - | - | Town gate |

### Town
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Rowhouse | 2x1 | 28W 12St 5G 10P | - | 0 | houses 10; needs well |
| Greenhouse | 2x1 | 35W 15St 10G 10L 10P | 3 | 1 | +2.5 food; Dimming-proof |
| Workshop | 2x1 | 50W 10G | 3 | 1 | 2 L -> 3 St |
| Lumen Pump | 1x1, vein | 24W 36St 15G 10P | 3 | 0 | +7 L; blight r4/3d |
| Tax Office | 1x1 | 16W 24St | 1 | 0 | +0.2 G per citizen/day; Spirit -5 |
| Well | 1x1, wet | 10W 15St 5S | - | 0 | drinking water r8 |
| Mason | 2x1 | 18W 27St 10P | 2 | 0 | 6 St -> 2 S, 2/worker/day |
| Refinery | 2x2 | 24W 36St 20G 15P | 2 | 0 | 6 L -> 1 C, 2/worker/day |
| Kitchen | 1x1 | 12W 18St 10P | 2 | 0 | 2 food (two types) -> 3 meals, 4/worker/day |
| Handcart Shed | 2x1 | 28W 12St 20P | - | 1 | haulers in region carry 15 |
| River Dock | 1x1, bank | 18W 14P 25G | 1 | 1 | two docks link by boat: 3x road speed downstream, 0.75x upstream |
| Levee | tile, bank | 6St 2S | - | 0 | holds back the spring flood; placed like road |
| Lumen Spire* | 2x2 | 100W 150St 80G 120L 40P 40S | - | 0 | City gate |

### City
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Apartment Block | 2x2 | 63W 27St 20G 30P 20S | - | 1 | houses 24; needs well |
| Lumen Reactor | 2x2, vein | 60W 90St 60G 30S | 4 | 0 | +10 L, Dimming hit x0.6 instead of x0.25; blight r6/2d |
| Purifier Tower | 1x1 | 40W 60St 40G 20L 20S | 2 | 3 | 1 tile/day r8, blocks blight r4; planet +0.03 |
| Grand Bazaar | 3x2 | 48W 72St 30G 30P | 4 | 1 | +1.5 G; counts as a food type |
| Park | 2x2 | 16W 24St 10G | - | 0 | Spirit coverage r5, blight-proof; planet +0.005 |
| Toolsmith | 2x1 | 32W 48St 30G 20S | 2 | 1 | 1 P + 1 C -> 1 T, 1.5/worker/day |
| Lumen Nexus* | 3x3 | 160W 240St 200G 300L 80S 40T 30C | - | 0 | Conflux gate; first grid node (r12) |
| Observatory | 2x2 | 48W 72St 80G 30S 10T | 1 | 1 | Dimming forecast two seasons ahead; Spirit coverage r8; 2 night workers make 1 starlight a night in a Dimming; with its night crew staffed, airship surveys fly 25% faster |

## 17. Buildings, Conflux to Ascendant (D45, D54)
Design intent: Conflux makes the settlement one connected machine (grid, rail, airships). Skyborne adds clean
land and clean Lumen in the sky, so you can stop leaning on the veins. Ascendant turns the whole game around:
heal the planet you spent 12 years draining, then face the Great Dimming.

### Conflux: Lumen grid, cargo rail, first airship dock
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Conduit Terraces | 3x2 | 98W 42St 40G 40P 40S 10T | - | 2 | houses 36; needs well; upgrades |
| Lumen Pylon | 1x1 | 21W 9St 10S 5T | - | 0 | grid node: feeds buildings in r8, links pylons within 12 |
| Grid Battery | 2x1 | 42W 18St 30G 20S 20C | - | 0 | holds 600 L for the grid, lossless, discharges in a Dimming |
| Rail Depot | 3x1 | 84W 36St 60G 30S 15T | 2 haul | 1 | cargo rail station, one per region, links via track |
| Airship Dock | 3x3 | 140W 60St 120G 40P 20T | 3 | 4 | freight between docked regions and islands; survey flight reveals a locked region's reward |
| Vein Bore | 2x2, vein | 80W 120St 80G 40S 20T | 4 | 0 | +16 L, Dimming x0.4; blight r5/1d; planet -0.05/day |
| Hydroponic Hall | 3x2 | 105W 45St 50G 30P 20T | 4 | 3 | +4 food, no soil, needs water; Dimming- and blight-proof |
| Water Tower | 1x1 | 32W 48St 20G 30S | - | 1 | drinking water r16, wets tiles r3 |
| Sky Foundry* | 3x3 | 240W 360St 400G 400L 120S 80T 60C | - | 0 | Skyborne gate; makes the first Lift Anchor free |

Rail track: tile, 1W + 1St + 1S. Pylons and the grid are an overlay (section 20).

### Skyborne: floating districts
Islands: a Lift Anchor raises a 16x12 sky island over an owned region (max 4 islands). Sky tiles are plain
"skystone": no soil, no veins, no forest, never blighted, no ground water. Each island needs 20 L/day through
the grid; short of it, the island goes still (all its buildings stop) but nothing falls. Islands are reached by
Sky Lifts and Airship Docks. The camera toggles ground/sky layer (Tab); islands are drawn semi-transparent over
the ground layer when viewing ground.

| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Lift Anchor | 3x3 (ground) | 160W 240St 300G 100S 60T 60C | 2 | 20 per island | raises one island |
| Sky Lift | 1x1 pair | 32W 48St 30G 20S 10T | - | 2 | walker/hauler link ground <-> island |
| Skyspire | 2x2 | 112W 48St 60G 40P 40S 20T | - | 2 | houses 40; island or ground; needs water |
| Cloud Cistern | 2x1, island | 24W 36St 20G 20S | - | 0 | drinking water r10 on its island, wets r3 |
| Sky Garden | 3x2, island | 84W 36St 40G 30P 10T | 3 | 1 | +3.5 food, own food type; needs wet |
| Aether Collector | 2x2, island | 60W 90St 60G 30S 10T | 3 | 0 | +10 L from the air; no blight, no planet drain; Dimming x0.5 |
| Skyforge | 2x2, island | 56W 84St 60G 40S | 3 | 2 | 1 P + 1 C -> 1 T at 3/worker/day |
| Dawn Beacon* | 2x2 | 320W 480St 800G 600L 150S 120T 100C | - | 0 | Ascendant gate; light need 0.5 -> 0.35 per citizen |

### Ascendant: planet healing and the finale
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Lumen Arcology | 3x3 | 210W 90St 120G 60S 40T 20C | - | 4 | houses 60; needs water; upgrades |
| Heartroot Tap | 2x2, vein | 80W 120St 100G 40S 30T | 3 | 0 | +12 L, no blight, no drain; works only at planet health >= 50% |
| Verdant Spring | 2x2 | 100W 150St 150G 50S 30C | 2 | 4 | 1 blighted tile/day in r10 -> fertile soil (fertility 100); planet +0.08 |
| Vein Mender | 1x1, vein | 60W 90St 100G 40C | 2 | 3 | extractors within r6 drain the planet half as much; planet +0.04 |
| Rewilding Grove | 2x2 | 40W 60St 60G 20P | 2 | 1 | spreads forest r8 (1 tile/day on grass/stump); planet +0.03 |
| Clearwater Works | 2x1, river | 64W 96St 80G 40S 20T | 2 | 2 | no fouling past its tile; planet +0.03 |
| Bloom Orchard | 3x3 | 84W 36St 40G 30P | 4 | 0 | +3 food, own food type; needs fertility >= 60; Dimming x0.75 |
| Hall of Seasons | 3x2 | 80W 120St 150G 60S | 2 | 2 | Spirit coverage r12; halves the darkness penalty in its range |
| Skyheart* | 4x4 | 4 stages, see section 18 | - | 0 | final landmark; starts the Great Dimming |

Count: Conflux 8 + landmark, Skyborne 8 + landmark, Ascendant 8 + Skyheart.

## 18. The Skyheart and the finale (D33)
- Built in 4 stages, each a separate construction (ONI-style megaproject):
  1. Foundation: 320W 480St 300S. 2. Lattice: 300P 200T. 3. Core: 400C 1000L. 4. Crown: 1500G 200T 200C.
- Finished: the Great Dimming is announced and starts one season later.
- Reservoir: the finished Skyheart holds up to 3000 L (grid-fed, lossless) and pours it into the grid and light
  during the Great Dimming. The season before is the last big stockpiling push.
- Campaign win: Great Dimming ends with population > 0 and planet health >= 50%. If health is below 50% at the
  end: no win, no loss; the game says so, play goes on into endless, and the win can't be retaken in this run (D52).
- Lose: population 0, any time.

## 19. Endless and milestones (D41)
- After the win: continue the same run. Dimming base +1 day per 2 years, no cap. Planet health keeps its rules
  (it drains unless cleaned).
- Endless start: a new map with no win check and no Great Dimming; the Dimming schedule follows eras, then
  grows +1 day per 2 years after Ascendant.
- Milestones on the pause screen (per run, also a lifetime list):
  1. First Dimming survived. 2. Village. 3. 100 citizens. 4. First tier III building. 5. City.
  6. Own 4 regions. 7. Conflux. 8. Cargo rail links 3 regions. 9. 300 citizens. 10. First island.
  11. Ascendant. 12. Planet health back above 80% after falling below 50%. 13. Skyheart finished.
  14. Great Dimming survived (win). 15. 600 citizens. Bonus: 10 Dimmings in a row with no darkness day.

## 20. Controls and UI
- Mouse: left place/select, right click (on release) cancel/deselect, wheel zoom (4 steps; walkers hidden at the
  farthest), right drag, middle drag or
  WASD to pan. Tab: ground/sky layer.
- Keys: space pause, 1/2/3 speed, B build menu, R road, C channel, X demolish, U upgrade selected, M region map.
- HUD (see `mockups/scene_village.png`): top bar with resources and deltas (refined goods in a fold-out),
  population/beds, Spirit, planet health with yearly trend; era + Dimming forecast panel; selected-building
  panel (tier, workers, buffers, priority); bottom build bar by category (Roads, Housing, Food, Resources, Lumen,
  Refining, Water, Logistics, Civic, Sky, Landmark).
- Overlays: blight, coverage (Shrine/Park/Hall), water (wet/dry/fouled), fertility, road connection, Lumen grid,
  regions (prices, rewards).
- Notifications: Dimming forecast, buffer full, no workers, island still, low planet health, milestone.

## 21. Save, data and engine (D6, D28)
- Autosave each season (3 rotating), plus 8 manual slots. Saves are versioned; on load, older saves pass through
  a chain of migration steps (one per save version) so they keep loading after updates.
- Save holds the full state: seed, tile states (terrain, blight, fertility, wet, forest), buildings with tier and
  buffers, citizens (position, home, job), stockpiles, clock, meters. Compressed.
- Buildings, goods, eras, terrain, upgrade tiers, the Dimming schedule and milestones are data (Godot `.tres`),
  not code. A new building or era = a data file plus art.
- Simulation runs separate from rendering on a fixed tick, testable headless (GUT or plain scripts), and can run
  other settlements off-screen later (v2 neighbours). Every settlement is a `Settlement` object.
- Production is always "inputs -> outputs per worker per day"; refining, upgrades and late buildings use the
  same system.
- Events go through one event bus with a log (v1.x events and v2 diplomacy plug in there).
- 600 walkers: drawn with batched sprites (MultiMesh or a custom draw), pathing on `AStarGrid2D` with cached
  home/job paths, re-planned only when roads change.

## 22. Resolved review points
All seven open points from the first draft were agreed as proposed: D48-D54.

## 23. Out of scope for v1
Combat, neighbours, trade (v2). Citizen age, skills and families (later, D29). Random events (v1.x). Map size
options, other biomes, Android, isometric art (later, see `roadmap.md`). Tech tree and science (never, D19).
