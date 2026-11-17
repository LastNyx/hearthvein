class_name EraDef
extends Resource
## One era row (design.md section 15). What an era unlocks is derived: every BuildingDef whose `era` is this id.

@export var id: String = ""
@export var display_name: String = ""
## 1-based position in the era sequence.
@export var order: int = 1
## Gate to reach this era. Camp has pop 0, gold 0 and no landmark.
@export var gate_pop: int = 0
@export var gate_gold: int = 0
## Building id of the landmark that must be built to reach this era ("" for Camp).
@export var gate_landmark: String = ""
## Base length in days of the Dimming in this era.
@export var dimming_base_days: int = 2
## One plain line for the era card: what gets harder from this era on (design.md sections 14-17).
@export var new_pressure: String = ""
