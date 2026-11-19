extends GutTest
## Ticket 107: the day and night map tint (DayNight helpers, DayNightDef data) and its Settings toggle.

var reg: DataRegistry
var def: DayNightDef
var dir: String


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


## Godot's get_temp_dir() ignores TMPDIR; the sandbox only allows writes under it, so prefer the env value.
func _temp_base() -> String:
	var base := OS.get_environment("TMPDIR")
	return base if base != "" else OS.get_temp_dir()


func before_each() -> void:
	def = reg.day_night
	dir = _temp_base().path_join("hv_107_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)


func after_each() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# AC1: the data carries the design numbers and the registry takes it.
func test_data_loads_the_night_numbers() -> void:
	assert_not_null(def)
	assert_eq(def.night_color, Color(0.50, 0.55, 0.78))
	assert_eq([def.dusk_start, def.night_start, def.dawn_start, def.day_start], [19, 21, 5, 7])
	assert_eq(reg.errors, [] as Array[String])


# AC1: white 07-19, night 21-05, halfway through dusk (20) and dawn (6).
func test_tint_for_day_dusk_night_dawn() -> void:
	assert_eq(DayNight.tint_for(12.0, def), Color.WHITE)
	assert_eq(DayNight.tint_for(0.0, def), def.night_color)
	assert_eq(DayNight.tint_for(23.0, def), def.night_color)
	assert_eq(DayNight.tint_for(19.0, def), Color.WHITE, "dusk starts white")
	assert_eq(DayNight.tint_for(21.0, def), def.night_color, "night starts dark")
	assert_eq(DayNight.tint_for(5.0, def), def.night_color, "dawn starts dark")
	assert_eq(DayNight.tint_for(7.0, def), Color.WHITE, "day starts white")
	var dusk := DayNight.tint_for(20.0, def)
	assert_almost_eq(dusk.r, (1.0 + def.night_color.r) / 2.0, 0.0001, "20:00 is halfway into dusk")
	assert_almost_eq(dusk.b, (1.0 + def.night_color.b) / 2.0, 0.0001)
	var dawn := DayNight.tint_for(6.0, def)
	assert_almost_eq(dawn.r, (def.night_color.r + 1.0) / 2.0, 0.0001, "06:00 is halfway into dawn")
	assert_almost_eq(dawn.b, (def.night_color.b + 1.0) / 2.0, 0.0001)


# AC2: during a Dimming the map is the night tint times the Dimming colour, component-wise.
func test_map_tint_is_night_times_dimming() -> void:
	var c := DayNight.map_tint(22.0, def, true, true)
	assert_almost_eq(c.r, def.night_color.r * DayNight.DIMMING_COLOR.r, 0.0001)
	assert_almost_eq(c.g, def.night_color.g * DayNight.DIMMING_COLOR.g, 0.0001)
	assert_almost_eq(c.b, def.night_color.b * DayNight.DIMMING_COLOR.b, 0.0001)
	assert_eq(DayNight.map_tint(22.0, def, false, true), def.night_color, "no Dimming at night is the night colour")
	assert_eq(DayNight.map_tint(12.0, def, true, true), DayNight.DIMMING_COLOR, "daytime Dimming is the Dimming colour")


# AC3: the setting defaults on, saves and loads.
func test_day_night_setting_round_trip() -> void:
	var path := dir.path_join("settings.cfg")
	var a := GameSettings.new()
	a.path = path
	a.day_night = false
	assert_eq(a.save(), OK)
	var b := GameSettings.new()
	b.path = path
	b.load_file()
	assert_false(b.day_night)
	var fresh := GameSettings.new()
	fresh.path = dir.path_join("missing.cfg")
	fresh.load_file()
	assert_true(fresh.day_night, "default on")


# AC3: the panel row exists and off gives the plain Dimming colour.
func test_settings_panel_has_the_toggle_and_saves_it() -> void:
	var g := GameSettings.new()
	g.path = dir.path_join("panel.cfg")
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	panel.setup(g)
	await wait_process_frames(1)
	var box := panel.find_child("DayNightToggle", true, false) as CheckBox
	assert_not_null(box)
	assert_true(box.button_pressed)
	panel.set_day_night(false)
	assert_false(g.day_night)
	var back := GameSettings.new()
	back.path = g.path
	back.load_file()
	assert_false(back.day_night)
	assert_eq(DayNight.map_tint(22.0, def, true, back.day_night), DayNight.DIMMING_COLOR, "off: plain Dimming")


# The tint reads the fraction inside the hour from the driver (paused it holds; the sim only moves in whole hours).
func test_hour_fraction_tracks_progress_inside_the_hour() -> void:
	var s := Settlement.new_game(42, reg)
	assert_eq(s.hour_fraction(), 0.0)
	s.step_seconds(GameClock.REAL_SECONDS_PER_HOUR * 0.5)
	assert_almost_eq(s.hour_fraction(), 0.5, 0.001)
	var drv := SimDriver.new()
	drv.settlement = s
	assert_almost_eq(drv.hour_fraction(), 0.5, 0.001)
	drv.free()
