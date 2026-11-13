class_name EraSystem
extends SimSystem
## Era progression (design.md section 15, D19, D32). Every hour, if the gate of the next era is met
## (Settlement.era_gate(): pop >= gate_pop, gold >= gate_gold, finished gate landmark), the settlement advances one
## era, at most one per hour. Numbers come only from the EraDef rows. The gold is only checked, never spent
## (it stays in the treasury; a gate is a threshold like population). Emits era_changed {from, to}.
## Unlocked buildings are derived: Settlement.is_unlocked / unlocked_buildings.


func on_hour(s: Settlement) -> void:
	var g := s.era_gate()
	if g["next"] == "" or not g["met"]:
		return
	var from := s.era_current
	s.era_current = g["next"]
	s.events.emit("era_changed", {"from": from, "to": s.era_current})
