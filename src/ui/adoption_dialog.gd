class_name AdoptionDialog
extends SimplePanel
## The question at the companionway (I025, A Little More Room Aboard): the
## animal from the dock has followed the Captain home. "Adopt" asks for a
## name and whether it is a she or a he (both optional, the same choices as
## the companions of I024), then "Welcome aboard" confirms; "Not now" lets it
## go back to the dock. Esc decides nothing: the dialog closes and the animal
## keeps following (a key pressed by accident never sends it away).
##
## Emits `decided` once: CHOICE_ADOPT (with the name and gender), CHOICE_DECLINE
## or CHOICE_LATER.

signal decided(choice: StringName, companion_name: String, companion_gender: StringName)

const CHOICE_ADOPT := &"adopt"
const CHOICE_DECLINE := &"decline"
const CHOICE_LATER := &"later"
## The gender choices in the picker, in order ("" = not said).
const GENDER_CHOICES: Array[StringName] = [&"", CompanionState.GENDER_FEMALE, CompanionState.GENDER_MALE]

var kind: StringName = CompanionState.DEFAULT_KIND
var name_edit: LineEdit
var gender_picker: OptionButton
var _decided := false
var _question: Control
var _naming: Control


func _init(animal_kind: StringName = CompanionState.DEFAULT_KIND) -> void:
	kind = animal_kind


func _ready() -> void:
	_build(Loc.t("A friend from the dock"), 640.0)
	_question = VBoxContainer.new()
	_question.name = "Question"
	_box.add_child(_question)
	var text := Label.new()
	text.name = "Text"
	text.text = CompanionRemarks.followed_home(kind)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(560, 0)
	_question.add_child(text)
	_naming = VBoxContainer.new()
	_naming.name = "Naming"
	_naming.visible = false
	_naming.add_theme_constant_override(&"separation", 10)
	_box.add_child(_naming)
	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"MutedLabel"
	hint.text = Loc.t("Give it a name if you like, and say whether it is a she or a he. Both are optional.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	_naming.add_child(hint)
	var row := HBoxContainer.new()
	row.name = "NameRow"
	row.add_theme_constant_override(&"separation", 10)
	_naming.add_child(row)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.max_length = CompanionState.MAX_NAME_LENGTH
	name_edit.placeholder_text = Loc.t("Name (optional)")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_text: String) -> void: _adopt())
	row.add_child(name_edit)
	gender_picker = OptionButton.new()
	gender_picker.name = "GenderPicker"
	gender_picker.custom_minimum_size = Vector2(150, 0)
	for label in ["Not said", "Female", "Male"]:
		gender_picker.add_item(Loc.t(label))
	gender_picker.select(0)
	row.add_child(gender_picker)
	_button("NotNowButton", Loc.t("Not now"), _answer.bind(CHOICE_DECLINE))
	_button("AdoptButton", Loc.t("Adopt"), _to_naming)
	_button("BackButton", Loc.t("Back"), _to_question).visible = false
	_button("WelcomeButton", Loc.t("Welcome aboard"), _adopt).visible = false


func _find_button(button_name: String) -> Button:
	return find_child(button_name, true, false) as Button


func _to_naming() -> void:
	_question.visible = false
	_naming.visible = true
	_find_button("NotNowButton").visible = false
	_find_button("AdoptButton").visible = false
	_find_button("BackButton").visible = true
	_find_button("WelcomeButton").visible = true
	name_edit.grab_focus.call_deferred()


func _to_question() -> void:
	_question.visible = true
	_naming.visible = false
	_find_button("NotNowButton").visible = true
	_find_button("AdoptButton").visible = true
	_find_button("BackButton").visible = false
	_find_button("WelcomeButton").visible = false
	focus_default()


## Shows the naming step (tests and tools).
func choose_adopt() -> void:
	_to_naming()


func is_naming() -> bool:
	return _naming != null and _naming.visible


func _adopt() -> void:
	_answer(CHOICE_ADOPT)


func companion_name() -> String:
	return CompanionState.clean_name(name_edit.text) if name_edit else ""


func companion_gender() -> StringName:
	return GENDER_CHOICES[clampi(gender_picker.selected, 0, GENDER_CHOICES.size() - 1)] if gender_picker else &""


func _answer(choice: StringName) -> void:
	if _decided:
		return
	_decided = true
	decided.emit(choice, companion_name() if choice == CHOICE_ADOPT else "", companion_gender() if choice == CHOICE_ADOPT else &"")
	close()


func focus_default() -> void:
	var adopt := _find_button("AdoptButton")
	if adopt and adopt.visible:
		adopt.grab_focus()
	elif name_edit:
		name_edit.grab_focus()


## Esc: on the naming step back to the question; on the question, nothing
## decided (it keeps following).
func handle_back() -> void:
	if is_naming():
		_to_question()
	else:
		_answer(CHOICE_LATER)
