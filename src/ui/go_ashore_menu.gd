class_name GoAshoreMenu
extends SimplePanel
## Go Ashore (Iteration 12): one small harbour moment. A title, a little drawn
## picture, a short text and one or two choices, each with its cost and the
## time it takes, plus Return to the boat. After a choice the panel tells what
## happened and offers only Return. GameSession does the bookkeeping; the App
## spends the time (choice_made).

signal choice_made(event_id: String, choice_index: int)

const Instrument := preload("res://src/ui/instrument_draw.gd")

var _offer := {}
var _icon: Control
var _icon_id := ""
var _text: Label
var _choices: VBoxContainer
var _time := 0.0


func _ready() -> void:
	var place := GameSession.get_location()
	_build(Loc.t("Ashore in %s") % (place.display_name if place else "harbour"), 660.0)
	var row := HBoxContainer.new()
	row.name = "EventRow"
	row.add_theme_constant_override(&"separation", 18)
	_box.add_child(row)
	_icon = Control.new()
	_icon.name = "Icon"
	_icon.custom_minimum_size = Vector2(96, 96)
	_icon.draw.connect(_draw_icon)
	row.add_child(_icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var heading := Label.new()
	heading.name = "EventTitle"
	heading.theme_type_variation = &"DisplayName"
	column.add_child(heading)
	_text = Label.new()
	_text.name = "EventText"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(500, 0)
	column.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_choices.add_theme_constant_override(&"separation", 8)
	_box.add_child(_choices)
	_button("ReturnButton", "Return to the boat", close, 220.0)
	_offer = GameSession.get_shore_event()
	if _offer.get("resting", false):
		heading.text = "A pleasant stroll"
		_icon_id = "bench"
		_text.text = Loc.t("You have had a good look around %s for now. Come back in a few hours, or see what the next harbour holds.") % \
			(place.display_name if place else Loc.t("the harbour"))
	elif _offer.has("event"):
		var event: Dictionary = _offer.event
		heading.text = event.title
		_icon_id = event.icon
		_text.text = ShoreEvents.fill(event.text, place.display_name)
		for i in event.choices.size():
			var choice: Dictionary = event.choices[i]
			var button := Button.new()
			button.name = "Choice%d" % i
			button.text = _describe_choice(choice)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = int(choice.cost) > GameSession.get_funds()
			button.pressed.connect(choice_made.emit.bind(String(event.id), i))
			_choices.add_child(button)
		if _offer.get("seen", false):
			_label("Seen", Loc.t("You have enjoyed everything %s has to offer before. It is still lovely.") % place.display_name, &"MutedLabel")
	else:
		heading.text = "Nothing ashore"
		_text.text = GameSession.facility_refusal(HarbourFacilities.GO_ASHORE)


func focus_default() -> void:
	var first := _choices.get_child(0) as Button if _choices.get_child_count() > 0 else null
	if first and not first.disabled:
		first.grab_focus()
	else:
		(find_child("ReturnButton", true, false) as Button).grab_focus()


func _process(delta: float) -> void:
	_time += delta
	_icon.queue_redraw()


## "Coffee and a pastry  ·  €6  ·  40 min" (free choices say so).
static func _describe_choice(choice: Dictionary) -> String:
	var cost := int(choice.cost)
	return Loc.t("%s  ·  %s  ·  %d min") % [choice.label, GameSession.format_money(cost) if cost > 0 else "free", int(choice.minutes)]


## Shows what happened; only Return remains.
func show_outcome(result: Dictionary) -> void:
	for child in _choices.get_children():
		child.queue_free()
	var seen := find_child("Seen", true, false)
	if seen:
		seen.queue_free()
	if String(result.error) != "":
		_text.text = result.error
		return
	var lines := [String(result.outcome)]
	var details := PackedStringArray()
	if int(result.cost) > 0:
		details.append("−%s" % GameSession.format_money(int(result.cost)))
	details.append(Loc.t("%d min") % int(result.minutes))
	if int(result.renown) > 0:
		details.append(Loc.t("+%d renown · a notable moment in the Captain's Log") % int(result.renown))
	lines.append("  ·  ".join(details))
	_text.text = "\n\n".join(lines)
	(find_child("ReturnButton", true, false) as Button).grab_focus()


func get_event_id() -> String:
	return String(_offer.event.id) if _offer.has("event") else ""


func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child)
	return buttons


func get_text() -> String:
	return _text.text


# --- The little picture ----------------------------------------------------------

## A line pictogram on a small data tile (Real Horizon): thin white strokes,
## one cyan detail, nothing filled in bright colour.
func _draw_icon() -> void:
	var c := _icon.size / 2.0
	var rect := Rect2(c - Vector2(44, 44), Vector2(88, 88))
	Instrument.tile(_icon, rect)
	Instrument.corners(_icon, rect.grow(-4.0), 8.0, Color(UiTheme.color(&"accent"), 0.7))
	var ink := UiTheme.color(&"ink")
	var soft := Color(UiTheme.color(&"ink_soft"), 0.8)
	var cyan := UiTheme.color(&"accent")
	var w := Instrument.STROKE
	var bob := sin(_time * 2.0) * 1.5
	match _icon_id:
		"cup":
			Instrument.outline(_icon, PackedVector2Array([c + Vector2(-16, -6), c + Vector2(10, -6), c + Vector2(8, 18), c + Vector2(-14, 18)]), ink, w)
			_icon.draw_arc(c + Vector2(11, 5), 6.0, -PI / 2, PI / 2, 10, ink, w, true)
			_icon.draw_line(c + Vector2(-22, 22), c + Vector2(16, 22), soft, 1.0, true)
			for i in 3:
				var x := c.x - 10 + i * 7
				_icon.draw_line(Vector2(x, c.y - 12 + bob), Vector2(x + 2, c.y - 22 + bob), Color(cyan, 0.8), 1.5, true)
		"bench":
			_icon.draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), ink, w, true)
			_icon.draw_line(c + Vector2(-26, -14), c + Vector2(26, -14), ink, w, true)
			for x in [-20.0, 20.0]:
				_icon.draw_line(c + Vector2(x, -14), c + Vector2(x, 18), ink, w, true)
			_icon.draw_line(c + Vector2(-30, 18), c + Vector2(30, 18), soft, 1.0, true)
			_icon.draw_line(c + Vector2(-26, 0), c + Vector2(26, 0), cyan, 1.0, true)
		"sailor":
			_icon.draw_arc(c + Vector2(0, -14), 9.0, 0, TAU, 24, ink, w, true)
			_icon.draw_arc(c + Vector2(0, 22), 18.0, PI * 1.1, PI * 1.9, 16, ink, w, true)
			for i in 2:
				_icon.draw_line(c + Vector2(-10, 9 + i * 6), c + Vector2(10, 9 + i * 6), cyan, 1.5, true)
		"basket":
			Instrument.outline(_icon, PackedVector2Array([c + Vector2(-20, -2), c + Vector2(20, -2), c + Vector2(14, 20), c + Vector2(-14, 20)]), ink, w)
			_icon.draw_arc(c + Vector2(0, -2), 16.0, PI, TAU, 16, ink, w, true)
			_icon.draw_arc(c + Vector2(-7, -7), 5.0, 0, TAU, 14, cyan, 1.5, true)
			_icon.draw_arc(c + Vector2(6, -8), 4.5, 0, TAU, 14, soft, 1.5, true)
			_icon.draw_line(c + Vector2(-17, 9), c + Vector2(17, 9), soft, 1.0, true)
		"view":
			_icon.draw_polyline(PackedVector2Array([c + Vector2(-34, 16), c + Vector2(-8, -16), c + Vector2(6, 2), c + Vector2(18, -8),
				c + Vector2(34, 16)]), ink, w, true)
			for i in 3:
				var y := c.y + 20 + i * 5
				_icon.draw_line(Vector2(c.x - 30 + i * 6, y), Vector2(c.x + 30 - i * 6, y), Color(cyan, 0.9 - i * 0.25), 1.5, true)
			_icon.draw_arc(c + Vector2(18, -24), 5.0, 0, TAU, 16, soft, 1.5, true)
		"board":
			_icon.draw_rect(Rect2(c + Vector2(-24, -20), Vector2(48, 34)), ink, false, w)
			for i in 4:
				var at := c + Vector2(-18 + (i % 2) * 20, -15 + (i / 2) * 15)
				_icon.draw_rect(Rect2(at, Vector2(16, 10)), cyan if i == 0 else soft, false, 1.0)
			_icon.draw_line(c + Vector2(0, 14), c + Vector2(0, 28), ink, w, true)
		"gull":
			for i in 3:
				var at := c + Vector2(-18 + i * 18, -4 + (i % 2) * 10 + bob * (1 if i % 2 else -1))
				var colour := cyan if i == 1 else ink
				_icon.draw_arc(at + Vector2(-5, 0), 5.0, PI, TAU, 8, colour, w, true)
				_icon.draw_arc(at + Vector2(5, 0), 5.0, PI, TAU, 8, colour, w, true)
		"boat":
			Instrument.outline(_icon, PackedVector2Array([c + Vector2(-28, 6), c + Vector2(28, 6), c + Vector2(18, 18), c + Vector2(-18, 18)]), ink, w)
			_icon.draw_line(c + Vector2(0, 6), c + Vector2(0, -26), ink, w, true)
			Instrument.outline(_icon, PackedVector2Array([c + Vector2(3, -24), c + Vector2(22, 1), c + Vector2(3, 1)]), cyan, 1.5)
			_icon.draw_line(c + Vector2(-34, 24 + bob * 0.5), c + Vector2(34, 24 + bob * 0.5), soft, 1.0, true)
		"houses":
			for i in 4:
				var x := c.x - 30 + i * 15
				var top := c.y - 14 + (i % 2) * 4
				_icon.draw_polyline(PackedVector2Array([Vector2(x, c.y + 18), Vector2(x, top), Vector2(x + 7, top - 7),
					Vector2(x + 14, top), Vector2(x + 14, c.y + 18)]), ink, 1.5, true)
				_icon.draw_rect(Rect2(x + 4, c.y - 4, 6, 6), cyan if i == 2 else soft, false, 1.0)
			_icon.draw_line(c + Vector2(-34, 18), c + Vector2(34, 18), ink, w, true)
		_:
			_icon.draw_arc(c, 10.0, 0, TAU, 24, ink, w, true)
			_icon.draw_circle(c, 3.0, cyan)
