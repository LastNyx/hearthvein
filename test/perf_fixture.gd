class_name PerfFixture
extends RefCounted
## Builds a big road-connected settlement for performance checks (ticket 18): a road lattice around the Hearth,
## tents for housing, foragers and woodcutters as jobs, a few storehouses, then `citizens` citizens.
## Not a test file (no test_ prefix); used by test/test_perf.gd and tools/perf_profile.gd.

const SPACING := 4


static func build(reg: DataRegistry, seed: int, citizens: int = 600) -> Settlement:
	var s := Settlement.new_game(seed, reg)
	populate(s, citizens)
	return s


## Fills an existing new game (also one a scene already shows) up to `citizens` citizens. Unlocks every region.
static func populate(s: Settlement, citizens: int) -> void:
	for i in MapState.REGION_COUNT:
		s.map.region_owned[i] = 1
	var hs := s.map.hearth_spot
	var ax := hs.x + 2
	var ay := hs.y
	var tiles: Array[Vector2i] = []
	for y in range(maxi(1, ay - 30), mini(MapState.HEIGHT - 1, ay + 30)):
		for x in range(maxi(1, ax - 50), mini(MapState.WIDTH - 1, ax + 50)):
			var p := Vector2i(x, y)
			if posmod(x - ax, SPACING) == 0 or posmod(y - ay, SPACING) == 0:
				s.place_road(p)
			else:
				tiles.append(p)
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - hs).length_squared() < (b - hs).length_squared())
	var need := {"tent": ceili(citizens / 2.0) - 4, "forager": ceili(citizens / 4.0), "woodcutter": ceili(citizens / 4.0),
			"storehouse": 6}
	var kinds: Array = need.keys()
	var k := 0
	for t in tiles:
		var left := 0
		for kind in kinds:
			left += need[kind]
		if left <= 0:
			break
		for j in kinds.size():
			var kind: String = kinds[(k + j) % kinds.size()]
			if need[kind] <= 0:
				continue
			var bid := s.place_building_instant(kind, t)
			if bid < 0:
				continue
			if not s.buildings[bid].connected:
				s.demolish(bid)
				continue
			need[kind] -= 1
			k += 1
			break
	for i in citizens - s.citizens.size():
		s.add_citizen()
