class_name SailRig
extends Node2D
## The deck's sails, seen from above: mainsail on the boom, jib on the
## forestay and, on deep downwind angles, the spinnaker forward of the bow.
##
## The rig only presents state: it reads the propulsion state (mode, true wind
## angle, spinnaker) from GameSession every frame and never decides anything
## itself, so it looks the same whichever scene was open when the state changed.
## Trim follows the wind smoothly; on entering the scene it snaps to the
## current state (no animation from a stale pose).
##
## Sails "breathe": while set they move very slightly around their trim
## (fullness, a fraction of a degree of angle, a gentle ripple along the
## leech), the spinnaker a little more. The motion runs on real time, is
## purely cosmetic and never reaches the simulation: speed and propulsion
## come only from PropulsionState. Furled sails do not move.
##
## Boat frame: +x is forward, -y is port, +y is starboard. Sails lie on the
## leeward side: wind from starboard puts them to port.
##
## Attachment points come from the deck scene's layout markers
## (Layout/SailMarkers: Mast, Tack, BoomEnd, Traveller, JibSheetLead,
## SpinnakerSheetLead; sheet leads are given on the starboard side and
## mirrored), so each vessel rigs its own sails. Without markers the starter
## sloop's values below are used.
##
## Art: each sail (and the boom) is drawn procedurally, or with a sprite from
## the vessel's visual profile (slots MainSailVisual, HeadSailVisual,
## SpinnakerVisual, BoomVisual). A sail sprite is stretched over the sail's
## current shape as a strip of triangles: the image's left edge is the luff
## (head/tack), its right edge the clew, its top edge the curved leech (for
## the spinnaker: the leading edge) and its bottom edge the foot. So the
## sprite follows the trim, the belly and the breathing automatically.

# Real Horizon: white Dacron, anodised spars, a navy sail cover, a
# restrained asymmetric in slate and white.
const SAIL := Color("#E3E2DA")
const SAIL_SHADE := Color("#BDBEB7")
const SAIL_EDGE := Color("#7D8483")
const BOOM := Color("#8D979A")
const COVER := Color("#2F3E4A")
const SPINNAKER := Color("#5D7F95")
const SPINNAKER_STRIPE := Color("#E3E2DA")
const SHEET := Color(0.80, 0.79, 0.75, 0.75)
## The sails' shadow on the deck and water (light from the upper left).
const SAIL_SHADOW := Color(0.04, 0.07, 0.09, 0.16)
const SHADOW_OFFSET := Vector2(10, 14)

## Defaults (the starter sloop) used when the scene has no SailMarkers.
const MAST := Vector2(182, 0)
const BOOM_LENGTH := 400.0
const JIB_TACK := Vector2(470, 0)
const TRAVELLER := Vector2(-360, 0)
const JIB_SHEET_LEAD := Vector2(-250, 120)
const SPINNAKER_SHEET_LEAD := Vector2(-430, 150)
## Spinnaker pole length and leading-edge depth relative to the foretriangle
## base (mast to tack): 270 and 560 units on the sloop.
const SPINNAKER_POLE_RATIO := 0.94
const SPINNAKER_DEPTH_RATIO := 1.945
## While the spinnaker flies, the deck view eases this far forward so the
## whole sail stays on screen (the stern still fits).
const SPINNAKER_VIEW_SHIFT := 110.0
## Sail motion (amplitudes at full set; frequencies in Hz, deliberately slow).
const MAIN_SWAY_DEG := 0.8
const JIB_SWAY_DEG := 1.2
const MAIN_BREATH := 0.06
const JIB_BREATH := 0.08
const SPINNAKER_BREATH := 0.07
const SPINNAKER_SWAY_DEG := 2.5
const LEECH_RIPPLE_PX := 2.0
## Main: boom angle from the centreline = clamp(|twa| * 0.55 - 17, 5, 50) degrees.
const MAIN_MIN_DEG := 5.0
const MAIN_MAX_DEG := 50.0
const JIB_MIN_DEG := 6.0
const JIB_MAX_DEG := 38.0
## How fast the trim follows the wind (1/s) and the spinnaker hoists/drops.
const TRIM_RATE := 1.6
const HOIST_RATE := 0.8

## Where to read the attachment markers from.
@export var markers_path: NodePath = ^"../Layout/SailMarkers"

## Attachment points (scene units), from the markers.
var mast := MAST
var tack := JIB_TACK
var boom_length := BOOM_LENGTH
var traveller := TRAVELLER
var jib_sheet_lead := JIB_SHEET_LEAD
var spinnaker_sheet_lead := SPINNAKER_SHEET_LEAD
var jib_foot := 288.0
var spinnaker_pole := 270.0
var spinnaker_depth := 560.0
## Sail sprites (null = procedural).
var main_texture: Texture2D
## The sailcloth (I020, the sailmaker): the drawn sails' colours, and a tint
## for sail sprites (white for the classic cream). A look only.
var sail_colour := SAIL
var sail_shade := SAIL_SHADE
var cloth_tint := Color.WHITE
var jib_texture: Texture2D
var spinnaker_texture: Texture2D
var boom_texture: Texture2D

## Current pose (eased towards the target).
var main_angle_deg := 0.0      # signed: - = boom to port, + = boom to starboard
var jib_angle_deg := 0.0
var set_amount := 0.0          # 0 = furled, 1 = sails drawing
var spinnaker_amount := 0.0    # 0 = down, 1 = fully set
## Real seconds of sail motion (cosmetic only).
var animation_time := 0.0
var _twa := 0.0


func _ready() -> void:
	read_markers()
	snap()


## Reads the attachment points from the layout markers (if present).
func read_markers() -> void:
	var markers := get_node_or_null(markers_path)
	if markers:
		mast = _marker(markers, "Mast", MAST)
		tack = _marker(markers, "Tack", JIB_TACK)
		boom_length = mast.distance_to(_marker(markers, "BoomEnd", MAST - Vector2(BOOM_LENGTH, 0)))
		traveller = _marker(markers, "Traveller", TRAVELLER)
		jib_sheet_lead = _marker(markers, "JibSheetLead", JIB_SHEET_LEAD)
		spinnaker_sheet_lead = _marker(markers, "SpinnakerSheetLead", SPINNAKER_SHEET_LEAD)
	var base := mast.distance_to(tack)
	jib_foot = base
	spinnaker_pole = base * SPINNAKER_POLE_RATIO
	spinnaker_depth = base * SPINNAKER_DEPTH_RATIO


static func _marker(markers: Node, marker_name: String, fallback: Vector2) -> Vector2:
	var marker := markers.get_node_or_null(marker_name) as Node2D
	return marker.position if marker else fallback


## Uses the sail sprites of a visual profile (missing ones stay procedural).
## Sails of `cloth` (HarbourTrades sail cloth id).
func set_cloth(cloth: String) -> void:
	var colours := HarbourTrades.sail_colours(cloth)
	sail_colour = colours[0]
	sail_shade = colours[1]
	cloth_tint = Color(sail_colour.r / SAIL.r, sail_colour.g / SAIL.g, sail_colour.b / SAIL.b).clamp()
	queue_redraw()


func apply_profile(profile: VesselVisualProfile) -> void:
	main_texture = profile.get_texture(&"MainSailVisual") if profile else null
	jib_texture = profile.get_texture(&"HeadSailVisual") if profile else null
	spinnaker_texture = profile.get_texture(&"SpinnakerVisual") if profile else null
	boom_texture = profile.get_texture(&"BoomVisual") if profile else null
	queue_redraw()


## Iteration 17: the rig is drawn above the captain (it is overhead). While
## `see_through` (the captain) is under a sail or the boom, the rig fades to
## SEE_THROUGH_ALPHA so the captain stays in view.
const SEE_THROUGH_ALPHA := 0.45
var see_through: Node2D


## Whether a deck point is under a set sail or the boom (boat frame).
func covers(point: Vector2) -> bool:
	var shape := get_shape()
	if set_amount > 0.05:
		var main: PackedVector2Array = (shape.main.leech as PackedVector2Array).duplicate()
		main.append(mast)
		if Geometry2D.is_point_in_polygon(point, main):
			return true
		if spinnaker_amount < 0.95:
			var jib: PackedVector2Array = (shape.jib.leech as PackedVector2Array).duplicate()
			if Geometry2D.is_point_in_polygon(point, jib):
				return true
	var clew: Vector2 = shape.main.clew
	return Geometry2D.get_closest_point_to_segment(point, mast, clew).distance_to(point) < 18.0


func _process(delta: float) -> void:
	if see_through:
		var under := covers(see_through.position)
		modulate.a = move_toward(modulate.a, SEE_THROUGH_ALPHA if under else 1.0, delta * 3.0)
	var target := _target()
	var k := 1.0 - exp(-TRIM_RATE * delta)
	main_angle_deg = lerpf(main_angle_deg, target.main, k)
	jib_angle_deg = lerpf(jib_angle_deg, target.jib, k)
	set_amount = move_toward(set_amount, target.set, delta * HOIST_RATE * 1.5)
	spinnaker_amount = move_toward(spinnaker_amount, target.spinnaker, delta * HOIST_RATE)
	_twa = target.twa
	animation_time += delta
	_frame_view()
	queue_redraw()


## Jumps to the current state without animating (scene entry, loading).
func snap() -> void:
	var target := _target()
	main_angle_deg = target.main
	jib_angle_deg = target.jib
	set_amount = target.set
	spinnaker_amount = target.spinnaker
	_twa = target.twa
	_frame_view()
	queue_redraw()


## Shifts the deck camera forward with the spinnaker (presentation only).
func _frame_view() -> void:
	var camera := get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera:
		# In the course view the camera frames the whole boat itself.
		camera.offset.x = 0.0 if camera.get_meta(&"course_view", false) else SPINNAKER_VIEW_SHIFT * spinnaker_amount


## Side the sails are on: "port", "starboard" or "" when furled/centred.
func get_sail_side() -> String:
	if set_amount < 0.5 or absf(main_angle_deg) < 0.5:
		return ""
	return "port" if main_angle_deg < 0.0 else "starboard"


func is_furled() -> bool:
	return set_amount < 0.01


func is_spinnaker_visible() -> bool:
	return spinnaker_amount > 0.01


## Target pose for the current propulsion state.
func _target() -> Dictionary:
	var target := {"main": 0.0, "jib": 0.0, "set": 0.0, "spinnaker": 0.0, "twa": 0.0}
	if not GameSession.is_active() or not GameSession.is_underway() or GameSession.is_anchored() or GameSession.is_holding_at_anchorage():
		return target  # in harbour, at anchor (Iteration 13) and waiting at an anchorage (18) the sails are furled
	var state := GameSession.get_propulsion()
	if not state.initialised or not state.sails_set():
		return target
	var twa := state.true_wind_angle
	# Leeward: wind from starboard (+) -> sails to port (-).
	var lee := -1.0 if twa >= 0.0 else 1.0
	var a := absf(twa)
	target.main = lee * clampf(a * 0.55 - 17.0, MAIN_MIN_DEG, MAIN_MAX_DEG)
	target.jib = lee * clampf(a * 0.4 - 10.0, JIB_MIN_DEG, JIB_MAX_DEG)
	target.set = 1.0
	target.spinnaker = 1.0 if state.spinnaker else 0.0
	target.twa = twa
	return target


# --- Geometry -----------------------------------------------------------------------

## Everything drawn, for the current pose at animation time `time` (defaults
## to now). Tests use it to check attachment points and motion.
func get_shape(time := -1.0) -> Dictionary:
	var t := animation_time if time < 0.0 else time
	return {"main": _main_shape(t), "jib": _jib_shape(t), "spinnaker": _spinnaker_shape(t)}


func _main_shape(t: float) -> Dictionary:
	var motion := set_amount
	var angle := deg_to_rad(main_angle_deg + motion * MAIN_SWAY_DEG * sin(t * TAU * 0.13) * signf(main_angle_deg))
	var clew := mast + Vector2(-cos(angle), sin(angle)) * boom_length
	var lee := signf(main_angle_deg) if main_angle_deg != 0.0 else 1.0
	var chord := clew - mast
	var normal := _leeward_normal(chord, lee)
	var fullness := 0.13 * set_amount * (1.0 + motion * MAIN_BREATH * sin(t * TAU * 0.21 + 0.7))
	var control := (mast + clew) / 2.0 + normal * chord.length() * fullness * 2.0
	var leech := _rippled(_curve(mast, clew, control, 18), normal, motion * LEECH_RIPPLE_PX * 0.6, t, 0.9)
	return {"head": mast, "clew": clew, "leech": leech, "foot_control": (mast + clew) / 2.0 + normal * chord.length() * fullness * 0.4}


func _jib_shape(t: float) -> Dictionary:
	var motion := set_amount * (1.0 - spinnaker_amount)
	var angle := deg_to_rad(jib_angle_deg + motion * JIB_SWAY_DEG * sin(t * TAU * 0.17 + 1.9) * signf(jib_angle_deg))
	var clew := tack + Vector2(-cos(angle), sin(angle)) * jib_foot
	var lee := signf(jib_angle_deg) if jib_angle_deg != 0.0 else 1.0
	var chord := clew - tack
	var normal := _leeward_normal(chord, lee)
	var fullness := 0.3 * (1.0 + motion * JIB_BREATH * sin(t * TAU * 0.27 + 2.4))
	var control := (tack + clew) / 2.0 + normal * chord.length() * fullness
	var leech := _rippled(_curve(tack, clew, control, 16), normal, motion * LEECH_RIPPLE_PX, t, 1.1)
	return {"tack": tack, "clew": clew, "leech": leech, "foot_control": (tack + clew) / 2.0 + normal * chord.length() * 0.05}


## The spinnaker: a big crescent flying ahead of the bow. Its tack is at the
## end of the pole (from the mast, out to windward), its clew is sheeted to
## the leeward quarter and its head is held by the halyard from the mast. On a
## broad reach it is swung out to leeward; dead downwind it is centred ahead.
func _spinnaker_shape(t: float) -> Dictionary:
	var lee := -1.0 if _twa >= 0.0 else 1.0
	var run := clampf((absf(_twa) - 115.0) / 65.0, 0.0, 1.0)
	var amount := spinnaker_amount
	var motion := amount
	# Pole angle from the centreline: forward on a reach, squared back running.
	var pole_angle := deg_to_rad(lerpf(22.0, 58.0, run))
	var kite_tack := mast + Vector2(cos(pole_angle), -lee * sin(pole_angle)) * spinnaker_pole
	var lead_y := absf(spinnaker_sheet_lead.y)
	var clew := Vector2(lerpf(tack.x, tack.x - 70.0, run), lee * lerpf(lead_y + 65.0, lead_y + 55.0, run))
	clew += Vector2(0.0, lee * motion * 6.0 * sin(t * TAU * 0.11 + 0.5))
	var swing := deg_to_rad(lerpf(30.0, 0.0, run) + motion * SPINNAKER_SWAY_DEG * sin(t * TAU * 0.09))
	var ahead := Vector2(cos(swing), lee * sin(swing))
	# Hoisting: grow out from the bow.
	kite_tack = tack.lerp(kite_tack, amount)
	clew = tack.lerp(clew, amount)
	var center := (kite_tack + clew) / 2.0
	var depth := spinnaker_depth * amount * (1.0 + motion * SPINNAKER_BREATH * sin(t * TAU * 0.12 + 1.3))
	var front_control := center + ahead * depth
	var back_control := center + ahead * depth * 0.55
	var front := _curve(kite_tack, clew, front_control, 24)
	return {
		"tack": kite_tack, "clew": clew, "head": _bezier(kite_tack, front_control, clew, 0.5), "front": front,
		"back_control": back_control, "center": center, "ahead": ahead, "depth": depth, "lee": lee,
	}


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var shape := get_shape()
	_draw_jib(shape.jib)
	_draw_main(shape.main)
	if spinnaker_amount > 0.01:
		_draw_spinnaker(shape.spinnaker)


func _draw_main(shape: Dictionary) -> void:
	var clew: Vector2 = shape.clew
	if set_amount > 0.01:
		# Sail: from the mast to the boom end, bellied to leeward.
		var leech: PackedVector2Array = shape.leech
		if main_texture:
			_draw_textured_sail(leech, _curve(mast, clew, shape.foot_control, leech.size() - 1), main_texture, set_amount)
		else:
			var outline := leech.duplicate()
			outline.append_array(_inner(_curve(clew, mast, shape.foot_control, 8)))
			_draw_cloth(outline, leech.size(), set_amount)
			draw_polyline(leech, Color(SAIL_EDGE, set_amount), 1.5, true)
			# Cross-cut panel seams, and the battens a little heavier.
			for k in 9:
				var t := (k + 1) / 10.0
				var on_boom := mast.lerp(clew, t)
				var on_leech := leech[roundi(t * (leech.size() - 1))]
				var batten := k in [2, 5, 7]
				draw_line(on_boom, on_leech, Color(sail_shade.darkened(0.1 if batten else 0.0), set_amount * (0.9 if batten else 0.35)),
					2.0 if batten else 0.8, true)
		# Main sheet to the traveller in the cockpit.
		draw_line(clew, traveller, Color(SHEET, set_amount * 0.8), 1.5, true)
	# Boom (and the sail cover on it when furled).
	if boom_texture:
		_draw_textured_spar(mast, clew, boom_texture)
	else:
		draw_line(mast, clew, BOOM.darkened(0.35), 7.0, true)
		draw_line(mast, clew, BOOM, 5.0, true)
		draw_line(mast + Vector2(0, -1.2), clew + Vector2(0, -1.2), BOOM.lightened(0.35), 1.2, true)
	if set_amount < 0.99:
		draw_line(mast + (clew - mast) * 0.03, clew - (clew - mast) * 0.04, Color(COVER, 1.0 - set_amount), 16.0, true)


func _draw_jib(shape: Dictionary) -> void:
	if set_amount <= 0.01 or spinnaker_amount >= 0.99:
		# Rolled up on the forestay (roller furling).
		draw_line(_furled_jib_start(), tack, Color(sail_shade, 0.9), 6.0, true)
		return
	var shown := set_amount * (1.0 - spinnaker_amount)
	var clew: Vector2 = shape.clew
	var leech: PackedVector2Array = shape.leech
	if jib_texture:
		_draw_textured_sail(leech, _curve(tack, clew, shape.foot_control, leech.size() - 1), jib_texture, shown)
	else:
		var outline: PackedVector2Array = leech.duplicate()
		outline.append_array(_inner(_curve(clew, tack, shape.foot_control, 6)))
		_draw_cloth(outline, leech.size(), shown)
		for k in 5:
			var t := (k + 1) / 6.0
			draw_line(tack.lerp(clew, t), leech[roundi(t * (leech.size() - 1))], Color(sail_shade, shown * 0.35), 0.8, true)
		draw_polyline(outline, Color(SAIL_EDGE, shown), 1.5, true)
	# Jib sheet to the leeward winch.
	var lee := signf(jib_angle_deg) if jib_angle_deg != 0.0 else 1.0
	draw_line(clew, Vector2(jib_sheet_lead.x, absf(jib_sheet_lead.y) * lee), Color(SHEET, shown * 0.8), 1.5, true)
	draw_line(_furled_jib_start(), tack, Color(sail_shade, 1.0 - shown), 6.0, true)


## Where the rolled-up jib starts along the forestay (just ahead of the mast).
func _furled_jib_start() -> Vector2:
	return mast + (tack - mast).normalized() * 40.0


func _draw_spinnaker(shape: Dictionary) -> void:
	var amount := spinnaker_amount
	var kite_tack: Vector2 = shape.tack
	var clew: Vector2 = shape.clew
	var lee: float = shape.lee
	var front: PackedVector2Array = shape.front
	var lead := Vector2(spinnaker_sheet_lead.x, absf(spinnaker_sheet_lead.y))
	# Rigging under the sail: pole (mast -> tack), halyard (mast -> head),
	# sheet (clew -> leeward quarter) and guy (tack -> windward quarter).
	draw_line(mast, kite_tack, Color(BOOM, amount), 5.0, true)
	draw_line(mast, shape.head, Color(SHEET, 0.7 * amount), 1.5, true)
	draw_line(clew, Vector2(lead.x, lee * lead.y), Color(SHEET, 0.8 * amount), 1.5, true)
	draw_line(kite_tack, Vector2(lead.x, -lee * lead.y), Color(SHEET, 0.6 * amount), 1.5, true)
	if spinnaker_texture:
		_draw_textured_sail(front, _curve(kite_tack, clew, shape.back_control, front.size() - 1), spinnaker_texture, amount)
	else:
		var outline := front.duplicate()
		outline.append_array(_inner(_curve(clew, kite_tack, shape.back_control, 16)))
		draw_colored_polygon(outline, Color(SPINNAKER, 0.95 * amount))
		for band in [0.3, 0.65]:
			var control: Vector2 = shape.center + shape.ahead * shape.depth * lerpf(0.55, 1.0, band)
			draw_polyline(_curve(kite_tack, clew, control, 20), Color(SPINNAKER_STRIPE, 0.85 * amount), 7.0, true)
		draw_polyline(front, Color(SAIL_EDGE, amount), 2.0, true)
	# Corner fittings: the sail visibly hangs from its tack, clew and head.
	for corner: Vector2 in [kite_tack, clew]:
		draw_circle(corner, 4.0, Color(BOOM, amount))


## A sail's cloth: its shadow on the deck first, then the sail shaded from
## the luff and foot (lit, sail_colour) to the curved leech (sail_shade), so
## its belly reads. `leech_count` points of `outline` are the leech.
func _draw_cloth(outline: PackedVector2Array, leech_count: int, alpha: float) -> void:
	# The offset is down-right on screen, whichever way the course view turns the deck.
	var offset := SHADOW_OFFSET.rotated(-get_global_transform().get_rotation())
	var shadow := PackedVector2Array()
	for p in outline:
		shadow.append(p + offset)
	draw_colored_polygon(shadow, Color(SAIL_SHADOW, SAIL_SHADOW.a * alpha))
	var colours := PackedColorArray()
	for i in outline.size():
		var on_leech := i < leech_count
		var t := float(i) / maxf(1.0, leech_count - 1) if on_leech else 0.0
		var c := sail_colour.lerp(sail_shade, 0.25 + 0.5 * sin(PI * t)) if on_leech else sail_colour.lightened(0.04)
		colours.append(Color(c, alpha))
	draw_polygon(outline, colours)


## Stretches `texture` over the band between two edges of a sail: `outer`
## (image top: leech / leading edge) and `inner` (image bottom: foot). Both
## run from the luff or tack (image left) to the clew (image right) and have
## the same number of points.
func _draw_textured_sail(outer: PackedVector2Array, inner: PackedVector2Array, texture: Texture2D, alpha: float) -> void:
	var count := mini(outer.size(), inner.size())
	if count < 2:
		return
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for i in count:
		var u := float(i) / (count - 1)
		points.append(outer[i])
		uvs.append(Vector2(u, 0.0))
		points.append(inner[i])
		uvs.append(Vector2(u, 1.0))
	colors.resize(points.size())
	colors.fill(Color(cloth_tint, alpha))
	var indices := PackedInt32Array()
	for i in count - 1:
		var a := i * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors, uvs,
		PackedInt32Array(), PackedFloat32Array(), texture.get_rid())


## A spar sprite (the boom): image left = mast end, right = outer end; its
## height is scaled with the length so it keeps its proportions.
func _draw_textured_spar(from: Vector2, to: Vector2, texture: Texture2D) -> void:
	var direction := (to - from).normalized()
	var side := Vector2(-direction.y, direction.x)
	var half_width := from.distance_to(to) * texture.get_height() / float(texture.get_width()) / 2.0
	var outer := PackedVector2Array([from - side * half_width, to - side * half_width])
	var inner := PackedVector2Array([from + side * half_width, to + side * half_width])
	_draw_textured_sail(outer, inner, texture, 1.0)


## A closing curve without its end points (they are already in the outline;
## repeated vertices make polygon triangulation fail).
static func _inner(points: PackedVector2Array) -> PackedVector2Array:
	return points.slice(1, points.size() - 1)


## Unit normal of `chord` pointing to the leeward side (`lee` = -1 port, +1 starboard).
static func _leeward_normal(chord: Vector2, lee: float) -> Vector2:
	var normal := Vector2(-chord.y, chord.x).normalized()
	return -normal if normal.y * lee < 0.0 else normal


## A gentle travelling ripple along a sail edge, zero at both ends.
static func _rippled(points: PackedVector2Array, normal: Vector2, amplitude: float, t: float, hz: float) -> PackedVector2Array:
	if amplitude <= 0.0:
		return points
	var out := points.duplicate()
	var last := out.size() - 1
	for i in range(1, last):
		var u := float(i) / last
		out[i] += normal * amplitude * sin(PI * u) * sin(TAU * (hz * t - u * 1.5))
	return out


static func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(control, t).lerp(control.lerp(b, t), t)


static func _curve(a: Vector2, b: Vector2, control: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps + 1:
		points.append(_bezier(a, control, b, float(i) / steps))
	return points
