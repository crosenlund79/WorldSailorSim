class_name TimePassage
extends CanvasLayer
## Time passing, gently (The Well-Run Ship): the game fades to black, the
## date (and for sleep the ship's clock) is shown in the middle of the
## screen, the time passes, and the game fades back into the new light.
##
##   7 May 2026
##   a Thursday
##
## Two uses, one look:
##   - sleep: the clock counts forward hour by hour (SLEEP_HOUR_SECONDS each,
##     calm, not a blur); midnight turns the date and the weekday;
##   - a new light (DayNightWatch): dawn or dusk, the date and a short phrase
##     ("a Thursday", "a Thursday evening").
## Purely presentation: the simulation is done by the caller under the black
## (`work`), never animated frame by frame here. Any key or click skips ahead
## to the fade back, so the captain is never kept waiting. While it shows,
## the game below is paused (the tree; this layer always runs).
##
## Tests switch it off (enabled = false), as does --no-time-passage on the
## command line (benchmarks): then callers do the same work at once, without
## any presentation.

signal finished

## Off in tests (the test runner), so logic tests stay synchronous.
static var enabled := true
## Tests of the presentation itself: shown even without a display.
static var headless_ok := false

const LAYER := 105
const FADE_OUT_SECONDS := 0.7
const FADE_IN_SECONDS := 1.0
## Real seconds each slept hour is shown for.
const SLEEP_HOUR_SECONDS := 0.42
## How long a dawn or dusk card rests on the screen.
const CARD_SECONDS := 2.2
## The black: a display's darkest charcoal-navy, not pure black.
const NIGHT_INK := Color("#0A1115")
## Instrument figures on the dark: white date, cyan phrase, soft clock.
const DATE_COLOUR := Color("#F0F3F1")
const PHRASE_COLOUR := Color("#7FC3D0")
const CLOCK_COLOUR := Color("#9DB0B5")

const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
	"November", "December"]
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

var _black: ColorRect
var _date: Label
var _phrase: Label
var _clock: Label
var _note: Label
var _skip := false
var _was_paused := false
var _running := false


## True when a time passage would be shown (not in tests, not headless).
static func is_shown() -> bool:
	return enabled and (headless_ok or DisplayServer.get_name() != "headless") and not OS.get_cmdline_user_args().has("--no-time-passage")


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = NIGHT_INK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_black.modulate.a = 0.0
	add_child(_black)
	var column := VBoxContainer.new()
	column.name = "Card"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 6)
	_black.add_child(column)
	_date = _label(column, "Date", &"DisplayHeader", DATE_COLOUR, 58)
	_phrase = _label(column, "Phrase", &"DisplayTagline", PHRASE_COLOUR, 32)
	_clock = _label(column, "Clock", &"Label", CLOCK_COLOUR, 30)
	_note = _label(column, "Note", &"Label", CLOCK_COLOUR, 22)
	for label in [_date, _phrase, _clock, _note]:
		label.modulate.a = 0.0


func _label(parent: Node, node_name: String, variation: StringName, colour: Color, size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_font_size_override(&"font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _input(event: InputEvent) -> void:
	# The black takes every click and key while it shows: nothing below reacts.
	if _running and (event is InputEventKey or event is InputEventMouseButton):
		if event.is_pressed():
			_skip = true
		get_viewport().set_input_as_handled()


func is_running() -> bool:
	return _running


# --- Words --------------------------------------------------------------------------------------

## "7 May 2026" (the ship's clock, UTC, like the HUD).
static func date_text(unix_time: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return Loc.t("%d %s %d", "date") % [d.day, Loc.month(d.month), d.year]


## "a Thursday", or "a Thursday evening".
static func weekday_phrase(unix_time: float, evening := false) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return (Loc.t("a %s evening") if evening else Loc.t("a %s")) % Loc.weekday(d.weekday)


## "22:00".
static func clock_text(unix_time: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%02d:%02d" % [d.hour, d.minute]


# --- Showing ---------------------------------------------------------------------------------------

## Sleep: fade to black, run `work` (the simulation, returns the game time
## slept to), then count the clock from `start_time` hour by hour to it,
## turning the date at midnight; `note` (why the captain woke early, or "")
## is shown at the end. Then fade back and emit finished.
func play_sleep(start_time: float, work: Callable, note_for := Callable()) -> void:
	_set_card(start_time, false)
	_clock.text = clock_text(start_time)
	await _begin()
	await _fade_texts([_date, _phrase, _clock], 1.0, 0.35)
	var end_time: float = work.call()
	var shown := start_time
	while shown < end_time - 1.0 and not _skip:
		await _wait(SLEEP_HOUR_SECONDS)
		shown = minf(shown + 3600.0, end_time)
		var before := Time.get_datetime_dict_from_unix_time(int(shown - 3600.0))
		_clock.text = clock_text(shown)
		if Time.get_datetime_dict_from_unix_time(int(shown)).day != before.day:
			_set_card(shown, false)
	_set_card(end_time, false)
	_clock.text = clock_text(end_time)
	var note: String = note_for.call() if note_for.is_valid() else ""
	if not note.is_empty():
		_note.text = note
		await _fade_texts([_note], 1.0, 0.3)
	await _wait(0.5 if not note.is_empty() else 0.3)
	await _end()


## A new light: fade to black, show the date and `phrase`-style words for
## `at_time` (evening: "a Thursday evening"), run `work` under the black (it
## completes the time and the light), then fade back.
func play_card(at_time: float, evening: bool, work: Callable) -> void:
	_set_card(at_time, evening)
	_clock.text = ""
	await _begin()
	await _fade_texts([_date, _phrase], 1.0, 0.45)
	work.call()
	await _wait(CARD_SECONDS)
	await _end()


func _set_card(unix_time: float, evening: bool) -> void:
	_date.text = date_text(unix_time)
	_phrase.text = weekday_phrase(unix_time, evening)


func _begin() -> void:
	_running = true
	_skip = false
	_was_paused = get_tree().paused
	get_tree().paused = true
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 1.0, FADE_OUT_SECONDS).set_trans(Tween.TRANS_SINE)
	await tween.finished


func _end() -> void:
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 0.0, FADE_IN_SECONDS).set_trans(Tween.TRANS_SINE)
	await tween.finished
	get_tree().paused = _was_paused
	_running = false
	finished.emit()
	queue_free()


func _fade_texts(labels: Array, to: float, seconds: float) -> void:
	if _skip:
		for label: Label in labels:
			label.modulate.a = to
		return
	var tween := create_tween().set_parallel()
	for label: Label in labels:
		tween.tween_property(label, "modulate:a", to, seconds)
	await tween.finished


## Waits `seconds` of real time, or less when the captain skips.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()
