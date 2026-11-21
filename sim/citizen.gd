class_name Citizen
extends RefCounted
## One person. Plain data, no scene tree (walkers in ticket 09 draw it). No age, skills or family in v1 (D29).

const JOB_NONE := ""
## Job kinds: a normal worker slot or a hauler slot of the job building.
const JOB_WORK := "work"
const JOB_HAUL := "haul"
## A builder slot (BuildingDef.builder_slots) of the job building. The citizen works at construction sites,
## chosen by ConstructionSystem, not at the job building itself.
const JOB_BUILD := "build"
## Shifts (ticket 132, spec N1): each citizen works days or nights. A night slot (BuildingDef.night_worker_slots)
## makes its worker a night citizen; everyone else works the day shift.
const SHIFT_DAY := "day"
const SHIFT_NIGHT := "night"

var id: int = -1
## Building id of the house the citizen sleeps in, -1 = homeless.
var home_id: int = -1
## Building id of the workplace, -1 = idle.
var job_id: int = -1
## JOB_WORK or JOB_HAUL when job_id >= 0.
var job_kind: String = JOB_NONE:
	set(v):
		if v != job_kind:
			job_kind = v
			job_epoch += 1
## Bumps whenever any citizen's job_kind changes: Settlement.citizen_ids_of_kind keeps its per-kind lists until then.
static var job_epoch: int = 0
## SHIFT_DAY or SHIFT_NIGHT, set by JobSystem when it allots a shift slot.
var shift: String = SHIFT_DAY


func is_idle() -> bool:
	return job_id < 0


func is_homeless() -> bool:
	return home_id < 0


func to_dict() -> Dictionary:
	return {"id": id, "home_id": home_id, "job_id": job_id, "job_kind": job_kind, "shift": shift}


static func from_dict(d: Dictionary) -> Citizen:
	var c := Citizen.new()
	c.id = int(d["id"])
	c.home_id = int(d["home_id"])
	c.job_id = int(d["job_id"])
	c.job_kind = str(d["job_kind"])
	c.shift = str(d.get("shift", SHIFT_DAY))  # a save from before ticket 132: everyone worked days
	return c
