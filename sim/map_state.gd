class_name MapState
extends RefCounted
## Compact tile-state grid. One packed array per field, indexed y * width + x.
## Everything is plain data so later systems can run daily passes over it cheaply.

const WIDTH := 128
const HEIGHT := 96
const REGION_W := 32
const REGION_H := 24
const REGION_COLS := 4
const REGION_ROWS := 4
const REGION_COUNT := 16
const EDGE_BAND := 6

## River flow directions (river_flow field). 0 means "not a river tile".
const FLOW_NONE := 0
const FLOW_N := 1
const FLOW_E := 2
const FLOW_S := 3
const FLOW_W := 4
const FLOW_VECTORS: Array[Vector2i] = [Vector2i.ZERO, Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Region reward types (empty string = none).
const REWARD_RICH_VEIN := "rich_vein"
const REWARD_RUINS := "ruins"
const REWARD_FERTILE_VALLEY := "fertile_valley"
const REWARD_OLD_FOREST := "old_forest"
const REWARD_SPRING := "spring"
const REWARD_TYPES: Array[String] = [REWARD_RICH_VEIN, REWARD_RUINS, REWARD_FERTILE_VALLEY, REWARD_OLD_FOREST, REWARD_SPRING]

var seed_used: int = 0
## terrain byte -> terrain def id (sorted ids of DataRegistry.terrain at generation time).
var terrain_ids: PackedStringArray = PackedStringArray()

var terrain: PackedByteArray = PackedByteArray()
var region: PackedByteArray = PackedByteArray()
var blight: PackedByteArray = PackedByteArray()      # 0/1
var fertility: PackedByteArray = PackedByteArray()   # 0..100
var wet: PackedByteArray = PackedByteArray()         # 0/1
var fouled: PackedByteArray = PackedByteArray()      # 0/1
var river_flow: PackedByteArray = PackedByteArray()  # FLOW_*

## Per region (index row * 4 + col).
var region_owned: PackedByteArray = PackedByteArray()  # 0/1
var region_reward: PackedStringArray = PackedStringArray()
var region_reward_pos: Array[Vector2i] = []  # marker tile, (-1,-1) when no reward

var start_region: int = -1
var hearth_spot: Vector2i = Vector2i(-1, -1)
## River centreline tiles in downstream order, entry first (the wide river and its lakes are river_flow != 0).
var river_path: Array[Vector2i] = []
## River width in tiles at each river_path index (2..4, smooth).
var river_width: Array[float] = []


func _init(ids: PackedStringArray = PackedStringArray()) -> void:
	terrain_ids = ids
	var n := WIDTH * HEIGHT
	terrain.resize(n)
	region.resize(n)
	blight.resize(n)
	fertility.resize(n)
	wet.resize(n)
	fouled.resize(n)
	river_flow.resize(n)
	for y in HEIGHT:
		for x in WIDTH:
			region[y * WIDTH + x] = region_at(x, y)
	region_owned.resize(REGION_COUNT)
	region_reward.resize(REGION_COUNT)
	for i in REGION_COUNT:
		region_reward_pos.append(Vector2i(-1, -1))


static func region_at(x: int, y: int) -> int:
	return (y / REGION_H) * REGION_COLS + x / REGION_W


static func region_rect(r: int) -> Rect2i:
	return Rect2i((r % REGION_COLS) * REGION_W, (r / REGION_COLS) * REGION_H, REGION_W, REGION_H)


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < WIDTH and y < HEIGHT


static func is_edge_band(x: int, y: int) -> bool:
	return x < EDGE_BAND or y < EDGE_BAND or x >= WIDTH - EDGE_BAND or y >= HEIGHT - EDGE_BAND


static func idx(x: int, y: int) -> int:
	return y * WIDTH + x


func terrain_index(id: String) -> int:
	return terrain_ids.find(id)


func get_terrain(x: int, y: int) -> int:
	return terrain[y * WIDTH + x]


func set_terrain(x: int, y: int, t: int) -> void:
	terrain[y * WIDTH + x] = t


func terrain_id_at(x: int, y: int) -> String:
	return terrain_ids[terrain[y * WIDTH + x]]


func set_terrain_id(x: int, y: int, id: String) -> void:
	terrain[y * WIDTH + x] = terrain_ids.find(id)


func get_region(x: int, y: int) -> int:
	return region[y * WIDTH + x]


func is_blighted(x: int, y: int) -> bool:
	return blight[y * WIDTH + x] != 0


func set_blighted(x: int, y: int, v: bool) -> void:
	blight[y * WIDTH + x] = 1 if v else 0


func get_fertility(x: int, y: int) -> int:
	return fertility[y * WIDTH + x]


func set_fertility(x: int, y: int, v: int) -> void:
	fertility[y * WIDTH + x] = clampi(v, 0, 100)


func is_wet(x: int, y: int) -> bool:
	return wet[y * WIDTH + x] != 0


func set_wet(x: int, y: int, v: bool) -> void:
	wet[y * WIDTH + x] = 1 if v else 0


func is_fouled(x: int, y: int) -> bool:
	return fouled[y * WIDTH + x] != 0


func set_fouled(x: int, y: int, v: bool) -> void:
	fouled[y * WIDTH + x] = 1 if v else 0


func get_flow(x: int, y: int) -> int:
	return river_flow[y * WIDTH + x]


func set_flow(x: int, y: int, dir: int) -> void:
	river_flow[y * WIDTH + x] = dir


func is_river(x: int, y: int) -> bool:
	return river_flow[y * WIDTH + x] != FLOW_NONE


## Downstream neighbour of a river tile (may be out of bounds at the map edge).
func downstream(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + FLOW_VECTORS[river_flow[y * WIDTH + x]]


func is_region_owned(r: int) -> bool:
	return region_owned[r] != 0


func set_region_owned(r: int, v: bool) -> void:
	region_owned[r] = 1 if v else 0


func get_region_reward(r: int) -> String:
	return region_reward[r]


## Plain-data snapshot for a save: every tile array as-is plus the generation metadata.
func to_dict() -> Dictionary:
	return {
		"seed_used": seed_used,
		"terrain_ids": terrain_ids,
		"terrain": terrain,
		"region": region,
		"blight": blight,
		"fertility": fertility,
		"wet": wet,
		"fouled": fouled,
		"river_flow": river_flow,
		"region_owned": region_owned,
		"region_reward": region_reward,
		"region_reward_pos": region_reward_pos,
		"start_region": start_region,
		"hearth_spot": hearth_spot,
		"river_path": river_path,
		"river_width": river_width,
	}


static func from_dict(d: Dictionary) -> MapState:
	var m := MapState.new(d["terrain_ids"])
	m.seed_used = int(d["seed_used"])
	m.terrain_ids = d["terrain_ids"]
	m.terrain = d["terrain"]
	m.region = d["region"]
	m.blight = d["blight"]
	m.fertility = d["fertility"]
	m.wet = d["wet"]
	m.fouled = d["fouled"]
	m.river_flow = d["river_flow"]
	m.region_owned = d["region_owned"]
	m.region_reward = d["region_reward"]
	m.region_reward_pos.assign(d["region_reward_pos"])
	m.start_region = int(d["start_region"])
	m.hearth_spot = d["hearth_spot"]
	m.river_path.assign(d["river_path"])
	m.river_width.assign(d["river_width"])
	return m
