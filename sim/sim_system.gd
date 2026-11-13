class_name SimSystem
extends RefCounted
## Base class for a simulation system (production, growth, blight ...). Override the hooks you need and
## register with Settlement.add_system(). Hooks run in registration order.

## Continuous-time hook for movement. `seconds` is game seconds at 1x (GameClock.REAL_SECONDS_PER_HOUR per hour).
## Runs before the on_hour hooks of the hour it belongs to.
func on_seconds(_settlement: Settlement, _seconds: float) -> void:
	pass


func on_hour(_settlement: Settlement) -> void:
	pass


func on_day(_settlement: Settlement) -> void:
	pass


func on_season(_settlement: Settlement) -> void:
	pass
