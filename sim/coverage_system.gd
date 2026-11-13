class_name CoverageSystem
extends SimSystem
## Coverage (design.md sections 11 and 16, ticket 23b): any finished building with a coverage_radius covers homes
## within that many tiles, measured tile edge to tile edge like a Market's reach (Building.footprint_gap). The Shrine
## is r6 now; the Park (r5), Observatory (r8) and Hall of Seasons (r12) use the same query later by their data alone.
##
## The Spirit "coverage" factor is +SpiritDef.coverage_bonus when more than SpiritDef.coverage_min_share of the housed
## citizens live in a covered home. "Most" is strict: exactly half is not enough.
##
## Drinking water (ticket 29, design.md section 9) is the same query on a separate field, BuildingDef.water_radius:
## a finished Well (r8), Water Tower (r16) or Cloud Cistern (r10) serves homes with BuildingDef.needs_water. The two
## are deliberately keyed on different fields so a Well never counts as Shrine coverage and a Shrine never waters a
## home. The Spirit "water" factor is -SpiritDef.water_max times the share of housed citizens in homes that need
## water and lack it (0 when no home needs water).
##
## A Well standing on a tile wet only from fouled water gives unsafe water (design.md section 9, ticket 29c): it
## serves nothing, so its homes count as missing water. Fouling changes hourly, so the water set is also keyed on
## MapState.foul_version; the coverage set never is. Both are pure caches, so they are left out of saves (test_save's
## SKIP list).

var _version: int = -1
var _foul_version: int = -1
var _covered: Dictionary = {}  # home building id -> true when a finished coverage building reaches it
var _water: Dictionary = {}    # home building id -> true when a finished water building reaches it


## Home building ids inside any finished coverage building's radius, low to high. The one query an overlay draws.
func covered_homes(s: Settlement) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	for bid: int in _covered.keys():
		out.append(bid)
	out.sort()
	return out


## True when this home building is inside some finished coverage building's radius.
func home_covered(s: Settlement, home_id: int) -> bool:
	_ensure(s)
	return _covered.get(home_id, false)


## Home building ids served by a finished Well, Water Tower or Cloud Cistern, low to high.
func water_served_homes(s: Settlement) -> Array[int]:
	_ensure(s)
	var out: Array[int] = []
	for bid: int in _water.keys():
		out.append(bid)
	out.sort()
	return out


## True when this home building is served with drinking water by some finished water building.
func home_has_water(s: Settlement, home_id: int) -> bool:
	_ensure(s)
	return _water.get(home_id, false)


## True when `source` has a positive coverage_radius and the home is within it. Static so the geometry is testable
## without placing anything.
static func building_covers(source: Building, home: Building) -> bool:
	var radius := source.def.coverage_radius
	return radius > 0 and Building.footprint_gap(source, home) <= radius


## True when `source` provides drinking water and the home is within its water_radius. Separate from
## building_covers so coverage and water never mix.
static func building_serves_water(source: Building, home: Building) -> bool:
	var radius := source.def.water_radius
	return radius > 0 and Building.footprint_gap(source, home) <= radius


## Spirit hook "coverage": +coverage_bonus when more than coverage_min_share of the housed citizens live in a covered
## home. Homeless citizens neither help nor hurt the share; a settlement with no housed citizen gets nothing.
static func spirit_factor(s: Settlement) -> float:
	var sys := s.get_system(CoverageSystem) as CoverageSystem
	if sys == null:
		return 0.0
	var housed := 0
	var covered := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.is_homeless():
			continue
		housed += 1
		if sys.home_covered(s, c.home_id):
			covered += 1
	if housed == 0:
		return 0.0
	var sd := s.registry.spirit
	return sd.coverage_bonus if float(covered) > float(housed) * sd.coverage_min_share else 0.0


## Spirit hook "water" (design.md section 11): -SpiritDef.water_max times the share of housed citizens whose home
## needs water and has none in reach. Weighed by housed citizens (like spirit_factor), but only over the citizens
## whose homes need water; a settlement where no home needs water gets 0, and homeless citizens never count.
static func water_factor(s: Settlement) -> float:
	var sys := s.get_system(CoverageSystem) as CoverageSystem
	if sys == null:
		return 0.0
	var needy := 0
	var lacking := 0
	for cid in s.citizens:
		var c: Citizen = s.citizens[cid]
		if c.is_homeless():
			continue
		var home: Building = s.buildings.get(c.home_id)
		if home == null or home.site or not home.def.needs_water:
			continue
		needy += 1
		if not sys.home_has_water(s, home.id):
			lacking += 1
	if needy == 0:
		return 0.0
	return -s.registry.spirit.water_max * float(lacking) / float(needy)


## Rebuild the covered-home sets when roads or buildings changed (a source or a home placed/demolished).
func _ensure(s: Settlement) -> void:
	if _version == s.structure_version and _foul_version == s.map.foul_version:
		return
	_version = s.structure_version
	_foul_version = s.map.foul_version
	_covered.clear()
	_water.clear()
	var sources: Array[Building] = []
	var water_sources: Array[Building] = []
	var homes: Array[Building] = []
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site:
			continue
		if b.def.coverage_radius > 0:
			sources.append(b)
		if b.def.water_radius > 0:
			water_sources.append(b)
		if b.def.housing_beds > 0:
			homes.append(b)
	for h in homes:
		for src in sources:
			if building_covers(src, h):
				_covered[h.id] = true
				break
		for src in water_sources:
			# Unsafe water: a source standing on a tile wet only from fouled water serves nothing.
			if FoulingSystem.wet_only_from_fouled(s, src.origin):
				continue
			if building_serves_water(src, h):
				_water[h.id] = true
				break
