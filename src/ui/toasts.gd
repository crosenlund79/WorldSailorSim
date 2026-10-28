class_name Toasts
extends VBoxContainer
## Short, non-blocking notifications that fade out on their own. Works while
## the game is paused, so menus can report results (e.g. "Game saved").

const MAX_VISIBLE := 3
const DEFAULT_DURATION := 3.5
## The arrival card (I021) stays a little longer than a notice.
const CARD_DURATION := 6.0
## A Golden Harbour Moment stays a little longer (a click puts it away).
const MOMENT_DURATION := 14.0
## Width of the arrival card's picture (the harbour illustration, cropped).
const CARD_PICTURE_WIDTH := 420.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_message(text: String, duration := DEFAULT_DURATION) -> void:
	while get_child_count() >= MAX_VISIBLE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	add_child(panel)
	var tween := panel.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	panel.modulate.a = 0.0
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_interval(duration)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)


## An arrival card (I021): the harbour's illustration (the middle of the
## strip, if there is one), the arrival line and one short sentence about the
## place. Non-blocking like any notice; it fades on its own.
func show_card(title: String, text: String, picture: Texture2D, duration := CARD_DURATION) -> void:
	while get_child_count() >= MAX_VISIBLE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	panel.name = "ArrivalCard"
	panel.theme_type_variation = &"ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	if picture:
		var size := picture.get_size()
		var crop := AtlasTexture.new()  # the middle of the strip, about two-fifths of it
		crop.atlas = picture
		crop.region = Rect2(size.x * 0.3, 0.0, size.x * 0.4, size.y)
		var view := TextureRect.new()
		view.name = "Picture"
		view.texture = crop
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.custom_minimum_size = Vector2(CARD_PICTURE_WIDTH, CARD_PICTURE_WIDTH * size.y / maxf(size.x * 0.4, 1.0))
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(view)
	for line: Array in [[title, &"HeaderLabel"], [text, &""]]:
		if String(line[0]) == "":
			continue
		var label := Label.new()
		label.text = line[0]
		label.theme_type_variation = line[1]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = CARD_PICTURE_WIDTH
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
	add_child(panel)
	var tween := panel.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	panel.modulate.a = 0.0
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(duration)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


## A Golden Harbour Moment (HarbourMoment): in the same column as the
## notices, so nothing stacks over anything else; it fades after `duration`
## seconds unless put away sooner with a click.
func show_moment(moment: Control, duration := MOMENT_DURATION) -> void:
	while get_child_count() >= MAX_VISIBLE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	add_child(moment)
	var tween := moment.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	moment.modulate.a = 0.0
	tween.tween_property(moment, "modulate:a", 1.0, 0.35)
	tween.tween_interval(duration)
	tween.tween_property(moment, "modulate:a", 0.0, 0.8)
	tween.tween_callback(moment.queue_free)


func get_messages() -> PackedStringArray:
	var result := PackedStringArray()
	for panel in get_children():
		if panel.is_queued_for_deletion():
			continue
		var text := PackedStringArray()
		for label: Label in panel.find_children("*", &"Label", true, false):
			text.append(label.text)
		result.append("\n".join(text))
	return result


## Removes every notification at once (screenshots, tests).
func clear() -> void:
	for panel in get_children():
		remove_child(panel)
		panel.queue_free()
