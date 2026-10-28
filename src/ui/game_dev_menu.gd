class_name GameDevMenu
extends SimplePanel
## A Game Developer at Sea (I022): the captain's little game (Pastimes,
## data/pastimes/game_dev.json). Pick a task, answer its one small question,
## and work a session of two to four game hours (shown before it starts).
## App spends the hours on the one clock; an event can interrupt the session
## and the hours worked still count - the unfinished task waits here to go on
## with. The devlog shows the milestones reached.

signal work_requested(task_id: String, choice: int)

var choice := -1

var _task: OptionButton
var _question: Label
var _choices: VBoxContainer
var _note: Label
var _work: Button
var _order: Array[int] = []


func _ready() -> void:
	_build(Pastimes.game_title(), 900)
	var game := GameSession.get_pastimes().game
	var stones := Pastimes.milestones()
	var at := int(game.milestone)
	_label("Progress", Loc.t("Released! Every milestone is done; small updates still make it better.") if GameSession.is_game_released() else
		Loc.t("Milestone %d of %d: %s · %s of %s points") % [at + 1, stones.size(), Loc.t(String(stones[at].name)),
			String.num(float(game.points), 1), str(int(stones[at].points))], &"HeaderLabel")
	_label("Devlog", _devlog(), &"MutedLabel")
	_task = OptionButton.new()
	_task.name = "Task"
	for entry: Dictionary in Pastimes.tasks():
		_task.add_item(Loc.t("%s (%d h)") % [Loc.t(String(entry.name)), int(entry.hours)])
	_box.add_child(_task)
	_question = _label("Question", "")
	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_box.add_child(_choices)
	_note = _label("Note", "", &"MutedLabel")
	_task.item_selected.connect(func(_i: int) -> void: _show_task())
	_button("CancelButton", "Cancel", close)
	_work = _button("WorkButton", "", func() -> void: work_requested.emit(selected_task(), choice), 260.0)
	var unfinished: Dictionary = game.task
	_task.select(maxi(Pastimes.tasks().find_custom(func(t: Dictionary) -> bool: return t.id == unfinished.get("id")), 0))
	_show_task()


## The milestones reached, newest first, in the developer's own words.
func _devlog() -> String:
	var stones := Pastimes.milestones()
	var lines: Array[String] = []
	var entries: Array = GameSession.get_pastimes().game.log
	for i in range(entries.size() - 1, maxi(entries.size() - 3, 0) - 1, -1):
		var index := int(entries[i].milestone)
		if index < stones.size():
			lines.append("%s - %s\n%s" % [Simulation.format_game_time(float(entries[i].time)), Loc.t(String(stones[index].name)), Loc.t(String(stones[index].log))])
	return "\n\n".join(lines) if not lines.is_empty() else Loc.t("Devlog: nothing yet. Every game starts with a first small step.")


func selected_task() -> String:
	var tasks := Pastimes.tasks()
	return String(tasks[_task.selected].id) if _task.selected >= 0 and _task.selected < tasks.size() else ""


## The interrupted session of this task, or {}.
func _unfinished() -> Dictionary:
	var unfinished: Dictionary = GameSession.get_pastimes().game.task
	return unfinished if unfinished.get("id") == selected_task() else {}


func _show_task() -> void:
	var task := Pastimes.task(selected_task())
	_question.text = Loc.t(String(task.get("question", "")))
	for child in _choices.get_children():
		child.queue_free()
	var unfinished := _unfinished()
	_order = Pastimes.choice_order(selected_task(), int(GameSession.get_pastimes().game.sessions))
	var group := ButtonGroup.new()
	choice = int(unfinished.get("choice", -1))
	for i in _order:
		var button := Button.new()
		button.name = "Choice%d" % _order.find(i)
		button.text = Loc.t(String(task.choices[i]))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == choice
		button.disabled = not unfinished.is_empty()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void:
			choice = i
			_update())
		_choices.add_child(button)
	_update()


## Picks the choice shown at `position` (for tests and the keyboard).
func pick(position: int) -> void:
	if position >= 0 and position < _order.size() and _unfinished().is_empty():
		choice = _order[position]
		(_choices.get_child(position) as Button).button_pressed = true
		_update()


func _update() -> void:
	var task := Pastimes.task(selected_task())
	var unfinished := _unfinished()
	var minutes := float(task.get("hours", 2)) * 60.0 - float(unfinished.get("minutes", 0.0))
	var length := Simulation.format_duration(minutes * 60.0)
	_note.text = Loc.t("This session takes %s of game time. Time passes as usual; an alarm or a warning interrupts it, and the hours worked still count.") % length
	if not unfinished.is_empty():
		_note.text += "\n" + Loc.t("Interrupted last time: the rest of the session is waiting.")
	_work.disabled = choice < 0
	_work.text = (Loc.t("Go on working (%s)") if not unfinished.is_empty() else Loc.t("Work for %s")) % length if choice >= 0 else Loc.t("Choose an answer first")


func focus_default() -> void:
	_task.grab_focus()
