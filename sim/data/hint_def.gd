class_name HintDef
extends Resource
## One first-time hint card (ticket 84, D59b, D68, D70). Data only: HintCards knows how to show it.
## Trigger: the event `trigger` (an EventBus kind), optionally only when its data has `filter_key` equal to
## `filter_value` (compared as text). `check` adds a condition HintCards evaluates (see HintCards.passes):
##   ""               none
##   upkeep_building  the completed building has Lumen upkeep and upkeep is on (Town era on)
##   no_workers       a finished, unpaused building with worker slots has nobody working in it
##   homeless         at least one citizen has no bed
##   region_buy       an adjacent locked region costs no more than the treasury
## no_workers, homeless and region_buy have no event of their own: they are checked on day_started.

const HELP_PAGES: PackedStringArray = ["core_loop", "building_roads", "citizens_food", "haulers_storage", "spirit",
		"lumen_blight", "dimming", "eras_gates", "planet_health", "controls"]
const CHECKS: PackedStringArray = ["", "upkeep_building", "no_workers", "homeless", "region_buy"]

@export var id: String = ""
@export var order: int = 1
@export var trigger: String = ""
@export var filter_key: String = ""
@export var filter_value: String = ""
@export var check: String = ""
@export var title: String = ""
@export_multiline var body: String = ""
## Help page (ticket 85) the More button opens; one of HELP_PAGES.
@export var help_page: String = ""
