class_name NewGameMenu
extends ModalPanel
## Starts a new game: the player picks the ship's companion and, since I022,
## the difficulty (Standard preselected; DifficultyPicker). The cat is
## preselected. The companion only affects who lives aboard.
##
## I024 (The Company We Keep): three companions - a Ragdoll cat, a Pug and a
## green-cheeked conure (a small parrot) - and the player may give it a name
## and say whether it is a she or a he. Both are optional: without a name the
## game says "the cat"; no name is ever made up.

signal start_requested(companion_kind: StringName, level: StringName, companion_name: String, companion_gender: StringName)

## The gender choices in the picker, in order ("" = not said).
const GENDER_CHOICES: Array[StringName] = [&"", CompanionState.GENDER_FEMALE, CompanionState.GENDER_MALE]

var companion_kind: StringName = CompanionState.DEFAULT_KIND
var difficulty: DifficultyPicker

@onready var _cat: Button = %CatButton
@onready var _dog: Button = %DogButton
@onready var _parrot: Button = %ParrotButton
@onready var _preview: ShipCompanion = %Preview
@onready var _description: Label = %Description
@onready var _name: LineEdit = %NameEdit
@onready var _gender: OptionButton = %GenderPicker


func _ready() -> void:
	var group := ButtonGroup.new()
	for button in [_cat, _dog, _parrot]:
		button.button_group = group
	_cat.text = Loc.t("Ragdoll cat")
	_dog.text = Loc.t("Pug")
	_parrot.text = Loc.t("Parrot")
	_cat.pressed.connect(select.bind(CompanionState.KIND_CAT))
	_dog.pressed.connect(select.bind(CompanionState.KIND_DOG))
	_parrot.pressed.connect(select.bind(CompanionState.KIND_PARROT))
	_name.max_length = CompanionState.MAX_NAME_LENGTH
	_name.placeholder_text = Loc.t("Name (optional)")
	_name.text_submitted.connect(func(_text: String) -> void: _start())
	($Center/Panel/VBox/NameRow/NameLabel as Label).text = Loc.t("Name")
	_gender.clear()
	for label in ["Not said", "Female", "Male"]:
		_gender.add_item(Loc.t(label))
	_gender.select(0)
	difficulty = DifficultyPicker.new()
	var buttons := $Center/Panel/VBox/Buttons as Control
	buttons.add_sibling(difficulty)
	buttons.get_parent().move_child(difficulty, buttons.get_index())
	var heading := Label.new()
	heading.name = "DifficultyQuestion"
	heading.text = "How forgiving should the sea be?"
	difficulty.add_sibling(heading)
	heading.get_parent().move_child(heading, difficulty.get_index())
	%StartButton.pressed.connect(_start)
	%CancelButton.pressed.connect(close)
	select(CompanionState.DEFAULT_KIND)


func _start() -> void:
	start_requested.emit(companion_kind, difficulty.level, companion_name(), companion_gender())


## The name as it will be kept ("" when none).
func companion_name() -> String:
	return CompanionState.clean_name(_name.text)


func companion_gender() -> StringName:
	return GENDER_CHOICES[clampi(_gender.selected, 0, GENDER_CHOICES.size() - 1)]


func select(kind: StringName) -> void:
	companion_kind = kind
	_cat.set_pressed_no_signal(kind == CompanionState.KIND_CAT)
	_dog.set_pressed_no_signal(kind == CompanionState.KIND_DOG)
	_parrot.set_pressed_no_signal(kind == CompanionState.KIND_PARROT)
	_preview.show_kind(kind)
	match kind:
		CompanionState.KIND_DOG:
			_description.text = Loc.t("A Pug: compact, cheerful and always close by. Naps on the cabin sole, by the steps or next to the settee, and comes ashore with you.")
		CompanionState.KIND_PARROT:
			_description.text = Loc.t("A green-cheeked conure: a small parrot, free aboard, never caged. Flies between favourite perches, chirps and whistles, and comes ashore with you.")
		_:
			_description.text = Loc.t("A Ragdoll cat: calm, soft and blue-eyed. Likes the settee, the chart table and your berth, purrs when petted, and comes ashore with you.")


func focus_default() -> void:
	%StartButton.grab_focus()
