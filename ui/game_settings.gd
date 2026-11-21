class_name GameSettings
extends RefCounted
## User settings (ticket 76, D58/D65/D69), stored in user://settings.cfg. Missing file, bad file or bad values fall
## back to the defaults. Volumes are only stored here; the sound ticket creates the buses and applies them.

## Emitted by the Settings panel after a change (the sound player applies the volumes).
signal changed

const SECTION := "settings"
const SCALES: Array[float] = [1.0, 1.25, 1.5]

## Tests set a temp path; Main passes its own.
var path: String = "user://settings.cfg"
var fullscreen: bool = false
var ui_scale: float = 1.0
var hints_enabled: bool = true
## The map darkens at night (ticket 107); off keeps the map at the Dimming colour only.
var day_night: bool = true
var tutorial_first_run_done: bool = false
var seen_hints: Array[String] = []
var volume_master: float = 0.8
var volume_effects: float = 0.8
var volume_ambience: float = 0.8
var mute_in_background: bool = true
## Bottom-left tools tab open or collapsed (ticket 88).
var tools_open: bool = true
## Top-left objectives panel collapsed to one line (ticket 126).
var objectives_collapsed: bool = false
## Goods pinned onto the HUD top-right cluster, oldest first (ticket 125); at most HudModel.PIN_LIMIT.
var pinned_goods: Array[String] = []
## The version the What's new panel was last offered for (ticket 92); empty before the first launch.
var last_seen_version: String = ""
## Auto-update (ticket 94): ask GitHub for a newer release on launch, when it last asked (unix time), and the version the
## player chose to skip.
var check_updates: bool = true
var update_last_check: int = 0
var update_skipped_version: String = ""


func to_dict() -> Dictionary:
	return {
		"fullscreen": fullscreen, "ui_scale": ui_scale, "hints_enabled": hints_enabled,
		"day_night": day_night,
		"tutorial_first_run_done": tutorial_first_run_done, "seen_hints": seen_hints.duplicate(),
		"volume_master": volume_master, "volume_effects": volume_effects, "volume_ambience": volume_ambience,
		"mute_in_background": mute_in_background, "tools_open": tools_open,
		"objectives_collapsed": objectives_collapsed,
		"pinned_goods": pinned_goods.duplicate(),
		"last_seen_version": last_seen_version,
		"check_updates": check_updates, "update_last_check": update_last_check,
		"update_skipped_version": update_skipped_version,
	}


## Reads the file; anything missing or malformed keeps its default. Never errors.
func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	fullscreen = _bool(cf, "fullscreen", fullscreen)
	hints_enabled = _bool(cf, "hints_enabled", hints_enabled)
	day_night = _bool(cf, "day_night", day_night)
	tutorial_first_run_done = _bool(cf, "tutorial_first_run_done", tutorial_first_run_done)
	mute_in_background = _bool(cf, "mute_in_background", mute_in_background)
	tools_open = _bool(cf, "tools_open", tools_open)
	objectives_collapsed = _bool(cf, "objectives_collapsed", objectives_collapsed)
	check_updates = _bool(cf, "check_updates", check_updates)
	var ulc: Variant = cf.get_value(SECTION, "update_last_check", 0)
	update_last_check = int(ulc) if ulc is int or ulc is float else 0
	var usv: Variant = cf.get_value(SECTION, "update_skipped_version", "")
	update_skipped_version = usv if usv is String else ""
	volume_master = _vol(cf, "volume_master", volume_master)
	volume_effects = _vol(cf, "volume_effects", volume_effects)
	volume_ambience = _vol(cf, "volume_ambience", volume_ambience)
	var lsv: Variant = cf.get_value(SECTION, "last_seen_version", "")
	last_seen_version = lsv if lsv is String else ""
	var sc: Variant = cf.get_value(SECTION, "ui_scale", ui_scale)
	if (sc is float or sc is int) and SCALES.has(float(sc)):
		ui_scale = float(sc)
	var hints: Variant = cf.get_value(SECTION, "seen_hints", [])
	seen_hints = []
	if hints is Array:
		for h in hints:
			if h is String:
				seen_hints.append(h)
	var pins: Variant = cf.get_value(SECTION, "pinned_goods", [])
	pinned_goods = []
	if pins is Array:
		for g in pins:
			if g is String:
				pinned_goods.append(g)


func save() -> Error:
	var cf := ConfigFile.new()
	for k: String in to_dict():
		cf.set_value(SECTION, k, to_dict()[k])
	return cf.save(path)


## Forgets the first-run flag and every shown hint; nothing else.
func reset_tutorial() -> void:
	seen_hints = []
	tutorial_first_run_done = false


## Fullscreen and UI scale onto the game window. Headless the DisplayServer ignores the mode change.
func apply(window: Window) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if window != null:
		window.content_scale_factor = ui_scale


func _bool(cf: ConfigFile, key: String, def: bool) -> bool:
	var v: Variant = cf.get_value(SECTION, key, def)
	return v if v is bool else def


func _vol(cf: ConfigFile, key: String, def: float) -> float:
	var v: Variant = cf.get_value(SECTION, key, def)
	return clampf(float(v), 0.0, 1.0) if v is float or v is int else def
