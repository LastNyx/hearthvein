class_name DataRegistry
extends RefCounted
## Loads every .tres under a data root, indexes it by id per type and validates all references.
## Plain RefCounted: create one, call load_all(), read `errors`. No autoload needed.

const DEFAULT_ROOT := "res://data"

var goods: Dictionary = {}      # id -> GoodDef
var buildings: Dictionary = {}  # id -> BuildingDef
var eras: Dictionary = {}       # id -> EraDef
var terrain: Dictionary = {}    # id -> TerrainDef
var errors: Array[String] = []


## Loads and validates. Returns the error list (empty when everything is fine).
## Every error is also reported with push_error.
func load_all(root: String = DEFAULT_ROOT) -> Array[String]:
	goods.clear()
	buildings.clear()
	eras.clear()
	terrain.clear()
	errors.clear()
	for path in _scan(root):
		_index(path)
	_validate()
	for e in errors:
		push_error("DataRegistry: " + e)
	return errors


func get_good(id: String) -> GoodDef:
	return goods.get(id)


func get_building(id: String) -> BuildingDef:
	return buildings.get(id)


func get_era(id: String) -> EraDef:
	return eras.get(id)


func get_terrain(id: String) -> TerrainDef:
	return terrain.get(id)


## Eras sorted by order.
func eras_in_order() -> Array[EraDef]:
	var out: Array[EraDef] = []
	for e in eras.values():
		out.append(e)
	out.sort_custom(func(a: EraDef, b: EraDef) -> bool: return a.order < b.order)
	return out


## Buildings unlocked by an era (derived from BuildingDef.era).
func buildings_of_era(era_id: String) -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for b in buildings.values():
		if b.era == era_id:
			out.append(b)
	return out


func _scan(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		errors.append("cannot open data folder %s" % dir_path)
		return found
	var names := Array(dir.get_files())
	names.sort()
	for f: String in names:
		# Exported builds list resources as "x.tres.remap".
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres"):
			found.append(dir_path.path_join(name))
	var subs := Array(dir.get_directories())
	subs.sort()
	for d: String in subs:
		found.append_array(_scan(dir_path.path_join(d)))
	return found


func _index(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res == null:
		errors.append("%s: failed to load" % path)
	elif res is GoodDef:
		_add(goods, res.id, res, path, "good")
	elif res is BuildingDef:
		_add(buildings, res.id, res, path, "building")
	elif res is EraDef:
		_add(eras, res.id, res, path, "era")
	elif res is TerrainDef:
		_add(terrain, res.id, res, path, "terrain")
	else:
		errors.append("%s: not a known definition type" % path)


func _add(table: Dictionary, id: String, res: Resource, path: String, label: String) -> void:
	if id == "":
		errors.append("%s: %s has an empty id" % [path, label])
	elif table.has(id):
		errors.append("%s: duplicate %s id '%s'" % [path, label, id])
	else:
		table[id] = res


func _validate() -> void:
	for g: GoodDef in goods.values():
		if g.kind != GoodDef.KIND_BASE and g.kind != GoodDef.KIND_REFINED:
			errors.append("good '%s': unknown kind '%s'" % [g.id, g.kind])
	for t: TerrainDef in terrain.values():
		if t.fertility_start < 0.0 or t.fertility_start > 1.0:
			errors.append("terrain '%s': fertility_start out of 0..1" % t.id)
	_validate_eras()
	for b: BuildingDef in buildings.values():
		_validate_building(b)


func _validate_eras() -> void:
	var orders := {}
	for e: EraDef in eras.values():
		if orders.has(e.order):
			errors.append("era '%s': order %d already used by '%s'" % [e.id, e.order, orders[e.order]])
		orders[e.order] = e.id
		if e.dimming_base_days <= 0:
			errors.append("era '%s': dimming_base_days must be positive" % e.id)
	# Gate landmarks. Era N's gate is the landmark of era N-1. If era N-1 has any buildings
	# defined, that landmark must exist (category landmark, in era N-1). If era N-1 has no
	# buildings yet (later eras come with later tickets) the id is "pending" and only has to
	# be non-empty. Adding the first building of an era therefore makes its landmark mandatory.
	var ordered := eras_in_order()
	for i in ordered.size():
		var e := ordered[i]
		if i == 0:
			if e.gate_landmark != "":
				errors.append("era '%s': first era must not have a gate landmark" % e.id)
			continue
		if e.gate_landmark == "":
			errors.append("era '%s': missing gate landmark" % e.id)
			continue
		var prev := ordered[i - 1]
		var b: BuildingDef = buildings.get(e.gate_landmark)
		if b != null:
			if b.category != "landmark":
				errors.append("era '%s': gate '%s' is not a landmark" % [e.id, b.id])
			elif b.era != prev.id:
				errors.append("era '%s': gate landmark '%s' belongs to era '%s', expected '%s'" % [e.id, b.id, b.era, prev.id])
		elif not buildings_of_era(prev.id).is_empty():
			errors.append("era '%s': gate landmark '%s' does not exist" % [e.id, e.gate_landmark])


func _validate_building(b: BuildingDef) -> void:
	var who := "building '%s'" % b.id
	if not eras.has(b.era):
		errors.append("%s: unknown era '%s'" % [who, b.era])
	if not BuildingDef.CATEGORIES.has(b.category):
		errors.append("%s: unknown category '%s'" % [who, b.category])
	if not BuildingDef.PLACEMENT_RULES.has(b.placement_rule):
		errors.append("%s: unknown placement rule '%s'" % [who, b.placement_rule])
	if not BuildingDef.STORAGE_MODES.has(b.storage_mode):
		errors.append("%s: unknown storage mode '%s'" % [who, b.storage_mode])
	elif b.storage_mode != "none" and b.storage_cap <= 0:
		errors.append("%s: storage mode '%s' needs a positive storage_cap" % [who, b.storage_mode])
	if b.size.x < 1 or b.size.y < 1:
		errors.append("%s: size must be at least 1x1" % who)
	_check_amounts(b.cost, who + " cost", true)
	if b.recipe != null:
		_check_amounts(b.recipe.inputs, who + " recipe input", false)
		_check_amounts(b.recipe.outputs, who + " recipe output", false)
		if b.recipe.outputs.is_empty():
			errors.append("%s: recipe has no outputs" % who)
		if b.worker_slots <= 0:
			errors.append("%s: has a recipe but no worker slots" % who)
	if b.upgradable and b.tiers.size() != 2:
		errors.append("%s: upgradable needs exactly 2 tiers (II, III)" % who)
	if not b.upgradable and not b.tiers.is_empty():
		errors.append("%s: has tiers but is not upgradable" % who)
	for t in b.tiers:
		if t == null:
			errors.append("%s: null tier" % who)
		else:
			_check_amounts(t.cost, "%s tier '%s' cost" % [who, t.display_name], true)


func _check_amounts(d: Dictionary, label: String, whole: bool) -> void:
	for k in d:
		if not (k is String) or not (goods.has(k)):
			errors.append("%s: unknown good '%s'" % [label, k])
		var v: Variant = d[k]
		if not (v is int or v is float) or v <= 0:
			errors.append("%s: amount for '%s' must be positive" % [label, k])
		elif whole and not (v is int):
			errors.append("%s: amount for '%s' must be a whole number" % [label, k])
