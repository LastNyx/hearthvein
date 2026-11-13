class_name Walker
extends RefCounted
## Movement state of one citizen (same id). Plain data, owned and driven by WalkerSystem.
## Position is `tile` plus `progress` (0..1) of the way to path[0], the tile being entered.

var citizen_id: int = -1
var tile: Vector2i = Vector2i.ZERO
## Tiles still to walk after `tile`; path[0] is the one being entered.
var path: Array[Vector2i] = []
var progress: float = 0.0
## Where the walker is going (or went): a door tile and its building id (-1 = plain tile).
var dest_tile: Vector2i = Vector2i.ZERO
var dest_building: int = -1
## Building id whose door the walker stands at, -1 while walking or standing elsewhere.
var at_building: int = -1
## True when the last route request found no path; WalkerSystem retries every hour.
var blocked: bool = false
## When true the hour schedule leaves this walker alone (hauling, ticket 10, drives it by walk_to_*).
var controlled: bool = false


func is_walking() -> bool:
	return not path.is_empty()


## Position in tile units, tile centre = tile + (0.5, 0.5).
func position() -> Vector2:
	var p := Vector2(tile)
	if not path.is_empty():
		p = p.lerp(Vector2(path[0]), progress)
	return p + Vector2(0.5, 0.5)


## Plain-data snapshot for a save: position, the path still to walk and where it is going.
func to_dict() -> Dictionary:
	var tiles := []
	for t in path:
		tiles.append(t)
	return {
		"citizen_id": citizen_id,
		"tile": tile,
		"path": tiles,
		"progress": progress,
		"dest_tile": dest_tile,
		"dest_building": dest_building,
		"at_building": at_building,
		"blocked": blocked,
		"controlled": controlled,
	}


static func from_dict(d: Dictionary) -> Walker:
	var w := Walker.new()
	w.citizen_id = int(d["citizen_id"])
	w.tile = d["tile"]
	w.path.assign(d["path"])
	w.progress = float(d["progress"])
	w.dest_tile = d["dest_tile"]
	w.dest_building = int(d["dest_building"])
	w.at_building = int(d["at_building"])
	w.blocked = bool(d["blocked"])
	w.controlled = bool(d["controlled"])
	return w
