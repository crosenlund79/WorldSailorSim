extends RefCounted
## Visual Identity V01, Checkpoint D: the illustrated Starling 33 and the
## illustrated harbour (generic pontoon, quay, facility signs) with
## Copenhagen's optional landmark layer. Art only: collision, stations,
## spawns, mooring and services are unchanged, the classic art is one setting
## away, the owner's drawings are untouched and every slot stays replaceable.

const APP_SCENE := preload("res://src/app/app.tscn")
const DECK := SessionState.AREA_EXTERIOR
const CABIN := SessionState.AREA_INTERIOR
const OWNER_ART := {
	"res://Visuals/Cat/Cat_SleepingBack.png": "687e62a876079c3fa7ee86d10b191974",
	"res://Visuals/Cat/Cat_alert.png": "70f0c3b5091153c614202b4a9dc2e6c2",
	"res://Visuals/Cat/Cat_resting.png": "0bb77ddaeca77b6e958e63e4ead8d494",
	"res://Visuals/Cat/Cat_stretching.png": "550e3c3d7f6b61521c87c4a3dee3387d",
}
const DECK_SLOTS: Array[StringName] = [&"HullBase", &"DeckBase", &"Coachroof", &"DeckDetails"]
const CABIN_SLOTS: Array[StringName] = [&"CabinBase", &"FurnitureVisual", &"CabinDetails"]

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	_test_data()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	# This suite is about the Wing 33 (starling_33) prototype of V01.
	await t.board(&"starling_33", app)
	await _test_starling_illustrated()
	await _test_harbour_copenhagen()
	await _test_generic_harbour_and_sea()
	await _test_other_boats()
	await _test_settings_row()
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _show(area: StringName, spawn: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, spawn)
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


## Everything gameplay in an area: collision shapes, stations, spawns, markers.
func _layout(area: BoatArea) -> Array:
	var result := []
	for node in area.get_node("Layout").find_children("*", "", true, false):
		var entry := [String(area.get_node("Layout").get_path_to(node))]
		if node is Node2D:
			entry.append((node as Node2D).position)
		if node is BoatFixture:
			entry.append((node as BoatFixture).get_points())
		if node is CollisionShape2D and (node as CollisionShape2D).shape:
			entry.append((node as CollisionShape2D).shape.get_rect())
		if node is CollisionPolygon2D:
			entry.append((node as CollisionPolygon2D).polygon)
		result.append(entry)
	return result


func _test_data() -> void:
	for path: String in OWNER_ART:
		t.check_eq(FileAccess.get_md5(path), OWNER_ART[path], "[art] the owner's drawing %s is untouched" % path.get_file())
	var starling := VesselCatalog.get_default().get_vessel(&"starling_33")
	t.check(starling.illustrated_visual_profile != null and starling.illustrated_visual_profile.art_folder == "res://assets/vessels/starling_33/illustrated",
		"[art] the Starling 33 has an illustrated prototype profile in its own folder")
	t.check(starling.visual_profile.art_folder == "res://assets/vessels/starling_33", "[art] its classic profile is unchanged")
	for slot in DECK_SLOTS + CABIN_SLOTS:
		t.check_eq(starling.illustrated_visual_profile.get_source(slot), "file", "[art] illustrated %s is a replaceable PNG slot" % slot)
	for id in [&"halcyon_40", &"petrel_36"]:
		var vessel := VesselCatalog.get_default().get_vessel(id)
		t.check(vessel.illustrated_visual_profile != null and vessel.illustrated_visual_profile.art_folder == "res://assets/vessels/%s/illustrated" % id,
			"[art] %s has its own illustrated profile in its own folder" % id)
		t.check(vessel.visual_profile != vessel.illustrated_visual_profile and vessel.visual_profile.art_folder == "res://assets/vessels/%s" % id,
			"[art] %s keeps its classic profile" % id)
		for slot in DECK_SLOTS + CABIN_SLOTS:
			t.check_eq(vessel.illustrated_visual_profile.get_source(slot), "file", "[art] %s illustrated %s is a replaceable PNG slot" % [id, slot])
	# The hat's art slots are replaceable without code.
	var art := HatArt.new()
	art.art_folder = "res://assets/no_such_folder"
	t.check(art.get_texture(HatArt.SLOT_WORN) == null, "[art] a hat slot without a file uses the drawing")
	var texture := ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	art.worn_texture = texture
	t.check(art.get_texture(HatArt.SLOT_WORN) == texture, "[art] an assigned hat texture replaces the drawing")
	art.procedural_only = true
	t.check(art.get_texture(HatArt.SLOT_WORN) == null, "[art] procedural_only brings the drawing back")
	# Harbour art is optional, data-driven and limited to three landmarks.
	var copenhagen := HarbourArt.for_port(&"copenhagen")
	t.check(copenhagen != null and copenhagen.get_landmarks().size() == 1 and copenhagen.get_landmarks()[0].title == "Nyhavn",
		"[harbour] Copenhagen has one landmark illustration (Nyhavn)")
	t.check(HarbourArt.for_port(&"kiel") == null and HarbourArt.for_port(&"") == null, "[harbour] other harbours need no art")
	var many := HarbourArt.new()
	many.port_id = &"test"
	for i in 4:
		var landmark := HarbourLandmark.new()
		landmark.texture = texture
		many.landmarks.append(landmark)
	t.check_eq(many.get_landmarks().size(), HarbourArt.MAX_LANDMARKS, "[harbour] at most three landmarks per harbour are shown")
	var empty := HarbourLandmark.new()
	many.landmarks = [empty]
	t.check(many.get_landmarks().is_empty(), "[harbour] a landmark without an image is simply skipped")


func _test_starling_illustrated() -> void:
	SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
	var deck := await _show(DECK, &"start")
	var classic_layout := _layout(deck)
	var visual := deck.get_node("Visual") as VesselVisual
	t.check(not visual.get_slot(&"DeckBase").is_sprite(), "[starling] Classic shows the earlier procedural deck")
	await t.screenshot("140_starling_deck_classic")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	await t.frames(2)
	var all_sprites := true
	for slot in DECK_SLOTS:
		all_sprites = all_sprites and visual.get_slot(slot).is_sprite() \
			and visual.get_slot(slot).get_sprite().texture.resource_path.contains("/illustrated/deck/")
	t.check(all_sprites, "[starling] Illustrated switches the deck to the painted layers at once")
	t.check_eq(_layout(deck), classic_layout, "[starling] collision, stations, spawns and sail markers are identical in both styles")
	var sprite := visual.get_slot(&"HullBase").get_sprite()
	t.check(is_equal_approx(sprite.texture.get_width() * sprite.scale.x, visual.canvas.size.x), "[starling] the layers cover exactly the canvas")
	t.check(deck.player.test_move(Transform2D(0.0, deck.to_global(Vector2(-330, 0))), Vector2(500, 0)), "[starling] the coachroof still blocks the player")
	await t.screenshot("141_starling_deck_illustrated")
	deck = await _show(DECK, &"start")
	t.check((deck.get_node("Visual") as VesselVisual).get_slot(&"Coachroof").is_sprite(), "[starling] a newly shown deck uses the illustrated art")
	# The cabin, in both styles.
	SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
	var cabin := await _show(CABIN, &"start")
	var cabin_layout := _layout(cabin)
	await t.screenshot("142_starling_cabin_classic")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	await t.frames(2)
	var cabin_visual := cabin.get_node("Visual") as VesselVisual
	var cabin_sprites := true
	for slot in CABIN_SLOTS:
		cabin_sprites = cabin_sprites and cabin_visual.get_slot(slot).is_sprite()
	t.check(cabin_sprites, "[starling] the cabin shows the painted layers")
	t.check_eq(_layout(cabin), cabin_layout, "[starling] the cabin's layout is identical in both styles")
	t.check(cabin.get_hat_hook() != null and cabin.get_hat_hook().is_showing_hat(), "[starling] the stored hat hangs on its hook over the painted locker")
	t.check(cabin.get_node("ProvisionDisplay").visible and cabin.get_node("Companion") != null, "[starling] provisions display and the cat are still there")
	await t.screenshot("143_starling_cabin_illustrated")
	GameSession.set_condition_for_testing(30.0)
	await t.frames(2)
	var overlay := cabin_visual.find_children("*", "DamageOverlay", true, false)
	t.check(not overlay.is_empty() and (overlay[0] as CanvasItem).visible, "[starling] damage is still drawn over the illustrated cabin")
	await t.screenshot("144_starling_cabin_illustrated_damaged")
	GameSession.set_condition_for_testing(100.0)


func _test_harbour_copenhagen() -> void:
	var deck := await _show(DECK, &"from_boatyard")
	var dressing := deck.get_harbour_dressing()
	t.check(dressing != null and dressing.is_visible_in_tree(), "[harbour] moored in Copenhagen the illustrated harbour is shown")
	if dressing == null:
		return
	t.check(dressing.get_landmarks().size() == 1 and dressing.get_landmarks()[0].title == "Nyhavn", "[harbour] with Copenhagen's landmark")
	var ids := dressing.get_sign_ids()
	t.check(ids.size() == 3 and ids.has(&"boatyard") and ids.has(&"grocery") and ids.has(&"go_ashore"),
		"[harbour] signs for the services there are: the grocery store, the boatyard (with repairs) and Go Ashore (Iteration 12)")
	var offered := HarbourFacilities.for_port(&"copenhagen").get_ids()
	t.check(ids.size() == offered.size() and ids.all(func(id: StringName) -> bool: return id in offered),
		"[harbour] and nothing else (no fuel or future services)")
	var mooring := deck.mooring
	t.check(not (mooring.get_node("Plank0") as CanvasItem).visible and (mooring.get_node("GrocerySign") as Label).text == "Groceries",
		"[harbour] the old pontoon drawing gives way to the illustration; the sign reads Groceries")
	var label := deck.mooring_label
	t.check(label.visible and label.text.contains("COPENHAGEN") and label.label_settings.font is FontVariation
		and (label.label_settings.font as FontVariation).base_font.resource_path.ends_with("BarlowCondensed-Medium.ttf"),
		"[harbour] the harbour name sign is in the signage face (Barlow Condensed)")
	t.check(dressing.get_parent() == mooring and dressing.get_index() > mooring.get_node("Pontoon").get_index()
		and mooring.get_parent().get_index() < deck.get_node("Visual").get_index(), "[harbour] it is drawn over the water and under the boat")
	t.check(dressing.find_children("*", "CollisionObject2D", true, false).is_empty()
		and dressing.get_children().all(func(child: Node) -> bool: return child is HighlightProvider),
		"[harbour] it has no collision of its own (only the signs' highlight outlines)")
	await t.screenshot("145_copenhagen_harbour_illustrated")
	# The services still work: walk to them and press E.
	t.check(await _use(deck, &"grocery") and app.modals.get_top() is GroceryMenu, "[harbour] the grocery store opens from the pontoon as before")
	app.modals.clear()
	await t.frames(2)
	t.check(await _use(deck, &"boatyard") and app.modals.get_top() is BoatyardMenu, "[harbour] the boatyard opens as before")
	await t.screenshot("146_boatyard_illustrated_starling")
	app.modals.clear()
	await t.frames(2)
	SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
	await t.frames(2)
	t.check(not dressing.visible and (mooring.get_node("Plank0") as CanvasItem).visible and (mooring.get_node("GrocerySign") as Label).text == "GROCERY STORE",
		"[harbour] Classic brings back the earlier pontoon")
	await t.screenshot("147_copenhagen_harbour_classic")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	await t.frames(2)


func _use(area: BoatArea, id: StringName) -> bool:
	var station: Interactable = null
	for node: Interactable in area.get_node("Layout/Stations").get_children():
		if node.interaction_id == id:
			station = node
	if station == null or not station.enabled:
		return false
	var cells := TestWalkability.walkable_cells(area, area.get_spawn_position(&"from_boatyard"))
	var tries := 0
	for p in TestWalkability.use_points(station, cells):
		area.player.position = p
		area.player.set_facing((station.global_position - p).normalized())
		await t.physics_frames(3)
		if area.player.get_focused_interactable() == station:
			await t.press_action(&"interact")
			await t.frames(2)
			return true
		tries += 1
		if tries > 40:
			break
	return false


func _test_generic_harbour_and_sea() -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = &"kiel"
	state.vessel_position = PortCatalog.get_default().get_port(&"kiel").get_geo_position()
	GameSession.replace_state(state)
	var deck := await _show(DECK, &"from_boatyard")
	var dressing := deck.get_harbour_dressing()
	# I021: a harbour without its own art shows the illustration of its look
	# (Kiel: the gabled harbour town), never a landmark of another place.
	var landmarks := dressing.get_landmarks()
	t.check(dressing.is_visible_in_tree() and landmarks.size() == 1 and landmarks[0].title == "Gabled harbour town" and dressing.get_sign_ids().size() == 3,
		"[harbour] a harbour without its own art (Kiel) gets the generic illustrated harbour with its look's view")
	t.check(deck.mooring_label.text.contains("KIEL"), "[harbour] with its own name on the sign")
	await t.screenshot("148_kiel_generic_harbour")
	GameSession.set_planned_route(t.make_route(&"kiel", &"copenhagen"))
	GameSession.depart()
	await t.frames(2)
	t.check(not dressing.is_visible_in_tree(), "[harbour] at sea there is no harbour")
	Simulation.advance(40.0 * 3600.0)
	await _settle()
	deck = await _show(DECK, &"from_boatyard")
	dressing = deck.get_harbour_dressing()
	t.check(GameSession.get_location_id() == &"copenhagen" and dressing.is_visible_in_tree() and dressing.get_landmarks().size() == 1,
		"[harbour] arriving in Copenhagen shows Nyhavn again")


func _test_other_boats() -> void:
	for id in [&"halcyon_40", &"petrel_36"]:
		GameSession.switch_vessel(id)
		var deck := await _show(DECK, &"from_boatyard")
		var visual := deck.get_node("Visual") as VesselVisual
		t.check(visual.get_slot(&"DeckBase").is_sprite() and visual.get_slot(&"HullBase").is_sprite(), "[art] the %s deck is illustrated in Illustrated mode" % id)
		SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
		await t.frames(2)
		t.check(not visual.get_slot(&"DeckBase").is_sprite(), "[art] the %s returns to its own classic art in Classic mode" % id)
		SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
		await t.frames(2)
		var dressing := deck.get_harbour_dressing()
		t.check(dressing != null and dressing.is_visible_in_tree() and dressing.get_sign_ids().size() == 3,
			"[harbour] the %s's pontoon gets the illustrated harbour and its signs too" % id)
		await t.screenshot("149_harbour_%s" % id)
	GameSession.switch_vessel(&"starling_33")


func _test_settings_row() -> void:
	app.open_settings()
	await t.frames(3)
	var menu := app.modals.get_top() as SettingsMenu
	var option := menu.find_child("ArtStyle", true, false) as OptionButton
	t.check(option != null and option.item_count == 2 and option.get_item_text(option.selected) == "Illustrated (prototype)",
		"[settings] Settings offers Artwork: Illustrated (prototype) or Classic")
	option.select(1)
	option.item_selected.emit(1)
	t.check_eq(SettingsManager.get_art_style(), SettingsManager.ART_CLASSIC, "[settings] choosing Classic applies it")
	await t.screenshot("150_settings_artwork")
	menu.find_child("ApplyButton", true, false).pressed.emit()
	var config := ConfigFile.new()
	config.load(SettingsManager.settings_path)
	t.check_eq(config.get_value("display", "art_style", ""), "classic", "[settings] and Apply saves it")
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_art_style(), SettingsManager.ART_CLASSIC, "[settings] it is restored when loading the settings")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	SettingsManager.save()
	app.modals.clear()
	await t.frames(2)
