class_name ClockDial
extends Control
## The sun/moon dial of the clock row (ticket 113, D4 UI half): a tiny sky box with the sun moving along an arc
## while it is up (dawn 05 to night 21) and the moon while it is not (21 to 05). Draws only; Hud pushes the time in.
## The hour windows come from DayNightDef (data/daynight/day_night.tres), the same numbers as the map tint (ticket 107).

const DAY_SKY := Color("4a7cb8")
const DUSK_SKY := Color("8a5a48")
const NIGHT_SKY := Color("141c34")
const GROUND := Color("4a7a3a")
const GROUND_EDGE := Color("2e4f26")
const SUN := Color("f2c44e")
const SUN_CORE := Color("ffe9a3")
const MOON := Color("e6ecf7")
const STAR := Color("cfd9f0")
const EDGE := Color(0.16, 0.13, 0.12)
const GROUND_H := 7.0
const MARGIN_X := 5.0
const MARGIN_TOP := 5.0
const RADIUS := 4.0
## Star dots as fractions of the sky box, drawn only while it is night.
const STARS: Array[Vector2] = [Vector2(0.18, 0.2), Vector2(0.42, 0.12), Vector2(0.7, 0.28), Vector2(0.86, 0.12),
		Vector2(0.28, 0.44), Vector2(0.6, 0.5)]

const MOON_DARK := Color("2c3558")
## Pixel moon disc: radius in pixels (a 9x9 grid).
const MOON_PX := 4

var hours_f: float = 0.0
var def: DayNightDef
## Tonight's moon as a 0-based day count (Settlement.moon_days()); -1 draws the old plain crescent-free moon.
var moon_days: int = -1


## Hud calls this every refresh with the hour of day plus the fraction inside it and tonight's moon day.
func set_time(h: float, d: DayNightDef, moon: int = -1) -> void:
	if is_equal_approx(h, hours_f) and d == def and moon == moon_days:
		return
	hours_f = h
	def = d
	moon_days = moon
	queue_redraw()


## The dial's moon for a day count: {"phase" 0..cycle-1 from new, "name", "lit" 0..1, "waxing", "full", "new"}.
static func moon_model(total_days: int, d: DayNightDef) -> Dictionary:
	if d == null:
		return {"phase": 0, "name": "", "lit": 1.0, "waxing": true, "full": false, "new": false}
	return {"phase": Moon.phase(total_days, d), "name": Moon.phase_name(total_days, d),
			"lit": Moon.lit_fraction(total_days, d), "waxing": Moon.is_waxing(total_days, d),
			"full": Moon.is_full(total_days, d), "new": Moon.is_new(total_days, d)}


## Whether pixel (px, py), each -MOON_PX..MOON_PX from the moon's centre, is inside the disc and, if so, on the lit side
## for phase index `phase` of `cycle` (0 = new, cycle/2 = full; lit on the right while waxing, on the left after).
static func moon_pixel(px: int, py: int, phase: int, cycle: int) -> int:
	var r := float(MOON_PX) + 0.5
	var xn := float(px) / r
	var yn := float(py) / r
	if xn * xn + yn * yn > 1.0:
		return -1  # outside the disc
	var w := sqrt(maxf(1.0 - yn * yn, 0.0))
	var k := cos(TAU * float(phase) / float(maxi(cycle, 1)))
	var waxing := phase * 2 < cycle
	var lit := xn > k * w if waxing else xn < -k * w
	return 1 if lit else 0


# ---------------------------------------------------------------- helpers (static so tests can read them headless)

## True while the moon is up: from night_start to dawn_start.
static func is_night(h: float, d: DayNightDef) -> bool:
	if d == null:
		return false
	var of_day := fposmod(h, 24.0)
	return of_day >= float(d.night_start) or of_day < float(d.dawn_start)


## How far along its arc the body is, 0..1: the sun dawn..night, the moon night..dawn.
static func arc_progress(h: float, d: DayNightDef) -> float:
	if d == null:
		return 0.0
	var of_day := fposmod(h, 24.0)
	var dawn := float(d.dawn_start)
	var night := float(d.night_start)
	if of_day >= dawn and of_day < night:
		return (of_day - dawn) / (night - dawn)
	return fposmod(of_day - night, 24.0) / (24.0 - (night - dawn))


## Where the sun or moon sits in a box of `size`: left to right along the arc, highest in the middle.
static func arc_pos(progress: float, size: Vector2) -> Vector2:
	var horizon := size.y - GROUND_H
	var x := lerpf(MARGIN_X, maxf(size.x - MARGIN_X, MARGIN_X), clampf(progress, 0.0, 1.0))
	var y := horizon - sin(clampf(progress, 0.0, 1.0) * PI) * maxf(horizon - MARGIN_TOP, 0.0)
	return Vector2(x, y)


## The sky colour at an hour: day blue, night navy, warmed through dusk and dawn.
static func sky_color(h: float, d: DayNightDef) -> Color:
	if d == null:
		return DAY_SKY
	var of_day := fposmod(h, 24.0)
	var dark := 1.0 - DayNight.tint_for(of_day, d).g
	dark = clampf(dark / maxf(1.0 - d.night_color.g, 0.0001), 0.0, 1.0)
	var c := DAY_SKY.lerp(NIGHT_SKY, dark)
	var dusk := float(d.dusk_start)
	var night := float(d.night_start)
	var dawn := float(d.dawn_start)
	var day := float(d.day_start)
	if of_day >= dusk and of_day < night:
		c = c.lerp(DUSK_SKY, sin(PI * (of_day - dusk) / maxf(night - dusk, 0.0001)) * 0.7)
	elif of_day >= dawn and of_day < day:
		c = c.lerp(DUSK_SKY, sin(PI * (of_day - dawn) / maxf(day - dawn, 0.0001)) * 0.7)
	return c


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var horizon := size.y - GROUND_H
	var sky := sky_color(hours_f, def)
	var bands := 4
	for i in bands:
		var shade := sky.lerp(sky.lightened(0.16), float(i) / float(bands - 1))
		draw_rect(Rect2(0.0, horizon * float(i) / bands, size.x, horizon / bands + 1.0), shade)
	if def != null and is_night(hours_f, def):
		for star in STARS:
			draw_rect(Rect2(Vector2(star.x * size.x, star.y * horizon).floor(), Vector2(2, 2)), STAR)
	draw_rect(Rect2(0.0, horizon, size.x, GROUND_H), GROUND)
	draw_rect(Rect2(0.0, horizon, size.x, 2.0), GROUND_EDGE)
	var pos := arc_pos(arc_progress(hours_f, def), size)
	if def != null and is_night(hours_f, def):
		if moon_days < 0:
			draw_circle(pos, RADIUS, MOON)
			draw_circle(pos + Vector2(1.8, -1.2), RADIUS - 0.5, sky)  # the crescent bite
		else:
			var ph := Moon.phase(moon_days, def)
			var origin := pos.round()
			for py in range(-MOON_PX, MOON_PX + 1):
				for px in range(-MOON_PX, MOON_PX + 1):
					var v := moon_pixel(px, py, ph, def.moon_cycle_days)
					if v >= 0:
						draw_rect(Rect2(origin + Vector2(px, py), Vector2.ONE), MOON if v == 1 else MOON_DARK)
	else:
		draw_circle(pos, RADIUS + 2.0, Color(SUN, 0.28))
		draw_circle(pos, RADIUS, SUN)
		draw_circle(pos - Vector2(1.0, 1.0), 1.5, SUN_CORE)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0)), EDGE, false, 1.0)
