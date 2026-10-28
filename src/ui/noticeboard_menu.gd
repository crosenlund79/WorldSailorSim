class_name NoticeboardMenu
extends SimplePanel
## The quay's noticeboard (I026 stage 02), read up close: the forecast in
## words, a few small pinned notes, the harbour's own words and who keeps
## which hours (HarbourNotes). Information only: no quests, and the weather
## and traffic warnings still come as always.


func _ready() -> void:
	var place := GameSession.get_location()
	var port_id := GameSession.get_location_id()
	var now := GameSession.get_game_time()
	_build(Loc.t("Noticeboard") + (" · %s" % place.display_name if place else ""), 720.0)
	_label("ForecastHeading", Loc.t("Forecast, pinned up this morning"), &"HeaderLabel")
	_label("ForecastText", "\n".join(HarbourNotes.forecast_lines(port_id, now)))
	_label("NoticesHeading", Loc.t("Notices"), &"HeaderLabel")
	_label("NoticesText", "\n".join(HarbourNotes.notices(port_id, now).map(func(n: String) -> String: return "·  " + n)))
	var notes := HarbourNotes.local_notes(port_id)
	if not notes.is_empty():
		_label("AboutText", "\n".join(notes), &"MutedLabel")
	_label("Hint", Loc.t("Opening hours are on each door and at the harbour office."), &"MutedLabel")
	_button("CloseButton", "Close", close)


func focus_default() -> void:
	(_buttons.get_node(^"CloseButton") as Button).grab_focus()
