class_name LightingSystem
extends SimSystem
## Lamps and the lit rule (ticket 133, spec N2). A finished lamp (BuildingDef.lamp) lights every tile within its
## radius from LogisticsDef.lamp_light_start to lamp_light_end (19 to 7, wrapping midnight) while it is fuelled.
##
## Fuel is delivered by haulers like any other input (HaulingSystem.need_for adds the tier's fuel need). The lamp
## burns lamp_fuel_per_night units once, at the dusk hour (lamp_light_start); with less than that it stays dark for
## the whole night. The Grid Lamp takes its fuel from the Lumen grid instead (no hauling).
##
## Settlement.is_lit(b) asks this system: true when one of the building's footprint tiles is inside a lit lamp's
## radius, during the lamp hours. The lit-tile set is a cache keyed on the layout (structure_version,
## completion_version, building count) and Settlement.light_version, which moves whenever a lamp becomes lit or dark;
## it rebuilds after a build, a demolish, a fuel burn or dawn without a scan of the map.
##
## Lit houses give Spirit a small bonus at night (lit_share x SpiritDef.light_bonus, capped); SpiritSystem reads it.
## The lamp's lit_tonight flag is saved on the Building; this system keeps no other state.

## Tiles a lit lamp reaches, as Vector2i -> true. Runtime cache only.
var _lit: Dictionary = {}
var _key: Array = []


func on_hour(s: Settlement) -> void:
	var lg := s.registry.logistics
	if lg == null:
		return
	var h := s.clock.hour()
	if h == lg.lamp_light_start:
		_burn(s)
	elif h == lg.lamp_light_end:
		var changed := false
		for bid in s.buildings:
			var b: Building = s.buildings[bid]
			if b.lit_tonight:
				b.lit_tonight = false
				changed = true
		if changed:
			s.light_version += 1


## At dusk: every lamp tries to pay its fuel for the coming night; those that can light up, the rest go dark.
## Night slots follow at once (a lamp that ran out this dusk closes its buildings' night entries).
func _burn(s: Settlement) -> void:
	var gs := s.get_system(GridSystem) as GridSystem
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.site or not b.def.lamp:
			continue
		var fuel := b.lamp_fuel(s.registry)
		var per := b.lamp_fuel_per_night(s.registry)
		var got := 0.0
		if fuel == "" or per <= 0.0:
			got = 0.0
		elif b.lamp_grid(s.registry) and gs != null and GridSystem.on_grid(s, b):
			got = gs.draw(s, gs.grid_of(s, b.id), per)  # the grid feeds it, a hauler never does
		elif b.input_buffer != null:
			got = b.input_buffer.remove(fuel, per)
		ResourceLedgerSystem.record_used(s, fuel, got, "light")
		b.lit_tonight = got >= per - Inventory.EPS
	# Always: the 132 layout cache must rebuild at dusk. JobSystem runs right after this system in the same hour.
	s.light_version += 1


## True when one of `b`'s footprint tiles is inside a lit lamp's radius during the lamp hours.
func is_building_lit(s: Settlement, b: Building) -> bool:
	if not s.is_lamp_hour():
		return false
	_ensure(s)
	for t in b.tiles():
		if _lit.has(t):
			return true
	return false


## True when `tile` is inside a lit lamp's radius during the lamp hours.
func is_tile_lit(s: Settlement, tile: Vector2i) -> bool:
	return s.is_lamp_hour() and _ensure(s).has(tile)


## Lit tiles within `radius` (Chebyshev) of the building's footprint, its own tiles counting (ticket 144: the
## Moonmoth Loft needs at least three lit tiles within two). 0 outside the lamp hours.
func lit_tiles_near(s: Settlement, b: Building, radius: int) -> int:
	if radius <= 0 or not s.is_lamp_hour():
		return 0
	var lit := _ensure(s)
	var seen := {}
	for t in b.tiles():
		for y in range(t.y - radius, t.y + radius + 1):
			for x in range(t.x - radius, t.x + radius + 1):
				var p := Vector2i(x, y)
				if lit.has(p):
					seen[p] = true
	return seen.size()


## Rebuilds the lit-tile set when the layout or the light state moved.
func _ensure(s: Settlement) -> Dictionary:
	var key := [s.structure_version, s.completion_version, s.buildings.size(), s.light_version]
	if key == _key:
		return _lit
	_key = key
	_lit.clear()
	var ids: Array = s.buildings.keys()
	ids.sort()
	for bid in ids:
		var b: Building = s.buildings[bid]
		if b.site or not b.def.lamp or not b.lit_tonight:
			continue
		var r := b.lamp_radius(s.registry)
		if r <= 0:
			continue
		for t in b.tiles():
			for y in range(t.y - r, t.y + r + 1):
				for x in range(t.x - r, t.x + r + 1):
					if not MapState.in_bounds(x, y):
						continue
					var dx := x - t.x
					var dy := y - t.y
					if dx * dx + dy * dy <= r * r:
						_lit[Vector2i(x, y)] = true
	return _lit
