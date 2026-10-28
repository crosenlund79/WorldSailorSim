class_name QuayCompanion
extends Node2D
## A companion ashore on the quay (I026 stage 02): the light version of
## ShipCompanion for HarbourFront. The companions that are ashore with the
## Captain (CompanionState.AREA_SHORE) come along onto the quay; this shows
## one of them with its own illustrated clips (CompanionVisualSet), trotting
## after the Captain at a little distance and resting when they stop. At the
## café it settles by the Captain's table (the cat and the dog lie down
## beside it, the conure perches on the back of the chair).
##
## Presentation only: it changes nothing in the companion's state (it stays
## "ashore" in the save), has no collision and takes no input. Petting stays
## a thing of the deck and the cabin.

const FOLLOW_DISTANCE := 70.0
## Where it settles relative to the Captain's café seat.
const CAFE_OFFSET := Vector2(0.0, 22.0)
const PERCH_OFFSET := Vector2(0.0, -8.0)

var companion: CompanionState
var visual_set: CompanionVisualSet
## The Captain to follow (a Node2D), and its slot (0 or 1: two keep apart).
var captain: Node2D
var slot := 0
## Set by HarbourFront while the Captain sits at the café: the seat
## ({"at", "facing"}) to settle by, or {}.
var resting_at: Dictionary = {}

var _clip: StringName = CompanionVisualSet.POSE_RESTING
var _frames: Array[Texture2D] = []
var _fps := 8.0
var _time := 0.0
var _facing := 1.0
var _speed := 120.0


func setup(companion_: CompanionState, captain_: Node2D, slot_: int) -> void:
	companion = companion_
	captain = captain_
	slot = slot_
	visual_set = CompanionVisualSet.for_kind(companion.kind)
	name = "QuayCompanion" + str(slot + 1)
	position = captain.position + _offset()
	if visual_set:
		_speed = maxf(visual_set.walk_speed * 5.5, 110.0) if not _is_bird() else 160.0
	_set_clip(_rest_clip())


func _is_bird() -> bool:
	return companion and companion.kind == CompanionState.KIND_PARROT


func _offset() -> Vector2:
	return Vector2(-FOLLOW_DISTANCE - slot * 46.0, 26.0 + slot * 18.0)


func _rest_clip() -> StringName:
	if not resting_at.is_empty():
		return CompanionVisualSet.POSE_SLEEPING if not _is_bird() and fmod(_time, 90.0) > 40.0 else CompanionVisualSet.POSE_RESTING
	return CompanionVisualSet.POSE_SIT if visual_set and visual_set.get_pose_art(CompanionVisualSet.POSE_SIT) else CompanionVisualSet.POSE_RESTING


func _move_clip() -> StringName:
	if _is_bird():
		return CompanionVisualSet.POSE_FLY if visual_set and visual_set.get_pose_art(CompanionVisualSet.POSE_FLY) else CompanionVisualSet.POSE_HOP
	return CompanionVisualSet.POSE_WALK


func _set_clip(clip: StringName) -> void:
	if clip == _clip and not _frames.is_empty():
		return
	_clip = clip
	_frames = visual_set.get_frames(clip) if visual_set else ([] as Array[Texture2D])
	if _frames.is_empty() and visual_set:
		_clip = CompanionVisualSet.POSE_RESTING
		_frames = visual_set.get_frames(_clip)
	_fps = float(visual_set.get_clip_settings(_clip).fps) if visual_set else 8.0
	queue_redraw()


## Where it is going: beside the Captain, or its place at the café table.
func target() -> Vector2:
	if not resting_at.is_empty():
		var seat_at: Vector2 = resting_at.at
		var facing: Vector2 = resting_at.facing
		if _is_bird():
			return seat_at - facing * 12.0 + PERCH_OFFSET  # on the back of the Captain's chair
		# On the ground beside the chair, away from the table.
		return seat_at - facing * 44.0 + Vector2(0.0, CAFE_OFFSET.y if slot == 0 else -CAFE_OFFSET.y * 0.6)
	return captain.position + _offset()


func is_resting() -> bool:
	return position.distance_to(target()) < 6.0


func _process(delta: float) -> void:
	if captain == null:
		return
	_time += delta
	var to := target() - position
	var distance := to.length()
	var settle := 4.0 if not resting_at.is_empty() else 34.0
	if distance > settle:
		var step := minf(_speed * delta * clampf(distance / 120.0, 0.6, 1.6), distance)
		position += to / distance * step
		if absf(to.x) > 2.0:
			_facing = signf(to.x)
		_set_clip(_move_clip())
	else:
		_set_clip(_rest_clip())
	queue_redraw()


func _draw() -> void:
	if _frames.is_empty():
		draw_circle(Vector2.ZERO, 12.0, Color("#B9A27A"))
		return
	var frame: Texture2D = _frames[int(_time * _fps) % _frames.size()]
	var rect := visual_set.get_draw_rect(_clip, frame)
	var art := visual_set.get_pose_art(_clip)
	var flip := (art != null and art.flip_h) != (_facing < 0.0)
	if flip:
		rect.position.x = -rect.end.x
		rect.size.x = -rect.size.x
	draw_texture_rect(frame, rect, false)
