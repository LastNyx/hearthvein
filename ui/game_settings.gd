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
var tutorial_first_run_done: bool = false
var seen_hints: Array[String] = []
var volume_master: float = 0.8
var volume_effects: float = 0.8
var volume_ambience: float = 0.8
var mute_in_background: bool = true


func to_dict() -> Dictionary:
	return {
		"fullscreen": fullscreen, "ui_scale": ui_scale, "hints_enabled": hints_enabled,
		"tutorial_first_run_done": tutorial_first_run_done, "seen_hints": seen_hints.duplicate(),
		"volume_master": volume_master, "volume_effects": volume_effects, "volume_ambience": volume_ambience,
		"mute_in_background": mute_in_background,
	}


## Reads the file; anything missing or malformed keeps its default. Never errors.
func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	fullscreen = _bool(cf, "fullscreen", fullscreen)
	hints_enabled = _bool(cf, "hints_enabled", hints_enabled)
	tutorial_first_run_done = _bool(cf, "tutorial_first_run_done", tutorial_first_run_done)
	mute_in_background = _bool(cf, "mute_in_background", mute_in_background)
	volume_master = _vol(cf, "volume_master", volume_master)
	volume_effects = _vol(cf, "volume_effects", volume_effects)
	volume_ambience = _vol(cf, "volume_ambience", volume_ambience)
	var sc: Variant = cf.get_value(SECTION, "ui_scale", ui_scale)
	if (sc is float or sc is int) and SCALES.has(float(sc)):
		ui_scale = float(sc)
	var hints: Variant = cf.get_value(SECTION, "seen_hints", [])
	seen_hints = []
	if hints is Array:
		for h in hints:
			if h is String:
				seen_hints.append(h)


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
