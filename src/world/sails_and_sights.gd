class_name SailsAndSights
extends RefCounted
## Sails & Sights (I028 Tier 6): the sailing world's monthly magazine. An
## issue is composed once, when its month is over, from that month's events in
## the world's ledger (the expeditions, the longest passages, the new books,
## the Captain's own published works and notable voyages) and the rankings as
## they stood at the month's end. It is then frozen in WorldState.issues and
## never recomposed, so the archive keeps what the magazine said at the time,
## even after later events. One issue per calendar month, by its "YYYY-MM" id:
## never twice after a save and load.

const MAX_STORIES := 5
const TOP := 10
## At most this many months are composed at once (a long absence: only the latest).
const MAX_CATCH_UP := 3


static func month_id(time: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(time))
	return "%04d-%02d" % [d.year, d.month]


## The first second of the month `time` is in.
static func month_start(time: float) -> float:
	var d := Time.get_datetime_dict_from_unix_time(int(time))
	return float(Time.get_unix_time_from_datetime_dict({"year": d.year, "month": d.month, "day": 1, "hour": 0, "minute": 0, "second": 0}))


static func next_month_start(time: float) -> float:
	return month_start(month_start(time) + 32.0 * 86400.0)


## The months that ended since the world began and have no issue yet (oldest
## first, at most MAX_CATCH_UP, the latest ones).
static func due_months(world: WorldState, now: float) -> Array:
	var due: Array = []
	if world.started_at <= 0.0:
		return due
	var have := {}
	for issue: Dictionary in world.issues:
		have[String(issue.id)] = true
	var start := month_start(world.started_at)
	while next_month_start(start) <= now:
		if not have.has(month_id(start)):
			due.append(start)
		start = next_month_start(start)
	return due.slice(maxi(due.size() - MAX_CATCH_UP, 0))


## Composes the issue for the month beginning at `start` (deterministic: the
## same ledger gives the same issue).
static func compose(world: WorldState, start: float, captain_lasting: int) -> Dictionary:
	var end := next_month_start(start)
	var d := Time.get_datetime_dict_from_unix_time(int(start))
	var month: Array = world.events.filter(func(e: Dictionary) -> bool: return float(e.t) >= start and float(e.t) < end and not e.get("minor", false))
	var stories: Array = []
	var weight := func(e: Dictionary) -> int:
		match String(e.kind):
			"expedition_complete": return 100
			"expedition_announced": return 80
			"captain_book": return 70
			"book": return 60
			"captain_passage": return 50 + int(e.get("nm", 0)) / 50
			"captain_dream": return 45
			"meeting": return 40
			"arrive": return int(e.get("nm", 0)) / 20
		return 0
	month.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa: int = weight.call(a)
		var wb: int = weight.call(b)
		return wa > wb if wa != wb else int(a.seq) < int(b.seq))
	var seen_people := {}
	for e: Dictionary in month:
		if stories.size() >= MAX_STORIES or int(weight.call(e)) <= 5:
			break
		var who := String((e.get("who", [""]) as Array)[0])
		if seen_people.has(who) and String(e.kind) == "arrive":
			continue
		if String(e.kind) == "book" and seen_people.has("#book"):
			continue  # one new book a month is news; more would read the same
		seen_people[who] = true
		if String(e.kind) == "book":
			seen_people["#book"] = true
		var story := _story(e)
		if not story.is_empty():
			stories.append(story)
	var ranks := WorldChronicle.rankings(world, end - 1.0, captain_lasting)
	var top: Array = []
	for row: Dictionary in ranks.slice(0, TOP):
		top.append({"id": row.id, "name": row.name, "role": row.role, "renown": row.renown, "rank": row.rank})
	var captain_rank := 0
	for row: Dictionary in ranks:
		if row.id == WorldChronicle.CAPTAIN:
			captain_rank = int(row.rank)
	var cover := "net_%02d" % (1 + posmod(hash(month_id(start)), 24))
	if not stories.is_empty() and String(stories[0].image) != "":
		cover = String(stories[0].image)
	return {"id": month_id(start), "year": d.year, "month": d.month, "number": world.issues.size() + 1, "published_at": end,
		"cover": cover, "stories": stories, "top": top, "captain_rank": captain_rank, "of": ranks.size()}


## A story from an event: {"kind", "headline", "text", "image", "who", "seq"}.
static func _story(e: Dictionary) -> Dictionary:
	var post := TravellerNetwork.post_for(e)
	var who: Array = e.get("who", [])
	var names := PackedStringArray()
	for id: Variant in who:
		names.append(String(WorldChronicle.traveller(String(id)).get("name", String(id))))
	var people := " & ".join(names)
	var vessel := String(WorldChronicle.yacht(String(e.get("yacht", ""))).get("name", ""))
	var place := TravellerNetwork._place(String(e.get("port", "")))
	var headline := ""
	var text := ""
	match String(e.kind):
		"expedition_complete":
			headline = Loc.t("%s reaches %s") % [vessel, place]
			text = Loc.t("%s completed %s, arriving in %s after the last %d nm.") % [people, TravellerNetwork._expedition_title(String(e.get("expedition", ""))),
				place, int(e.get("nm", 0))]
		"expedition_announced":
			headline = Loc.t("New expedition: %s") % TravellerNetwork._expedition_title(String(e.get("expedition", "")))
			text = Loc.t("%s will sail %s from %s to %s.") % [people, vessel, place, TravellerNetwork._place(String(e.get("to", "")))]
		"book":
			headline = Loc.t("New on the shelf from %s") % people
			match String(e.get("role", "")):
				"photographer":
					text = Loc.t("A new book of photographs from a season at sea, quiet harbours and wide skies.")
				"cook":
					text = Loc.t("A cookbook from a small galley: recipes for calm evenings and rough nights.")
				"writer":
					text = Loc.t("New stories from the sea, written in harbours and on night watches.")
				_:
					text = Loc.t("A new book from one of the sailing world's familiar names, written between harbours.")
		"captain_book":
			headline = Loc.t("“%s”") % String(e.get("title", ""))
			text = Loc.t("%s publishes a new work, received with %d stars.") % [people, int(e.get("stars", 3))]
		"captain_passage":
			headline = Loc.t("%d nm to %s") % [int(e.get("nm", 0)), place]
			text = Loc.t("%s brought their yacht safely into %s after a passage of %d nm.") % [people, place, int(e.get("nm", 0))]
		"captain_dream":
			headline = Loc.t("A dream fulfilled at sea")
			text = Loc.t("Aboard with %s, a passenger saw a lifelong dream come true.") % people
		"meeting":
			headline = Loc.t("Met in %s") % place
			text = Loc.t("%s shared a table on the quay in %s.") % [people, place]
		"arrive":
			headline = Loc.t("%s in %s") % [vessel, place]
			text = Loc.t("%s arrived in %s after %d nm.") % [people, place, int(e.get("nm", 0))]
		_:
			return {}
	return {"kind": String(e.kind), "headline": headline, "text": text, "image": String(post.get("image", "")), "who": who.duplicate(), "seq": int(e.get("seq", 0))}
