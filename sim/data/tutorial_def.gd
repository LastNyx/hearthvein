class_name TutorialDef
extends Resource
## One guided goal (D66, ticket 82). Data only: TutorialSystem knows how to check each `kind`. Goals are checked in
## `order`, one at a time. Kinds and their parameters:
##   camera_moved     the UI reported a camera move (Settlement.report_camera_moved)
##   road_to_hearth   a road joined to the Hearth beyond the starting tile
##   built            `amount` finished buildings of `def_id`
##   built_connected  `amount` finished buildings of `def_id` that a road joins to the Hearth
##   population       `amount` citizens
##   dimming_stock    a Dimming is forecast and the Lumen and food in store cover every citizen for its whole length
##   dimming_ended    a Dimming has ended

const KINDS: PackedStringArray = ["camera_moved", "road_to_hearth", "built", "built_connected", "population",
		"dimming_stock", "dimming_ended"]

@export var id: String = ""
## 1-based position in the goal list.
@export var order: int = 1
## Two or three short plain lines: what to do and why.
@export_multiline var text: String = ""
@export var kind: String = ""
@export var def_id: String = ""
@export var amount: int = 0
## What the UI pulses: a build def id ("tent") or an overlay key ("blight"). "" = nothing.
@export var highlight: String = ""
## Hint card ids (ticket 84) this goal already teaches, so the card is not shown on top of it.
@export var covers_hints: Array[String] = []
