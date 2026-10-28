class_name DifficultyMenu
extends SimplePanel
## The difficulty during a game (I022), from the pause menu: the same three
## levels as at the start. A change counts from now on: food, wear, weather
## damage and harbour costs follow the new level; money already spent or
## earned and the boat's state stay as they are (the starting money is not
## given or taken back).

var picker: DifficultyPicker


func _ready() -> void:
	_build("Difficulty", 660.0)
	_label("Note", Loc.t("A change counts from now on. Money already spent or earned and the state of your boat stay as they are."),
		&"MutedLabel")
	picker = DifficultyPicker.new()
	picker.level = GameSession.get_difficulty()
	_box.add_child(picker)
	_button("CancelButton", "Cancel", close)
	_button("ApplyButton", "Apply", func() -> void:
		var changed := picker.level != GameSession.get_difficulty()
		GameSession.set_difficulty(picker.level)
		if changed:
			notify(Loc.t("Difficulty: %s, from now on.") % Difficulty.display_name(picker.level))
		close())


func focus_default() -> void:
	var apply := find_child("ApplyButton", true, false) as Button
	if apply:
		apply.grab_focus()
