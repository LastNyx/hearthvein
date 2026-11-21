class_name TutorialPanel
extends PanelContainer
## The tutorial goal panel under the clock row (ticket 83, D59a, D66): goal n/total, the instruction and the why, live
## numbers where they help, a Skip button with a confirm, and a check mark that flashes when a goal completes. Hidden
## unless TutorialSystem is active. It follows the system on every refresh(), so a loaded game shows the right goal.
## When the last goal completes (not skipped) a closing card opens: what next (Meeting Hall, Village gate numbers from
## the EraDef) and F1 for help; its OK button closes it.

const GREEN := Color("78be5a")

var hud: Hud
var s: Settlement
var card: PanelContainer
var _tut: TutorialSystem
var _title: Label
var _what: Label
var _why: Label
var _live: Label
var _check: Control
var _check_tween: Tween
var _skip: Button
var _confirm: HBoxContainer


## `card_parent` is the full-screen control the closing card is centred in.
func setup(h: Hud, settlement: Settlement, card_parent: Control) -> void:
	hud = h
	s = settlement
	_tut = s.get_system(TutorialSystem) as TutorialSystem
	name = "TutorialPanel"
	size_flags_horizontal = Control.SIZE_SHRINK_END
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(360, 0)
	add_theme_stylebox_override("panel", hud._style())
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = hud._label(head, 18, Hud.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check = _Check.new()
	_check.name = "Check"
	_check.custom_minimum_size = Vector2(26, 24)
	_check.visible = false
	head.add_child(_check)
	_what = _wrapped(hud._label(v, 16, Hud.INK))
	_why = _wrapped(hud._label(v, 14, Hud.DIM))
	_live = _wrapped(hud._label(v, 14, Hud.CYAN))
	_skip = hud._button(v, "Skip tutorial", 13)
	_skip.name = "Skip"
	_skip.pressed.connect(func() -> void:
		_skip.visible = false
		_confirm.visible = true)
	_confirm = HBoxContainer.new()
	_confirm.name = "SkipConfirm"
	_confirm.add_theme_constant_override("separation", 4)
	_confirm.visible = false
	v.add_child(_confirm)
	hud._label(_confirm, 14, Hud.INK).text = "Skip all goals?"
	var yes := hud._button(_confirm, "Yes, skip", 13)
	yes.name = "SkipYes"
	yes.pressed.connect(func() -> void: s.skip_tutorial())
	var no := hud._button(_confirm, "Keep going", 13)
	no.name = "SkipNo"
	no.pressed.connect(func() -> void:
		_confirm.visible = false
		_skip.visible = true)
	_build_card(card_parent)
	s.events.subscribe("tutorial_goal_completed", func(_e: Dictionary) -> void: _flash_check())
	s.events.subscribe("tutorial_finished", func(e: Dictionary) -> void:
		if not bool(e["data"].get("skipped", false)):
			card.visible = true
			refresh())
	refresh()


func _wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(336, 0)
	return l


func refresh() -> void:
	visible = _tut.is_active() and not card.visible
	var g := _tut.current_goal()
	if g == null:
		_confirm.visible = false
		_skip.visible = true
		return
	var total := s.registry.tutorial_goals_in_order().size()
	_title.text = "Tutorial %d/%d" % [_tut.goal_index() + 1, total]
	var lines := g.text.split("\n", false)
	_what.text = lines[0] if lines.size() > 0 else ""
	_why.text = lines[1] if lines.size() > 1 else ""
	_why.visible = _why.text != ""
	_live.text = live_text()
	_live.visible = _live.text != ""


## The live numbers line for the current goal ("" when there is nothing to count).
func live_text() -> String:
	var g := _tut.current_goal()
	if g == null:
		return ""
	match g.kind:
		"built", "built_connected":
			if g.amount <= 1:
				return ""
			var n := 0
			for b: Building in s.buildings.values():
				if b.def.id == g.def_id and not b.site:
					n += 1
			return "Built: %d/%d" % [mini(n, g.amount), g.amount]
		"population":
			return "Citizens: %d/%d" % [s.citizens.size(), g.amount]
		"dimming_stock":
			var t := _tut.stock_targets(s)
			if not t["ready"]:
				return "Waiting for a Dimming forecast."
			return "Lumen %d/%d   Food %d/%d" % [floori(t["lumen_have"]), ceili(t["lumen_target"]),
					floori(t["food_have"]), ceili(t["food_target"])]
	return ""


func check_visible() -> bool:
	return _check.visible


func _flash_check() -> void:
	if _check_tween != null:
		_check_tween.kill()
	_check.visible = true
	_check.modulate = Color.WHITE
	_check_tween = create_tween()
	_check_tween.tween_interval(0.8)
	_check_tween.tween_property(_check, "modulate:a", 0.0, 0.6)
	_check_tween.tween_callback(func() -> void: _check.visible = false)


func _build_card(parent: Control) -> void:
	card = PanelContainer.new()
	card.name = "TutorialCard"
	card.add_theme_stylebox_override("panel", hud._style(Hud.PANEL_BG, Hud.GOLD))
	card.visible = false
	var holder := CenterContainer.new()  # centres the card whatever the screen size
	holder.name = "TutorialCardHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	hud._label(v, 18, Hud.GOLD).text = "Tutorial complete"
	var next := ""
	var era := s.registry.get_era("village")
	if era != null:
		var lm := s.registry.get_building(era.gate_landmark)
		next = "Next: reach the %s era. Build the %s, and have %d citizens and %d gold." % [era.display_name,
				lm.display_name if lm != null else era.gate_landmark, era.gate_pop, era.gate_gold]
	_wrapped(hud._label(v, 16, Hud.INK)).text = next
	_wrapped(hud._label(v, 16, Hud.DIM)).text = "Press F1 for help any time."
	var ok := hud._button(v, "OK", 16)
	ok.name = "TutorialOk"
	ok.pressed.connect(func() -> void: card.visible = false)


## The goal-complete tick: a green check mark drawn as lines (the pixel fonts have no check glyph).
class _Check extends Control:
	func _draw() -> void:
		draw_polyline(PackedVector2Array([Vector2(3, 12), Vector2(10, 19), Vector2(23, 4)]), TutorialPanel.GREEN, 3.0)
