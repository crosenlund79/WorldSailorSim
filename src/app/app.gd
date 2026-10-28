extends Node
## Application shell and flow coordinator (the project's main scene).
##
## App owns the persistent layers (current screen, HUD, modal menus,
## notifications) and connects them: menus and screens emit requests, App
## calls the services (GameSession, SaveManager) and asks the SceneRouter to
## show the right screen. It is also the single place that handles Esc, so no
## two layers ever react to the same key press.

@export var main_menu_scene: PackedScene
@export var world_map_scene: PackedScene
@export var pause_menu_scene: PackedScene
@export var settings_menu_scene: PackedScene
@export var save_load_menu_scene: PackedScene
@export var sleep_menu_scene: PackedScene
## New Game: choose the ship's companion.
@export var new_game_menu_scene: PackedScene
## The boatyard (in harbour only): browse and choose the vessel.
@export var boatyard_menu_scene: PackedScene
## Developer guides viewer (main menu, development builds only).
@export var dev_guides_menu_scene: PackedScene
## The provisions locker (cabin station) and the rescue report.
@export var provisions_menu_scene: PackedScene = preload("res://src/ui/provisions_menu.tscn")
@export var rescue_dialog_scene: PackedScene = preload("res://src/ui/rescue_dialog.tscn")
## Played on every button press, routed to the UI bus.
@export var ui_click_sound: AudioStream
## Engine loops (SFX bus): open air on deck, muffled below deck and at the chart.
@export var engine_sound: AudioStream = preload("res://assets/audio/placeholder/engine_hum.wav")
@export var engine_muffled_sound: AudioStream = preload("res://assets/audio/placeholder/engine_hum_muffled.wav")
## Secret achievement found (a soft chime), and a hat blowing away (a short
## sour little note). SFX bus, quiet.
@export var achievement_sound: AudioStream = preload("res://assets/audio/placeholder/achievement_chime.wav")
@export var hat_lost_sound: AudioStream = preload("res://assets/audio/placeholder/hat_sour_note.wav")

## Spawn marker in the cabin where the player wakes after sleeping.
const WAKE_SPAWN := &"v_berth"
const ENGINE_LOOP := &"engine"
const ENGINE_MUFFLED_LOOP := &"engine_muffled"
## Engine loudness on deck and inside (cabin, chart table), and the fade time.
const ENGINE_OUTSIDE_DB := -6.0
const ENGINE_INSIDE_DB := -16.0
const ENGINE_FADE_SECONDS := 1.5
const STORM_LOOP := WeatherAudio.STORM_LOOP
## Weather audio is checked once per real second (WeatherAudio).
const WEATHER_AUDIO_INTERVAL := 1.0
## Loudness of the achievement chime and the hat's sour note (SFX bus).
const ACHIEVEMENT_DB := -9.0
const HAT_LOST_DB := -10.0

@onready var router: SceneRouter = $SceneRouter
@onready var hud: Hud = $HudLayer/Hud
@onready var modals: ModalStack = $ModalLayer/ModalStack
@onready var toasts: Toasts = $ToastLayer/ToastArea/Toasts
@onready var _hud_layer: CanvasLayer = $HudLayer


var _toast_offsets := Vector2.ZERO
var _weather_audio_timer := 0.0
## Wind, water, rain, thunder and lightning aboard (Iteration 17).
var weather_audio: WeatherAudio
## True from a rescue until its dialog is closed: gameplay stays paused (also
## while the screen changes to the harbour underneath).
var _rescue_open := false
## The companion follows the captain between cabin and deck (Iteration 18):
## seconds until it goes, where to, and when it next wanders on deck.
var _follow_left := 0.0
var _follow_target: StringName = &""
var _wander_left := 60.0
const FOLLOW_UP_SECONDS := Vector2(2.5, 5.0)
const FOLLOW_DOWN_SECONDS := Vector2(4.0, 8.0)
const WANDER_SECONDS := Vector2(45.0, 100.0)


## While moored or safely at anchor, the companion comes up on deck a little
## after the captain and goes back down a little after them; on deck it
## moves to another of its places now and then. Underway or in poor weather
## it stays below (GameSession brings it down by itself).
func _update_companion_follow(delta: float) -> void:
	var area := router.current_screen as BoatArea
	if area == null or not GameSession.is_active() or router.is_busy() or GameSession.is_asleep() or get_tree().paused:
		return
	var companion := GameSession.get_companion()
	if companion == null:
		return
	var want := companion.area
	if area.area_id == SessionState.AREA_EXTERIOR and GameSession.companion_may_be_on_deck():
		want = CompanionState.AREA_DECK
	elif area.area_id == SessionState.AREA_INTERIOR:
		want = CompanionState.AREA_CABIN
	if want == companion.area:
		_follow_target = &""
		if want == CompanionState.AREA_DECK and area.area_id == SessionState.AREA_EXTERIOR and not GameSession.is_settled_at_anchor():
			_wander_left -= delta
			if _wander_left <= 0.0:
				_wander_left = randf_range(WANDER_SECONDS.x, WANDER_SECONDS.y)
				GameSession.set_companion_area(CompanionState.AREA_DECK, (companion.deck_spot + randi_range(1, 2)) % 3)
		return
	if _follow_target != want:
		_follow_target = want
		var delay := FOLLOW_UP_SECONDS if want == CompanionState.AREA_DECK else FOLLOW_DOWN_SECONDS
		_follow_left = randf_range(delay.x, delay.y)
	_follow_left -= delta
	if _follow_left <= 0.0:
		_follow_target = &""
		_wander_left = randf_range(WANDER_SECONDS.x, WANDER_SECONDS.y)
		GameSession.set_companion_area(want, randi_range(0, 2))


## An anchorage was reached; its prompt waits for a free moment (Iteration 18).
var _anchorage_prompt_due := false
## A VHF call waiting to be shown (I019), or {}.
var _pending_vhf := {}
## Real seconds left for the captain to reach the rod after a bite (counts
## only while playing, not while a menu is open), Iteration 13.
var _bite_wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_toast_offsets = Vector2(toasts.offset_left, toasts.offset_right)
	$Screen.process_mode = Node.PROCESS_MODE_PAUSABLE
	for vessel in VesselCatalog.get_default().vessels:
		for problem in vessel.validate():
			push_error("Vessel '%s': %s" % [vessel.id, problem])
	get_tree().node_added.connect(_on_node_added)
	modals.stack_changed.connect(_on_modal_stack_changed)
	modals.notification_requested.connect(notify)
	hud.menu_requested.connect(open_pause_menu)
	hud.chart_requested.connect(open_chart_from_warning)
	hud.save_requested.connect(open_save_menu)
	GameSession.notice.connect(notify)
	Simulation.weather_warning.connect(_on_weather_warning)
	Simulation.traffic_alert.connect(_on_traffic_alert)
	Simulation.vhf_call.connect(_on_vhf_call)
	Simulation.arrived.connect(_on_arrived)
	GameSession.rescued.connect(_on_rescued)
	GameSession.voyage_logged.connect(_on_voyage_logged)
	GameSession.renown_awarded.connect(_on_renown_awarded)
	GameSession.hat_warning.connect(_on_hat_warning)
	GameSession.hat_lost.connect(_on_hat_lost)
	GameSession.fish_bite.connect(_on_fish_bite)
	GameSession.anchorage_reached.connect(_on_anchorage_reached)
	GameSession.anchor_alarm.connect(_on_anchor_alarm)
	GameSession.anchor_moment.connect(_on_anchor_moment)
	GameSession.fishing_warning.connect(func(warning: Dictionary) -> void: notify(String(warning.text)))
	# Test weather never outlives the game it was made in.
	GameSession.session_started.connect(DevTools.on_session_changed)
	GameSession.state_replaced.connect(DevTools.on_session_changed)
	GameSession.session_ended.connect(DevTools.on_session_changed)
	GameSession.provisions_warning.connect(func(_level: int, text: String) -> void: notify(text))
	router.screen_changed.connect(_on_screen_changed)
	weather_audio = WeatherAudio.new()
	weather_audio.name = "WeatherAudio"
	weather_audio.lighting_provider = func() -> BoatLighting:
		var area := router.current_screen as BoatArea
		return area.get_lighting() if area else null
	add_child(weather_audio)
	GameSession.propulsion_changed.connect(func(_mode: StringName) -> void: update_engine_audio())
	GameSession.state_replaced.connect(update_engine_audio)
	_hud_layer.hide()
	Simulation.passage_started.connect(_on_passage_started)
	day_night_watch = DayNightWatch.new()
	day_night_watch.name = "DayNightWatch"
	day_night_watch.app = self
	add_child(day_night_watch)
	var academy_layer := UiScaleLayer.new()
	academy_layer.name = "AcademyLayer"
	academy_layer.layer = 15
	add_child(academy_layer)
	academy = AcademyGuide.new()
	academy.name = "AcademyGuide"
	academy.app = self
	academy_layer.add_child(academy)
	show_main_menu()
	# Cozy Polish: the game's own loading screen over the menu, once per launch.
	if LoadingScreen.wanted():
		loading_screen = LoadingScreen.new()
		loading_screen.name = "LoadingScreen"
		add_child(loading_screen)


## The start-up loading screen while it is up (null afterwards).
var loading_screen: LoadingScreen
## The Captain's Academy card (I022): the First Voyage and the tips.
var academy: AcademyGuide


func is_loading() -> bool:
	return is_instance_valid(loading_screen) and not loading_screen.is_done()


func _process(delta: float) -> void:
	_weather_audio_timer -= delta
	if _weather_audio_timer <= 0.0:
		_weather_audio_timer = WEATHER_AUDIO_INTERVAL
		update_weather_audio()
	_update_bite_wait(delta)
	_update_companion_follow(delta)
	if _anchorage_prompt_due and is_in_gameplay() and modals.is_empty() and not router.is_busy() and not GameSession.is_asleep():
		_anchorage_prompt_due = false
		show_anchorage_prompt()
	if not _pending_vhf.is_empty() and is_in_gameplay() and modals.is_empty() and not router.is_busy() and not GameSession.is_asleep() \
			and not is_instance_valid(voyage_map):
		var call := _pending_vhf
		_pending_vhf = {}
		show_vhf_dialog(call)


## Weather sounds follow the weather at the boat (the same weather model as
## everything else): see WeatherAudio. Aboard (deck, cabin) and at the chart
## (inside); nothing in the menus.
func update_weather_audio() -> void:
	var area := router.current_screen as BoatArea
	var place := ""
	if GameSession.is_active() and area != null:
		place = "deck" if area.area_id == SessionState.AREA_EXTERIOR else "inside"
	elif GameSession.is_active() and router.current_screen is WorldMap:
		place = "inside"
	if place.is_empty():
		weather_audio.update(null, "", false, [])
		return
	var storms: Array = Simulation.get_storms_near(GameSession.get_vessel_position()) if GameSession.is_underway() else []
	weather_audio.update(Simulation.get_weather_at_vessel(), place, GameSession.is_underway(), storms)


func is_storm_audio_playing() -> bool:
	return AudioManager.is_loop_playing(STORM_LOOP)


func _is_on_deck() -> bool:
	var area := router.current_screen as BoatArea
	return area != null and area.area_id == SessionState.AREA_EXTERIOR


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and (event as InputEventKey).keycode == KEY_F8:
		# Developer view: show every interaction area (never in normal play).
		if DevTools.is_enabled():
			get_viewport().set_input_as_handled()
			set_interaction_debug(not Interactable.debug_show_areas)
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and (event as InputEventKey).keycode == KEY_F10:
		if DevTools.is_enabled():
			get_viewport().set_input_as_handled()
			toggle_dev_tests()
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and (event as InputEventKey).keycode == KEY_F5:
		get_viewport().set_input_as_handled()
		quicksave()
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and (event as InputEventKey).keycode == KEY_F9:
		get_viewport().set_input_as_handled()
		quickload()
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and (event as InputEventKey).keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		toggle_handbook()
		return
	if event.is_action_pressed(&"captains_log") and not event.is_echo():
		get_viewport().set_input_as_handled()
		toggle_captains_log()
		return
	if event.is_action_pressed(&"captains_hat") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			toggle_hat()
		return
	if event.is_action_pressed(&"action_wheel") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			open_action_wheel()
		return
	if event.is_action_pressed(&"sail_trim") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			open_sail_trim()
		return
	if event.is_action_pressed(&"reel_in") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			open_fishing()
		return
	if event.is_action_pressed(&"chartplotter") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			toggle_chartplotter()
		return
	if not event.is_action_pressed(&"pause") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if router.is_busy():
		return
	if not modals.is_empty():
		modals.handle_back()
	elif router.current_screen is BoatArea:
		open_pause_menu()
	elif router.current_screen and router.current_screen.has_method(&"handle_back"):
		router.current_screen.handle_back()


func notify(text: String) -> void:
	toasts.show_message(text)


## Life at anchor (0.102b): a quiet line, shown a little longer than a notice.
## The wake-up line is shown by sleep_for() after the waking notice.
func _on_anchor_moment(kind: String, text: String) -> void:
	if kind != "wake" and not text.is_empty():
		toasts.show_message(text, ANCHOR_MOMENT_SECONDS)

const ANCHOR_MOMENT_SECONDS := 5.5


func is_in_gameplay() -> bool:
	return GameSession.is_active() and router.current_screen is BoatArea


# --- Main flow -------------------------------------------------------------------

func show_main_menu() -> void:
	modals.clear()
	GameSession.end_session()
	AudioManager.stop_ambience()
	AudioManager.stop_music()
	update_engine_audio()
	router.change_screen(main_menu_scene, _connect_main_menu)


## New Game asks for the ship's companion (cat or dog) first.
func open_new_game_menu() -> void:
	if not modals.is_empty() or router.is_busy():
		return
	var menu := new_game_menu_scene.instantiate() as NewGameMenu
	menu.start_requested.connect(start_new_game)
	modals.push(menu)


func start_new_game(companion_kind: StringName = CompanionState.DEFAULT_KIND, level: StringName = Difficulty.STANDARD) -> void:
	modals.clear()
	GameSession.start_new_session(companion_kind, level)
	_show_current_boat_area()
	if AcademyGuide.enabled and Academy.first_voyage_state() == Academy.NEVER_OFFERED:
		offer_first_voyage.call_deferred()


# --- The Captain's Academy (I022) ----------------------------------------------------

## The first new game on this computer asks once: a First Voyage, or not?
## (Loading a saved game never asks.) Either answer is remembered; the
## Handbook can begin it again.
func offer_first_voyage() -> void:
	await get_tree().process_frame
	while router.is_busy() or is_loading():
		await get_tree().process_frame
	if not is_in_gameplay():
		return
	var begin: bool = await modals.confirm(Loc.t("Your first voyage"),
		Loc.t("Would you like a short First Voyage? A small card shows one step at a time, from walking about to setting sail, and you can skip it whenever you like. The Captain's Handbook (%s) is always there either way.") % Academy.key("handbook"),
		Loc.t("Begin"), Loc.t("Skip"))
	if begin:
		academy.begin_first_voyage()
	else:
		Academy.skip_first_voyage()


## The Captain's Handbook, at `page` (or its first page). Opens over the
## pause menu too; anywhere else only when nothing is open.
func open_handbook(page := "") -> HandbookMenu:
	if router.is_busy() or (not modals.is_empty() and not modals.get_top() is PauseMenu):
		return null
	var menu := HandbookMenu.new()
	menu.first_voyage_requested.connect(func() -> void:
		modals.clear()
		academy.begin_first_voyage())
	modals.push(menu)
	if not page.is_empty():
		menu.show_page(page)
	return menu


## F1: opens the Handbook, or closes it when it is on top.
func toggle_handbook() -> void:
	if modals.get_top() is HandbookMenu:
		modals.get_top().close()
	else:
		open_handbook()


func continue_game() -> void:
	var slot := SaveManager.get_most_recent_valid_slot()
	if slot == 0:
		notify(Loc.t("There is no saved game to continue."))
		return
	load_slot(slot)


## Loads a slot, asking first if the current session has unsaved progress.
func request_load(slot: int) -> void:
	if GameSession.has_unsaved_changes():
		var proceed: bool = await modals.confirm(Loc.t("Load this game?"),
			Loc.t("Progress since your last save will be lost."), "Load")
		if not proceed:
			return
	load_slot(slot)


## Validates the slot completely before anything changes; a failed load
## leaves the current session and screen exactly as they were.
func load_slot(slot: int) -> void:
	var result := SaveManager.load_from_slot(slot)
	if not result.is_ok():
		notify(Loc.t("Could not load %s. %s") % [SaveManager.slot_name(slot), result.error])
		return
	modals.clear()
	GameSession.replace_state(result.state)
	notify(Loc.t("Loaded %s.") % SaveManager.slot_name(slot))
	_show_current_boat_area()


# --- Quicksave and quickload (Iteration 17) ------------------------------------------
# F5 writes the quicksave file (never a manual slot), aboard, with no window
# open and no transition or Long Passage running; F9 loads it, asking first
# when there is unsaved progress. A key held down or pressed twice within
# QUICK_COOLDOWN_MSEC does nothing more. The save is the same verified write
# (temporary file, read back, previous kept as backup) as a manual save.

const QUICK_COOLDOWN_MSEC := 1000
var _last_quick_msec := -100000


## Why a quicksave cannot be taken now ("" when it can).
func quicksave_blocker() -> String:
	if not GameSession.is_active():
		return Loc.t("There is no game to save.")
	if router.is_busy() or not router.current_screen is BoatArea:
		return Loc.t("You can quicksave aboard the boat.")
	if not modals.is_empty():
		return Loc.t("Close the open window to quicksave.")
	if Simulation.is_passage_running():
		return Loc.t("Stop the Long Passage to quicksave.")
	return ""


func quicksave() -> void:
	if Time.get_ticks_msec() - _last_quick_msec < QUICK_COOLDOWN_MSEC:
		return
	_last_quick_msec = Time.get_ticks_msec()
	var blocker := quicksave_blocker()
	if not blocker.is_empty():
		notify(blocker)
		return
	var err := SaveManager.save_to_slot(SaveManager.QUICKSAVE_SLOT, GameSession.get_state_snapshot())
	if err == OK:
		GameSession.mark_saved()
		notify(Loc.t("Quicksaved (F9 to load)."))
	else:
		notify(Loc.t("Quicksave failed (%s). The previous quicksave was kept.") % error_string(err))


func quickload() -> void:
	if Time.get_ticks_msec() - _last_quick_msec < QUICK_COOLDOWN_MSEC or router.is_busy() or not modals.is_empty():
		return
	_last_quick_msec = Time.get_ticks_msec()
	if not SaveManager.get_slot_info(SaveManager.QUICKSAVE_SLOT).is_loadable():
		notify(Loc.t("No quicksave yet. Press F5 aboard to quicksave."))
		return
	if GameSession.is_active() and GameSession.has_unsaved_changes():
		var proceed: bool = await modals.confirm(Loc.t("Load the quicksave?"),
			Loc.t("Progress since your last save will be lost."), "Load")
		if not proceed:
			return
	load_slot(SaveManager.QUICKSAVE_SLOT)


func request_main_menu() -> void:
	if GameSession.has_unsaved_changes():
		var proceed: bool = await modals.confirm(Loc.t("Return to main menu?"),
			Loc.t("Progress since your last save will be lost."), Loc.t("Leave without saving"))
		if not proceed:
			return
	show_main_menu()


func quit_game() -> void:
	# Stop sounds (e.g. this button's click) and give the audio thread a moment
	# to release them before the engine shuts down.
	AudioManager.stop_all()
	await get_tree().create_timer(0.1, true).timeout
	get_tree().quit()


## Copies the saves from Next Harbor (the game's earlier name) after asking.
## Only copies: the originals are never changed, occupied slots never
## overwritten (see LegacySaves).
func import_legacy_saves() -> void:
	var count := LegacySaves.count_importable()
	if count == 0 or not modals.is_empty():
		return
	var go: bool = await modals.confirm(Loc.t("Import Next Harbor saves?"),
		Loc.n("%d save from Next Harbor, the game's earlier name, will be copied into free slots. The originals stay where they are, and no slot that is in use is overwritten.",
			"%d saves from Next Harbor, the game's earlier name, will be copied into free slots. The originals stay where they are, and no slot that is in use is overwritten.", count) % count, "Import")
	if not go:
		return
	notify(LegacySaves.describe(LegacySaves.import_all()))
	var menu := router.current_screen as MainMenu
	if menu:
		menu.refresh_saves()


# --- Boat and chart ----------------------------------------------------------------

func open_chart() -> void:
	router.change_screen(world_map_scene, _connect_world_map)


# --- Action wheel and chartplotter (Iteration 17) --------------------------------------

## The chartplotter on deck (shown underway): on or off.
func toggle_chartplotter() -> void:
	ChartPlotter.shown = not ChartPlotter.shown
	if ChartPlotter.shown and not (GameSession.is_underway() and _is_on_deck()):
		notify(Loc.t("The chartplotter shows on deck while underway."))


## The actions that make sense here, for the action wheel:
## [{"id", "label", "action"}, plus "checked" (a Callable read when the wheel
## opens) for the on/off ones]. Existing actions only.
func get_wheel_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var area := router.current_screen as BoatArea
	if area == null:
		return actions
	var add := func(id: StringName, label: String, action: Callable) -> void:
		actions.append({"id": id, "label": label, "action": action})
	var go_label := Loc.t("Go below") if area.area_id == SessionState.AREA_EXTERIOR else Loc.t("Go on deck")
	# A fish on the line comes first (Iteration 18).
	if not GameSession.get_pending_bite().is_empty():
		add.call(&"reel_in", Loc.t("Reel in!"), func() -> void: open_fishing.call_deferred())
	if area.area_id == SessionState.AREA_INTERIOR:
		add.call(&"sleep", "Sleep", open_sleep_menu)
		add.call(&"dream_map", Loc.t("World map"), open_dream_map)
		add.call(&"chart", Loc.t("Chart table"), open_chart)
		add.call(&"provisions", "Provisions", open_provisions)
		add.call(&"cabin_home", "Make it home", func() -> void: open_cabin_home.call_deferred())
		add.call(&"postcards", Loc.t("Write a postcard"), func() -> void: open_postcards.call_deferred())
		add.call(&"game_dev", Loc.t("Work on your little game"), func() -> void: open_game_dev.call_deferred())
	else:
		if GameSession.is_underway():
			# On/off items show a check mark read from the setting itself (Cozy Polish).
			add.call(&"chartplotter", Loc.t("Chart plotter"), toggle_chartplotter)
			actions.back().checked = func() -> bool: return ChartPlotter.shown
			add.call(&"sailing_panel", Loc.t("Sailing details"), func() -> void: SailingPanel.collapsed = not SailingPanel.collapsed)
			actions.back().checked = func() -> bool: return not SailingPanel.collapsed
			add.call(&"radar", "Radar", func() -> void: RadarPanel.shown = not RadarPanel.shown)
			actions.back().checked = func() -> bool: return RadarPanel.shown
			if not GameSession.is_anchored():
				add.call(&"sail_trim", Loc.t("Trim sails"), func() -> void: open_sail_trim.call_deferred())
			if GameSession.is_anchored() or GameSession.anchoring_refusal() == "" or GameSession.is_holding_at_anchorage():
				add.call(&"anchor", "Anchor", func() -> void: open_anchor())
			if GameSession.is_holding_at_anchorage():
				add.call(&"sail_on", Loc.t("Sail on from the anchorage"), func() -> void:
					var error := GameSession.sail_on_from_anchorage()
					notify(Loc.t("Sailing on along the course.") if error == "" else error))
		elif GameSession.get_planned_route() != null:
			add.call(&"set_sail", Loc.t("Set sail"), request_departure)
		add.call(&"chart", "Charts", open_chart)
		if GameSession.get_pending_bite().is_empty():
			add.call(&"fishing", Loc.t("Fishing rod"), func() -> void: open_fishing.call_deferred())
	add.call(&"go", go_label, func() -> void:
		if router.current_screen == area and not router.is_busy():
			area.begin_exit()
			_on_area_change_requested(area.companionway_target_area, area.companionway_target_spawn))
	# The coffee mug (Cozy Polish): set down here, take it, or drink up.
	if GameSession.is_carrying_coffee():
		add.call(&"coffee_down", Loc.t("Coffee in the holder") if area.area_id == SessionState.AREA_EXTERIOR else Loc.t("Set coffee down"),
			func() -> void: notify(GameSession.put_coffee_down()))
		add.call(&"coffee_finish", Loc.t("Finish the coffee"), func() -> void: notify(GameSession.finish_coffee()))
	elif GameSession.coffee_waits_here():
		add.call(&"coffee_take", Loc.t("Take your coffee"), func() -> void: notify(GameSession.pick_up_coffee()))
	add.call(&"log", "log" if not GameSession.is_underway() else Loc.t("Captain's Log"), toggle_captains_log)
	return actions


## Sail trim (Iteration 18): underway, at sea (not at anchor).
func open_sail_trim() -> SailTrimPanel:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	if not _hand_free():
		return null
	if not GameSession.is_underway() or GameSession.is_anchored():
		notify(Loc.t("Sail trim is for sailing: set sail first.") if not GameSession.is_underway() else Loc.t("At anchor the sails are down."))
		return null
	var panel := SailTrimPanel.new()
	modals.push(panel)
	return panel


func open_action_wheel() -> ActionWheel:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	var area := router.current_screen as BoatArea
	var wheel := ActionWheel.new()
	var title := Loc.t("In the cabin") if area.area_id == SessionState.AREA_INTERIOR else (
		Loc.t("At anchor") if GameSession.is_anchored() else (Loc.t("At the helm") if GameSession.is_underway() else Loc.t("On deck")))
	wheel.setup(get_wheel_actions(), title)
	modals.push(wheel)
	return wheel


## The cabin's framed world map: the Dreamer's Map (WorldMap.MODE_DREAM).
func open_dream_map() -> void:
	router.change_screen(world_map_scene, func(map: WorldMap) -> void:
		map.mode = WorldMap.MODE_DREAM
		_connect_world_map(map)
		map.plan_requested.connect(open_chart_for_port))


## From the Dreamer's Map to the navigation station's chart, with the harbour
## selected there (the course is planned with the same router as always).
func open_chart_for_port(port_id: StringName) -> void:
	if router.is_busy():
		return
	router.change_screen(world_map_scene, func(map: WorldMap) -> void:
		_connect_world_map(map)
		map.select_port.call_deferred(port_id))


func open_chart_from_warning() -> void:
	if is_in_gameplay() and modals.is_empty() and not router.is_busy():
		router.change_screen(world_map_scene, func(map: WorldMap) -> void:
			_connect_world_map(map)
			map.show_tab.call_deferred(WorldMap.TAB_WEATHER))


## Leaves the chart. Unapplied course changes are only discarded after asking.
func close_chart() -> void:
	var map := router.current_screen as WorldMap
	if map and map.has_unapplied_changes():
		var leave: bool = await modals.confirm(Loc.t("Leave the chart?"),
			Loc.t("Your course changes have not been applied. The current course stays as it is."),
			Loc.t("Discard changes"), Loc.t("Keep editing"))
		if not leave:
			return
	_show_current_boat_area()


# --- Voyage ------------------------------------------------------------------------

## Asks for confirmation, then sets sail on the planned route.
func request_departure() -> void:
	var route := GameSession.get_planned_route()
	if route == null or not route.has_path():
		notify(Loc.t("Plot a course at the chart table before setting sail."))
		return
	var catalog := PortCatalog.get_default()
	var estimate := Simulation.estimate_route_seconds(route.path)
	var waypoints := "" if route.waypoints.is_empty() else Loc.n(" via %d waypoint", " via %d waypoints",
		route.waypoints.size()) % route.waypoints.size()
	# Passage Readiness (Iteration 14): advice in the question, never a refusal.
	var readiness := PassageReadiness.assess(route.path)
	SessionLog.write("readiness", {"to": String(route.destination_port_id), "level": readiness.level,
		"topics": readiness.items.filter(func(i: Dictionary) -> bool: return int(i.level) > 0).map(func(i: Dictionary) -> String: return String(i.topic))})
	var go: bool = await modals.confirm(Loc.t("Set sail for %s?") % catalog.get_display_name(route.destination_port_id),
		Loc.t("%d nm%s, about %s with the expected wind (estimate).\n\n%s") % [roundi(route.get_distance_nm()), waypoints,
			Simulation.format_duration(estimate), PassageReadiness.describe(readiness, 3)], Loc.t("Set sail"))
	if not go:
		return
	var error := GameSession.depart()
	notify(error if not error.is_empty() else Loc.t("Underway to %s. The autopilot holds the course.") %
		catalog.get_display_name(route.destination_port_id))


## In port the helm sets sail; underway it checks the sail configuration: a
## fresh assessment through the propulsion controller (never a manual engine
## switch; the controller's minimum times still apply).
func _on_helm_requested() -> void:
	if GameSession.is_anchored():
		notify(Loc.t("At anchor. Raise the anchor at the windlass on the foredeck before sailing on."))
	elif GameSession.is_underway():
		notify(describe_reassessment(Simulation.reassess_propulsion()))
	else:
		request_departure()


## Player-facing result of a helm check.
static func describe_reassessment(result: Dictionary) -> String:
	if result.is_empty():
		return ""
	var after: PropulsionState = result.after
	var profile := GameSession.get_vessel_profile()
	var conditions := Loc.format("%.1f kn possible under sail in %d kn of wind", [after.potential_kn, roundi(after.wind_speed_kn)])
	if result.changed:
		if after.sails_set():
			return Loc.t("Sailing conditions favourable (%s). Sails set%s, engine stopped.") % [conditions,
				Loc.t(" with the spinnaker") if after.spinnaker else ""]
		if after.engine_reason == PropulsionState.REASON_STALL:
			return Loc.t("Becalmed or head to wind (%s). Sails furled, engine started.") % conditions
		return Loc.t("Insufficient sailing performance (%s). Sails furled, engine started.") % conditions
	if after.sails_set():
		if after.potential_kn < profile.engine_start_below_kn:
			return Loc.t("Light wind (%s). The sails stay up a little longer; the engine starts if it does not improve.") % conditions
		return Loc.t("Sails are drawing well (%s). No change needed.") % conditions
	if after.potential_kn > profile.engine_stop_above_kn:
		return Loc.t("The wind is filling in (%s). The engine runs a little longer before the sails go up.") % conditions
	return Loc.t("Insufficient sailing performance (%s). Continuing under engine.") % conditions


## Opens the sleep dialog from the berth (cabin) or the chart's Sleep button.
## Both use the same dialog and the same Simulation.sleep().
func open_sleep_menu() -> void:
	if not GameSession.is_active() or not modals.is_empty() or router.is_busy():
		return
	var map := router.current_screen as WorldMap
	if not (router.current_screen is BoatArea or map):
		return
	if map and map.has_unapplied_changes():
		notify(Loc.t("Apply or discard your course changes before sleeping."))
		return
	var menu := sleep_menu_scene.instantiate() as SleepMenu
	menu.sleep_requested.connect(sleep_for)
	modals.push(menu)


## Sleeps by advancing the normal simulation; stops early on arrival or a
## weather warning (those report themselves through their own signals).
## Sleeping is an explicit advance of time, so it also works while the game is
## paused, and the pause stays as it was afterwards (time does not start
## running continuously on waking).
##
## The Well-Run Ship: with a screen, the game first fades to black and shows
## the date and the clock (TimePassage); the simulation runs once under the
## black (one advance, not frame by frame), the clock then counts the hours
## slept, and the game fades back in the new light. Without a screen (tests)
## everything happens at once.
func sleep_for(hours: float) -> void:
	modals.clear()
	if is_instance_valid(time_passage):
		return  # already sleeping
	if not TimePassage.is_shown():
		_after_sleep(hours, _sleep_now(hours))
		return
	var outcome := {}
	time_passage = TimePassage.new()
	add_child(time_passage)
	time_passage.play_sleep(GameSession.get_game_time(), func() -> float:
		outcome.result = _sleep_now(hours)
		return GameSession.get_game_time(),
		func() -> String: return _wake_reason(outcome.result))
	await time_passage.finished
	_on_modal_stack_changed(modals.depth())
	_after_sleep(hours, outcome.result)


## The sleep itself: the simulation, and the captain back in the berth (with
## the light and the interface already right for the new hour).
func _sleep_now(hours: float) -> Dictionary:
	GameSession.begin_sleep()
	var result := Simulation.sleep(hours)
	var wake_line := GameSession.end_sleep(result.elapsed_seconds)
	SessionLog.write("sleep", {"hours": hours, "slept_h": snappedf(result.elapsed_seconds / 3600.0, 0.01), "stopped_by": String(result.stopped_by),
		"anchored": GameSession.is_anchored()})
	if result.stopped_by != Simulation.STOP_RESCUE:
		_wake_in_berth()
	if TimePassage.is_shown():
		snap_light()
	return {"result": result, "wake_line": wake_line}


## One short line on the black when the captain woke early.
static func _wake_reason(outcome: Dictionary) -> String:
	match (outcome.result as Simulation.AdvanceResult).stopped_by:
		Simulation.STOP_WARNING:
			return Loc.t("Woken by a weather warning")
		Simulation.STOP_BITE:
			return Loc.t("Woken by the bell on the rod")
		Simulation.STOP_ANCHOR:
			return Loc.t("Woken by the anchor alarm")
		Simulation.STOP_ARRIVAL:
			return Loc.t("Woken: the boat has arrived")
		Simulation.STOP_ANCHORAGE:
			return Loc.t("Woken at the anchorage")
		Simulation.STOP_TRAFFIC:
			return Loc.t("Woken by a traffic warning")
		Simulation.STOP_VHF:
			return Loc.t("Woken by a call on the radio")
	return ""


func _after_sleep(_hours: float, outcome: Dictionary) -> void:
	var result: Simulation.AdvanceResult = outcome.result
	var wake_line: String = outcome.wake_line
	if result.stopped_by == Simulation.STOP_RESCUE:
		return  # the rescue has already brought the player ashore and reports itself
	var slept := Simulation.format_duration(result.elapsed_seconds)
	var now := Simulation.format_game_time(GameSession.get_game_time())
	var still_paused := Loc.t("  Time is still paused.") if GameSession.is_paused() else ""
	match result.stopped_by:
		Simulation.STOP_WARNING:
			notify(Loc.t("You were woken after %s by a weather warning. It is %s.%s") % [slept, now, still_paused])
		Simulation.STOP_BITE:
			notify(Loc.t("You were woken after %s by the bell on the rod: a fish is on! Go up to the rod. It is %s.%s") % [slept, now, still_paused])
		Simulation.STOP_ANCHOR:
			notify(Loc.t("You were woken after %s by the anchor alarm: %s. Go up to the windlass. It is %s.%s") % [slept,
				AnchorSite.holding_text(GameSession.get_anchor().holding).to_lower(), now, still_paused])
		Simulation.STOP_ARRIVAL:
			notify(Loc.t("You were woken after %s: the boat has arrived. It is %s.%s") % [slept, now, still_paused])
		Simulation.STOP_ANCHORAGE:
			notify(Loc.t("You were woken after %s: we've arrived at our anchorage. It is %s.%s") % [slept, now, still_paused])
		Simulation.STOP_TRAFFIC:
			notify(Loc.t("You were woken after %s by a traffic warning. Go up on deck and keep a lookout. It is %s.%s") % [slept, now, still_paused])
		Simulation.STOP_VHF:
			notify(Loc.t("You were woken after %s by a call for assistance on the radio. It is %s.%s") % [slept, now, still_paused])
		_:
			notify(Loc.t("You slept %s. It is %s.%s") % [slept, now, still_paused])
	if not wake_line.is_empty():
		toasts.show_message(wake_line, ANCHOR_MOMENT_SECONDS)


## After a jump in time (sleep, a dawn or dusk passed under the black): the
## interface and the boat's light take the new hour at once, instead of
## easing over the next seconds in view.
func snap_light() -> void:
	UiTheme.set_blend(UiTheme._target_blend(), true)
	var area := router.current_screen as BoatArea
	var lighting := area.get_node_or_null(^"Lighting") if area else null
	if lighting and lighting.has_method(&"update_now"):
		lighting.update_now()


## Long Passage as a journey (The Well-Run Ship): the voyage map while the
## passage clock runs (not in tests, like the time passages).
var voyage_map: VoyageMap
var _dock_after_map := false


func _on_passage_started(_rate: float) -> void:
	if not TimePassage.is_shown() or is_instance_valid(voyage_map) or not GameSession.is_underway():
		return
	voyage_map = VoyageMap.new()
	voyage_map.name = "VoyageMap"
	voyage_map.screen = router.current_screen
	voyage_map.hud_layer = _hud_layer
	voyage_map.hud = hud
	voyage_map.closed.connect(_on_voyage_map_closed)
	add_child(voyage_map)


func _on_voyage_map_closed() -> void:
	voyage_map = null
	if _dock_after_map:
		_dock_after_map = false
		show_docking_arrival.call_deferred()


## The time passage on screen now (sleep, dawn or dusk), or null.
var time_passage: TimePassage
## Watches for dawn and dusk in ordinary play (The Well-Run Ship).
var day_night_watch: DayNightWatch


## True when a dawn or dusk card may cover the game: aboard or at the chart,
## no menu, no screen change, nothing else passing time on screen.
func can_show_time_passage() -> bool:
	return GameSession.is_active() and (router.current_screen is BoatArea or router.current_screen is WorldMap) \
		and modals.is_empty() and not router.is_busy() and not _rescue_open and not is_instance_valid(time_passage)


## Dawn or dusk (DayNightWatch): the date card, and under the black the
## twilight passes with the normal simulation (from `from` to `until`, game
## time; it stops early for an event, which then reports itself as always).
func play_new_light(from: float, until: float, evening: bool) -> void:
	time_passage = TimePassage.new()
	add_child(time_passage)
	time_passage.play_card(until, evening, func() -> void:
		var result := Simulation.advance(until - from, true)
		# As in accelerated time: something that wants the captain brings the
		# clock back to normal speed.
		if (not result.warnings.is_empty() or result.hat_warned or result.bite or result.anchor_alarm != "" or result.anchorage
				or result.stopped_by != Simulation.STOP_NONE) and GameSession.get_time_scale() > 1:
			GameSession.set_time_scale(1)
		SessionLog.write("new_light", {"evening": evening, "minutes": roundi(result.elapsed_seconds / 60.0),
			"stopped_by": String(result.stopped_by)})
		snap_light())
	await time_passage.finished
	_on_modal_stack_changed(modals.depth())


## After any sleep (full or cut short, in port or underway, started in the
## cabin or at the chart) the player wakes in the cabin beside the V-berth.
func _wake_in_berth() -> void:
	GameSession.enter_boat_area(SessionState.AREA_INTERIOR, WAKE_SPAWN)
	var area := router.current_screen as BoatArea
	if area and area.area_id == SessionState.AREA_INTERIOR:
		area.place_player_at_spawn(WAKE_SPAWN)
	else:
		_show_current_boat_area()  # closes the chart (or leaves the deck)


## The boat was lost at sea and the crew rescued (GameSession.rescue(), which
## has already moved everything to the home harbour). Shows the boat there,
## aboard in the cabin, with the rescue report on top. Gameplay is paused
## until the report is closed; time then runs at 1× (a player pause stays).
func _on_rescued(info: Dictionary) -> void:
	hud.hide_warning()
	modals.clear()
	_rescue_open = true
	_show_current_boat_area()
	var dialog := rescue_dialog_scene.instantiate() as RescueDialog
	dialog.setup(info)
	# Cleared before the stack reports the dialog closed (connected first), so
	# that report un-pauses the game.
	dialog.closed.connect(func() -> void: _rescue_open = false)
	modals.push(dialog)
	_on_modal_stack_changed(modals.depth())


## The provisions locker in the cabin: the numbers, and the way to the
## grocery store in harbour.
func open_provisions() -> void:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return
	var menu := provisions_menu_scene.instantiate() as ProvisionsMenu
	menu.grocery_requested.connect(open_grocery)
	modals.push(menu)


## The harbour grocery store (on top of whatever menu asked for it). In
## harbour only.
func open_grocery() -> void:
	if not is_in_gameplay() or router.is_busy():
		return
	if not GameSession.is_moored_in_harbour():
		notify(Loc.t("The grocery store is in harbour; you are at sea."))
		return
	if not GameSession.has_facility(HarbourFacilities.GROCERY):
		_refuse_facility(HarbourFacilities.GROCERY)
		return
	SessionLog.write("facility", {"facility": "grocery", "outcome": "opened", "port": String(GameSession.get_location_id())})
	var grocery := GroceryMenu.new()
	grocery.fishmonger_requested.connect(open_fishmonger)
	modals.push(grocery)


# --- Harbour trades (I020) ------------------------------------------------------------------

## The fishmonger (next to the grocery store): where the catch is sold.
func open_fishmonger() -> FishmongerMenu:
	return _open_trade(HarbourFacilities.FISHMONGER, FishmongerMenu.new()) as FishmongerMenu


## The chandlery (at the boatyard).
func open_chandlery() -> ChandleryMenu:
	var menu := ChandleryMenu.new()
	menu.time_requested.connect(_spend_yard_time)
	return _open_trade(HarbourFacilities.CHANDLERY, menu) as ChandleryMenu


## The sailmaker (at the boatyard).
func open_sailmaker() -> SailmakerMenu:
	var menu := SailmakerMenu.new()
	menu.time_requested.connect(_spend_yard_time)
	return _open_trade(HarbourFacilities.SAILMAKER, menu) as SailmakerMenu


func _open_trade(trade: StringName, menu: TradePanel) -> TradePanel:
	if not GameSession.has_facility(trade):
		_refuse_facility(trade)
		menu.free()
		return null
	SessionLog.write("facility", {"facility": String(trade), "outcome": "opened", "port": String(GameSession.get_location_id())})
	modals.push(menu)
	return menu


## "Make it home" (I020), in the cabin: which cabin things are shown aboard.
func open_cabin_home() -> CabinHomeMenu:
	var area := router.current_screen as BoatArea
	if area == null or area.area_id != SessionState.AREA_INTERIOR or not modals.is_empty():
		return null
	var menu := CabinHomeMenu.new()
	modals.push(menu)
	return menu


## Go Ashore (Iteration 12): a small harbour event, in harbours that offer it.
func open_go_ashore() -> void:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return
	if not GameSession.has_facility(HarbourFacilities.GO_ASHORE):
		_refuse_facility(HarbourFacilities.GO_ASHORE)
		return
	SessionLog.write("facility", {"facility": "go_ashore", "outcome": "opened", "port": String(GameSession.get_location_id())})
	var menu := GoAshoreMenu.new()
	menu.choice_made.connect(_on_shore_choice.bind(menu))
	modals.push(menu)
	var offer := GameSession.get_shore_event()
	SessionLog.write("shore_event", {"port": String(GameSession.get_location_id()), "event": menu.get_event_id(),
		"resting": offer.get("resting", false), "seen": offer.get("seen", false)})


## A Go Ashore choice: GameSession settles it, then the time passes ashore.
func _on_shore_choice(event_id: String, choice_index: int, menu: GoAshoreMenu) -> void:
	var result := GameSession.apply_shore_choice(event_id, choice_index)
	if String(result.error).is_empty() and int(result.minutes) > 0:
		Simulation.spend_time_ashore(float(result.minutes))
	menu.show_outcome(result)
	SessionLog.write("shore_choice", {"port": String(GameSession.get_location_id()), "event": event_id, "choice": choice_index,
		"error": result.error, "cost": result.cost, "minutes": result.minutes, "renown": result.renown})


# --- Fishing (Iteration 13) ---------------------------------------------------------

## The rod on the stern rail.
func open_fishing() -> FishingMenu:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	if not _hand_free():
		return null
	var menu := FishingMenu.new()
	menu.wait_requested.connect(_on_fishing_wait.bind(menu))
	modals.push(menu)
	_bite_wait = 0.0
	SessionLog.write("fishing_open", {"line_out": GameSession.is_line_out(), "mode": String(GameSession.get_fishing_mode()),
		"bite": not GameSession.get_pending_bite().is_empty()})
	return menu


## Waiting at the rod: time passes on deck (the hat is in the wind) until a
## bite or another event, at most `minutes`.
func _on_fishing_wait(minutes: float, menu: FishingMenu) -> void:
	if not GameSession.is_line_out():
		return
	var result := Simulation.spend_time_aboard(minutes, false)
	SessionLog.write("fishing_wait", {"minutes": result.elapsed_seconds / 60.0, "stopped_by": String(result.stopped_by)})
	if result.stopped_by == Simulation.STOP_RESCUE:
		return
	menu.show_wait_result(result)


## A fish bit: the bell on the rod, a notice and the HUD's "Fish on!" (the
## fight starts at once when the rod's panel is open).
func _on_fish_bite(_bite: Dictionary) -> void:
	AudioManager.play_sfx(FishingSounds.bite(), FishingSounds.DB)
	SessionLog.write("fishing_bite", {"species": _bite.species, "kg": _bite.kg, "mode": _bite.mode})
	if modals.get_top() is FishingMenu:
		return
	_bite_wait = GameSession.BITE_WAIT_SECONDS
	notify(Loc.t("Fish on! Press R to reel in (the rod is on the stern rail)."))


## The fish waits a while (real time, while playing) before it gets away.
func _update_bite_wait(delta: float) -> void:
	if _bite_wait <= 0.0 or get_tree().paused:
		return
	_bite_wait -= delta
	if _bite_wait > 0.0 or GameSession.get_pending_bite().is_empty():
		return
	GameSession.expire_bite()
	AudioManager.play_sfx(FishingSounds.snap(), FishingSounds.DB)
	notify(Loc.t("The fish got away before you reached the rod. The line is still out."))
	SessionLog.write("fishing_result", {"result": "escaped_unattended"})


func get_bite_wait() -> float:
	return _bite_wait


## The galley stove (Iteration 13).
func open_cooking() -> CookingMenu:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	if not _hand_free():
		return null
	var menu := CookingMenu.new()
	menu.cooked.connect(_on_meal_cooked)
	menu.coffee_made.connect(func(result: Dictionary) -> void: Simulation.spend_time_aboard(float(result.minutes), true))
	modals.push(menu)
	SessionLog.write("galley_open", {"refusal": GameSession.cooking_refusal(), "fish": GameSession.get_fishing().hold.size()})
	return menu


## A dish is done: its cooking time passes below deck.
func _on_meal_cooked(result: Dictionary) -> void:
	var passed := Simulation.spend_time_aboard(float(result.minutes), true)
	if passed.stopped_by != Simulation.STOP_NONE and passed.stopped_by != Simulation.STOP_RESCUE:
		notify(Loc.t("While cooking: %s") % (Loc.t("a fish is on the line!") if passed.stopped_by == Simulation.STOP_BITE else
			(Loc.t("the anchor alarm went.") if passed.stopped_by == Simulation.STOP_ANCHOR else Loc.t("a weather warning came in."))))


# --- The anchor (Iteration 13) --------------------------------------------------------

## The windlass on the foredeck.
## The boat arrived at an anchorage waypoint (Iteration 18): ask once, when
## nothing else is open (after waking, after a menu closes).
func _on_anchorage_reached(_index: int) -> void:
	AudioManager.play_sfx(FishingSounds.bite(), FishingSounds.DB)
	_anchorage_prompt_due = true


func show_anchorage_prompt() -> AnchoragePrompt:
	if not GameSession.is_holding_at_anchorage() or not modals.is_empty():
		return null
	var prompt := AnchoragePrompt.new()
	prompt.anchor_requested.connect(func() -> void: open_anchor.call_deferred())
	prompt.sail_on_requested.connect(func() -> void:
		var error := GameSession.sail_on_from_anchorage()
		notify(Loc.t("Sailing on along the course.") if error == "" else error))
	modals.push(prompt)
	SessionLog.write("anchorage_prompt", {"site": String(GameSession.evaluate_anchorage().get("class", ""))})
	return prompt


func is_anchorage_prompt_due() -> bool:
	return _anchorage_prompt_due


func open_anchor() -> AnchorMenu:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	if not _hand_free():
		return null
	var menu := AnchorMenu.new()
	menu.time_requested.connect(func(minutes: float) -> void: Simulation.spend_time_aboard(minutes, false))
	modals.push(menu)
	var site := GameSession.evaluate_anchorage() if GameSession.is_underway() and not GameSession.is_anchored() else {}
	SessionLog.write("anchor_open", {"anchored": GameSession.is_anchored(), "class": String(site.get("class", "")),
		"refusal": GameSession.anchoring_refusal() if not GameSession.is_anchored() else ""})
	return menu


## The anchor alarm: a soft double beep, always with a notice and the HUD's
## red "Anchor dragging!" (or amber poor holding).
func _on_anchor_alarm(alarm: Dictionary) -> void:
	AudioManager.play_sfx(FishingSounds.warning(), FishingSounds.DB)
	notify(String(alarm.text))
	SessionLog.write("anchor_alarm", {"level": alarm.level, "dragged_nm": snappedf(GameSession.get_anchor().dragged_nm, 0.001)})


## The trophy board in the cabin.
func open_trophies() -> void:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return
	modals.push(TrophyMenu.new())


## A harbour service that is not offered here (Iteration 12): say so, log it.
func _refuse_facility(facility: StringName) -> void:
	notify(GameSession.facility_refusal(facility))
	SessionLog.write("facility", {"facility": String(facility), "outcome": "unavailable", "port": String(GameSession.get_location_id())})


## The cabin's work station: remote work, in harbour only.
func open_work_menu() -> void:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return
	if not GameSession.can_work_remotely():
		notify(Loc.t("Remote work needs a steady connection: moor in a harbour first."))
		return
	var menu := WorkMenu.new()
	menu.work_requested.connect(work_for)
	menu.publish_requested.connect(open_publish_menu)
	modals.push(menu)


## Works for `hours` through the normal simulation (Simulation.work), then
## reports the pay. Like sleeping, it also works while paused and leaves the
## pause as it was; the player stays at the desk.
func work_for(hours: int) -> void:
	if not GameSession.can_work_remotely():
		notify(Loc.t("Remote work needs a steady connection: moor in a harbour first."))
		return
	var result: Dictionary = await pass_time(func() -> Dictionary: return Simulation.work(hours))
	if not String(result.error).is_empty():
		notify(result.error)
		return
	if result.stopped_by == Simulation.STOP_RESCUE:
		return
	var stopped := interruption_reason(result.stopped_by)
	notify((Loc.t("Interrupted: %s.") % stopped + " " if not stopped.is_empty() else "") + Loc.t("You worked %d h and earned %s. It is %s. Funds: %s.%s") % [
		result.hours, GameSession.format_money(result.earned), Simulation.format_game_time(GameSession.get_game_time()),
		GameSession.format_money(GameSession.get_funds()), Loc.t("  Time is still paused.") if GameSession.is_paused() else ""])


# --- Hours-long tasks on the one clock (I022) -------------------------------------------

## Spends a task's hours on the one clock: with a screen, the game fades to
## black, `work` runs the simulation once under it (Simulation.work,
## spend_time_aboard ...: it returns an AdvanceResult or a Dictionary with
## "stopped_by") while the clock counts the hours, a line says why it stopped
## early, and the game fades back in at ×1. Without a screen (tests) it all
## happens at once. Like sleep it works while paused and leaves the pause as
## it was. Returns what `work` returned.
func pass_time(work: Callable) -> Variant:
	modals.clear()
	var outcome := {}
	var run := func() -> float:
		outcome.result = work.call()
		if TimePassage.is_shown():
			snap_light()
		return GameSession.get_game_time()
	if TimePassage.is_shown() and not is_instance_valid(time_passage):
		time_passage = TimePassage.new()
		add_child(time_passage)
		time_passage.play_sleep(GameSession.get_game_time(), run, func() -> String:
			var why := interruption_reason(_stopped_by(outcome.result))
			return Loc.t("Interrupted: %s") % why if not why.is_empty() else "")
		await time_passage.finished
		_on_modal_stack_changed(modals.depth())
	else:
		run.call()
	if GameSession.get_time_scale() > 1:
		GameSession.set_time_scale(1)
	return outcome.result


static func _stopped_by(result: Variant) -> StringName:
	if result is Simulation.AdvanceResult:
		return result.stopped_by
	return StringName(result.get("stopped_by", Simulation.STOP_NONE)) if result is Dictionary else Simulation.STOP_NONE


## Why a task stopped early, in a few words ("" when it ran to the end).
static func interruption_reason(stopped_by: StringName) -> String:
	match stopped_by:
		Simulation.STOP_WARNING:
			return Loc.t("a weather warning came in")
		Simulation.STOP_BITE:
			return Loc.t("the bell on the rod rang: a fish is on")
		Simulation.STOP_ANCHOR:
			return Loc.t("the anchor alarm went")
		Simulation.STOP_ARRIVAL:
			return Loc.t("the boat has arrived")
		Simulation.STOP_ANCHORAGE:
			return Loc.t("the boat is at the anchorage")
		Simulation.STOP_TRAFFIC:
			return Loc.t("a traffic warning")
		Simulation.STOP_VHF:
			return Loc.t("a call on the radio")
		Simulation.STOP_RESCUE:
			return Loc.t("the rescue came")
	return ""


## Postcards from the Sea (I022): from the cabin.
func open_postcards() -> PostcardMenu:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	var menu := PostcardMenu.new()
	menu.make_requested.connect(func() -> void: make_postcard.call_deferred())
	menu.scrapbook_requested.connect(func() -> void: modals.push(ScrapbookMenu.new()))
	modals.push(menu)
	return menu


## Makes the postcard drafted in GameSession: its remaining time passes on the
## one clock; an interruption keeps the card, with the time already given it.
func make_postcard() -> void:
	if GameSession.get_pastimes().draft.is_empty():
		return
	var minutes := GameSession.postcard_minutes_left()
	var result: Simulation.AdvanceResult = await pass_time(func() -> Simulation.AdvanceResult: return Simulation.spend_time_aboard(minutes, true))
	var outcome := GameSession.work_on_postcard(result.elapsed_seconds / 60.0)
	if result.stopped_by == Simulation.STOP_RESCUE:
		return
	var now := Simulation.format_game_time(GameSession.get_game_time())
	if outcome.done:
		notify(Loc.t("Your postcard is published and in the scrapbook. It is %s.") % now)
	else:
		notify(Loc.t("Interrupted after %s: %s. The postcard is kept; finish it later from the cabin (Q, Write a postcard). It is %s.") % [
			Simulation.format_duration(result.elapsed_seconds), interruption_reason(result.stopped_by), now])


## A Game Developer at Sea (I022): from the cabin.
func open_game_dev() -> GameDevMenu:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	var menu := GameDevMenu.new()
	menu.work_requested.connect(func(task_id: String, choice: int) -> void: work_on_game.call_deferred(task_id, choice))
	modals.push(menu)
	return menu


## A session on the little game: the task's (remaining) hours pass on the one
## clock; when interrupted, the hours worked still count.
func work_on_game(task_id: String, choice: int) -> void:
	var task := Pastimes.task(task_id)
	if task.is_empty():
		return
	var unfinished: Dictionary = GameSession.get_pastimes().game.task
	var minutes := float(task.hours) * 60.0 - (float(unfinished.minutes) if unfinished.get("id") == task_id else 0.0)
	var result: Simulation.AdvanceResult = await pass_time(func() -> Simulation.AdvanceResult: return Simulation.spend_time_aboard(minutes, true))
	var outcome := GameSession.work_on_game(task_id, choice, result.elapsed_seconds / 60.0)
	if result.stopped_by == Simulation.STOP_RESCUE:
		return
	var now := Simulation.format_game_time(GameSession.get_game_time())
	if not outcome.done:
		notify(Loc.t("Interrupted after %s: %s. The hours worked count; go on later from the cabin. It is %s.") % [
			Simulation.format_duration(result.elapsed_seconds), interruption_reason(result.stopped_by), now])
		return
	var lines: Array[String] = [Loc.t(String((task.done as Array)[clampi(choice, 0, (task.done as Array).size() - 1)]))]
	if not (outcome.milestone as Dictionary).is_empty():
		lines.append(Loc.t("Milestone: %s!") % Loc.t(String(outcome.milestone.name)))
	if int(outcome.euros) > 0:
		lines.append(Loc.t("The first sales: %s.") % GameSession.format_money(int(outcome.euros)))
	lines.append(Loc.t("It is %s.") % now)
	notify(" ".join(lines))


func _on_weather_warning(warning: Dictionary) -> void:
	hud.show_warning(warning.text)
	notify(warning.text)


## A vessel newly on a collision course (I019): the warning, a short alarm,
## and the radar shows by itself while the risk lasts.
func _on_traffic_alert(info: Dictionary) -> void:
	AudioManager.play_sfx(FishingSounds.warning(), FishingSounds.DB)
	hud.show_warning(String(info.text))
	if not GameSession.is_asleep():
		notify(String(info.text))


## A call on the VHF (I019): a short radio sound, and the call is shown as
## soon as nothing else is open (after waking, after the voyage map).
func _on_vhf_call(call: Dictionary) -> void:
	AudioManager.play_sfx(FishingSounds.bite(), FishingSounds.DB)
	_pending_vhf = call
	if not GameSession.is_asleep() and GameSession.get_time_scale() > 1 and not is_instance_valid(voyage_map):
		GameSession.set_time_scale(1)


func show_vhf_dialog(call: Dictionary) -> VhfDialog:
	if not GameSession.can_answer_vhf(call) or not modals.is_empty():
		return null
	var dialog := VhfDialog.new()
	dialog.call = call
	dialog.answered.connect(func(result: Dictionary) -> void: notify(String(result.text)))
	modals.push(dialog)
	SessionLog.write("vhf_dialog", {"id": String(call.id), "kind": String(call.kind)})
	return dialog


func get_pending_vhf() -> Dictionary:
	return _pending_vhf


func _on_arrived(port_id: StringName) -> void:
	hud.hide_warning()
	# The arrival card (I021): the harbour's picture, the arrival and one line
	# about the place. Notices go to the same corner, so it never blocks.
	var port := PortCatalog.get_default().get_port(port_id)
	var picture := HarbourLooks.get_default().picture_for(port_id)
	if port_id == _new_harbour_id and picture:
		show_harbour_moment(port_id, picture)
	else:
		toasts.show_card(Loc.t("Arrived in %s.") % PortCatalog.get_default().get_display_name(port_id),
			port.get_description() if port else "", picture)
	_new_harbour_id = &""
	# Sleeping through the arrival, the captain wakes in the cabin as always.
	if is_instance_valid(voyage_map):
		_dock_after_map = true  # after the voyage map, when the captain comes aboard
	elif not GameSession.is_asleep():
		show_docking_arrival.call_deferred()


## The short docking arrival (Iteration 17): aboard and with no window open,
## the deck is shown (from the cabin too) with the captain at the helm while
## the boat comes alongside, the engine running. Otherwise nothing extra.
func show_docking_arrival() -> void:
	if not is_in_gameplay() or not modals.is_empty() or router.is_busy() or not GameSession.is_moored_in_harbour():
		return
	var area := router.current_screen as BoatArea
	if area.area_id != SessionState.AREA_EXTERIOR:
		GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
		router.change_screen(GameSession.get_vessel_definition().get_area_scene(SessionState.AREA_EXTERIOR), func(deck: BoatArea) -> void:
			_connect_boat_area(deck)
			deck.ready.connect(_start_docking.bind(deck), CONNECT_ONE_SHOT | CONNECT_DEFERRED))
		return
	_start_docking(area)


func _start_docking(deck: BoatArea) -> void:
	if not is_instance_valid(deck):
		return
	AudioManager.play_loop(ENGINE_LOOP, engine_sound, ENGINE_OUTSIDE_DB, 0.3)
	deck.docking_finished.connect(update_engine_audio, CONNECT_ONE_SHOT)
	deck.play_docking_arrival()


## A first visit is noted in the Captain's Log (one short message).
func _on_voyage_logged(record: Dictionary, new_harbour: bool) -> void:
	if new_harbour:
		var log := GameSession.get_captains_log()
		var line := Loc.t("New harbour in the Captain's Log: %s (%d of %d visited).") % [
			PortCatalog.get_default().get_display_name(StringName(record.to)), log.get_distinct_harbours(),
			PortCatalog.get_default().ports.size()]
		# A first arrival with a picture gets a Golden Harbour Moment, which
		# carries this line itself (one card, not two notices).
		if HarbourLooks.get_default().picture_for(StringName(record.to)):
			_new_harbour_id = StringName(record.to)
			_new_harbour_line = line
		else:
			notify(line)


# --- Golden Harbour Moments -------------------------------------------------------

## The harbour just logged for the first time (until its arrival is shown).
var _new_harbour_id: StringName = &""
var _new_harbour_line := ""


## The first arrival in a harbour with a picture: a small illustrated travel
## memory (HarbourMoment) in the notice column, lit for the hour. Never a
## window: it does not pause or take the keyboard, a click puts it away, and
## it fades by itself. Returning to a known harbour keeps the small card.
func show_harbour_moment(port_id: StringName, picture: Texture2D) -> HarbourMoment:
	var moment := HarbourMoment.new()
	moment.port_id = port_id
	moment.picture = picture
	moment.special = HarbourLooks.get_default().is_special(port_id)
	moment.elevation = Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time())
	moment.overcast = BoatLighting.overcast_of(Simulation.get_weather_at_vessel())
	moment.log_line = _new_harbour_line
	toasts.show_moment(moment)
	SessionLog.write("harbour_moment", {"port": String(port_id), "special": moment.special, "elevation": snappedf(moment.elevation, 0.1)})
	return moment


## Renown earned on a voyage: one short message for all of it. A secret
## achievement found gets its own message (title and description) and a
## soft chime.
func _on_renown_awarded(awards: Array) -> void:
	var total := 0
	var titles: Array[String] = []
	for award: Dictionary in awards:
		if award.get("secret", false):
			notify(Loc.t("Secret achievement: %s. %s  +%d renown") % [Loc.t(String(award.title)), Loc.t(String(award.text)), int(award.reward)])
			AudioManager.play_sfx(achievement_sound, ACHIEVEMENT_DB)
			continue
		total += int(award.reward)
		titles.append(Loc.t(String(award.title)))
	if not titles.is_empty():
		notify(Loc.t("+%d renown: %s.") % [total, ", ".join(titles)])


# --- Captain's hat ------------------------------------------------------------------

## Actions that need a free hand (the rod, the anchor, the stove, the
## sheets): with the hat and a mug in hand, a friendly word instead.
func _hand_free() -> bool:
	var refusal := GameSession.hands_refusal()
	if refusal.is_empty():
		return true
	if not refusal in toasts.get_messages():  # once, however often the key is pressed
		notify(refusal)
	return false


## The hat key (H): off and under the arm, or back on.
func toggle_hat() -> void:
	notify(GameSession.toggle_hat())


## Hat messages stay up longer than ordinary notices (HatBadge's durations), so
## they are noticed even with the sound off or while looking elsewhere
## (Iteration 12). Toasts sit above every panel.


func _on_hat_warning(text: String) -> void:
	toasts.show_message(text, HatBadge.WARNING_SECONDS)
	SessionLog.write("hat_warning_shown", {"area": String(GameSession.get_boat_area()), "seconds": HatBadge.WARNING_SECONDS})


func _on_hat_lost(info: Dictionary) -> void:
	toasts.show_message(Loc.t("%s %s A new one is sold at the harbour grocery store.") % [HatBadge.LOST_HEADLINE, info.text], HatBadge.LOST_SECONDS)
	if hud and hud.hat_badge:
		hud.hat_badge.pulse()
	AudioManager.play_sfx(hat_lost_sound, HAT_LOST_DB)
	SessionLog.write("hat_lost_shown", {"area": String(GameSession.get_boat_area()), "seconds": HatBadge.LOST_SECONDS,
		"modal_open": not modals.is_empty()})


func _show_current_boat_area() -> void:
	var area := GameSession.get_boat_area()
	# The scenes come from the active vessel (see VesselDefinition).
	var scene := GameSession.get_vessel_definition().get_area_scene(area)
	if scene == null:
		push_error("Cannot show unknown boat area '%s'." % area)
		return
	router.change_screen(scene, _connect_boat_area)


func _on_area_change_requested(area: StringName, spawn_point: StringName) -> void:
	GameSession.enter_boat_area(area, spawn_point)
	_show_current_boat_area()


# --- Menus -------------------------------------------------------------------------

func open_pause_menu() -> void:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return
	var menu := pause_menu_scene.instantiate() as PauseMenu
	menu.save_requested.connect(open_save_menu)
	menu.load_requested.connect(open_load_menu)
	menu.log_requested.connect(open_captains_log)
	menu.settings_requested.connect(open_settings)
	menu.difficulty_requested.connect(func() -> void: modals.push(DifficultyMenu.new()))
	menu.handbook_requested.connect(func() -> void: open_handbook())
	menu.main_menu_requested.connect(request_main_menu)
	menu.dev_tests_requested.connect(func() -> void:
		modals.clear()
		toggle_dev_tests())
	modals.push(menu)


## The Captain's Log: L opens and closes it aboard or at the chart; the pause
## menu opens it on top of itself.
func toggle_captains_log() -> void:
	if not GameSession.is_active() or router.is_busy():
		return
	if modals.get_top() is CaptainsLogMenu:
		modals.get_top().close()
		return
	if not modals.is_empty() or not (router.current_screen is BoatArea or router.current_screen is WorldMap):
		return
	open_captains_log()


func open_captains_log() -> CaptainsLogMenu:
	if not GameSession.is_active():
		return null
	var menu := CaptainsLogMenu.new()
	menu.name = "CaptainsLogMenu"
	menu.publish_requested.connect(open_publish_menu)
	modals.push(menu)
	return menu


## The travel-update dialog (from the Captain's Log or the work station), on
## top of the menu that asked for it.
func open_publish_menu() -> void:
	if not GameSession.is_active() or router.is_busy():
		return
	var menu := PublishMenu.new()
	menu.name = "PublishMenu"
	menu.publish_confirmed.connect(publish_travel_update)
	modals.push(menu)


## Publishes the confirmed travel update (GameSession.publish_travel_update)
## and reports the income.
func publish_travel_update() -> void:
	modals.clear()
	var result := GameSession.publish_travel_update()
	if not String(result.error).is_empty():
		notify(result.error)
		return
	notify(Loc.t("Travel update published: %d renown earned you %s. Funds: %s.") % [result.renown,
		GameSession.format_money(result.euros), GameSession.format_money(result.funds_after)])


## Developer view of the interaction areas (F8 with the developer tools).
func set_interaction_debug(enabled: bool) -> void:
	Interactable.debug_show_areas = enabled
	for node in get_tree().root.find_children("*", "Interactable", true, false):
		var interactable := node as Interactable
		interactable.set_process(true)
		interactable.queue_redraw()
	notify(Loc.t("Interaction areas: %s") % ("shown" if enabled else "hidden"))


## The developer test panel (DevTools): F10 opens and closes it, in the boat or
## on the chart. Development builds only; it does not exist for players.
func toggle_dev_tests() -> void:
	if not DevTools.is_enabled() or not GameSession.is_active() or router.is_busy():
		return
	if modals.get_top() is DevTestPanel:
		modals.get_top().close()
		return
	if not modals.is_empty() or not (router.current_screen is BoatArea or router.current_screen is WorldMap):
		return
	modals.push(DevTestPanel.new())


## The boatyard: only in harbour, never underway.
func open_boatyard() -> void:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return
	if not GameSession.is_moored_in_harbour():
		notify(Loc.t("The boatyard is only open while you are moored in harbour."))
		return
	if not GameSession.can_change_vessel():
		_refuse_facility(HarbourFacilities.BOATYARD)
		return
	SessionLog.write("facility", {"facility": "boatyard", "outcome": "opened", "port": String(GameSession.get_location_id())})
	var menu := boatyard_menu_scene.instantiate() as BoatyardMenu
	menu.vessel_chosen.connect(switch_vessel)
	menu.grocery_requested.connect(open_grocery)
	menu.care_requested.connect(open_boat_care)
	menu.chandlery_requested.connect(open_chandlery)
	menu.sailmaker_requested.connect(open_sailmaker)
	modals.push(menu)


## Boat care (Iteration 14), on top of the boatyard: the condition overview,
## the services this yard offers, equipment and, where the yard can lift
## boats, the haul-out. The work's time passes ashore.
func open_boat_care() -> BoatCareMenu:
	if not GameSession.is_moored_in_harbour() or not GameSession.has_facility(HarbourFacilities.BOATYARD):
		_refuse_facility(HarbourFacilities.BOATYARD)
		return null
	var menu := BoatCareMenu.new()
	menu.time_requested.connect(_spend_yard_time)
	menu.haul_out_requested.connect(open_haul_out)
	modals.push(menu)
	SessionLog.write("boat_care_open", {"port": String(GameSession.get_location_id()),
		"overall": String(BoatCare.overall_level(GameSession.get_boat_care(), GameSession.get_condition(), GameSession.get_game_time())),
		"haul_out": GameSession.has_facility(HarbourFacilities.HAUL_OUT)})
	return menu


## The haul-out (only at a yard that can lift boats).
func open_haul_out() -> HaulOutPanel:
	if GameSession.service_refusal(BoatCare.SERVICE_HAUL_OUT) != "":
		notify(GameSession.service_refusal(BoatCare.SERVICE_HAUL_OUT))
		return null
	var panel := HaulOutPanel.new()
	panel.time_requested.connect(_spend_yard_time)
	modals.push(panel)
	return panel


func _spend_yard_time(minutes: float) -> void:
	if minutes > 0.0:
		Simulation.spend_time_ashore(minutes)
	var yard := _find_modal(BoatyardMenu) as BoatyardMenu
	if yard:
		yard.refresh_condition()


func _find_modal(type: Variant) -> ModalPanel:
	for modal in modals.get_all():
		if is_instance_of(modal, type):
			return modal
	return null


## Moves aboard `vessel_id` (from the boatyard): the session, companion, time
## and harbour are kept; the player steps aboard on deck by the boatyard.
func switch_vessel(vessel_id: StringName) -> void:
	if vessel_id == GameSession.get_vessel_id():
		modals.clear()
		return
	# I022: a boat not yet yours is bought first (asked, once).
	var vessel := VesselCatalog.get_default().get_vessel(vessel_id)
	if vessel and not GameSession.owns_vessel(vessel_id):
		var buy: bool = await modals.confirm(Loc.t("Buy the %s?") % vessel.display_name,
			Loc.t("The %s costs %s; you have %s. It is yours for good, and you move aboard at once. Your other boats stay yours.") % [
				vessel.display_name, GameSession.format_money(vessel.price), GameSession.format_money(GameSession.get_funds())], "Buy")
		if not buy:
			return
		var refusal := GameSession.buy_vessel(vessel_id)
		if refusal != "":
			notify(refusal)
			return
	modals.clear()
	var error := GameSession.switch_vessel(vessel_id)
	if error != "":
		notify(error)
		return
	_show_current_boat_area()
	notify(Loc.t("Welcome aboard the %s.") % GameSession.get_vessel_definition().display_name)


## The developer guides (DEV_GUIDES/). Not a gameplay feature: offered only
## in development builds, from the main menu.
func open_dev_guides() -> void:
	if not modals.is_empty() or router.is_busy() or not DevGuides.is_available():
		return
	modals.push(dev_guides_menu_scene.instantiate() as ModalPanel)


func open_settings() -> void:
	modals.push(settings_menu_scene.instantiate() as ModalPanel)


func open_save_menu() -> void:
	var menu := save_load_menu_scene.instantiate() as SaveLoadMenu
	menu.setup(SaveLoadMenu.Mode.SAVE)
	modals.push(menu)


func open_load_menu() -> void:
	var menu := save_load_menu_scene.instantiate() as SaveLoadMenu
	menu.setup(SaveLoadMenu.Mode.LOAD)
	menu.load_requested.connect(request_load)
	modals.push(menu)


# --- Screen wiring -----------------------------------------------------------------

func _connect_main_menu(menu: MainMenu) -> void:
	menu.new_game_requested.connect(open_new_game_menu)
	menu.continue_requested.connect(continue_game)
	menu.load_requested.connect(open_load_menu)
	menu.settings_requested.connect(open_settings)
	menu.quit_requested.connect(quit_game)
	menu.dev_guides_requested.connect(open_dev_guides)
	menu.import_requested.connect(import_legacy_saves)
	if not SettingsManager.has_chosen_language():
		show_language_picker.call_deferred()


## The first launch (I019): English or Dansk, asked once before anything else.
func show_language_picker() -> LanguagePicker:
	if SettingsManager.has_chosen_language() or not modals.is_empty():
		return null
	var picker := LanguagePicker.new()
	modals.push(picker)
	return picker


func _connect_boat_area(area: BoatArea) -> void:
	area.area_change_requested.connect(_on_area_change_requested)
	area.chart_requested.connect(open_chart)
	area.world_map_requested.connect(open_dream_map)
	area.sleep_requested.connect(open_sleep_menu)
	area.helm_requested.connect(_on_helm_requested)
	area.message_requested.connect(notify)
	area.interaction_prompt_changed.connect(hud.set_prompt)
	area.boatyard_requested.connect(open_boatyard)
	area.provisions_requested.connect(open_provisions)
	area.work_requested.connect(open_work_menu)
	area.grocery_requested.connect(open_grocery)
	area.go_ashore_requested.connect(open_go_ashore)
	area.fishing_requested.connect(open_fishing)
	area.trophies_requested.connect(open_trophies)
	area.cooking_requested.connect(open_cooking)
	area.anchor_requested.connect(open_anchor)


func _connect_world_map(map: WorldMap) -> void:
	map.close_requested.connect(close_chart)
	map.depart_requested.connect(request_departure)
	map.sleep_requested.connect(open_sleep_menu)


func _on_screen_changed(screen: Node) -> void:
	if is_instance_valid(voyage_map):
		voyage_map.close_now()
	var area := screen as BoatArea
	SessionLog.write("screen", {"screen": String(screen.name) if screen else "", "area": String(area.area_id) if area else ""})
	# The HUD's clock bar is the shared time control: also shown on the chart.
	_hud_layer.visible = area != null or screen is WorldMap
	hud.set_chart_mode(screen is WorldMap)
	# On the chart, notifications are centred over the map like the clock bar.
	var toast_shift := -Hud.CHART_SIDEBAR_WIDTH / 2.0 if screen is WorldMap else 0.0
	toasts.offset_left = _toast_offsets.x + toast_shift
	toasts.offset_right = _toast_offsets.y + toast_shift
	hud.set_prompt("")
	if area:
		hud.set_area(area.area_id)
		hud.refresh()
	else:
		AudioManager.stop_ambience()
	update_engine_audio()
	_on_modal_stack_changed(modals.depth())


## Runs the engine sound while the boat is motoring: loud on deck, quieter and
## muffled inside. Both layers run in step and are only cross-faded, so the
## engine never restarts on a scene change. Off in the main menu and in port.
func update_engine_audio() -> void:
	var running := GameSession.is_active() and GameSession.is_motoring() and not (router.current_screen is MainMenu)
	if not running:
		AudioManager.stop_loop(ENGINE_LOOP, ENGINE_FADE_SECONDS)
		AudioManager.stop_loop(ENGINE_MUFFLED_LOOP, ENGINE_FADE_SECONDS)
		return
	var area := router.current_screen as BoatArea
	var outside := area != null and area.area_id == SessionState.AREA_EXTERIOR
	AudioManager.play_loop(ENGINE_LOOP, engine_sound,
		ENGINE_OUTSIDE_DB if outside else AudioManager.SILENT_DB, ENGINE_FADE_SECONDS)
	AudioManager.play_loop(ENGINE_MUFFLED_LOOP, engine_muffled_sound,
		AudioManager.SILENT_DB if outside else ENGINE_INSIDE_DB, ENGINE_FADE_SECONDS)


func _on_modal_stack_changed(depth: int) -> void:
	# Gameplay pauses while any menu is open over it. Menus, the HUD and
	# notifications run with PROCESS_MODE_ALWAYS and stay responsive.
	get_tree().paused = (depth > 0 and is_in_gameplay()) or _rescue_open
	if depth == 0 and router.current_screen is MainMenu:
		var menu := router.current_screen as MainMenu
		menu.refresh_saves()
		menu.focus_default()


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	# Once per button: a button moved to another parent enters the tree again.
	if button and ui_click_sound and not button.has_meta(&"ui_click"):
		button.set_meta(&"ui_click", true)
		button.pressed.connect(AudioManager.play_ui.bind(ui_click_sound))
