class_name SoundPlayer
extends Node
## Sound (ticket 86, D61/D64/D65). Owned by Main, so it outlives TITLE/GAME swaps: bind(settlement) re-subscribes to the
## new Settlement's event bus, set_title() quietens the ambience. Effects play on the Effects bus, ambience on Ambience;
## the volume sliders (GameSettings.changed) and mute-in-background reach the buses at once. One sound of a kind plays
## per RATE_LIMIT seconds. Every Button/CheckBox that enters the tree clicks (SceneTree.node_added).

const RATE_LIMIT := 0.15
const BUS_EFFECTS := "Effects"
const BUS_AMBIENCE := "Ambience"
const FILES := {
	"click": "res://assets/audio/ui/click.ogg",
	"place": "res://assets/audio/sfx/place.ogg",
	"demolish": "res://assets/audio/sfx/demolish.ogg",
	"completed": "res://assets/audio/sfx/completed.ogg",
	"era": "res://assets/audio/sfx/era.ogg",
	"milestone": "res://assets/audio/sfx/milestone.ogg",
	"forecast": "res://assets/audio/sfx/forecast.ogg",
}
const DAY_FILE := "res://assets/audio/ambience/day.ogg"
const DRONE_FILE := "res://assets/audio/ambience/drone.ogg"
## Settlement event -> sound kind.
const EVENT_KINDS := {
	"building_placed": "place", "building_demolished": "demolish", "building_completed": "completed",
	"era_changed": "era", "milestone": "milestone", "dimming_forecast": "forecast",
}
## Ambience layer gains per mode (linear): title is quiet, day and drone are the two game layers.
const MODES := {"title": {"day": 0.3, "drone": 0.0}, "day": {"day": 1.0, "drone": 0.0}, "drone": {"day": 0.0, "drone": 1.0}}

var settings: GameSettings
## Seconds for the day/drone crossfade.
var fade_seconds: float = 3.0
## "title", "day" or "drone".
var ambience_mode: String = "title"
## Seconds clock for the rate limit (tests swap it).
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var _last: Dictionary = {}
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _layers: Dictionary = {}
var _tween: Tween
var _background_muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the ambience keeps running under pause (era card, help, menu)
	_ensure_buses()
	for kind: String in FILES:
		_streams[kind] = load(FILES[kind])
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_EFFECTS
		add_child(p)
		_pool.append(p)
	for layer: String in ["day", "drone"]:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_AMBIENCE
		var st := load(DAY_FILE if layer == "day" else DRONE_FILE) as AudioStreamOggVorbis
		if st != null:
			st.loop = true
			p.stream = st
		add_child(p)
		_layers[layer] = p
	_apply_gains(MODES[ambience_mode], false)
	for layer: AudioStreamPlayer in _layers.values():
		layer.play()
	get_tree().node_added.connect(_on_node_added)


func setup(s: GameSettings) -> void:
	settings = s
	s.changed.connect(apply_volumes)
	apply_volumes()


## Volumes from the settings onto the buses (linear 0-1 -> dB; zero mutes).
func apply_volumes() -> void:
	if settings == null:
		return
	_ensure_buses()
	_set_bus("Master", settings.volume_master, _background_muted)
	_set_bus(BUS_EFFECTS, settings.volume_effects, false)
	_set_bus(BUS_AMBIENCE, settings.volume_ambience, false)


func _set_bus(bus: String, v: float, muted: bool) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, muted or v <= 0.0)


func _ensure_buses() -> void:
	for bus in [BUS_EFFECTS, BUS_AMBIENCE]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_background_muted = settings != null and settings.mute_in_background
		apply_volumes()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_background_muted = false
		apply_volumes()


## Subscribes to a (new) Settlement's events and picks the day or drone ambience for its current state.
func bind(s: Settlement) -> void:
	for ev: String in EVENT_KINDS:
		s.events.subscribe(ev, func(_e: Dictionary) -> void: play(EVENT_KINDS[ev]))
	s.events.subscribe("dimming_started", func(_e: Dictionary) -> void: set_ambience("drone"))
	s.events.subscribe("dimming_ended", func(_e: Dictionary) -> void: set_ambience("day"))
	set_ambience("drone" if DimmingSystem.is_active(s) else "day", false)


func set_title() -> void:
	set_ambience("title", false)


## Moves the ambience to `mode`; `fade` crossfades over fade_seconds, otherwise it jumps.
func set_ambience(mode: String, fade: bool = true) -> void:
	if mode == ambience_mode:
		return
	ambience_mode = mode
	if _layers.is_empty():
		return
	_apply_gains(MODES[mode], fade)


func _apply_gains(gains: Dictionary, fade: bool) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if not fade or _layers.is_empty() or fade_seconds <= 0.0:
		for layer: String in gains:
			if _layers.has(layer):
				(_layers[layer] as AudioStreamPlayer).volume_linear = gains[layer]
		return
	_tween = create_tween().set_parallel(true)
	for layer: String in gains:
		_tween.tween_property(_layers[layer], "volume_linear", gains[layer], fade_seconds)


## Gain (linear) of an ambience layer, "day" or "drone".
func layer_gain(layer: String) -> float:
	return (_layers[layer] as AudioStreamPlayer).volume_linear


## Plays one sound of `kind` unless one of that kind played within RATE_LIMIT. Returns whether it played.
func play(kind: String) -> bool:
	var now: float = clock.call()
	if _last.has(kind) and now - float(_last[kind]) < RATE_LIMIT:
		return false
	_last[kind] = now
	_start(kind)
	return true


## The actual output (tests override it with a recorder).
func _start(kind: String) -> void:
	var st: AudioStream = _streams.get(kind)
	if st == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = st
			p.play()
			return


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_on_button):
		(n as BaseButton).pressed.connect(_on_button)


func _on_button() -> void:
	play("click")
