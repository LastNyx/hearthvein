extends SceneTree
## Regenerates test/fixtures/save_v0.dat, the version-0 save used by test/test_save_migration.gd.
## Run from the repo root: godot --headless --path . -s tools/make_v0_fixture.gd
##
## v0 is the v1 state with two differences: the settlement's gold key was called "coins", and the Spirit system kept
## no saved state yet. The fixture is a fresh, deterministic game (gold set to a non-zero value so the test can see
## the rename), so re-running this script makes the same state again.

const SEED := 42
const PATH := "res://test/fixtures/save_v0.dat"
const GOLD := 123.5


func _init() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var s := Settlement.new_game(SEED, reg)
	s.gold = GOLD
	var state := s.to_dict()
	state["coins"] = state["gold"]
	state.erase("gold")
	(state["systems"] as Dictionary).erase("spirit")
	var f := FileAccess.open_compressed(PATH, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("make_v0_fixture: cannot write %s (error %d)" % [PATH, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_var({"version": 0, "state": state}, false)
	var err := f.get_error()
	f.close()
	if err != OK:
		push_error("make_v0_fixture: write to %s failed (error %d)" % [PATH, err])
		quit(1)
		return
	print("wrote %s" % PATH)
	quit()
