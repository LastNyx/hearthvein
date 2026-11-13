extends GutTest
## Ticket 25b: region rewards (design.md section 4, D40).
##
## MapGen bakes the terrain part of each reward; buying the region applies the rest once: rich vein x1.5 Lumen for
## vein extractors in the region, old forest twice as fast regrowth, the spring's water in the wet pass, and the
## ruins payout (gold and/or refined goods) exactly once, even across a save/load. The fertile valley's soil is
## already generated and needs no purchase effect.

const SEED := 42
const SAVE_DIR := "/tmp/nyx-flash"
const SAVE_FILE := "hearthvein_ticket25b_save.dat"

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)


func _region_with_reward(kind: String) -> int:
	for r in MapState.REGION_COUNT:
		if s.map.get_region_reward(r) == kind:
			return r
	return -1


## Rebuilds `s` from the first seed (1..120) whose map carries `kind`. False when none does.
func _find_map_with(kind: String) -> bool:
	for seed in range(1, 121):
		s = Settlement.new_game(seed, reg)
		if _region_with_reward(kind) >= 0:
			return true
	return false


## First tile in the region's rect with the given terrain, (-1, -1) when there is none.
func _tile_in_region(r: int, terrain_id: String) -> Vector2i:
	var rect := MapState.region_rect(r)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if s.map.terrain_id_at(x, y) == terrain_id:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Buys every region on a 4-connected path from the owned set to r, in order. Returns the gold spent, or -1 when
## the path could not be bought.
func _own_region(r: int) -> int:
	if s.map.is_region_owned(r):
		return 0
	var prev := {}  # region -> region it was reached from (BFS from all owned regions)
	var queue: Array[int] = []
	for owned in MapState.REGION_COUNT:
		if s.map.is_region_owned(owned):
			queue.append(owned)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if cur == r:
			break
		for n in MapState.region_neighbours(cur):
			if s.map.is_region_owned(n) or prev.has(n):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(r):
		return -1
	var path: Array[int] = []
	var c := r
	while not s.map.is_region_owned(c):
		path.push_front(c)
		c = prev[c]
	var spent := 0
	for region in path:
		var price := s.next_region_price()
		if not s.buy_region(region):
			return -1
		spent += price
	return spent


func _owned_ruins() -> int:
	var n := 0
	for r in MapState.REGION_COUNT:
		if s.map.is_region_owned(r) and s.map.get_region_reward(r) == MapState.REWARD_RUINS:
			n += 1
	return n


# AC data: every reward number comes from data.
func test_reward_numbers_come_from_data() -> void:
	assert_eq(reg.regions.rich_vein_factor, 1.5, "design: rich vein x1.5")
	assert_eq(reg.regions.ruins_gold, 100, "design gives no number; the ticket chose 100 gold")
	assert_eq(reg.regions.ruins_goods, {})
	assert_eq(reg.forest.old_forest_regrow_factor, 0.5, "half the seasons = twice as fast")


# AC1 rich vein: x1.5 Lumen for vein extractors, only in an owned rich-vein region.
func test_rich_vein_applies_on_purchase_and_only_to_vein_extractors() -> void:
	assert_true(_find_map_with(MapState.REWARD_RICH_VEIN), "a map with a rich vein")
	var r := _region_with_reward(MapState.REWARD_RICH_VEIN)
	var vein := _tile_in_region(r, "lumen_vein")
	assert_ne(vein, Vector2i(-1, -1), "MapGen laid the rich-vein cluster")
	var tap := Building.new()
	tap.def = reg.get_building("lumen_tap")
	tap.origin = vein
	assert_eq(RegionSystem.rich_vein_modifier(s, tap), 1.0, "nothing until the region is bought")
	s.gold = 10000.0
	assert_true(_own_region(r) >= 0)
	assert_almost_eq(RegionSystem.rich_vein_modifier(s, tap), 1.5, 0.001)
	var prod := s.get_system(ProductionSystem) as ProductionSystem
	assert_true(prod.modifiers.has(RegionSystem.rich_vein_modifier), "registered as a production modifier")
	var forager := Building.new()
	forager.def = reg.get_building("forager")
	forager.origin = vein
	assert_eq(RegionSystem.rich_vein_modifier(s, forager), 1.0, "not a vein extractor")


func test_rich_vein_does_not_apply_in_another_region() -> void:
	var tap := Building.new()
	tap.def = reg.get_building("lumen_tap")
	tap.origin = s.map.hearth_spot
	assert_eq(RegionSystem.rich_vein_modifier(s, tap), 1.0, "the start region has no rich vein")


# AC1 old forest: stumps in an owned old-forest region regrow in one season instead of two.
func test_old_forest_regrows_twice_as_fast() -> void:
	assert_true(_find_map_with(MapState.REWARD_OLD_FOREST), "a map with an old forest")
	var r := _region_with_reward(MapState.REWARD_OLD_FOREST)
	var t := _tile_in_region(r, "forest")
	assert_ne(t, Vector2i(-1, -1), "MapGen laid the old-forest blob")
	s.set_terrain(t, "stump")
	assert_eq(RegionSystem.regrow_factor(s, t), 1.0, "nothing until the region is bought")
	s.gold = 10000.0
	assert_true(_own_region(r) >= 0)
	assert_almost_eq(RegionSystem.regrow_factor(s, t), reg.forest.old_forest_regrow_factor, 0.001)
	var fs := s.get_system(ForestSystem) as ForestSystem
	assert_true(fs.regrow_factors.has(RegionSystem.regrow_factor), "registered as a regrowth hook")
	s.step_days(GameClock.DAYS_PER_SEASON)
	assert_eq(s.map.terrain_id_at(t.x, t.y), "forest", "one season is enough with the reward")


# AC1 spring: the spring water is in the wet map after the purchase, and the base cache rebuilt.
func test_spring_is_water_and_wet_after_purchase() -> void:
	assert_true(_find_map_with(MapState.REWARD_SPRING), "a map with a spring")
	var r := _region_with_reward(MapState.REWARD_SPRING)
	var pos := s.map.region_reward_pos[r]
	# MapGen already wrote the spring's 2x2 water. Clear it so the purchase has to put it back, which proves the
	# spring path (and the water_version bump that rebuilds WaterSystem's base mask).
	for dy in 2:
		for dx in 2:
			s.set_terrain(pos + Vector2i(dx, dy), "grass")
	var v := s.map.water_version
	s.gold = 10000.0
	assert_true(_own_region(r) >= 0)
	for dy in 2:
		for dx in 2:
			assert_eq(s.map.terrain_id_at(pos.x + dx, pos.y + dy), "water", "spring tile (%d,%d)" % [dx, dy])
	assert_true(s.map.is_wet(pos.x, pos.y), "the wet pass counts the spring")
	assert_gt(s.map.water_version, v, "the cached water base must rebuild")


# AC1 fertile valley: MapGen already laid the fertile soil patch; buying only reveals it.
func test_fertile_valley_is_already_on_the_map() -> void:
	assert_true(_find_map_with(MapState.REWARD_FERTILE_VALLEY), "a map with a fertile valley")
	var r := _region_with_reward(MapState.REWARD_FERTILE_VALLEY)
	var pos := s.map.region_reward_pos[r]
	var before := 0
	for y in range(pos.y - 5, pos.y + 6):
		for x in range(pos.x - 5, pos.x + 6):
			if MapState.in_bounds(x, y) and s.map.terrain_id_at(x, y) == "fertile_soil":
				before += 1
	assert_gt(before, 0, "MapGen laid fertile soil around the marker")
	s.gold = 10000.0
	assert_true(_own_region(r) >= 0)
	var after := 0
	for y in range(pos.y - 5, pos.y + 6):
		for x in range(pos.x - 5, pos.x + 6):
			if MapState.in_bounds(x, y) and s.map.terrain_id_at(x, y) == "fertile_soil":
				after += 1
	assert_eq(after, before, "purchase neither adds nor removes the fertile patch")


# AC1+AC2 ruins: the payout lands on purchase and never lands again.
func test_ruins_pays_once_on_purchase() -> void:
	assert_true(_find_map_with(MapState.REWARD_RUINS), "a map with ruins")
	var r := _region_with_reward(MapState.REWARD_RUINS)
	s.gold = 10000.0
	var spent := _own_region(r)
	assert_true(spent >= 0, "the ruins region was bought")
	assert_almost_eq(s.gold, 10000.0 - float(spent) + float(_owned_ruins() * reg.regions.ruins_gold), 0.001,
			"prices spent, one ruins payout (a path region may carry ruins too)")
	var after := s.gold
	var rs := s.get_system(RegionSystem) as RegionSystem
	assert_eq(rs.apply_rewards(s, r), "", "already applied")
	assert_eq(s.gold, after, "the ruins never pay twice")
	assert_eq(s.events.log_of("region_reward").size(), _owned_rewards(), "one reward event per bought reward region")


func _owned_rewards() -> int:
	var n := 0
	for i in MapState.REGION_COUNT:
		if s.map.is_region_owned(i) and s.map.get_region_reward(i) != "":
			n += 1
	return n


## The claim survives a save: the loaded settlement does not pay the ruins a second time.
func test_ruins_does_not_pay_again_after_a_save() -> void:
	assert_true(_find_map_with(MapState.REWARD_RUINS), "a map with ruins")
	var r := _region_with_reward(MapState.REWARD_RUINS)
	s.gold = 10000.0
	assert_true(_own_region(r) >= 0)
	var after := s.gold
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(SAVE_FILE)
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	DirAccess.remove_absolute(path)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	var rs := loaded.get_system(RegionSystem) as RegionSystem
	assert_eq(rs.apply_rewards(loaded, r), "", "the loaded claim says it was paid")
	assert_eq(loaded.gold, after, "no second payout")


## Ruins goods go into the nearest storage with room; the data row decides which and how many.
func test_ruins_goods_are_stored() -> void:
	var rd := RegionsDef.new()
	rd.ruins_gold = 0
	rd.ruins_goods = {"planks": 5}
	var before := float(s.totals().get("planks", 0.0))
	RegionSystem.pay_ruins(s, rd, s.map.hearth_spot)
	assert_almost_eq(float(s.totals().get("planks", 0.0)), before + 5.0, 0.001, "planks reached the Hearth")


func test_ruins_gold_is_paid() -> void:
	var rd := RegionsDef.new()
	rd.ruins_gold = 25
	rd.ruins_goods = {}
	var before := s.gold
	RegionSystem.pay_ruins(s, rd, s.map.hearth_spot)
	assert_almost_eq(s.gold, before + 25.0, 0.001)
