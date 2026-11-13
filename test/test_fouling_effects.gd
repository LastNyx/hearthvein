extends GutTest
## Ticket 29c: fouled water effects (design.md section 9, D42).
## Fouled water halves the Fishing Dock, takes a quarter off a farm whose wetness comes only from fouled water, and
## a Well wet only from fouled water serves no drinking water.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var prod: ProductionSystem
var cov: CoverageSystem
var sp: SpiritSystem
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	prod = s.get_system(ProductionSystem)
	cov = s.get_system(CoverageSystem)
	sp = s.get_system(SpiritSystem)


func _owned(t: Vector2i) -> bool:
	return s.map.is_region_owned(s.map.get_region(t.x, t.y))


func _is_water(t: Vector2i) -> bool:
	return s.map.terrain_id_at(t.x, t.y) == "water"


func _no_water_within(t: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := t + Vector2i(dx, dy)
			if MapState.in_bounds(n.x, n.y) and _is_water(n):
				return false
	return true


## An owned, empty land tile beside the river where a Fishing Dock can stand.
func _shore_spot() -> Vector2i:
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			var t := Vector2i(x, y)
			if not _owned(t) or _is_water(t) or s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE:
				continue
			if s.can_place("fishing_dock", t)["ok"]:
				return t
	return Vector2i(-1, -1)


func _adjacent_water(t: Vector2i) -> Vector2i:
	for d in Placement.DIRS:
		var n := t + d
		if MapState.in_bounds(n.x, n.y) and _is_water(n):
			return n
	return Vector2i(-1, -1)


## An owned, empty, dry 2x2 grass block with no water within `gap` of any of its tiles.
func _dry_block(w: int, h: int, gap: int) -> Vector2i:
	for y in range(0, MapState.HEIGHT - h + 1):
		for x in range(0, MapState.WIDTH - w + 1):
			var ok := true
			for dy in h:
				for dx in w:
					var t := Vector2i(x + dx, y + dy)
					if not _owned(t) or s.map.terrain_id_at(t.x, t.y) != "grass" \
							or s.building_at(t) != null or s.road_at(t) != Settlement.ROAD_NONE \
							or not _no_water_within(t, gap):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A run of empty owned land with a free tile beside it for a fouled pond, and no real water within 2 of where the
## Well will stand. Returns {home, well, pond}, or {} when the map has no such place.
func _well_stage() -> Dictionary:
	for y in MapState.HEIGHT:
		for x in range(0, MapState.WIDTH - 7):
			var b := Vector2i(x, y)
			var ok := true
			for dx in 8:
				var t := b + Vector2i(dx, 0)
				if not _owned(t) or _is_water(t) or s.building_at(t) != null \
						or s.road_at(t) != Settlement.ROAD_NONE:
					ok = false
					break
			if not ok:
				continue
			var well := b + Vector2i(5, 0)
			if not _no_water_within(well, 2):
				continue
			return {"home": b, "well": well, "pond": b + Vector2i(6, 0)}
	return {}


## A finished building inserted straight into the layout (no placement rules), bumping structure_version.
func _fake(def_id: String, origin: Vector2i) -> Building:
	_next_fake += 1
	var b := Building.new()
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = origin
	s.buildings[b.id] = b
	s.structure_version += 1
	return b


func _factor(id: String) -> float:
	return sp.breakdown(s)["factors"][id]


# The two multipliers are the design's numbers, read from data.
func test_fouled_water_numbers_come_from_data() -> void:
	assert_almost_eq(reg.water.foul_dock_output_factor, 0.5, 0.001)
	assert_almost_eq(reg.water.foul_farm_output_factor, 0.75, 0.001)


# AC1a: a Fishing Dock beside fouled water produces at half rate.
func test_fishing_dock_output_is_halved_on_fouled_water() -> void:
	var spot := _shore_spot()
	assert_ne(spot, Vector2i(-1, -1), "a shore spot for the Dock")
	if spot == Vector2i(-1, -1):
		return
	var dock: Building = s.buildings.get(s.place_building_instant("fishing_dock", spot))
	assert_not_null(dock)
	var shore := _adjacent_water(spot)
	assert_ne(shore, Vector2i(-1, -1), "the Dock really touches water")
	assert_almost_eq(FoulingSystem.output_modifier(s, dock), 1.0, 0.001, "clean water is no penalty")
	var clean := prod.multiplier(s, dock)
	assert_true(s.set_fouled(shore, true))
	assert_almost_eq(FoulingSystem.output_modifier(s, dock), 0.5, 0.001, "fouled shore water halves the Dock")
	assert_almost_eq(prod.multiplier(s, dock), clean * 0.5, 0.001, "the modifier reaches production")
	assert_true(s.set_fouled(shore, false))
	assert_almost_eq(FoulingSystem.output_modifier(s, dock), 1.0, 0.001, "clean water again, full rate")


# AC1a: an Irrigated Farm watered only by a fouled pond loses a quarter of its output; clean water is no penalty.
func test_a_farm_wet_only_from_fouled_water_runs_at_three_quarters() -> void:
	var b := _dry_block(2, 2, 2)
	assert_ne(b, Vector2i(-1, -1), "a dry grass 2x2")
	if b == Vector2i(-1, -1):
		return
	var farm: Building = s.buildings.get(s.place_building_instant("farm", b))
	assert_not_null(farm)
	farm.tier = 2  # the fouled x0.75 is for the Irrigated Farm only (ticket 31c)
	var pond := b + Vector2i(-1, 0)
	assert_false(_is_water(pond), "the stage starts dry")
	s.set_terrain(pond, "water")
	WaterSystem.recompute(s)
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 1.5, 0.001, "the pond waters the Irrigated Farm")
	assert_almost_eq(FoulingSystem.output_modifier(s, farm), 1.0, 0.001, "clean water is no penalty")
	var clean := prod.multiplier(s, farm)
	assert_true(s.set_fouled(pond, true))
	assert_almost_eq(FoulingSystem.output_modifier(s, farm), 0.75, 0.001, "fouled-only wetness takes a quarter")
	assert_almost_eq(prod.multiplier(s, farm), clean * 0.75, 0.001, "the modifier reaches production")
	assert_true(s.set_fouled(pond, false))
	assert_almost_eq(FoulingSystem.output_modifier(s, farm), 1.0, 0.001, "clean pond, no penalty")
	s.set_terrain(pond, "grass")
	WaterSystem.recompute(s)
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 0.0, 0.001, "a dry Irrigated Farm stops")
	assert_almost_eq(FoulingSystem.output_modifier(s, farm), 1.0, 0.001, "a dry farm has no wetness to foul")


# A plain tier-I Farm is not penalised: design.md section 9 names irrigated farms only (ticket 31c gate).
func test_a_plain_farm_is_not_penalised_by_fouled_water() -> void:
	var b := _dry_block(2, 2, 2)
	assert_ne(b, Vector2i(-1, -1), "a dry grass 2x2")
	if b == Vector2i(-1, -1):
		return
	var farm: Building = s.buildings.get(s.place_building_instant("farm", b))
	assert_not_null(farm)
	assert_eq(farm.tier, 1)
	var pond := b + Vector2i(-1, 0)
	s.set_terrain(pond, "water")
	WaterSystem.recompute(s)
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 1.25, 0.001, "a plain wet farm keeps its x1.25")
	assert_true(s.set_fouled(pond, true))
	assert_false(FoulingSystem.farm_wet_only_fouled(s, farm), "a plain farm is not gated on fouled water")
	assert_almost_eq(FoulingSystem.output_modifier(s, farm), 1.0, 0.001, "fouled water does not touch a plain farm")


# AC1b: a Well on a tile wet only from fouled water gives no coverage, so its homes count as missing water.
func test_a_well_wet_only_from_fouled_water_serves_nothing() -> void:
	var stage := _well_stage()
	assert_false(stage.is_empty(), "an empty run with room for a fouled pond")
	if stage.is_empty():
		return
	var home := _fake("rowhouse", stage["home"])
	var well := _fake("well", stage["well"])
	var pond: Vector2i = stage["pond"]
	for cid in s.citizens:
		(s.citizens[cid] as Citizen).home_id = home.id
	s.set_terrain(pond, "water")
	WaterSystem.recompute(s)
	assert_true(s.set_fouled(pond, true))
	assert_true(FoulingSystem.wet_only_from_fouled(s, well.origin), "the Well stands on fouled-only water")
	assert_false(cov.home_has_water(s, home.id), "unsafe water is not coverage")
	assert_almost_eq(_factor("water"), -reg.spirit.water_max, 0.001, "the home counts as missing water")
	assert_true(s.set_fouled(pond, false))
	assert_false(FoulingSystem.wet_only_from_fouled(s, well.origin), "the pond is clean now")
	assert_true(cov.home_has_water(s, home.id), "the same Well serves clean water")
	assert_almost_eq(_factor("water"), 0.0, 0.001, "no missing-water penalty")


# A Well on a clean tile keeps serving even while other water on the map is fouled.
func test_clean_wells_keep_serving_while_the_river_is_fouled() -> void:
	var stage := _well_stage()
	assert_false(stage.is_empty(), "an empty run for the well and home")
	if stage.is_empty():
		return
	var home := _fake("rowhouse", stage["home"])
	var well := _fake("well", stage["well"])
	var pond: Vector2i = stage["pond"]
	s.set_terrain(pond, "water")
	WaterSystem.recompute(s)
	# A fouled river tile elsewhere does not touch this well's clean pond.
	var far := Vector2i(-1, -1)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_river(x, y):
				far = Vector2i(x, y)
				break
		if far.x >= 0:
			break
	assert_ne(far, Vector2i(-1, -1), "the map has a river")
	s.set_fouled(far, true)
	assert_true(cov.home_has_water(s, home.id), "the clean Well still serves")
	s.set_fouled(far, false)
