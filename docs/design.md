# Hearthvein design (v1)

Source of truth for decisions: `decisions.md` (D1-D26). This doc turns them into rules and numbers.
Every number here is a first guess, meant to be tuned in playtests; they live in data files, not code.

## 1. Pitch
Grow one settlement from a camp around the Hearth into a glowing City on a living planet. Lumen, the cyan
planet-energy in the veins under the ground, drives everything, but pumping it sickens the land around the
pumps. Every year the veins go quiet for a while (the Dimming), each time for longer. Reach the City era and
survive the Great Dimming to win.

Original techno-fantasy city builder, Godot 4 / GDScript, desktop Linux first, 45-60 minute run.

## 2. Core loop
1. Place buildings and roads (the player never handles individual citizens).
2. Citizens walk to free job slots, which are filled automatically by priority (food first).
3. Production fills stockpiles: food, materials, Lumen, gold.
4. Food surplus fills the growth bar; housing caps the population.
5. Gold + population + an era landmark unlock the next era and its buildings.
6. Stockpile Lumen and food before each forecast Dimming; manage blight from the pumps.

Tension: more Lumen means faster growth and more power, but more blight, which costs food and Spirit.
The Dimming punishes settlements that never stockpiled.

## 3. Time
- 1 day = 30 s at 1x speed. Speeds: pause, 1x, 2x, 3x.
- Season = 6 days, year = 4 seasons = 24 days = 12 min at 1x.
- Target run: Village ~10 min, Town ~25 min, City ~40 min, Great Dimming over by 50-60 min.

## 4. Map
- One seeded 64x48 square grid, 32x32 tiles, top-down 3/4 view (D12, D13, D23).
- Terrain: grass, fertile soil (farms x1.5), forest (woodcutters; regrows slowly), rock (quarries),
  water (fishing, blocks building), Lumen vein (taps, pumps and reactors must sit on one).
- Guaranteed: one river crossing the map, 3-5 veins within 12 tiles of the start, forest and rock within
  8 tiles. Outer 6 tiles on every edge: plain land only, kept free for v2 neighbours.

## 5. Citizens, housing and growth
- Start: Hearth (houses 8), 8 citizens, 60 food, 40 materials, 10 Lumen, 0 gold.
- Each citizen eats 1 food/day. Daily surplus goes into the growth bar.
- Growth bar size = 8 + pop / 3 food. Full bar and a free bed = one new citizen at the Hearth.
- Immigration: Spirit >= 70 and free beds = one newcomer every 3 days, on top of growth.
- Food stock at 0 with a deficit: one citizen leaves per day until food balances.
- Homeless (pop above beds, e.g. after a house is demolished): Spirit penalty, no growth.
- Housing: Hearth 8, Tent 2, Cottage 4, Rowhouse 10, Apartment Block 24.

## 6. Jobs and walking
- Each production building has worker slots. Free slots are filled from idle adults, highest priority first:
  food > Lumen > materials > gold > civic. The player can raise or lower one building's priority (3 levels)
  or pause it; never assigns a person.
- Workers walk home -> job. Output only counts while at work, so distance matters.
- Walking speed (tiles/s): grass 1.0, dirt road 1.5, paved road 2.0.
- A building with no road connection to the Hearth gets no workers and shows an icon (D22).
- Roads: dirt free, paved 1 material/tile (Town era).

## 7. Resources and storage
| Resource | From | Used for |
|---|---|---|
| Food | Forager, Farm, Fishing Dock, Greenhouse | eating, growth |
| Materials | Woodcutter, Quarry, Workshop | building, paved roads |
| Lumen | Lumen Tap, Lumen Pump, Lumen Reactor | Town/City upkeep, light during the Dimming, landmarks |
| Gold | Market, Tax Office, Grand Bazaar | era gates, Town/City buildings |

- Storage: Hearth 150 of each; each Storehouse +250 of each. Over the cap is wasted.
- Lumen during the Dimming: each citizen needs 0.5 Lumen/day for light and warmth. Short = "darkness":
  Spirit -20 target and no growth. This is why you stockpile.

## 8. Spirit (D18)
One meter, 0-100, starts at 60. Each day it moves 2 points towards a target:
- Base 50.
- +5 per food type eaten beyond the first (types: forage, fish, crops, greenhouse; max +15).
- +10 if most homes are inside Shrine/Park coverage.
- -15 hunger (any citizen unfed today).
- -up to 15 blight near homes (share of homes with blight within 2 tiles).
- -10 homeless. -20 darkness during the Dimming. -5 if a Tax Office exists.

Effects: >= 70 work +15%, growth +20%, immigration on. <= 30 work -20%, no immigration.
Below 20 for 5 days in a row: one citizen leaves every 2 days.

## 9. The Dimming (D16, D20)
- Once a year, starting on day 3 of autumn. Always forecast: shown one season ahead with its length.
- Length: year 1: 2 days, year 2: 3, year 3: 4, year 4+: 5 (cap until the Great Dimming).
- During a Dimming: Lumen output x0.25, crops (Farm, Forager) x0.5, Lumen upkeep buildings work at x0.5
  if Lumen runs out, citizens need light Lumen (section 7).
- The Great Dimming: announced the moment the City era is reached, starts 1 season later, lasts 8 days,
  output x0.15. If the Skyheart is finished it halves every Dimming penalty. Survive it with pop > 0 = win.
  Free play continues after.

## 10. Blight (D16)
- Every Lumen extractor has a blight radius and a period. Each period, the nearest non-blighted tile in the
  radius turns blighted.
  - Lumen Tap: radius 2, every 6 days. Lumen Pump: radius 4, every 3 days. Lumen Reactor: radius 6, every 2 days.
- Blighted tile: farm output on it x0.5, forest does not regrow, cannot hold a Park or Shrine,
  homes within 2 tiles lower Spirit.
- Removing the extractor stops the spread; existing blight stays.
- Cleanser: clears 1 blighted tile every 2 days within radius 5. Purifier Tower: 1 tile/day in radius 8 and
  blocks new blight inside radius 4. Park: blocks new blight inside its own footprint.
- Blight never ends the game (D20); it only makes things harder.

## 11. Eras (D19)
| Era | Gate to reach it | Landmark |
|---|---|---|
| Camp | start | Meeting Hall (gate to Village) |
| Village | pop 15, gold 30, Meeting Hall | Bell Tower (gate to Town) |
| Town | pop 40, gold 150, Bell Tower | Lumen Spire (gate to City) |
| City | pop 80, gold 400, Lumen Spire | Skyheart (final; softens the Great Dimming) |

Reaching an era unlocks its building set and its landmark.

## 12. Buildings (first guesses)
Cost = materials / gold / Lumen. Workers = slots. Upkeep is Lumen per day.

### Camp
| Building | Size | Cost | Workers | Effect |
|---|---|---|---|---|
| Hearth | 2x2 | start | - | town centre, houses 8, storage 150, spawns citizens |
| Tent | 1x1 | 5/0/0 | - | houses 2 |
| Forager | 1x1 | 10/0/0 | 2 | +1.5 food each; needs grass/forest within 3 tiles |
| Woodcutter | 1x1 | 10/0/0 | 2 | +1 materials each; needs forest within 4 tiles |
| Storehouse | 2x1 | 25/0/0 | - | +250 storage |
| Lumen Tap | 1x1, on vein | 20/0/0 | 2 | +4.5 Lumen each; blight r2 / 6 days |
| Meeting Hall* | 2x2 | 60/0/10 | - | Village gate |

### Village
| Building | Size | Cost | Workers | Effect |
|---|---|---|---|---|
| Cottage | 1x1 | 15/0/0 | - | houses 4 |
| Farm | 2x2 | 30/0/0 | 3 | +2 food each (x1.5 fertile, x0.5 per blighted share) |
| Fishing Dock | 1x1, shore | 20/0/0 | 2 | +1.5 food each, not hit by the Dimming |
| Quarry | 1x1, rock | 25/0/0 | 2 | +1.5 materials each |
| Market | 2x2 | 40/0/0 | 2 | +1 gold each; food variety needs a Market in reach of homes |
| Shrine | 1x1 | 30/0/5 | - | Spirit coverage radius 6 |
| Bell Tower* | 1x1 | 120/20/20 | - | Town gate |

### Town (Lumen upkeep starts here)
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Rowhouse | 2x1 | 40/5/0 | - | 0 | houses 10 |
| Greenhouse | 2x1 | 50/10/10 | 3 | 1 | +2.5 food each, ignores Dimming crop penalty |
| Workshop | 2x1 | 50/10/0 | 3 | 1 | turns 2 Lumen into 3 materials, per worker per day |
| Lumen Pump | 1x1, vein | 60/15/0 | 3 | 0 | +7 Lumen each; blight r4 / 3 days |
| Tax Office | 1x1 | 40/0/0 | 1 | 0 | +0.2 gold per citizen per day; Spirit -5 |
| Cleanser | 2x1 | 60/20/10 | 2 | 2 | clears 1 blight tile / 2 days, r5 |
| Lumen Spire* | 2x2 | 250/80/120 | - | 0 | City gate |

### City
| Building | Size | Cost | Workers | Upkeep | Effect |
|---|---|---|---|---|---|
| Apartment Block | 2x2 | 90/20/0 | - | 1 | houses 24 |
| Lumen Reactor | 2x2, vein | 150/60/0 | 4 | 0 | +10 Lumen each, Dimming hit only x0.6; blight r6 / 2 days |
| Purifier Tower | 1x1 | 100/40/20 | 2 | 3 | clears 1 tile/day r8, blocks new blight r4 |
| Grand Bazaar | 3x2 | 120/30/0 | 4 | 1 | +1.5 gold each, counts as an extra food type |
| Park | 2x2 | 40/10/0 | - | 0 | Spirit coverage r5, blight-proof footprint |
| Skyheart* | 3x3 | 400/200/300 | - | 0 | halves all Dimming penalties |

## 13. Controls and UI
- Mouse: left place/select, right cancel, wheel zoom (3 steps), middle drag or WASD to pan.
- Keys: space pause, 1/2/3 speed, B build menu, R road tool, X demolish (refunds 50%).
- HUD (see `mockups/scene_village.png`): top bar with resources and deltas, population/beds, Spirit bar;
  era + Dimming forecast panel; selected-building panel; bottom build bar by category
  (Roads, Housing, Food, Materials, Lumen, Civic, Landmark).
- Overlays: blight (violet), Shrine/Park coverage, road connection.

## 14. Win, lose, save
- Win: City era reached and the Great Dimming survived (pop > 0 when it ends). Free play continues.
- Lose: population 0.
- Save: one autosave per season plus manual save slots; the map is rebuilt from its seed plus a diff.

## 15. Built for expansion (v1 rules that make v2+ cheap)
- Buildings, resources, eras, terrain and the Dimming schedule are data (Godot `.tres` resources), not code.
  A new building or era should be a data file plus art, no new logic.
- Simulation runs separately from rendering on a fixed daily tick, so it can be tested headless and later run
  for other settlements (v2 neighbours) off-screen.
- Every settlement is an object (`Settlement`) even though v1 has one; neighbours in v2 reuse it.
- Production is "inputs -> outputs per worker per day", so production chains (planks, tools, refined Lumen)
  are new data, not a new system.
- Events go through one event bus with a log; v2 diplomacy and v1.x story events plug into it.
- Map edges stay free (section 4).

## 16. Out of scope for v1
Combat, neighbours, trade (v2). Production chains, map sizes, Android, isometric art (later, see
`roadmap.md`). Tech tree and science (never, D19).
