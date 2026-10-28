class_name ShipCompanion
extends Node2D
## The ship's cat or dog, resting in the cabin. Presentation only: the kind
## and resting spot come from GameSession (CompanionState), so the companion
## is the same after loading, sleeping or coming back from the deck or chart.
## Exactly one exists, because it is part of the cabin scene.
##
## Where it rests comes from the cabin's layout: the marker named after the
## spot under `spots_path` (Layout/CompanionSpots), so every vessel places its
## own spots. When the schedule moves it while you watch, it walks (the parrot
## flies) there; out of view, asleep or at high time speed it is simply there.
## No pathfinding in the cabin and no collision, so it never blocks the player.
##
## Look: when the kind has a CompanionVisualSet (data/companions/<kind>_visuals.tres,
## the cat and, since Iteration 13, the dog) the companion shows pose images: resting most of the
## time, now and then a nap or a stretch, a short alert look when the player
## comes close, and the alert pose with hearts when petted. Poses change with
## a short cross-fade; the timing comes from the set. Poses are presentation
## only and never saved. Without a set, or when its images are missing, the
## procedural top-down drawing is used (the fallback).
##
## Petting it (E, via its Interactable) plays a short sound on the SFX bus and
## a small reaction: the cat purrs and shows a few hearts; the dog pants softly
## and wags its tail.
##
## I024 (The Company We Keep): three kinds (a Ragdoll cat, a Pug, a small
## parrot), and the poses are animated clips (CompanionPoseArt frames): the
## logical `pose` (resting, sleeping, alert, stretching, sit, groom, ...)
## chooses the clip, short transition clips (lie down, wake, turn, settle,
## takeoff, land) play in between, and walking uses the walk clip at the
## stride's own speed so the feet do not slide. It faces where it goes (the
## art faces right; it is mirrored for left). The parrot flies between its
## perches (takeoff, flight with a little height, landing) and hops short
## distances. Ashore (CompanionState.AREA_SHORE) the deck companion follows
## the Captain down the gangplank to a place on the pontoon.
##
## Iteration 18: the companion can also be on deck (CompanionState.area). The
## deck has its own ShipCompanion (`on_deck`, built by BoatArea) resting at
## the deck's safe places (DeckCompanionSpots); the cabin one shows only while
## the companion is below. When it changes area while you watch, it walks:
## up from the companionway to its place, between places, or back to the
## companionway and below - along paths that stay aboard (since I024 with the
## walk clip at the stride's speed; see above).

signal petted(kind: StringName)
signal pose_changed(pose: StringName)
## Life at anchor (0.102b): the companion settled down for a quiet stay at
## anchor (curls up and dozes much more), or stopped being settled.
signal settled_changed(settled: bool)

const REACTION_SECONDS := 1.6
const INTERACT_RADIUS := 34.0
## Drawn in a flat top-down style matching the boat fixtures.
const CAT_FUR := Color("#5E6A72")
const CAT_DARK := Color("#3E474D")
const CAT_LIGHT := Color("#D9CFB8")
const DOG_FUR := Color("#9C6B45")
const DOG_DARK := Color("#6E4A30")
const DOG_LIGHT := Color("#E3D2B4")
const OUTLINE := Color(0.06, 0.1, 0.12, 0.55)
const HEART := Color("#C97A6C")

@export var purr_sound: AudioStream = preload("res://assets/audio/placeholder/companion_purr.wav")
@export var dog_sound: AudioStream = preload("res://assets/audio/placeholder/companion_dog_pant.wav")
@export var parrot_sound: AudioStream = preload("res://assets/audio/placeholder/companion_parrot_chirp.wav")

## A preview (e.g. in the New Game dialog): just the drawing, no
## interaction and no session state.
@export var preview := false
## The cabin's resting-spot markers (one Marker2D per CompanionState spot id).
@export var spots_path := ^"../Layout/CompanionSpots"
## I025: which companion this node shows - the first (0) or the second (1)
## aboard. Every cabin and deck has one node per slot; a slot with nobody in
## it shows nothing. Signals name a companion by its stable id.
@export var slot := 0
## I025: an animal that is not (yet) a companion - the one waiting on the
## dock (DockEncounterScene). Its kind is set directly; it follows no session
## state and is not petted (its own interaction is "befriend").
@export var stray := false
## Where a second animal rests when both share a spot (towards the room's
## middle, so they lie side by side, never on top of one another).
const PAIR_OFFSET := 26.0
## I025: how much faster than its calm walk it moves (and its walk clip
## plays, so the feet never slide): a dock animal following the Captain
## (the cat walks briskly, the Pug trots).
var pace := 1.0

var kind: StringName = CompanionState.DEFAULT_KIND
var spot: StringName = &""
var interactable: Interactable
## The pose images of the current kind (null: procedural drawing).
var visual_set: CompanionVisualSet
## The pose shown now (sprite mode only).
var pose: StringName = CompanionVisualSet.POSE_RESTING

var _textures := {}             # pose -> Texture2D, frame 0 (only poses that loaded)
var _clips := {}                # pose -> Array[Texture2D] (I024 animation frames)
## The clip drawn now (usually the pose's own; a transition plays first).
var clip: StringName = CompanionVisualSet.POSE_RESTING
var _clip_time := 0.0
var _clip_rate := 1.0
var _clip_queue: Array[StringName] = []
## +1 facing right (as drawn), -1 mirrored.
var facing := 1.0
var _previous_flip := false
var _previous_rect := Rect2()
## Parrot flight: height above the ground point while flying (scene units).
var _lift := 0.0
var _flying := false
## Seconds the walk waits before moving (a turn or a takeoff plays first).
var _walk_delay := 0.0
var _turn_flip_at := -1.0
var _blink_left := 4.0
var _pose_left := 0.0           # seconds until the next idle change
var _previous_texture: Texture2D
var _previous_pose: StringName
var _fade := 1.0                # 0 -> 1 while cross-fading to the new pose
var _alert_ready_at := 0.0      # _time from which an approach may alert again
var _was_focused := false
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _reaction := 0.0
## Seconds a walk waits because the companion was just petted (it stops,
## enjoys it, then walks on).
var _walk_pause := 0.0
## Settled at anchor: rest turns into long naps (see advance_behaviour()).
var settled := false
## The deck's companion (Iteration 18): rests at DeckCompanionSpots.
var on_deck := false
var deck_spots: DeckCompanionSpots
const WALK_SPEED := 60.0
const FLY_SPEED := 140.0
## How high the parrot flies over the cabin and deck (scene units).
const FLY_HEIGHT := 22.0
## The parrot hops instead of flying when the distance is this short.
const HOP_DISTANCE := 34.0
## How far the hop clip moves the bird forward on its 256 px canvas.
const HOP_DRIFT_PX := 15.0
## Ashore: its places on the pontoon, as offsets along the shore from the
## gangplank (clear of the service stations at ±215).
const SHORE_OFFSETS: Array[float] = [-80.0, 95.0, -150.0]
var _walk := PackedVector2Array()
var _walk_index := 0
var _walking_out := false
## How much longer the naps are while settled.
const SETTLED_SLEEP_FACTOR := 2.5
## A kind word when petted (CompanionRemarks): at most one per
## REMARK_COOLDOWN_MS of real time, so petting often does not fill the
## screen with notes. The turn is shared by every companion node in this run,
## so the next remark is a different line wherever the companion is.
const REMARK_COOLDOWN_MS := 15000
static var _remark_turn := 0
static var _last_remark_ms := -REMARK_COOLDOWN_MS


func _ready() -> void:
	z_index = 5
	if preview:
		_load_visuals()
		return
	interactable = Interactable.new()
	interactable.name = "Pet"
	interactable.interaction_id = &"befriend" if stray else &"pet"
	interactable.focus_priority = -1  # stations and doors nearby keep precedence
	# Focused, it glows around the animal itself (Iteration 13), like every
	# station: no tint, no circle.
	interactable.highlight_target = ^""
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = INTERACT_RADIUS
	shape.shape = circle
	interactable.add_child(shape)
	add_child(interactable)
	set_meta(HighlightResolver.META_FOR, interactable.interaction_id)
	add_to_group(HighlightResolver.GROUP)
	if stray:
		_load_visuals()
		return
	_sync()
	GameSession.companion_area_changed.connect(_on_area_changed)
	GameSession.companion_moved.connect(_on_companion_moved)
	GameSession.state_replaced.connect(_sync)
	GameSession.companions_changed.connect(_sync)
	GameSession.anchor_life_changed.connect(_on_anchor_life_changed)
	# Coming below at a quiet anchorage: already curled up.
	if GameSession.is_settled_at_anchor():
		settled = true
		if is_sprite_mode():
			set_pose(CompanionVisualSet.POSE_SLEEPING)


func _process(delta: float) -> void:
	_time += delta
	_reaction = maxf(_reaction - delta, 0.0)
	_walk_pause = maxf(_walk_pause - delta, 0.0)
	if is_walking() and _walk_pause <= 0.0:
		_advance_walk(delta)
	if is_sprite_mode():
		advance_behaviour(delta)
	queue_redraw()


## Called when the player pets the companion (E). Walking (in, out or across
## the deck) it stops for the moment of petting, then walks on.
func pet() -> void:
	_reaction = REACTION_SECONDS
	AudioManager.play_sfx(get_sound())
	if is_walking():
		_walk_pause = REACTION_SECONDS
	if is_sprite_mode():
		# Walking it keeps its walking look (alert) until it arrives; resting,
		# it plays its petting response (the pet clip, else the alert look).
		set_pose(CompanionVisualSet.POSE_ALERT, 60.0 if is_walking() else maxf(visual_set.alert_seconds, REACTION_SECONDS))
	if not stray:
		GameSession.note_companion_petted(kind)
	petted.emit(kind)


## The remark for this petting (in the current language), or "" while the
## last one is recent. Each call that returns a remark moves to the next line.
func take_remark() -> String:
	var now := Time.get_ticks_msec()
	if now - _last_remark_ms < REMARK_COOLDOWN_MS:
		return ""
	_last_remark_ms = now
	_remark_turn += 1
	return CompanionRemarks.remark(CompanionRemarks.identity(get_companion_state()), _remark_turn - 1)


## Lets the next petting have its remark at once (tests).
static func reset_remark_cooldown() -> void:
	_last_remark_ms = Time.get_ticks_msec() - REMARK_COOLDOWN_MS


## The boat became settled at anchor (or stopped being so). Settling shows:
## a stretch, then down for a long nap.
func _on_anchor_life_changed(on: bool) -> void:
	if on == settled:
		return
	settled = on
	settled_changed.emit(on)
	SessionLog.write("companion_settled", {"kind": String(kind), "settled": on, "spot": String(spot)})
	if not is_sprite_mode():
		return
	if on and pose != CompanionVisualSet.POSE_SLEEPING:
		set_pose(CompanionVisualSet.POSE_STRETCHING if _textures.has(CompanionVisualSet.POSE_STRETCHING) else CompanionVisualSet.POSE_SLEEPING)
	elif not on and pose == CompanionVisualSet.POSE_SLEEPING:
		# Something changed (the anchor came up, the wind rose): it wakes.
		set_pose(CompanionVisualSet.POSE_ALERT, visual_set.alert_seconds)


## Preview only: shows the given kind.
func show_kind(companion_kind: StringName) -> void:
	kind = companion_kind
	_load_visuals()
	queue_redraw()


## Its resting spot changed (the schedule, or waking by the berth). In view
## it walks (or flies) there; out of view it is simply there.
func _on_companion_moved(id: int, _spot: StringName) -> void:
	var companion := get_companion_state()
	if companion == null or companion.id != id or is_walking():
		return
	if not on_deck and companion.area == CompanionState.AREA_CABIN and is_visible_in_tree() and is_sprite_mode() \
			and companion.kind == kind and not GameSession.is_asleep() and GameSession.get_time_scale() <= 1:
		spot = companion.spot
		_start_walk(position, _rest_position())
		return
	_sync()


## True when the companion's `area` is shown by this node: the cabin's, or
## the deck's (which also shows it ashore, on the pontoon beside the boat).
func _shows(area: StringName) -> bool:
	return area in [CompanionState.AREA_DECK, CompanionState.AREA_SHORE] if on_deck else area == CompanionState.AREA_CABIN


## Up on deck, down below, ashore, or to another place (Iteration 18, I024).
func _on_area_changed(id: int, area: StringName) -> void:
	var companion := get_companion_state()
	if companion == null or companion.id != id:
		return
	if GameSession.is_asleep():
		_sync()  # it moved while the Captain slept: simply there
		return
	var shown := is_visible_in_tree()
	if _shows(area):
		# Arriving here (or moving to another place here): walk in.
		var target := _rest_position()
		var start := position if shown and not _walking_out else _entry_position()
		visible = true
		_walking_out = false
		_start_walk(start, target)
	elif shown:
		# Leaving this area: walk to the way out, then go.
		_walking_out = true
		_start_walk(position, _entry_position())
	_update_interactable()


func is_walking() -> bool:
	return _walk_index < _walk.size()


## Walks (flies, hops) from where it is to `target`, by the same ways as
## every other walk (I025: the dock animal, the welcome home, pair moments).
func walk_to(target: Vector2) -> void:
	_walking_out = false
	_start_walk(position, target)


## True while the parrot is in the air.
func is_flying() -> bool:
	return _flying


func _is_bird() -> bool:
	return kind == CompanionState.KIND_PARROT


func _start_walk(from: Vector2, to: Vector2) -> void:
	position = from
	_walk = _route(from, to)
	_walk_index = 1
	_walk_delay = 0.0
	_turn_flip_at = -1.0
	_flying = false
	if not is_sprite_mode():
		return
	set_pose(CompanionVisualSet.POSE_ALERT, 60.0)
	var dx := to.x - from.x
	if _is_bird():
		if from.distance_to(to) <= HOP_DISTANCE and has_clip(CompanionVisualSet.POSE_HOP):
			_face(dx)
			_play_clip(CompanionVisualSet.POSE_HOP)
		else:
			_face(dx)
			_flying = true
			_walk = PackedVector2Array([from, to])  # it flies: no path around fittings
			if has_clip(CompanionVisualSet.POSE_TAKEOFF):
				_play_clip(CompanionVisualSet.POSE_TAKEOFF, [CompanionVisualSet.POSE_FLY])
				_walk_delay = clip_length(CompanionVisualSet.POSE_TAKEOFF) * 0.6
			else:
				_play_clip(CompanionVisualSet.POSE_FLY)
		return
	var first := _walk[mini(1, _walk.size() - 1)]
	var turning := absf(first.x - from.x) > 6.0 and signf(first.x - from.x) != facing
	if turning and has_clip(CompanionVisualSet.POSE_TURN):
		# A real turn: the body comes round (the clip faces the viewer at its
		# middle, where the drawing is mirrored), then it walks.
		_play_clip(CompanionVisualSet.POSE_TURN, [CompanionVisualSet.POSE_WALK])
		_walk_delay = clip_length(CompanionVisualSet.POSE_TURN)
		_turn_flip_at = _walk_delay * 0.5
	else:
		_face(first.x - from.x)
		_play_clip(CompanionVisualSet.POSE_WALK if has_clip(CompanionVisualSet.POSE_WALK) else CompanionVisualSet.POSE_ALERT)


## The way from `from` to `to`: on deck around the fittings; ashore down the
## gangplank (and back up); in the cabin straight.
func _route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not on_deck or deck_spots == null:
		return PackedVector2Array([from, to])
	var shore := _shore_access()
	var from_shore := shore != null and shore.is_off_the_boat(from)
	var to_shore := shore != null and shore.is_off_the_boat(to)
	if shore == null or (not from_shore and not to_shore):
		return deck_spots.path(from, to)
	var top := Vector2(shore.get_plank_x(), shore.get_rail_y() - 14.0)
	var bottom := shore.get_landing_point()
	if from_shore and to_shore:
		return PackedVector2Array([from, to])
	var points := PackedVector2Array()
	if to_shore:
		points = deck_spots.path(from, top)
		points.append(bottom)
		points.append(to)
	else:
		points = PackedVector2Array([from, bottom])
		points.append_array(deck_spots.path(top, to))
	return points


func _shore_access() -> ShoreAccess:
	var area := get_parent() as BoatArea
	var shore := area.get_shore_access() if area else null
	return shore if shore and shore.is_valid() and shore.is_active() else null


func _advance_walk(delta: float) -> void:
	if _walk_delay > 0.0:
		_walk_delay -= delta
		if _turn_flip_at >= 0.0 and _clip_time >= _turn_flip_at:
			_turn_flip_at = -1.0
			facing = -facing
		return
	var speed := _walk_speed()
	var step := speed * delta
	var start := _walk[0]
	var end := _walk[_walk.size() - 1]
	while step > 0.0 and is_walking():
		var target := _walk[_walk_index]
		var d := position.distance_to(target)
		_face(target.x - position.x)
		if d <= step:
			position = target
			step -= d
			_walk_index += 1
		else:
			position += (target - position) / d * step
			step = 0.0
	if _flying:
		# Up and over, down again at the end (FLY_HEIGHT at most).
		var rise := minf(position.distance_to(start), position.distance_to(end))
		_lift = minf(FLY_HEIGHT, rise * 0.6)
		if has_clip(CompanionVisualSet.POSE_LAND) and clip != CompanionVisualSet.POSE_LAND \
				and position.distance_to(end) <= speed * clip_length(CompanionVisualSet.POSE_LAND) * 0.8:
			_play_clip(CompanionVisualSet.POSE_LAND)
	update_highlight()
	if is_walking():
		return
	_walk = PackedVector2Array()
	_walk_index = 0
	_lift = 0.0
	_flying = false
	if _walking_out:
		_walking_out = false
		visible = false
	elif is_sprite_mode():
		# Petted on the way: the reaction plays out before it settles.
		if is_reacting():
			set_pose(CompanionVisualSet.POSE_ALERT, _reaction)
		else:
			set_pose(CompanionVisualSet.POSE_RESTING)
	_update_interactable()


func _walk_speed() -> float:
	if visual_set == null:
		return WALK_SPEED * pace
	if _flying:
		return visual_set.fly_speed if visual_set.fly_speed > 0.0 else FLY_SPEED
	if _is_bird():
		# A hop covers its distance in one hop clip.
		var length := maxf(clip_length(CompanionVisualSet.POSE_HOP), 0.3)
		return maxf(HOP_DISTANCE / length, 20.0)
	return (visual_set.walk_speed if visual_set.walk_speed > 0.0 else WALK_SPEED) * pace


## Faces the way of a move along x (small moves keep the facing).
func _face(dx: float) -> void:
	if absf(dx) > 2.0:
		facing = signf(dx)


## Where it comes in and goes out: the companionway.
func _entry_position() -> Vector2:
	if on_deck and deck_spots:
		return deck_spots.get_entry()
	return get_spot_position(&"companionway")


func _rest_position() -> Vector2:
	var companion := get_companion_state()
	if companion == null:
		return position
	if on_deck and companion.area == CompanionState.AREA_SHORE:
		var shore := _shore_access()
		if shore:
			return get_shore_spot(shore, companion.deck_spot)
	if on_deck and deck_spots:
		return deck_spots.get_spot(companion.deck_spot)
	return _paired(get_spot_position(companion.spot), companion)


## The companion this node shows (a copy), or null when its slot is empty.
func get_companion_state() -> CompanionState:
	if stray or preview:
		return null
	var all := GameSession.get_companions()
	return all[slot] if slot < all.size() else null


## The other companion's copy, or null.
func _other_companion() -> CompanionState:
	var all := GameSession.get_companions()
	return all[1 - slot] if all.size() == 2 else null


## A second animal on the same cabin spot lies beside the first, a little
## towards the room (the companionway marker), not on top of it.
func _paired(at: Vector2, companion: CompanionState) -> Vector2:
	var other := _other_companion()
	if slot == 0 or other == null or other.area != CompanionState.AREA_CABIN or other.spot != companion.spot:
		return at
	var toward := get_spot_position(&"companionway") - at
	if toward.length() < 1.0:
		toward = Vector2(1, 0)
	return at + toward.normalized() * PAIR_OFFSET


## Its place `index` on the pontoon (I024): beside the gangplank, on the
## walkable strip, clear of the service stations.
static func get_shore_spot(shore: ShoreAccess, index: int) -> Vector2:
	var strip := shore.get_shore_rect()
	var x := clampf(shore.get_plank_x() + SHORE_OFFSETS[clampi(index, 0, SHORE_OFFSETS.size() - 1)], strip.position.x + 30.0, strip.end.x - 30.0)
	return Vector2(x, strip.position.y + strip.size.y * 0.42)


## Pettable whenever it is shown here, resting or walking (also on its way
## out to follow the captain: it pauses, then goes).
func _update_interactable() -> void:
	if interactable:
		interactable.enabled = visible


func is_reacting() -> bool:
	return _reaction > 0.0


func get_sound() -> AudioStream:
	match kind:
		CompanionState.KIND_DOG:
			return dog_sound
		CompanionState.KIND_PARROT:
			return parrot_sound
	return purr_sound


## True when pose images are shown (false: procedural drawing).
func is_sprite_mode() -> bool:
	return _textures.has(CompanionVisualSet.POSE_RESTING)


## The texture shown for `pose_name` (its first frame; falls back to
## resting), or null.
func get_pose_texture(pose_name: StringName) -> Texture2D:
	return _textures.get(pose_name, _textures.get(CompanionVisualSet.POSE_RESTING))


## True when the art has a clip for `clip_name`.
func has_clip(clip_name: StringName) -> bool:
	return _clips.has(clip_name)


## How long one run of a clip takes (seconds at its own fps).
func clip_length(clip_name: StringName) -> float:
	if not _clips.has(clip_name) or visual_set == null:
		return 0.0
	return (_clips[clip_name] as Array).size() / maxf(float(visual_set.get_clip_settings(clip_name).fps), 0.5)


## The frame of the clip drawn now.
func get_clip_texture() -> Texture2D:
	var frames: Array = _clips.get(clip, _clips.get(CompanionVisualSet.POSE_RESTING, []))
	if frames.is_empty():
		return get_pose_texture(pose)
	var settings := visual_set.get_clip_settings(clip if _clips.has(clip) else CompanionVisualSet.POSE_RESTING)
	var index := int(_clip_time * float(settings.fps))
	if settings.loop:
		index = posmod(index, frames.size())
	else:
		index = mini(index, frames.size() - 1)
	return frames[index]


## Shows `pose_name` for `seconds` (then the idle behaviour continues). A pose
## without an image shows the resting image instead. A short transition clip
## may play first (lying down, waking, settling).
func set_pose(pose_name: StringName, seconds := -1.0) -> void:
	var before := pose
	if pose_name != pose:
		pose = pose_name
		pose_changed.emit(pose)
	_pose_left = seconds if seconds >= 0.0 else _idle_duration(pose_name)
	if pose_name == before and clip != CompanionVisualSet.POSE_WALK:
		return
	if is_walking() and pose_name == CompanionVisualSet.POSE_ALERT and not is_reacting():
		return  # walking: its walk (or flight) clip goes on
	var shown := _pose_clip(pose_name)
	var intro: Array[StringName] = []
	match pose_name:
		CompanionVisualSet.POSE_RESTING:
			if before == CompanionVisualSet.POSE_SLEEPING:
				intro = [CompanionVisualSet.POSE_WAKE]
			elif before in [CompanionVisualSet.POSE_SIT, CompanionVisualSet.POSE_TAIL_WAG] or clip == CompanionVisualSet.POSE_WALK:
				intro = [CompanionVisualSet.POSE_LIE_DOWN]
		CompanionVisualSet.POSE_SLEEPING:
			if settled or spot == CompanionState.WAKE_SPOT:
				intro = [CompanionVisualSet.POSE_SETTLE]
		CompanionVisualSet.POSE_STRETCHING:
			if before == CompanionVisualSet.POSE_SLEEPING:
				intro = [CompanionVisualSet.POSE_WAKE]
	var queue: Array[StringName] = []
	for c in intro:
		if has_clip(c):
			queue.append(c)
	queue.append(shown)
	_play_clip(queue[0], queue.slice(1))
	# A once-clip that is the pose itself (a stretch, a ruffle) is spread over
	# the pose's time, a little slower, rather than ending early.
	if queue.size() == 1 and has_clip(shown) and not bool(visual_set.get_clip_settings(shown).loop) and _pose_left > 0.0:
		_clip_rate = clampf(clip_length(shown) / _pose_left, 0.4, 1.0)
	update_highlight()


## The clip that shows `pose_name`: petted, its petting response.
func _pose_clip(pose_name: StringName) -> StringName:
	if pose_name == CompanionVisualSet.POSE_ALERT and is_reacting() and has_clip(CompanionVisualSet.POSE_PET):
		return CompanionVisualSet.POSE_PET
	return pose_name if has_clip(pose_name) else CompanionVisualSet.POSE_RESTING


## Starts drawing `clip_name` (then the clips in `then`, in order), with a
## short cross-fade from what was drawn.
func _play_clip(clip_name: StringName, then: Array[StringName] = []) -> void:
	if not is_sprite_mode():
		return
	var current := get_clip_texture()
	if clip_name != clip or not then.is_empty():
		_previous_texture = current
		_previous_pose = clip
		_previous_flip = _is_flipped(clip)
		_previous_rect = visual_set.get_draw_rect(clip, current) if current else Rect2()
		_fade = 0.0 if visual_set and visual_set.fade_seconds > 0.0 else 1.0
	clip = clip_name if has_clip(clip_name) else CompanionVisualSet.POSE_RESTING
	_clip_queue = then
	_clip_time = 0.0
	_clip_rate = 1.0


## A response to the Captain's words (I024, CompanionRemarks.response()):
## plays `clip_name` as a short moment, then it carries on. Nothing when it
## is asleep, walking, or has no such clip.
func respond(clip_name: StringName) -> bool:
	if not is_sprite_mode() or is_walking() or pose == CompanionVisualSet.POSE_SLEEPING or clip_name == &"":
		return false
	if clip_name == CompanionVisualSet.POSE_RESTING:
		_play_clip(CompanionVisualSet.POSE_RESTING)
		return true
	if not has_clip(clip_name):
		return false
	var seconds := maxf(clip_length(clip_name), 2.4)
	if clip_name in [CompanionVisualSet.POSE_ALERT, CompanionVisualSet.POSE_PET, CompanionVisualSet.POSE_TAIL_WAG] and not preview:
		AudioManager.play_sfx(get_sound())  # a purr, a pant, a chirp (the parrot never speaks)
	if clip_name == CompanionVisualSet.POSE_ALERT:
		set_pose(CompanionVisualSet.POSE_ALERT, seconds)
	else:
		set_pose(clip_name, seconds)
	return true


## Runs the pose behaviour for `delta` seconds (called every frame; tests
## call it directly to fast-forward).
func advance_behaviour(delta: float) -> void:
	if not is_sprite_mode():
		return
	if visual_set.fade_seconds > 0.0:
		_fade = minf(_fade + delta / visual_set.fade_seconds, 1.0)
	_advance_clip(delta)
	# Looking up when the player comes close (not while napping or reacting).
	var focused := interactable != null and interactable.is_focused()
	if focused and not _was_focused and pose == CompanionVisualSet.POSE_RESTING and not is_walking() \
			and visual_set.approach_alert_cooldown > 0.0 and _time >= _alert_ready_at:
		_alert_ready_at = _time + visual_set.approach_alert_cooldown
		set_pose(CompanionVisualSet.POSE_ALERT, visual_set.alert_seconds * 0.75)
	_was_focused = focused
	# The parrot blinks now and then while it sits (the pose stays resting).
	if pose == CompanionVisualSet.POSE_RESTING and clip == CompanionVisualSet.POSE_RESTING and has_clip(CompanionVisualSet.POSE_BLINK) and not is_walking():
		_blink_left -= delta
		if _blink_left <= 0.0:
			_blink_left = _rng.randf_range(3.0, 8.0)
			_play_clip(CompanionVisualSet.POSE_BLINK, [CompanionVisualSet.POSE_RESTING] as Array[StringName])
			_fade = 1.0
	_pose_left -= delta
	if _pose_left > 0.0 or is_walking():
		return
	if settled and _textures.has(CompanionVisualSet.POSE_SLEEPING) and pose != CompanionVisualSet.POSE_SLEEPING:
		# Settled at anchor: whatever it was doing, back to its nap.
		set_pose(CompanionVisualSet.POSE_SLEEPING)
		return
	match pose:
		CompanionVisualSet.POSE_RESTING:
			var extras := _idle_extras()
			if _rng.randf() < visual_set.sleep_chance and _textures.has(CompanionVisualSet.POSE_SLEEPING):
				set_pose(CompanionVisualSet.POSE_SLEEPING)
			elif not extras.is_empty():
				set_pose(extras[_rng.randi() % extras.size()])
			else:
				set_pose(CompanionVisualSet.POSE_RESTING)
		CompanionVisualSet.POSE_SLEEPING:
			# Waking up: usually a stretch (or, for the bird, a ruffle) first.
			var after := CompanionVisualSet.POSE_RUFFLE if _is_bird() else CompanionVisualSet.POSE_STRETCHING
			if _rng.randf() < 0.5 and _textures.has(after):
				set_pose(after)
			else:
				set_pose(CompanionVisualSet.POSE_RESTING)
		_:
			set_pose(CompanionVisualSet.POSE_RESTING)


## What it does between rests, by kind (only clips the art has). The
## stretch stays in every mammal's list.
func _idle_extras() -> Array[StringName]:
	var wanted: Array[StringName] = []
	match kind:
		CompanionState.KIND_DOG:
			wanted = [CompanionVisualSet.POSE_STRETCHING, CompanionVisualSet.POSE_TAIL_WAG, CompanionVisualSet.POSE_SIT, CompanionVisualSet.POSE_STRETCHING]
		CompanionState.KIND_PARROT:
			wanted = [CompanionVisualSet.POSE_PREEN, CompanionVisualSet.POSE_RUFFLE, CompanionVisualSet.POSE_HEAD_TURN, CompanionVisualSet.POSE_STRETCHING]
		_:
			wanted = [CompanionVisualSet.POSE_STRETCHING, CompanionVisualSet.POSE_GROOM, CompanionVisualSet.POSE_SIT, CompanionVisualSet.POSE_STRETCHING]
	return wanted.filter(func(p: StringName) -> bool: return _textures.has(p))


func _advance_clip(delta: float) -> void:
	_clip_time += delta * _clip_rate * (pace if clip == CompanionVisualSet.POSE_WALK else 1.0)
	if _clip_queue.is_empty() or not has_clip(clip):
		return
	var settings := visual_set.get_clip_settings(clip)
	if not settings.loop and _clip_time >= clip_length(clip):
		var next: StringName = _clip_queue.pop_front()
		var rest := _clip_queue.duplicate()
		_play_clip(next, rest)
		_fade = 1.0  # transitions are drawn to meet: no fade between them


func _idle_duration(pose_name: StringName) -> float:
	if visual_set == null:
		return 1.0
	match pose_name:
		CompanionVisualSet.POSE_SLEEPING:
			return _rng.randf_range(visual_set.sleep_seconds.x, visual_set.sleep_seconds.y) * (SETTLED_SLEEP_FACTOR if settled else 1.0)
		CompanionVisualSet.POSE_STRETCHING, CompanionVisualSet.POSE_RUFFLE, CompanionVisualSet.POSE_HEAD_TURN:
			return maxf(visual_set.stretch_seconds, clip_length(pose_name))
		CompanionVisualSet.POSE_ALERT:
			return visual_set.alert_seconds
		CompanionVisualSet.POSE_GROOM, CompanionVisualSet.POSE_PREEN:
			return _rng.randf_range(4.0, 8.0)
		CompanionVisualSet.POSE_SIT:
			return _rng.randf_range(8.0, 18.0)
		CompanionVisualSet.POSE_TAIL_WAG:
			return _rng.randf_range(2.6, 4.0)
		_:
			return _rng.randf_range(visual_set.rest_seconds.x, visual_set.rest_seconds.y)


## Loads the pose images of the current kind (missing ones are skipped with a
## warning; without a resting image the procedural drawing is used).
func _load_visuals() -> void:
	use_visual_set(CompanionVisualSet.for_kind(kind), false)
	if visual_set and not _textures.has(CompanionVisualSet.POSE_RESTING) and not visual_set.get_pose_names().is_empty():
		push_warning("Companion art '%s' has no usable 'resting' image; using the procedural %s." % [kind, CompanionState.display_name(kind)])
	_rng.seed = hash(String(kind) + String(spot))
	_pose_left = _idle_duration(pose)


## Uses `visual_set_override` instead of the kind's set (tests and tools; a
## null set shows the procedural drawing).
func use_visual_set(visual_set_override: CompanionVisualSet, refresh := true) -> void:
	_textures.clear()
	_clips.clear()
	visual_set = visual_set_override
	if visual_set:
		for pose_name in visual_set.get_pose_names():
			var frames := visual_set.get_frames(pose_name)
			if not frames.is_empty():
				_textures[pose_name] = frames[0]
				_clips[pose_name] = frames
		if not _textures.has(CompanionVisualSet.POSE_RESTING):
			_textures.clear()
			_clips.clear()
	pose = CompanionVisualSet.POSE_RESTING
	clip = CompanionVisualSet.POSE_RESTING
	_clip_queue = []
	_clip_time = 0.0
	_clip_rate = 1.0
	_previous_texture = null
	_fade = 1.0
	_pose_left = _idle_duration(pose)
	_sync_rotation()
	update_highlight()
	if refresh:
		queue_redraw()


## Shows the companion from the session state (kind and resting spot).
func _sync() -> void:
	if stray:
		return
	var companion := get_companion_state()
	if companion == null:
		visible = false
		_walk = PackedVector2Array()
		_walk_index = 0
		_update_interactable()
		return
	visible = true
	if companion.kind != kind or (visual_set == null and _textures.is_empty()):
		kind = companion.kind
		_load_visuals()
	kind = companion.kind
	spot = companion.spot
	visible = _shows(companion.area)
	_walk = PackedVector2Array()
	_walk_index = 0
	_walking_out = false
	_walk_pause = 0.0
	position = _rest_position()
	_sync_rotation()
	update_highlight()
	interactable.prompt = CompanionRemarks.pet_prompt(CompanionRemarks.identity(companion))
	_update_interactable()
	# I025: just adopted - its first minute aboard (once).
	if not on_deck and visible and not companion.welcomed and not _welcoming and is_sprite_mode():
		_welcoming = true
		_welcome.call_deferred()


var _welcoming := false


func _welcome() -> void:
	var area := get_parent() as BoatArea
	var other: ShipCompanion = null
	if area:
		for node in area.get_companion_nodes():
			if node != self:
				other = node
	WelcomeHome.play(self, other)
	_welcoming = false


func _sync_rotation() -> void:
	# The procedural drawing lies in its own (fixed) direction per spot; pose
	# images are drawn upright, never rotated.
	rotation = 0.0 if is_sprite_mode() else deg_to_rad(float(absi(hash(String(spot))) % 360))


# --- Highlight (Iteration 13) ------------------------------------------------------

## How far the glow stands off the animal's outline (scene units).
const HIGHLIGHT_MARGIN := 3.0
## Silhouettes of pose images (texture -> local hull in image pixels).
static var _hulls := {}


## The outline of the animal as drawn now, in this node's coordinates: the
## silhouette of the pose image (its convex hull), or an ellipse around the
## procedural drawing. HighlightResolver reads it through
## get_highlight_outline(); pose changes update the focus glow directly.
func get_local_outline() -> PackedVector2Array:
	if is_sprite_mode():
		var shown: StringName = clip if _clips.has(clip) else CompanionVisualSet.POSE_RESTING
		var texture: Texture2D = _clips[shown][0]
		var rect := visual_set.get_draw_rect(shown, texture)
		rect.position.y -= _lift
		var mirror := _is_flipped(shown)
		var hull := silhouette(texture)
		if hull.size() >= 3:
			var points := PackedVector2Array()
			var size := texture.get_size()
			for p in hull:
				var at := rect.position + p / size * rect.size
				points.append(Vector2(-at.x, at.y) if mirror else at)
			var grown := Geometry2D.offset_polygon(points, HIGHLIGHT_MARGIN, Geometry2D.JOIN_ROUND)
			return grown[0] if not grown.is_empty() else points
		return HighlightResolver.rounded_rect(rect, 10.0)
	var radii := Vector2(38, 18) if kind == CompanionState.KIND_DOG else Vector2(22, 19)
	var centre := Vector2(4, 0) if kind == CompanionState.KIND_DOG else Vector2(2, 1)
	# Local space: the node's rotation turns it with the drawing.
	return _ellipse(centre, radii, 28)


func get_highlight_outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in get_local_outline():
		points.append(to_global(p))
	return points


## Refreshes the focus glow's outline (the pose or the look changed).
func update_highlight() -> void:
	if interactable:
		interactable.set_highlight_outline_global(get_highlight_outline())


## The convex silhouette of a pose image (pixels; opaque parts only, the soft
## shadow left out). Cached per texture.
static func silhouette(texture: Texture2D) -> PackedVector2Array:
	if _hulls.has(texture):
		return _hulls[texture]
	var image := texture.get_image()
	if image == null:
		return PackedVector2Array()
	if image.is_compressed():
		image.decompress()
	var points := PackedVector2Array()
	var step := maxi(1, image.get_width() / 96)
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			if image.get_pixel(x, y).a > 0.6:
				points.append(Vector2(x, y))
	var hull := Geometry2D.convex_hull(points) if points.size() >= 3 else PackedVector2Array()
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	_hulls[texture] = hull
	return hull


## The resting position of `spot_id` in this cabin (its marker), or the
## current position when the cabin has no such marker.
func get_spot_position(spot_id: StringName) -> Vector2:
	var spots := get_node_or_null(spots_path)
	var marker := spots.get_node_or_null(NodePath(String(spot_id))) as Node2D if spots else null
	if marker == null:
		push_warning("ShipCompanion: no resting spot marker '%s'" % spot_id)
		return position
	return marker.position


## Where the current pose image is drawn (local, unmirrored), for tests and tools.
func get_pose_rect(pose_name: StringName = pose) -> Rect2:
	var texture := get_pose_texture(pose_name)
	return visual_set.get_draw_rect(pose_name, texture) if texture and visual_set else Rect2()


func _draw() -> void:
	if is_sprite_mode():
		_draw_pose()
		if is_reacting():
			_draw_hearts()
		return
	# Breathing: a slow, very small swell; a little deeper while reacting.
	var breath := 1.0 + 0.025 * sin(_time * TAU * 0.25) + (0.03 * sin(_time * TAU * 1.8) if is_reacting() else 0.0)
	if kind == CompanionState.KIND_DOG:
		_draw_dog(breath)
	else:
		_draw_cat(breath)
	if is_reacting() and kind == CompanionState.KIND_CAT:
		_draw_hearts()


func _draw_pose() -> void:
	# Breathing lives in the clips now; a still pose (art without frames, e.g.
	# the Captain's own drawing) keeps the very small vertical swell.
	var rate := 0.18 if pose == CompanionVisualSet.POSE_SLEEPING else 0.25
	var still := (_clips.get(clip, []) as Array).size() <= 1
	var swell := 0.012 * sin(_time * TAU * rate) if still else 0.0
	var lift := Vector2(0.0, -_lift)
	if _lift > 0.5:
		# A faint shadow stays on the ground below the flying bird.
		var shadow := visual_set.display_size * 0.16
		draw_colored_polygon(_ellipse(Vector2.ZERO, Vector2(shadow, shadow * 0.4)), Color(0.08, 0.12, 0.14, 0.18 * (1.0 - _lift / (FLY_HEIGHT * 2.0))))
	if _previous_texture and _fade < 1.0:
		var rect := _previous_rect
		rect.position += lift
		_draw_texture_in(_previous_texture, rect, _previous_flip, 1.0 - _fade, swell)
	var texture := get_clip_texture()
	if texture:
		var rect := visual_set.get_draw_rect(clip, texture)
		rect.position += lift
		if clip == CompanionVisualSet.POSE_HOP:
			# The hop is drawn moving forward on its canvas; the node itself
			# carries the bird, so that drift is taken out (no jump back).
			var length := maxf(clip_length(clip), 0.01)
			rect.position.x -= HOP_DRIFT_PX * visual_set.display_size / 256.0 * clampf(_clip_time / length, 0.0, 1.0)
		_draw_texture_in(texture, rect, _is_flipped(clip), _fade if _previous_texture else 1.0, swell)


## Mirrored when it faces left (and when the pose's art says so).
func _is_flipped(clip_name: StringName) -> bool:
	var art := visual_set.get_pose_art(clip_name) if visual_set else null
	return (art != null and art.flip_h) != (facing < 0.0)


func _draw_texture_in(texture: Texture2D, rect: Rect2, flip: bool, alpha: float, swell: float) -> void:
	if texture == null or alpha <= 0.0:
		return
	var bottom := rect.end.y
	rect.size.y *= 1.0 + swell
	rect.position.y = bottom - rect.size.y
	if flip:
		# Mirrored about the ground point (x = 0), so it turns on the spot.
		rect.position.x = -rect.end.x
		rect.position.x += rect.size.x
		rect.size.x = -rect.size.x
	draw_texture_rect(texture, rect, false, Color(1, 1, 1, alpha))


func _draw_cat(breath: float) -> void:
	# Curled up: round body, tail wrapped around, head tucked in.
	var body := _ellipse(Vector2.ZERO, Vector2(17, 14) * breath)
	draw_colored_polygon(_ellipse(Vector2(1, 2), Vector2(18, 15) * breath), OUTLINE)
	draw_colored_polygon(body, CAT_FUR)
	for i in 3:  # stripes
		var x := -8.0 + i * 6.0
		draw_line(Vector2(x, -12 * breath), Vector2(x + 2, -6 * breath), CAT_DARK, 2.0, true)
	var tail := PackedVector2Array()
	for i in 13:
		var a := deg_to_rad(110.0 + i * 13.0)
		tail.append(Vector2(cos(a), sin(a)) * Vector2(19, 16) * breath)
	draw_polyline(tail, CAT_DARK, 5.0, true)
	var head := Vector2(10, 6)
	draw_colored_polygon(_ellipse(head, Vector2(8.5, 8)), CAT_FUR)
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([head + Vector2(3, -6 * side), head + Vector2(10, -6 * side), head + Vector2(6, -11 * side)])
		draw_colored_polygon(ear, CAT_DARK)
	draw_colored_polygon(_ellipse(head + Vector2(4, 0), Vector2(3.5, 3)), CAT_LIGHT)


func _draw_dog(breath: float) -> void:
	# Lying stretched out: long body, head with floppy ears, wagging tail.
	var wag := sin(_time * TAU * (5.0 if is_reacting() else 0.4)) * (0.6 if is_reacting() else 0.12)
	var tail_end := Vector2(-24, 0) + Vector2(-12, 0).rotated(wag)
	draw_line(Vector2(-22, 0), tail_end, DOG_DARK, 5.0, true)
	draw_colored_polygon(_ellipse(Vector2(1, 2), Vector2(25, 15) * breath), OUTLINE)
	draw_colored_polygon(_ellipse(Vector2.ZERO, Vector2(24, 14) * breath), DOG_FUR)
	draw_colored_polygon(_ellipse(Vector2(-4, 0), Vector2(12, 7) * breath), DOG_LIGHT.lerp(DOG_FUR, 0.55))
	for paw in [Vector2(18, -11), Vector2(18, 11)]:
		draw_colored_polygon(_ellipse(paw + Vector2(6, 0), Vector2(6, 3.5)), DOG_FUR)
	var head := Vector2(26, 0)
	draw_colored_polygon(_ellipse(head, Vector2(11, 10)), DOG_FUR)
	draw_colored_polygon(_ellipse(head + Vector2(9, 0), Vector2(6, 5)), DOG_LIGHT)
	draw_circle(head + Vector2(14, 0), 2.2, DOG_DARK)
	var droop := 1.0 + (0.15 * sin(_time * TAU * 3.0) if is_reacting() else 0.0)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(_ellipse(head + Vector2(-3, 9 * side * droop), Vector2(6, 4)), DOG_DARK)


func _draw_hearts() -> void:
	var t := 1.0 - _reaction / REACTION_SECONDS
	for i in 2:
		# Above the head: the procedural cat's, or the top of the pose image.
		var top := get_pose_rect().position.y + 14.0 if is_sprite_mode() else -22.0
		var at := Vector2(8 + i * 12, top - t * 22 - i * 6).rotated(-rotation)
		var alpha := clampf(1.0 - t, 0.0, 1.0)
		var size := 4.0
		draw_circle(at + Vector2(-size * 0.5, 0), size * 0.6, Color(HEART, alpha))
		draw_circle(at + Vector2(size * 0.5, 0), size * 0.6, Color(HEART, alpha))
		draw_colored_polygon(PackedVector2Array([at + Vector2(-size * 1.05, 0.8), at + Vector2(size * 1.05, 0.8), at + Vector2(0, size * 1.4)]),
			Color(HEART, alpha))


static func _ellipse(center: Vector2, radii: Vector2, steps := 20) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points
