class_name HatDrawing
extends RefCounted
## The temporary procedural captain's hat, seen from above: a white crown with
## a navy band, a glossy black peak and a little brass badge, outlined in a
## slightly uneven dark ink line so it sits with the hand-drawn look. Used
## wherever HatArt has no image for a slot.

const INK := Color(0.11, 0.13, 0.15, 0.7)
const CROWN := Color("#E6E7E1")
const CROWN_SHADE := Color("#B9BCB6")
const BAND := Color("#1F2B38")
const PEAK := Color("#14191E")
const PEAK_SHINE := Color("#56626C")
const BADGE := Color("#B39858")
const SHADOW := Color(0.02, 0.04, 0.05, 0.28)


## Draws the hat centred at `center` with crown radius `radius`, the peak
## pointing at `angle` (radians, 0 = +x).
static func draw_hat(canvas: CanvasItem, center: Vector2, radius: float, angle := 0.0, alpha := 1.0) -> void:
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal()
	var a := func(color: Color) -> Color: return Color(color, color.a * alpha)
	canvas.draw_colored_polygon(_blob(center + Vector2(2, 3), radius * 1.05, 0.0, 3), a.call(SHADOW))
	# Peak: a crescent in front of the crown.
	var peak := PackedVector2Array()
	for i in 13:
		var t := -1.0 + i / 6.0
		peak.append(center + dir * (radius * 0.55 + radius * 0.62 * cos(t * PI / 2.0)) + side * radius * 0.92 * t)
	for i in range(12, -1, -1):
		var t := -1.0 + i / 6.0
		peak.append(center + dir * (radius * 0.35 + radius * 0.25 * cos(t * PI / 2.0)) + side * radius * 0.8 * t)
	canvas.draw_colored_polygon(peak, a.call(PEAK))
	canvas.draw_polyline(_closed(peak), a.call(INK), maxf(radius * 0.09, 1.2), true)
	canvas.draw_line(center + dir * radius * 0.95 - side * radius * 0.35, center + dir * radius * 1.0 + side * radius * 0.15,
		a.call(PEAK_SHINE), maxf(radius * 0.08, 1.0), true)
	# Band and crown, with a soft shade on the side away from the light.
	var band := _blob(center, radius * 0.86, angle, 7)
	canvas.draw_colored_polygon(band, a.call(BAND))
	var crown := _blob(center - dir * radius * 0.05, radius * 0.7, angle, 11)
	canvas.draw_colored_polygon(crown, a.call(CROWN))
	canvas.draw_colored_polygon(_blob(center - dir * radius * 0.05 + Vector2(radius * 0.18, radius * 0.2), radius * 0.42, angle, 5),
		a.call(Color(CROWN_SHADE, 0.55)))
	canvas.draw_polyline(_closed(crown), a.call(INK), maxf(radius * 0.08, 1.2), true)
	canvas.draw_polyline(_closed(band), a.call(INK), maxf(radius * 0.1, 1.4), true)
	# Brass badge at the front of the crown.
	var badge := center + dir * radius * 0.48
	canvas.draw_circle(badge, radius * 0.17, a.call(BADGE))
	canvas.draw_arc(badge, radius * 0.17, 0.0, TAU, 16, a.call(INK), maxf(radius * 0.05, 1.0), true)


## A slightly irregular circle: a hand-drawn outline that stays the same
## every frame (the wobble comes from `seed`, not from time).
static func _blob(center: Vector2, radius: float, angle: float, seed: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := 28
	for i in count:
		var t := TAU * i / count
		var wobble := 1.0 + 0.012 * sin(t * 3.0 + seed) + 0.008 * sin(t * 5.0 + seed * 1.7)
		points.append(center + Vector2.from_angle(t + angle) * radius * wobble)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
