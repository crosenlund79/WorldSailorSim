class_name HumanGait
extends RefCounted
## One way of walking for every person seen from above (I027 Tier 4: the
## Captain, the townsfolk, the girl, and I028's passengers): the walking
## cycle's phase advances with the distance walked, so the cadence always
## matches the speed; the arms swing opposite the legs (the right arm forward
## as the left foot leads); each foot stays planted on the ground while the
## body passes over it and lifts a little as it swings through; the weight
## shifts a touch towards the standing foot. No bounce. When the walker stops
## the amount eases to nothing and the feet settle side by side.
##
## Seen from above, only the shoes peek out from under the coat: a planted
## foot moves back under the body as it walks on, at a little over half its
## speed (a fully planted foot at the Captain's brisk pace would need a stride
## reaching far beyond the body - legs like an X; subtle feet were asked
## for).
##
## Presentation only: never affects movement or collision. The drawings
## (SailorDrawing, TownsfolkDrawing, GirlDrawing) take the phase and the
## amount and keep their own clothes, build and proportions.

## An adult's step at true scale (units, about 1 cm): the body moves this far
## while one foot is planted. A child's is shorter (CHILD_STEP).
const STEP := 56.0
const CHILD_STEP := 34.0
## How far, at most, a foot's forward offset may reach, as a share of the
## step (half the step would keep a planted foot perfectly still).
const REACH := 0.27
## The sideways weight shift (units).
const SWAY := 0.7
## How quickly the walk eases in and out (amount per second).
const EASE := 6.0


## The phase after walking `moved` units with steps of `step`.
static func advance(phase: float, moved: float, step := STEP) -> float:
	return fmod(phase + moved / step * PI, TAU)


## The walk's amount moved towards walking (1) or standing (0).
static func ease_amount(amount: float, walking: bool, delta: float) -> float:
	return move_toward(amount, 1.0 if walking else 0.0, delta * EASE)


## The arms' swing (-1..1): positive brings the right arm forward.
static func swing(phase: float, amount: float) -> float:
	return sin(phase) * amount


## A foot's place along the walking direction (units, + ahead of the hips)
## and its lift (0 planted .. 1 highest), for the left (side_sign -1) or the
## right foot (+1). The left foot leads when the right arm is forward.
static func foot(phase: float, amount: float, side_sign: float, step := STEP) -> Vector2:
	var reach := step * REACH
	var p := phase - PI * 0.5 + (PI if side_sign > 0.0 else 0.0)
	var u := fposmod(p / TAU, 1.0)
	var along: float
	var lift := 0.0
	if u < 0.5:
		along = reach * (1.0 - 4.0 * u)  # planted: from ahead to behind, as fast as the body moves
	else:
		var s := (u - 0.5) * 2.0
		var eased := s * s * (3.0 - 2.0 * s)
		along = -reach + 2.0 * reach * eased  # swinging through, lifted
		lift = sin(s * PI)
	return Vector2(along * amount, lift * amount)


## The sideways weight shift (units along the walker's right): towards the
## planted foot.
static func sway(phase: float, amount: float) -> float:
	return cos(phase) * SWAY * amount


## Draws the shoes under a body (before the body is drawn), each with a short
## trouser cuff above it, the lifted one a little smaller.
## `facing` is the walking direction (unit), `hips` the hips' centre, `k` the
## walker's build.
static func draw_feet(canvas: CanvasItem, facing: Vector2, hips: Vector2, phase: float, amount: float, trousers: Color,
		shoes: Color, k := 1.0, step := STEP, ink := Color(0.12, 0.15, 0.17, 0.5)) -> void:
	var side := facing.orthogonal()
	for side_sign: float in [-1.0, 1.0]:
		var f := foot(phase, amount, side_sign, step)
		var hip := hips + side * side_sign * 4.6 * k
		var at := hip + facing * f.x + side * side_sign * 0.6 * k
		var size := (1.0 - 0.1 * f.y) * k
		canvas.draw_line(at - facing * 6.0 * k * signf(f.x + 0.01), at, Color(trousers, 0.95), 5.0 * k, true)
		var toe := at + facing * 4.4 * size
		var heel := at - facing * 3.6 * size
		canvas.draw_line(heel, toe, ink, 5.6 * size, true)
		canvas.draw_line(heel, toe, shoes, 4.4 * size, true)
		canvas.draw_circle(toe - facing * 0.6, 1.0 * size, Color(shoes.lightened(0.18), 0.7))
