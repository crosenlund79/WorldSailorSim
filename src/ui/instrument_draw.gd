extends RefCounted
## Shared drawing for the interface's procedural pictures (Real Horizon):
## modern marine-instrument faces, data tiles and line pictograms. Colours come
## from UiTheme roles, so a drawing follows the day/night blend as long as its
## owner redraws on UiTheme.palette_changed (or every frame).
##
## Used with preload (no class_name): const Instrument := preload("res://src/ui/instrument_draw.gd")
##
## Angles in degrees are instrument angles: 0 at the top, clockwise.

const HAIRLINE := 1.0
const STROKE := 2.0


static func role(name: StringName) -> Color:
	return UiTheme.color(name)


## The unit vector for an instrument angle (0 = up, clockwise).
static func dir(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(sin(a), -cos(a))


## A flat data tile: sunken glass with a hairline border.
static func tile(ci: CanvasItem, rect: Rect2, fill: StringName = &"surface_sunken", border: StringName = &"border") -> void:
	ci.draw_rect(rect, role(fill))
	ci.draw_rect(rect.grow(-0.5), role(border), false, HAIRLINE)


## Short corner brackets inside a rect (a display's viewfinder marks).
static func corners(ci: CanvasItem, rect: Rect2, length: float, colour: Color) -> void:
	var r := rect.grow(-0.5)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x <= r.get_center().x else -1.0
		var sy := 1.0 if corner.y <= r.get_center().y else -1.0
		ci.draw_line(corner, corner + Vector2(length * sx, 0), colour, HAIRLINE)
		ci.draw_line(corner, corner + Vector2(0, length * sy), colour, HAIRLINE)


## A round instrument face: dark glass, a hairline bezel and an inner ring.
static func face(ci: CanvasItem, center: Vector2, radius: float) -> void:
	ci.draw_circle(center, radius, role(&"surface_sunken"))
	ci.draw_arc(center, radius, 0.0, TAU, 96, role(&"border"), HAIRLINE + 1.0, true)
	ci.draw_arc(center, radius - 4.0, 0.0, TAU, 96, role(&"border_soft"), HAIRLINE, true)


## Fine tick marks on a circle of radius `r` (pointing inwards), from
## `from_deg` to `to_deg` every `step_deg`; every `major_every`-th is longer
## and brighter.
static func ticks(ci: CanvasItem, center: Vector2, r: float, from_deg: float, to_deg: float, step_deg: float,
		major_every := 3, minor_len := 5.0, major_len := 10.0) -> void:
	var minor := Color(role(&"ink_soft"), 0.65)
	var major := role(&"ink")
	var n := int(round((to_deg - from_deg) / step_deg))
	for i in n + 1:
		var deg := from_deg + i * step_deg
		if i == n and is_equal_approx(fposmod(to_deg - from_deg, 360.0), 0.0) and n > 0:
			break  # a full circle: the last tick is the first
		var is_major := major_every > 0 and i % major_every == 0
		var d := dir(deg)
		var length := major_len if is_major else minor_len
		ci.draw_line(center + d * r, center + d * (r - length), major if is_major else minor,
			1.5 if is_major else HAIRLINE, true)


## An arc between two instrument angles (degrees), `width` wide.
static func arc(ci: CanvasItem, center: Vector2, r: float, from_deg: float, to_deg: float, colour: Color, width: float) -> void:
	var points := maxi(int(absf(to_deg - from_deg) / 4.0), 4)
	ci.draw_arc(center, r, deg_to_rad(from_deg - 90.0), deg_to_rad(to_deg - 90.0), points, colour, width, true)


## A slim instrument pointer from the hub to `length`, with a short tail and
## a hub cap.
static func pointer(ci: CanvasItem, center: Vector2, deg: float, length: float, colour: Color, width := 3.0) -> void:
	var d := dir(deg)
	ci.draw_line(center - d * length * 0.12, center + d * length, Color(0, 0, 0, 0.35), width + 2.0, true)
	ci.draw_line(center - d * length * 0.12, center + d * length, colour, width, true)
	ci.draw_circle(center, width + 3.0, role(&"surface_raised"))
	ci.draw_arc(center, width + 3.0, 0.0, TAU, 24, colour, 1.5, true)


## A closed outline through `points` (a line pictogram).
static func outline(ci: CanvasItem, points: PackedVector2Array, colour: Color, width := STROKE) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	ci.draw_polyline(closed, colour, width, true)


## A small chevron/arrow head at `tip` pointing along `forward`.
static func arrow_head(ci: CanvasItem, tip: Vector2, forward: Vector2, length: float, colour: Color) -> void:
	var f := forward.normalized()
	var side := f.orthogonal() * length * 0.55
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - f * length + side, tip - f * length - side]), colour)
