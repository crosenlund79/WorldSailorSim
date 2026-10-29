class_name PropulsionState
extends RefCounted
## What drives the boat right now, and the automatic controller's memory.
## Plain data owned by SessionState (saved with the game); updated only by
## PropulsionController through Simulation. Scenes read it to present sails,
## the engine sound and the HUD.

const MODE_SAIL := &"sail"
const MODE_ENGINE := &"engine"
const MODES: Array[StringName] = [MODE_SAIL, MODE_ENGINE]

const REASON_NONE := &""
const REASON_POOR := &"poor"        # averaged sailing performance too low
const REASON_STALL := &"stall"      # becalmed or head to wind
const REASON_START := &"start"      # conditions too poor when leaving
const REASON_CHOSEN := &"chosen"    # I027: the Captain motors to windward

var mode: StringName = MODE_SAIL
var engine_reason: StringName = REASON_NONE
## False until the first evaluation of a voyage (then the averaging starts).
var initialised := false
## Rolling (exponential, time-based) average of the potential sail-only speed.
var average_potential_kn := 0.0
## Potential sail-only speed at the last evaluation (also while motoring).
var potential_kn := 0.0
## Effective speed through the water until the next evaluation.
var speed_kn := 0.0
## Game seconds spent in the current mode / near stall / above the stop threshold.
var mode_seconds := 0.0
var stall_seconds := 0.0
var favorable_seconds := 0.0
## Game time of the last evaluation.
var last_evaluation_time := 0.0
## Conditions at the last evaluation (for presentation and the next heading check).
var heading_deg := 0.0
var wind_from_deg := 0.0
var wind_speed_kn := 0.0
## Signed true wind angle: + = wind from starboard, - = from port, 0 = head to wind.
var true_wind_angle := 0.0
var spinnaker := false


func is_motoring() -> bool:
	return mode == MODE_ENGINE


## True when sails are drawing (sailing); false when motoring.
func sails_set() -> bool:
	return mode == MODE_SAIL


## "Close hauled", "beam reach", … for an absolute true wind angle.
static func point_of_sail_name(angle: float) -> String:
	var a := absf(angle)
	if a < 40.0:
		return Loc.t("head to wind")
	if a < 60.0:
		return Loc.t("close hauled")
	if a < 80.0:
		return Loc.t("close reach")
	if a < 105.0:
		return Loc.t("beam reach")
	if a < 150.0:
		return Loc.t("broad reach")
	return "running"


## Which side the wind comes from: "starboard", "port" or "" (dead ahead/astern).
static func wind_side(angle: float) -> String:
	if absf(angle) < 1.0 or absf(angle) > 179.0:
		return ""
	return Loc.t("starboard") if angle > 0.0 else Loc.t("port")


## One-line description for the HUD: "Under sail · broad reach · 6.8 kn".
func describe() -> String:
	if is_motoring():
		var why := Loc.t("becalmed or head to wind") if engine_reason == REASON_STALL else Loc.t("insufficient sailing performance")
		if engine_reason == REASON_CHOSEN:
			why = Loc.t("motoring to windward, as you chose")
		return Loc.format("Motoring · %s · %.1f kn", [why, speed_kn])
	var text := Loc.format("Under sail · %s · %.1f kn", [point_of_sail_name(true_wind_angle), speed_kn])
	return text + Loc.t(" · spinnaker set") if spinnaker else text


func duplicate_state() -> PropulsionState:
	var copy := PropulsionState.new()
	copy.from_dict_unchecked(to_dict())
	return copy


func to_dict() -> Dictionary:
	return {
		"mode": String(mode), "engine_reason": String(engine_reason), "initialised": initialised,
		"average_potential_kn": average_potential_kn, "potential_kn": potential_kn, "speed_kn": speed_kn,
		"mode_seconds": mode_seconds, "stall_seconds": stall_seconds, "favorable_seconds": favorable_seconds,
		"last_evaluation_time": last_evaluation_time, "heading_deg": heading_deg,
		"wind_from_deg": wind_from_deg, "wind_speed_kn": wind_speed_kn,
		"true_wind_angle": true_wind_angle, "spinnaker": spinnaker,
	}


func from_dict_unchecked(data: Dictionary) -> void:
	mode = StringName(data.mode)
	engine_reason = StringName(data.engine_reason)
	initialised = data.initialised
	for key in ["average_potential_kn", "potential_kn", "speed_kn", "mode_seconds", "stall_seconds",
			"favorable_seconds", "last_evaluation_time", "heading_deg", "wind_from_deg", "wind_speed_kn", "true_wind_angle"]:
		set(key, float(data[key]))
	spinnaker = data.spinnaker


## Validates saved data. Returns null (with reasons in `errors`) when invalid.
static func from_dict(data: Variant, errors: Array[String]) -> PropulsionState:
	if not data is Dictionary:
		errors.append("propulsion data is not an object")
		return null
	if not data.get("mode") is String or StringName(data.mode) not in MODES or not data.get("engine_reason") is String \
			or not data.get("initialised") is bool or not data.get("spinnaker") is bool:
		errors.append("invalid propulsion mode")
		return null
	for key in ["average_potential_kn", "potential_kn", "speed_kn", "mode_seconds", "stall_seconds",
			"favorable_seconds", "last_evaluation_time", "heading_deg", "wind_from_deg", "wind_speed_kn", "true_wind_angle"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)):
			errors.append("invalid propulsion value: %s" % key)
			return null
	if float(data.speed_kn) < 0.0 or float(data.speed_kn) > 50.0 or float(data.mode_seconds) < 0.0:
		errors.append("propulsion values out of range")
		return null
	var state := PropulsionState.new()
	state.from_dict_unchecked(data)
	return state
