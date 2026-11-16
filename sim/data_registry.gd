class_name DataRegistry
extends RefCounted
## Loads every .tres under a data root, indexes it by id per type and validates all references.
## Plain RefCounted: create one, call load_all(), read `errors`. No autoload needed.

const DEFAULT_ROOT := "res://data"

var goods: Dictionary = {}      # id -> GoodDef
var buildings: Dictionary = {}  # id -> BuildingDef
var eras: Dictionary = {}       # id -> EraDef
var terrain: Dictionary = {}    # id -> TerrainDef
var roads: Dictionary = {}      # id -> RoadDef
var logistics: LogisticsDef = null  # the single data/logistics/logistics.tres
var spirit: SpiritDef = null  # the single data/spirit/spirit.tres
var growth: GrowthDef = null  # the single data/growth/growth.tres
var planet: PlanetDef = null  # the single data/planet/planet.tres
var soil: SoilDef = null      # the single data/soil/soil.tres
var forest: ForestDef = null  # the single data/forest/forest.tres
var water: WaterDef = null    # the single data/water/water.tres
var regions: RegionsDef = null  # the single data/regions/regions.tres
var mapgen: MapGenDef = null        # the single data/mapgen/mapgen.tres
var tiers: TierRuleDef = null       # the single data/tiers/tiers.tres (upgrade tier default rule)
var errors: Array[String] = []


## Loads and validates. Returns the error list (empty when everything is fine).
## Every error is also reported with push_error.
func load_all(root: String = DEFAULT_ROOT) -> Array[String]:
	goods.clear()
	buildings.clear()
	eras.clear()
	terrain.clear()
	roads.clear()
	logistics = null
	growth = null
	spirit = null
	planet = null
	soil = null
	forest = null
	water = null
	regions = null
	mapgen = null
	tiers = null
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


func get_road(id: String) -> RoadDef:
	return roads.get(id)


## Road def for a Settlement.ROAD_* level, or null.
func get_road_by_level(level: int) -> RoadDef:
	for r: RoadDef in roads.values():
		if r.level == level:
			return r
	return null


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
	elif res is LogisticsDef:
		if logistics != null:
			errors.append("%s: a second logistics definition" % path)
		logistics = res
	elif res is GrowthDef:
		if growth != null:
			errors.append("%s: a second growth definition" % path)
		growth = res
	elif res is SpiritDef:
		if spirit != null:
			errors.append("%s: a second spirit definition" % path)
		spirit = res
	elif res is PlanetDef:
		if planet != null:
			errors.append("%s: a second planet definition" % path)
		planet = res
	elif res is SoilDef:
		if soil != null:
			errors.append("%s: a second soil definition" % path)
		soil = res
	elif res is ForestDef:
		if forest != null:
			errors.append("%s: a second forest definition" % path)
		forest = res
	elif res is WaterDef:
		if water != null:
			errors.append("%s: a second water definition" % path)
		water = res
	elif res is RegionsDef:
		if regions != null:
			errors.append("%s: a second regions definition" % path)
		regions = res
	elif res is MapGenDef:
		if mapgen != null:
			errors.append("%s: a second mapgen definition" % path)
		mapgen = res
	elif res is TierRuleDef:
		if tiers != null:
			errors.append("%s: a second tier rule definition" % path)
		tiers = res
	elif res is RoadDef:
		_add(roads, res.id, res, path, "road")
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
	for t: TerrainDef in terrain.values():
		if t.walk_speed < 0.0:
			errors.append("terrain '%s': walk_speed must not be negative" % t.id)
	var levels := {}
	for r: RoadDef in roads.values():
		if r.walk_speed <= 0.0:
			errors.append("road '%s': walk_speed must be positive" % r.id)
		if r.era != "" and not eras.has(r.era):
			errors.append("road '%s': unknown era '%s'" % [r.id, r.era])
		_check_amounts(r.cost, "road '%s' cost" % r.id, false)
		if levels.has(r.level):
			errors.append("road '%s': level %d already used by '%s'" % [r.id, r.level, levels[r.level]])
		levels[r.level] = r.id
	if logistics == null:
		if not goods.is_empty():  # an unreadable data root is already one error
			errors.append("missing logistics definition")
	elif logistics.door_buffer_cap <= 0.0 or logistics.haul_load <= 0.0 or logistics.input_buffer_days <= 0.0 \
			or logistics.min_pickup <= 0.0 or logistics.units_per_felled_tile <= 0.0 \
			or logistics.build_days_per_tile <= 0.0 or logistics.build_days_per_era < 0.0 or logistics.build_days_min <= 0.0 \
			or logistics.build_days_max < logistics.build_days_min or logistics.builder_crew <= 0 \
			or logistics.demolish_refund < 0.0 or logistics.demolish_refund > 1.0 \
			or logistics.unpaid_upkeep_factor <= 0.0 or logistics.unpaid_upkeep_factor > 1.0:
		errors.append("logistics: every number must be positive")
	if growth == null:
		if not goods.is_empty():
			errors.append("missing growth definition")
	elif growth.food_per_citizen <= 0.0 or growth.bar_base <= 0.0 or growth.bar_pop_divisor <= 0.0 \
			or growth.soft_cap <= 0 or growth.soft_cap_span <= 0.0 or growth.immigration_days <= 0 or growth.leave_per_day <= 0:
		errors.append("growth: every number must be positive")
	if spirit == null:
		if not goods.is_empty():
			errors.append("missing spirit definition")
	elif spirit.step_per_day <= 0.0 or spirit.start < 0.0 or spirit.start > 100.0 or spirit.low_at >= spirit.high_at \
			or spirit.grief_divisor <= 0.0 or spirit.leave_after_days <= 0 or spirit.leave_every_days <= 0 \
			or spirit.coverage_min_share < 0.0 or spirit.coverage_min_share > 1.0:
		errors.append("spirit: invalid numbers")
	if planet == null:
		if not goods.is_empty():
			errors.append("missing planet definition")
	elif planet.start < 0.0 or planet.start > 100.0 or planet.vein_divisor <= 0.0 or planet.dieback_divisor <= 0.0 \
			or planet.trend_days <= 0 or not terrain.has(planet.dieback_terrain):
		errors.append("planet: invalid numbers")
	if soil == null:
		if not goods.is_empty():
			errors.append("missing soil definition")
	elif soil.wear_per_season < 0.0 or soil.recovery_per_season <= 0.0 \
			or soil.blight_factor < 0.0 or soil.blight_factor > 1.0:
		errors.append("soil: invalid numbers")
	if forest == null:
		if not goods.is_empty():
			errors.append("missing forest definition")
	elif forest.regrow_seasons <= 0 or forest.forester_regrow_seasons <= 0 \
			or forest.regrow_min_health < 0.0 or forest.regrow_min_health > 100.0 \
			or forest.plant_per_worker_day < 0.0 or forest.old_forest_regrow_factor <= 0.0:
		errors.append("forest: invalid numbers")
	if water == null:
		if not goods.is_empty():
			errors.append("missing water definition")
	elif water.wet_radius_water < 0 or water.wet_radius_channel < 0 \
			or water.farm_wet_fraction <= 0.0 or water.farm_wet_fraction > 1.0 or water.farm_wet_bonus < 1.0 \
			or water.channel_cost_materials < 0.0 or water.foul_spread_tiles_per_hour < 1 \
			or water.foul_clear_hours < 0 \
			or water.foul_dock_output_factor <= 0.0 or water.foul_dock_output_factor > 1.0 \
			or water.foul_farm_output_factor <= 0.0 or water.foul_farm_output_factor > 1.0:
		errors.append("water: invalid numbers")
	if regions == null:
		if not goods.is_empty():
			errors.append("missing regions definition")
	else:
		if regions.prices.is_empty() or regions.prices.any(func(p: int) -> bool: return p <= 0) \
				or regions.price_after <= 0:
			errors.append("regions: prices must be positive")
		if regions.rich_vein_factor < 1.0:
			errors.append("regions: rich_vein_factor must be at least 1")
		if regions.ruins_gold < 0:
			errors.append("regions: ruins_gold must not be negative")
		_check_amounts(regions.ruins_goods, "regions ruins goods", false)
	_validate_mapgen()
	_validate_tiers()
	_validate_eras()
	for b: BuildingDef in buildings.values():
		_validate_building(b)


func _validate_mapgen() -> void:
	if mapgen == null:
		if not goods.is_empty():
			errors.append("missing mapgen definition")
		return
	var m := mapgen
	if m.river_width_min < 2.0 or m.river_width_max > 4.0 or m.river_width_min > m.river_width_max:
		errors.append("mapgen: river width must satisfy 2 <= min <= max <= 4")
	if m.river_width_freq <= 0.0 or m.river_smooth_window < 0 or m.river_meander_spacing <= 0 \
			or m.river_meander_jitter < 0 or m.river_start_offset < 7:
		errors.append("mapgen: river numbers out of range")
	if m.lake_count_min < 0 or m.lake_count_max < m.lake_count_min or m.pond_count_min < 0 \
			or m.pond_count_max < m.pond_count_min:
		errors.append("mapgen: lake/pond counts out of range")
	if m.lake_radius_min <= 0.0 or m.lake_radius_max < m.lake_radius_min or m.pond_radius_min <= 0.0 \
			or m.pond_radius_max < m.pond_radius_min:
		errors.append("mapgen: lake/pond radii out of range")


func _validate_tiers() -> void:
	if tiers == null:
		if not goods.is_empty():
			errors.append("missing tier rule definition")
		return
	var t := tiers
	if t.eras.size() != 2 or t.output_factors.size() != 2 or t.extra_worker_slots.size() != 2 \
			or t.cost_fractions.size() != 2:
		errors.append("tiers: eras, output_factors, extra_worker_slots and cost_fractions need one entry per tier (II, III)")
		return
	for e in t.eras:
		if e != "" and not eras.has(e):
			errors.append("tiers: unknown era '%s'" % e)
	for f in t.output_factors:
		if f <= 0.0:
			errors.append("tiers: output factors must be positive")
	for n in t.extra_worker_slots:
		if n < 0:
			errors.append("tiers: extra worker slots must not be negative")
	for i in t.cost_fractions.size():
		_check_amounts(t.cost_fractions[i], "tiers tier %d cost fraction" % (i + 2), false)
		for g in t.cost_fractions[i]:
			if float(t.cost_fractions[i][g]) > 1.0:
				errors.append("tiers: cost fraction for '%s' must be at most 1" % g)


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
		if b.recipe.any_input_count > 0:
			if b.recipe.any_input_count > b.recipe.any_input_goods.size():
				errors.append("%s: recipe needs %d flexible inputs but lists %d" % [who,
						b.recipe.any_input_count, b.recipe.any_input_goods.size()])
			if b.recipe.any_input_amount <= 0.0:
				errors.append("%s: recipe flexible input amount must be positive" % who)
			for g in b.recipe.any_input_goods:
				if not goods.has(g):
					errors.append("%s: recipe unknown flexible input '%s'" % [who, g])
	if b.upgradable and b.tiers.size() != 2:
		errors.append("%s: upgradable needs exactly 2 tiers (II, III)" % who)
	if b.fertility_output and b.recipe == null:
		errors.append("%s: fertility_output without a recipe" % who)
	if b.fertile_origin_bonus < 1.0:
		errors.append("%s: fertile_origin_bonus must be at least 1" % who)
	if b.plants_forest and b.placement_radius <= 0:
		errors.append("%s: plants_forest needs a placement_radius" % who)
	if b.gold_per_worker_day < 0.0:
		errors.append("%s: gold_per_worker_day must not be negative" % who)
	if b.market_reach < 0:
		errors.append("%s: market_reach must not be negative" % who)
	if b.coverage_radius < 0:
		errors.append("%s: coverage_radius must not be negative" % who)
	if b.wet_radius < 0:
		errors.append("%s: wet_radius must not be negative" % who)
	if b.water_radius < 0:
		errors.append("%s: water_radius must not be negative" % who)
	if b.needs_water and b.housing_beds <= 0:
		errors.append("%s: needs_water without housing beds" % who)
	if b.region_haul_load < 0.0:
		errors.append("%s: region_haul_load must not be negative" % who)
	if b.clean_radius < 0 or b.clean_interval_days < 0:
		errors.append("%s: cleaning numbers must not be negative" % who)
	elif (b.clean_radius > 0) != (b.clean_interval_days > 0):
		errors.append("%s: clean_radius and clean_interval_days go together" % who)
	if b.paved_haul_speed_factor < 1.0:
		errors.append("%s: paved_haul_speed_factor must be at least 1" % who)
	if b.blight_block_radius < 0:
		errors.append("%s: blight_block_radius must not be negative" % who)
	if not b.upgradable and not b.tiers.is_empty():
		errors.append("%s: has tiers but is not upgradable" % who)
	for t in b.tiers:
		if t == null:
			errors.append("%s: null tier" % who)
		else:
			_check_amounts(t.cost, "%s tier '%s' cost" % [who, t.display_name], true)
			if t.multiplier < 0.0:
				errors.append("%s: tier '%s' multiplier must not be negative" % [who, t.display_name])
			if t.extra_worker_slots < -1:
				errors.append("%s: tier '%s' extra worker slots must be -1 (default) or more"
						% [who, t.display_name])
			if t.wet_bonus < 1.0:
				errors.append("%s: tier '%s' wet_bonus must be at least 1" % [who, t.display_name])
			if t.needs_wet and not b.fertility_output:
				errors.append("%s: tier '%s' needs_wet without fertility_output" % [who, t.display_name])


func _check_amounts(d: Dictionary, label: String, whole: bool) -> void:
	for k in d:
		if not (k is String) or not (goods.has(k)):
			errors.append("%s: unknown good '%s'" % [label, k])
		var v: Variant = d[k]
		if not (v is int or v is float) or v <= 0:
			errors.append("%s: amount for '%s' must be positive" % [label, k])
		elif whole and not (v is int):
			errors.append("%s: amount for '%s' must be a whole number" % [label, k])
