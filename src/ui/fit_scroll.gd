class_name FitScroll
extends ScrollContainer
## A scroll area that is exactly as tall as its content when the screen has
## room, and only as tall as the screen allows when it has not (then the
## content scrolls). Its window's title and buttons stay outside it, so they
## are always on screen (Steady Hands: Settings had grown taller than a
## 1080-line screen, with its title and Apply / Back cut off, and the
## Boatyard at a 130 % interface size).
##
## `frame` is the window's panel: everything in it besides this scroll area
## is kept, and the scroll area gets what is left of the screen's height
## (less MARGIN at top and bottom). Recomputed only when the window size, the
## interface size or the content changes; never per frame.

const MARGIN := 24.0
const MIN_HEIGHT := 140.0

var frame: Control


## Wraps `nodes` (children of one container, in order) in a FitScroll placed
## where the first of them was. Returns the scroll area.
static func wrap(nodes: Array[Control], window_panel: Control) -> FitScroll:
	var first := nodes[0]
	var parent := first.get_parent()
	var index := first.get_index()
	var scroll := FitScroll.new()
	scroll.name = "FitScroll"
	scroll.frame = window_panel
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var separation: int = (parent as Control).get_theme_constant(&"separation") if parent is BoxContainer else 8
	content.add_theme_constant_override(&"separation", separation)
	scroll.add_child(content)
	parent.add_child(scroll)
	parent.move_child(scroll, index)
	for node in nodes:
		node.reparent(content, false)
	return scroll


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	get_viewport().size_changed.connect(_queue_fit)
	SettingsManager.ui_scale_changed.connect(func(_scale: float) -> void: _queue_fit())
	for child in get_children():
		if child is Control and not child is ScrollBar:
			(child as Control).minimum_size_changed.connect(_queue_fit)
	_queue_fit()


var _fit_queued := false


func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		fit.call_deferred()


## Sets the height: the content's, or what the screen leaves.
func fit() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	var content: Control = null
	for child in get_children():
		if child is Control and not child is ScrollBar:
			content = child
	if content == null:
		return
	var want := content.get_combined_minimum_size().y
	var scale_y := maxf(get_global_transform_with_canvas().get_scale().y, 0.01)
	var screen := get_viewport().get_visible_rect().size.y / scale_y
	# The rest of the window: what shares this scroll area's container, plus
	# the window panel's own border (not the panel's minimum size, which a
	# window may have set to the whole screen).
	var others := 0.0
	var box := get_parent() as Control
	if box:
		others = box.get_combined_minimum_size().y - get_combined_minimum_size().y
	if frame and frame != box:
		var style := frame.get_theme_stylebox(&"panel")
		others += style.get_minimum_size().y if style else 0.0
	var room := screen - others - MARGIN * 2.0
	var height := clampf(want, minf(MIN_HEIGHT, want), maxf(room, MIN_HEIGHT))
	if not is_equal_approx(custom_minimum_size.y, height):
		custom_minimum_size.y = height


## True when the content is taller than the room it has (it scrolls).
func is_scrolling() -> bool:
	for child in get_children():
		if child is Control and not child is ScrollBar:
			return (child as Control).get_combined_minimum_size().y > custom_minimum_size.y + 0.5
	return false
