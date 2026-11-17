class_name SaveMenuModel
extends RefCounted
## Rows and commands of the pause/save menu (ticket 19d), over SaveSlots. No scene tree: the Control (ui/save_menu.gd)
## only copies these strings onto buttons. Loading returns the new Settlement; ui/main.gd swaps it in.

var slots: SaveSlots
var registry: DataRegistry
## Returns the Settlement being played right now (what Save writes).
var current: Callable
var status: String = ""
## Row waiting for a Yes/No: {"action": "overwrite" | "delete", "slot": int}, or empty.
var pending: Dictionary = {}


func _init(save_slots: SaveSlots, reg: DataRegistry, current_settlement: Callable) -> void:
	slots = save_slots
	registry = reg
	current = current_settlement


## Existing autosaves (newest first), then the 8 manual slots, empty ones included:
## {kind, slot, title, empty, detail, can_save, can_load, can_delete}. mode "save" lists the manual slots only
## (autosaves are not written by hand); "load" and the default list both.
func rows(mode: String = "all") -> Array[Dictionary]:
	var listed := slots.list()
	var autos: Array[Dictionary] = []
	var manual := {}
	for e in listed:
		if e["kind"] == "auto":
			autos.append(e)
		else:
			manual[e["slot"]] = e
	autos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["saved_at"] > b["saved_at"])
	var out: Array[Dictionary] = []
	for n in (0 if mode == "save" else autos.size()):
		var e: Dictionary = autos[n]
		out.append({"kind": "auto", "slot": e["slot"], "title": "Autosave %d" % (n + 1), "empty": false,
				"detail": detail_text(e), "can_save": false, "can_load": true, "can_delete": false, "confirm": ""})
	for i in SaveSlots.MANUAL_SLOTS:
		var filled: bool = manual.has(i)
		out.append({"kind": "manual", "slot": i, "title": "Slot %d" % (i + 1), "empty": not filled,
				"detail": detail_text(manual[i]) if filled else "Empty",
				"can_save": true, "can_load": filled, "can_delete": filled,
					"confirm": str(pending["action"]) if not pending.is_empty() and pending["slot"] == i else ""})
	return out


## "Village, Spring 3 Year 2, pop 24, saved 13 Nov 10:12".
func detail_text(e: Dictionary) -> String:
	var era := registry.get_era(e["era"])
	var parts: Array[String] = [era.display_name if era != null else str(e["era"])]
	if str(e["date"]) != "":
		parts.append(str(e["date"]))
	if int(e["population"]) >= 0:
		parts.append("pop %d" % int(e["population"]))
	parts.append("saved " + saved_text(int(e["saved_at"])))
	return ", ".join(parts)


static func saved_text(unix: int) -> String:
	if unix <= 0:
		return "unknown"
	var local := unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %02d:%02d" % [d["day"], MONTHS[int(d["month"]) - 1], d["hour"], d["minute"]]


func has_continue() -> bool:
	return slots.latest_auto() >= 0


## Save button: a filled slot asks first (pending = overwrite), an empty one saves at once. Returns true if it saved.
func request_save(slot: int) -> bool:
	if _filled(slot):
		pending = {"action": "overwrite", "slot": slot}
		status = "Overwrite Slot %d?" % (slot + 1)
		return false
	return save_to(slot) == OK


func _filled(slot: int) -> bool:
	for e in slots.list():
		if e["kind"] == "manual" and e["slot"] == slot:
			return true
	return false


## Delete button: always asks first.
func request_delete(slot: int) -> void:
	pending = {"action": "delete", "slot": slot}
	status = "Delete Slot %d?" % (slot + 1)


## Yes: run the pending overwrite or delete.
func confirm() -> void:
	var p := pending
	pending = {}
	if p.is_empty():
		return
	if p["action"] == "overwrite":
		save_to(p["slot"])
	else:
		delete_slot(p["slot"])


## No: drop the pending action.
func cancel() -> void:
	pending = {}
	status = ""


func save_to(slot: int) -> Error:
	var err := slots.save_slot(slot, current.call())
	status = "Saved to Slot %d" % (slot + 1) if err == OK else "Could not save to Slot %d" % (slot + 1)
	return err


## The loaded Settlement, or null (status says why).
func load_row(kind: String, slot: int) -> Settlement:
	var s: Settlement = slots.load_auto(slot, registry) if kind == "auto" else slots.load_slot(slot, registry)
	if s == null:
		status = "Could not load that save"
	else:
		status = "Loaded"
	return s


## The newest save of any kind (autosave or manual slot) as a slots.list() entry, or empty when there is none.
func newest_save() -> Dictionary:
	var best := {}
	var auto := slots.latest_auto()
	for e in slots.list():
		if e["kind"] == "auto" and e["slot"] != auto:
			continue
		if best.is_empty() or int(e["saved_at"]) > int(best["saved_at"]):
			best = e
	return best


## Title screen Continue: loads the newest save of any kind. Null (status says why) when there is none.
func continue_newest() -> Settlement:
	var e := newest_save()
	if e.is_empty():
		status = "No save yet"
		return null
	return load_row(e["kind"], e["slot"])


func continue_latest() -> Settlement:
	var i := slots.latest_auto()
	if i < 0:
		status = "No autosave yet"
		return null
	return load_row("auto", i)


func delete_slot(slot: int) -> Error:
	var err := slots.delete_slot(slot)
	status = "Deleted Slot %d" % (slot + 1) if err == OK else "Nothing to delete"
	return err
