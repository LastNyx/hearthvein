class_name MilestoneDef
extends Resource
## One milestone (design.md section 19). Data only: MilestoneSystem knows how to check each `kind`.
## Kinds and their parameters:
##   dimming_survived       a regular Dimming ended with population > 0
##   dimming_streak_no_dark `amount` regular Dimmings in a row with no darkness day
##   population             `amount` citizens
##   era                    `text` = era id reached (or a later one)
##   tier3                  any finished building at tier III
##   regions_owned          `amount` owned regions
##   rail_regions           `amount` regions joined by one cargo rail network
##   first_island           a sky island exists
##   planet_recovered       planet health above `amount` after having fallen below `dip`
##   skyheart_finished      the Skyheart is finished
##   great_dimming_won      the campaign is won

const KINDS: PackedStringArray = ["dimming_survived", "dimming_streak_no_dark", "population", "era", "tier3",
		"regions_owned", "rail_regions", "first_island", "planet_recovered", "skyheart_finished", "great_dimming_won"]

@export var id: String = ""
@export var display_name: String = ""
## 1-based position in the pause screen list; the bonus comes last.
@export var order: int = 1
@export var kind: String = ""
@export var amount: float = 0.0
@export var dip: float = 0.0
@export var text: String = ""
