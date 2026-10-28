class_name ShipCompanion
extends Node2D
## The ship's cat or dog, resting in the cabin. Presentation only: the kind
## and resting spot come from GameSession (CompanionState), so the companion
## is the same after loading, sleeping or coming back from the deck or chart.
## Exactly one exists, because it is part of the cabin scene.
##
## Where it rests comes from the cabin's layout: the marker named after the
## spot under `spots_path` (Layout/CompanionSpots), so every vessel places its
## own spots. It moves instantly between its resting spots when the schedule
## says so (no walking, no pathfinding, no collision, so it never blocks the
## player).
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
## Iteration 18: the companion can also be on deck (CompanionState.area). The
## deck has its own ShipCompanion (`on_deck`, built by BoatArea) resting at
## the deck's safe places (DeckCompanionSpots); the cabin one shows only while
## the companion is below. When it changes area while you watch, it walks:
## up from the companionway to its place, between places, or back to the
## companionway and below - along paths that stay aboard. Walking is a short
## glide in its alert pose (no pathfinding every frame).

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

## A preview (e.g. in the New Game dialog): just the drawing, no
## interaction and no session state.
@export var preview := false
## The cabin's resting-spot markers (one Marker2D per CompanionState spot id).
@export var spots_path := ^"../Layout/CompanionSpots"

var kind: StringName = CompanionState.DEFAULT_KIND
var spot: StringName = &""
var interactable: Interactable
## The pose images of the current kind (null: procedural drawing).
var visual_set: CompanionVisualSet
## The pose shown now (sprite mode only).
var pose: StringName = CompanionVisualSet.POSE_RESTING

var _textures := {}             # pose -> Texture2D (only poses that loaded)
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
	interactable.interaction_id = &"pet"
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
	set_meta(HighlightResolver.META_FOR, &"pet")
	add_to_group(HighlightResolver.GROUP)
	_sync()
	GameSession.companion_area_changed.connect(_on_area_changed)
	GameSession.companion_moved.connect(_on_companion_moved)
	GameSession.state_replaced.connect(_sync)
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
	AudioManager.play_sfx(purr_sound if kind == CompanionState.KIND_CAT else dog_sound)
	if is_walking():
		_walk_pause = REACTION_SECONDS
	if is_sprite_mode():
		# Walking it keeps its walking look (alert) until it arrives.
		set_pose(CompanionVisualSet.POSE_ALERT, 60.0 if is_walking() else maxf(visual_set.alert_seconds, REACTION_SECONDS))
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
	return CompanionRemarks.remark(CompanionRemarks.identity(GameSession.get_companion()), _remark_turn - 1)


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


func _on_companion_moved(_spot: StringName) -> void:
	if not is_walking():
		_sync()


## Up on deck, down below, or to another place on deck (Iteration 18).
func _on_area_changed(area: StringName) -> void:
	var here := CompanionState.AREA_DECK if on_deck else CompanionState.AREA_CABIN
	var shown := is_visible_in_tree()
	if area == here:
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


func _start_walk(from: Vector2, to: Vector2) -> void:
	position = from
	_walk = deck_spots.path(from, to) if on_deck and deck_spots else PackedVector2Array([from, to])
	_walk_index = 1
	if is_sprite_mode():
		set_pose(CompanionVisualSet.POSE_ALERT, 60.0)


func _advance_walk(delta: float) -> void:
	var step := WALK_SPEED * delta
	while step > 0.0 and is_walking():
		var target := _walk[_walk_index]
		var d := position.distance_to(target)
		if d <= step:
			position = target
			step -= d
			_walk_index += 1
		else:
			position += (target - position) / d * step
			step = 0.0
	update_highlight()
	if is_walking():
		return
	_walk = PackedVector2Array()
	_walk_index = 0
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


## Where it comes in and goes out: the companionway.
func _entry_position() -> Vector2:
	if on_deck and deck_spots:
		return deck_spots.get_entry()
	return get_spot_position(&"companionway")


func _rest_position() -> Vector2:
	var companion := GameSession.get_companion()
	if on_deck and deck_spots:
		return deck_spots.get_spot(companion.deck_spot)
	return get_spot_position(companion.spot)


## Pettable whenever it is shown here, resting or walking (also on its way
## out to follow the captain: it pauses, then goes).
func _update_interactable() -> void:
	if interactable:
		interactable.enabled = visible


func is_reacting() -> bool:
	return _reaction > 0.0


func get_sound() -> AudioStream:
	return purr_sound if kind == CompanionState.KIND_CAT else dog_sound


## True when pose images are shown (false: procedural drawing).
func is_sprite_mode() -> bool:
	return _textures.has(CompanionVisualSet.POSE_RESTING)


## The texture shown for `pose_name` (falls back to resting), or null.
func get_pose_texture(pose_name: StringName) -> Texture2D:
	return _textures.get(pose_name, _textures.get(CompanionVisualSet.POSE_RESTING))


## Shows `pose_name` for `seconds` (then the idle behaviour continues). A pose
## without an image shows the resting image instead.
func set_pose(pose_name: StringName, seconds := -1.0) -> void:
	if pose_name != pose:
		_previous_texture = get_pose_texture(pose)
		_previous_pose = pose
		_fade = 0.0 if visual_set and visual_set.fade_seconds > 0.0 else 1.0
		pose = pose_name
		pose_changed.emit(pose)
		update_highlight()
	_pose_left = seconds if seconds >= 0.0 else _idle_duration(pose_name)


## Runs the pose behaviour for `delta` seconds (called every frame; tests
## call it directly to fast-forward).
func advance_behaviour(delta: float) -> void:
	if not is_sprite_mode():
		return
	if visual_set.fade_seconds > 0.0:
		_fade = minf(_fade + delta / visual_set.fade_seconds, 1.0)
	# Looking up when the player comes close (not while napping or reacting).
	var focused := interactable != null and interactable.is_focused()
	if focused and not _was_focused and pose == CompanionVisualSet.POSE_RESTING \
			and visual_set.approach_alert_cooldown > 0.0 and _time >= _alert_ready_at:
		_alert_ready_at = _time + visual_set.approach_alert_cooldown
		set_pose(CompanionVisualSet.POSE_ALERT, visual_set.alert_seconds * 0.75)
	_was_focused = focused
	_pose_left -= delta
	if _pose_left > 0.0:
		return
	if settled and _textures.has(CompanionVisualSet.POSE_SLEEPING) and pose != CompanionVisualSet.POSE_SLEEPING:
		# Settled at anchor: whatever it was doing, back to its nap.
		set_pose(CompanionVisualSet.POSE_SLEEPING)
		return
	match pose:
		CompanionVisualSet.POSE_RESTING:
			if _rng.randf() < visual_set.sleep_chance and _textures.has(CompanionVisualSet.POSE_SLEEPING):
				set_pose(CompanionVisualSet.POSE_SLEEPING)
			elif _textures.has(CompanionVisualSet.POSE_STRETCHING):
				set_pose(CompanionVisualSet.POSE_STRETCHING)
			else:
				set_pose(CompanionVisualSet.POSE_RESTING)
		CompanionVisualSet.POSE_SLEEPING:
			# Waking up: usually a stretch first.
			if _rng.randf() < 0.5 and _textures.has(CompanionVisualSet.POSE_STRETCHING):
				set_pose(CompanionVisualSet.POSE_STRETCHING)
			else:
				set_pose(CompanionVisualSet.POSE_RESTING)
		_:
			set_pose(CompanionVisualSet.POSE_RESTING)


func _idle_duration(pose_name: StringName) -> float:
	if visual_set == null:
		return 1.0
	match pose_name:
		CompanionVisualSet.POSE_SLEEPING:
			return _rng.randf_range(visual_set.sleep_seconds.x, visual_set.sleep_seconds.y) * (SETTLED_SLEEP_FACTOR if settled else 1.0)
		CompanionVisualSet.POSE_STRETCHING:
			return visual_set.stretch_seconds
		CompanionVisualSet.POSE_ALERT:
			return visual_set.alert_seconds
		_:
			return _rng.randf_range(visual_set.rest_seconds.x, visual_set.rest_seconds.y)


## Loads the pose images of the current kind (missing ones are skipped with a
## warning; without a resting image the procedural drawing is used).
func _load_visuals() -> void:
	_textures.clear()
	visual_set = CompanionVisualSet.for_kind(kind)
	if visual_set == null:
		return
	for pose_name in visual_set.get_pose_names():
		var texture := visual_set.get_texture(pose_name)
		if texture:
			_textures[pose_name] = texture
	if not _textures.has(CompanionVisualSet.POSE_RESTING):
		if not visual_set.get_pose_names().is_empty():
			push_warning("Companion art '%s' has no usable 'resting' image; using the procedural %s." % [kind, CompanionState.display_name(kind)])
		_textures.clear()
		return
	_rng.seed = hash(String(kind) + String(spot))
	_previous_texture = null
	_fade = 1.0
	pose = CompanionVisualSet.POSE_RESTING
	_pose_left = _idle_duration(pose)
	update_highlight()


## Uses `visual_set_override` instead of the kind's set (tests and tools; a
## null set shows the procedural drawing).
func use_visual_set(visual_set_override: CompanionVisualSet) -> void:
	_textures.clear()
	visual_set = visual_set_override
	if visual_set:
		for pose_name in visual_set.get_pose_names():
			var texture := visual_set.get_texture(pose_name)
			if texture:
				_textures[pose_name] = texture
		if not _textures.has(CompanionVisualSet.POSE_RESTING):
			_textures.clear()
	pose = CompanionVisualSet.POSE_RESTING
	_previous_texture = null
	_fade = 1.0
	_pose_left = _idle_duration(pose)
	_sync_rotation()
	update_highlight()
	queue_redraw()


## Shows the companion from the session state (kind and resting spot).
func _sync() -> void:
	var companion := GameSession.get_companion()
	if companion == null:
		visible = false
		return
	visible = true
	if companion.kind != kind or (visual_set == null and _textures.is_empty()):
		kind = companion.kind
		_load_visuals()
	kind = companion.kind
	spot = companion.spot
	var here := CompanionState.AREA_DECK if on_deck else CompanionState.AREA_CABIN
	visible = companion.area == here
	_walk = PackedVector2Array()
	_walk_index = 0
	_walking_out = false
	_walk_pause = 0.0
	position = _rest_position()
	_sync_rotation()
	update_highlight()
	interactable.prompt = Loc.t("Pet %s") % CompanionState.display_name(kind)
	_update_interactable()


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
		var texture := get_pose_texture(pose)
		var rect := visual_set.get_draw_rect(pose, texture)
		var hull := silhouette(texture)
		if hull.size() >= 3:
			var points := PackedVector2Array()
			var size := texture.get_size()
			for p in hull:
				points.append(rect.position + p / size * rect.size)
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


## Where the current pose image is drawn (local), for tests and tools.
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
	# Breathing: a very small vertical swell from the bottom (slower asleep).
	var rate := 0.18 if pose == CompanionVisualSet.POSE_SLEEPING else 0.25
	var swell := 0.012 * sin(_time * TAU * rate)
	if _previous_texture and _fade < 1.0:
		_draw_pose_texture(_previous_pose, _previous_texture, 1.0 - _fade, swell)
	_draw_pose_texture(pose, get_pose_texture(pose), _fade if _previous_texture else 1.0, swell)


func _draw_pose_texture(pose_name: StringName, texture: Texture2D, alpha: float, swell: float) -> void:
	if texture == null or alpha <= 0.0:
		return
	var rect := visual_set.get_draw_rect(pose_name, texture)
	var bottom := rect.end.y
	rect.size.y *= 1.0 + swell
	rect.position.y = bottom - rect.size.y
	var art := visual_set.get_pose_art(pose_name)
	if art and art.flip_h:
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
