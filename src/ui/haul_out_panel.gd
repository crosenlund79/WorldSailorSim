class_name HaulOutPanel
extends SimplePanel
## The haul-out (Iteration 14): a small event at a yard that can lift boats.
##
## First the choice: the haul-out itself (the bottom scrubbed, the hull put
## right) and any work worth doing while she is out (an engine or rig service
## when due, the hard antifouling coating if not fitted), with the total and
## the day it takes. Then the travel lift brings her up (HaulOutScene), the
## weed comes off, a day passes ashore, and the result is written to the
## Captain's Log (the Boat tab's care history).
##
## GameSession.haul_out() is the one transaction; the App spends the day
## (`time_requested`).

signal time_requested(minutes: float)

const LIFT_SECONDS := 1.8
const SCRUB_SECONDS := 1.2

var _scene: HaulOutScene
var _info: Label
var _total: Label
var _options := {}
var _confirm: Button
var _cancel: Button
var _finished := false
var _result := {}


func _ready() -> void:
	var location := GameSession.get_location()
	_build(Loc.t("Haul-out in %s") % (location.display_name if location else "harbour"), 720.0)
	_scene = HaulOutScene.new()
	_scene.name = "Scene"
	_scene.catamaran = GameSession.get_vessel_definition().hull_type == VesselDefinition.HULL_CATAMARAN
	var care := GameSession.get_boat_care()
	_scene.fouled = BoatCare.fouling(care, GameSession.get_game_time()) / BoatCare.FOULING_NEEDED
	_box.add_child(_scene)
	_info = _label("Info", Loc.t("The yard lifts the %s out for a day: the bottom is scrubbed and the hull put right. While she is out, the yard can also:") %
		GameSession.get_vessel_definition().display_name)
	var options := VBoxContainer.new()
	options.name = "Options"
	_box.add_child(options)
	var extras := GameSession.get_haul_out_extras()
	for extra in extras:
		var box := CheckBox.new()
		box.name = String(extra)
		var price := GameSession.upgrade_price(String(extra)) if extra == &"hard_antifouling" else int(GameSession.service_quote(extra).cost)
		var name: String = Loc.t(String(BoatCare.get_upgrade(String(extra)).name)) if extra == &"hard_antifouling" else Loc.t(BoatCare.SERVICE_NAMES[extra])
		box.text = "%s (%s)" % [name, GameSession.format_money(price)]
		box.toggled.connect(func(_on: bool) -> void: _update_total())
		options.add_child(box)
		_options[extra] = box
	if extras.is_empty():
		_info.text = Loc.t("The yard lifts the %s out for a day: the bottom is scrubbed and the hull put right.") % GameSession.get_vessel_definition().display_name
	_total = _label("Total", "", &"HeaderLabel")
	_cancel = _button("CancelButton", "Not now", close)
	_confirm = _button("ConfirmButton", "Haul out", _on_confirm, 220.0)
	_update_total()


func get_selected_extras() -> Array[StringName]:
	var extras: Array[StringName] = []
	for extra: StringName in _options:
		if (_options[extra] as CheckBox).button_pressed:
			extras.append(extra)
	return extras


## Ticks an option (tests and keyboard users alike).
func set_option(extra: StringName, on: bool) -> void:
	if _options.has(extra):
		(_options[extra] as CheckBox).button_pressed = on


func _update_total() -> void:
	if _finished:
		return
	var quote := GameSession.haul_out_quote(get_selected_extras())
	_total.text = Loc.t("Total %s · one day ashore · you have %s") % [GameSession.format_money(int(quote.cost)),
		GameSession.format_money(GameSession.get_funds())]
	_confirm.text = Loc.t("Haul out (%s)") % GameSession.format_money(int(quote.cost))
	_confirm.disabled = int(quote.cost) > GameSession.get_funds()


func _on_confirm() -> void:
	var extras := get_selected_extras()
	_result = GameSession.haul_out(extras)
	if _result.error != "":
		notify(_result.error)
		return
	SessionLog.write("haul_out", {"port": String(GameSession.get_location_id()), "cost": _result.cost,
		"extras": extras.map(func(e: StringName) -> String: return String(e)), "first": _result.first})
	_confirm.disabled = true
	_cancel.disabled = true
	for box: CheckBox in _options.values():
		box.disabled = true
	_total.text = "Up she comes…"
	var tween := create_tween()
	tween.tween_property(_scene, "lift", 1.0, LIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_scene, "fouled", 0.0, SCRUB_SECONDS)
	tween.tween_callback(_finish)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	time_requested.emit(float(_result.minutes))
	var location := GameSession.get_location()
	var done := PackedStringArray()
	for item: String in _result.done:
		done.append(item.to_lower())
	_info.text = Loc.t("A day on the hard in %s: %s. Back in the water, she feels quick and light again.") % [
		location.display_name if location else "harbour", ", ".join(done)]
	_total.text = Loc.t("Paid %s. Written in the Captain's Log (Boat).%s") % [GameSession.format_money(int(_result.cost)),
		Loc.t("\nFirst haul-out: +2 renown.") if _result.first else ""]
	_cancel.visible = false
	_confirm.text = "Back in the water"
	_confirm.disabled = false
	_confirm.pressed.disconnect(_on_confirm)
	_confirm.pressed.connect(close)
	_confirm.grab_focus()


## Skips the lifting animation (tests).
func finish_now() -> void:
	if _result.is_empty() or _finished:
		return
	_scene.lift = 1.0
	_scene.fouled = 0.0
	_finish()


func is_finished() -> bool:
	return _finished


func get_scene() -> HaulOutScene:
	return _scene


func focus_default() -> void:
	_confirm.grab_focus()
