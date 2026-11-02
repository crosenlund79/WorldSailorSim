class_name WritingMenu
extends SimplePanel
## Travel writing (I028 Tier 5) on the laptop, in place of the little game:
## the work in progress and its next session (choose an angle, then write for
## two hours - App spends the time, an interruption counts its share), or a
## new work (a form you are ready for, about something you really lived),
## and the works published so far. The rules are TravelWriting's; the state
## is GameSession's.

signal write_requested(angle: String)

var _form: OptionButton
var _topic: OptionButton
var _topics: Array = []


func _ready() -> void:
	_build("Travel writing", 900)
	var writing := GameSession.get_writing()
	var project: Dictionary = writing.get("project", {})
	if not project.is_empty():
		var f := TravelWriting.form(String(project.form))
		_label("Project", Loc.t("Writing: %s about %s · session %d of %d") % [Loc.t(String(f.title)), String(project.topic.label).to_lower(),
			int(project.sessions) + 1, int(f.sessions)], &"HeaderLabel")
		_label("AngleNote", "Each session takes two hours. The angle that suits your subject counts more.", &"MutedLabel")
		for angle: Dictionary in TravelWriting.angles():
			_button("Angle_%s" % angle.id, String(angle.text), func() -> void:
				write_requested.emit(String(angle.id))
				close())
	else:
		_label("NewWork", "Begin a new work", &"HeaderLabel")
		_form = OptionButton.new()
		_form.name = "Form"
		var works := (writing.get("works", []) as Array).filter(func(w: Dictionary) -> bool: return not w.get("legacy", false)).size()
		for f: Dictionary in TravelWriting.forms():
			var problem := TravelWriting.form_problem(f, GameSession.get_captains_log(), works)
			_form.add_item("%s · %s%s" % [Loc.t(String(f.title)), Loc.n("%d session", "%d sessions", int(f.sessions)) % int(f.sessions),
				(" (" + problem + ")") if problem != "" else ""])
		_box.add_child(_form)
		_topics = GameSession.writing_topics()
		_topic = OptionButton.new()
		_topic.name = "Topic"
		for t: Dictionary in _topics:
			_topic.add_item(String(t.label))
		_box.add_child(_topic)
		if _topics.is_empty():
			_label("NoTopics", "Sail somewhere first: your writing comes from your own voyages.", &"MutedLabel")
		_button("BeginButton", "Begin writing", func() -> void:
			if _topics.is_empty():
				return
			var error := GameSession.start_writing(String(TravelWriting.forms()[_form.selected].id), String(_topics[_topic.selected].id))
			if error != "":
				notification_requested.emit(error)
				return
			notification_requested.emit(Loc.t("A new work begun. Choose an angle for the first session."))
			close())
	var published := (writing.get("works", []) as Array).duplicate()
	if not published.is_empty():
		_label("Works", "Published", &"HeaderLabel")
		published.reverse()
		for work: Dictionary in published.slice(0, 8):
			var kind := Loc.t("Your little game") if work.form == "game" else Loc.t(String(TravelWriting.form(String(work.form)).get("title", "")))
			_label("Work_%s" % work.id, "“%s” · %s · %s · %s" % [work.title, kind, "★".repeat(int(work.stars)),
				Simulation.format_game_time(float(work.published_at), false)], &"MutedLabel")
	_button("CloseButton", "Close", close)
