class_name SaveSlots
extends RefCounted
## Autosave rotation and manual save slots over SaveGame (design.md section 21, ticket 19c).
##
## A save dir holds `slot_<i>.dat` + `slot_<i>.meta` for the 8 manual slots and `auto_<i>.dat` + `auto_<i>.meta`
## for the 3 rotating autosaves. The small JSON sidecar carries era, clock label, population and saved-at, so list()
## describes every slot without decompressing whole saves.
##
## Autosave: attach(settlement) subscribes to the bus' season_started event. Each season start writes the next
## autosave: a free rotation index first, then the oldest slot by saved-at (with a stored sequence number as tie
## breaker, so several seasons stepped in one second still rotate in order). detach() unsubscribes (19d swaps
## settlements).
##
## SaveGame.save flushes the season hooks still queued when the event fires (ticket 57c spreads them over frames), so
## the snapshot is taken after that season's on_season hooks; the flush re-enters the deferred loop with the event
## itself already consumed, so it does not recurse.

const MANUAL_SLOTS := 8
const AUTO_SLOTS := 3
const SAVE_SUFFIX := ".dat"
const META_SUFFIX := ".meta"

var save_dir: String
var _settlement: Settlement = null
var _season_cb: Callable = Callable()


func _init(dir: String = "user://saves") -> void:
	save_dir = dir
	DirAccess.make_dir_recursive_absolute(save_dir)


# ---------------------------------------------------------------- autosave

## Subscribes to the settlement's season starts. Attaching twice moves the subscription to the new settlement.
func attach(settlement: Settlement) -> void:
	detach()
	_settlement = settlement
	_season_cb = _on_season_started
	settlement.events.subscribe("season_started", _season_cb)


func detach() -> void:
	if _settlement != null and _season_cb.is_valid():
		_settlement.events.unsubscribe("season_started", _season_cb)
	_settlement = null
	_season_cb = Callable()


func _on_season_started(_entry: Dictionary) -> void:
	if _settlement == null:
		return
	autosave(_settlement)


## Writes the next autosave now (the season event calls this; tests call it directly too). Returns the error.
func autosave(s: Settlement) -> Error:
	var pick := _pick_auto_slot()
	var path := _auto_path(int(pick["slot"]))
	var meta := _meta_for(s, int(pick["slot"]), "auto")
	meta["seq"] = int(pick["seq"])
	var err := SaveGame.save(s, path)
	if err != OK:
		push_error("SaveSlots.autosave: cannot write %s (error %d)" % [path, err])
		return err
	return _write_meta(path, meta)


## Loads autosave `i` (rotation index 0..2). Null when the index is out of range or the file does not load.
func load_auto(i: int, registry: DataRegistry) -> Settlement:
	if not _in_range(i, AUTO_SLOTS):
		push_error("SaveSlots.load_auto: autosave index %d is outside 0..%d" % [i, AUTO_SLOTS - 1])
		return null
	return SaveGame.load(_auto_path(i), registry)


## Rotation index of the newest existing autosave, -1 when there is none (the "continue" button of 19d).
func latest_auto() -> int:
	var found := -1
	var found_saved := 0
	var found_seq := 0
	for i in AUTO_SLOTS:
		if not FileAccess.file_exists(_auto_path(i)):
			continue
		var meta := _read_meta(_meta_path(_auto_path(i)))
		var saved := int(meta.get("saved_at", 0))
		var seq := int(meta.get("seq", 0))
		if found == -1 or saved > found_saved or (saved == found_saved and seq > found_seq):
			found = i
			found_saved = saved
			found_seq = seq
	return found


## The slot to write and its sequence number: the lowest free index, else the oldest by (saved_at, seq).
func _pick_auto_slot() -> Dictionary:
	var first_free := -1
	var oldest := -1
	var oldest_saved := 0
	var oldest_seq := 0
	var max_seq := 0
	for i in AUTO_SLOTS:
		var path := _auto_path(i)
		if not FileAccess.file_exists(path):
			if first_free == -1:
				first_free = i
			continue
		var meta := _read_meta(_meta_path(path))
		var saved := int(meta.get("saved_at", 0))
		var seq := int(meta.get("seq", 0))
		max_seq = maxi(max_seq, seq)
		if oldest == -1 or saved < oldest_saved or (saved == oldest_saved and seq < oldest_seq):
			oldest = i
			oldest_saved = saved
			oldest_seq = seq
	var slot := first_free if first_free != -1 else oldest
	return {"slot": slot, "seq": max_seq + 1}


# ---------------------------------------------------------------- manual slots

## Saves `s` into manual slot `i` (0..7). A 9th slot (index 8 or below 0) is refused.
func save_slot(i: int, s: Settlement) -> Error:
	if not _in_range(i, MANUAL_SLOTS):
		push_error("SaveSlots.save_slot: slot %d is outside 0..%d" % [i, MANUAL_SLOTS - 1])
		return ERR_PARAMETER_RANGE_ERROR
	var path := _slot_path(i)
	var err := SaveGame.save(s, path)
	if err != OK:
		push_error("SaveSlots.save_slot: cannot write %s (error %d)" % [path, err])
		return err
	return _write_meta(path, _meta_for(s, i, "manual"))


## Loads manual slot `i`. Null when the index is out of range or the file does not load.
func load_slot(i: int, registry: DataRegistry) -> Settlement:
	if not _in_range(i, MANUAL_SLOTS):
		push_error("SaveSlots.load_slot: slot %d is outside 0..%d" % [i, MANUAL_SLOTS - 1])
		return null
	return SaveGame.load(_slot_path(i), registry)


## Deletes manual slot `i` and its metadata. ERR_FILE_NOT_FOUND when the slot is empty.
func delete_slot(i: int) -> Error:
	if not _in_range(i, MANUAL_SLOTS):
		push_error("SaveSlots.delete_slot: slot %d is outside 0..%d" % [i, MANUAL_SLOTS - 1])
		return ERR_PARAMETER_RANGE_ERROR
	var path := _slot_path(i)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return err
	DirAccess.remove_absolute(_meta_path(path))
	return OK


## Every existing slot as {slot, kind ("manual"/"auto"), era, date, population, saved_at}, autosaves first. For an
## autosave, slot is its rotation index 0..2. Read from the sidecars only, so listing never loads a save.
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in AUTO_SLOTS:
		var path := _auto_path(i)
		if FileAccess.file_exists(path):
			out.append(_entry(_read_meta(_meta_path(path)), i, "auto"))
	for i in MANUAL_SLOTS:
		var path := _slot_path(i)
		if FileAccess.file_exists(path):
			out.append(_entry(_read_meta(_meta_path(path)), i, "manual"))
	return out


func _entry(meta: Dictionary, slot: int, kind: String) -> Dictionary:
	return {
		"slot": slot,
		"kind": kind,
		"era": str(meta.get("era", "")),
		"date": str(meta.get("date", "")),
		"population": int(meta.get("population", -1)),
		"saved_at": int(meta.get("saved_at", 0)),
	}


func _meta_for(s: Settlement, slot: int, kind: String) -> Dictionary:
	return {
		"slot": slot,
		"kind": kind,
		"era": s.era_id(),
		"date": s.clock.label(),
		"population": s.citizens.size(),
		"saved_at": int(Time.get_unix_time_from_system()),
	}


# ---------------------------------------------------------------- files and metadata

func _slot_path(i: int) -> String:
	return save_dir.path_join("slot_%d%s" % [i, SAVE_SUFFIX])


func _auto_path(i: int) -> String:
	return save_dir.path_join("auto_%d%s" % [i, SAVE_SUFFIX])


func _meta_path(save_path: String) -> String:
	return save_path + META_SUFFIX


## Writes the sidecar atomically too (JSON text): a reader never sees half a sidecar.
func _write_meta(save_path: String, meta: Dictionary) -> Error:
	var path := _meta_path(save_path)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("SaveSlots: cannot write %s (error %d)" % [tmp, err])
		return err
	f.store_string(JSON.stringify(meta))
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		push_error("SaveSlots: write to %s failed (error %d)" % [tmp, err])
		return err
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		DirAccess.remove_absolute(tmp)
		push_error("SaveSlots: cannot move %s over %s (error %d)" % [tmp, path, rename_err])
		return rename_err
	return OK


func _read_meta(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _in_range(i: int, count: int) -> bool:
	return i >= 0 and i < count
