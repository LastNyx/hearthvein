# Hearthvein decision log

Simple 2D civilization-style strategy game, original, built in Godot.

## Round 1 (2026-11-13)

- D1. Project lives at `~/Proyek/hearthvein/` (renamed from civ-lite after D25); docs in `docs/`, mockups in `docs/mockups/`.
- D2. Target: desktop (Linux) for v1, mouse + keyboard. Keep UI simple enough for a later Android export.
- D3. Hex tiles (Godot TileMap hex layout).
- D4. One rule-based AI rival in v1 (expand, build army, attack nearest city).
- D5. Pixel art, 32x32 tiles, top-down tilted terrain, small character sprites for units.

## Round 2 (2026-11-13)

- D6. GDScript 2.0 on Godot 4 (latest stable), static typing.
- D7. One map size in v1, target game length 45-60 min (exact size pending genre decision).
- D8. Four resources including gold (exact list pending genre decision).

## Round 3 (2026-11-13)

- D9. Genre: city builder / colony sim (Frostpunk, Timberborn family), one settlement growing camp -> city
  through eras. No combat in v1. Ben mentions possible Spore-like conflict later (open question).
  - Supersedes D4 (AI rival dropped), the 4X win conditions and settler/warrior/archer units.
  - D3 (hex) reopened.
- D10. Theme: original techno-fantasy world (industrial + magic, glowing planet-energy, working name "Lumen").
  Core tension: pumping Lumen drives growth but sickens the surrounding land. No FF7 names, characters or art.

## Round 4 (2026-11-13)

- D11. Spore-style neighbours (befriend or fight) are v2, not v1; v1 map leaves edge room. Roadmap in `roadmap.md`.
- D12. Square grid (replaces D3).
- D13. Top-down 3/4 camera, not isometric.
- D14. Resources: food, materials (wood+stone merged), Lumen, gold.
- D15. Citizens are visible walkers; jobs filled automatically, no manual worker assignment. Player sees population grow.
  Confirmed round 5: walkers visible, free job slots auto-filled (Timberborn style), player manages
  population/housing/food, never individual citizens.

## Round 5 (2026-11-13)

Research notes: Timberborn (escalating forecast droughts, auto job fill by priority), Frostpunk (scripted
cold steps to a storm finale, revolt loss), Civ (food surplus growth bar capped by housing), Spore (v2).

- D16. Main threat: seasonal "Dimming" when Lumen veins go quiet (Lumen output falls, crops slow, Lumen
  buildings weaken). Each Dimming longer than the last, always forecast. Pumps spread blight on nearby tiles
  (cuts farm output). Game builds to a final, longest Dimming.
- D17. Growth: citizens eat food daily; surplus fills a growth bar; full bar = new citizen from the town centre.
  Housing is the hard cap; food deficit = people starve/leave.
- D18. One morale meter, Spirit: up from met needs (food variety, decoration/shrine, clean land), down from
  hunger, blight near homes, homelessness. High = faster work and growth; low for too long = people leave.
- D19. Progression: four eras Camp -> Village -> Town -> City, each gated by population + gold + an era
  landmark building; each era unlocks a building set. No tech tree, no science resource.

## Round 6 (2026-11-13)

- D20. Win: reach City era and survive the Great Dimming (final, longest); free play after. Lose: population 0.
  No land game-over; heavy blight just makes things harder.
- D21. Building list (names placeholder until spec):
  Camp: Hearth (town centre), Tent, Forager, Woodcutter, Storehouse, Lumen Tap; landmark Meeting Hall.
  Village: Cottage, Farm (2x2), Fishing Dock, Quarry, Market, Shrine; landmark Bell Tower.
  Town: Rowhouse, Greenhouse, Workshop, Lumen Pump, Tax Office, Cleanser; landmark Lumen Spire.
  City: Apartment Block, Lumen Reactor, Purifier Tower, Grand Bazaar, Park; landmark Skyheart (final).
- D22. Roads: building needs road connection to the town centre to get workers (icon when unconnected);
  roads speed walkers; dirt free, paved unlocks in Town era.
- D23. Map: one generated 64x48 tile map, seeded. Terrain: grass, fertile soil, forest, rock, water, Lumen veins.
  Guaranteed river and 3-5 Lumen veins near start; edges open for v2 neighbours.
- D24. Palette: warm earthy greens/browns, cyan-white Lumen glow, violet-grey blight; timber/stone early,
  iron/pipes/glowing conduits in Town/City.
- D26. Art direction: mockups v2 approved (lush 3/4 pixel art, layered shaded trees, steep gable roofs, cast
  shadows, soft terrain edges, fantasy touches: crystal-sail Lumen mill, Lumen lanterns, rune-stone shrine,
  glowing flora). Reference: Ben's screenshot of a lush top-down village (style only, nothing copied).
  Citizens are too big relative to buildings; scale them down (tune in-game, not blocking).
- D25. Title: Hearthvein ("Lumenfall" and "Veinlight" taken). Town centre named "Hearth" (avoid Hearthstone).

## Round 7 (2026-11-13) - game length and structure

Ben wants an Oxygen Not Included-like long game. Reverses D7's 45-60 min target.

- D27. Run shape: a campaign with a win after roughly 6-10 hours, plus an endless mode (after the win or as its
  own start) with growing Dimmings and harder late problems. Supersedes D7's run length; D20's win becomes the
  campaign win.
- D28. One run spans many sittings: autosave, several save slots, and saves that keep loading after updates
  (old saves converted). Built from v1.
- D29. Depth in v1: production chains (e.g. planks, tools, refined Lumen) and a changing environment (blight,
  water, soil fertility, forest regrowth), plus light logistics: goods are carried by haulers, no micromanagement.
  Citizen life (age, skills, families) is later. D15 holds: never assign individual citizens.
- D30. Planet health: a map-wide meter. Blight and tapped veins lower it; Cleanser, Purifier Tower and Park raise
  it. Low planet health makes Dimmings harsher, forests die back and veins thin out. It is the long-run pressure.
- D31. Progression: eras plus building upgrade tiers paid with refined goods. More than 5 eras is fine (count in
  round 8). Still no research tree (D19 holds).

## Round 8 (2026-11-13)

- D32. Seven eras: Camp, Village, Town, City, Conflux (Lumen grid, cargo rail, first airship dock), Skyborne
  (Lumen-lifted floating districts as new land), Ascendant (final; planet healing). Names placeholder. Skyheart
  moves to Ascendant as the final landmark. More eras later as content updates. Extends D19/D21.
- D33. Campaign win: reach Ascendant, finish the Skyheart, survive the Great Dimming with planet health >= 50%
  when it ends. Lose: population 0. Supersedes D20's win condition.
- D34. Map 128x96 split into regions: start in one ~32x24 region, buy neighbouring regions with gold; Skyborne
  floating districts add sky land. Edges still kept for v2 neighbours. Supersedes D23's 64x48.
- D35. Clock: 1 day = 60 s at 1x, season = 8 days, year = 32 min; an 8-hour campaign is about 15 years.
- D36. Upgrade tiers: base, II, III, in place (keeps spot and workers), paid with refined goods. Only housing,
  food, materials and Lumen buildings upgrade; landmarks and civic buildings don't.

## Round 9 (2026-11-13)

- D37. Dimming: one a year, forecast one season ahead. Base length by era (Camp 2 days, +1 per era, Ascendant 8),
  times planet health factor (x1.0 at 100%, x1.5 at 50%, x2.0 at 0%). Great Dimming: 16 days, starts one season
  after the Skyheart is finished. Supersedes the year-based schedule in design.md v0.
- D38. Base resources stay four (D14). Refined goods in v1, unlocked across eras: planks (Sawmill), cut stone
  (Mason), tools (Toolsmith: planks + refined Lumen), Lumen cells (Refinery: lossless Lumen storage), meals
  (Kitchen: two food types; counts as food variety). Upgrades and late buildings cost refined goods.
- D39. Hauling: Hauler is an auto-filled job. Producers drop goods at the door; haulers move them to the nearest
  storehouse with room and from storehouses to consumers. Player only places storehouses and roads. Handcarts in
  Town, cargo rail between regions in Conflux.
- D40. Regions: buy any region adjacent to an owned one; gold price rises (50, 100, 200, ... then flattens).
  Locked regions show dimmed terrain. Some hold a reward (rich vein, ruins with a one-time reward, fertile valley).
  No era locks.
- D41. Endless in v1: continue after the win (Dimmings +1 day per 2 years, no cap; planet health drains unless
  cleaned), an endless start (no win check, no Great Dimming), and ~15 milestones on the pause screen.

## Round 10 (2026-11-13)

- D42. Water: per-tile wet/dry map that spreads along channels (no fluid simulation). Farms near water or linked by
  irrigation produce more; Irrigated Farm (tier II) needs it. Wells give drinking water to housing above Town
  (missing = Spirit penalty). Blight upstream fouls the river downstream (less fishing, slower irrigated farms).
- D43. Lumen for light: during a Dimming each citizen needs 0.5 Lumen/day; short = Spirit drops hard, no growth.
- D44. v1 is the whole game (all seven eras, regions, Great Dimming, win, endless); no staged public releases,
  Ben builds it for himself for now. Build order still goes era by era with a play check after each
  (implementation order, not releases).
- D45. Conflux, Skyborne and Ascendant building lists (6-8 each plus landmarks) are drafted by Nyx in design.md for
  Ben's review, no grill round.
- D46. Population target ~600 citizens, all simulated and drawn as walkers; walkers hidden at far zoom; above 600
  growth slows through a softer housing cap.
- D47. Hearthvein lives in a private git repo (GitHub, Ben's account).

## Round 11 (2026-11-13) - design.md review, Ben agreed all seven open points

- D48. Construction: placing a building makes a site; haulers deliver its cost, builders (auto-filled job at the Hearth
  and Builder's Yard) build it. Upgrades build the same way while the building keeps running.
- D49. City's gate landmark is the Lumen Nexus (first Lumen grid node). Conflux gate: Sky Foundry. Skyborne gate:
  Dawn Beacon. Ascendant: Skyheart (D32).
- D50. Lumen is a hauled good until Conflux; the Lumen grid feeds buildings in pylon range directly.
- D51. The Great Dimming is a fixed 16 days, not scaled by planet health.
- D52. Planet health below 50% when the Great Dimming ends: no win in that run; play continues as endless.
- D53. Airship Dock: freight between docked regions and islands, plus surveys of locked regions. No trade (v2).
- D54. Conflux, Skyborne and Ascendant building lists as drafted in design.md section 17 (D45 closed); era gates
  from City on and Skyheart stage costs stay first guesses until play checks.
- D55. Tests run headless with GUT against the simulation; placeholder art is generated procedurally (like the
  mockups) until the art decision. Work is tracked as one feature `v1` in `.scratch/v1/` (Nyx decided).

## Round 12 (2026-11-17) - main menu, settings and onboarding

- D56. The game boots into a title screen: a freshly generated map pans slowly behind it (sim not running). Menu:
  Continue (latest save, hidden when there is none), New game, Load, Milestones, Settings, Quit.
- D57. New game panel: seed field (blank = random), Endless start toggle, Tutorial toggle (on by default for the
  first run, off after). No difficulty or map size options in v1.
- D58. Settings: fullscreen/windowed, UI scale (100/125/150%), hints on/off, reset tutorial, plus sound (D61). No key
  rebinding in v1.
- D59. Onboarding has three layers: (a) guided goals in the first session (one goal at a time, the matching build
  button highlighted, ticks off when the sim sees it done, game keeps running, skippable), covering Camp up to the
  first Dimming; (b) first-time hint cards afterwards (first Dimming forecast, full buffer, new era, first blight, ...);
  (c) an F1 help screen on the core loop, plus hover tooltips (description, inputs/outputs) on build buttons and
  buildings on the map.
- D60. Esc becomes a plain pause menu: Resume, Save, Load, Settings, Help, Main menu, Quit. New game and the Endless
  start toggle move to the title screen; Milestones is reachable from both.
- D61. v1 gets sound (Ben, 2026-11-17); scope settled in the next round.
- D62. Map pan moves from middle-drag to right-drag (Ben, 2026-11-17); right-click cancel is reconciled next round.
- D63. Right mouse: a drag of a few pixels or more pans, a plain click (on release) still cancels/deselects;
  middle-drag keeps panning too.
- D64. Sound v1 = effects (UI click, place, demolish, construction done, era reached, milestone, Dimming forecast) and
  ambience (day loop of wind/birds, a low hum during a Dimming) from CC0 packs (Kenney first), listed in a credits
  file. No music in v1.
- D65. Sound settings: master, effects and ambience volume; mute when the window is in the background.
- D66. Guided goals: 1 move the camera, 2 road from the Hearth, 3 two Tents, 4 Forager (haulers explained),
  5 Woodcutter, 6 Lumen Tap on a vein (blight overlay V, the trade-off), 7 Market (gold for the Village gate),
  8 reach 12 citizens (growth bar, beds, Spirit), 9 stock Lumen and food when the first Dimming is forecast,
  10 survive it; a closing card points at the Meeting Hall and the Village gate.
- D67. Tutorial on + blank seed = one fixed, checked seed (forest, vein and river near the Hearth).
- D68. Era intro cards: on reaching an era, one card (what's new, new pressure, next gate); pauses the game; part of
  the hints layer (hints off hides them).
- D69. Saves from before onboarding load with the tutorial done and hints on; seen hints live in user settings, not
  per save, so they don't repeat across runs.
- D70. First-time hints: a small card at the right edge, no pause, closes on click or after 20 s, "more" opens the
  matching F1 help page. Only era cards pause.
- D71. Tooltips: one-line description per building in its data file (Nyx writes all of them); cost, workers,
  inputs/outputs per day, upkeep and range come from existing data.
- D72. Title logo: "Hearthvein" in the existing pixel style with a cyan vein line, generated by the art script.
