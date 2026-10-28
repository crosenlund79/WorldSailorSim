class_name AnchorSignals
extends Node2D
## What tells everyone the boat is at anchor (Iteration 18), on deck:
##   - the black anchor ball, hoisted in the forward rigging (on the
##     forestay, between the mast and the bow) - the day shape;
##   - the anchor rode: from the bow fitting down into the water ahead,
##     slack in good holding, straighter when the anchor is dragging;
##   - a small marker buoy over the anchor, bobbing gently (a presentation
##     choice for clarity: it marks where the anchor lies).
## The Magic Anchor (0.105b) looks a little different, modestly: a small
## brass mechanism at the bow fitting, a brass-tinted line kept short and
## stylised (whatever the depth: no rope drawn across the sea to suggest
## hundreds of metres), and a brass band on the buoy.
## Sprite Workshop (0.105b): the buoy and the ball can be replaced by drawn
## PNGs (BUOY_ID, BALL_ID; centred on the same spot, drawn BUOY_SIZE and
## BALL_SIZE across); the procedural drawing is the fallback.
## Only at anchor: not moored, not underway, not while merely waiting at an
## anchorage. At night the white anchor light (BoatLighting, "anchor") shows
## too; the ball stays in place but the light is what is seen.
## Everything is in the boat's own coordinates, so it turns with the boat in
## every view. Reads GameSession only (presentation; nothing is saved).

const BALL := Color("#1c1c1e")
const ROPE := Color("#C9C3B2")
const BUOY := Color("#D9783A")
const BUOY_BAND := Color("#E6E7E1")
const BOB_SPEED := 1.3
const BALL_RADIUS := 12.0
const BRASS := Color("#B39858")
const BRASS_DARK := Color("#6E5E3A")
## The Magic Anchor's line, drawn this long whatever the scope or depth.
const MAGIC_LINE := 64.0
const BUOY_ID := &"equipment.anchor.buoy"
const BALL_ID := &"equipment.anchor.ball_day"
const BUOY_SIZE := 24.0
const BALL_SIZE := 26.0

var bow := Vector2.ZERO
var mast := Vector2.ZERO
var _clock := 0.0
var _buoy_art: Texture2D
var _ball_art: Texture2D


func setup(boat_area: BoatArea, lighting: BoatLighting) -> void:
	name = "AnchorSignals"
	z_index = 24
	z_as_relative = false
	var bounds := lighting.boat_bounds() if lighting else boat_area.walkable_bounds
	bow = Vector2(bounds.end.x - 4.0, bounds.get_center().y)
	var rig := boat_area.get_node_or_null(^"SailRig") as SailRig
	mast = rig.mast if rig else bounds.get_center()
	_buoy_art = ArtworkResolver.get_artwork(BUOY_ID)
	_ball_art = ArtworkResolver.get_artwork(BALL_ID)
	GameSession.anchor_changed.connect(_refresh)
	GameSession.state_replaced.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = GameSession.is_active() and GameSession.is_anchored()
	set_process(visible)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


## Where the ball hangs, the rode's end and the buoy (boat coordinates).
func get_ball_position() -> Vector2:
	return mast.lerp(bow, 0.5) + Vector2(0, -2)


func get_buoy_position() -> Vector2:
	var anchor := GameSession.get_anchor()
	# Short enough to stay in view: the rode leads off the bow at an angle,
	# as a boat lying to its anchor sheers a little.
	var length := 70.0 + float(anchor.scope) * 6.0
	if anchor.kind == AnchorState.KIND_MAGIC:
		length = MAGIC_LINE
	if anchor.holding == AnchorState.HOLDING_DRAGGING:
		length *= 0.8
	var bob := Vector2(0, sin(_clock * BOB_SPEED) * 2.0) if not SettingsManager.get_reduce_motion() else Vector2.ZERO
	return bow + Vector2.from_angle(deg_to_rad(40.0)) * length + bob


## Where the buoy's picture is drawn (boat coordinates; centred on the buoy).
func get_buoy_rect() -> Rect2:
	return Rect2(get_buoy_position() - Vector2.ONE * BUOY_SIZE / 2.0, Vector2.ONE * BUOY_SIZE)


func uses_buoy_replacement() -> bool:
	return _buoy_art != null


func _draw() -> void:
	if not visible:
		return
	var anchor := GameSession.get_anchor()
	var buoy := get_buoy_position()
	# The rode: a gentle curve from the bow fitting into the water (taut when
	# dragging), fading as it goes under.
	var sag := 6.0 if anchor.holding == AnchorState.HOLDING_DRAGGING else 22.0
	var points := PackedVector2Array()
	for i in 13:
		var f := i / 12.0
		points.append(bow.lerp(buoy - (buoy - bow).normalized() * 10.0, f) + Vector2(0, sin(f * PI) * sag * 0.5))
	var magic := anchor.kind == AnchorState.KIND_MAGIC
	var rope := ROPE.lerp(BRASS, 0.55) if magic else ROPE
	for i in range(1, points.size()):
		var f := float(i) / points.size()
		draw_line(points[i - 1], points[i], Color(rope, 0.95 - f * 0.7), 2.4, true)
	# The buoy: a small round float with a pale band and a ring of ripples.
	draw_arc(buoy, 12.0 + sin(_clock * BOB_SPEED * 1.6) * 1.2, 0.0, TAU, 24, Color(1, 1, 1, 0.22), 1.6, true)
	if _buoy_art:
		draw_texture_rect(_buoy_art, get_buoy_rect(), false)
	else:
		draw_circle(buoy, 9.0, BUOY)
		draw_arc(buoy, 9.0, 0.0, TAU, 20, Color("#2A3236"), 1.6, true)
		draw_line(buoy + Vector2(-8.0, 0), buoy + Vector2(8.0, 0), BRASS if magic else BUOY_BAND, 2.8, true)
	if magic:
		_draw_brass_mechanism()
	# The black ball, hoisted on the forestay.
	var ball := get_ball_position()
	draw_circle(ball + Vector2(2.0, 3.0), BALL_RADIUS, Color(0, 0, 0, 0.25))
	if _ball_art:
		draw_texture_rect(_ball_art, Rect2(ball - Vector2.ONE * BALL_SIZE / 2.0, Vector2.ONE * BALL_SIZE), false)
		return
	draw_circle(ball, BALL_RADIUS, BALL)
	draw_arc(ball, BALL_RADIUS, 0.0, TAU, 28, Color("#5a5a5e"), 1.6, true)
	draw_circle(ball + Vector2(-3.5, -3.5), 3.0, Color(1, 1, 1, 0.25))


## The Magic Anchor's little brass mechanism on the bow fitting: a toothed
## wheel with a hub, and a soft glint.
func _draw_brass_mechanism() -> void:
	var c := bow + Vector2(-6.0, 0.0)
	var turn := 0.0 if SettingsManager.get_reduce_motion() else _clock * 0.4
	for i in 8:
		var a := turn + i * TAU / 8.0
		draw_line(c + Vector2.from_angle(a) * 5.0, c + Vector2.from_angle(a) * 8.5, BRASS_DARK, 3.0, true)
	draw_circle(c, 6.5, BRASS)
	draw_arc(c, 6.5, 0.0, TAU, 20, BRASS_DARK, 1.4, true)
	draw_circle(c, 2.2, BRASS_DARK)
	draw_circle(c + Vector2(-2.5, -2.5), 1.6, Color(1, 1, 1, 0.45))
