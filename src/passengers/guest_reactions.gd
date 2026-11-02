class_name GuestReactions
extends RefCounted
## How passengers respond to what actually happens aboard (I028 Tier 2): the
## weather they sail in, the Captain's cautious choices, scenic harbours,
## the animals aboard, the accommodation and the timing - each through the
## traveller's own traits, so an anxious passenger and a hardy one feel the
## same gale differently. A reaction moves the booking's satisfaction a
## little (0-100, starting at START) and is written in its events (the facts
## the review and the ledger come from); now and then it brings a line of
## dialogue (data/passengers/lines.json). No meters, no chores.

const LINES_PATH := "res://data/passengers/lines.json"
const START := 70.0
## A reaction of one kind is felt at most once in this long (game seconds).
const KIND_COOLDOWN_S := 6.0 * 3600.0

static var _lines: Dictionary


static func lines() -> Dictionary:
	if _lines.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		_lines = parsed.get("events", {}) if parsed is Dictionary else {}
	return _lines


## A line for an event, chosen by the traveller and the moment (translated).
static func line(kind: String, traveller: Dictionary, salt: int) -> String:
	var options: Array = lines().get(kind, [])
	if options.is_empty():
		return ""
	return Loc.t(String((options[absi(hash("%s|%s|%d" % [traveller.get("id", ""), kind, salt])) % options.size()] as Dictionary).text))


## Records a reaction on a booking: its satisfaction moves by `delta` (once per
## kind in KIND_COOLDOWN_S unless `always`). Returns true if it counted.
static func note(booking: Dictionary, kind: String, delta: float, now: float, always := false) -> bool:
	var events: Array = booking.get("events", [])
	if not always:
		for e: Dictionary in events:
			if e.kind == kind and now - float(e.t) < KIND_COOLDOWN_S:
				return false
	events.append({"t": now, "kind": kind, "d": snappedf(delta, 0.1)})
	booking["events"] = events
	booking["satisfaction"] = clampf(float(booking.get("satisfaction", START)) + delta, 0.0, 100.0)
	return true


## Boarding: the boat against what they hoped for. Returns [kind, delta] pairs noted.
static func on_board(booking: Dictionary, traveller: Dictionary, vessel_id: StringName, now: float) -> Array:
	var noted: Array = []
	var want := Accommodation.COMFORT_ORDER.find(StringName(traveller.get("comfort", "comfortable")))
	var have := Accommodation.COMFORT_ORDER.find(Accommodation.comfort_tier(vessel_id))
	if have < want:
		note(booking, "comfort_unhappy", -6.0 * (want - have), now, true)
		noted.append("comfort_unhappy")
	elif have > want:
		note(booking, "comfort_pleased", 4.0, now, true)
	if traveller.get("privacy", "") == "prefers" and not booking.get("private", false):
		note(booking, "privacy_unhappy", -5.0, now, true)
		noted.append("privacy_unhappy")
	return noted


## The weather at the boat (Simulation's hazard level, 0 calm to 3+ severe).
## Returns the dialogue kind to say, or "".
static func on_weather(booking: Dictionary, traveller: Dictionary, hazard: int, now: float) -> String:
	booking["max_hazard"] = maxi(int(booking.get("max_hazard", 0)), hazard)
	match String(traveller.get("weather", "steady")):
		"anxious":
			if hazard >= 1 and note(booking, "rough", -4.0 * hazard, now):
				return "rough_anxious"
		"hardy":
			if hazard >= 1 and hazard <= 2 and note(booking, "lively", 3.0, now):
				return "rough_hardy"
		_:
			if hazard >= 2 and note(booking, "rough", -3.0 * (hazard - 1), now):
				return "rough_anxious"
	if hazard == 0 and traveller.get("motivation", "") in ["rest", "together", "see"] and note(booking, "calm", 2.0, now):
		return "calm_relaxed"
	return ""


## The Captain chose caution in bad weather (anchored, held or turned for
## shelter): the nervous are grateful, nobody is punished for good seamanship.
static func on_caution(booking: Dictionary, traveller: Dictionary, now: float) -> String:
	booking["excused"] = true
	var gain := 8.0 if traveller.get("weather", "") == "anxious" else 3.0
	if note(booking, "caution", gain, now):
		return "cautious_thanks"
	return ""


## Arriving at a scenic harbour or anchorage (its scenic tags, or a special harbour).
static func on_scenic(booking: Dictionary, traveller: Dictionary, now: float) -> String:
	if traveller.get("motivation", "") == "photo" or traveller.get("background", "") == "photographer":
		if note(booking, "scenic", 7.0, now):
			return "scenic_photo"
	elif note(booking, "scenic", 3.0, now):
		return "scenic_plain"
	return ""


## A day at sea with animals aboard.
static func on_pets(booking: Dictionary, traveller: Dictionary, now: float) -> String:
	if traveller.get("pets", "") == "likes" and note(booking, "pets", 4.0, now):
		return "pet_lover"
	return ""


## Arrival against the promise: hours late (0 or less: on time).
static func on_arrival_time(booking: Dictionary, traveller: Dictionary, hours_late: float, now: float) -> String:
	booking["late_h"] = maxf(hours_late, 0.0)
	if hours_late <= 0.0:
		note(booking, "on_time", 4.0 if traveller.get("timing", "") == "strict" else 2.0, now, true)
		return ""
	var excused: bool = booking.get("excused", false)
	var per_6h: float = {"strict": 6.0, "normal": 3.0, "relaxed": 0.8}.get(traveller.get("timing", "normal"), 3.0)
	var loss: float = minf(per_6h * ceilf(hours_late / 6.0), 35.0) * (0.35 if excused else 1.0)
	note(booking, "late", -loss, now, true)
	return "delay_relaxed" if traveller.get("timing", "") == "relaxed" else "delay_strict"
