extends SceneTree
## Headless: godot --headless --path . -s tools/find_tutorial_seed.gd [-- first_seed count]
## Scans seeds with the real MapGen and prints the first few that pass TutorialSeedCheck (ticket 79), with their
## distances. Put the pick into data/mapgen/mapgen.tres (tutorial_seed). A tool, not a test.


func _init() -> void:
	var reg := DataRegistry.new()
	reg.load_all()
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var want := int(args[1]) if args.size() > 1 else 5
	var found := 0
	var sd := first
	while found < want and sd < first + 5000:
		var m := MapGen.generate(sd, reg)
		var r := TutorialSeedCheck.measure(m, reg)
		if r["ok"]:
			found += 1
			print("seed %d: %s hearth %s" % [sd, r, m.hearth_spot])
		sd += 1
	print("scanned %d..%d, %d found" % [first, sd - 1, found])
	quit()
