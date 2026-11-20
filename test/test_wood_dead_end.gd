extends GutTest
## Ticket 121: a Woodcutter or Forester can always be placed when the wood is gone (the wood dead end).

const SEED := 42

var reg: DataRegistry
var s: Settlement
var m: HudModel


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	s.era_override = "village"
	m = HudModel.new(s)


func _drain_wood() -> void:
	s.hearth.inventory.remove("wood", s.hearth.inventory.amount_of("wood"))


## A buildable spot for the def next to the Hearth.
func _spot(id: String) -> Vector2i:
	var h := s.map.hearth_spot
	for r in range(2, 10):
		for y in range(h.y - r, h.y + r + 1):
			for x in range(h.x - r, h.x + r + 1):
				if s.can_place(id, Vector2i(x, y))["ok"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_woodcutter_and_forester_are_free_with_no_wood() -> void:
	_drain_wood()
	for id in ["woodcutter", "forester"]:
		assert_eq(s.cost_for(id), {}, "%s costs nothing at wood 0" % id)
		var bid := s.place_building(id, _spot(id))
		assert_gt(bid, -1, "%s placed at wood 0" % id)
		var site: Building = s.buildings[bid]
		assert_true(site.site_delivered(), "%s needs no goods hauled" % id)
		s.demolish(bid)


func test_woodcutter_pays_normally_while_wood_covers_it() -> void:
	assert_eq(s.cost_for("woodcutter"), {"wood": 10})
	assert_eq(s.cost_for("forester"), {"wood": 20})
	s.hearth.inventory.remove("wood", s.hearth.inventory.amount_of("wood") - 15.0)
	assert_eq(s.cost_for("woodcutter"), {"wood": 10}, "15 wood covers 10")
	assert_eq(s.cost_for("forester"), {}, "15 wood does not cover 20")


func test_only_one_free_site_at_a_time() -> void:
	_drain_wood()
	assert_gt(s.place_building("woodcutter", _spot("woodcutter")), -1)
	assert_eq(s.cost_for("woodcutter"), {"wood": 10}, "an open free site is already on its way")


func test_build_card_shows_free_with_no_wood() -> void:
	_drain_wood()
	var rows := m.cost_rows(reg.get_building("woodcutter"))
	assert_eq(rows.size(), 0, "no cost rows: nothing to be short of")
