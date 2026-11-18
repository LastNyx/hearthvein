class_name HintCards
extends VBoxContainer
## First-time hint cards (ticket 84, D59b, D68, D70). Hint rows are data (data/hints/*.tres, HintDef): a trigger event,
## an optional data filter, an optional extra check, a title, a body and a help page. A card sits at the right edge
## under the era and tutorial panels and never pauses the game. It closes on a click or after 20 s; one shows at a time
## and the rest queue. Each hint shows once ever (GameSettings.seen_hints, saved when it is shown), never while hints are
## off, and never while the tutorial goal in view covers it (that hint then counts as seen: the goal taught it).
## The More button emits help_page_requested(page_id) and is hidden while nothing is connected (the help screen, 85).

signal help_page_requested(page_id: String)

const SHOW_SECONDS := 20.0
const WIDTH := 360.0

var hud: Hud
var s: Settlement
var settings: GameSettings
var _card: PanelContainer
var _title: Label
var _body: Label
var _more: Button
var _current: HintDef
var _queue: Array[HintDef] = []
var _left := 0.0
var _by_trigger: Dictionary = {}  # event kind -> Array[HintDef]


func setup(h: Hud, settlement: Settlement, game_settings: GameSettings) -> void:
	hud = h
	s = settlement
	settings = game_settings
	name = "HintCards"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_END
	_build_card()
	for def in s.registry.hints_in_order():
		if not _by_trigger.has(def.trigger):
			_by_trigger[def.trigger] = []
			s.events.subscribe(def.trigger, _on_event)
		_by_trigger[def.trigger].append(def)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "HintCard"
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	_card.add_theme_stylebox_override("panel", hud._style(Hud.PANEL_BG, Hud.CYAN))
	_card.visible = false
	_card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_card.add_child(v)
	_title = hud._label(v, 18, Hud.CYAN)
	_body = hud._label(v, 16, Hud.INK)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - 24, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_more = hud._button(row, "More", 14)
	_more.name = "HintMore"
	_more.pressed.connect(func() -> void:
		if _current != null:
			help_page_requested.emit(_current.help_page)
		close())
	hud._label(row, 13, Hud.DIM).text = "Click to close"


## Id of the card showing, "" when none.
func current_id() -> String:
	return _current.id if _current != null else ""


func queued_ids() -> Array[String]:
	var out: Array[String] = []
	for d in _queue:
		out.append(d.id)
	return out


func visible_card() -> bool:
	return _card.visible


func card_node() -> PanelContainer:
	return _card


func more_button() -> Button:
	return _more


## Closes the card on view and shows the next queued hint, if any is still allowed.
func close() -> void:
	_current = null
	_card.visible = false
	while not _queue.is_empty():
		var next: HintDef = _queue.pop_front()
		if _allowed(next):
			_show(next)
			return


func _process(delta: float) -> void:
	tick(delta)


## Real seconds since the last call: closes the card after SHOW_SECONDS.
func tick(delta: float) -> void:
	if _current == null:
		return
	_left -= delta
	if _left <= 0.0:
		close()


func _on_event(e: Dictionary) -> void:
	for def: HintDef in _by_trigger.get(e["kind"], []):
		if def.filter_key != "" and str(e["data"].get(def.filter_key)) != def.filter_value:
			continue
		if passes(def, e):
			offer(def)


## Whether the hint's extra check holds for this event (see HintDef.check).
func passes(def: HintDef, e: Dictionary) -> bool:
	match def.check:
		"upkeep_building":
			var b := s.registry.get_building(str(e["data"].get("def", "")))
			return b != null and b.upkeep_lumen > 0.0 and UpkeepSystem.is_on(s)
		"no_workers":
			var staffed := {}
			for c: Citizen in s.citizens.values():
				if c.job_id >= 0 and c.job_kind == Citizen.JOB_WORK:
					staffed[c.job_id] = true
			for id in s.buildings:
				var b: Building = s.buildings[id]
				if not b.site and not b.paused and b.def.worker_slots > 0 and not staffed.has(id):
					return true
			return false
		"homeless":
			return s.homeless_count() > 0
		"region_buy":
			for r in MapState.REGION_COUNT:
				if s.can_buy_region(r)["ok"]:
					return true
			return false
	return true


## Shows the hint now, or queues it behind the one showing. Nothing when it is seen, queued, off or covered.
func offer(def: HintDef) -> void:
	if not settings.hints_enabled or settings.seen_hints.has(def.id) or def == _current or _queue.has(def):
		return
	var tut := s.get_system(TutorialSystem) as TutorialSystem
	if tut != null and tut.covers_hint(def.id):
		_mark_seen(def)
		return
	if _current != null:
		_queue.append(def)
	else:
		_show(def)


func _allowed(def: HintDef) -> bool:
	return settings.hints_enabled and not settings.seen_hints.has(def.id)


func _show(def: HintDef) -> void:
	_current = def
	_left = SHOW_SECONDS
	_title.text = def.title
	_body.text = def.body
	_more.visible = help_page_requested.get_connections().size() > 0
	_card.visible = true
	_mark_seen(def)


func _mark_seen(def: HintDef) -> void:
	if not settings.seen_hints.has(def.id):
		settings.seen_hints.append(def.id)
		settings.save()
