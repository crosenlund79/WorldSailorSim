class_name BuildLabel
extends Label
## The development build identifier in the bottom-right corner of the window:
## "LCH · i024 · DEV · 1a2b3c4" (GameVersion.build_label()), so every
## screenshot and bug report says which checkpoint was running.
##
## App adds exactly one, on its own UiScaleLayer above everything else
## (menus, gameplay, pause, loading and time passing), so it stays through
## every screen change and follows the UI scale and the window size. Small,
## neutral grey with a soft dark outline (readable on light and dark), no
## panel, no animation; it ignores the mouse and never takes focus or keys.
## Hidden when GameVersion.shows_build_label() is false (a public export).

const LAYER := 128
const FONT_SIZE := 14
const MARGIN := Vector2(12, 4)


## A CanvasLayer holding the label, or null when it is switched off.
static func create_layer() -> CanvasLayer:
	if not GameVersion.shows_build_label():
		return null
	var layer := UiScaleLayer.new()
	layer.name = "BuildLabelLayer"
	layer.layer = LAYER
	var root := Control.new()
	root.name = "BuildLabelRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var label := BuildLabel.new()
	label.name = "BuildLabel"
	root.add_child(label)
	return layer


func _ready() -> void:
	text = GameVersion.build_label()
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_color_override(&"font_color", Color(0.8, 0.82, 0.82, 0.74))
	add_theme_color_override(&"font_outline_color", Color(0.04, 0.06, 0.07, 0.6))
	add_theme_constant_override(&"outline_size", 3)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN.x
	offset_bottom = -MARGIN.y
	offset_left = offset_right - get_minimum_size().x
	offset_top = offset_bottom - get_minimum_size().y
