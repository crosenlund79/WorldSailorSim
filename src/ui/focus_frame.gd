class_name FocusFrame
extends Control
## A focused view's surround (I026, A World You Can Touch): when a menu opens
## from a physical object - the logbook, the VHF set, the provisions locker,
## the stove, the trophy board, the sea chest, the berth's alarm clock, the
## systems panel - the object's material is drawn round the menu's panel so
## it reads as the object brought close (a book's boards, a radio's bezel, a
## teak frame, the stove's steel, an electrical panel), and the panel grows
## in briefly from the object's side of the screen. The menu itself is
## unchanged; the frame only draws, never takes the mouse or the keyboard.
##
## attach(modal, kind) after the modal is pushed. One frame per modal.

enum Kind { BOOK, RADIO, TEAK, STEEL, ELECTRIC }

const OPEN_SECONDS := 0.18
const MARGIN := 26.0
const SHADOW := Color(0.0, 0.02, 0.04, 0.35)

var kind := Kind.TEAK
var _panel: Control


## Frames `modal`'s "Panel" as `frame_kind`; returns the frame (null when the
## modal has no panel).
static func attach(modal: Control, frame_kind: Kind) -> FocusFrame:
	var panel := modal.find_child("Panel", true, false) as Control
	if panel == null or modal.has_node(^"FocusFrame"):
		return null
	var frame := FocusFrame.new()
	frame.name = "FocusFrame"
	frame.kind = frame_kind
	frame._panel = panel
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.focus_mode = Control.FOCUS_NONE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Under the panel, over the dimmed backdrop: a direct child of the modal
	# (never inside a container, which would lay it out), just before the
	# branch that holds the panel.
	var branch: Node = panel
	while branch.get_parent() != modal:
		branch = branch.get_parent()
	modal.add_child(frame)
	modal.move_child(frame, branch.get_index())
	panel.resized.connect(frame.queue_redraw)
	panel.item_rect_changed.connect(frame.queue_redraw)
	# Brought close: a short grow and fade-in.
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.94, 0.94)
	modal.modulate.a = 0.0
	var tween := modal.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, OPEN_SECONDS)
	tween.tween_property(modal, "modulate:a", 1.0, OPEN_SECONDS)
	return frame


func _draw() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var r := Rect2(_panel.get_global_rect().position - get_global_rect().position, _panel.size).grow(MARGIN)
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), SHADOW)
	match kind:
		Kind.BOOK:
			_book(r)
		Kind.RADIO:
			_radio(r)
		Kind.STEEL:
			_steel(r)
		Kind.ELECTRIC:
			_electric(r)
		_:
			_teak(r)


## A bound logbook lying open: dark green cloth boards, the cream page block
## round the page, the spine down the middle, a red ribbon.
func _book(r: Rect2) -> void:
	draw_rect(r, Color("#2A4439"))
	draw_rect(r.grow(-2.0), Color("#365A4B"))
	var pages := r.grow(-7.0)
	draw_rect(pages, Color(0.86, 0.83, 0.74))
	for i in 4:
		draw_rect(pages.grow(-1.5 - i * 1.6), Color(0.93, 0.9, 0.82, 0.5), false, 0.8)
	# The spine's shadow down the middle of the open book.
	var cx := r.get_center().x
	draw_rect(Rect2(Vector2(cx - 5.0, pages.position.y), Vector2(10.0, pages.size.y)), Color(0.45, 0.4, 0.32, 0.35))
	draw_line(Vector2(cx, r.position.y), Vector2(cx, r.end.y), Color(0.15, 0.22, 0.19, 0.8), 2.0)
	var rx := r.end.x - 60.0
	draw_colored_polygon(PackedVector2Array([Vector2(rx, r.position.y - 4.0), Vector2(rx + 10.0, r.position.y - 4.0),
		Vector2(rx + 10.0, r.position.y + 26.0), Vector2(rx + 5.0, r.position.y + 21.0), Vector2(rx, r.position.y + 26.0)]), Color("#9E3B32"))


## A marine VHF: a graphite moulding, four screws, a lit channel window.
func _radio(r: Rect2) -> void:
	draw_rect(r, Color("#15191C"))
	draw_rect(r.grow(-2.0), Color("#3A4247"))
	draw_rect(r.grow(-6.0), Color("#262C30"))
	# A speaker grille along the bottom edge.
	for i in 18:
		var x := r.position.x + 40.0 + i * 7.0
		if x < r.end.x - 120.0:
			draw_line(Vector2(x, r.end.y - 16.0), Vector2(x, r.end.y - 8.0), Color("#15191C"), 2.0)
	for corner in [r.position + Vector2(9, 9), Vector2(r.end.x - 9, r.position.y + 9), r.end - Vector2(9, 9), Vector2(r.position.x + 9, r.end.y - 9)]:
		draw_circle(corner, 3.0, Color("#5A6368"))
		draw_line(corner - Vector2(2, 0), corner + Vector2(2, 0), Color("#22282C"), 1.0)
	# The channel window, top right, softly lit.
	var w := Rect2(Vector2(r.end.x - 92.0, r.position.y + 2.0), Vector2(70.0, 13.0))
	draw_rect(w, Color("#3E6B5C"))
	draw_rect(w.grow(-2.0), Color("#7FCFAE"))
	draw_circle(Vector2(r.position.x + 30.0, r.position.y + 9.0), 3.0, Color("#E0A848"))


## Varnished teak with mitred corners (the locker, the board, the chest).
func _teak(r: Rect2) -> void:
	draw_rect(r, Color("#6B4A2E"))
	draw_rect(r.grow(-3.0), Color("#8A6240"))
	for i in 5:
		var y := r.position.y + 4.0 + i * (r.size.y - 8.0) / 5.0
		draw_line(Vector2(r.position.x + 4.0, y), Vector2(r.position.x + MARGIN - 4.0, y + 6.0), Color(0.36, 0.24, 0.14, 0.35), 1.0)
		draw_line(Vector2(r.end.x - MARGIN + 4.0, y), Vector2(r.end.x - 4.0, y + 6.0), Color(0.36, 0.24, 0.14, 0.35), 1.0)
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var toward: Vector2 = (r.get_center() - c).sign() * MARGIN
		draw_line(c, c + toward, Color(0.3, 0.2, 0.12, 0.6), 1.0)


## Brushed stainless round the galley.
func _steel(r: Rect2) -> void:
	draw_rect(r, Color("#8E979B"))
	draw_rect(r.grow(-3.0), Color("#AEB6B9"))
	for i in 9:
		var y := r.position.y + 3.0 + i * (r.size.y - 6.0) / 9.0
		draw_line(Vector2(r.position.x + 3.0, y), Vector2(r.end.x - 3.0, y), Color(1, 1, 1, 0.07), 1.0)
	# The fiddle rail along the front.
	draw_line(Vector2(r.position.x + 6.0, r.end.y - 5.0), Vector2(r.end.x - 6.0, r.end.y - 5.0), Color("#C9D0D2"), 3.0)


## An off-white switch panel with breakers down the sides.
func _electric(r: Rect2) -> void:
	draw_rect(r, Color("#C9CCC6"))
	draw_rect(r.grow(-3.0), Color("#DCDFD9"))
	var n := int((r.size.y - 20.0) / 26.0)
	for i in n:
		var y := r.position.y + 14.0 + i * 26.0
		for x in [r.position.x + 9.0, r.end.x - 9.0]:
			draw_rect(Rect2(Vector2(x - 4.0, y), Vector2(8.0, 12.0)), Color("#3A4044"))
			draw_rect(Rect2(Vector2(x - 2.5, y + 2.0), Vector2(5.0, 4.0)), Color("#E6E8E4"))
