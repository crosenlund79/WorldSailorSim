class_name AnchorLife
extends RefCounted
## Life at anchor (revision 0.102b): the quiet rules behind a safe evening at
## anchor. Pure functions; GameSession decides when the boat is settled and
## records which moments a stay has already had, the boat scenes present it.
##
## There is no day/night simulation in the game, so the time of day aboard is
## the local solar hour at the boat (game time is UTC; 15° of longitude make
## an hour). That is enough for "evening", "night" and "morning" moods.

const PHASE_MORNING := &"morning"
const PHASE_DAY := &"day"
const PHASE_EVENING := &"evening"
const PHASE_NIGHT := &"night"

## Settled: at anchor, holding well or fair, no alarm, and less wind than
## this (knots) where the boat lies.
const SETTLED_WIND_KN := 18.0
## The first quiet line comes this long after the anchor holds (game seconds).
const SETTLE_DELAY_S := 20.0 * 60.0
## A sleep at least this long counts for the wake-up moment (game seconds).
const WAKE_MIN_SLEEP_S := 3.0 * 3600.0

## How the boat scenes are tinted when settled at anchor (white: unchanged).
## Deliberately gentle: a warm evening, a soft blue night, a pale morning.
const TINTS := {
	PHASE_MORNING: Color(1.0, 0.94, 0.85),
	PHASE_DAY: Color(1.0, 1.0, 1.0),
	PHASE_EVENING: Color(0.97, 0.89, 0.79),
	PHASE_NIGHT: Color(0.66, 0.72, 0.86),
}
## The cabin lamp's warm glow (alpha 0 in daylight).
const LAMP := {
	PHASE_MORNING: 0.0,
	PHASE_DAY: 0.0,
	PHASE_EVENING: 0.22,
	PHASE_NIGHT: 0.32,
}

const SETTLED_LINES: Array[String] = [
	"The anchor holds. The sea is quiet.",
	"The boat settles to her anchor.",
	"For now, there is nowhere you need to be.",
]
const EVENING_LINES: Array[String] = [
	"A quiet evening aboard.",
	"The boat rocks gently at anchor. The light goes golden.",
	"Evening at anchor. The light goes soft over the water.",
]
const NIGHT_LINES: Array[String] = [
	"Night at anchor. Only the water talks against the hull.",
]
const WAKE_LINES: Array[String] = [
	"A new day aboard. The anchor held all night.",
	"You wake to the slap of small waves. Still right where you left her.",
	"Morning at anchor. The water is bright and still.",
]
const PET_LINES := {
	CompanionState.KIND_CAT: "The cat is curled up for the night and purrs at your touch.",
	CompanionState.KIND_DOG: "The dog thumps its tail once and goes back to dozing.",
}


## The local solar hour (0..24) at longitude `lon` for game time `time`.
static func local_hour(time: float, lon: float) -> float:
	return fposmod(time / 3600.0 + lon / 15.0, 24.0)


static func phase_at(hour: float) -> StringName:
	if hour >= 5.0 and hour < 9.0:
		return PHASE_MORNING
	if hour >= 9.0 and hour < 18.0:
		return PHASE_DAY
	if hour >= 18.0 and hour < 22.5:
		return PHASE_EVENING
	return PHASE_NIGHT


## The local day number (changes at local midnight): keys "once a day" moments.
static func local_day(time: float, lon: float) -> int:
	return floori((time / 3600.0 + lon / 15.0) / 24.0)


## A line from `lines`, chosen by `seed` (stable, so a reload shows the same).
static func pick(lines: Array[String], seed: int) -> String:
	return lines[posmod(seed, lines.size())] if not lines.is_empty() else ""
