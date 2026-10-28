extends RefCounted
## I024, The Company We Keep:
##   - companions: three kinds (Ragdoll cat, Pug, parrot), an optional name and
##     gender chosen at New Game (no name is made up), smaller sizes, real
##     animated clips (walk, turn, sit, sleep, wake, petting, the parrot's
##     takeoff, flight and landing), older saves keep their companion;
##   - ashore: the companion follows the Captain down the gangplank, the boat
##     cannot cast off while it is ashore (a personal line in English and
##     Danish, and a way to call it aboard), loading never leaves it ashore;
##   - waking: by the berth, sometimes a small line, never over an alarm;
##   - long passages: the Captain talks a little more as the days go by, never
##     in a flood, never sooner after a reload;
##   - renown: the achievement collection (categories, unlocked first by date,
##     locked ones greyed with a lock, when / where / which boat, honest
##     fallbacks for older saves), sustained sailing-speed milestones that
##     need a real hour under sail, companion milestones that cannot be
##     farmed, and nothing paid twice;
##   - the laptop on the cabin table: every cabin has one, it opens the laptop
##     view, the apps are drawn on its screen, Esc closes, the postcard
##     composer and remote work still work there.

const APP_SCENE := preload("res://src/app/app.tscn")
const BOATS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]
const HOUR := 3600.0

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	WeatherFixtures.use([])
	_test_state_and_saves()
	_test_pre_i024_save()
	_test_remarks_and_languages()
	_test_speed_tracking()
	_test_collection()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_new_game_menu()
	await _test_animation()
	await _test_parrot_flight()
	await _test_shore_and_departure()
	await _test_wake_by_berth()
	await _test_passage_talk()
	await _test_laptop()
	SettingsManager.set_language(&"en")
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


func _companion() -> ShipCompanion:
	var area := app.router.current_screen as Node
	return area.find_child("Companion", false, false) as ShipCompanion if area else null


# --- State and saves -------------------------------------------------------------------

func _test_state_and_saves() -> void:
	var parrot := CompanionState.create(CompanionState.KIND_PARROT, 0.0, "  Kiwi \n the  Brave ", CompanionState.GENDER_FEMALE)
	t.check(parrot.kind == CompanionState.KIND_PARROT and parrot.name == "Kiwi the Brave" and parrot.gender == CompanionState.GENDER_FEMALE,
		"[companion] a parrot named 'Kiwi the Brave' (tidied), female")
	t.check(CompanionState.create(CompanionState.KIND_DOG, 0.0).name == "", "[companion] no name chosen: none is made up")
	t.check(CompanionState.clean_name("Abcdefghijklmnopqrstuvwxyz").length() == CompanionState.MAX_NAME_LENGTH, "[companion] names are kept short")
	var errors: Array[String] = []
	# An older (I023) companion: no name, no gender, cat or dog.
	var old := CompanionState.from_dict({"kind": "dog", "spot": "seating", "next_move_time": 1000.0, "moves": 3, "area": "deck", "deck_spot": 1}, errors)
	t.check(old != null and errors.is_empty() and old.kind == CompanionState.KIND_DOG and old.name == "" and old.gender == &"",
		"[saves] an I023 dog loads: a Pug now, no name or gender invented")
	var round_trip := CompanionState.from_dict(parrot.to_dict(), errors)
	t.check(round_trip != null and round_trip.to_dict() == parrot.to_dict(), "[saves] name, gender and kind survive a save")
	var ashore := parrot.to_dict()
	ashore.area = "shore"
	var loaded := CompanionState.from_dict(ashore, errors)
	t.check(loaded != null and loaded.area == CompanionState.AREA_DECK, "[saves] a game saved with the companion ashore loads with it aboard (never lost)")
	var woke := CompanionState.create(CompanionState.KIND_DOG, 0.0)
	woke.wake_by_berth(100.0)
	t.check(CompanionState.from_dict(woke.to_dict(), errors) != null and woke.spot == CompanionState.WAKE_SPOT,
		"[saves] a dog found by the berth on waking saves and loads")
	# Sizes: smaller than before (cat 100) and the parrot clearly the smallest.
	var sizes := {}
	for kind in CompanionState.KINDS:
		sizes[kind] = CompanionVisualSet.for_kind(kind).display_size
	t.check(sizes.cat < 100.0 and sizes.dog < sizes.cat and sizes.parrot < sizes.dog, "[proportions] cat %s, dog %s, parrot %s (was 100)" % [sizes.cat, sizes.dog, sizes.parrot])


## A real save written by the build before I024 (tests/fixtures/save_pre_i024.json:
## a dog without a name, a voyage to Kiel and back, a postcard, one travel
## update) loads with everything kept, and its history shows honestly.
func _test_pre_i024_save() -> void:
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/save_pre_i024.json")
	var before: Dictionary = JSON.parse_string(fixture).session
	SaveManager.save_dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir)
	var file := FileAccess.open(SaveManager.save_dir.path_join("slot_3.json"), FileAccess.WRITE)
	file.store_string(fixture)
	file.close()
	var loaded := SaveManager.load_from_slot(3)
	if not t.check(loaded.is_ok(), "[saves] the pre-I024 save loads (%s)" % loaded.error):
		return
	var state := loaded.state
	t.check(state.companion.kind == CompanionState.KIND_DOG and state.companion.name == "" and state.companion.gender == &""
		and state.companion.spot == StringName(before.companion.spot), "[saves] its dog is there (a Pug now), same spot, no name invented")
	t.check(state.progress.lifetime_renown == int(before.progress.lifetime_renown) and state.progress.unpublished_renown == int(before.progress.unpublished_renown)
		and state.progress.publications == int(before.progress.publications) and state.progress.completed.keys() == (before.progress.completed as Dictionary).keys(),
		"[saves] renown %d, publications and every earned record kept" % state.progress.lifetime_renown)
	t.check(state.pastimes.postcards.size() == (before.pastimes.postcards as Array).size(), "[saves] the postcards kept")
	var catalog := AchievementCatalog.get_default()
	var cast_off := catalog.unlock_of(catalog.get_achievement("first_voyage"), state.progress)
	t.check(float(cast_off.time) == float(before.progress.completed.first_voyage.first) and AchievementCatalog.describe_where(cast_off) == "Location not recorded",
		"[history] 'Cast off' from the older save: its real date, 'Location not recorded'")
	var going_public := catalog.unlock_of(catalog.get_achievement("going_public"), state.progress)
	t.check(AchievementCatalog.describe_when(going_public) == "Previously unlocked", "[history] its travel update: 'Going public', previously unlocked")
	t.check(state.progress.is_completed(&"visit_kiel") and not catalog.collection(state.progress).any(func(e: Dictionary) -> bool: return e.achievement.id == "visit_kiel"),
		"[saves] a retired goal stays earned in the history, not in the collection")
	t.check_eq(SaveManager.save_to_slot(3, state), OK, "(setup) saved again")
	var again := SaveManager.load_from_slot(3)
	t.check(again.is_ok() and again.state.progress.to_dict() == state.progress.to_dict() and again.state.companion.to_dict() == state.companion.to_dict(),
		"[saves] and saves and loads again unchanged")
	SaveManager.delete_slot(3)


func _test_remarks_and_languages() -> void:
	var fido := {"kind": CompanionState.KIND_DOG, "name": "Fido", "gender": CompanionState.GENDER_MALE}
	var cat := {"kind": CompanionState.KIND_CAT, "name": "", "gender": &""}
	SettingsManager.set_language(&"en")
	t.check_eq(CompanionRemarks.still_ashore(fido), "Wait! Fido is still ashore.", "[ashore] the refusal names the companion")
	t.check_eq(CompanionRemarks.still_ashore(cat), "Wait! The cat is still ashore.", "[ashore] without a name: the cat")
	SettingsManager.set_language(&"da")
	var danish := CompanionRemarks.still_ashore(fido)
	t.check(danish.contains("Fido") and danish != "Wait! Fido is still ashore.", "[ashore] in Danish too (%s)" % danish)
	t.check(not CompanionRemarks.call_aboard_label(cat).begins_with("Call"), "[ashore] the recall action is Danish (%s)" % CompanionRemarks.call_aboard_label(cat))
	SettingsManager.set_language(&"en")
	# Wake lines and passage lines: by kind, the name when there is one.
	t.check(CompanionRemarks.wake_line(fido, 1).contains("Fido") or not CompanionRemarks.WAKE[CompanionState.KIND_DOG][1].contains("%s"),
		"[waking] the wake-up line uses the name")
	var early := CompanionRemarks.passage_lines(cat, CompanionRemarks.STAGE_EARLY)
	var extended := CompanionRemarks.passage_lines(fido, CompanionRemarks.STAGE_EXTENDED)
	t.check(early.all(func(l: String) -> bool: return not l.contains("%s")), "[talk] an unnamed companion is never addressed by a name")
	t.check(extended.size() >= 12 and not extended.any(func(l: String) -> bool: return l in early), "[talk] a real pool of lines per stage (%d extended)" % extended.size())
	t.check(CompanionRemarks.passage_stage(10.0) == 0 and CompanionRemarks.passage_stage(60.0) == 1 and CompanionRemarks.passage_stage(200.0) == 2,
		"[talk] the stages follow the days at sea")
	var silent := 0
	for n in 14:
		if CompanionRemarks.response(fido, n).text == "":
			silent += 1
	t.check(silent > 0 and silent < 14, "[talk] sometimes the companion does nothing (%d of 14)" % silent)


# --- Sailing speed and the collection --------------------------------------------------------

func _test_speed_tracking() -> void:
	GameSession.start_new_session()
	var renown := GameSession.get_lifetime_renown()
	# Fifty minutes at 9 kn, then the engine: not a sustained hour.
	for i in 10:
		GameSession.note_sailing(i * 300.0, (i + 1) * 300.0, 9.0, true)
	GameSession.note_sailing(3000.0, 3300.0, 6.0, false)
	for i in 3:
		GameSession.note_sailing(3300.0 + i * 300.0, 3600.0 + i * 300.0, 9.5, true)
	t.check_eq(GameSession.get_lifetime_renown(), renown, "[speed] 50 minutes fast, then the engine: no speed milestone (the hour starts again)")
	# A gap in time (a reload, an anchorage) also starts again.
	GameSession.note_sailing(9000.0, 9300.0, 9.5, true)
	for i in 12:
		GameSession.note_sailing(9300.0 + i * 300.0, 9600.0 + i * 300.0, 9.5, true)
	var progress := GameSession.get_objective_progress()
	t.check(progress.is_completed(&"speed:sail_7") and progress.is_completed(&"speed:sail_9") and not progress.is_completed(&"speed:sail_12"),
		"[speed] a full hour at 9.5 kn under sail: seven and nine knots, not twelve")
	t.check(is_equal_approx(float(progress.get_record(GameSession.RECORD_BEST_HOUR).value), 9.5), "[speed] the best hour is kept (9.5 kn)")
	var after := GameSession.get_lifetime_renown()
	for i in 24:
		GameSession.note_sailing(12900.0 + i * 300.0, 13200.0 + i * 300.0, 9.5, true)
	t.check_eq(GameSession.get_lifetime_renown(), after, "[speed] sailing on fast pays nothing more (once only)")
	# Every milestone is reachable by a boat that can sail that fast.
	var fastest := 0.0
	var slowest := INF
	for id in BOATS:
		var max_kn := VesselCatalog.get_default().get_vessel(id).performance.max_sail_speed_kn
		fastest = maxf(fastest, max_kn)
		slowest = minf(slowest, max_kn)
	t.check(slowest > 7.0 and fastest > 12.0, "[speed] 7 kn is within every boat (slowest %.0f kn), 12 kn within the fastest (%.0f kn)" % [slowest, fastest])
	t.check(Simulation.STOP_NONE == &"", "(setup) simulation constants")


func _test_collection() -> void:
	var catalog := AchievementCatalog.get_default()
	var objectives := ObjectiveCatalog.get_default()
	t.check(catalog.achievements.size() >= 25 and catalog.achievements.size() <= 40, "[collection] a smaller collection: %d achievements" % catalog.achievements.size())
	t.check(catalog.get_categories().size() == catalog.categories.size(), "[collection] every category has achievements (%d)" % catalog.categories.size())
	var companion := catalog.achievements.filter(func(a: Dictionary) -> bool: return a.category == "companionship")
	t.check(companion.size() <= 4 and not companion.any(func(a: Dictionary) -> bool: return str(a.records).contains("pet")),
		"[collection] a handful of companion achievements, none for petting (%d)" % companion.size())
	var icons_ok := catalog.achievements.all(func(a: Dictionary) -> bool: return AchievementCatalog.icon_of(a, true) != null)
	t.check(icons_ok and AchievementCatalog.icon_of({"secret": true, "icon": "x"}, false) != null, "[collection] every achievement has its badge, secrets a sealed one")
	# An older save: records without place; renown past 250 before the record existed.
	var progress := ObjectiveProgress.new()
	progress.completed = {"first_voyage": {"count": 1, "first": 1.7776e9, "last_event": 1.7776e9},
		"distance_1000": {"count": 1, "first": 1.7778e9, "last_event": 1.7778e9}, "harbours_5": {"count": 1, "first": 1.7777e9, "last_event": 1.7777e9}}
	progress.lifetime_renown = 300
	progress.unpublished_renown = 300
	var errors: Array[String] = []
	var reloaded := ObjectiveProgress.from_dict(progress.to_dict(), errors)
	var list := catalog.collection(reloaded)
	var ids := list.map(func(e: Dictionary) -> String: return e.achievement.id)
	t.check(ids[0] == "distance_1000" and ids[1] == "first_voyage", "[collection] unlocked first, the most recent at the top (%s)" % [ids.slice(0, 4)])
	var first := list[1] as Dictionary
	t.check_eq(AchievementCatalog.describe_where(first.unlock), "Location not recorded", "[legacy] an older unlock: its date, but no invented place")
	var renown := list.filter(func(e: Dictionary) -> bool: return e.achievement.id == "renown_250")[0] as Dictionary
	t.check(not (renown.unlock as Dictionary).is_empty() and AchievementCatalog.describe_when(renown.unlock) == "Previously unlocked",
		"[legacy] renown passed before I024: unlocked, 'Previously unlocked'")
	t.check(not ids.has("harbours_5") and objectives.get_objective(&"harbours_5").retired, "[collection] filler (Harbour hopper) is retired from the collection")
	# A new unlock records when, where and on which boat.
	reloaded.award(&"heavy_weather", "Heavy weather", 40, 1.78e9, {"port": "kiel", "lon": 10.15, "lat": 54.33, "vessel": "starling_33"})
	var again := ObjectiveProgress.from_dict(reloaded.to_dict(), errors)
	var heavy := catalog.unlock_of(catalog.get_achievement("heavy_weather"), again)
	t.check(heavy.time == 1.78e9 and AchievementCatalog.describe_where(heavy).contains("Kiel") and AchievementCatalog.describe_boat(heavy) == "Wing 33",
		"[history] time, harbour and boat saved and loaded (%s, %s)" % [AchievementCatalog.describe_where(heavy), AchievementCatalog.describe_boat(heavy)])
	var at_sea := catalog.unlock_of(catalog.get_achievement("long_haul"), _with_award("passage_500", {"port": "", "lon": -20.5, "lat": 40.25, "vessel": "petrel_36"}))
	t.check_eq(AchievementCatalog.describe_where(at_sea), "At sea, 40.2°N 20.5°W", "[history] at sea: the position, no more precise than the game knows")
	t.check(again.lifetime_renown == 340 and again.is_completed(&"renown:250") == false, "[renown] totals kept; a milestone passed earlier is not back-dated")
	# Filters.
	var voyages := catalog.collection(again, "voyages")
	t.check(not voyages.is_empty() and voyages.all(func(e: Dictionary) -> bool: return e.achievement.category == "voyages"), "[collection] the category filter")


func _with_award(id: String, at: Dictionary) -> ObjectiveProgress:
	var progress := ObjectiveProgress.new()
	progress.award(StringName(id), id, 50, 1.79e9, at)
	return progress


# --- New game ---------------------------------------------------------------------------

func _test_new_game_menu() -> void:
	app.show_main_menu()
	await _settle()
	app.open_new_game_menu()
	await t.frames(3)
	var menu := app.modals.get_top() as NewGameMenu
	if not t.check(menu != null, "[new game] the dialog opens"):
		return
	await t.click(menu.find_child("ParrotButton", true, false) as Button)
	t.check(menu.companion_kind == CompanionState.KIND_PARROT and (menu.find_child("Preview", true, false) as ShipCompanion).is_sprite_mode(),
		"[new game] the parrot can be chosen, and is previewed")
	(menu.find_child("NameEdit", true, false) as LineEdit).text = "Kiwi"
	(menu.find_child("GenderPicker", true, false) as OptionButton).select(1)
	await t.screenshot("i024_new_game_parrot")
	await t.click(menu.find_child("StartButton", true, false) as Button)
	await _settle()
	var companion := GameSession.get_companion()
	t.check(companion.kind == CompanionState.KIND_PARROT and companion.name == "Kiwi" and companion.gender == CompanionState.GENDER_FEMALE,
		"[new game] the game starts with Kiwi, a female parrot")


# --- Animation --------------------------------------------------------------------------

func _test_animation() -> void:
	for kind in CompanionState.KINDS:
		GameSession.start_new_session(kind, Difficulty.STANDARD, "Pip")
		await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var pet := _companion()
		var clips := 0
		for name: StringName in pet.visual_set.get_pose_names():
			if pet.has_clip(name) and pet.visual_set.get_frames(name).size() > 1:
				clips += 1
		t.check(pet.is_sprite_mode() and clips >= 10, "[animation] the %s has %d animated clips" % [kind, clips])
		# Frames move on as time passes (idle breathing).
		pet.set_pose(CompanionVisualSet.POSE_RESTING, 999.0)
		var seen := {}
		for i in 20:
			pet.advance_behaviour(0.1)
			seen[pet.get_clip_texture()] = true
		t.check(seen.size() >= 3, "[animation] the %s's resting clip is animated (%d frames seen in 2 s)" % [kind, seen.size()])
		pet.pet()
		t.check(pet.clip == (CompanionVisualSet.POSE_PET if pet.has_clip(CompanionVisualSet.POSE_PET) else CompanionVisualSet.POSE_ALERT),
			"[animation] petting plays the %s's own response (%s)" % [kind, pet.clip])
		# Over half an hour it does more than rest and sleep.
		pet.set_pose(CompanionVisualSet.POSE_RESTING)
		var poses := {}
		for i in int(1800.0 / 0.5):
			pet.advance_behaviour(0.5)
			poses[pet.pose] = true
		t.check(poses.size() >= 4, "[animation] the %s's day has variety: %s" % [kind, poses.keys()])
	# Walking: the walk clip, facing the way it goes, at the stride's speed.
	GameSession.start_new_session(CompanionState.KIND_CAT)
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var cat := _companion()
	cat.facing = 1.0
	var from := cat.position
	cat._start_walk(from, from + Vector2(-60, 0))
	t.check(cat.clip == CompanionVisualSet.POSE_TURN, "[animation] walking the other way, the cat turns first")
	for i in 12:
		cat._process(0.05)
	t.check(cat.facing < 0.0 and cat.clip == CompanionVisualSet.POSE_WALK, "[animation] then walks, facing left (mirrored)")
	var at := cat.position
	cat._process(0.5)
	var speed := at.distance_to(cat.position) / 0.5
	t.check(absf(speed - cat.visual_set.walk_speed) < 0.5, "[animation] at the stride's speed (%.1f units/s), so the feet do not slide" % speed)
	await t.screenshot("i024_cat_walking")
	await t.wait_until(func() -> bool: return not cat.is_walking(), 10.0)
	t.check(cat.clip in [CompanionVisualSet.POSE_LIE_DOWN, CompanionVisualSet.POSE_RESTING], "[animation] arriving, it lies down (%s)" % cat.clip)


func _test_parrot_flight() -> void:
	GameSession.start_new_session(CompanionState.KIND_PARROT, Difficulty.STANDARD, "Kiwi")
	var area := await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var bird := _companion()
	var from := bird.position
	var to := bird.get_spot_position(&"settee")
	if from.distance_to(to) < 60.0:
		to = bird.get_spot_position(&"v_berth")
	bird._start_walk(from, to)
	t.check(bird.is_flying() and bird.clip == CompanionVisualSet.POSE_TAKEOFF, "[parrot] it takes off to fly to another perch")
	var lifted := 0.0
	var flapping := false
	for i in 40:
		bird._process(0.05)
		lifted = maxf(lifted, bird._lift)
		flapping = flapping or bird.clip == CompanionVisualSet.POSE_FLY
		if i == 10:
			await t.screenshot("i024_parrot_flight")
	t.check(flapping and lifted > 10.0, "[parrot] it flies (wings beating), up over the cabin (%.0f units)" % lifted)
	await t.wait_until(func() -> bool: return not bird.is_walking(), 10.0)
	t.check(bird.position.is_equal_approx(to) and bird._lift == 0.0, "[parrot] and lands on the perch, no teleport")
	var hop_to := bird.position + Vector2(20, 0)
	bird._start_walk(bird.position, hop_to)
	t.check(not bird.is_flying() and bird.clip == CompanionVisualSet.POSE_HOP, "[parrot] a short way: it hops")
	await t.wait_until(func() -> bool: return not bird.is_walking(), 5.0)
	t.check(bird.position.is_equal_approx(hop_to), "[parrot] along the perch")
	bird.set_pose(CompanionVisualSet.POSE_RESTING, 999.0)
	await t.screenshot("i024_parrot_perched")
	t.check(area != null, "(setup) cabin")


# --- Ashore and departure ---------------------------------------------------------------

func _test_shore_and_departure() -> void:
	for kind in [CompanionState.KIND_DOG, CompanionState.KIND_PARROT]:
		GameSession.start_new_session(kind, Difficulty.STANDARD, "Fido" if kind == CompanionState.KIND_DOG else "Kiwi")
		t.set_wind(200.0, 8.0)
		var deck := await _show(SessionState.AREA_EXTERIOR, &"start")
		var shore := deck.get_shore_access()
		if not t.check(shore != null and shore.is_active(), "(setup) the %s's harbour has a gangplank" % kind):
			continue
		deck.player.position = shore.get_landing_point() + Vector2(60, 10)
		await t.physics_frames(3)
		await t.wait_until(func() -> bool: return GameSession.is_companion_ashore(), 12.0)
		t.check(GameSession.is_companion_ashore(), "[ashore] the %s follows the Captain ashore" % kind)
		var pet := _companion()
		for i in 3000:  # its walk down the gangplank, at its own pace
			if not pet.is_walking():
				break
			pet._process(0.05)
		t.check(pet.visible and shore.is_off_the_boat(pet.position), "[ashore] and is there, on the pontoon")
		await t.screenshot("i024_%s_ashore" % kind)
		# Every way to cast off is refused.
		GameSession.plan_route_to(&"kiel")
		var refusal := GameSession.depart()
		t.check(refusal.contains("still ashore") and refusal.contains("Fido" if kind == CompanionState.KIND_DOG else "Kiwi") and not GameSession.is_underway(),
			"[departure] '%s'" % refusal)
		var wheel: Array = app.get_wheel_actions().map(func(a: Dictionary) -> StringName: return a.id)
		t.check(wheel.has(&"call_aboard"), "[departure] the action wheel offers to call it aboard")
		app.request_departure()
		await t.frames(3)
		var dialog := app.modals.get_top() as ConfirmDialog
		t.check(dialog != null, "[departure] setting sail asks to fetch it first")
		await t.screenshot("i024_departure_blocked")
		if dialog:
			dialog._answer(true)
			await t.frames(3)
		t.check(not GameSession.is_companion_ashore(), "[departure] called: it comes back aboard")
		app.modals.clear()
		t.check_eq(GameSession.depart(), "", "[departure] then the boat can cast off")
		await _settle()


# --- Waking -----------------------------------------------------------------------------

func _test_wake_by_berth() -> void:
	WeatherFixtures.use([])
	t.set_wind(200.0, 8.0)
	GameSession.start_new_session(CompanionState.KIND_DOG, Difficulty.STANDARD, "Fido")
	await _show(SessionState.AREA_EXTERIOR, &"start")
	var lines := {}
	for night in 6:
		app.sleep_for(8.0)
		await _settle()
		t.check_eq(GameSession.get_companion().spot, CompanionState.WAKE_SPOT, "(waking %d) by the berth" % night)
		for message in app.toasts.get_messages():
			if message.contains("Fido") or message.contains("berth"):
				lines[message] = true
		app.toasts.clear()
	var area := app.router.current_screen as BoatArea
	var dog := _companion()
	t.check(area.area_id == SessionState.AREA_INTERIOR and dog.visible and dog.position.is_equal_approx(dog.get_spot_position(CompanionState.WAKE_SPOT)),
		"[waking] the Captain wakes in the cabin with Fido by the berth")
	t.check(lines.size() >= 1 and lines.size() <= 5, "[waking] sometimes, not always, a small line (%d in 6 mornings): %s" % [lines.size(), lines.keys().slice(0, 2)])
	await t.screenshot("i024_waking_by_berth")


# --- Long passages ----------------------------------------------------------------------

func _test_passage_talk() -> void:
	GameSession.start_new_session(CompanionState.KIND_CAT, Difficulty.STANDARD, "Snowy", CompanionState.GENDER_FEMALE)
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	GameSession.plan_route_to(&"reykjavik")
	if GameSession.get_planned_route() == null:
		GameSession.plan_route_to(&"tromso")
	t.check_eq(GameSession.depart(), "", "(setup) a long passage")
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var said := 0
	# Six days at sea in 20-minute steps; real time is simulated, generously.
	for step in 6 * 72:
		Simulation.advance(1200.0, false)
		app.toasts.clear()
		var before: int = app._talk_count
		app._update_passage_talk(60.0)
		if app._talk_count > before:
			said += 1
			if said == 1:
				t.check(GameSession.get_game_time() - GameSession.get_voyage_departed_at() >= CompanionRemarks.PASSAGE_FIRST_HOURS * HOUR,
					"[talk] not in the first hours of a passage")
		if not GameSession.is_underway():
			break
	t.check(said >= 6 and said <= 18, "[talk] in six days at sea the Captain talks now and then (%d times), never a flood" % said)
	var flood := 0
	app._talk_real_wait = 0.0
	app._talk_next_at = 0.0
	app._update_passage_talk(0.1)
	for i in 30:
		app.toasts.clear()
		var before: int = app._talk_count
		app._update_passage_talk(1.0)
		flood += app._talk_count - before
	t.check_eq(flood, 0, "[talk] at most one remark per few real minutes, however fast time runs")
	# A reload never brings the next remark sooner.
	app._talk_voyage_at = -1.0
	app._update_passage_talk(0.1)
	t.check(app._talk_next_at >= GameSession.get_game_time() + CompanionRemarks.PASSAGE_GAP_HOURS[2] * HOUR - 1.0, "[talk] after loading, the next remark is a full gap away")
	# A remark with Snowy's response, for the screenshot.
	app._talk_next_at = 0.0
	app._talk_real_wait = 0.0
	app.toasts.clear()
	app._update_passage_talk(0.1)
	var shown: Array = app.toasts.get_messages()
	t.check(shown.size() == 1 and String(shown[0]).contains("“"), "[talk] the Captain's words: %s" % [shown])
	await t.screenshot("i024_long_passage_talk")
	# Not over a warning.
	app.toasts.clear()
	app.hud.show_warning("Gale warning")
	app._talk_next_at = 0.0
	app._talk_real_wait = 0.0
	var before: int = app._talk_count
	app._update_passage_talk(0.1)
	t.check_eq(app._talk_count, before, "[talk] never over a warning")
	app.hud.hide_warning()


# --- The laptop -------------------------------------------------------------------------

func _test_laptop() -> void:
	GameSession.start_new_session(CompanionState.KIND_CAT, Difficulty.STANDARD, "Snowy")
	GameSession.test_all_boats_owned = true
	for id in BOATS:
		GameSession.switch_vessel(id)
		var cabin := await _show(SessionState.AREA_INTERIOR, &"from_deck")
		var station := cabin.get_node_or_null(^"Layout/Stations/Work") as Interactable
		var prop := cabin.get_laptop()
		t.check(prop != null and station != null and prop.position.distance_to(station.position) < 80.0, "[laptop] the %s's table has the laptop, by the work station" % id)
		var laptop: LaptopView = app.open_laptop()
		await t.frames(3)
		t.check(laptop != null and laptop.get_screen_rect().encloses(Rect2(laptop.get_content().global_position - laptop.global_position, Vector2(10, 10))),
			"[laptop] on the %s it opens, its apps on the screen" % id)
		app.modals.clear()
	GameSession.test_all_boats_owned = false
	GameSession.switch_vessel(&"starling_33")
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	await t.screenshot("i024_laptop_on_table")
	# Some history to show.
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	var guard := 40
	while GameSession.is_underway() and guard > 0:
		guard -= 1
		Simulation.advance(12.0 * HOUR, true)
	await _show(SessionState.AREA_INTERIOR, &"from_deck")
	var laptop: LaptopView = app.open_laptop()
	await t.frames(4)
	await t.screenshot("i024_laptop_home")
	t.check(laptop.get_content().find_child("Tiles", true, false) != null, "[laptop] Home: renown, achievements and publications at a glance")
	laptop.show_app(LaptopView.APP_ACHIEVEMENTS)
	await t.frames(3)
	var shown: Array[String] = laptop.get_shown_ids()
	var grid: Node = laptop.get_content().find_child("Grid", true, false)
	var first_locked := -1
	var ordered := true
	for i in grid.get_child_count():
		var unlocked := bool(grid.get_child(i).get_meta(&"unlocked"))
		if not unlocked and first_locked < 0:
			first_locked = i
		elif unlocked and first_locked >= 0:
			ordered = false
	t.check(shown.size() == AchievementCatalog.get_default().achievements.size() and ordered and first_locked > 0,
		"[laptop] the collection: %d, unlocked first (%d), then the locked ones" % [shown.size(), first_locked])
	var locked: Node = grid.get_child(first_locked)
	var badge := locked.find_child("Badge", true, false) as TextureRect
	t.check(badge.material != null and locked.find_child("Lock", true, false) != null, "[laptop] a locked badge is greyed and carries a lock")
	await t.screenshot("i024_achievements_locked_grey")
	laptop.select_achievement(shown[0])
	await t.frames(2)
	var detail: Node = laptop.get_content().find_child("Detail", true, false)
	t.check((detail.find_child("When", true, false) as Label).text.contains("2026") and (detail.find_child("Where", true, false) as Label).text.contains("Kiel"),
		"[laptop] the detail: when and where (%s / %s)" % [(detail.find_child("When", true, false) as Label).text, (detail.find_child("Where", true, false) as Label).text])
	await t.screenshot("i024_achievement_detail")
	laptop.set_category("seamanship")
	await t.frames(3)
	t.check(laptop.get_shown_ids().all(func(id: String) -> bool: return AchievementCatalog.get_default().get_achievement(id).category == "seamanship"),
		"[laptop] the category filter")
	await t.screenshot("i024_achievement_categories")
	laptop.show_app(LaptopView.APP_HISTORY)
	await t.frames(3)
	t.check(laptop.get_content().find_child("Records", true, false) != null, "[laptop] voyage history")
	laptop.show_app(LaptopView.APP_PUBLICATIONS)
	await t.frames(2)
	var composer: PostcardMenu = laptop.open_postcards()
	await t.frames(3)
	t.check(composer.embedded and laptop.task == composer and laptop.get_screen_rect().has_point(composer.global_position - laptop.global_position + Vector2(4, 4)),
		"[laptop] the postcard composer opens on the screen")
	await t.screenshot("i024_laptop_postcards")
	var cards := GameSession.get_pastimes().postcards.size()
	composer.choose(0, 0, "classic")
	await t.click(composer.find_child("MakeButton", true, false))
	await t.wait_until(func() -> bool: return GameSession.get_pastimes().postcards.size() == cards + 1, 4.0)
	t.check_eq(GameSession.get_pastimes().postcards.size(), cards + 1, "[laptop] and a postcard is made and published from it")
	await _settle()
	# Esc: the task, then the laptop.
	laptop = app.open_laptop(LaptopView.APP_PUBLICATIONS)
	await t.frames(2)
	laptop.open_publish()
	await t.frames(2)
	app.modals.handle_back()
	await t.frames(2)
	t.check(app.modals.get_top() == laptop and laptop.task == null, "[laptop] Esc closes the open task first")
	app.modals.handle_back()
	await t.frames(2)
	t.check(app.modals.is_empty(), "[laptop] then the laptop")
	# Danish fits.
	SettingsManager.set_language(&"da")
	laptop = app.open_laptop(LaptopView.APP_ACHIEVEMENTS)
	await t.frames(4)
	await t.screenshot("i024_laptop_danish")
	t.check((laptop.find_child("Tab_achievements", true, false) as Button).text != "Achievements", "[laptop] in Danish")
	app.modals.clear()
	SettingsManager.set_language(&"en")
