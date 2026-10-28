class_name HatHook
extends Node2D
## The hat's place in the cabin: a brass hook, with the captain's hat on it
## while it is stored. Every cabin marks the spot with Layout/HatSpot (art
## only, no collision); BoatArea places this node there. The interaction
## (put on / hang up) is the cabin's `hat` station.

const HOOK := Color("#9AA3A6")  # stainless
const HOOK_DARK := Color("#5A6266")

var _stored := false


func _ready() -> void:
	# The hook (with or without the hat) is what the `hat` station highlights.
	add_to_group(HighlightResolver.GROUP)
	set_meta(HighlightResolver.META_FOR, &"hat")
	GameSession.hat_changed.connect(func(_status: StringName) -> void: refresh())
	GameSession.state_replaced.connect(refresh)
	refresh()


func refresh() -> void:
	_stored = GameSession.is_active() and GameSession.get_hat_status() == HatState.STORED
	queue_redraw()


## Global outline of the hook and its hat, for the focus highlight.
func get_highlight_outline() -> PackedVector2Array:
	# The hat when it hangs here, otherwise just the little brass plate.
	var local := HighlightResolver.circle(Vector2(0, 4), 22.0) if _stored \
		else HighlightResolver.rounded_rect(Rect2(-13, -8, 26, 16), 5.0)
	var points := PackedVector2Array()
	for p in local:
		points.append(to_global(p))
	return points


## True while the hat hangs here.
func is_showing_hat() -> bool:
	return _stored


func _draw() -> void:
	# The hook: a small brass plate with a peg.
	draw_rect(Rect2(-9, -4, 18, 8), HOOK_DARK)
	draw_rect(Rect2(-7, -3, 14, 6), HOOK)
	draw_circle(Vector2.ZERO, 3.0, HOOK_DARK)
	if _stored:
		HatArt.get_default().draw_slot(self, HatArt.SLOT_STORED, Vector2(0, 4), PI * 0.5)
