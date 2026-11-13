class_name Settlement
extends RefCounted
## The central simulation object. Holds registry, map, clock, event bus and a list of systems.
## Features are added as SimSystem subclasses, not by growing this class.

var registry: DataRegistry
var map: MapState
var clock := GameClock.new()
var events := EventBus.new()
var systems: Array[SimSystem] = []


static func new_game(seed: int, reg: DataRegistry) -> Settlement:
	var s := Settlement.new()
	s.registry = reg
	s.map = MapGen.generate(seed, reg)
	return s


func add_system(system: SimSystem) -> void:
	systems.append(system)


## Deterministic advance, one hour at a time. Per hour: clock moves, then on_hour hooks run; when the new
## hour starts a day, day_started is emitted and on_day hooks run; likewise season_started / on_season.
func step_hours(n: int) -> void:
	for i in n:
		clock.total_hours += 1
		events.now_hours = clock.total_hours
		for sys in systems:
			sys.on_hour(self)
		if clock.is_day_start():
			events.emit("day_started", {"day": clock.day(), "season": clock.season_name(), "year": clock.year()})
			for sys in systems:
				sys.on_day(self)
			if clock.is_season_start():
				events.emit("season_started", {"season": clock.season_name(), "year": clock.year()})
				for sys in systems:
					sys.on_season(self)


func step_days(n: int) -> void:
	step_hours(n * GameClock.HOURS_PER_DAY)
