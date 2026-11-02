class_name TravelWriting
extends RefCounted
## Travel writing (I028 Tier 5): the Captain's pastime in place of the little
## game, read from data/pastimes/writing.json. A work (an essay, a journal, a
## travelogue, an adventure book, a novel) is about something that really
## happened - a harbour visited, a voyage, rough weather sailed through, a
## passenger whose dream came true, a companion aboard - and is written in
## two-hour sessions; each session the Captain chooses an angle, and the angle
## that suits the topic counts more. The finished work is published at once
## (GameSession): modest income, renown, an event in the world's history.
## Longer forms need real experience (voyages, harbours, a long passage,
## earlier works). No prose to compose: a few honest choices.

const DATA_PATH := "res://data/pastimes/writing.json"
const BEST := 1.5
const PLAIN := 1.0

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func forms() -> Array:
	return data().get("forms", [])


static func form(id: String) -> Dictionary:
	for f: Dictionary in forms():
		if f.id == id:
			return f
	return {}


static func angles() -> Array:
	return data().get("angles", [])


static func session_hours() -> float:
	return float(data().get("session_hours", 2))


## "" when the Captain has the experience for a form, else what is missing.
static func form_problem(f: Dictionary, log: CaptainsLog, works: int) -> String:
	var needs: Dictionary = f.get("needs", {})
	if log != null and int(needs.get("voyages", 0)) > log.voyages_completed:
		return Loc.t("needs %d voyages behind you") % int(needs.voyages)
	if log != null and int(needs.get("harbours", 0)) > log.get_visited_ids().size():
		return Loc.t("needs %d harbours visited") % int(needs.harbours)
	if log != null and float(needs.get("longest_nm", 0.0)) > log.get_longest_nm():
		return Loc.t("needs a passage of %d nm") % int(needs.longest_nm)
	if int(needs.get("works", 0)) > works:
		return Loc.t("needs %d published works first") % int(needs.works)
	return ""


## What can be written about now, from the game's own records:
## [{"id", "kind" (place/voyage/weather/passenger/pet), "label", "arg", "angle"}].
static func topics(log: CaptainsLog, book: PassageBook, companions: Array) -> Array:
	var found: Array = []
	var seen := {}
	var catalog := PortCatalog.get_default()
	if log:
		for i in range(log.voyages.size() - 1, -1, -1):
			var v: Dictionary = log.voyages[i]
			if v.get("outcome", "") != "arrived":
				continue
			var to := String(v.to)
			var name := catalog.get_display_name(StringName(to))
			if not seen.has("place:" + to):
				seen["place:" + to] = true
				found.append({"id": "place:" + to, "kind": "place", "label": Loc.t("The harbour of %s") % name, "arg": name, "angle": "places"})
			if float(v.nm) >= 60.0 and not seen.has("voyage:" + to):
				seen["voyage:" + to] = true
				found.append({"id": "voyage:%s:%d" % [to, int(float(v.departed))], "kind": "voyage", "label": Loc.t("The passage to %s (%.0f nm)") % [name, float(v.nm)],
					"arg": name, "angle": "sea"})
			if int(v.get("worst_hazard", 0)) >= 2 and not seen.has("weather:" + to):
				seen["weather:" + to] = true
				found.append({"id": "weather:%s:%d" % [to, int(float(v.departed))], "kind": "weather", "label": Loc.t("Rough weather on the way to %s") % name,
					"arg": name, "angle": "sea"})
	if book:
		for r: Dictionary in book.records:
			if (r.get("dream", {}) as Dictionary).get("met", false) or int(r.get("stars", 0)) == 5:
				found.append({"id": "passenger:" + String(r.id), "kind": "passenger", "label": Loc.t("Sailing with %s") % r.name, "arg": String(r.name), "angle": "people"})
	for companion: Variant in companions:
		var cname := String(companion.name) if companion is CompanionState else String(companion)
		if cname != "":
			found.append({"id": "pet:" + cname, "kind": "pet", "label": Loc.t("Life aboard with %s") % cname, "arg": cname, "angle": "people"})
	return found.slice(0, 14)


## A title for a work, from its topic (deterministic).
static func title_for(topic: Dictionary, salt: int) -> String:
	var options: Array = (data().get("titles", {}) as Dictionary).get(String(topic.get("kind", "place")), ["%s"])
	var pattern := Loc.t(String(options[absi(salt) % options.size()]))
	return pattern % String(topic.get("arg", "")) if "%s" in pattern else pattern


## The weight of a session: the angle that suits the topic counts more.
static func session_quality(topic: Dictionary, angle: String) -> float:
	return BEST if angle == String(topic.get("angle", "")) else PLAIN


## How a finished work is received: {"stars" 3-5, "euros", "renown"}.
static func reception(f: Dictionary, quality_sum: float, sessions: int) -> Dictionary:
	var q := clampf(quality_sum / maxf(sessions, 1) , PLAIN, BEST)
	var share := (q - PLAIN) / (BEST - PLAIN)  # 0 plain .. 1 every angle right
	return {"stars": 3 + roundi(share * 2.0), "euros": int(snappedf(float(f.euros) * (0.8 + 0.4 * share), 5.0)),
		"renown": roundi(float(f.renown) * (0.8 + 0.4 * share))}
