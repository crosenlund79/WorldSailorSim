class_name Difficulty
extends RefCounted
## Relaxed, Standard or Seasoned Captain (I022). The same sea, weather and
## rules for everyone: a level only scales a few existing numbers, read from
## data/progression/difficulty.json (Standard is 1.0 everywhere, the game as
## designed):
##   starting_funds   money at the start of a new game
##   provisions_use   food and water eaten and drunk per day
##   wear             rig wear under sail and engine hours
##   weather_damage   hull damage from heavy weather
##   costs            provisions and boat care (repairs, services, haul-outs)
##   rescue_fee       the fee when the crew is rescued
## The level belongs to the saved game (SessionState.difficulty; old saves are
## Standard). It may be changed at any time from the pause menu; a change
## counts from then on and never touches money already spent or earned.

const RELAXED := &"relaxed"
const STANDARD := &"standard"
const SEASONED := &"seasoned"
const LEVELS: Array[StringName] = [RELAXED, STANDARD, SEASONED]
const DATA_PATH := "res://data/progression/difficulty.json"

static var _levels := {}


static func _data() -> Dictionary:
	if _levels.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_levels = (parsed as Dictionary).get("levels", {}) if parsed is Dictionary else {}
	return _levels


## `level` if it is a known level, otherwise Standard.
static func valid(level: Variant) -> StringName:
	return StringName(level) if (level is String or level is StringName) and StringName(level) in LEVELS else STANDARD


## A number of a level (`key` as above); 1.0 (or 0) when unknown.
static func value_of(level: StringName, key: String) -> float:
	var entry: Dictionary = _data().get(String(valid(level)), {})
	return float(entry.get(key, 1.0))


## The factor `key` for the game being played now.
static func factor(key: String) -> float:
	return value_of(GameSession.get_difficulty(), key)


## The level's name ("Relaxed") in the current language.
static func display_name(level: StringName) -> String:
	return Loc.t(String((_data().get(String(valid(level)), {}) as Dictionary).get("name", "Standard")))


## What the level changes, in the current language.
static func describe(level: StringName) -> String:
	return Loc.t(String((_data().get(String(valid(level)), {}) as Dictionary).get("text", "")))


## Money to start a new game with.
static func starting_funds(level: StringName) -> int:
	var entry: Dictionary = _data().get(String(valid(level)), {})
	return int(entry.get("starting_funds", SessionState.STARTING_FUNDS))
