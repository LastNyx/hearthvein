class_name Citizen
extends RefCounted
## One person. Plain data, no scene tree (walkers in ticket 09 draw it). No age, skills or family in v1 (D29).

const JOB_NONE := ""
## Job kinds: a normal worker slot or a hauler slot of the job building.
const JOB_WORK := "work"
const JOB_HAUL := "haul"

var id: int = -1
## Building id of the house the citizen sleeps in, -1 = homeless.
var home_id: int = -1
## Building id of the workplace, -1 = idle.
var job_id: int = -1
## JOB_WORK or JOB_HAUL when job_id >= 0.
var job_kind: String = JOB_NONE


func is_idle() -> bool:
	return job_id < 0


func is_homeless() -> bool:
	return home_id < 0
