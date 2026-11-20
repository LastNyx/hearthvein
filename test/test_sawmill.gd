extends GutTest
## Ticket 24: Sawmill, planks and the Builder's Yard (design.md sections 6-8 and 16 Village, D38, D48).
## The two data rows, planks made from hauled wood through the real systems, and extra builders.

const SEED := 42

var reg: DataRegistry


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


## A cleared, road-connected strip east of the Hearth (the same patch test_hauling uses).
func _strip(s: Settlement) -> void:
	var h := s.map.hearth_spot
	for x in range(h.x + 2, h.x + 18):
		for y in range(h.y - 4, h.y + 5):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))


## Places a finished building north of the road, `dx` tiles east of the Hearth.
func _put(s: Settlement, id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var origin := Vector2i(s.map.hearth_spot.x + dx, s.map.hearth_spot.y - def.size.y)
	var bid := s.place_building_instant(id, origin)
	assert_true(bid >= 0, "%s placed at %s" % [id, origin])
	var b: Building = s.buildings.get(bid)
	assert_true(b.connected, "%s is connected to the Hearth by road" % id)
	return b


## Two construction sites north of the road whose cost is already delivered (hauling is ticket 11's test).
func _ready_sites(s: Settlement) -> Array[Building]:
	var out: Array[Building] = []
	var dx := 4
	for i in 2:
		var def := reg.get_building("tent")
		var origin := Vector2i(s.map.hearth_spot.x + dx, s.map.hearth_spot.y - def.size.y)
		var bid := s.place_building("tent", origin)
		assert_true(bid >= 0, "tent site placed at %s" % origin)
		var b: Building = s.buildings.get(bid)
		for g in def.cost:
			if g != BuildingDef.GOLD:
				b.input_buffer.add(g, float(def.cost[g]))
		assert_true(b.site_delivered(), "the site's cost is in")
		out.append(b)
		dx += 2
	s.refresh_population()  # builder slots only open for ready sites
	return out


func _builders(s: Settlement) -> int:
	var n := 0
	for cid in s.citizens:
		if (s.citizens[cid] as Citizen).job_kind == Citizen.JOB_BUILD:
			n += 1
	return n


## Game hours until both sites are finished (-1 when they still stand after `max_days`).
func _hours_until_both_built(s: Settlement, sites: Array[Building], max_days: int) -> int:
	for i in max_days * 24:
		if not sites[0].site and not sites[1].site:
			return i
		s.step_hours(1)
	return -1


# AC1a: both rows match the Village table and the recipe is 2 wood -> 1 plank, 3/worker/day.
func test_data_matches_the_village_table() -> void:
	var saw := reg.get_building("sawmill")
	assert_not_null(saw)
	assert_eq([saw.era, saw.category], ["village", "refining"])
	assert_eq([saw.size, saw.cost, saw.worker_slots], [Vector2i(2, 1), {"wood": 14, "stone": 21}, 2])
	assert_eq(saw.recipe.inputs, {"wood": 6.0}, "2 per plank x 3 planks a worker-day")
	assert_eq(saw.recipe.outputs, {"planks": 3.0})
	assert_false(saw.upgradable, "design section 10: refiners do not upgrade")
	assert_eq(reg.get_good("planks").kind, "refined")
	var yard := reg.get_building("builders_yard")
	assert_not_null(yard)
	assert_eq([yard.era, yard.size, yard.cost], ["village", Vector2i(2, 1), {"wood": 21, "stone": 9}])
	assert_eq([yard.builder_slots, yard.hauler_slots, yard.worker_slots], [4, 2, 0])


func test_both_are_village_buildings() -> void:
	var s := Settlement.new_game(SEED, reg)
	var ids: Array = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_false(ids.has("sawmill") or ids.has("builders_yard"), "locked in Camp")
	s.era_override = "village"
	ids = s.unlocked_buildings().map(func(b: BuildingDef) -> String: return b.id)
	assert_true(ids.has("sawmill") and ids.has("builders_yard"))


# AC1b: end to end. Haulers bring wood to the Sawmill, planks are made and hauled into storage, and the
# Hearth loses two wood for every plank that arrives.
func test_sawmill_consumes_hauled_wood_and_planks_reach_storage() -> void:
	var s := Settlement.new_game(SEED, reg)
	s.era_override = "village"
	_strip(s)
	s.hearth.inventory.add("wood", 400.0)  # clamped to the Hearth's 150
	s.hearth.inventory.add("stone", 400.0)  # clamped to the Hearth's 150
	s.hearth.inventory.add("food", 200.0)  # no starving workers skewing the rate
	var saw := _put(s, "sawmill", 4)
	s.step_days(3)  # the crew walks to work and haulers fill the two-day input buffer
	assert_gt(saw.input_buffer.amount_of("wood"), 10.0, "wood was hauled to the Sawmill")
	var before_m := s.hearth.inventory.amount_of("wood")
	var before_p := s.hearth.inventory.amount_of("planks")
	s.step_days(5)
	var planks := s.hearth.inventory.amount_of("planks") - before_p
	var used := before_m - s.hearth.inventory.amount_of("wood")
	assert_gt(planks, 0.0, "planks reached the Hearth's storage")
	assert_between(planks / 5.0, 5.0, 6.4, "two workers x 3 planks a day")
	assert_between(used / planks, 1.9, 2.1, "2 wood per plank")
	assert_eq(saw.halt, "", "the Sawmill kept running")
	assert_eq(s.totals().get("planks", 0.0), s.hearth.inventory.amount_of("planks"), "planks are a real stored good")


# AC2: two ready sites take about twice as long with only the Hearth's four builders; a Builder's Yard adds four
# more, so both sites get a full crew and are built at the same time.
func test_builders_yard_builds_two_sites_in_parallel() -> void:
	var crew := reg.logistics.builder_crew
	var small := reg.logistics.small_town_pop
	reg.logistics.small_town_pop = 0  # the small-town rule (118) staffs the builders first, this is about the Yard's slots
	reg.logistics.builder_crew = 4  # a crew of 4 fills the Hearth; the data has 2 since 118, which two sites fit on the Hearth alone
	var plain := Settlement.new_game(SEED, reg)
	plain.era_override = "village"
	_strip(plain)
	var a := _ready_sites(plain)
	assert_eq(_builders(plain), 4, "the Hearth's builder slots only")
	var plain_hours := _hours_until_both_built(plain, a, 10)

	var yarded := Settlement.new_game(SEED, reg)
	yarded.era_override = "village"
	_strip(yarded)
	var b := _ready_sites(yarded)
	_put(yarded, "builders_yard", 10)
	for i in 4:
		yarded.add_citizen()  # enough people to fill the extra slots
	_put(yarded, "cottage", 13)  # and a home for them, so no homeless penalty slows the Yard side
	yarded.refresh_population()
	assert_eq(_builders(yarded), 8, "four Hearth builders plus four from the Yard")
	var yard_hours := _hours_until_both_built(yarded, b, 10)

	assert_gt(plain_hours, 0, "both sites finish without a Yard")
	assert_gt(yard_hours, 0, "both sites finish with a Yard")
	assert_lt(float(yard_hours), float(plain_hours) * 0.8,  # 0.7 before 118: crews now walk site to site, which helps the plain case more
			"a Yard builds the two sites together (%d h vs %d h)" % [yard_hours, plain_hours])
	reg.logistics.builder_crew = crew
	reg.logistics.small_town_pop = small
