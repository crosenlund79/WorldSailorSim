class_name PastimesState
extends RefCounted
## The captain's pastimes aboard (I022, The Captain's Other Life), as saved:
##
##   postcards   the scrapbook, newest last: [{"kind", "subject", "caption",
##               "layout", "time", "place"}] (at most Pastimes scrapbook_size)
##   draft       a postcard being made, or {}: {"kind", "subject", "caption",
##               "layout", "minutes"} (minutes already spent on it; kept when
##               an event interrupts the work, so it can be finished later)
##   game        the little game: {"points": float (towards the current
##               milestone), "milestone": int (index of the one being made),
##               "sessions": int, "task": {"id", "choice", "minutes"} or {}
##               (a session interrupted part-way), "log": [{"milestone",
##               "time"}]}
##
## Optional in saves: an older save has an empty scrapbook and no game yet.
## Malformed parts are dropped quietly (never a refused save).

var postcards: Array[Dictionary] = []
var draft := {}
var game := {"points": 0.0, "milestone": 0, "sessions": 0, "task": {}, "log": []}


func duplicate_state() -> PastimesState:
	var copy := PastimesState.new()
	for card in postcards:
		copy.postcards.append(card.duplicate(true))
	copy.draft = draft.duplicate(true)
	copy.game = game.duplicate(true)
	return copy


func to_dict() -> Dictionary:
	return {"postcards": postcards.duplicate(true), "draft": draft.duplicate(true), "game": game.duplicate(true)}


## Never fails: unknown or malformed parts are left out.
static func from_dict(data: Variant) -> PastimesState:
	var state := PastimesState.new()
	if not data is Dictionary:
		return state
	var cards: Variant = data.get("postcards", [])
	if cards is Array:
		for card: Variant in cards:
			if card is Dictionary and card.get("kind") is String and card.get("subject") is String and _is_number(card.get("caption")) \
					and card.get("layout") is String and _is_number(card.get("time")):
				state.postcards.append({"kind": card.kind, "subject": card.subject, "caption": int(card.caption), "layout": card.layout,
					"time": float(card.time), "place": String(card.get("place", ""))})
	var saved_draft: Variant = data.get("draft", {})
	if saved_draft is Dictionary and saved_draft.get("kind") is String and saved_draft.get("subject") is String \
			and _is_number(saved_draft.get("caption")) and saved_draft.get("layout") is String and _is_number(saved_draft.get("minutes")):
		state.draft = {"kind": saved_draft.kind, "subject": saved_draft.subject, "caption": int(saved_draft.caption),
			"layout": saved_draft.layout, "minutes": maxf(float(saved_draft.minutes), 0.0)}
	var saved_game: Variant = data.get("game", {})
	if saved_game is Dictionary:
		state.game.points = maxf(float(saved_game.get("points", 0.0)), 0.0) if _is_number(saved_game.get("points", 0.0)) else 0.0
		state.game.milestone = maxi(int(saved_game.get("milestone", 0)), 0) if _is_number(saved_game.get("milestone", 0)) else 0
		state.game.sessions = maxi(int(saved_game.get("sessions", 0)), 0) if _is_number(saved_game.get("sessions", 0)) else 0
		var task: Variant = saved_game.get("task", {})
		if task is Dictionary and task.get("id") is String and _is_number(task.get("choice")) and _is_number(task.get("minutes")):
			state.game.task = {"id": task.id, "choice": int(task.choice), "minutes": maxf(float(task.minutes), 0.0)}
		var entries: Variant = saved_game.get("log", [])
		if entries is Array:
			for entry: Variant in entries:
				if entry is Dictionary and _is_number(entry.get("milestone")) and _is_number(entry.get("time")):
					state.game.log.append({"milestone": int(entry.milestone), "time": float(entry.time)})
	return state


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
