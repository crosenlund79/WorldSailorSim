class_name ScrapbookMenu
extends SimplePanel
## The scrapbook of Postcards from the Sea (I022): the cards made, newest
## first, one page at a time (arrows or Left/Right), each drawn again from
## the game's art (PostcardView) with when it was sent.

var page := 0
var view: PostcardView

var _when: Label
var _previous: Button
var _next: Button


func _ready() -> void:
	_build(Loc.t("Scrapbook"), 700)
	view = PostcardView.new()
	view.name = "Card"
	var center := CenterContainer.new()
	center.add_child(view)
	_box.add_child(center)
	_when = _label("When", "", &"MutedLabel")
	_when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_previous = _button("PreviousButton", "<", turn.bind(-1), 64.0)
	_next = _button("NextButton", ">", turn.bind(1), 64.0)
	_button("CloseButton", "Close", close)
	_show()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
		turn(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
		turn(1)
		get_viewport().set_input_as_handled()


func turn(delta: int) -> void:
	page = clampi(page + delta, 0, maxi(_cards().size() - 1, 0))
	_show()


## Newest first.
func _cards() -> Array[Dictionary]:
	var cards := GameSession.get_pastimes().postcards.duplicate()
	cards.reverse()
	return cards


func _show() -> void:
	var cards := _cards()
	view.visible = not cards.is_empty()
	_previous.disabled = page <= 0
	_next.disabled = page >= cards.size() - 1
	if cards.is_empty():
		_when.text = Loc.t("No postcards yet. Make one at the cabin table: Q, then Write a postcard.")
		return
	view.card = cards[page]
	_when.text = Loc.t("%d of %d · sent %s") % [page + 1, cards.size(), Simulation.format_game_time(float(cards[page].time))]


func focus_default() -> void:
	if not _next.disabled:
		_next.grab_focus()
	else:
		(_box.get_node("Buttons/CloseButton") as Button).grab_focus()
