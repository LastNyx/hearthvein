class_name SaveGame
extends RefCounted
## Save files (design.md section 21, ticket 19). A save is one ZSTD-compressed Variant holding
## {"version": int, "state": Settlement.to_dict()}. No objects are written: defs are saved by id, everything else is
## plain data, so a save made by one build loads in another with the same data folder.
##
## Migrations between versions are 19b; until then a file with a version this build does not know is refused.

const CURRENT_VERSION := 1


## Writes `s` to `path`, compressed. Pending day/season hooks (Settlement._deferred) are run first, so a save never
## sits between a day change and the hooks of that day. Returns OK or the FileAccess error.
static func save(s: Settlement, path: String) -> Error:
	s.flush_deferred()
	var payload := {"version": CURRENT_VERSION, "state": s.to_dict()}
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


## Reads a save written by save(). Null (and a pushed error) when the file is missing, not compressed, not a save,
## from a newer version, or names data the registry does not have.
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
	if version < 1 or version > CURRENT_VERSION:
		push_error("SaveGame.load: %s has save version %d, this build reads 1..%d" % [path, version, CURRENT_VERSION])
		return null
	var state: Variant = (payload as Dictionary)["state"]
	if typeof(state) != TYPE_DICTIONARY:
		push_error("SaveGame.load: %s has a bad state section" % path)
		return null
	return Settlement.from_dict(state, registry)


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
