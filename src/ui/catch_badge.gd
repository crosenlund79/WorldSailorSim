class_name CatchBadge
extends HBoxContainer
## Rarity and specimen grade at a glance (Iteration 18), never by colour
## alone: rarity as 1-4 filled pips with its name ("Rare"), the grade as a
## medal with its name ("Silver"). Sharks add "released"; junk shows neither.

## Grade discs: muted metal tones on the dark panel (named in text as well).
const MEDALS := {&"bronze": Color("#B4835A"), &"silver": Color("#B8C2C6"), &"gold": Color("#D2B05E")}

var _pips: Control
var _rarity_label: Label
var _grade_label: Label
var _medal: Control
var _rarity := ""
var _grade: StringName = &""


func _ready() -> void:
	add_theme_constant_override(&"separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips = Control.new()
	_pips.custom_minimum_size = Vector2(66, 20)
	_pips.draw.connect(_draw_pips)
	add_child(_pips)
	_rarity_label = Label.new()
	_rarity_label.name = "Rarity"
	add_child(_rarity_label)
	_medal = Control.new()
	_medal.custom_minimum_size = Vector2(22, 20)
	_medal.draw.connect(_draw_medal)
	add_child(_medal)
	_grade_label = Label.new()
	_grade_label.name = "Grade"
	add_child(_grade_label)
	UiTheme.palette_changed.connect(_update)
	_update()


## `rarity`: a FishingCatalog rarity id ("" for junk); `grade`: a grade or
## GRADE_NONE (shown as "Ordinary"); `show_grade` false before it is known.
func set_catch(rarity: String, grade: StringName, show_grade := true) -> void:
	_rarity = rarity
	_grade = grade if show_grade else &"?"
	_update()


func get_text() -> String:
	return "%s %s" % [_rarity_label.text, _grade_label.text] if _rarity_label else ""


func _update() -> void:
	if _rarity_label == null:
		return
	_pips.visible = _rarity != ""
	_rarity_label.visible = _rarity != ""
	_rarity_label.text = FishingCatalog.rarity_label(_rarity)
	var known := _grade != &"?" and _rarity != ""
	_medal.visible = known and _grade != FishingCatalog.GRADE_NONE
	_grade_label.visible = known
	_grade_label.text = ("· %s" % FishingCatalog.grade_label(_grade)) if known else ""
	_pips.queue_redraw()
	_medal.queue_redraw()


## Rarity as a small bar gauge (like a signal-strength readout): rising
## segments, the reached ones in instrument cyan.
func _draw_pips() -> void:
	var count := FishingCatalog.rarity_index(_rarity) + 1
	var cyan := UiTheme.color(&"accent")
	var empty := UiTheme.color(&"border")
	for i in FishingCatalog.RARITY_ORDER.size():
		var h := 6.0 + i * 3.0
		var bar := Rect2(Vector2(3 + i * 16, 17 - h), Vector2(11, h))
		if i < count:
			_pips.draw_rect(bar, cyan)
		else:
			_pips.draw_rect(bar.grow(-0.5), empty, false, 1.0)


func _draw_medal() -> void:
	if not MEDALS.has(_grade):
		return
	var c := Vector2(11, 10)
	_medal.draw_circle(c, 7.5, MEDALS[_grade])
	_medal.draw_arc(c, 7.5, 0.0, TAU, 24, UiTheme.color(&"surface_sunken"), 1.0, true)
	_medal.draw_arc(c, 4.0, 0.0, TAU, 16, Color(UiTheme.color(&"surface_sunken"), 0.6), 1.0, true)
