extends RefCounted
## Revision 0.105b, Sprite Workshop Phase 1 (ARTMAN, ARTRES, ARTTEST).
##   - the manifests: required columns, unique ids and files, honest statuses,
##     nothing installed in the repository;
##   - the resolver: missing -> fallback, cached (no reloading), validation of
##     shape and readability with a useful warning;
##   - every READY entry really reaches the art it claims to replace (fixture
##     installed, the consumer asked, fixture removed);
##   - the three working examples in the running game, each through the full
##     sequence (original, valid replacement shown at the right size and pivot,
##     removed -> original again, wrong shape and unreadable file -> safe
##     fallback with a warning):
##       1. a small in-world object: the anchor buoy (procedural adapter);
##       2. a pet: Snøvs resting (pose-texture set; state and safe places unchanged);
##       3. a layered asset: the Arctic Wanderer 26's coachroof deck layer.
## Fixtures are made in code (TestArtFixtures) and removed again.

const APP_SCENE := preload("res://src/app/app.tscn")
const F := preload("res://tests/helpers/art_fixtures.gd")
const W := preload("res://tests/helpers/walkability.gd")
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	ArtworkResolver.reload()
	_test_manifests()
	_test_resolver_basics()
	await _test_every_ready_entry()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	Simulation.auto_advance = false
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_buoy()
	await _test_snovs()
	await _test_coachroof()
	t.check(F.installed_pngs().is_empty(), "[workshop] nothing left installed in art_replacements/ (%s)" % [F.installed_pngs()])
	ArtworkResolver.reload()
	CompanionVisualSet.clear_cache()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _entry(id: String) -> Dictionary:
	return ArtworkResolver.get_entry(StringName(id))


# --- Manifests ------------------------------------------------------------------------------

func _test_manifests() -> void:
	var manifests := ArtworkResolver.find_manifests(ArtworkResolver.ROOT)
	var entries := ArtworkResolver.get_entries()
	t.check(manifests.size() >= 10 and entries.size() >= 100, "[manifest] %d manifests, %d entries" % [manifests.size(), entries.size()])
	t.check(ArtworkResolver.get_warnings().is_empty(), "[manifest] all valid: no duplicate ids or files, every status known (%s)" % [ArtworkResolver.get_warnings()])
	var readme_ok := true
	for m in manifests:
		readme_ok = readme_ok and FileAccess.file_exists(m.get_base_dir().path_join("README.md"))
	t.check(readme_ok and FileAccess.file_exists(ArtworkResolver.ROOT.path_join("README_START_HERE.md")) and FileAccess.file_exists(ArtworkResolver.ROOT.path_join("INDEX.md")),
		"[manifest] every folder has its README.md; the root has README_START_HERE.md and INDEX.md")
	var counts := {}
	for id: StringName in entries:
		var s := String(entries[id].integration_status)
		counts[s] = int(counts.get(s, 0)) + 1
	t.check(counts.get("READY", 0) > 0 and counts.get("ADAPTER_REQUIRED", 0) > 0 and counts.get("REFERENCE_ONLY", 0) > 0,
		"[manifest] honest statuses: %s" % [counts])
	t.check(F.installed_pngs().is_empty(), "[manifest] no replacement PNGs are installed in the repository")
	t.check(_entry("pet.snovs.resting").get("integration_status") == "READY" and _entry("character.captain.body").get("integration_status") == "ADAPTER_REQUIRED",
		"[manifest] Snøvs is READY; the walking Captain honestly needs an adapter")


func _test_resolver_basics() -> void:
	var fallback := PlaceholderTexture2D.new()
	t.check(ArtworkResolver.get_artwork(&"no.such.asset", fallback) == fallback, "[resolver] an unknown id gives the fallback")
	t.check(ArtworkResolver.get_artwork(&"pet.snovs.resting", fallback) == fallback, "[resolver] a READY entry with no PNG gives the fallback, silently")
	t.check(ArtworkResolver.get_artwork(&"character.captain.body") == null, "[resolver] non-READY entries are never resolved")
	var entry := _entry("equipment.anchor.buoy")
	t.check(ArtworkResolver.validate_size(entry, 48, 48) == "" and ArtworkResolver.validate_size(entry, 96, 96) == ""
		and ArtworkResolver.validate_size(entry, 48, 96) != "" and ArtworkResolver.validate_size(entry, 8, 8) != "",
		"[resolver] size rule: the manifest's shape, half to four times the 2x size")
	F.install(entry)
	ArtworkResolver.reload()
	var loads := ArtworkResolver.loads
	var first := ArtworkResolver.get_artwork(&"equipment.anchor.buoy")
	for i in 50:
		ArtworkResolver.get_artwork(&"equipment.anchor.buoy")
	t.check(first != null and ArtworkResolver.loads == loads + 1, "[resolver] loaded once and cached (%d loads for 51 requests)" % (ArtworkResolver.loads - loads))
	F.remove(entry)
	ArtworkResolver.reload()


# --- Every READY entry reaches its art --------------------------------------------------------

func _test_every_ready_entry() -> void:
	var entries := ArtworkResolver.get_entries()
	var failed: Array[String] = []
	var checked := 0
	for id: StringName in entries:
		var entry: Dictionary = entries[id]
		if entry.integration_status != ArtworkResolver.STATUS_READY:
			continue
		var big := maxi(int(entry.source_width_2x), int(entry.source_height_2x)) > 1024
		F.install(entry, Vector2i.ZERO, 0.5 if big else 1.0)
		ArtworkResolver.reload()
		CompanionVisualSet.clear_cache()
		var ok := await _consumer_shows(String(id))
		F.remove(entry)
		checked += 1
		if not ok:
			failed.append(String(id))
	ArtworkResolver.reload()
	CompanionVisualSet.clear_cache()
	t.check(failed.is_empty(), "[ready] all %d READY entries reach the art they replace (failed: %s)" % [checked, failed])


## Asks the real consumer of `id` for its picture: true when it is the fixture.
func _consumer_shows(id: String) -> bool:
	var parts := id.split(".")
	match parts[0]:
		"boat":
			if parts[1] == "shared":
				return parts[2] == "solar_panel" and await _solar_shows()
			var scene := load("res://src/vessels/%s/%s_visual.tscn" % [parts[1], parts[2]]) as PackedScene
			var visual := scene.instantiate() as VesselVisual
			t.add_child(visual)
			visual.apply(VesselCatalog.get_default().get_vessel(StringName(parts[1])).illustrated_visual_profile)
			var shown := false
			for slot in visual.get_slots():
				if String(visual.workshop_id(slot.slot)) == id:
					var sprite := slot.get_node_or_null("Sprite") as Sprite2D
					shown = sprite != null and sprite.visible and F.is_fixture(sprite.texture)
			visual.queue_free()
			return shown
		"pet":
			var kind := &"cat" if parts[1] == "snovs" else StringName(parts[1])
			return F.is_fixture(CompanionVisualSet.for_kind(kind).get_texture(StringName(parts[2])))
		"fish":
			return F.is_fixture(FishArt.layer(parts[1], parts[2]))
		"character":
			HatArt.clear_default()
			return F.is_fixture(HatArt.get_default().get_texture(StringName(parts[2].trim_prefix("hat_"))))
		"equipment":
			# AnchorSignals asks for exactly these ids (example 1 shows it in the game).
			return StringName(id) in [AnchorSignals.BUOY_ID, AnchorSignals.BALL_ID] and F.is_fixture(ArtworkResolver.get_artwork(StringName(id)))
	return false


func _solar_shows() -> bool:
	var panels := SolarPanels.new()
	t.add_child(panels)
	panels.setup([Rect2(0, 0, 40, 100)] as Array[Rect2])
	var shown := panels.uses_replacement() and F.is_fixture(panels._texture)
	panels.queue_free()
	return shown


# --- Example 1: the anchor buoy (a small in-world object, procedural adapter) ----------------

func _anchor_off_nyborg() -> BoatArea:
	var spot := GameSession.nearest_anchorage_spot(Vector2(10.95, 55.35), 6.0)
	var state := GameSession.get_state_snapshot()
	var route := PlannedRoute.new()
	route.origin_port_id = &"copenhagen"
	route.origin_position = spot
	route.destination_port_id = &"copenhagen"
	route.path = PackedVector2Array([spot, spot + Vector2(0.0, -0.05)])
	state.voyage = Voyage.create(route, state.game_time)
	state.vessel_status = SessionState.STATUS_UNDERWAY
	state.location_id = &""
	state.vessel_position = spot
	state.planned_route = null
	GameSession.replace_state(state)
	t.set_wind(200.0, 8.0)
	GameSession.drop_anchor(5, 0.9)
	return await _show(DECK)


func _show(area: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, &"start")
	app._show_current_boat_area()
	await _settle()
	app.toasts.clear()
	app.hud.hide_warning()
	return app.router.current_screen as BoatArea


func _reload_art() -> void:
	ArtworkResolver.reload()
	CompanionVisualSet.clear_cache()


func _test_buoy() -> void:
	var entry := _entry("equipment.anchor.buoy")
	var deck := await _anchor_off_nyborg()
	if not t.check(GameSession.is_anchored(), "(setup) at anchor off Nyborg"):
		return
	deck.view_heading_override = 90.0
	deck._update_camera()
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.4).timeout
	t.check(not deck.get_anchor_signals().uses_buoy_replacement(), "[example 1] 1. no PNG: the original buoy is drawn")
	await t.screenshot("rb_16_workshop_buoy_original")
	F.install(entry)
	_reload_art()
	deck = await _show(DECK)
	deck.view_heading_override = 90.0
	deck._update_camera()
	await t.get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.4).timeout
	var signals := deck.get_anchor_signals()
	t.check(signals.uses_buoy_replacement(), "[example 1] 2-3. a valid %s x %s PNG: the replacement buoy appears" % [entry.source_width_2x, entry.source_height_2x])
	var rect := signals.get_buoy_rect()
	t.check(rect.size == Vector2(AnchorSignals.BUOY_SIZE, AnchorSignals.BUOY_SIZE) and rect.get_center().is_equal_approx(signals.get_buoy_position()),
		"[example 1] 4. drawn %d x %d units, centred on the buoy (pivot)" % [roundi(rect.size.x), roundi(rect.size.y)])
	await t.screenshot("rb_17_workshop_buoy_replaced")
	F.remove(entry)
	_reload_art()
	deck = await _show(DECK)
	t.check(not deck.get_anchor_signals().uses_buoy_replacement(), "[example 1] 5-6. removed: the original buoy is back")
	F.install(entry, Vector2i(48, 96))
	_reload_art()
	deck = await _show(DECK)
	var warned := "\n".join(ArtworkResolver.get_warnings())
	t.check(not deck.get_anchor_signals().uses_buoy_replacement() and warned.contains("equipment.anchor.buoy") and warned.contains("shape"),
		"[example 1] 7-8. a wrongly shaped PNG is refused with a useful warning; the original stays (%s)" % warned)
	F.remove(entry)
	F.install_garbage(entry)
	_reload_art()
	deck = await _show(DECK)
	warned = "\n".join(ArtworkResolver.get_warnings())
	t.check(not deck.get_anchor_signals().uses_buoy_replacement() and warned.contains("could not be read"),
		"[example 1] an unreadable file is refused safely (%s)" % warned)
	F.remove(entry)
	_reload_art()
	deck.view_heading_override = NAN
	GameSession.raise_anchor()


# --- Example 2: Snøvs (a pet, pose-texture set) ------------------------------------------------

func _companion(area: BoatArea) -> ShipCompanion:
	return area.find_child("Companion", true, false) as ShipCompanion


func _test_snovs() -> void:
	var entry := _entry("pet.snovs.resting")
	GameSession.end_session()
	app.start_new_game()
	await _settle()
	if GameSession.get_companion().kind != CompanionState.KIND_CAT:
		var state := GameSession.get_state_snapshot()
		state.companion = CompanionState.create(CompanionState.KIND_CAT, state.game_time)
		GameSession.replace_state(state)
	var cabin := await _show(CABIN)
	var pet := _companion(cabin)
	if not t.check(pet != null and pet.kind == CompanionState.KIND_CAT, "(setup) Snøvs (the ship's cat) is in the cabin"):
		return
	pet.set_pose(CompanionVisualSet.POSE_RESTING, 30.0)
	var original := pet.get_pose_texture(CompanionVisualSet.POSE_RESTING)
	t.check(original != null and not F.is_fixture(original), "[example 2] 1. no PNG: Snøvs's own resting picture")
	var spot_before := GameSession.get_companion().spot
	var position_before := pet.position
	await t.frames(3)
	await t.screenshot("rb_18_workshop_snovs_original")
	F.install(entry)
	_reload_art()
	cabin = await _show(CABIN)
	pet = _companion(cabin)
	pet.set_pose(CompanionVisualSet.POSE_RESTING, 30.0)
	var texture := pet.get_pose_texture(CompanionVisualSet.POSE_RESTING)
	t.check(F.is_fixture(texture), "[example 2] 2-3. a valid %s x %s PNG: Snøvs is drawn with it" % [entry.source_width_2x, entry.source_height_2x])
	var rect := pet.visual_set.get_draw_rect(CompanionVisualSet.POSE_RESTING, texture)
	t.check(rect.size.is_equal_approx(Vector2.ONE * pet.visual_set.display_size) and (rect.position + pet.visual_set.pivot * rect.size).is_zero_approx(),
		"[example 2] 4. shown %d x %d units, its pivot (the ground point) on the resting spot" % [roundi(rect.size.x), roundi(rect.size.y)])
	t.check(GameSession.get_companion().spot == spot_before and pet.position.is_equal_approx(position_before),
		"[example 2] the pet's state and resting place are unchanged by the picture")
	t.check(not F.is_fixture(pet.get_pose_texture(CompanionVisualSet.POSE_SLEEPING)), "[example 2] the other poses keep their own pictures until drawn")
	await t.frames(3)
	await t.screenshot("rb_19_workshop_snovs_replaced")
	F.remove(entry)
	_reload_art()
	cabin = await _show(CABIN)
	pet = _companion(cabin)
	t.check(not F.is_fixture(pet.get_pose_texture(CompanionVisualSet.POSE_RESTING)) and pet.is_sprite_mode(), "[example 2] 5-6. removed: Snøvs's own picture is back")
	F.install(entry, Vector2i(284, 142))
	_reload_art()
	cabin = await _show(CABIN)
	pet = _companion(cabin)
	t.check(not F.is_fixture(pet.get_pose_texture(CompanionVisualSet.POSE_RESTING)) and "\n".join(ArtworkResolver.get_warnings()).contains("pet.snovs.resting"),
		"[example 2] 7-8. a wrongly shaped PNG is refused with a warning; Snøvs keeps the original")
	F.remove(entry)
	_reload_art()


# --- Example 3: a layered boat asset (the Arctic Wanderer 26 coachroof) ------------------------

func _test_coachroof() -> void:
	var entry := _entry("boat.arctic_wanderer_26.deck.coachroof")
	GameSession.end_session()
	app.start_new_game()
	await _settle()
	var state := GameSession.get_state_snapshot()
	state.vessel_id = &"arctic_wanderer_26"
	GameSession.replace_state(state)
	var deck := await _show(DECK)
	var visual := deck.get_node("Visual") as VesselVisual
	var slot := visual.get_slot(&"Coachroof")
	var sprite := slot.get_node_or_null("Sprite") as Sprite2D
	t.check(sprite != null and not F.is_fixture(sprite.texture), "[example 3] 1. no PNG: the boat's own coachroof layer")
	var cells_before := W.walkable_cells(deck, deck.get_spawn_position(&"start")).size()
	await t.screenshot("rb_20_workshop_coachroof_original")
	F.install(entry)
	_reload_art()
	deck = await _show(DECK)
	visual = deck.get_node("Visual") as VesselVisual
	sprite = visual.get_slot(&"Coachroof").get_node_or_null("Sprite") as Sprite2D
	t.check(sprite != null and F.is_fixture(sprite.texture), "[example 3] 2-3. a valid %s x %s PNG: the replacement layer is drawn" % [entry.source_width_2x, entry.source_height_2x])
	var shown := Rect2(sprite.position, sprite.texture.get_size() * sprite.scale)
	t.check(shown.position.is_equal_approx(visual.canvas.position) and absf(shown.size.x - visual.canvas.size.x) < 0.5 and absf(shown.size.y - visual.canvas.size.y) < 0.5,
		"[example 3] 4. it covers exactly the boat's art canvas %s (origin at its top-left)" % visual.canvas)
	var other := visual.get_slot(&"DeckBase").get_node_or_null("Sprite") as Sprite2D
	t.check(other != null and not F.is_fixture(other.texture), "[example 3] the other layers keep their own art")
	t.check(W.walkable_cells(deck, deck.get_spawn_position(&"start")).size() == cells_before, "[example 3] the walkable deck is unchanged by the picture (%d cells)" % cells_before)
	await t.screenshot("rb_21_workshop_coachroof_replaced")
	F.remove(entry)
	_reload_art()
	deck = await _show(DECK)
	sprite = (deck.get_node("Visual") as VesselVisual).get_slot(&"Coachroof").get_node_or_null("Sprite") as Sprite2D
	t.check(sprite != null and not F.is_fixture(sprite.texture), "[example 3] 5-6. removed: the original layer is back")
	F.install(entry, Vector2i(1760, 1760))
	_reload_art()
	deck = await _show(DECK)
	sprite = (deck.get_node("Visual") as VesselVisual).get_slot(&"Coachroof").get_node_or_null("Sprite") as Sprite2D
	t.check(sprite != null and not F.is_fixture(sprite.texture) and "\n".join(ArtworkResolver.get_warnings()).contains("coachroof"),
		"[example 3] 7-8. a square PNG for a 2.75:1 layer is refused with a warning; the original stays")
	F.remove(entry)
	_reload_art()
