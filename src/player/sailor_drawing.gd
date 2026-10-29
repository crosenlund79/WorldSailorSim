class_name SailorDrawing
extends RefCounted
## The player seen from above (Real Horizon restyle of 0.100b): a sailor in a
## slate softshell jacket with an inflatable lifejacket's collar round the
## neck (a red pull tab, reflective patches), readable shoulders, arms that
## swing a little while walking, and a head with hair behind and a hint of
## face in front. Natural proportions, form by tone rather than outline. Art only: the collision circle and the
## movement are the player's, unchanged. The captain's hat is drawn on top by
## PlayerHat (its centre is the head's centre, the origin).
##
## I027 Tier 4: an adult's proportions (a smaller head against the
## shoulders), a lighter ink line, and the shared walk (HumanGait): the arms
## swing opposite each other and opposite the legs (they swung together
## before: the side was applied twice), the legs and shoes show under the
## jacket as the feet step, and the weight shifts a touch.
##
## `facing` is the unit direction the player faces; `swing` (-1..1) is the
## arms' swing (0 when standing); `phase` and `amount` are HumanGait's
## walking cycle for the feet. The same numbers always give the same drawing.

const INK := Color(0.12, 0.15, 0.17, 0.55)
const JUMPER := Color("#46596A")
const JUMPER_LIGHT := Color("#5D7385")
const LIFEJACKET := Color("#2C3236")
const LIFEJACKET_LIGHT := Color("#454D52")
const TAB := Color("#C2483A")
const REFLECT := Color("#C9CFCF")
const STRIPE := Color("#5D7385")
const SLEEVE := Color("#3E5060")
const SKIN := Color("#C99C7E")
const HAIR := Color("#4A3A2E")
const SHADOW := Color(0.02, 0.04, 0.05, 0.28)
## Half the shoulders' width (across) and half the body's depth (along facing).
const SHOULDER := 17.0
const DEPTH := 9.0
const HEAD := 7.6
## How far a hand travels forward and back while walking.
const SWING := 4.5
const TROUSERS := Color("#2C3542")
const SHOES := Color("#4A3A2C")


## Where a hand is (left: side -1, right: +1), relative to the origin.
static func hand_position(facing: Vector2, swing: float, side_sign: float) -> Vector2:
	var side := facing.orthogonal()
	var shoulder := side * (SHOULDER - 2.0) * side_sign - facing * 2.5
	return shoulder + facing * (5.0 + SWING * swing * side_sign) + side * side_sign * 3.0


## Both hands while walking: [the -1 side's, the +1 side's]. They swing
## opposite each other (hand_position applies the side once).
static func hand_positions(facing: Vector2, swing: float, carrying := false, mug := false) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for side_sign: float in [-1.0, 1.0]:
		var arm_swing := swing
		if carrying and side_sign < 0.0:
			arm_swing = 0.2  # the arm holding the hat moves less
		if mug and side_sign > 0.0:
			arm_swing = 0.25  # and the one holding the coffee, carefully
		out.append(hand_position(facing, arm_swing, side_sign))
	return out


static func draw(canvas: CanvasItem, facing: Vector2, swing: float, carrying := false, mug := false, phase := 0.0, amount := 0.0) -> void:
	var side := facing.orthogonal()
	var body_center := -facing * 2.5 + side * HumanGait.sway(phase, amount)
	canvas.draw_colored_polygon(_ellipse(body_center + Vector2(3, 4), SHOULDER + 1.0, DEPTH + 2.0, side), SHADOW)
	HumanGait.draw_feet(canvas, facing, body_center, phase, amount, TROUSERS, SHOES)
	# Arms first (under the shoulders): sleeve from shoulder to wrist, a hand.
	var right_hand := Vector2.ZERO
	var hands := hand_positions(facing, swing, carrying, mug)
	for side_sign: float in [-1.0, 1.0]:
		var shoulder: Vector2 = body_center + side * (SHOULDER - 3.0) * side_sign
		var hand: Vector2 = hands[0 if side_sign < 0.0 else 1]
		canvas.draw_line(shoulder, hand, INK, 7.4, true)
		canvas.draw_line(shoulder, hand, SLEEVE, 6.0, true)
		canvas.draw_line(shoulder - side * side_sign * 1.2, hand - side * side_sign * 1.2, JUMPER_LIGHT, 1.6, true)
		canvas.draw_circle(hand, 3.2, Color(INK, 0.6))
		canvas.draw_circle(hand, 2.6, SKIN)
		if side_sign > 0.0:
			right_hand = hand
	# Shoulders and body: the jacket, lit from the upper left.
	var body := _ellipse(body_center, SHOULDER, DEPTH, side)
	canvas.draw_colored_polygon(body, JUMPER)
	canvas.draw_colored_polygon(_ellipse(body_center + Vector2(-1.5, -1.5), SHOULDER * 0.72, DEPTH * 0.6, side), Color(JUMPER_LIGHT, 0.6))
	canvas.draw_polyline(_closed(body), INK, 1.1, true)
	# The lifejacket: a padded collar round the neck and down the chest.
	var collar := _ellipse(body_center + facing * 1.0, HEAD + 5.5, DEPTH - 0.5, side)
	canvas.draw_colored_polygon(collar, LIFEJACKET)
	canvas.draw_colored_polygon(_ellipse(body_center + facing * 1.0 + Vector2(-1, -1), HEAD + 3.0, DEPTH - 3.0, side), LIFEJACKET_LIGHT)
	for side_sign: float in [-1.0, 1.0]:
		canvas.draw_line(body_center + facing * 4.0 + side * side_sign * (HEAD + 1.5),
			body_center + facing * 6.5 + side * side_sign * (HEAD + 1.5), REFLECT, 2.0, true)
	canvas.draw_circle(body_center + facing * (DEPTH - 0.5) + side * 4.0, 1.6, TAB)
	# Head: hair on the back, a little face showing in front.
	canvas.draw_circle(Vector2(1.5, 2.0), HEAD + 0.5, SHADOW)
	canvas.draw_circle(Vector2.ZERO, HEAD + 0.8, INK)
	canvas.draw_circle(Vector2.ZERO, HEAD, HAIR)
	canvas.draw_circle(Vector2(-2.0, -2.0), HEAD * 0.55, Color(HAIR.lightened(0.18), 0.6))
	var face := PackedVector2Array()
	for i in 13:
		var a := -PI * 0.5 + PI * i / 12.0
		face.append(facing * HEAD * 0.95 * cos(a) * 0.55 + facing * HEAD * 0.4 + side * HEAD * 0.95 * sin(a))
	canvas.draw_colored_polygon(face, SKIN)
	canvas.draw_circle(facing * (HEAD + 0.6), 1.6, SKIN.darkened(0.15))  # nose
	canvas.draw_arc(Vector2.ZERO, HEAD + 0.4, 0.0, TAU, 24, INK, 0.9, true)
	# The coffee mug in the right hand (Cozy Polish), on top so it reads.
	if mug:
		CoffeeMug.draw_mug(canvas, right_hand + facing * 3.0, 0.75, side.angle())


static func _ellipse(center: Vector2, half_across: float, half_along: float, side: Vector2) -> PackedVector2Array:
	var facing := -side.orthogonal()
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		# Slightly squarer shoulders than a pure ellipse.
		var c := cos(t)
		var s := sin(t)
		var squarer := signf(c) * pow(absf(c), 0.8)
		pts.append(center + side * half_across * squarer + facing * half_along * s)
	return pts


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
