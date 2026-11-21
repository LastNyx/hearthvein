extends GutTest
## Ticket 137: the gain popup (+N with the good's icon). The spawn rules (throttle, merge, whole units, the def's
## gain_popup flag, the settings switch, the far zoom) and the read-only use of the ledger's made goods.

var reg: DataRegistry
var s: Settlement


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(42, reg)


# AC1: throttle (one popup per 3 s per key), merge (the held amounts show together), whole units only, no popup for
# a def without the flag, none with the setting off, and none at the farthest zoom.
func test_popup_spawn_rules() -> void:
	var m := GainPopupModel.new()
	# Whole units only: a fraction below one stays held.
	m.note(1, "wood", 0.4, Vector2(4, 4))
	assert_eq(m.spawned, 0, "less than one unit spawns nothing")
	m.note(1, "wood", 0.7, Vector2(4, 4))
	assert_eq(m.spawned, 1, "crossing a whole unit spawns one popup")
	assert_eq(int(m.popups().back()["units"]), 1, "the popup shows the whole units only")
	assert_eq(str(m.popups().back()["good"]), "wood", "the popup names its good")
	# Throttle: inside the same 3 s window nothing new spawns, however much is made.
	m.note(1, "wood", 5.0, Vector2(4, 4))
	assert_eq(m.spawned, 1, "no second popup inside the same 3 s")
	m.tick(2.9)
	assert_eq(m.spawned, 1, "still inside the window")
	# Merge: the held 5 units (plus the 0.1 remainder) show together once the window opens.
	m.tick(0.2)
	assert_eq(m.spawned, 2, "the next window opens")
	assert_eq(int(m.popups().back()["units"]), 5, "the held amounts merge into one popup")
	# A different key (another building) has its own throttle.
	m.note(2, "stone", 2.0, Vector2(6, 6))
	assert_eq(m.spawned, 3, "another building pops at once")
	assert_eq(str(m.popups().back()["good"]), "stone", "it shows its own good")
	# The settings switch off: nothing spawns.
	var st := GameSettings.new()
	st.gain_popups = false
	var off := GainPopupModel.new()
	off.settings = st
	off.note(3, "wood", 9.0, Vector2(4, 4))
	off.tick(9.0)
	assert_eq(off.spawned, 0, "setting off spawns nothing")
	# The def's gain_popup flag: Woodcutter and Quarry opt in, a plain producer and a Clear tile do not.
	assert_true(GainPopupView.gain_source(s, "woodcutter"), "Woodcutter opts in")
	assert_true(GainPopupView.gain_source(s, "quarry"), "Quarry opts in")
	assert_false(GainPopupView.gain_source(s, "farm"), "a def without the flag is no source")
	assert_false(GainPopupView.gain_source(s, "clear_grass"), "clearing plain grass yields nothing")
	assert_true(GainPopupView.gain_source(s, "clear_forest"), "a Clear yield pops over its tile")
	# Far zoom hides the popups; every closer zoom shows them.
	assert_false(GainPopupView.shown_at_zoom(CameraController.ZOOM_STEPS[0]), "hidden at the farthest zoom")
	for i in range(1, CameraController.ZOOM_STEPS.size()):
		assert_true(GainPopupView.shown_at_zoom(CameraController.ZOOM_STEPS[i]), "shown at zoom step %d" % i)


# AC2: a popup run reads the ledger's made goods and leaves the sim exactly as it was.
func test_popups_never_touch_sim_state() -> void:
	ResourceLedgerSystem.record_made(s, "wood", 4.0, "woodcutter")
	var ledger := s.get_system(ResourceLedgerSystem) as ResourceLedgerSystem
	var before := {
		"made": ledger.made_today.duplicate(true),
		"made_by": ledger.made_by_today.duplicate(true),
		"used": ledger.used_today.duplicate(true),
		"gold": s.gold,
		"totals": s.totals().duplicate(true),
		"buildings": s.buildings.size(),
		"log": s.events.log.size(),
	}
	var gains := GainPopupView.made_since(s, {})
	assert_eq(gains.size(), 1, "the made wood is seen")
	assert_eq(str(gains[0]["good"]), "wood", "with its good")
	assert_eq(float(gains[0]["amount"]), 4.0, "and its amount")
	var m := GainPopupModel.new()
	for g in gains:
		if GainPopupView.gain_source(s, str(g["def_id"])):
			m.note(str(g["def_id"]), str(g["good"]), float(g["amount"]), Vector2(4, 4))
	m.tick(4.0)
	assert_eq(m.spawned, 1, "a popup spawned from the ledger entry")
	var after := {
		"made": ledger.made_today.duplicate(true),
		"made_by": ledger.made_by_today.duplicate(true),
		"used": ledger.used_today.duplicate(true),
		"gold": s.gold,
		"totals": s.totals().duplicate(true),
		"buildings": s.buildings.size(),
		"log": s.events.log.size(),
	}
	assert_eq(after, before, "the popups leave every sim value alone")
