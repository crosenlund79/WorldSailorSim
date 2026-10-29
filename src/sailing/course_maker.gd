class_name CourseMaker
extends RefCounted
## Which way to point the boat to make the best progress along a leg (I027,
## The Cost of the Wind): sailing straight when the leg can be sailed, and
## otherwise tacking (upwind) or gybing (downwind) on the best angle. Pure
## logic on the one sailing model (VesselProfile.sail_speed_kn); the
## simulation, the ETA and the instruments all ask it, so they agree.
##
## VMC - velocity made good on course - is the speed towards the leg's
## direction: boat speed × cos(the angle between the heading and the leg).
## The boat on a tack heads B + side × delta (side +1 = turned clockwise,
## to the right of the leg; -1 = to the left), and drifts sideways from the
## leg's line at boat speed × sin(delta) while it makes VMC along it.
##
## When the boat changes side (Simulation, at its evaluation points):
## - the offset from the line reaches the lane's edge (lane_nm: narrower as
##   the waypoint nears, so the zigzag closes on it);
## - land ahead on this side;
## - a wind shift: the other side makes SHIFT_GAIN times the progress, after
##   MIN_TACK_TIME_S on this one (the hysteresis against flip-flopping).
## Each tack or gybe costs VesselProfile.tack_loss_s of no progress.

## Heading search step and range either side of the leg (degrees).
const STEP_DEG := 2.0
const MAX_DELTA_DEG := 90.0
## Sail straight while the direct course makes at least this share of the
## best zigzag's VMC (a few percent is not worth the tacks: a beam reach is
## sailed straight although a broad reach is a little faster).
const DIRECT_SHARE := 0.92
## While beating, the engine stops (PropulsionController) once the sails on
## the tack make this much more than the engine-start threshold.
const BEAT_STOP_MARGIN_KN := 0.15
## A wind shift tacks the boat only when the other side is this much better...
const SHIFT_GAIN := 1.15
## ...and after this long on the current tack (game seconds).
const MIN_TACK_TIME_S := 1800.0
## Even at the lane's edge, at least this long between tacks (short-tacking
## near a waypoint, never a flurry); land ahead always tacks.
const MIN_LANE_TACK_S := 600.0
## The lane either side of the leg's line: this share of the leg still ahead,
## within these limits (nm).
const LANE_SHARE := 0.3
const LANE_MIN_NM := 0.2
const LANE_MAX_NM := 6.0
## Back to the line after a zigzag (or under engine): at most this angle off.
const RECOVER_DEG := 15.0
## Below this offset (nm) the boat counts as on its line.
const ON_LINE_NM := 0.02


## The best heading on one side of a leg: {"side", "delta", "heading",
## "speed", "vmc"} (delta 0 = the leg's own bearing).
static func on_side(profile: VesselProfile, leg_bearing: float, wind_from: float, wind_kn: float, side: int) -> Dictionary:
	var best := {"side": side, "delta": 0.0, "heading": fposmod(leg_bearing, 360.0), "speed": 0.0, "vmc": -INF}
	var delta := 0.0
	while delta <= MAX_DELTA_DEG + 1e-6:
		var heading := fposmod(leg_bearing + side * delta, 360.0)
		var speed := profile.sail_speed_kn(wind_kn, WindField.relative_angle(heading, wind_from))
		var vmc := speed * cos(deg_to_rad(delta))
		if vmc > float(best.vmc) + 1e-6:
			best = {"side": side, "delta": delta, "heading": heading, "speed": speed, "vmc": vmc}
		delta += STEP_DEG
	return best


## The choice for a leg: {"zigzag": bool, "direct": {...}, "starboard":
## on_side(+1), "port": on_side(-1), "best": the better of the two}. A zigzag
## when the direct course makes less than DIRECT_SHARE of the best VMC.
static func plan(profile: VesselProfile, leg_bearing: float, wind_from: float, wind_kn: float) -> Dictionary:
	var direct_speed := profile.sail_speed_kn(wind_kn, WindField.relative_angle(leg_bearing, wind_from))
	var direct := {"side": 0, "delta": 0.0, "heading": fposmod(leg_bearing, 360.0), "speed": direct_speed, "vmc": direct_speed}
	var right := on_side(profile, leg_bearing, wind_from, wind_kn, 1)
	var left := on_side(profile, leg_bearing, wind_from, wind_kn, -1)
	var best: Dictionary = right if float(right.vmc) >= float(left.vmc) else left
	var zigzag := float(best.vmc) > 0.0 and float(best.delta) > 0.0 and direct_speed < DIRECT_SHARE * float(best.vmc)
	return {"zigzag": zigzag, "direct": direct, "starboard": right, "port": left, "best": best}


## One side of a plan by its sign (+1 starboard of the line, -1 port).
static func side_of(course: Dictionary, side: int) -> Dictionary:
	return course.starboard if side > 0 else course.port


## Half-width of the lane either side of the line, for the leg still ahead.
static func lane_nm(remaining_leg_nm: float) -> float:
	return clampf(remaining_leg_nm * LANE_SHARE, LANE_MIN_NM, LANE_MAX_NM)


## Tacks or gybes expected over `progress_nm` along the line at `delta`
## degrees off it, in a lane for `remaining_leg_nm` (for the ETA).
static func expected_tacks(progress_nm: float, delta: float, remaining_leg_nm: float) -> float:
	if delta <= 0.0:
		return 0.0
	return progress_nm * tan(deg_to_rad(minf(delta, 85.0))) / (2.0 * lane_nm(remaining_leg_nm))


## The heading offset (degrees, signed) that steers back towards the line
## from `cross_track_nm` off it, or 0 when on it.
static func recovery_offset(cross_track_nm: float) -> float:
	return -signf(cross_track_nm) * RECOVER_DEG if absf(cross_track_nm) > ON_LINE_NM else 0.0


## True when a heading this far off the wind is a gybe-run rather than a beat.
static func is_downwind(heading: float, wind_from: float) -> bool:
	return absf(WindField.relative_angle(heading, wind_from)) > 90.0
