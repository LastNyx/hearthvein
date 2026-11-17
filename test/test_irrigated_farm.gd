extends GutTest
## Ticket 31c: Irrigated Farm (design.md sections 9 and 10, D36). Farm tier II only works on wet ground: it needs at
## least half its footprint wet to run at all, and then gets the tier's own x1.5 plus the irrigation x1.5. The
## irrigation x1.5 replaces the plain farm wet x1.25 -- the two do not stack. Upgrading goes in place and needs the
## farm to be wet first.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var prod: ProductionSystem


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "town"  # tier II unlocks in Town
	prod = s.get_system(ProductionSystem)


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


## An owned, empty, dry w x h grass block with no water within `gap` of any of its tiles: the stage a test wets by
## digging its own pond, without the real river interfering.
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


## A finished Farm on a dry block, every footprint tile at full fertility, so wetness is the only variable.
func _dry_farm() -> Building:
	var b := _dry_block(2, 2, 2)
	assert_ne(b, Vector2i(-1, -1), "a dry grass 2x2")
	if b == Vector2i(-1, -1):
		return null
	for dy in 2:
		for dx in 2:
			s.map.set_fertility(b.x + dx, b.y + dy, 100)
	var bid := s.place_building_instant("farm", b)
	assert_true(bid >= 0, "farm placed at %s" % b)
	return s.buildings.get(bid)


## Dig a pond right beside the farm's first tile: all four footprint tiles end up wet.
func _wet(farm: Building) -> void:
	s.set_terrain(farm.origin + Vector2i(-1, 0), "water")
	WaterSystem.recompute(s)


# The tier data carries the irrigation numbers; nothing here is a code constant.
func test_tier_ii_is_the_irrigated_farm_in_data() -> void:
	var def := reg.get_building("farm")
	assert_eq(def.tiers.size(), 2)
	var ii := def.tiers[0]
	assert_eq(ii.display_name, "Irrigated Farm")
	assert_true(ii.needs_wet, "the Irrigated Farm needs wet ground")
	assert_almost_eq(ii.wet_bonus, 1.5, 0.001, "x1.5 on top of the tier")
	assert_almost_eq(ii.multiplier, 1.5, 0.001, "the tier's own output factor")


# AC1: an Irrigated Farm on wet ground gets the tier x1.5 and the irrigation x1.5 (the plain x1.25 is replaced).
func test_irrigated_farm_gets_its_x1_5_when_wet() -> void:
	var farm := _dry_farm()
	if farm == null:
		return
	_wet(farm)
	assert_true(WaterSystem.footprint_wet(s, farm), "the pond waters at least half the footprint")
	var plain := prod.multiplier(s, farm)
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 1.25, 0.001, "a plain wet farm gets the plain x1.25")
	farm.tier = 2
	assert_eq(farm.display_name(reg), "Irrigated Farm")
	assert_almost_eq(farm.output_factor(reg), 1.5, 0.001, "the tier's own x1.5")
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 1.5, 0.001, "the irrigation x1.5")
	assert_almost_eq(prod.multiplier(s, farm) / plain, 1.8, 0.001,
			"1.5 x 1.5 without the x1.25 stacked on top (that would be 2.25)")


# AC2: an Irrigated Farm on dry ground produces nothing and stops with the "dry" halt reason.
func test_irrigated_farm_stops_when_dry() -> void:
	var farm := _dry_farm()
	if farm == null:
		return
	farm.tier = 2
	assert_false(WaterSystem.footprint_wet(s, farm), "nothing waters the footprint")
	assert_almost_eq(WaterSystem.wet_bonus(s, farm), 0.0, 0.001, "no wet ground, no production")
	assert_almost_eq(prod.multiplier(s, farm), 0.0, 0.001, "an Irrigated Farm produces nothing while dry")
	s.step_hours(1)
	assert_eq(farm.halt, "dry", "it stops with the dry reason")
	_wet(farm)
	s.step_hours(1)
	assert_ne(farm.halt, "dry", "wet ground lets it run again")


# The in-place upgrade to tier II is refused while the farm is dry, and allowed once it is wet.
func test_upgrading_to_irrigated_needs_a_wet_farm() -> void:
	var farm := _dry_farm()
	if farm == null:
		return
	assert_eq(s.can_upgrade(farm.id), {"ok": false, "reason": "needs_wet"})
	assert_false(s.upgrade(farm.id), "nothing starts on dry ground")
	_wet(farm)
	assert_eq(s.can_upgrade(farm.id), {"ok": true, "reason": ""}, "wet enough to upgrade")
