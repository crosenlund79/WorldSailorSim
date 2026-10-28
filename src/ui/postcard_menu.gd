class_name PostcardMenu
extends SimplePanel
## Postcards from the Sea (I022): choose what the card shows (a subject from
## the game's own records, Pastimes.subjects()), its words and its layout, see
## it, then make and publish it. Making one takes about two hours of game
## time, said before it starts; App spends them on the one clock (fade, the
## simulation, back at ×1) and an event can interrupt it - the card being
## made is then kept here to finish or put aside.
##
## A subject earns renown the first time only; the list says which have.
## The scrapbook (ScrapbookMenu) shows the cards made.

## The draft is set in GameSession; App spends the time.
signal make_requested
signal scrapbook_requested

var preview: PostcardView

var _subjects: Array[Dictionary] = []
var _subject: OptionButton
var _caption: OptionButton
var _layout: OptionButton
var _note: Label
var _make: Button


func _ready() -> void:
	_build(Loc.t("Postcards from the Sea"), 1080)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_box.add_child(row)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(400, 0)
	row.add_child(column)
	preview = PostcardView.new()
	preview.name = "Preview"
	row.add_child(preview)
	_subjects = Pastimes.subjects()
	_subject = _option(column, "Subject", Loc.t("What the card shows"))
	for subject in _subjects:
		var title := "%s: %s" % [Pastimes.kind_name(subject.kind), subject.title]
		_subject.add_item(title + ("  ✓" if Pastimes.is_posted(subject.kind, subject.subject) else ""))
	_caption = _option(column, "Caption", Loc.t("The words"))
	_layout = _option(column, "Layout", Loc.t("The layout"))
	for layout in Pastimes.LAYOUTS:
		_layout.add_item(Pastimes.layout_name(layout))
	_note = Label.new()
	_note.name = "Note"
	_note.theme_type_variation = &"MutedLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(400, 0)
	column.add_child(_note)
	_subject.item_selected.connect(func(_i: int) -> void: _fill_captions(0))
	_caption.item_selected.connect(func(_i: int) -> void: _update())
	_layout.item_selected.connect(func(_i: int) -> void: _update())
	_button("ScrapbookButton", Loc.t("Scrapbook (%d)") % GameSession.get_pastimes().postcards.size(), scrapbook_requested.emit)
	if not GameSession.get_pastimes().draft.is_empty():
		var aside := _button("AbandonButton", Loc.t("Throw away the unfinished card"), func() -> void: pass, 200.0)
		aside.pressed.connect(func() -> void:
			GameSession.abandon_postcard()
			aside.hide()
			_update())
	_button("CancelButton", "Cancel", close)
	_make = _button("MakeButton", "", _on_make, 260.0)
	_resume_draft()
	_update()


func _option(column: VBoxContainer, node_name: String, title: String) -> OptionButton:
	var label := Label.new()
	label.text = title
	column.add_child(label)
	var option := OptionButton.new()
	option.name = node_name
	option.fit_to_longest_item = false
	option.custom_minimum_size = Vector2(400, 0)
	column.add_child(option)
	return option


## A card interrupted part-way comes back as it was.
func _resume_draft() -> void:
	var draft := GameSession.get_pastimes().draft
	var index := _subjects.find_custom(func(s: Dictionary) -> bool: return s.kind == draft.get("kind") and s.subject == draft.get("subject"))
	_subject.select(maxi(index, 0))
	_fill_captions(int(draft.get("caption", 0)) if index >= 0 else 0)
	_layout.select(maxi(Pastimes.LAYOUTS.find(String(draft.get("layout", "classic"))), 0))


func _fill_captions(selected: int) -> void:
	_caption.clear()
	var subject := selected_subject()
	if subject.is_empty():
		return
	for i in Pastimes.captions(subject.kind).size():
		_caption.add_item(Pastimes.caption_text(subject.kind, i, subject.args))
	_caption.select(clampi(selected, 0, _caption.item_count - 1))
	_update()


func selected_subject() -> Dictionary:
	return _subjects[_subject.selected] if _subject.selected >= 0 and _subject.selected < _subjects.size() else {}


## The card as chosen now (what the preview shows).
func chosen_card() -> Dictionary:
	var subject := selected_subject()
	if subject.is_empty():
		return {}
	return {"kind": subject.kind, "subject": subject.subject, "caption": maxi(_caption.selected, 0),
		"layout": Pastimes.LAYOUTS[maxi(_layout.selected, 0)], "place": Pastimes.where_now()}


## Chooses subject `index`, caption and layout (keyboard-free, for tests).
func choose(index: int, caption: int, layout: String) -> void:
	_subject.select(index)
	_fill_captions(caption)
	_layout.select(maxi(Pastimes.LAYOUTS.find(layout), 0))
	_update()


func _update() -> void:
	var card := chosen_card()
	preview.card = card
	if card.is_empty():
		_note.text = Loc.t("Nothing to send yet.")
		_make.disabled = true
		_make.text = Loc.t("Make and publish")
		return
	var draft := GameSession.get_pastimes().draft
	var same: bool = draft.get("kind") == card.kind and draft.get("subject") == card.subject
	var minutes := GameSession.postcard_minutes_left() if same else Pastimes.postcard_minutes()
	var hours := Simulation.format_duration(minutes * 60.0)
	var reward := Loc.t("A first card of this subject earns %d renown.") % Pastimes.postcard_renown() if not Pastimes.is_posted(card.kind, card.subject) \
		else Loc.t("Already posted once: a card for the scrapbook, without renown.")
	_note.text = Loc.t("Writing, arranging and publishing a postcard takes about %s of game time. Time passes as usual, and an alarm or a warning interrupts it; the card is kept to finish later.") % hours \
		+ "\n" + reward
	_make.disabled = false
	_make.text = (Loc.t("Finish the card (%s)") if same else Loc.t("Make and publish (%s)")) % hours


func _on_make() -> void:
	var card := chosen_card()
	if card.is_empty():
		return
	GameSession.set_postcard_draft(card.kind, card.subject, card.caption, card.layout)
	make_requested.emit()


func focus_default() -> void:
	(_make if not _make.disabled else _subject).grab_focus()
