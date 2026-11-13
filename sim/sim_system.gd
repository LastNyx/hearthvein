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


## Runtime state this system keeps between hooks, as plain data (arrays, dictionaries, numbers; no objects).
## Empty by default. A system that keeps state (walkers, trips, accumulators, counters) must override this so a save
## in the middle of a run resumes exactly where it was. Pure caches (path grids, lookup tables) are left out and
## rebuilt on load.
func save_state() -> Dictionary:
	return {}


## Restore state written by save_state(). Empty dict = nothing to restore. Override together with save_state().
func load_state(_d: Dictionary, _settlement: Settlement) -> void:
	pass
