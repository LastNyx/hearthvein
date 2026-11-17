class_name SimSystem
extends RefCounted
## Base class for a simulation system (production, growth, blight ...). Override the hooks you need and
## register with Settlement.add_system(). Hooks run in registration order.

## Stable key a system's save_state() is stored under (ticket 19). A system that keeps state declares
## `const SAVE_KEY := "walker"` in its own script; one without the constant keeps no state and is not written to a
## save. (GDScript forbids redeclaring a parent constant, so this is a convention read from the runtime script rather
## than a base-class constant.) Keys are never derived from the class name, so renaming a class cannot break a save.
static func save_key_of(sys: SimSystem) -> String:
	var script := sys.get_script() as GDScript
	if script == null:
		return ""
	var constants := script.get_script_constant_map()
	return str(constants["SAVE_KEY"]) if constants.has("SAVE_KEY") else ""

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
