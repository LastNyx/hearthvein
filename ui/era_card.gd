class_name EraCard
extends CenterContainer
## The era intro card (ticket 84, D70): on era_changed a centred card names the era, lists the buildings it unlocks (from
## the BuildingDef rows), one line of new pressure (EraDef.new_pressure) and the next gate (EraDef pop, gold, landmark).
## It pauses the game through the SimDriver speed and puts the speed back when it closes.

var hud: Hud
var s: Settlement
var driver: SimDriver
var _card: PanelContainer
var _title: Label
var _new: Label
var _pressure: Label
var _next: Label
var _saved_speed := 1
var _open := false


func setup(h: Hud, settlement: Settlement, sim_driver: SimDriver) -> void:
	hud = h
	s = settlement
	driver = sim_driver
	name = "EraCardHolder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.name = "EraCard"
	_card.visible = false
	_card.add_theme_stylebox_override("panel", hud._style(Hud.PANEL_BG, Hud.GOLD))
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_card.add_child(v)
	_title = hud._label(v, 18, Hud.GOLD)
	_new = _wrapped(hud._label(v, 16, Hud.INK))
	_pressure = _wrapped(hud._label(v, 16, Hud.PURPLE))
	_next = _wrapped(hud._label(v, 16, Hud.DIM))
	var ok := hud._button(v, "OK", 16)
	ok.name = "EraOk"
	ok.pressed.connect(close)
	s.events.subscribe("era_changed", func(e: Dictionary) -> void: open_for(str(e["data"]["to"])))


func _wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	return l


func is_open() -> bool:
	return _open


func open_for(era_id: String) -> void:
	var era := s.registry.get_era(era_id)
	if era == null:
		return
	_title.text = "%s era reached" % era.display_name
	var names: Array[String] = []
	for d in s.registry.buildings_of_era(era_id):
		names.append(d.display_name)
	names.sort()
	_new.text = "New buildings: %s." % ", ".join(names)
	_pressure.text = era.new_pressure
	var g := s.era_gate()
	if g["next"] == "":
		_next.text = "No more eras. Build the Skyheart, the final landmark."
	else:
		var nxt := s.registry.get_era(g["next"])
		var lm := s.registry.get_building(nxt.gate_landmark)
		_next.text = "Next: the %s era. Build the %s, and have %d citizens and %d gold." % [nxt.display_name,
				lm.display_name if lm != null else nxt.gate_landmark, nxt.gate_pop, nxt.gate_gold]
	if not _open:
		_saved_speed = driver.speed
		driver.set_speed(0)
	_open = true
	_card.visible = true


func close() -> void:
	if not _open:
		return
	_open = false
	_card.visible = false
	if driver.speed == 0:
		driver.set_speed(_saved_speed)
