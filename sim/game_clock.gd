class_name GameClock
extends RefCounted
## Canonical time is an integer count of hours since the start (year 1, spring, day 1, hour 0).

const HOURS_PER_DAY := 24
const DAYS_PER_SEASON := 8
const SEASONS_PER_YEAR := 4
const DAYS_PER_YEAR := DAYS_PER_SEASON * SEASONS_PER_YEAR
const SEASON_NAMES: Array[String] = ["spring", "summer", "autumn", "winter"]
## 1 day = 120 real seconds at 1x (one game hour = 5 s).
const REAL_SECONDS_PER_DAY := 120.0
const REAL_SECONDS_PER_HOUR := REAL_SECONDS_PER_DAY / HOURS_PER_DAY

var total_hours: int = 0


func hour() -> int:
	return total_hours % HOURS_PER_DAY


## Days elapsed since start (0-based).
func total_days() -> int:
	return total_hours / HOURS_PER_DAY


## Day within the season, 1..8.
func day() -> int:
	return total_days() % DAYS_PER_SEASON + 1


func total_seasons() -> int:
	return total_days() / DAYS_PER_SEASON


## Season index 0..3.
func season() -> int:
	return total_seasons() % SEASONS_PER_YEAR


func season_name() -> String:
	return SEASON_NAMES[season()]


## Year, starting at 1.
func year() -> int:
	return total_days() / DAYS_PER_YEAR + 1


func is_day_start() -> bool:
	return hour() == 0


func is_season_start() -> bool:
	return hour() == 0 and total_days() % DAYS_PER_SEASON == 0


func label() -> String:
	return "Year %d, %s, Day %d" % [year(), season_name().capitalize(), day()]


func to_dict() -> Dictionary:
	return {"total_hours": total_hours}


static func from_dict(d: Dictionary) -> GameClock:
	var c := GameClock.new()
	c.total_hours = int(d["total_hours"])
	return c
