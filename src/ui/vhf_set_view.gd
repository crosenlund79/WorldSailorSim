class_name VhfSetView
extends SimplePanel
## The VHF set at the nav station, brought close (I026, A World You Can
## Touch; framed as the radio by FocusFrame). What the radio really has:
##   - channel 16, standing by;
##   - a call that came in and was not answered yet (VhfRadio, I019): answer
##     it here (the same VhfDialog as when it pops up);
##   - the weather broadcast: the wind at the boat now and, under way with a
##     course, the hazards the forecast already sees ahead on it
##     (Simulation.route_hazards) - the same information as the warnings,
##     which stay in the HUD and never depend on opening the radio.
## Nothing here is new simulation and nothing is saved.

signal answer_requested(call: Dictionary)

## The call waiting (App.get_pending_vhf()), or {}.
var pending := {}


func _init(waiting: Dictionary = {}) -> void:
	pending = waiting


func _ready() -> void:
	_build(Loc.t("VHF radio · channel 16"), 640.0)
	_label("Status", Loc.t("Standing by on channel 16."), &"MutedLabel")
	if not pending.is_empty() and GameSession.can_answer_vhf(pending):
		_label("Call", Loc.t("A call is waiting:") + " " + VhfRadio.describe(pending))
		_button("AnswerButton", Loc.t("Answer the call"), func() -> void:
			var call := pending
			close()
			answer_requested.emit(call))
	_label("BroadcastTitle", Loc.t("Weather broadcast"), &"HeaderLabel")
	for line in broadcast_lines():
		_label("Broadcast", line)
	_button("CloseButton", Loc.t("Close"), close)


## The broadcast, in words, from the weather the game already knows.
static func broadcast_lines() -> Array[String]:
	var out: Array[String] = []
	var here := Simulation.get_weather_at_vessel()
	out.append(Loc.t("At the boat now: wind %s %d kn, gusts %d kn; %s.") % [WindField.compass_name(here.from_deg),
		roundi(here.speed_kn), roundi(here.gust_kn), here.get_label().to_lower()])
	var voyage := GameSession.get_voyage()
	if GameSession.is_underway() and voyage and voyage.route and voyage.route.has_path():
		var hazards := Simulation.route_hazards(voyage.route.path, voyage.progress_nm)
		if hazards.is_empty():
			out.append(Loc.t("Nothing worse than a fresh breeze is forecast on your course for now."))
		for hazard in hazards.slice(0, 3):
			out.append(Loc.t("On your course, %s: %s, %d nm ahead.") % [Loc.t(Simulation.describe_when(float(hazard.hours))),
				String(hazard.label).to_lower(), roundi(float(hazard.distance_nm))])
	elif not GameSession.is_underway():
		out.append(Loc.t("Plan a course at the chart table to hear what the forecast holds on the way."))
	return out


func focus_default() -> void:
	var answer := find_child("AnswerButton", true, false) as Button
	(answer if answer else find_child("CloseButton", true, false) as Button).grab_focus()
