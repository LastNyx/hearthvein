extends GutTest
## Ticket 20: Cottage and Farm with fertility output (design.md sections 9 and 16).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var h: Vector2i


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	# Production-only tests: no eating of the food made and no hauling out of the door buffers.
	s.systems.erase(s.get_system(GrowthSystem))
	s.systems.erase(s.get_system(HaulingSystem))
	h = s.map.hearth_spot


func _free_spot(def_id: String) -> Vector2i:
	for y in range(MapState.HEIGHT - 3):
		for x in range(MapState.WIDTH - 3):
			if s.can_place(def_id, Vector2i(x, y), true)["ok"]:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## A cleared, road-connected strip east of the Hearth (same patch test_hauling uses), so farms are staffed and
## their doors sit on the road.
func _strip() -> void:
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## Places a finished Farm with its origin north (side -1) or south (side 1) of the road at the same x, so both
## commute identically. `fertilities` is the four footprint tile values in row-major order; only the origin tile
## gets `origin_terrain`, the rest is grass.
func _farm(side: int, origin_terrain: String, fertilities: Array) -> Building:
	var o := Vector2i(h.x + 4, h.y - 2 if side < 0 else h.y + 1)
	var i := 0
	for y in 2:
		for x in 2:
			var t := o + Vector2i(x, y)
			s.set_terrain(t, origin_terrain if t == o else "grass")
			s.map.set_fertility(t.x, t.y, int(fertilities[i]))
			i += 1
	var bid := s.place_building_instant("farm", o)
	assert_true(bid >= 0, "farm placed at %s" % o)
	return s.buildings.get(bid)




# AC1: Cottage houses 4, and both buildings are data-driven Village unlocks.
func test_cottage_houses_four() -> void:
	var def := reg.get_building("cottage")
	assert_eq(def.era, "village")
	assert_eq(def.size, Vector2i(1, 1))
	assert_eq(def.cost, {"wood": 10, "stone": 5})
	assert_eq(def.housing_beds, 4)
	var before := s.beds_total()
	var o := _free_spot("cottage")
	assert_true(o.x >= 0, "a free tile for the Cottage")
	assert_gt(s.place_building_instant("cottage", o), -1)
	assert_eq(s.beds_total(), before + 4)


func test_cottage_and_farm_are_locked_in_camp() -> void:
	s.era_override = ""
	var cottage_o := _free_spot("cottage")
	var farm_o := _free_spot("farm")
	assert_eq(s.can_place("cottage", cottage_o), {"ok": false, "reason": "era_locked"})
	assert_eq(s.can_place("farm", farm_o), {"ok": false, "reason": "era_locked"})
	s.era_override = "village"
	assert_true(s.can_place("cottage", cottage_o)["ok"])
	assert_true(s.can_place("farm", farm_o)["ok"])
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("cottage") and ids.has("farm"))


# AC2a: Farm output follows the mean fertility of its 2x2 footprint.
func test_farm_output_follows_footprint_fertility() -> void:
	_strip()
	s.systems.erase(s.get_system(HaulingSystem))  # read the door buffers as filled, nobody empties them
	var farm := reg.get_building("farm")
	assert_eq([farm.size, farm.cost, farm.worker_slots], [Vector2i(2, 2), {"wood": 21, "stone": 9}, 3])
	assert_eq(farm.recipe.outputs, {"crops": 6.0})
	var rich := _farm(-1, "grass", [100, 100, 100, 100])
	var mixed := _farm(1, "grass", [100, 100, 0, 0])  # mean 50, half of the rich farm
	s.step_days(1)  # let both crews walk to work
	rich.door_buffer.remove("crops", 100.0)  # the buffers caps at 20: start both from empty
	mixed.door_buffer.remove("crops", 100.0)
	var r0 := 0.0
	var m0 := 0.0
	s.step_days(1)
	var a := rich.door_buffer.amount_of("crops") - r0
	var b := mixed.door_buffer.amount_of("crops") - m0
	assert_gt(b, 0.0, "the lean farm still makes food")
	assert_between(a / b, 1.9, 2.1, "rich %f vs mixed %f" % [a, b])


# AC2b: x1.5 when the origin tile started as fertile soil.
func test_farm_fertile_origin_bonus() -> void:
	_strip()
	s.systems.erase(s.get_system(HaulingSystem))
	assert_eq(reg.get_building("farm").fertile_origin_bonus, 1.5)
	var plain := _farm(-1, "grass", [100, 100, 100, 100])
	var fertile := _farm(1, "fertile_soil", [100, 100, 100, 100])
	s.step_days(1)  # let both crews walk to work
	plain.door_buffer.remove("crops", 100.0)  # the buffers cap at 20: start both from empty
	fertile.door_buffer.remove("crops", 100.0)
	var p0 := 0.0
	var f0 := 0.0
	s.step_days(1)
	var a := plain.door_buffer.amount_of("crops") - p0
	var b := fertile.door_buffer.amount_of("crops") - f0
	assert_gt(a, 0.0, "the plain farm still makes food")
	assert_gt(b / a, 1.2, "plain %f vs fertile origin %f (the door buffer caps at 20, so the x1.5 shows only in part)" % [a, b])
	assert_lt(b, 20.001, "capped by the door buffer")
