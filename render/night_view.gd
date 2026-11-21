class_name NightView
extends Node2D
## The night render (ticket 135): flat stepped pools of warm light around lit lamps, lit windows on houses and
## working buildings, and ember pixels on a working kiln. Everything comes from NightRenderModel, so the sim's lit
## rule stays in one place (Settlement.is_lit, ticket 133); draws nothing by day. Lives in MapView.fx, so the map's
## night tint darkens it with the rest of the world (the HUD is a CanvasLayer and is never tinted).

const TILE := ArtLibrary.TILE
## How often the walker counts behind the lit windows are refreshed (the light state itself changes hourly).
const REFRESH_SECONDS := 0.5
## Ember pixels of a working kiln: three flat warm dots low in the sprite.
const EMBER_COLOR := Color(1.0, 0.55, 0.2)
const EMBER_STEPS := 3
## The Night Watch walker (ticket 143): a small pool, walked forward along its route and back at this pace, with a
## warm lantern dot at its centre.
const LANTERN_SECONDS_PER_TILE := 0.35
const LANTERN_RADIUS := 0.9
const LANTERN_COLOR := Color(1.0, 0.9, 0.6)

var settlement: Settlement
var _pools: Array[Dictionary] = []
var _windows: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _lanterns: Array[Dictionary] = []
var _since_refresh := 0.0
## Time since setup: drives the lantern walker along its route at a flat pace (render only).
var _time := 0.0


func setup(s: Settlement) -> void:
	settlement = s
	z_index = 5  # inside MapView.fx: above the y-sorted objects and their glows
	refresh()


## Rebuild the model and the drawing.
func refresh() -> void:
	_pools = NightRenderModel.pools(settlement) if settlement != null else []
	_windows = NightRenderModel.windows(settlement) if settlement != null else []
	_embers = NightRenderModel.embers(settlement) if settlement != null else []
	_lanterns = NightRenderModel.lantern_walkers(settlement) if settlement != null else []
	queue_redraw()


func _process(delta: float) -> void:
	if settlement == null:
		return
	_time += delta
	_since_refresh += delta
	if _since_refresh >= REFRESH_SECONDS:
		_since_refresh = 0.0
		refresh()
	elif not _lanterns.is_empty():
		queue_redraw()  # the lantern walker moves every frame


func _draw() -> void:
	for p in _pools:
		var centre := (Vector2(p["origin"]) + Vector2(p["size"]) * 0.5) * TILE
		var radius := float(p["radius"]) * TILE
		for step in NightRenderModel.POOL_STEPS:
			# Widest and palest first: three flat discs make three visible steps, not a soft gradient.
			var col := NightRenderModel.POOL_COLOR
			col.a = NightRenderModel.POOL_ALPHA * float(step + 1)
			var k := 1.0 - float(step) / float(NightRenderModel.POOL_STEPS)
			draw_circle(centre, radius * k, col)
	for w in _windows:
		_draw_windows(w)
	for e in _embers:
		_draw_embers(e)
	for e in _lanterns:
		_draw_lantern(e)


## The Night Watch walker's small lantern pool: the walker advances one route tile every LANTERN_SECONDS_PER_TILE and
## turns back at the last one, so it loops the road all night. Three flat steps, like a lamp pool but smaller.
func _draw_lantern(e: Dictionary) -> void:
	var route: Array = e["route"]
	var n := route.size()
	if n == 0:
		return
	var span := maxi(n * 2 - 2, 1)
	var i := int(_time / LANTERN_SECONDS_PER_TILE) % span
	if i >= n:
		i = span - i
	var centre := (Vector2(route[i]) + Vector2(0.5, 0.5)) * TILE
	var radius := LANTERN_RADIUS * TILE
	for step in NightRenderModel.POOL_STEPS:
		var col := NightRenderModel.POOL_COLOR
		col.a = NightRenderModel.POOL_ALPHA * float(step + 1) * 2.0
		var k := 1.0 - float(step) / float(NightRenderModel.POOL_STEPS)
		draw_circle(centre, radius * k, col)
	draw_circle(centre, 2.0, LANTERN_COLOR)


## The warm window pixels of the building's sprite, drawn over it at full strength: a lit window overlay.
func _draw_windows(e: Dictionary) -> void:
	var art := _art_id(e)
	var tex := ArtLibrary.window_texture(art) if art != "" else null
	if tex == null:
		return
	draw_texture(tex, ArtLibrary.sprite_rect(art, e["origin"], e["size"]).position)


## Three flat ember pixels in the lower body of the sprite.
func _draw_embers(e: Dictionary) -> void:
	var art := _art_id(e)
	if art == "":
		return
	var r := ArtLibrary.sprite_rect(art, e["origin"], e["size"])
	for i in EMBER_STEPS:
		var p := Vector2(r.position.x + r.size.x * (0.4 + 0.12 * i), r.position.y + r.size.y * (0.82 - 0.04 * i))
		draw_rect(Rect2(p, Vector2(2, 2)), EMBER_COLOR)


## The building's tier art where the manifest has it, else its base sprite (as PlacementView draws it).
func _art_id(e: Dictionary) -> String:
	var b: Building = settlement.buildings.get(int(e["id"]))
	if b == null:
		return ""
	var id := b.tier_art_id(settlement.registry)
	return id if id != "" and ArtLibrary.has_building(id) else b.def.id
