class_name AcademyGuide
extends Control
## The Captain's Academy in play (I022): one small card in the lower right
## corner, never a window that blocks the game.
##
## The First Voyage (Layer A): one step at a time, each ticked off by what the
## player really does (walking, the wheel, the log, the deck, the chart, a
## course, setting sail, letting time run). The card always has Skip.
##
## Contextual tips (Layer B): the first time something happens (the first
## time underway, a weather warning, a bite, a harbour ...) a short tip is
## queued; it shows only when nothing else is open, no warning is up and the
## First Voyage is not running, once per computer, and it can be closed or
## followed to its Handbook page. Tips can be turned off in Settings.
##
## The card hides whenever a window opens, a warning shows or time passes
## under the black, and comes back afterwards.

## Off in tests (the suites that test the Academy switch it on).
static var enabled := true

const CHECK_SECONDS := 0.25
const NIGHT_CHECK_SECONDS := 2.0
const TIP_SECONDS := 25.0
const DONE_SECONDS := 12.0
## Right margin of the card: aboard it sits in the free lower right corner;
## at the chart it stays left of the chart's side panel (its buttons).
const MARGIN_ABOARD := 24.0
const MARGIN_CHART := 540.0
## A breath between two tips (seconds of play).
const TIP_GAP_SECONDS := 20.0
## The sun this far below the horizon counts as night (for the night tip).
const NIGHT_ELEVATION := -6.0

## The App (untyped: App's script refers to this class).
var app: Node
var card: PanelContainer

var _heading: Label
var _text: Label
var _more: Button
var _close: Button
var _skip: Button
var _queue: Array[String] = []
## The tip on the card now ("" none); "!done" is the First Voyage's farewell.
var _tip := ""
var _tip_left := 0.0
var _moved := false
var _check_left := 0.0
var _night_left := 0.0
var _gap_left := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = PanelContainer.new()
	card.name = "AcademyCard"
	card.custom_minimum_size = Vector2(440, 0)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_right = -24.0
	card.offset_bottom = -120.0
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.theme_type_variation = &"HeaderLabel"
	box.add_child(_heading)
	_text = Label.new()
	_text.name = "Text"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(420, 0)
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_skip = _add_button(buttons, "SkipButton", skip_first_voyage)
	_more = _add_button(buttons, "MoreButton", read_more)
	_close = _add_button(buttons, "CloseButton", dismiss)
	card.hide()
	GameSession.voyage_started.connect(func() -> void: queue_tip("underway"))
	Simulation.arrived.connect(func(_port: StringName) -> void:
		queue_tip("arrival")
		if GameSession.has_facility(HarbourFacilities.BOATYARD):
			queue_tip("boatyard"))
	Simulation.weather_warning.connect(func(_warning: Dictionary) -> void: queue_tip("weather"))
	Simulation.traffic_alert.connect(func(_info: Dictionary) -> void: queue_tip("traffic"))
	Simulation.vhf_call.connect(func(_call: Dictionary) -> void: queue_tip("vhf"))
	Simulation.passage_started.connect(func(_rate: float) -> void: queue_tip("passage"))
	GameSession.fish_bite.connect(func(_info: Dictionary) -> void: queue_tip("bite"))
	GameSession.anchor_changed.connect(func() -> void:
		if GameSession.is_anchored():
			queue_tip("anchor"))
	GameSession.provisions_warning.connect(func(_level: int, _text_: String) -> void: queue_tip("provisions"))
	GameSession.hat_warning.connect(func(_text_: String) -> void: queue_tip("hat"))
	GameSession.renown_awarded.connect(func(_awards: Array) -> void: queue_tip("renown"))
	GameSession.boat_area_changed.connect(func(area: StringName) -> void:
		if area == SessionState.AREA_INTERIOR:
			queue_tip("cabin"))


func _add_button(row: HBoxContainer, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_NONE  # never takes the keys from the game
	button.pressed.connect(action)
	row.add_child(button)
	return button


## Remembers that `id` happened; its tip shows at the next free moment
## (once per computer, and only with tips on).
func queue_tip(id: String) -> void:
	if not enabled or Academy.tip(id).is_empty() or Academy.is_tip_seen(id) or _queue.has(id) or _tip == id:
		return
	_queue.append(id)


func queued_tips() -> Array[String]:
	return _queue


func shown_tip() -> String:
	return _tip


func _input(event: InputEvent) -> void:
	if not _moved and Academy.first_voyage_state() == Academy.ACTIVE:
		for action in Academy.MOVE_ACTIONS:
			if event.is_action_pressed(action):
				_moved = true


func _process(delta: float) -> void:
	if not enabled:
		card.hide()
		return
	if card.visible and not _tip.is_empty():
		_tip_left -= delta
		if _tip_left <= 0.0:
			dismiss()
	_gap_left -= delta
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_SECONDS
	_night_left -= CHECK_SECONDS
	if _night_left <= 0.0:
		_night_left = NIGHT_CHECK_SECONDS
		if GameSession.is_active() and Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time()) < NIGHT_ELEVATION:
			queue_tip("night")
	update_card()


## Shows, changes or hides the card for this moment.
func update_card() -> void:
	var voyage := Academy.first_voyage_state() == Academy.ACTIVE
	if voyage and GameSession.is_active():
		_advance_voyage()
		voyage = Academy.first_voyage_state() == Academy.ACTIVE
		if not voyage and _tip.is_empty():
			_tip = "!done"
			_tip_left = DONE_SECONDS
	var free := is_free()
	if not free:
		card.hide()
		return
	if voyage:
		_show_step()
		return
	if not SettingsManager.get_tips_enabled() and _tip != "!done":
		_tip = ""
	if _tip.is_empty() and SettingsManager.get_tips_enabled() and not _queue.is_empty() and _gap_left <= 0.0:
		_tip = _queue.pop_front()
		_tip_left = TIP_SECONDS
		Academy.mark_tip_seen(_tip)
	if _tip.is_empty():
		card.hide()
	elif _tip == "!done":
		var done: Dictionary = Academy.data().get("first_voyage_done", {})
		_show(Loc.t(String(done.get("title", ""))), Academy.fill(String(done.get("text", ""))), false, false)
	else:
		_show(Loc.t("Tip"), Academy.fill(String(Academy.tip(_tip).text)), true, false)


## True when the card may show: in play (aboard or at the chart), nothing
## open, no warning up, no time passing under the black, nothing loading.
func is_free() -> bool:
	if app == null or not GameSession.is_active() or app.router.is_busy() or not app.modals.is_empty():
		return false
	if not (app.router.current_screen is BoatArea or app.router.current_screen is WorldMap):
		return false
	if is_instance_valid(app.time_passage) or is_instance_valid(app.voyage_map) or app.is_loading():
		return false
	return not app.hud.is_warning_visible()


func _show(heading: String, text: String, more: bool, skip: bool) -> void:
	card.offset_right = -(MARGIN_CHART if app and app.router.current_screen is WorldMap else MARGIN_ABOARD)
	_heading.text = heading
	_text.text = text
	_more.visible = more
	_close.visible = true
	_more.text = Loc.t("Read more")
	_close.text = Loc.t("Got it")
	_skip.visible = skip
	_skip.text = Loc.t("Skip the First Voyage")
	card.show()


func _show_step() -> void:
	var list := Academy.steps()
	var index := clampi(Academy.current_step(), 0, list.size() - 1)
	var step: Dictionary = list[index]
	_show(Loc.t("First Voyage · %d of %d: %s") % [index + 1, list.size(), Loc.t(String(step.title))], Academy.fill(String(step.text)), true, true)
	_close.visible = false


## Ticks off every step that is done now (a step already true goes at once).
func _advance_voyage() -> void:
	var list := Academy.steps()
	while Academy.first_voyage_state() == Academy.ACTIVE and Academy.current_step() < list.size():
		if not step_done(String(list[Academy.current_step()].id)):
			return
		Academy.complete_step()


## Whether the player has done First Voyage step `id`.
func step_done(id: String) -> bool:
	var screen: Node = app.router.current_screen if app else null
	match id:
		"walk":
			return _moved
		"wheel":
			return app != null and app.modals.get_top() is ActionWheel
		"log":
			return app != null and app.modals.get_top() is CaptainsLogMenu
		"deck":
			return screen is BoatArea and (screen as BoatArea).area_id == SessionState.AREA_EXTERIOR
		"chart":
			return screen is WorldMap
		"course":
			return GameSession.get_planned_route() != null or GameSession.is_underway()
		"sail":
			return GameSession.is_underway()
		"speed":
			return GameSession.is_underway() and GameSession.get_time_scale() > 1
	return false


## Closes the tip (or the First Voyage's farewell).
func dismiss() -> void:
	if not _tip.is_empty():
		_gap_left = TIP_GAP_SECONDS
	_tip = ""
	card.hide()


## Opens the Handbook at the page of the tip or step shown.
func read_more() -> void:
	var page := ""
	if Academy.first_voyage_state() == Academy.ACTIVE:
		page = String(Academy.steps()[clampi(Academy.current_step(), 0, Academy.steps().size() - 1)].get("page", ""))
	elif not _tip.is_empty() and _tip != "!done":
		page = String(Academy.tip(_tip).get("page", ""))
		dismiss()
	if app:
		app.open_handbook(page)


func skip_first_voyage() -> void:
	Academy.skip_first_voyage()
	card.hide()
	if app:
		app.notify(Loc.t("First Voyage skipped. You can begin it again from the Captain's Handbook (%s).") % Academy.key("handbook"))


## Begins the First Voyage now (after the offer, or from the Handbook).
func begin_first_voyage() -> void:
	Academy.begin_first_voyage()
	_moved = false
	_tip = ""
	update_card()
