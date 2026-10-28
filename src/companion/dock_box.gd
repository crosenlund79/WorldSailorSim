class_name DockBox
extends Node2D
## The small cardboard box on the dock (I025, DockEncounterScene): open, its
## flaps folded out, a strip of brown tape, a soft shadow - seen a little from
## the front like the animals. Drawn in two parts so an animal can sit in it:
## the back (inside, back and side flaps) below the animal and the front wall
## above it. Never closed and never a cage: the conure perches on the rim.
## Presentation only.

enum Part { BACK, FRONT }

const CARD := Color("#B48A5E")
const CARD_LIGHT := Color("#C9A273")
const CARD_DARK := Color("#8C6A45")
const INSIDE := Color("#6E5236")
const TAPE := Color("#9A7348")
const INK := Color(0.12, 0.12, 0.1, 0.6)
const SHADOW := Color(0.02, 0.04, 0.05, 0.24)
## Half the opening's width, its depth (top view) and the front wall's height.
const HALF_WIDTH := 24.0
const DEPTH := 18.0
const WALL := 14.0
## The front rim's middle, relative to the box's ground point (a perch).
const RIM := Vector2(0.0, -WALL)

@export var part := Part.BACK


func _draw() -> void:
	if part == Part.BACK:
		draw_back(self)
	else:
		draw_front(self)


## The opening's corners: back-left, back-right, front-right, front-left
## (the front edge is the top of the front wall).
static func _opening() -> PackedVector2Array:
	var front := -WALL
	var back := front - DEPTH
	return PackedVector2Array([Vector2(-HALF_WIDTH + 2.0, back), Vector2(HALF_WIDTH - 2.0, back),
		Vector2(HALF_WIDTH, front), Vector2(-HALF_WIDTH, front)])


static func draw_back(canvas: CanvasItem) -> void:
	var o := _opening()
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-HALF_WIDTH - 2, 2), Vector2(HALF_WIDTH + 6, 2),
		Vector2(HALF_WIDTH + 8, -6), Vector2(-HALF_WIDTH, -6)]), SHADOW)
	# Back flap folded out (leaning back), side flaps folded out sideways.
	var back_flap := PackedVector2Array([o[0], o[1], o[1] + Vector2(3, -11), o[0] + Vector2(-3, -11)])
	canvas.draw_colored_polygon(back_flap, CARD_DARK)
	canvas.draw_polyline(_closed(back_flap), INK, 1.0, true)
	for left in [true, false]:
		var a: Vector2 = o[0] if left else o[1]
		var b: Vector2 = o[3] if left else o[2]
		var out := Vector2(-10.0 if left else 10.0, 3.0)
		var flap := PackedVector2Array([a, b, b + out, a + out + Vector2(0, -2)])
		canvas.draw_colored_polygon(flap, CARD_LIGHT if left else CARD)
		canvas.draw_polyline(_closed(flap), INK, 1.0, true)
	# The inside, darker towards the back.
	canvas.draw_colored_polygon(o, INSIDE)
	canvas.draw_colored_polygon(PackedVector2Array([o[0], o[1], o[1] + Vector2(0, 6), o[0] + Vector2(0, 6)]), INSIDE.darkened(0.2))


static func draw_front(canvas: CanvasItem) -> void:
	var o := _opening()
	var wall := PackedVector2Array([o[3], o[2], Vector2(HALF_WIDTH, 0), Vector2(-HALF_WIDTH, 0)])
	canvas.draw_colored_polygon(wall, CARD)
	# Light on the left, a darker crease at the bottom.
	canvas.draw_colored_polygon(PackedVector2Array([o[3], o[3] + Vector2(10, 0), Vector2(-HALF_WIDTH + 10, 0), Vector2(-HALF_WIDTH, 0)]), Color(CARD_LIGHT, 0.5))
	canvas.draw_line(Vector2(-HALF_WIDTH, -1.5), Vector2(HALF_WIDTH, -1.5), Color(CARD_DARK, 0.7), 1.5, true)
	# A strip of tape down the middle and the front flap, folded down over it.
	canvas.draw_rect(Rect2(-3.5, -WALL, 7.0, WALL), TAPE)
	var flap := PackedVector2Array([o[3], o[2], o[2] + Vector2(1, 5), o[3] + Vector2(-1, 5)])
	canvas.draw_colored_polygon(flap, CARD_LIGHT)
	canvas.draw_polyline(_closed(wall), INK, 1.1, true)
	canvas.draw_polyline(_closed(flap), INK, 0.9, true)


## The box carried in a child's arms (seen from above, flaps folded in).
static func draw_carried(canvas: CanvasItem, at: Vector2, angle: float) -> void:
	canvas.draw_set_transform(at, angle, Vector2.ONE)
	var rect := Rect2(-HALF_WIDTH * 0.6, -DEPTH * 0.55, HALF_WIDTH * 1.2, DEPTH * 1.1)
	canvas.draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size), SHADOW)
	canvas.draw_rect(rect, CARD)
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.45)), CARD_LIGHT)
	canvas.draw_line(Vector2(rect.position.x, 0), Vector2(rect.end.x, 0), CARD_DARK, 1.0, true)
	canvas.draw_rect(rect, INK, false, 1.0)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
