extends GutTest
## Ticket 109: the resource ledger (made and used per good per day, 60-day stock history, saved).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var ledger: ResourceLedgerSystem
var h: Vector2i
var dir: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


## Godot's get_temp_dir() ignores TMPDIR; the sandbox only allows writes under it, so prefer the env value.
func _temp_base() -> String:
	var base := OS.get_environment("TMPDIR")
	return base if base != "" else OS.get_temp_dir()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	ledger = s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	h = s.map.hearth_spot
	# Seed 42 has forest right east of the Hearth: clear a strip for the road and the buildings beside it.
	for x in range(h.x + 2, h.x + 16):
		for y in range(h.y - 3, h.y + 3):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
		s.place_road(Vector2i(x, h.y))
	dir = _temp_base().path_join("hv_109_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## Places a finished building beside the road (north of it), `dx` tiles east of the Hearth.
func _put(id: String, dx: int) -> Building:
	var def := reg.get_building(id)
	var bid := s.place_building_instant(id, Vector2i(h.x + dx, h.y - def.size.y))
	assert_true(bid >= 0, "%s placed" % id)
	return s.buildings.get(bid)


## A woodcutter with forest in its radius, the way test_hauling sets one up.
func _woodcutter() -> Building:
	var w := _put("woodcutter", 4)
	for dy in [-4, -3]:
		for dx in range(-2, 3):
			s.set_terrain(Vector2i(h.x + 4 + dx, h.y + dy), "forest")
	return w


# AC1: a woodcutter's wood shows up as made, by its def id, for the day.
func test_a_woodcutter_makes_wood_attributed_to_its_def() -> void:
	_woodcutter()
	s.step_days(2)
	var y := ledger.yesterday("wood")
	assert_gt(y["made"], 0.0, "the woodcutter made wood yesterday")
	assert_gt(float(y["made_by"].get("woodcutter", 0.0)), 0.0, "the made wood is attributed to the woodcutter def")
	assert_almost_eq(float(y["made_by"].get("woodcutter", 0.0)), y["made"], 0.001,
			"the woodcutter is the only wood source here")


# AC2: eating and site delivery show up as used.
func test_eating_and_site_delivery_are_used() -> void:
	s.step_days(1)  # day 1's eating runs at the day boundary
	assert_gt(ledger.today("food")["used"], 0.0, "citizens ate")
	# A tent site (5 wood) hauled from the Hearth's start stock: goods built into a site are used, not moved.
	var bid := s.place_building("tent", Vector2i(h.x + 6, h.y - 1))
	assert_true(bid >= 0, "tent site placed")
	var site: Building = s.buildings[bid]
	for i in 24:
		s.step_hours(1)
		if site.site_delivered():
			break
	assert_true(site.site_delivered(), "the site got its wood")
	assert_gt(ledger.today("wood")["used"], 0.0, "wood delivered into the site is used")


# AC3: history keeps 60 samples, oldest dropped.
func test_history_keeps_the_newest_sixty_samples() -> void:
	for i in 65:
		s.gold = float(i)
		ledger.on_day_started({}, s)
	var gold := ledger.history("gold")
	assert_eq(gold.size(), ResourceLedgerSystem.HISTORY_DAYS, "60 samples kept")
	assert_eq(gold[0], 5.0, "the first five samples dropped off")
	assert_eq(gold[gold.size() - 1], 64.0, "newest sample last")


# AC4: save round trip keeps the ledger; a v4 save loads with an empty one.
func test_save_round_trip_keeps_the_ledger() -> void:
	_woodcutter()
	s.step_days(2)
	var path := dir.path_join("ledger.dat")
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	var l := loaded.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	assert_not_null(l)
	assert_almost_eq(l.yesterday("wood")["made"], ledger.yesterday("wood")["made"], 0.001, "yesterday's made wood")
	assert_eq(l.yesterday("wood")["made_by"], ledger.yesterday("wood")["made_by"], "yesterday's made-by breakdown")
	assert_almost_eq(l.today("food")["used"], ledger.today("food")["used"], 0.001, "today's eaten food")
	assert_eq(l.history("food"), ledger.history("food"), "the stock history")
	assert_eq(l.history("wood"), ledger.history("wood"), "the wood history")


# AC1 (ticket 124): what used each good, by reason, and for production the building that ate it; all of it survives a
# save, and an old save loads with no breakdown.
func test_used_by_reason_and_building_survive_a_save() -> void:
	s.era_override = "village"
	s.hearth.inventory.add("wood", 150.0)
	s.hearth.inventory.add("food", 200.0)
	var saw := _put("sawmill", 4)
	assert_true(saw.connected, "the sawmill is road-connected")
	s.step_days(8)
	var by: Dictionary = ledger.used_breakdown("wood")
	assert_gt(float(by.get("production:sawmill", 0.0)), 0.0, "the sawmill's wood use is attributed to it")
	assert_gt(float(ledger.used_breakdown("food").get("eaten", 0.0)), 0.0, "eating is a reason")
	var path := dir.path_join("used.dat")
	assert_eq(SaveGame.save(s, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded, "the save loads")
	if loaded == null:
		return
	var lb: Dictionary = (loaded.get_system(ResourceLedgerSystem) as ResourceLedgerSystem).used_breakdown("wood")
	assert_eq(lb.keys(), by.keys(), "the same reasons survive the save")
	for k: String in by:
		assert_almost_eq(float(lb.get(k, 0.0)), float(by[k]), 0.001, "the amount for %s survives" % k)
	var state := s.to_dict()
	(state["systems"] as Dictionary).erase("ledger")
	var old_path := dir.path_join("old.dat")
	assert_eq(SaveGame.write_payload({"version": 4, "state": state}, old_path), OK)
	var old := SaveGame.load(old_path, reg)
	assert_not_null(old, "the old save loads")
	if old == null:
		return
	assert_eq((old.get_system(ResourceLedgerSystem) as ResourceLedgerSystem).used_breakdown("wood"), {},
			"an old save has no used-by breakdown")


func test_a_v4_save_loads_with_an_empty_ledger() -> void:
	s.step_days(1)
	var state := s.to_dict()
	(state["systems"] as Dictionary).erase("ledger")
	var path := dir.path_join("v4.dat")
	assert_eq(SaveGame.write_payload({"version": 4, "state": state}, path), OK)
	var loaded := SaveGame.load(path, reg)
	assert_not_null(loaded, "the v4 save loads")
	if loaded == null:
		return
	assert_eq(loaded.clock.total_hours, s.clock.total_hours)
	var l := loaded.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	assert_not_null(l)
	assert_eq(l.today("food"), {"made": 0.0, "used": 0.0, "made_by": {}}, "today is empty")
	assert_eq(l.yesterday("food"), {"made": 0.0, "used": 0.0, "made_by": {}}, "yesterday is empty")
	var empty: Array[float] = []
	assert_eq(l.history("food"), empty, "no history")
