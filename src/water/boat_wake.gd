class_name BoatWake
extends Node2D
## A restrained wake (I027 playtest): while the boat moves through the water,
## two faint diverging lines and a soft stirred band trail from the transom,
## and a little white curls at the bow, all in the deck's coordinates (+x the
## bow). Their strength follows the boat's speed through the water (nothing
## when moored, anchored or becalmed; full at FULL_KN), and short dashes in
## them stream aft at the boat's own pace, as the sea's pattern does
## (SeaSurface.FLOW_PX_PER_KN). Drawn over the water, under the hull (in
## Surroundings); a few lines per frame, redrawn only while under way.

## Below this the water hardly stirs; at FULL_KN the wake is as strong as it gets.
const START_KN := 0.6
const FULL_KN := 7.0
## How far astern the wake reaches (scene units, about cm) at full strength,
## and how wide its arms open (the Kelvin angle, ~19.5°).
const LENGTH := 900.0
const SPREAD := 0.35
const FOAM := Color(0.92, 0.95, 0.94)
const EASE := 1.5

var area: BoatArea
## The hull's stern (x), bow (x) and half-beam at the stern (deck units).
var stern_x := -380.0
var bow_x := 350.0
var half_beam := 90.0
var strength := 0.0
var _flow := 0.0


func setup(boat_area: BoatArea, hull: PackedVector2Array) -> void:
	area = boat_area
	name = "BoatWake"
	if hull.size() >= 3:
		stern_x = INF
		bow_x = -INF
		for p in hull:
			stern_x = minf(stern_x, p.x)
			bow_x = maxf(bow_x, p.x)
		half_beam = 0.0
		for p in hull:
			if p.x < stern_x + 40.0:
				half_beam = maxf(half_beam, absf(p.y))


func _process(delta: float) -> void:
	var kn := GameSession.get_vessel_speed_kn() if GameSession.is_active() and GameSession.is_underway() and not GameSession.is_anchored() else 0.0
	var target := clampf(inverse_lerp(START_KN, FULL_KN, kn), 0.0, 1.0)
	var before := strength
	strength = move_toward(strength, target, EASE * delta)
	_flow = fposmod(_flow + kn * SeaSurface.FLOW_PX_PER_KN * delta, 60.0)
	if strength > 0.005 or before > 0.005:
		queue_redraw()


func _draw() -> void:
	if strength <= 0.005:
		return
	var reach := LENGTH * (0.4 + 0.6 * strength)
	var alpha := 0.32 * strength
	# The stirred band right astern: a soft lighter streak, fading aft.
	var band := PackedVector2Array()
	var band_colours := PackedColorArray()
	var start := Vector2(stern_x + 4.0, 0.0)
	band.append(start + Vector2(0.0, -half_beam * 0.45))
	band.append(start + Vector2(0.0, half_beam * 0.45))
	band.append(start + Vector2(-reach * 0.5, half_beam * 0.8))
	band.append(start + Vector2(-reach * 0.5, -half_beam * 0.8))
	for k in 4:
		band_colours.append(Color(FOAM, alpha * (0.55 if k < 2 else 0.0)))
	draw_polygon(band, band_colours)
	# The two arms, opening from the quarters at the Kelvin angle, in short
	# dashes streaming aft and fading with distance.
	for side: float in [-1.0, 1.0]:
		var from := Vector2(stern_x + 30.0, side * half_beam * 0.95)
		var direction := Vector2(-1.0, side * SPREAD).normalized()
		var d := _flow
		while d < reach:
			var fade := 1.0 - d / reach
			var a := from + direction * d
			var b := from + direction * minf(d + 34.0, reach)
			draw_line(a, b, Color(FOAM, alpha * fade), 2.2 * (0.6 + 0.4 * fade), true)
			d += 60.0
	# A little white curling off the bow.
	var bow := Vector2(bow_x - 6.0, 0.0)
	for side: float in [-1.0, 1.0]:
		draw_line(bow, bow + Vector2(-70.0, side * 26.0), Color(FOAM, alpha * 0.9), 2.4, true)
		draw_line(bow + Vector2(-30.0, side * 12.0), bow + Vector2(-110.0, side * 36.0), Color(FOAM, alpha * 0.45), 1.6, true)
