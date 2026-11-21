class_name SaveGame
extends RefCounted
## Save files (design.md section 21, tickets 19 and 19b). A save is one ZSTD-compressed Variant holding
## {"version": int, "state": Settlement.to_dict()}. No objects are written: defs are saved by id, everything else is
## plain data, so a save made by one build loads in another with the same data folder.
##
## A file older than CURRENT_VERSION is upgraded by MIGRATIONS, one step per version and in order (see
## migrate_chain). A file from a newer build, or one that fails _validate, is refused: load returns null.

const CURRENT_VERSION := 6

## Migration steps: source version -> Callable(state: Dictionary) -> Dictionary of the next version.
## The chain is run by version number, so the dictionary order does not matter. To add a version: write the step,
## register it under CURRENT_VERSION, and bump CURRENT_VERSION, e.g. when going to 2:
##     const CURRENT_VERSION := 2
##     static var MIGRATIONS := {0: migrate_v0_to_v1, 1: migrate_v1_to_v2}  (now at 3, see below)
static var MIGRATIONS: Dictionary = {
	0: migrate_v0_to_v1,
	1: migrate_v1_to_v2,
	2: migrate_v2_to_v3,
	3: migrate_v3_to_v4,
	4: migrate_v4_to_v5,
	5: migrate_v5_to_v6,
}

## Keys Settlement.from_dict reads from a state dictionary.
const REQUIRED_STATE_KEYS: Array[String] = [
	"map", "occupancy", "roads", "channels", "buildings", "citizens", "hearth", "gold",
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
##
## Atomic (ticket 19c): the save is written to `path + ".tmp"` and renamed over `path` only when the write returned
## OK, so a crash or a full disk mid-write cannot destroy the previous save. Returns OK or the FileAccess error.
static func save(s: Settlement, path: String) -> Error:
	s.flush_deferred()
	return write_payload({"version": CURRENT_VERSION, "state": s.to_dict()}, path)


## The file half of save(): check (debug builds), compress and write `payload` atomically. Plain data in, so the autosave
## runs it on a thread (SaveSlots, ticket 89b); push_error and the file calls are safe off the main thread.
static func write_payload(payload: Dictionary, path: String) -> Error:
	if OS.is_debug_build():
		_check_plain(payload, "save")
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		var err := FileAccess.get_open_error()
		DirAccess.remove_absolute(tmp)  # a stale file from an earlier crash must not linger
		push_error("SaveGame.save: cannot write %s (error %d)" % [tmp, err])
		return err
	f.store_var(payload, false)
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		push_error("SaveGame.save: write to %s failed (error %d)" % [tmp, err])
		return err
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp)
		push_error("SaveGame.save: cannot move %s over %s (error %d)" % [tmp, path, rename_err])
		return rename_err
	return OK


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


## v1 -> v2: the irrigation channel grid (ticket 21) joined the settlement state. An older save has no channels.
static func migrate_v1_to_v2(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame migration 1 -> 2: state is not a dictionary")
		return null
	var d: Dictionary = state
	if not d.has("channels"):
		var ch := PackedByteArray()
		ch.resize(MapState.WIDTH * MapState.HEIGHT)
		d["channels"] = ch
	return d


## v2 -> v3: the tutorial (ticket 82) joined the settlement state. A save from before it loads with the tutorial
## finished (D69): the player has already learned the game.
static func migrate_v2_to_v3(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame migration 2 -> 3: state is not a dictionary")
		return null
	var d: Dictionary = state
	var systems: Dictionary = d.get("systems", {})
	if not systems.has("tutorial"):
		systems["tutorial"] = {"active": false, "finished": true, "index": 0, "done": [], "camera_moved": false,
				"ended_seen": false}
	d["systems"] = systems
	return d


## v3 -> v4 (ticket 99): the raw good "materials" became wood and stone. Every amount of it anywhere in the state
## (storage, door, input, site and upgrade buffers, trips in flight, reservations, totals, daily marks) becomes half
## wood, half stone, wood taking the odd unit. A trip carries one good, so a trip in flight becomes wood. Site needs
## are not saved: they are recomputed from the def (Settlement.from_dict resets a site buffer's cap).
static func migrate_v3_to_v4(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame migration 3 -> 4: state is not a dictionary")
		return null
	_split_materials(state)
	return state


## v4 -> v5 (ticket 109): the resource ledger joined the systems. A save from before it has no "ledger" section and
## loads with an empty ledger (no counters, no history): there is nothing to convert.
static func migrate_v4_to_v5(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame migration 4 -> 5: state is not a dictionary")
		return null
	return state


## v5 -> v6 (ticket 132): citizens learned their shift (day or night). Before the night shift, everyone worked days, so
## every citizen that has no shift saved works the day shift.
static func migrate_v5_to_v6(state: Variant) -> Variant:
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame migration 5 -> 6: state is not a dictionary")
		return null
	var d: Dictionary = state
	for pair in d.get("citizens", []):
		if typeof(pair) == TYPE_ARRAY and (pair as Array).size() == 2 and typeof(pair[1]) == TYPE_DICTIONARY:
			var c: Dictionary = pair[1]
			if not c.has("shift"):
				c["shift"] = Citizen.SHIFT_DAY
	return d


## Walks `v` in place. A Dictionary key "materials" splits into "wood" and "stone"; in an Array the string
## "materials" and a [good, amount] pair of it are replaced by one entry each for wood and stone.
static func _split_materials(v: Variant) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.has("planned") and str(d.get("good", "")) == "materials":
			d["good"] = "wood"
		var m: Variant = d.get("materials")
		if (typeof(m) == TYPE_FLOAT or typeof(m) == TYPE_INT) and d.has("materials"):
			d.erase("materials")
			var amount := float(m)
			var stone := floorf(amount / 2.0)
			d["wood"] = float(d.get("wood", 0.0)) + amount - stone
			d["stone"] = float(d.get("stone", 0.0)) + stone
		for k in d.keys():
			_split_materials(d[k])
	elif typeof(v) == TYPE_ARRAY:
		var a: Array = v
		var i := 0
		while i < a.size():
			var e: Variant = a[i]
			if typeof(e) == TYPE_STRING and e == "materials":
				a[i] = "wood"
				a.insert(i + 1, "stone")
				i += 1
			elif typeof(e) == TYPE_ARRAY and (e as Array).size() == 2 and typeof(e[0]) == TYPE_STRING \
					and e[0] == "materials" and (typeof(e[1]) == TYPE_FLOAT or typeof(e[1]) == TYPE_INT):
				var amount := float(e[1])
				var stone := floorf(amount / 2.0)
				a[i] = ["wood", amount - stone]
				a.insert(i + 1, ["stone", stone])
				i += 1
			else:
				_split_materials(e)
			i += 1


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
	if not _packed_size(state["channels"], TYPE_PACKED_BYTE_ARRAY, cells):
		push_error("SaveGame.load: channels is not a PackedByteArray of %d cells" % cells)
		return false
	if state.has("sky_map"):  # absent in a save from before the sky layer (ticket 40): no islands
		for key in ["sky_occupancy", "sky_roads", "sky_map"]:
			if not state.has(key):
				push_error("SaveGame.load: state is missing '%s'" % key)
				return false
		if not _packed_size(state["sky_occupancy"], TYPE_PACKED_INT32_ARRAY, cells) \
				or not _packed_size(state["sky_roads"], TYPE_PACKED_BYTE_ARRAY, cells):
			push_error("SaveGame.load: sky grids are not tile-sized packed arrays")
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
