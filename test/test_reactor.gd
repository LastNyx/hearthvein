extends GutTest
## Ticket 33b: Lumen Reactor (design.md sections 12, 14 and 16 City).
## The City row (2x2 on a vein, +10 Lumen per worker-day), its Dimming multiplier (x0.6, not the vein x0.25) and
## its blight (radius 6, every 2 days). The row's data checks live with the other City rows in
## test_city_buildings.gd; this file covers the behaviour behind those numbers.

const SEED := 42
const DAY := GameClock.HOURS_PER_DAY
const WINTER := 3 * GameClock.DAYS_PER_SEASON

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "city"
	s.planet_health_override = 100.0


## An origin whose 2x2 footprint covers a vein and fits the start region.
func _vein_spot() -> Vector2i:
	var def := reg.get_building("lumen_reactor")
	for y in MapState.HEIGHT - 1:
		for x in MapState.WIDTH - 1:
			var o := Vector2i(x, y)
			if not s.can_place("lumen_reactor", o, true)["ok"]:
				continue
			for fy in range(o.y, o.y + def.size.y):
				for fx in range(o.x, o.x + def.size.x):
					if s.map.terrain_id_at(fx, fy) == "lumen_vein":
						return o
	return Vector2i(-1, -1)


## Feeds everyone so the population (and the light need) stays put while the clock runs to a day.
func _to_day(day: int) -> void:
	while s.clock.total_hours < day * DAY:
		s.hearth.inventory.add("food", 20.0)
		s.step_hours(mini(DAY, day * DAY - s.clock.total_hours))


func _within(t: Vector2i, b: Building, r: int) -> bool:
	for ft in b.tiles():
		var d := t - ft
		if d.x * d.x + d.y * d.y <= r * r:
			return true
	return false


# AC1: during a Dimming a Reactor runs at x0.6 while an ordinary vein extractor runs at x0.25 (data, not code).
func test_reactor_uses_its_own_dimming_multiplier() -> void:
	var reactor := Building.new()
	reactor.def = reg.get_building("lumen_reactor")
	var tap := Building.new()
	tap.def = reg.get_building("lumen_tap")
	_to_day(WINTER - 1)
	assert_eq(DimmingSystem.output_modifier(s, reactor), 1.0, "no Dimming yet")
	assert_eq(DimmingSystem.output_modifier(s, tap), 1.0)
	_to_day(WINTER)
	assert_true(DimmingSystem.is_active(s))
	assert_eq(DimmingSystem.output_modifier(s, reactor), 0.6, "the Reactor's data factor")
	assert_eq(DimmingSystem.output_modifier(s, tap), 0.25, "an ordinary extractor still takes the planet factor")
	assert_true(s.get_system(ProductionSystem).modifiers.has(DimmingSystem.output_modifier),
			"production asks the Dimming system")


# AC2: a finished Reactor blights one tile every 2 days inside radius 6.
func test_reactor_blights_radius_6_every_2_days() -> void:
	var o := _vein_spot()
	assert_ne(o, Vector2i(-1, -1), "a 2x2 vein spot on seed 42")
	var id := s.place_building_instant("lumen_reactor", o)
	assert_gt(id, -1)
	var b: Building = s.buildings[id]
	assert_false(b.site)
	assert_eq(BlightSystem.count(s), 0)
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 0, "nothing before the 2nd day")
	s.step_days(1)
	assert_eq(BlightSystem.count(s), 1)
	for y in MapState.HEIGHT:
		for x in MapState.WIDTH:
			if s.map.is_blighted(x, y):
				assert_true(_within(Vector2i(x, y), b, 6), "inside radius 6 of the footprint")
	assert_eq(BlightSystem.count(s), 1)
	s.step_days(2)
	assert_eq(BlightSystem.count(s), 2, "one more tile on day 4")


# The world needs the vein spots for both extractors; a Reactor still refuses dry ground.
func test_reactor_places_only_on_a_vein() -> void:
	var o := _vein_spot()
	assert_ne(o, Vector2i(-1, -1), "a 2x2 vein spot on seed 42")
	assert_true(s.can_place("lumen_reactor", o)["ok"])
	var dry := Vector2i(-1, -1)
	for y in 2:
		for x in 2:
			var t := Vector2i(s.map.hearth_spot.x + 3 + x, s.map.hearth_spot.y - 3 + y)
			if dry.x < 0 and s.can_place("lumen_reactor", t)["reason"] == "needs_vein":
				dry = t
	assert_ne(dry, Vector2i(-1, -1), "grass near the Hearth")
	assert_false(s.can_place("lumen_reactor", dry)["ok"])
