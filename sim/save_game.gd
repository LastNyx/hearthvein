class_name SaveGame
extends RefCounted
## Save files (design.md section 21, tickets 19 and 19b). A save is one ZSTD-compressed Variant holding
## {"version": int, "state": Settlement.to_dict()}. No objects are written: defs are saved by id, everything else is
## plain data, so a save made by one build loads in another with the same data folder.
##
## A file older than CURRENT_VERSION is upgraded by MIGRATIONS, one step per version and in order (see
## migrate_chain). A file from a newer build, or one that fails _validate, is refused: load returns null.

const CURRENT_VERSION := 1

## Migration steps: source version -> Callable(state: Dictionary) -> Dictionary of the next version.
## The chain is run by version number, so the dictionary order does not matter. To add a version: write the step,
## register it under CURRENT_VERSION, and bump CURRENT_VERSION, e.g. when going to 2:
##     const CURRENT_VERSION := 2
##     static var MIGRATIONS := {0: migrate_v0_to_v1, 1: migrate_v1_to_v2}
static var MIGRATIONS: Dictionary = {
	0: migrate_v0_to_v1,
}

## Keys Settlement.from_dict reads from a state dictionary.
const REQUIRED_STATE_KEYS: Array[String] = [
	"map", "occupancy", "roads", "buildings", "citizens", "hearth", "gold",
	"next_building_id", "next_citizen_id", "grid_version", "structure_version",
	"forest_gain_version", "terrain_dirty", "hour_acc", "clock", "events",
	"era_current", "era_override", "planet_health_override", "spirit_override", "systems",
]

## Keys MapState.from_dict reads from the "map" dictionary.
const REQUIRED_MAP_KEYS: Array[String] = [
	"seed_used", "terrain_ids", "terrain", "region", "blight", "fertility", "wet", "fouled",
	"river_flow", "region_owned", "region_reward", "region_reward_pos", "start_region",
	"hearth_spot", "river_path", "river_width",
]

## Tile-sized map arrays and the packed type each one must be.
const SIZED_MAP_ARRAYS := {
	"terrain": TYPE_PACKED_BYTE_ARRAY,
	"region": TYPE_PACKED_BYTE_ARRAY,
	"blight": TYPE_PACKED_BYTE_ARRAY,
	"fertility": TYPE_PACKED_BYTE_ARRAY,
	"wet": TYPE_PACKED_BYTE_ARRAY,
	"fouled": TYPE_PACKED_BYTE_ARRAY,
	"river_flow": TYPE_PACKED_BYTE_ARRAY,
}


## Writes `s` to `path`, compressed. Pending day/season hooks (Settlement._deferred) are run first, so a save never
## sits between a day change and the hooks of that day. In a debug build the payload is walked and an error is pushed
## for any object or Callable in it: store_var() would silently write an object as an id instead of failing.
## Returns OK or the FileAccess error.
static func save(s: Settlement, path: String) -> Error:
	s.flush_deferred()
	var payload := {"version": CURRENT_VERSION, "state": s.to_dict()}
	if OS.is_debug_build():
		_check_plain(payload, "save")
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("SaveGame.save: cannot write %s (error %d)" % [path, err])
		return err
	f.store_var(payload, false)
	var err := f.get_error()
	f.close()
	if err != OK:
		push_error("SaveGame.save: write to %s failed (error %d)" % [path, err])
	return err


## Reads a save written by save(), migrating older files up to CURRENT_VERSION. Null (and a pushed error) when the
## file is missing, not compressed, not a save, from a newer version, has a broken state section, or names data the
## registry does not have.
static func load(path: String, registry: DataRegistry) -> Settlement:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("SaveGame.load: cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var payload: Variant = f.get_var(false)
	var read_err := f.get_error()
	f.close()
	if read_err != OK:
		push_error("SaveGame.load: %s is not a readable save (error %d)" % [path, read_err])
		return null
	if typeof(payload) != TYPE_DICTIONARY or not (payload as Dictionary).has("version") \
			or not (payload as Dictionary).has("state"):
		push_error("SaveGame.load: %s is not a save file" % path)
		return null
	var version := int((payload as Dictionary)["version"])
	if version < 0 or version > CURRENT_VERSION:
		push_error("SaveGame.load: %s has save version %d, this build reads 0..%d" % [path, version, CURRENT_VERSION])
		return null
	var state: Variant = (payload as Dictionary)["state"]
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame.load: %s has a bad state section" % path)
		return null
	state = migrate_chain(version, state, MIGRATIONS, CURRENT_VERSION)
	if state == null:
		return null
	if not _validate(state, registry):
		return null
	return Settlement.from_dict(state, registry)


## Runs the migration steps from `from_version` up to `target_version`, one per version and in order. Each step gets
## the dictionary the previous one returned. Returns the migrated Dictionary, or null (with a pushed error) when a
## step is missing or does not return a dictionary. Public so tests can inject a fake chain; load() passes MIGRATIONS.
static func migrate_chain(from_version: int, state: Dictionary, migrations: Dictionary,
		target_version: int) -> Variant:
	var version := from_version
	while version < target_version:
		var step: Variant = migrations.get(version)
		if not (step is Callable) or not (step as Callable).is_valid():
			push_error("SaveGame.load: no migration from save version %d" % version)
			return null
		var next: Variant = (step as Callable).call(state)
		if typeof(next) != TYPE_DICTIONARY:
			push_error("SaveGame.load: migration %d -> %d did not return a dictionary"
					% [version, version + 1])
			return null
		state = next
		version += 1
	return state


# ---------------------------------------------------------------- migrations

## v0 -> v1: gold was stored as "coins", and the Spirit system kept no saved state yet (its -1 sentinel means
## "not read yet", so a missing section resolves to SpiritDef.start exactly like a v1 save of a fresh game).
static func migrate_v0_to_v1(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame migration 0 -> 1: state is not a dictionary")
		return null
	var d: Dictionary = state
	if not d.has("gold"):
		d["gold"] = float(d.get("coins", 0.0))
	if d.has("coins"):
		d.erase("coins")
	var systems: Dictionary = d.get("systems", {})
	if not systems.has("spirit"):
		systems["spirit"] = {"value": -1.0, "low_days": 0, "days_since_leave": 0}
	d["systems"] = systems
	return d


# ---------------------------------------------------------------- validation

## True when `state` has the shape Settlement.from_dict needs: every required key, tile-sized packed arrays, the
## right section types, and only building defs the registry knows. Pushes one error naming the first problem.
static func _validate(state: Dictionary, registry: DataRegistry) -> bool:
	var cells := MapState.WIDTH * MapState.HEIGHT
	for key in REQUIRED_STATE_KEYS:
		if not state.has(key):
			push_error("SaveGame.load: state is missing '%s'" % key)
			return false
	if typeof(state["map"]) != TYPE_DICTIONARY:
		push_error("SaveGame.load: state map is not a dictionary")
		return false
	var map: Dictionary = state["map"]
	for key in REQUIRED_MAP_KEYS:
		if not map.has(key):
			push_error("SaveGame.load: map is missing '%s'" % key)
			return false
	for key in SIZED_MAP_ARRAYS:
		if not _packed_size(map[key], int(SIZED_MAP_ARRAYS[key]), cells):
			push_error("SaveGame.load: map.%s is not a packed array of %d cells" % [key, cells])
			return false
	if not _packed_size(state["occupancy"], TYPE_PACKED_INT32_ARRAY, cells):
		push_error("SaveGame.load: occupancy is not a PackedInt32Array of %d cells" % cells)
		return false
	if not _packed_size(state["roads"], TYPE_PACKED_BYTE_ARRAY, cells):
		push_error("SaveGame.load: roads is not a PackedByteArray of %d cells" % cells)
		return false
	for key in ["clock", "events", "systems"]:
		if typeof(state[key]) != TYPE_DICTIONARY:
			push_error("SaveGame.load: state.%s is not a dictionary" % key)
			return false
	for key in ["buildings", "citizens", "terrain_dirty"]:
		if typeof(state[key]) != TYPE_ARRAY:
			push_error("SaveGame.load: state.%s is not an array" % key)
			return false
	if not _validate_entries(state["buildings"], "building", true, registry):
		return false
	if not _validate_entries(state["citizens"], "citizen", false, registry):
		return false
	return true


## Every entry of a [id, dictionary] list has that shape and, when `needs_def`, names a registered building def.
static func _validate_entries(entries: Array, what: String, needs_def: bool, registry: DataRegistry) -> bool:
	for pair in entries:
		if typeof(pair) != TYPE_ARRAY or (pair as Array).size() != 2 \
				or typeof(pair[1]) != TYPE_DICTIONARY:
			push_error("SaveGame.load: a %s entry is malformed" % what)
			return false
		if needs_def:
			var d: Dictionary = pair[1]
			var def_id := str(d.get("def", ""))
			if not d.has("def") or registry.get_building(def_id) == null:
				push_error("SaveGame.load: unknown building def '%s'" % def_id)
				return false
	return true


static func _packed_size(v: Variant, type: int, cells: int) -> bool:
	if typeof(v) != type:
		return false
	return v.size() == cells


## Debug-only save check: an Object or Callable anywhere in the payload would be written by store_var() as a bare id
## and come back wrong (or not at all), so say so loudly instead of writing a save that cannot round trip.
static func _check_plain(v: Variant, path: String) -> void:
	match typeof(v):
		TYPE_OBJECT, TYPE_CALLABLE:
			push_error("SaveGame.save: %s holds a %s, which does not belong in a save"
					% [path, type_string(typeof(v))])
		TYPE_DICTIONARY:
			for key in v:
				_check_plain(v[key], "%s[%s]" % [path, key])
		TYPE_ARRAY:
			for i in (v as Array).size():
				_check_plain((v as Array)[i], "%s[%d]" % [path, i])


## Dictionary -> [key, value] pairs. System state keeps dictionaries as pair lists so insertion order survives a
## round trip (sim loops iterate dictionaries and order is part of determinism).
static func pairs(d: Dictionary) -> Array:
	var out := []
	for k in d:
		out.append([k, d[k]])
	return out


static func unpairs(p: Array) -> Dictionary:
	var out := {}
	for pair in p:
		out[pair[0]] = pair[1]
	return out
