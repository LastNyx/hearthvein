extends GutTest
## Ticket 146: newcomers arrive at night on a lit road (spec .scratch/v1/night-shift-spec.md N9).
##
## At the night shift's start a newcomer may arrive on top of the day's, but only when the arrival point (the Hearth and
## the road tiles around it) is lit. Dark, they wait and a hint card says why. Day arrivals do not change.

const SEED := 42

var reg: DataRegistry
var _share: float = 0.0
var dir: String
var cfg: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	_share = reg.growth.night_arrival_share
	reg.growth.night_arrival_share = 1.0  # one newcomer per lit night, so one night is enough to see it
	dir = "/tmp/nyx-flash/hearthvein_arrivals_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	reg.growth.night_arrival_share = _share
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


## A settlement with growth on, Spirit high, a tent (3 free beds) and, when `lit`, a fuelled lamp by the Hearth.
func _town(lit: bool) -> Settlement:
	var s := Settlement.new_game(SEED, reg)
	s.spirit_override = 60.0
	var hs := s.map.hearth_spot
	for x in range(hs.x - 2, hs.x + 12):
		for y in range(hs.y - 4, hs.y + 4):
			if s.map.terrain_id_at(x, y) == "forest":
				s.set_terrain(Vector2i(x, y), "grass")
	assert_true(s.place_building_instant("tent", Vector2i(hs.x + 4, hs.y - 3)) >= 0)
	if lit:
		var bid := s.place_building_instant("lamp", Vector2i(hs.x + 4, hs.y + 2))
		assert_true(bid >= 0, "lamp placed")
		(s.buildings[bid] as Building).input_buffer.add("wood", 6.0)
	return s


func _to_hour(s: Settlement, hour: int) -> void:
	s.step_hours(posmod(hour - s.clock.hour(), 24))


func test_night_arrival_needs_a_lit_arrival_point() -> void:
	var lit := _town(true)
	_to_hour(lit, 19)
	var before := lit.citizens.size()
	_to_hour(lit, 21)
	assert_eq(lit.citizens.size(), before + 1, "a lit arrival point lets a newcomer in at night")
	assert_eq(lit.events.log_of("night_arrival_blocked").size(), 0)

	var dark := _town(false)
	_to_hour(dark, 19)
	before = dark.citizens.size()
	_to_hour(dark, 21)
	assert_eq(dark.citizens.size(), before, "no light, they wait outside")
	assert_eq(dark.events.log_of("night_arrival_blocked").size(), 1, "and the blocked arrival is announced")


func test_day_arrivals_do_not_depend_on_light() -> void:
	var dark := _town(false)
	var before := dark.citizens.size()
	_to_hour(dark, 18)  # before the night shift: only the day's immigration could have run
	assert_eq(dark.citizens.size(), before + 0, "no night arrival by day")
	dark.step_days(1)
	var g := dark.get_system(GrowthSystem) as GrowthSystem
	assert_eq(g.last_day["immigrated"], 1, "the day immigration still comes without a lamp")


func test_blocked_night_arrival_shows_the_hint_card() -> void:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	add_child_autofree(main)
	await wait_process_frames(2)
	main.start_new_game(42, false, false)
	await wait_process_frames(2)
	var cards := (main.get_node("Hud") as Hud).hint_cards
	main.settlement.events.emit("night_arrival_blocked", {})
	assert_eq(cards.current_id(), "night_arrival_blocked")
	var def := main.settlement.registry.hints["night_arrival_blocked"] as HintDef
	assert_eq(def.body, "Newcomers wait outside: light the road to the town.")
