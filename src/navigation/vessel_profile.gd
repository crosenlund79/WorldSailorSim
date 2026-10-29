class_name VesselProfile
extends Resource
## Performance characteristics of one boat. Everything that makes a boat
## faster or slower lives here, so future boats (catamarans, faster cruisers)
## are new profile resources, not code changes.
##
## Sailing speed is a simple "polar" model:
##   speed = max_sail_speed × wind_factor(true wind speed)
##           × angle_efficiency(true wind angle) × spinnaker_bonus (if set)
## capped at max_sail_speed_kn. The engine gives a fixed engine_speed_kn.
## The propulsion controller thresholds (when to motor) are per boat too.
## The numbers are gameplay tuning, not measured data of a real boat.

const DEFAULT_PATH := "res://data/vessel/starter_sloop.tres"

static var _default: VesselProfile

@export var display_name := ""
@export var length_ft := 33.0

@export_group("Sailing")
## Upper limit of sailing speed (excellent conditions), knots.
@export_range(1.0, 30.0, 0.1) var max_sail_speed_kn := 10.0
## Wind speed scale of the saturation curve: wind_factor = 1 - exp(-tws / scale).
## Smaller means the boat reaches its potential in lighter winds.
@export_range(1.0, 40.0, 0.1) var wind_speed_scale_kn := 9.0
## Below light_air_min_kn true wind the sails give nothing; full effect from light_air_full_kn.
@export_range(0.0, 10.0, 0.1) var light_air_min_kn := 0.8
@export_range(0.0, 10.0, 0.1) var light_air_full_kn := 3.0
## Efficiency (0..1) by true wind angle in degrees, 0 = head to wind, 180 = dead
## downwind. Points are (angle, efficiency), linearly interpolated.
## I027: the close-hauled band (35-65°) raised to what a cruising sloop does
## to windward (about two thirds of its reaching speed at 45°), so beating is
## a real way upwind (CourseMaker) instead of always the engine.
@export var angle_efficiency_curve := PackedVector2Array([
	Vector2(0, 0.0), Vector2(35, 0.0), Vector2(40, 0.45), Vector2(45, 0.62), Vector2(55, 0.74), Vector2(65, 0.80),
	Vector2(80, 0.85), Vector2(95, 0.95), Vector2(110, 1.0), Vector2(125, 0.97), Vector2(140, 0.90),
	Vector2(155, 0.80), Vector2(170, 0.70), Vector2(180, 0.66),
])

## A tack or gybe costs this much time without progress (game seconds):
## the boat slows through the wind and builds speed again (I027).
@export_range(0.0, 600.0, 1.0) var tack_loss_s := 90.0

@export_group("Spinnaker")
@export var has_spinnaker := true
## The spinnaker is set when the true wind angle is at least this (180 - 65°).
@export_range(90.0, 180.0, 0.5) var spinnaker_min_angle := 115.0
## Downwind efficiency multiplier while the spinnaker is set (still capped).
@export_range(1.0, 1.5, 0.01) var spinnaker_bonus := 1.12

@export_group("Engine")
@export_range(0.5, 20.0, 0.1) var engine_speed_kn := 5.0

@export_group("Automatic propulsion")
## Start the engine when the averaged potential sailing speed drops below this.
@export_range(0.0, 20.0, 0.1) var engine_start_below_kn := 3.5
## Return to sail when the averaged potential stays above this...
@export_range(0.0, 20.0, 0.1) var engine_stop_above_kn := 6.0
## ...for at least this long (game seconds).
@export var engine_stop_confirm_s := 1200.0
## Averaging time constant of the potential sailing speed (game seconds).
@export var averaging_time_s := 3600.0
## Near-stall: below this potential speed the engine starts after stall_delay_s.
@export_range(0.0, 5.0, 0.05) var stall_below_kn := 0.5
@export var stall_delay_s := 600.0
## Minimum time in a mode before switching (except for a near-stall start).
@export var min_sail_time_s := 900.0
@export var min_engine_time_s := 1800.0
## A course change larger than this restarts the averaging from the new heading.
@export_range(0.0, 180.0, 1.0) var heading_reset_deg := 30.0

@export_group("Seaworthiness")
## Weather damage multiplier (1.0 = the reference boat). Below 1 the boat takes
## heavy weather better, above 1 worse. See WeatherDamage.
@export_range(0.25, 3.0, 0.05) var weather_damage_factor := 1.0


static func get_default() -> VesselProfile:
	if _default == null:
		_default = load(DEFAULT_PATH) as VesselProfile
	return _default


static func clear_default() -> void:
	_default = null


## Sailing efficiency (0..1) for an absolute true wind angle (0..180°).
func angle_efficiency(true_wind_angle: float) -> float:
	var angle := clampf(absf(true_wind_angle), 0.0, 180.0)
	var curve := angle_efficiency_curve
	for i in range(1, curve.size()):
		if angle <= curve[i].x:
			var span := curve[i].x - curve[i - 1].x
			var f := (angle - curve[i - 1].x) / span if span > 0.0 else 1.0
			return lerpf(curve[i - 1].y, curve[i].y, f)
	return curve[curve.size() - 1].y if not curve.is_empty() else 0.0


## True if the spinnaker would be set at this true wind angle (when sailing).
func wants_spinnaker(true_wind_angle: float) -> bool:
	return has_spinnaker and absf(true_wind_angle) >= spinnaker_min_angle


## Potential sail-only speed in knots for a true wind speed and angle,
## including the spinnaker where it would be set.
func sail_speed_kn(true_wind_speed_kn: float, true_wind_angle: float) -> float:
	var wind_factor := 1.0 - exp(-maxf(true_wind_speed_kn, 0.0) / wind_speed_scale_kn)
	wind_factor *= smoothstep(light_air_min_kn, light_air_full_kn, true_wind_speed_kn)
	var speed := max_sail_speed_kn * wind_factor * angle_efficiency(true_wind_angle)
	if wants_spinnaker(true_wind_angle):
		speed *= spinnaker_bonus
	return clampf(speed, 0.0, max_sail_speed_kn)
