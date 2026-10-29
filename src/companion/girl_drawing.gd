class_name GirlDrawing
extends RefCounted
## The little girl who comes to fetch an animal the Captain did not take
## aboard (I025, A Little More Room Aboard), seen from above like the Captain
## (SailorDrawing) and drawn the same way: form by tone, a soft ink line, lit
## from the upper left. A child's proportions next to him: narrower shoulders
## (about 0.7 of his), a slightly larger head for her size, two short braids
## and a muted red raincoat with its hood down. No full NPC: only what her
## short moment needs - walking, standing, a wave (one arm raised) and the
## box carried in both arms.
##
## `facing` is the unit direction she faces; `swing` (-1..1) the arms'
## swing; `wave` (0..1) how far the right arm is raised; `phase` and `amount`
## the shared walk (HumanGait, a child's step) for her legs and shoes. I027:
## her head a child's, a little smaller than the Captain's (it was larger),
## and the lighter ink line. The same numbers always give the same drawing.

const INK := Color(0.12, 0.15, 0.17, 0.55)
const COAT := Color("#9E4A3C")
const COAT_LIGHT := Color("#B8634F")
const COAT_DARK := Color("#7A372D")
const HOOD := Color("#86402F")
const SKIN := Color("#D2A688")
const HAIR := Color("#8A5A36")
const HAIR_LIGHT := Color("#A8774C")
const TIE := Color("#3E6B73")
const SHADOW := Color(0.02, 0.04, 0.05, 0.26)
## Half the shoulders' width and half the body's depth (SailorDrawing: 17, 9).
const SHOULDER := 12.5
const DEPTH := 7.0
const HEAD := 6.6
const TIGHTS := Color("#3E4A5A")
const BOOTS := Color("#6E3A30")
const SWING := 4.5
## Where a perching bird sits: on her left shoulder (local, before facing).
const SHOULDER_PERCH := Vector2(-2.0, -10.5)


## Her left shoulder, relative to the origin (for the conure to land on).
static func shoulder_point(facing: Vector2) -> Vector2:
	var side := facing.orthogonal()
	return -facing * 2.0 - side * (SHOULDER - 3.5)


static func hand_position(facing: Vector2, swing: float, side_sign: float, wave := 0.0) -> Vector2:
	var side := facing.orthogonal()
	var shoulder := side * (SHOULDER - 2.0) * side_sign - facing * 2.0
	var hand := shoulder + facing * (4.0 + SWING * swing * side_sign) + side * side_sign * 2.0
	if side_sign > 0.0 and wave > 0.0:
		# The raised arm: out to the side and forward, the hand moving a little.
		var raised := shoulder + side * 9.0 + facing * 9.0
		hand = hand.lerp(raised, clampf(wave, 0.0, 1.0))
	return hand


static func draw(canvas: CanvasItem, facing: Vector2, swing: float, wave := 0.0, box := false, phase := 0.0, amount := 0.0) -> void:
	var side := facing.orthogonal()
	var body_center := -facing * 2.0 + side * HumanGait.sway(phase, amount) * 0.7
	canvas.draw_colored_polygon(SailorDrawing._ellipse(body_center + Vector2(2.5, 3.5), SHOULDER + 1.0, DEPTH + 2.0, side), SHADOW)
	HumanGait.draw_feet(canvas, facing, body_center, phase, amount, TIGHTS, BOOTS, 0.75, HumanGait.CHILD_STEP)
	# Braids first: two short plaits down her back, a ribbon at each end.
	for side_sign: float in [-1.0, 1.0]:
		var root := -facing * 4.0 + side * side_sign * 4.5
		var tip := root - facing * 8.0 + side * side_sign * (1.5 + swing * 0.8 * side_sign)
		canvas.draw_line(root, tip, INK, 4.4, true)
		canvas.draw_line(root, tip, HAIR, 3.2, true)
		canvas.draw_circle(tip, 1.6, TIE)
	# Arms (under the shoulders).
	for side_sign: float in [-1.0, 1.0]:
		var shoulder: Vector2 = body_center + side * (SHOULDER - 2.5) * side_sign
		var hand := hand_position(facing, 0.15 if box else swing, side_sign, wave)
		if box:
			hand = facing * 9.0 + side * side_sign * 6.0
		canvas.draw_line(shoulder, hand, INK, 5.6, true)
		canvas.draw_line(shoulder, hand, COAT_DARK, 4.4, true)
		canvas.draw_circle(hand, 2.4, Color(INK, 0.6))
		canvas.draw_circle(hand, 1.9, SKIN)
	# The raincoat: shoulders and body, a little lighter on the upper left.
	var body := SailorDrawing._ellipse(body_center, SHOULDER, DEPTH, side)
	canvas.draw_colored_polygon(body, COAT)
	canvas.draw_colored_polygon(SailorDrawing._ellipse(body_center + Vector2(-1.2, -1.2), SHOULDER * 0.7, DEPTH * 0.55, side), Color(COAT_LIGHT, 0.6))
	canvas.draw_polyline(SailorDrawing._closed(body), INK, 1.0, true)
	# The hood, down, folded behind the neck.
	canvas.draw_colored_polygon(SailorDrawing._ellipse(body_center - facing * 3.0, HEAD * 0.95, DEPTH * 0.55, side), HOOD)
	# Head: hair on the back and top, the face in front.
	canvas.draw_circle(Vector2(1.2, 1.6), HEAD + 0.4, SHADOW)
	canvas.draw_circle(Vector2.ZERO, HEAD + 0.7, INK)
	canvas.draw_circle(Vector2.ZERO, HEAD, HAIR)
	canvas.draw_circle(Vector2(-1.6, -1.6), HEAD * 0.55, Color(HAIR_LIGHT, 0.6))
	# A parting down the middle, towards the braids.
	canvas.draw_line(facing * HEAD * 0.2, -facing * HEAD * 0.9, Color(HAIR.darkened(0.3), 0.8), 0.9, true)
	var face := PackedVector2Array()
	for i in 13:
		var a := -PI * 0.5 + PI * i / 12.0
		face.append(facing * HEAD * 0.95 * cos(a) * 0.5 + facing * HEAD * 0.45 + side * HEAD * 0.9 * sin(a))
	canvas.draw_colored_polygon(face, SKIN)
	canvas.draw_circle(facing * (HEAD + 0.4), 1.2, SKIN.darkened(0.12))
	canvas.draw_arc(Vector2.ZERO, HEAD + 0.35, 0.0, TAU, 24, INK, 0.8, true)
	if box:
		DockBox.draw_carried(canvas, facing * 13.0, side.angle())
