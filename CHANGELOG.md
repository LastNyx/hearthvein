# Changelog

All notable changes to Hearthvein. Newest first.

## Unreleased

### Added
- Wood and stone replace the single "materials" good. Woodcutters cut wood, Quarries and Workshops make stone, the
  Sawmill turns wood into planks and the Mason turns stone into cut stone. Costs name the real goods, and the top bar
  shows both. Old saves keep loading; their materials are split half wood, half stone.
- Clear tool (K): mark forest, stumps or rock and builders clear them for wood or stone.
- Plant tool (N): mark grass and Foresters plant there first.
- Hovering a stump says when it grows back, or why it won't.
- Panels say who does what: filled job places ("Haulers 1/2, Builders 3/4"), who lives in a house and what they do,
  and the people count in the top bar breaks down by job on hover.
- "Output full" says what to do: build a Storehouse nearby, or why haulers are short.

### Changed
- A finished building's priority goes back to Normal; the buttons say Build priority on a site and Work priority on
  a finished building. Houses and other buildings without jobs have no priority buttons.
- Balance: Woodcutters cut more, buildings take less work, door buffers hold twice as much and more people haul.
- Builders stay at their site until it is finished instead of walking back to the yard every evening; they rest
  in front of it at night, where you can see them, and work 06:00-20:00.

### Fixed
- A finished building did not start working until something else was placed or demolished.

## 1.1.4 - 2026-11-19

### Added
- Upgrade is a tool like Demolish: switch it on (U) and click buildings to upgrade them one after another; hovering
  shows the cost or why a building cannot be upgraded.
- The irrigation channel explains itself: it wets the ground next to it while connected to water, farms with at
  least half their tiles wet grow 25% more, and higher farm tiers need wet ground. Tiles it would wet are tinted
  while you place it.
- A construction site says why it is waiting: the materials still missing, its place in line for builders, or that
  no Builder's Yard can reach it.

### Changed
- The active tool is lit (Demolish, Upgrade, the building or road being placed).
- The Cleanser unlocks at Village, so early blight can be cleaned; the Lumen Tap's description warns that it
  spreads blight.
- Construction sites get their materials by priority, then oldest first; paused sites wait.
- The Ground/Sky button and the Tab key only appear once you have a sky island.

## 1.1.3 - 2026-11-19

### Added
- Updates from inside the game: the title screen shows "Update x.y.z available" when a new release is out, with
  its notes. Windows downloads and runs the installer; the Linux AppImage replaces itself and restarts. Checked at
  most once a day; turn it off in Settings.

### Fixed
- The pixel fonts were missing from the downloadable builds, which showed a plain default font instead.

## 1.1.2 - 2026-11-19

### Added
- Tools tab in the bottom-left corner: pause and 1x / 2x / 3x speed (the current speed is always shown, even when
  the tab is collapsed), Demolish, Upgrade, Region map and Help.
- Bridges. Drag a road across the river to build a bridge (5 Materials per water tile); pave it for a stone
  bridge. Track can cross water too, at three times the track cost.
- Moving water and chimney smoke: rivers and lakes shimmer, and chimneys puff smoke while the building is
  working.
- What's new on the title screen: this list in the game, opened once by itself after an update. The
  version number shows in the corner of the title screen.

### Changed
- Faster early game: producers make more, construction is quicker, the growth bar fills sooner and immigrants
  arrive from Spirit 50.
- Markets pay 1.5 gold per worker a day (was 4), so gold matters again at the Town and City gates.
- Immigration starts at Spirit 40 (was 50) and brings a newcomer every day (was every two days), so a busy
  City keeps growing.
- Smoother play in big settlements: a 600-citizen town now costs about a fifth of the frame time it did, the work
  at the end of each in-game hour is spread over several frames, and the autosave at each season start is written
  in the background.

### Fixed
- Hauling no longer starves: a fifth of the citizens always haul, so food and goods leave full doors.
- Builders live at their builders' yard and take the nearest site; a site no yard can reach in a work day says
  "too far from a builders' yard".
- There was no way to cross the river, so half the map was out of reach on foot.

## 1.1.1 - 2026-11-18

First public release. Same game as 1.1.0, merged into the main line and repackaged.

## 1.1.0 - 2026-11-17

### Added
- Title screen with Continue, New game, Load, Milestones, Settings and Quit.
- New game panel: seed, endless start and a guided tutorial on a fixed starting map.
- Settings: volumes, UI scale, controls.
- Hint cards for common problems and an era card when a new era begins.
- F1 help screen with ten pages on the core loop, building, the Dimming and the controls.
- Tooltips on build buttons and on the map.
- Pause menu (Esc).
- Right-drag to pan the map.
- Sound effects and ambience (CC0).

## 1.0.0 - 2026-11-17

First packaged build: the full campaign from Camp to Ascendant.

- Seven eras: Camp, Village, Town, City, Conflux, Skyborne, Ascendant.
- Lumen, blight and planet health; a yearly Dimming that grows longer on a sick planet.
- Water, channels, soil and forest; hauling and storehouses; building upgrade tiers; Spirit.
- Lumen grid and batteries, rail, airship docks and surveys, sky islands and lifts.
- The Skyheart and the Great Dimming finale, endless mode, milestones, save slots and autosave.
- Windows installer and Linux AppImage / tar.gz.
