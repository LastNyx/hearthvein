class_name Island
extends RefCounted
## One sky island (ticket 40): the 16x12 skystone raised by a finished Lift Anchor over one region. Plain data, saved
## by IslandSystem. Later tickets add per-island state here (Lumen supply and the still flag, ticket 40b).

var id: int = -1
## Region index the island floats over (one island per region).
var region: int = -1
## Tile rect on the sky layer, in the same tile coordinates as the ground.
var rect := Rect2i()
## Building id of the Lift Anchor that raised it.
var anchor_id: int = -1


func to_dict() -> Dictionary:
	return {"id": id, "region": region, "rect": rect, "anchor_id": anchor_id}


static func from_dict(d: Dictionary) -> Island:
	var i := Island.new()
	i.id = int(d["id"])
	i.region = int(d["region"])
	i.rect = d["rect"]
	i.anchor_id = int(d["anchor_id"])
	return i
