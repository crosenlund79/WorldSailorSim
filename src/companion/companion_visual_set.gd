class_name CompanionVisualSet
extends Resource
## The artwork of one companion kind (cat, dog, ...): its poses and how they
## are placed. Pure data, edited in the inspector or as a .tres file, so the
## art can be replaced or extended without touching any script. See
## DEV_GUIDES/COMPANION_ANIMATION.md.
##
## Placement: every pose image is treated as the same logical canvas. Its
## longer side is drawn `display_size` scene units long, and the point
## `pivot` (0..1 of the image, (0.5, 0.5) = centre) sits on the companion's
## resting marker. Drawing all poses on the same canvas (same size, animal in
## the same place) is therefore enough for them to line up; per-pose `offset`
## and `scale` in CompanionPoseArt correct exceptions.
##
## Images with transparency are used as they are. Opaque images (no alpha,
## e.g. drawn on white paper) get their background removed when loaded: the
## colour of the corners is made transparent wherever it touches the image
## border, so enclosed white areas (a white chest) stay. The source files are
## never modified.

## Where the set for each kind lives: res://data/companions/<kind>_visuals.tres.
## A kind without a set keeps its procedural drawing (since I024 every kind
## has one: the cat, the dog and the parrot, each with animated clips).
const PATH_PATTERN := "res://data/companions/%s_visuals.tres"
const POSE_RESTING := &"resting"
const POSE_SLEEPING := &"sleeping"
const POSE_ALERT := &"alert"
const POSE_STRETCHING := &"stretching"
## I024 clips (a set may have any of them; missing ones are simply not played).
const POSE_WALK := &"walk"
const POSE_TURN := &"turn"
const POSE_SIT := &"sit"
const POSE_LIE_DOWN := &"lie_down"
const POSE_WAKE := &"wake"
const POSE_GROOM := &"groom"
const POSE_PET := &"pet"
const POSE_SETTLE := &"settle"
const POSE_TAIL_WAG := &"tail_wag"
const POSE_BLINK := &"blink"
const POSE_HEAD_TURN := &"head_turn"
const POSE_HOP := &"hop"
const POSE_TAKEOFF := &"takeoff"
const POSE_FLY := &"fly"
const POSE_LAND := &"land"
const POSE_RUFFLE := &"ruffle"
const POSE_PREEN := &"preen"

@export var kind: StringName
## Sprite Workshop id prefix for this companion's poses (0.105b): a valid PNG
## for "<workshop_id>.<pose>" in art_replacements is used instead of the pose's
## own image (e.g. pet.snovs.resting). Empty: no replacements.
@export var workshop_id := ""
@export var poses: Array[CompanionPoseArt] = []

@export_group("Placement")
## Length in scene units of an image's longer side (the player is 40 across).
@export_range(8.0, 400.0, 1.0) var display_size := 72.0
## Point of the image (0..1) placed on the resting marker.
@export var pivot := Vector2(0.5, 0.5)

@export_group("Loading")
## Remove a plain background from opaque images (see above).
@export var remove_background := true
## How different from the corner colour a pixel may be and still count as
## background (0..1, RGB distance).
@export_range(0.0, 0.5, 0.01) var background_tolerance := 0.12
## Images are scaled down to at most this many pixels on their longer side
## when loaded (the companion is small on screen; this saves memory).
@export_range(32, 2048, 1) var max_texture_size := 320

@export_group("Movement")
## Walking speed in scene units per second, matched to the walk clip's stride
## so the feet do not slide (0: the game's default).
@export_range(0.0, 200.0, 0.5) var walk_speed := 0.0
## Flying speed (birds), scene units per second.
@export_range(0.0, 400.0, 1.0) var fly_speed := 0.0

@export_group("Behaviour")
## Seconds (real time, min..max) spent resting between idle changes.
@export var rest_seconds := Vector2(25.0, 60.0)
## Seconds (min..max) a nap on its back lasts.
@export var sleep_seconds := Vector2(60.0, 150.0)
## Chance that a rest is followed by a nap (otherwise a stretch).
@export_range(0.0, 1.0, 0.05) var sleep_chance := 0.6
@export var stretch_seconds := 2.6
## How long the alert pose shows after petting.
@export var alert_seconds := 2.0
## When the player comes close to a resting companion it looks up briefly,
## at most this often (seconds). 0 disables it.
@export var approach_alert_cooldown := 20.0
## Cross-fade between poses.
@export var fade_seconds := 0.25

static var _cache := {}


## The set for a companion kind, or null when it has none.
static func for_kind(companion_kind: StringName) -> CompanionVisualSet:
	var path := PATH_PATTERN % companion_kind
	return load(path) as CompanionVisualSet if ResourceLoader.exists(path) else null


## Forgets loaded images (after art files changed while running, and in tests).
static func clear_cache() -> void:
	_cache.clear()


func get_pose_art(pose: StringName) -> CompanionPoseArt:
	for art in poses:
		if art and art.pose == pose:
			return art
	return null


func get_pose_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for art in poses:
		if art:
			names.append(art.pose)
	return names


## The prepared texture of `pose` (its first frame), or null when its image
## is missing or unreadable (a warning names the file).
func get_texture(pose: StringName) -> Texture2D:
	var art := get_pose_art(pose)
	if art == null or art.image_path.is_empty():
		return null
	var replacement := _workshop_texture(pose)
	if replacement:
		return replacement
	return _texture_for_path(art.image_path, pose)


## Every frame of `pose`'s clip (I024), frame 0 first: [] when its first
## image is missing; a frame that is missing is left out (with a warning).
## A Sprite Workshop replacement replaces the whole clip with its one image.
func get_frames(pose: StringName) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var first := get_texture(pose)
	if first == null:
		return out
	out.append(first)
	if _workshop_texture(pose):
		return out
	var art := get_pose_art(pose)
	for path in art.frames:
		var texture := _texture_for_path(path, pose)
		if texture:
			out.append(texture)
	return out


## The pose's own clip settings: {"fps", "loop"}.
func get_clip_settings(pose: StringName) -> Dictionary:
	var art := get_pose_art(pose)
	return {"fps": art.fps if art else 8.0, "loop": art.loop if art else true}


func _workshop_texture(pose: StringName) -> Texture2D:
	if workshop_id == "":
		return null
	var replacement := ArtworkResolver.get_artwork(StringName("%s.%s" % [workshop_id, pose]))
	if replacement == null:
		return null
	var replaced_key := "workshop|%s.%s" % [workshop_id, pose]
	if not _cache.has(replaced_key):
		_cache[replaced_key] = ImageTexture.create_from_image(prepare_image(replacement.get_image()))
	return _cache[replaced_key]


func _texture_for_path(path: String, pose: StringName) -> Texture2D:
	var key := "%s|%d|%s|%.3f" % [path, max_texture_size, remove_background, background_tolerance]
	if _cache.has(key):
		return _cache[key]
	var image := _read_image(path)
	var texture: Texture2D = null
	if image == null:
		push_warning("Companion art '%s': pose '%s' image %s is missing or unreadable; that pose falls back." % [kind, pose, path])
	else:
		texture = ImageTexture.create_from_image(prepare_image(image))
	_cache[key] = texture
	return texture


## Size in scene units and top-left corner (relative to the resting marker)
## at which `texture` of `pose` is drawn.
func get_draw_rect(pose: StringName, texture: Texture2D) -> Rect2:
	var art := get_pose_art(pose)
	var image_size := texture.get_size()
	var factor := display_size / maxf(image_size.x, image_size.y) * (art.scale if art else 1.0)
	var size := image_size * factor
	return Rect2(-pivot * size + (art.offset if art else Vector2.ZERO), size)


## Scales the image down and, for opaque images, removes the background.
func prepare_image(source: Image) -> Image:
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > max_texture_size:
		var factor := float(max_texture_size) / longest
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	if remove_background and not has_transparent_border(image):
		_remove_border_background(image)
	return image


## True when the image already has transparency along its border.
static func has_transparent_border(image: Image) -> bool:
	var w := image.get_width()
	var h := image.get_height()
	for i in range(0, maxi(w, h), 4):
		for p in [Vector2i(mini(i, w - 1), 0), Vector2i(mini(i, w - 1), h - 1), Vector2i(0, mini(i, h - 1)), Vector2i(w - 1, mini(i, h - 1))]:
			if image.get_pixelv(p).a < 0.5:
				return true
	return false


static func _read_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		return texture.get_image() if texture else null
	if FileAccess.file_exists(path):
		# Not imported by Godot (e.g. a file outside the project): works while
		# developing, but such a file is not part of an exported game.
		push_warning("Companion art %s is not an imported resource; it is read directly." % path)
		var image := Image.load_from_file(path)
		return image if image and not image.is_empty() else null
	return null


## Flood fill from the border: pixels close to the corner colour become
## transparent; the anti-aliased rim next to them becomes partly transparent.
func _remove_border_background(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var data := image.get_data()
	var corners := [0, w - 1, (h - 1) * w, (h - 1) * w + w - 1]
	var background := Vector3.ZERO
	for c in corners:
		background += Vector3(data[c * 4], data[c * 4 + 1], data[c * 4 + 2]) / 255.0
	background /= 4.0
	var bg := background * 255.0
	# RGB distance to the background, 0..1 (inlined below for speed).
	var limit := background_tolerance * 255.0 * sqrt(3.0)
	var removed := PackedByteArray()
	removed.resize(w * h)
	var queue := PackedInt32Array()
	for x in w:
		queue.append(x)
		queue.append((h - 1) * w + x)
	for y in h:
		queue.append(y * w)
		queue.append(y * w + w - 1)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		if removed[index] != 0:
			continue
		var o := index * 4
		var dr := data[o] - bg.x
		var dg := data[o + 1] - bg.y
		var db := data[o + 2] - bg.z
		if dr * dr + dg * dg + db * db > limit * limit:
			continue
		removed[index] = 1
		data[index * 4 + 3] = 0
		var x := index % w
		var y := index / w
		if x > 0:
			queue.append(index - 1)
		if x < w - 1:
			queue.append(index + 1)
		if y > 0:
			queue.append(index - w)
		if y < h - 1:
			queue.append(index + w)
	# Soften the rim: kept pixels touching removed ones fade with their
	# similarity to the background (removes the light halo).
	var rim := background_tolerance * 3.0
	for index in w * h:
		if removed[index] != 0:
			continue
		var x := index % w
		var y := index / w
		var touches := (x > 0 and removed[index - 1] != 0) or (x < w - 1 and removed[index + 1] != 0) \
			or (y > 0 and removed[index - w] != 0) or (y < h - 1 and removed[index + w] != 0)
		if touches:
			var o := index * 4
			var d := Vector3(data[o], data[o + 1], data[o + 2]).distance_to(bg) / 255.0 / sqrt(3.0)
			data[index * 4 + 3] = clampi(roundi(255.0 * clampf((d - background_tolerance) / (rim - background_tolerance), 0.0, 1.0)), 0, 255)
	image.set_data(w, h, false, Image.FORMAT_RGBA8, data)
