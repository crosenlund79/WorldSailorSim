extends RefCounted
## Iteration 004b: the cat's artwork as poses; since Iteration 13 the cat and
## the dog are new illustrated art in the game's style
## (tools/companions/paint_companions.py), and the owner's original cat
## drawings stay in Visuals/Cat/, unchanged. The files and their mapping,
## background removal (checked on the owner's opaque drawings), consistent
## placement, the pose behaviour, petting, fallbacks, replacing a pose image
## through data only, all the vessels, the dog, and persistence.

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")
const CAT_FILES := {
	&"resting": "res://assets/companions/cat/resting.png",
	&"sleeping": "res://assets/companions/cat/sleeping.png",
	&"alert": "res://assets/companions/cat/alert.png",
	&"stretching": "res://assets/companions/cat/stretching.png",
}
const DOG_FILES := {
	&"resting": "res://assets/companions/dog/resting.png",
	&"sleeping": "res://assets/companions/dog/sleeping.png",
	&"alert": "res://assets/companions/dog/alert.png",
	&"stretching": "res://assets/companions/dog/stretching.png",
}
## The owner's original drawings (kept, never modified) and their checksums.
const OWNER_FILES := {
	&"resting": "res://Visuals/Cat/Cat_resting.png",
	&"sleeping": "res://Visuals/Cat/Cat_SleepingBack.png",
	&"alert": "res://Visuals/Cat/Cat_alert.png",
	&"stretching": "res://Visuals/Cat/Cat_stretching.png",
}
const OWNER_MD5 := {
	&"resting": "0bb77ddaeca77b6e958e63e4ead8d494",
	&"sleeping": "687e62a876079c3fa7ee86d10b191974",
	&"alert": "70f0c3b5091153c614202b4a9dc2e6c2",
	&"stretching": "550e3c3d7f6b61521c87c4a3dee3387d",
}
const REPLACEMENT_DIR := "user://test_companion_art"

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	CompanionVisualSet.clear_cache()
	_test_files_and_mapping()
	_test_background_removal()
	_test_consistent_placement()

	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	Simulation.auto_advance = false
	await _test_new_game_preview()
	await _test_poses_in_cabin()
	await _test_behaviour()
	await _test_approach_and_petting()
	await _test_fallbacks()
	await _test_replacement_workflow()
	await _test_all_vessels()
	await _test_persistence()
	await _test_dog()

	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	CompanionVisualSet.clear_cache()


# --- Files, mapping, image preparation ------------------------------------------------

func _test_files_and_mapping() -> void:
	for pose: StringName in CAT_FILES:
		var path: String = CAT_FILES[pose]
		t.check(FileAccess.file_exists(path) and ResourceLoader.exists(path), "[cat art] %s is in the project and imported" % path)
	var set := CompanionVisualSet.for_kind(&"cat")
	if not t.check(set != null, "[cat art] data/companions/cat_visuals.tres loads"):
		return
	# I024: animated clips; each pose's first frame is <pose>_00.png (the old
	# single files are kept beside them as copies of that frame).
	var names := set.get_pose_names()
	t.check([&"resting", &"sleeping", &"alert", &"stretching"].all(func(p: StringName) -> bool: return p in names) and names.size() >= 10,
		"[cat art] the four classic poses and more clips mapped (%d)" % names.size())
	for pose: StringName in CAT_FILES:
		var art := set.get_pose_art(pose)
		var first := String(CAT_FILES[pose]).replace(".png", "_00.png")
		t.check(art != null and art.image_path == first and art.frames.size() >= 3, "[cat art] '%s' is a clip starting with %s" % [pose, first.get_file()])
		var texture := set.get_texture(pose)
		t.check(texture != null and texture.get_width() <= set.max_texture_size and texture.get_width() >= 200,
			"[cat art] '%s' loads (%s)" % [pose, texture.get_size() if texture else "missing"])
	for pose: StringName in OWNER_FILES:
		t.check(FileAccess.get_md5(OWNER_FILES[pose]) == OWNER_MD5[pose], "[cat art] the owner's original %s is kept, unchanged" % String(OWNER_FILES[pose]).get_file())
	var dog := CompanionVisualSet.for_kind(&"dog")
	if t.check(dog != null and [&"resting", &"sleeping", &"alert", &"stretching"].all(func(p: StringName) -> bool: return p in dog.get_pose_names()),
			"[dog art] data/companions/dog_visuals.tres: the dog's poses"):
		for pose: StringName in DOG_FILES:
			var first := String(DOG_FILES[pose]).replace(".png", "_00.png")
			t.check(dog.get_pose_art(pose).image_path == first and dog.get_texture(pose) != null, "[dog art] '%s' starts with %s" % [pose, first.get_file()])


func _test_background_removal() -> void:
	# On the owner's drawings (opaque, on white paper): a copy of the set that
	# points at them.
	var set := CompanionVisualSet.for_kind(&"cat").duplicate(true) as CompanionVisualSet
	for pose: StringName in OWNER_FILES:
		set.get_pose_art(pose).image_path = OWNER_FILES[pose]
	for pose: StringName in OWNER_FILES:
		var image := set.get_texture(pose).get_image()
		var w := image.get_width()
		var corners_clear := image.get_pixel(0, 0).a < 0.05 and image.get_pixel(w - 1, w - 1).a < 0.05
		var white_kept := 0
		var opaque := 0
		for y in range(0, w, 2):
			for x in range(0, w, 2):
				var c := image.get_pixel(x, y)
				if c.a > 0.95:
					opaque += 1
					if c.get_luminance() > 0.92:
						white_kept += 1
		t.check(corners_clear and opaque > 2000, "[cat art] '%s': the white paper background is removed, the cat stays (%d px)" % [pose, opaque])
		t.check(white_kept > 40, "[cat art] '%s': the white fur inside the outline is kept (%d px)" % [pose, white_kept])
	# A synthetic check: white paper, a closed black ring, white inside.
	var paper := Image.create(64, 64, false, Image.FORMAT_RGB8)
	paper.fill(Color.WHITE)
	for a in 360:
		for r in [18.0, 19.0, 20.0]:
			paper.set_pixelv(Vector2i(32, 32) + Vector2i(Vector2.from_angle(deg_to_rad(a)) * r), Color.BLACK)
	var prepared := set.prepare_image(paper)
	t.check(prepared.get_pixel(2, 2).a == 0.0 and prepared.get_pixel(32, 32).a == 1.0 and prepared.get_pixel(32, 32).get_luminance() > 0.99,
		"[cat art] background removal keeps enclosed white and clears the outside")
	var clear := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	clear.fill(Color(1, 1, 1, 0))
	clear.fill_rect(Rect2i(8, 8, 16, 16), Color(1, 1, 1, 1))
	t.check(set.prepare_image(clear).get_pixel(16, 16) == Color(1, 1, 1, 1), "[cat art] images with transparency are used unchanged")


func _test_consistent_placement() -> void:
	var set := CompanionVisualSet.for_kind(&"cat")
	var first := Rect2()
	var same := true
	for pose: StringName in CAT_FILES:
		var rect := set.get_draw_rect(pose, set.get_texture(pose))
		if first == Rect2():
			first = rect
		same = same and rect.is_equal_approx(first)
	t.check(same, "[cat art] all four poses share the same logical size and position %s" % first)
	# I024: the pivot is the animal's ground point (where it rests), not the canvas centre.
	var ground := first.position + set.pivot * first.size
	t.check(is_equal_approx(maxf(first.size.x, first.size.y), set.display_size) and ground.is_zero_approx(),
		"[cat art] %d units, its ground point on the resting spot" % set.display_size)


# --- In the game ----------------------------------------------------------------------

func _test_new_game_preview() -> void:
	# I025: New Game no longer previews a companion (one is found along the
	# way); the art below is tested on a game started with the cat.
	await t.click(app.router.current_screen.find_child("NewGameButton", true, false) as Button)
	var menu := app.modals.get_top() as NewGameMenu
	t.check(menu != null and menu.find_child("Preview", true, false) == null, "[new game] no companion preview (I025)")
	app.modals.clear()
	app.start_new_game(CompanionState.KIND_CAT)
	await _settle()


func _companion() -> ShipCompanion:
	var area := app.router.current_screen as Node
	return area.find_child("Companion", true, false) as ShipCompanion if area else null


func _test_poses_in_cabin() -> void:
	var cat := _companion()
	if not t.check(cat != null and cat.is_sprite_mode(), "[cat art] the cat in the cabin shows its illustrated artwork"):
		return
	t.check(cat.pose == &"resting" and cat.rotation == 0.0, "[cat art] it starts resting, upright (never rotated)")
	var camera := (app.router.current_screen as Node).get_node("Camera2D") as Camera2D
	var camera_position := camera.position
	var camera_zoom := camera.zoom
	camera.position = cat.position
	camera.zoom = Vector2(3.5, 3.5)
	for pose: StringName in CAT_FILES:
		cat.set_pose(pose, 999.0)
		cat.advance_behaviour(1.0)  # finish the cross-fade
		t.check(cat.pose == pose and cat.get_pose_texture(pose) == CompanionVisualSet.for_kind(&"cat").get_texture(pose),
			"[cat art] '%s' shows %s" % [pose, String(CAT_FILES[pose]).get_file()])
		await t.frames(2)
		await t.screenshot("54_cat_pose_%s" % pose)
	camera.position = camera_position
	camera.zoom = camera_zoom
	cat.set_pose(&"resting")


func _test_behaviour() -> void:
	var cat := _companion()
	var set := cat.visual_set
	cat.set_pose(&"resting")
	var changes: Array = []
	var seen := {}
	var held := 0.0
	var shortest := INF
	var on_change := func(p: StringName) -> void:
		changes.append(p)
	cat.pose_changed.connect(on_change)
	var step := 0.1
	var last := cat.pose
	for i in int(30.0 * 60.0 / step):  # 30 minutes
		cat.advance_behaviour(step)
		held += step
		if cat.pose != last:
			if last != &"alert":
				shortest = minf(shortest, held)
			held = 0.0
			last = cat.pose
			seen[last] = true
	cat.pose_changed.disconnect(on_change)
	t.check(seen.has(&"sleeping") and seen.has(&"stretching") and seen.has(&"resting"), "[cat art] over 30 minutes it rests, naps and stretches (%s)" % [seen.keys()])
	t.check(changes.size() >= 10 and changes.size() <= 120, "[cat art] pose changes are occasional (%d in 30 min)" % changes.size())
	t.check(shortest >= set.stretch_seconds - 0.15, "[cat art] no flickering: each pose holds at least %.1f s (shortest %.1f s)" % [set.stretch_seconds, shortest])
	cat.set_pose(&"resting")


func _test_approach_and_petting() -> void:
	var area := app.router.current_screen as BoatArea
	var cat := _companion()
	cat.set_pose(&"resting", 999.0)
	cat._alert_ready_at = 0.0
	var cells := W.walkable_cells(area, area.get_spawn_position(&"start"))
	var near := W.nearest(cells, cat.position)
	area.player.position = area.get_spawn_position(&"start")
	await t.physics_frames(3)
	app.toasts.clear()
	await t.frames(2)
	await t.screenshot("13_companion_cat")
	area.player.position = near
	await t.physics_frames(3)
	await t.frames(2)
	t.check(area.player.get_focused_interactable() == cat.interactable, "[cat art] the cat can be reached")
	t.check_eq(cat.pose, &"alert", "[cat art] walking up to the resting cat makes it look up")
	# Iteration 13: focused, the cat glows around its own outline, like the
	# stations: no tint and no circle, and the focus rules are unchanged.
	t.check(cat.interactable.highlight_target.is_empty() and cat.modulate == Color.WHITE and cat.interactable.highlight_outline.size() >= 6,
		"[highlight] the focused cat glows around its silhouette (%d points), untinted" % cat.interactable.highlight_outline.size())
	t.check_eq(cat.interactable.focus_priority, -1, "[highlight] stations nearby keep precedence over the cat")
	var bounds := Rect2(cat.interactable.highlight_outline[0], Vector2.ZERO)
	for p in cat.interactable.highlight_outline:
		bounds = bounds.expand(p)
	var drawn := cat.get_pose_rect()
	t.check(bounds.size.x < drawn.size.x + 10.0 and bounds.size.y < drawn.size.y + 10.0 and bounds.size.x > drawn.size.x * 0.4,
		"[highlight] the outline hugs the drawn cat (%s inside %s)" % [bounds.size.round(), drawn.size.round()])
	await t.get_tree().create_timer(0.7).timeout
	await t.screenshot("13_companion_cat_highlighted")
	await t.wait_until(func() -> bool: return cat.pose == &"resting", 4.0)
	t.check_eq(cat.pose, &"resting", "[cat art] and it settles again")
	# Petting (one press of E): alert + hearts + purr, then back to resting.
	await t.press_action(&"interact")
	t.check(cat.is_reacting() and cat.pose == &"alert", "[cat art] petting shows the alert pose with hearts")
	t.check(_sfx_player_with(cat.purr_sound) != null, "[cat art] the purr plays on the SFX bus")
	await t.screenshot("55_cat_petted")
	await t.wait_until(func() -> bool: return cat.pose == &"resting" and not cat.is_reacting(), 5.0)
	t.check(cat.pose == &"resting" and not cat.is_reacting(), "[cat art] it returns to resting by itself")
	# A sleeping cat is not woken by walking past, only by petting.
	area.player.position = area.get_spawn_position(&"start")
	await t.physics_frames(3)
	cat.set_pose(&"sleeping", 999.0)
	cat._alert_ready_at = 0.0
	area.player.position = near
	await t.physics_frames(3)
	await t.frames(2)
	t.check_eq(cat.pose, &"sleeping", "[cat art] walking past does not wake a sleeping cat")
	await t.press_action(&"interact")
	t.check_eq(cat.pose, &"alert", "[cat art] petting wakes it")
	await t.wait_until(func() -> bool: return cat.pose == &"resting", 5.0)


func _test_fallbacks() -> void:
	var cat := _companion()
	var original := cat.visual_set
	# One pose missing: it falls back to the resting image; nothing breaks.
	var partial := original.duplicate(true) as CompanionVisualSet
	partial.get_pose_art(&"alert").image_path = "res://Visuals/Cat/Cat_missing_alert.png"
	cat.use_visual_set(partial)
	t.check(cat.is_sprite_mode() and cat.get_pose_texture(&"alert") == cat.get_pose_texture(&"resting"),
		"[cat art] a missing pose image falls back to the resting image")
	cat.pet()
	t.check(cat.is_reacting(), "[cat art] petting still works without an alert image")
	# Resting missing: the procedural cat.
	var broken := original.duplicate(true) as CompanionVisualSet
	broken.get_pose_art(&"resting").image_path = "res://Visuals/Cat/does_not_exist.png"
	cat.use_visual_set(broken)
	await t.frames(2)
	t.check(not cat.is_sprite_mode() and cat.visible, "[cat art] without a resting image the procedural cat is shown")
	cat.pet()
	t.check(cat.is_reacting(), "[cat art] and it can still be petted")
	await t.screenshot("56_cat_fallback_procedural")
	cat.use_visual_set(null)
	t.check(not cat.is_sprite_mode(), "[cat art] no set at all: procedural, no error")
	cat.use_visual_set(original)
	t.check(cat.is_sprite_mode(), "[cat art] back to the artwork")


## Replacing a pose image only through files and data: a new PNG for the
## resting pose, written next to the test saves (the owner's files are never
## touched), selected in a copy of the pose set. No script changes.
func _test_replacement_workflow() -> void:
	var cat := _companion()
	var originals := {}
	for pose: StringName in CAT_FILES:
		originals[pose] = FileAccess.get_md5(CAT_FILES[pose])
	DirAccess.make_dir_recursive_absolute(REPLACEMENT_DIR)
	var drawing := Image.create(400, 400, false, Image.FORMAT_RGB8)
	drawing.fill(Color.WHITE)
	for y in 400:
		for x in 400:
			var d := Vector2(x - 200, y - 220).length()
			if d < 120.0:
				drawing.set_pixel(x, y, Color.BLACK if d > 112.0 else Color("#D9774A"))
	var path := REPLACEMENT_DIR.path_join("Cat_resting.png")
	t.check_eq(drawing.save_png(path), OK, "(setup) a new resting drawing saved as Cat_resting.png")
	var replaced := cat.visual_set.duplicate(true) as CompanionVisualSet
	replaced.get_pose_art(&"resting").image_path = path
	cat.use_visual_set(replaced)
	var shown := cat.get_pose_texture(&"resting").get_image()
	var centre := shown.get_pixel(shown.get_width() / 2, int(shown.get_height() * 0.55))
	t.check(centre.is_equal_approx(Color("#D9774A")) or centre.r > 0.75 and centre.g < 0.55, "[art workflow] the replacement image is shown (colour %s)" % centre.to_html())
	t.check(shown.get_pixel(0, 0).a == 0.0, "[art workflow] its white background is removed too")
	t.check(cat.get_pose_rect(&"resting").size.x == cat.visual_set.display_size, "[art workflow] at the same logical size")
	var untouched := true
	for pose: StringName in CAT_FILES:
		untouched = untouched and FileAccess.get_md5(CAT_FILES[pose]) == originals[pose]
	for pose: StringName in OWNER_FILES:
		untouched = untouched and FileAccess.get_md5(OWNER_FILES[pose]) == OWNER_MD5[pose]
	t.check(untouched, "[art workflow] the game's and the owner's original files are unchanged")
	await t.frames(2)
	await t.screenshot("57_cat_replaced_resting_pose")
	cat.use_visual_set(CompanionVisualSet.for_kind(&"cat"))
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(REPLACEMENT_DIR)


func _test_all_vessels() -> void:
	for id in VesselCatalog.get_default().get_ids():
		app.modals.clear()
		GameSession.start_new_session(CompanionState.KIND_CAT)
		t.check_eq(GameSession.switch_vessel(id), "", "(setup) aboard %s" % id)
		await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var cat := _companion()
		var marker := (app.router.current_screen as Node).get_node("Layout/CompanionSpots/%s" % GameSession.get_companion().spot) as Node2D
		t.check(_count_companions() == 1 and cat.is_sprite_mode() and cat.position == marker.position,
			"[cat art] %s: one drawn cat on its resting spot" % id)
		cat.pet()
		t.check(cat.is_reacting() and cat.pose == &"alert" and _sfx_player_with(cat.purr_sound) != null, "[cat art] %s: petting works" % id)
		await t.frames(3)
		await t.screenshot("58_cat_on_%s" % id)


func _test_persistence() -> void:
	app.modals.clear()
	GameSession.start_new_session(CompanionState.KIND_CAT)
	GameSession.switch_vessel(&"petrel_36")
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var before := GameSession.get_companion().to_dict()
	t.check_eq(SaveManager.save_to_slot(2, GameSession.get_state_snapshot()), OK, "(setup) saved aboard the trimaran")
	var text := FileAccess.get_file_as_string(SaveManager.save_dir.path_join("slot_2.json"))
	t.check(not text.contains("pose") and not text.contains("Cat_resting"), "[cat art] poses are not saved (presentation only)")
	app.show_main_menu()
	await _settle()
	app.load_slot(2)
	await _settle()
	var cat := _companion()
	t.check(GameSession.get_companion().to_dict() == before and cat != null and cat.is_sprite_mode() and _count_companions() == 1,
		"[cat art] after loading: the same cat, drawn, in the same spot")
	app.switch_vessel(&"halcyon_40")
	await _settle()
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	cat = _companion()
	t.check(GameSession.get_companion().to_dict() == before and cat.is_sprite_mode() and _count_companions() == 1,
		"[cat art] after changing boats: the same cat, once")
	cat.pet()
	t.check(cat.is_reacting(), "[cat art] and it can be petted")
	SaveManager.delete_slot(2)


func _test_dog() -> void:
	app.modals.clear()
	GameSession.start_new_session(CompanionState.KIND_DOG)
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var dog := _companion()
	t.check(dog != null and dog.kind == CompanionState.KIND_DOG and dog.is_sprite_mode() and dog.pose == &"resting",
		"[dog] the dog shows its new illustrated art, resting")
	dog.set_pose(&"resting", 999.0)
	await t.frames(2)
	await t.screenshot("13_companion_dog")
	var area := app.router.current_screen as BoatArea
	var cells := W.walkable_cells(area, area.get_spawn_position(&"from_deck"))
	# Walk up beside the dog (not onto it), as a player would.
	var beside := cells.filter(func(c: Vector2) -> bool: return c.distance_to(dog.position) >= 26.0 and c.distance_to(dog.position) <= 60.0)
	beside.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(dog.position) < b.distance_to(dog.position))
	for p: Vector2 in beside:
		area.player.position = p
		area.player.set_facing(dog.position - p)
		await t.physics_frames(4)
		if area.player.get_focused_interactable() == dog.interactable:
			break
	await t.frames(2)
	t.check(area.player.get_focused_interactable() == dog.interactable and dog.interactable.highlight_outline.size() >= 6 and dog.modulate == Color.WHITE,
		"[highlight] the focused dog glows around its silhouette, untinted")
	await t.get_tree().create_timer(0.7).timeout
	await t.screenshot("13_companion_dog_highlighted")
	t.check(dog.rotation == 0.0, "[dog] drawn upright like the cat")
	dog.pet()
	t.check(dog.is_reacting() and _sfx_player_with(dog.dog_sound) != null, "[dog] petting: reaction and panting sound")
	await t.frames(2)
	t.check(dog.pose == &"alert", "[dog] petted: it looks up happily")
	await t.screenshot("59_dog_petted")


# --- Helpers ------------------------------------------------------------------------

func _count_companions() -> int:
	var count := 0
	for node in t.get_tree().root.find_children("*", "", true, false):
		if node is ShipCompanion and not (node as ShipCompanion).preview and node.is_visible_in_tree():
			count += 1
	return count


func _sfx_player_with(stream: AudioStream) -> AudioStreamPlayer:
	for child in AudioManager.get_children():
		var player := child as AudioStreamPlayer
		if player and player.stream == stream and player.playing and player.bus == AudioManager.BUS_SFX:
			return player
	return null


func _show(area: StringName, spawn: StringName) -> void:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)
