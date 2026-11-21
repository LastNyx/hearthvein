class_name NightRenderModel
extends RefCounted
## The night render model (ticket 135): which lamps get a light pool, which buildings get lit windows and which get
## ember pixels. Flat data the renderer draws and the headless tests check; the lit rule itself stays in the sim
## (Settlement.is_lit, ticket 133), so this never decides what is lit on its own.
##
## A pool is a fuelled lamp that is lit tonight, with the radius of its tier. Windows go to a lit home or to a working
## building, and only during the lamp hours. A Charcoal Kiln that is working shows ember pixels.

## Steps of a pool: three flat discs of growing alpha, widest and palest first (not a soft gradient or a glow).
const POOL_STEPS := 3
## Warm light of the pools and the windows. The light is added to the tinted ground (ticket 170), so a low alpha
## keeps the night map readable while the three steps still read warm.
const POOL_COLOR := Color(1.0, 0.6, 0.25)
const POOL_ALPHA := 0.05
## Buildings whose working sprite shows glowing embers at night (ticket 135: the kiln).
const EMBER_BUILDINGS := ["charcoal_kiln"]


## One entry per lit lamp: {"id", "origin", "size", "radius"}. Empty by day and for lamps with no fuel.
static func pools(s: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if s == null:
		return out
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or not b.def.lamp or not s.is_lit(b):
			continue
		var r := b.lamp_radius(s.registry)
		if r <= 0:
			continue
		out.append({"id": b.id, "origin": b.origin, "size": b.def.size, "radius": r})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## One entry per building with lit windows: {"id", "origin", "size"}. A house (category housing) inside a lamp's
## light, or a building with a worker at its door right now (a working building at night). Empty by day.
static func windows(s: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if s == null or not s.is_lamp_hour():
		return out
	var counts := _work_counts(s)
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused:
			continue
		var lit_home := b.def.category == "housing" and s.is_lit(b)
		var working := int(counts.get(b.id, 0)) > 0
		if lit_home or working:
			out.append({"id": b.id, "origin": b.origin, "size": b.def.size})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## One entry per Night Watch out tonight: {"id", "origin", "route"}. The route is the very patrol the sim lights
## (WalkerSystem.patrol_route), which NightView draws as the walker's small lantern pool (ticket 143).
static func lantern_walkers(s: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if s == null or not s.is_lamp_hour():
		return out
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	if ws == null:
		return out
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.def.patrol_radius <= 0 or not b.lit_tonight:
			continue
		var route := ws.patrol_route(s, b)
		if not route.is_empty():
			out.append({"id": b.id, "origin": b.origin, "route": route})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## One entry per working ember building: {"id", "origin", "size"}. The Charcoal Kiln glows from its cracks at night.
static func embers(s: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if s == null or not s.is_lamp_hour():
		return out
	var counts := _work_counts(s)
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site or b.paused or not EMBER_BUILDINGS.has(b.def.id):
			continue
		if int(counts.get(b.id, 0)) > 0:
			out.append({"id": b.id, "origin": b.origin, "size": b.def.size})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


## Workers standing at their building's door right now (WalkerSystem.work_counts), empty without a walker system.
static func _work_counts(s: Settlement) -> Dictionary:
	var ws := s.get_system(WalkerSystem) as WalkerSystem
	return ws.work_counts() if ws != null else {}
