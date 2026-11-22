extends GutTest
## Ticket 108: the Dimming's numbers in the HUD text helpers, the forecast stock line, and "x0.5 Dimming" on a selected
## building and its map tooltip.

const SEED := 42

var reg: DataRegistry
var s: Settlement
var m: HudModel
var d: DimmingSystem
var h: Vector2i
var _next_fake: int = 9000


func before_all() -> void:
	reg = DataRegistry.new()
	reg.load_all()


func before_each() -> void:
	s = Settlement.new_game(SEED, reg)
	m = HudModel.new(s)
	d = s.get_system(DimmingSystem) as DimmingSystem
	h = s.map.hearth_spot


## A regular Dimming starting today for `length` days (the fixture the HUD reads; no stepping needed).
func _dimming(length: int = 4) -> void:
	d._start_day = s.clock.total_days()
	d._length = length
	d._active = true


func _forecast(days: int, length: int) -> void:
	d._start_day = s.clock.total_days() + days
	d._length = length
	d._active = false


## A finished building inserted for its def's name and Dimming factor; its inventory stays null.
func _fake(def_id: String) -> Building:
	_next_fake += 1
	var b := Building.new()
	b.id = _next_fake
	b.def = reg.get_building(def_id)
	b.origin = h + Vector2i(6, 6)
	s.buildings[b.id] = b
	return b


# ---------------------------------------------------------------- Dimming text: light

func test_light_line_has_need_stock_and_days() -> void:
	assert_eq(m.dimming_light_text(), "", "no light line outside a Dimming")
	_dimming(4)
	# 8 citizens x 0.5 Lumen = 4 a day; the start stock is 10 Lumen and no cells: 2 days, short of the 4 left.
	assert_eq(m.dimming_light_text(), "Light: needs 4 Lumen/day, have 10 Lumen + 0 cells (about 2 days)")
	assert_eq(m.dimming_short_text(), "", "stock that ran out yesterday is not a shortfall today")
	s.hearth.inventory.add("lumen", 20.0)
	assert_eq(m.dimming_light_text(), "Light: needs 4 Lumen/day, have 30 Lumen + 0 cells (enough)")


func test_light_line_counts_lumen_cells_at_the_data_rate() -> void:
	_dimming(4)
	s.hearth.inventory.remove("lumen", 10.0)
	s.hearth.inventory.add("lumen_cells", 3.0)  # 3 x 5 Lumen = 15, still short of the 16 needed for 4 days
	assert_eq(m.dimming_light_text(), "Light: needs 4 Lumen/day, have 0 Lumen + 3 cells (about 3 days)")
	assert_eq(m.dimming_short_text(), "")


# ---------------------------------------------------------------- Dimming text: short

func test_light_short_warning() -> void:
	_dimming(4)
	assert_eq(m.dimming_short_text(), "", "a Dimming alone is not a shortfall")
	d.last_light = {"need": 32.0, "drawn_lumen": 3.0, "drawn_cells": 0.0, "short": 1.0}
	assert_eq(m.dimming_short_text(), "Light short: Spirit falls")
	d.last_light = {"need": 32.0, "drawn_lumen": 32.0, "drawn_cells": 0.0, "short": 0.0}
	assert_eq(m.dimming_short_text(), "")
	d._dark = true
	assert_eq(m.dimming_short_text(), "Light short: Spirit falls")


# ---------------------------------------------------------------- Dimming text: output

func test_output_line_lists_affected_buildings_and_caps_at_four() -> void:
	assert_eq(m.dimming_output_text(), "", "no output line outside a Dimming")
	_dimming(4)
	_fake("farm")
	_fake("forager")
	_fake("woodcutter")  # unaffected: not listed
	_fake("lumen_tap")
	assert_eq(m.dimming_output_text(), "Output: Farm x0.5, Forager x0.5, Lumen Tap x0.25")
	_fake("aether_collector")
	_fake("bloom_orchard")
	assert_eq(m.dimming_output_text(),
			"Output: Aether Collector x0.5, Bloom Orchard x0.75, Farm x0.5, Forager x0.5, +1 more")


func test_output_line_skips_sites() -> void:
	_dimming(4)
	_fake("farm").site = true
	assert_eq(m.dimming_output_text(), "", "a farm under construction makes nothing yet")


# ---------------------------------------------------------------- Dimming text: forecast stock

func test_forecast_stock_line() -> void:
	assert_eq(m.dimming_stock_text(), "", "no stock line without a forecast")
	_forecast(2, 3)
	# 4 Lumen a day for the 3 days: ~12. 60 food / 8 a day = 7.5 days, enough for the 2-day wait and the Dimming.
	assert_eq(m.dimming_light_text(), "", "no light line before the Dimming starts")
	# The start stock is 10 Lumen: 2 of the 3 days at 4 a day.
	assert_eq(m.dimming_stock_text(), "Stock before it: ~12 Lumen for 3 days (Lumen + cells last 2 of 3 days)")
	s.hearth.inventory.remove("food", 50.0)  # 10 food = 1.25 days, short of the 5 living days
	assert_eq(m.dimming_stock_text(),
			"Stock before it: ~12 Lumen for 3 days (Lumen + cells last 2 of 3 days) and food")


func test_forecast_stock_line_says_all_days_when_cells_cover_it() -> void:
	_forecast(2, 3)
	s.hearth.inventory.add("lumen_cells", 1.0)  # 10 Lumen + 1 cell x 5 = 15, over the 12 needed
	assert_eq(m.dimming_stock_text(), "Stock before it: ~12 Lumen for 3 days (Lumen + cells last all 3 days)")


func test_forecast_stock_line_counts_dimming_supply_and_upkeep() -> void:
	_forecast(2, 8)
	s.hearth.inventory.add("food", 100.0)  # keep the food part out of this line
	# 4 Lumen a day for 8 days = 32; 10 Lumen lasts 2 days.
	assert_eq(m.dimming_stock_text(), "Stock before it: ~32 Lumen for 8 days (Lumen + cells last 2 of 8 days)")
	var tap := _fake("lumen_tap")  # 8 Lumen a worker, x0.25 in a Dimming = 2 a day for one worker
	var c: Citizen = s.citizens[s.citizens.keys()[0]]
	c.job_kind = Citizen.JOB_WORK
	c.job_id = tap.id
	assert_eq(m.dimming_stock_text(), "Stock before it: ~32 Lumen for 8 days (Lumen + cells last 5 of 8 days)")
	var shop := _fake("toolsmith")  # 1 Lumen upkeep a day: 4 + 1 - 2 = 3 a day, 10 Lumen = 3 days
	assert_eq(m.dimming_stock_text(), "Stock before it: ~32 Lumen for 8 days (Lumen + cells last 3 of 8 days)")


# ---------------------------------------------------------------- selected building and tooltip

func test_selected_building_and_tooltip_show_dimming_factor() -> void:
	var farm := _fake("farm")
	m.select(farm.id)
	assert_false("x0.5 Dimming" in m.selection()["lines"], "outside a Dimming the panel says nothing")
	assert_false((m.tooltip_for_building(farm)["text"] as String).contains("x0.5 Dimming"))
	_dimming(4)
	var lines: Array = m.selection()["lines"]
	assert_true("x0.5 Dimming" in lines, str(lines))
	assert_string_contains(m.tooltip_for_building(farm)["text"], "x0.5 Dimming")
	var wc := _fake("woodcutter")
	m.select(wc.id)
	assert_false("x0.5 Dimming" in m.selection()["lines"], "an unaffected building stays plain")
	m.select(farm.id)
	d._active = false
	assert_false("x0.5 Dimming" in m.selection()["lines"], "the Dimming is over")
