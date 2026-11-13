class_name CoverageSystem
extends SimSystem
## Coverage (design.md sections 11 and 16, ticket 23b): any finished building with a coverage_radius covers homes
## within that many tiles, measured tile edge to tile edge like a Market's reach (Building.footprint_gap). The Shrine
## is r6 now; the Park (r5), Observatory (r8) and Hall of Seasons (r12) use the same query later by their data alone.
##
## The Spirit "coverage" factor is +SpiritDef.coverage_bonus when more than SpiritDef.coverage_min_share of the housed
## citizens live in a covered home. "Most" is strict: exactly half is not enough.
##
## The covered-home set is cached on structure_version like the Market reach: placing or demolishing a building
## rebuilds it, nothing else can change it. A pure cache, so it is left out of saves (test_save's SKIP list).

var _version: int = -1
var _covered: Dictionary = {}  # home building id -> true when a finished coverage building reaches it


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


## True when `source` has a positive coverage_radius and the home is within it. Static so the geometry is testable
## without placing anything.
static func building_covers(source: Building, home: Building) -> bool:
	var radius := source.def.coverage_radius
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


## Rebuild the covered-home set when roads or buildings changed (a coverage building or a home placed/demolished).
func _ensure(s: Settlement) -> void:
	if _version == s.structure_version:
		return
	_version = s.structure_version
	_covered.clear()
	var sources: Array[Building] = []
	var homes: Array[Building] = []
	for bid in s.buildings:
		var b: Building = s.buildings[bid]
		if b.site:
			continue
		if b.def.coverage_radius > 0:
			sources.append(b)
		if b.def.housing_beds > 0:
			homes.append(b)
	if sources.is_empty():
		return
	for h in homes:
		for src in sources:
			if building_covers(src, h):
				_covered[h.id] = true
				break
