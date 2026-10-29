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
## The companions follow the captain between cabin and deck (Iteration 18):
## per companion id (I025: up to two), seconds until it goes, where to, and
## when it next wanders on deck.
var _follow := {}
const FOLLOW_UP_SECONDS := Vector2(2.5, 5.0)
const FOLLOW_DOWN_SECONDS := Vector2(4.0, 8.0)
const WANDER_SECONDS := Vector2(45.0, 100.0)


## While moored or safely at anchor, the companion comes up on deck a little
## after the captain and goes back down a little after them; on deck it
## moves to another of its places now and then. Underway or in poor weather
## it stays below (GameSession brings it down by itself).
##
## I024: moored in a harbour it also follows the Captain ashore, down the
## gangplank to a place on the pontoon near them, and back. Coming back it
## sometimes lingers a while (it is exploring); the boat cannot cast off
## until it is aboard, and "Call ... aboard" fetches it at once.
##
## I025: each companion on its own timing (two never move as one), and two
## never take the same place on deck or on the pontoon.
func _update_companion_follow(delta: float) -> void:
	var area := router.current_screen as BoatArea
	if area == null or not GameSession.is_active() or router.is_busy() or GameSession.is_asleep() or get_tree().paused:
		return
	var companions := GameSession.get_companions()
	for companion in companions:
		_follow_one(companion, companions, area, delta)


func _follow_one(companion: CompanionState, all: Array[CompanionState], area: BoatArea, delta: float) -> void:
	var timing: Dictionary = _follow.get(companion.id, {"target": &"", "left": 0.0, "wander": randf_range(30.0, 60.0)})
	_follow[companion.id] = timing
	var want := companion.area
	var shore := area.get_shore_access() if area.area_id == SessionState.AREA_EXTERIOR else null
	var captain_ashore := shore != null and shore.is_active() and shore.is_player_ashore()
	if captain_ashore and GameSession.companion_may_go_ashore():
		want = CompanionState.AREA_SHORE
	elif area.area_id == SessionState.AREA_EXTERIOR and GameSession.companion_may_be_on_deck():
		want = CompanionState.AREA_DECK
	elif area.area_id == SessionState.AREA_INTERIOR:
		want = CompanionState.AREA_CABIN
	var taken := {}
	for other in all:
		if other.id != companion.id and other.area in [CompanionState.AREA_DECK, CompanionState.AREA_SHORE]:
			taken[other.deck_spot] = true
	if want == companion.area:
		timing.target = &""
		var wanders := (want == CompanionState.AREA_DECK and area.area_id == SessionState.AREA_EXTERIOR and not GameSession.is_settled_at_anchor()) \
			or want == CompanionState.AREA_SHORE
		if wanders:
			timing.wander = float(timing.wander) - delta
			if float(timing.wander) <= 0.0:
				timing.wander = randf_range(WANDER_SECONDS.x, WANDER_SECONDS.y)
				var place := _shore_place_near(shore, area.player.position, companion.deck_spot, taken) if want == CompanionState.AREA_SHORE \
					else _free_place((companion.deck_spot + randi_range(1, 2)) % 3, taken)
				GameSession.set_companion_area(want, place, companion.id)
		return
	if timing.target != want:
		timing.target = want
		var delay := FOLLOW_UP_SECONDS if want == CompanionState.AREA_DECK else FOLLOW_DOWN_SECONDS
		if want == CompanionState.AREA_SHORE:
			delay = FOLLOW_UP_SECONDS
		elif companion.area == CompanionState.AREA_SHORE and randf() < SHORE_LINGER_CHANCE:
			delay = SHORE_LINGER_SECONDS  # still sniffing about on the pontoon
		timing.left = randf_range(delay.x, delay.y)
	timing.left = float(timing.left) - delta
	if float(timing.left) <= 0.0:
		timing.target = &""
		timing.wander = randf_range(WANDER_SECONDS.x, WANDER_SECONDS.y)
		var place := _free_place(randi_range(0, 2), taken)
		if want == CompanionState.AREA_SHORE:
			place = _shore_place_near(shore, area.player.position, -1, taken)
		GameSession.set_companion_area(want, place, companion.id)


## `wanted`, or the next place (0-2) nobody else is using.
static func _free_place(wanted: int, taken: Dictionary) -> int:
	for i in 3:
		var place := (wanted + i) % 3
		if not taken.has(place):
			return place
	return wanted

## Coming back aboard, now and then it stays ashore a little longer (I024).
const SHORE_LINGER_CHANCE := 0.35
const SHORE_LINGER_SECONDS := Vector2(25.0, 60.0)


## Its place on the pontoon nearest the Captain (not `avoid`, not `taken`).
static func _shore_place_near(shore: ShoreAccess, captain: Vector2, avoid: int, taken := {}) -> int:
	var best := 0
	var best_d := INF
	for i in ShipCompanion.SHORE_OFFSETS.size():
		if i == avoid or taken.has(i):
			continue
		var d := ShipCompanion.get_shore_spot(shore, i).distance_to(captain)
		if d < best_d:
			best_d = d
			best = i
	return best


## Calls the companions back aboard from the shore (I024; I025: all at once).
func recall_companion() -> void:
	var line := GameSession.recall_companion()
	if line != "":
		_follow.clear()
		notify(line)


# --- Talk on long passages (I024) ---------------------------------------------------

## The Captain talks to the companion now and then underway, a little more
## as the days at sea add up (CompanionRemarks: stages, lines, responses).
## Timed on the voyage's own game clock, at most one remark per stage gap
## and never within PASSAGE_MIN_REAL_SECONDS of real time, so neither time
## acceleration nor sleeping brings a flood; after loading, the next remark
## is a full gap away (a reload never brings one sooner). Only in a quiet
## moment: aboard, no window, notice or warning showing. No meter, nothing
## to earn, nothing lost by silence.
var _talk_voyage_at := -1.0
var _talk_next_at := INF
var _talk_real_wait := 0.0
var _talk_said: Array[String] = []
var _talk_count := 0


func _update_passage_talk(delta: float) -> void:
	var departed := GameSession.get_voyage_departed_at() if GameSession.is_active() else -1.0
	if departed < 0.0:
		_talk_voyage_at = -1.0
		return
	var now := GameSession.get_game_time()
	if departed != _talk_voyage_at:
		_talk_voyage_at = departed
		_talk_said.clear()
		_talk_count = 0
		var gap := CompanionRemarks.PASSAGE_GAP_HOURS[CompanionRemarks.passage_stage((now - departed) / 3600.0)] * 3600.0
		# A passage just begun: after the first hours. Joined later (a loaded
		# game): a whole gap from now.
		_talk_next_at = departed + CompanionRemarks.PASSAGE_FIRST_HOURS * 3600.0 if now - departed < 600.0 else now + gap
		_talk_real_wait = CompanionRemarks.PASSAGE_MIN_REAL_SECONDS * 0.5
	if not get_tree().paused and not GameSession.is_paused():
		_talk_real_wait -= delta
	if now < _talk_next_at or _talk_real_wait > 0.0:
		return
	if not is_in_gameplay() or not modals.is_empty() or router.is_busy() or GameSession.is_asleep() or get_tree().paused \
			or toasts.get_child_count() > 0 or hud.is_warning_visible() or not GameSession.get_pending_bite().is_empty() \
			or is_instance_valid(voyage_map) or (academy != null and academy.card.visible):
		return  # not now: the remark waits for a quiet moment (no tip card either)
	var crew := GameSession.get_companions()
	if crew.is_empty():
		return  # sailing alone: the Captain keeps their own counsel (I025)
	var who := CompanionRemarks.identity(crew[0])
	var hours := (now - departed) / 3600.0
	var stage := CompanionRemarks.passage_stage(hours)
	var lines := CompanionRemarks.passage_lines(who, stage).filter(func(l: String) -> bool: return not l in _talk_said)
	if lines.is_empty():
		_talk_said.clear()
		lines = CompanionRemarks.passage_lines(who, stage)
	var seed := absi(hash("%d:%d" % [int(departed), _talk_count]))
	# I025: with two companions, the remark is sometimes to one of them,
	# sometimes about both - one remark, never twice as many.
	var addressed := 0
	var pair_lines: Array[String] = []
	if crew.size() == 2:
		addressed = (seed / 3) % 2
		who = CompanionRemarks.identity(crew[addressed])
		var other := CompanionRemarks.identity(crew[1 - addressed])
		pair_lines.assign(CompanionRemarks.passage_pair_lines(who, other, stage).filter(func(l: String) -> bool: return not l in _talk_said))
		lines = CompanionRemarks.passage_lines(who, stage).filter(func(l: String) -> bool: return not l in _talk_said)
		if lines.is_empty():
			lines = CompanionRemarks.passage_lines(who, stage)
	var key: String = lines[seed % lines.size()]
	var text := CompanionRemarks.say(who, key)
	var about_both := false
	if crew.size() == 2 and not pair_lines.is_empty() and seed % 3 == 0:
		key = pair_lines[(seed / 11) % pair_lines.size()]
		text = CompanionRemarks.say_pair(who, CompanionRemarks.identity(crew[1 - addressed]), key)
		about_both = true
	_talk_said.append(key)
	_talk_count += 1
	# Its response, when it is here to hear it (and awake); sometimes nothing.
	var area := router.current_screen as BoatArea
	var nodes := area.get_companion_nodes() if area else ([] as Array[ShipCompanion])
	var companion: ShipCompanion = nodes[addressed] if addressed < nodes.size() else null
	if companion and companion.visible and companion.pose != CompanionVisualSet.POSE_SLEEPING:
		var answer := CompanionRemarks.response(who, seed / 7)
		if companion.respond(answer.clip) and answer.text != "":
			text += "\n" + String(answer.text)
	# A remark about both: now and then the other one answers too.
	var other: ShipCompanion = nodes[1 - addressed] if about_both and nodes.size() == 2 else null
	if other and other.visible and other.pose != CompanionVisualSet.POSE_SLEEPING:
		var reply := CompanionRemarks.pair_response(CompanionRemarks.identity(crew[1 - addressed]), seed / 13)
		if other.respond(reply.clip) and reply.text != "":
			text += "\n" + String(reply.text)
	toasts.show_message(text, ANCHOR_MOMENT_SECONDS)
	SessionLog.write("passage_talk", {"hours": snappedf(hours, 0.1), "stage": stage, "line": key})
	var gap := CompanionRemarks.PASSAGE_GAP_HOURS[stage] * 3600.0
	_talk_next_at = now + gap * (0.8 + 0.5 * float(seed % 100) / 100.0)
	_talk_real_wait = CompanionRemarks.PASSAGE_MIN_REAL_SECONDS


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
	hud.instruments_requested.connect(open_instruments)
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
	# (static: connected once, however many Apps have run in this process)
	for changed: Signal in [GameSession.session_started, GameSession.state_replaced, GameSession.session_ended]:
		if not changed.is_connected(DevTools.on_session_changed):
			changed.connect(DevTools.on_session_changed)
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
	# The development build identifier, bottom right, over every screen.
	var build_label_layer := BuildLabel.create_layer()
	if build_label_layer:
		add_child(build_label_layer)
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
	_update_passage_talk(delta)
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
	elif GameSession.is_active() and is_on_quay():
		place = "deck"  # out in the open on the quay (I026)
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
	if event.is_action_pressed(&"tack") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy() and GameSession.is_underway():
			get_viewport().set_input_as_handled()
			tack_now()
		return
	if event.is_action_pressed(&"reel_in") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy() and not is_on_quay():
			get_viewport().set_input_as_handled()
			open_fishing()
		return
	if event.is_action_pressed(&"chartplotter") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			open_chartplotter()
		return
	if event.is_action_pressed(&"instruments") and not event.is_echo():
		if is_in_gameplay() and modals.is_empty() and not router.is_busy():
			get_viewport().set_input_as_handled()
			open_instruments()
		return
	if not event.is_action_pressed(&"pause") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if router.is_busy():
		return
	if not modals.is_empty():
		modals.handle_back()
	elif router.current_screen is BoatArea or router.current_screen is HarbourFront:
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
	return GameSession.is_active() and (router.current_screen is BoatArea or router.current_screen is HarbourFront)


# --- Main flow -------------------------------------------------------------------

func show_main_menu() -> void:
	modals.clear()
	GameSession.end_session()
	AudioManager.stop_ambience()
	AudioManager.stop_music()
	update_engine_audio()
	router.change_screen(main_menu_scene, _connect_main_menu)


## New Game asks for the ship's companion first (I024: Ragdoll cat, Pug or
## parrot, with an optional name and gender).
func open_new_game_menu() -> void:
	if not modals.is_empty() or router.is_busy():
		return
	var menu := new_game_menu_scene.instantiate() as NewGameMenu
	# I025: a new game begins without a companion (kind "").
	menu.start_requested.connect(func(level: StringName) -> void: start_new_game(&"", level))
	modals.push(menu)


func start_new_game(companion_kind: StringName = CompanionState.DEFAULT_KIND, level: StringName = Difficulty.STANDARD,
		companion_name := "", companion_gender: StringName = &"") -> void:
	modals.clear()
	GameSession.start_new_session(companion_kind, level, companion_name, companion_gender)
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
	if router.is_busy() or not (router.current_screen is BoatArea or router.current_screen is HarbourFront):
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

# --- Marine electronics (I026 stage 03) ----------------------------------------------------------

## The helm's chartplotter, close up (P, the action wheel, the plotter at
## the helm). Aboard, in harbour or at sea; Esc closes.
func open_chartplotter() -> PlotterView:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	var view := PlotterView.new()
	modals.push(view)
	return view


## The instruments, close up: the fitted package's units with their pages
## and the package selector (I, the action wheel, a click on the HUD's
## instruments or on the units at the helm). Esc closes.
func open_instruments() -> InstrumentView:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	var view := InstrumentView.new()
	modals.push(view)
	return view


## The actions that make sense here, for the action wheel:
## [{"id", "label", "action"}, plus "checked" (a Callable read when the wheel
## opens) for the on/off ones]. Existing actions only.
func get_wheel_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_on_quay():
		return _quay_wheel_actions()
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
		# I024: postcards, travel updates, the little game and the achievements
		# all live on the laptop now (one item instead of two).
		add.call(&"laptop", Loc.t("Laptop"), func() -> void: open_laptop.call_deferred())
		if GameSession.is_underway():
			# I026: the instruments from below (the essentials never need a walk).
			add.call(&"instruments", Loc.t("Instruments"), func() -> void: open_instruments.call_deferred())
	else:
		if GameSession.is_underway():
			# On/off items show a check mark read from the setting itself (Cozy Polish).
			# I026: the plotter and the instruments are devices at the helm now
			# (their focused views); the radar stays an on/off display.
			add.call(&"chartplotter", Loc.t("Chart plotter"), func() -> void: open_chartplotter.call_deferred())
			add.call(&"instruments", Loc.t("Instruments"), func() -> void: open_instruments.call_deferred())
			add.call(&"radar", "Radar", func() -> void: RadarPanel.shown = not RadarPanel.shown)
			actions.back().checked = func() -> bool: return RadarPanel.shown
			if not GameSession.is_anchored():
				add.call(&"sail_trim", Loc.t("Trim sails"), func() -> void: open_sail_trim.call_deferred())
				# I027: the choice to windward - motor straight up, at a fuel cost.
				add.call(&"motor_upwind", Loc.t("Motor to windward"), func() -> void:
					GameSession.set_motor_upwind(not GameSession.is_motoring_upwind())
					Simulation.evaluate_propulsion(false, true)
					notify(Loc.t("To windward the engine takes over while there is fuel.") if GameSession.is_motoring_upwind()
						else Loc.t("To windward the boat beats under sail.")))
				actions.back().checked = func() -> bool: return GameSession.is_motoring_upwind()
				# I027: tacking or gybing by hand while the autopilot zigzags.
				var course := GameSession.get_voyage_course()
				if int(course.get("tack_side", 0)) != 0 and not GameSession.get_propulsion().is_motoring():
					add.call(&"tack", Loc.t("Gybe now") if _is_gybing() else Loc.t("Tack now"), func() -> void: tack_now())
			if GameSession.is_anchored() or GameSession.anchoring_refusal() == "" or GameSession.is_holding_at_anchorage():
				add.call(&"anchor", "Anchor", func() -> void: open_anchor())
			if GameSession.is_holding_at_anchorage():
				add.call(&"sail_on", Loc.t("Sail on from the anchorage"), func() -> void:
					var error := GameSession.sail_on_from_anchorage()
					notify(Loc.t("Sailing on along the course.") if error == "" else error))
		elif GameSession.get_planned_route() != null:
			add.call(&"set_sail", Loc.t("Set sail"), request_departure)
		if GameSession.is_companion_ashore():
			var ashore: Array[Dictionary] = []
			for companion in GameSession.get_companions_ashore():
				ashore.append(CompanionRemarks.identity(companion))
			add.call(&"call_aboard", CompanionRemarks.call_all_aboard_label(ashore), recall_companion)
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
	if area == null:
		wheel.setup(get_wheel_actions(), Loc.t("On the quay"))
		modals.push(wheel)
		return wheel
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
	# I024: never without the companion. It is fetched first, then the
	# departure question follows as usual.
	if GameSession.is_companion_ashore():
		var ashore: Array[Dictionary] = []
		for companion in GameSession.get_companions_ashore():
			ashore.append(CompanionRemarks.identity(companion))
		var fetch: bool = await modals.confirm(CompanionRemarks.still_ashore_all(ashore),
			CompanionRemarks.ashore_hint(ashore[0]) if ashore.size() == 1 else Loc.t("Both are still exploring the pontoon."),
			CompanionRemarks.call_all_aboard_label(ashore))
		if not fetch:
			return
		recall_companion()
		if GameSession.is_companion_ashore():
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


## A tack (or gybe) by hand (I027; K, or the wheel): the autopilot takes the
## other side at once and keeps it a while. Says what happened, or why not.
func tack_now() -> void:
	var gybe := _is_gybing()
	var refusal := Simulation.manual_tack()
	if refusal != "":
		notify(refusal)
		return
	var side := PropulsionState.wind_side(GameSession.get_propulsion().true_wind_angle)
	notify((Loc.t("Gybed: now on the %s gybe.") if gybe else Loc.t("Ready about… tacked: now on the %s tack.")) % side)


## True while the zigzag is downwind (gybes rather than tacks).
func _is_gybing() -> bool:
	return GameSession.is_underway() and absf(GameSession.get_propulsion().true_wind_angle) > 90.0


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
	FocusFrame.attach(menu, FocusFrame.Kind.TEAK)  # I026: by the berth


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
	var companion_line := ""
	if result.stopped_by != Simulation.STOP_RESCUE:
		companion_line = GameSession.wake_companion(result.elapsed_seconds)  # I024: by the berth
		_wake_in_berth()
	if TimePassage.is_shown():
		snap_light()
	return {"result": result, "wake_line": wake_line, "companion_line": companion_line}


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
	elif result.stopped_by == Simulation.STOP_NONE and not String(outcome.get("companion_line", "")).is_empty():
		# I024: a small morning moment with the companion - only when nothing
		# more important woke the Captain.
		toasts.show_message(outcome.companion_line, ANCHOR_MOMENT_SECONDS)


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
	return GameSession.is_active() and (router.current_screen is BoatArea or router.current_screen is WorldMap or is_on_quay()) \
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
	FocusFrame.attach(menu, FocusFrame.Kind.TEAK)  # I026: the locker, opened


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
	modals.push(GroceryMenu.new())


# --- Harbour trades (I020) ------------------------------------------------------------------

## The fishmonger (next to the grocery store): where the catch is sold.
func open_fishmonger() -> FishmongerMenu:
	return _open_trade(HarbourFacilities.FISHMONGER, FishmongerMenu.new()) as FishmongerMenu


## The chandlery (its own storefront on the quay since I026; electronics too).
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
	FocusFrame.attach(menu, FocusFrame.Kind.STEEL)  # I026: at the stove
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
	var board := TrophyMenu.new()
	modals.push(board)
	FocusFrame.attach(board, FocusFrame.Kind.TEAK)  # I026: the board, up close


## A harbour service that is not offered here (Iteration 12): say so, log it.
func _refuse_facility(facility: StringName) -> void:
	notify(GameSession.facility_refusal(facility))
	SessionLog.write("facility", {"facility": String(facility), "outcome": "unavailable", "port": String(GameSession.get_location_id())})


## The Captain's laptop at the cabin table (I024, LaptopView): renown,
## publications, the achievement collection, a voyage history, remote work
## and the little game, all on its screen. The work station opens it.
func open_laptop(start_app: StringName = LaptopView.APP_HOME) -> LaptopView:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	var laptop := LaptopView.new(start_app)
	laptop.name = "LaptopView"
	laptop.postcard_requested.connect(func() -> void: make_postcard.call_deferred())
	laptop.work_requested.connect(func(hours: int) -> void: work_for.call_deferred(hours))
	laptop.game_work_requested.connect(func(task_id: String, choice: int) -> void: work_on_game.call_deferred(task_id, choice))
	laptop.publish_confirmed.connect(publish_travel_update)
	modals.push(laptop)
	SessionLog.write("laptop", {"app": String(start_app), "port": String(GameSession.get_location_id())})
	return laptop


## Remote work, on the laptop (in harbour only).
func open_work_menu() -> WorkMenu:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	if not GameSession.can_work_remotely():
		notify(Loc.t("Remote work needs a steady connection: moor in a harbour first."))
		return null
	var laptop := open_laptop()
	return laptop.open_work() if laptop else null


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


## Postcards from the Sea (I022): from the cabin, on the laptop (I024).
func open_postcards() -> PostcardMenu:
	var laptop := open_laptop(LaptopView.APP_PUBLICATIONS)
	return laptop.open_postcards() if laptop else null


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
		notify(Loc.t("Interrupted after %s: %s. The postcard is kept; finish it later on the laptop in the cabin (Publications). It is %s.") % [
			Simulation.format_duration(result.elapsed_seconds), interruption_reason(result.stopped_by), now])


## A Game Developer at Sea (I022): from the cabin, on the laptop (I024).
func open_game_dev() -> GameDevMenu:
	var laptop := open_laptop()
	return laptop.open_game() if laptop else null


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
	hud.show_warning(String(info.text), Loc.t("Traffic warning"))
	if not GameSession.is_asleep():
		notify(String(info.text))


## A call on the VHF (I019): a short radio sound, and the call is shown as
## soon as nothing else is open (after waking, after the voyage map).
func _on_vhf_call(call: Dictionary) -> void:
	AudioManager.play_sfx(FishingSounds.bite(), FishingSounds.DB)
	_pending_vhf = call
	_update_vhf_lamp()
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
	if area == null:
		return  # on the quay (I026): the boat is already alongside
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
	# I025: the animal from the dock followed the Captain home - the question
	# comes just before going below.
	var boat := router.current_screen as BoatArea
	var dock := boat.get_dock_encounter_scene() if boat and boat.area_id == SessionState.AREA_EXTERIOR else null
	if dock and area == SessionState.AREA_INTERIOR and dock.is_following():
		var choice: Array = await ask_about_dock_animal(dock.kind)
		match choice[0]:
			AdoptionDialog.CHOICE_ADOPT:
				var companion := GameSession.adopt_dock_animal(String(choice[1]), StringName(choice[2]))
				if companion:
					notify(CompanionRemarks.welcomed_line(companion, GameSession.get_location().display_name if GameSession.get_location() else ""))
			AdoptionDialog.CHOICE_DECLINE:
				boat.cancel_exit()
				dock.decline()
				return
			_:
				boat.cancel_exit()
				return
	GameSession.enter_boat_area(area, spawn_point)
	_show_current_boat_area()


## The companionway question (AdoptionDialog). Returns [choice, name, gender].
func ask_about_dock_animal(kind: StringName) -> Array:
	var dialog := AdoptionDialog.new(kind)
	dialog.name = "AdoptionDialog"
	modals.push(dialog)
	return await dialog.decided


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
	if not modals.is_empty() or not (router.current_screen is BoatArea or router.current_screen is WorldMap or is_on_quay()):
		return
	open_captains_log()


func open_captains_log() -> CaptainsLogMenu:
	if not GameSession.is_active():
		return null
	var menu := CaptainsLogMenu.new()
	menu.name = "CaptainsLogMenu"
	menu.publish_requested.connect(open_publish_menu)
	modals.push(menu)
	FocusFrame.attach(menu, FocusFrame.Kind.BOOK)  # I026: the logbook (L opens the same book)
	return menu


# --- The things a sailor uses below (I026, CabinObject) -----------------------------

## A cabin object was used (BoatArea.cabin_object_requested): its focused view.
func open_cabin_object(kind: StringName) -> ModalPanel:
	if not is_in_gameplay() or router.is_busy() or not modals.is_empty():
		return null
	match kind:
		CabinObject.LOGBOOK:
			return open_captains_log()
		CabinObject.VHF:
			return open_vhf_set()
		CabinObject.SYSTEMS:
			var systems := SystemsView.new()
			systems.name = "SystemsView"
			modals.push(systems)
			FocusFrame.attach(systems, FocusFrame.Kind.ELECTRIC)
			return systems
		CabinObject.CHEST:
			return open_cabin_home()
		CabinObject.POSTCARD:
			var scrapbook := ScrapbookMenu.new()
			scrapbook.name = "ScrapbookMenu"
			modals.push(scrapbook)
			FocusFrame.attach(scrapbook, FocusFrame.Kind.TEAK)
			return scrapbook
	return null


## The VHF set at the nav station: channel 16, a call waiting (answered here
## with the same dialog), the weather broadcast.
func open_vhf_set() -> VhfSetView:
	var view := VhfSetView.new(_pending_vhf)
	view.name = "VhfSetView"
	view.answer_requested.connect(func(call: Dictionary) -> void:
		_pending_vhf = {}
		_update_vhf_lamp()
		show_vhf_dialog.call_deferred(call))
	modals.push(view)
	FocusFrame.attach(view, FocusFrame.Kind.RADIO)
	return view


## The VHF set's lamp blinks while a call waits.
func _update_vhf_lamp() -> void:
	var area := router.current_screen as BoatArea
	var radio := area.get_cabin_object(CabinObject.VHF) if area else null
	if radio:
		radio.call_waiting = not _pending_vhf.is_empty()


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
	menu.care_requested.connect(open_boat_care)
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


# --- The quay (I026 stage 02, living harbours) -------------------------------------------
# The harbour's waterfront (HarbourFront), up the pontoon's walkway: every
# business in its own building, opening its existing menu in a shop-counter
# frame (ShopCounter), on its own opening hours (BusinessHours). A screen
# like the chart: GameSession keeps the Captain on deck, on the pontoon by
# the walkway, so saving here saves them there and loading returns aboard.

const HARBOUR_FRONT_SCENE := preload("res://src/harbour/harbour_front.tscn")
## The business whose counter the open menus belong to (for the frame).
var _quay_business: StringName = &""


func is_on_quay() -> bool:
	return router.current_screen is HarbourFront


func get_quay() -> HarbourFront:
	return router.current_screen as HarbourFront


## Up the walkway to the quay (from the deck, moored in harbour).
func open_quay() -> void:
	if not GameSession.is_active() or router.is_busy() or not modals.is_empty() or not GameSession.is_moored_in_harbour():
		var deck := router.current_screen as BoatArea
		if deck:
			deck.cancel_exit()
		return
	var area := router.current_screen as BoatArea
	if area:
		var back := area.get_walkway_return_point()
		if back != Vector2.INF:
			GameSession.set_player_position(back)
	SessionLog.write("quay_enter", {"port": String(GameSession.get_location_id())})
	router.change_screen(HARBOUR_FRONT_SCENE, _connect_harbour_front)


## Back down the walkway: aboard, on the pontoon by the walkway.
func leave_quay() -> void:
	if not is_on_quay() or router.is_busy():
		return
	modals.clear()
	_quay_business = &""
	SessionLog.write("quay_leave", {"port": String(GameSession.get_location_id())})
	_show_current_boat_area()


func _connect_harbour_front(front: HarbourFront) -> void:
	front.place_requested.connect(_on_quay_place)
	front.leave_requested.connect(leave_quay)
	front.message_requested.connect(notify)
	front.interaction_prompt_changed.connect(hud.set_prompt)


## A door (or the hatch, the noticeboard, the lane, the travel lift) on the
## quay was used: its menu in its counter's frame, or - closed - the offer
## to wait until it opens.
func _on_quay_place(place: StringName) -> void:
	var front := get_quay()
	if front == null or router.is_busy() or not modals.is_empty():
		return
	var port := GameSession.get_location_id()
	var now := GameSession.get_game_time()
	_quay_business = place
	match place:
		QuayLayout.NOTICEBOARD:
			open_noticeboard()
		HarbourFront.FUEL:
			open_fuel_berth()
		HarbourFront.HATCH:
			open_harbour_office(true)
		QuayLayout.LANE:
			open_go_ashore()
		HarbourFront.TRAVEL_LIFT:
			_quay_business = QuayLayout.BOATYARD
			if not BusinessHours.is_open(QuayLayout.BOATYARD, port, now):
				ask_wait_until_open(QuayLayout.BOATYARD)
			else:
				open_boat_care()
		_:
			if not BusinessHours.is_open(place, port, now):
				ask_wait_until_open(place)
				return
			match place:
				QuayLayout.BOATYARD:
					open_boatyard()
				QuayLayout.CHANDLERY:
					open_chandlery()
				QuayLayout.SAIL_LOFT:
					open_sailmaker()
				QuayLayout.GROCERY:
					open_grocery()
				QuayLayout.FISHMONGER:
					open_fishmonger()
				QuayLayout.CAFE:
					open_cafe()
				QuayLayout.HARBOUR_OFFICE:
					open_harbour_office(false)
	_frame_quay_modal()


## The menus that open from a counter on the quay get its frame.
func _frame_quay_modal() -> void:
	if not is_on_quay() or _quay_business.is_empty():
		return
	var top := modals.get_top()
	if top == null or top.has_node(^"ShopCounter"):
		return
	if top is BoatyardMenu or top is BoatCareMenu or top is HaulOutPanel or top is TradePanel or top is GroceryMenu or top is CafeMenu \
			or top is HarbourOfficeMenu or top is NoticeboardMenu or top is GoAshoreMenu:
		ShopCounter.attach(top, _quay_business, get_quay().layout.archetype)


## A closed door: when it opens, and the offer to wait for it (the time
## passes as when working or sleeping; anything that needs the Captain
## stops it). The harbour office's hatch is always open.
func ask_wait_until_open(business: StringName) -> void:
	var port := GameSession.get_location_id()
	var now := GameSession.get_game_time()
	var at := BusinessHours.next_opening(business, port, now)
	var name := HarbourFront.business_name(business)
	var wait: bool = await modals.confirm(Loc.t("%s: closed") % name,
		Loc.t("It opens at %s local time, in %s. Wait on the quay until then? Time passes as usual, and anything that needs you will interrupt the wait.") % [
			BusinessHours.format_hour(BusinessHours.local_hours(port, at)), Simulation.format_duration(at - now)],
		Loc.t("Wait until it opens"), Loc.t("Not now"))
	if wait:
		await wait_until_open(business)


## Waits on the quay until `business` opens (TimePassage, as sleeping).
func wait_until_open(business: StringName) -> void:
	var port := GameSession.get_location_id()
	var now := GameSession.get_game_time()
	var minutes := ceilf((BusinessHours.next_opening(business, port, now) - now) / 60.0) + 1.0
	if minutes <= 1.0:
		return
	SessionLog.write("quay_wait", {"business": String(business), "minutes": minutes})
	var result: Simulation.AdvanceResult = await pass_time(func() -> Simulation.AdvanceResult: return Simulation.spend_time_ashore(minutes))
	if result.stopped_by == Simulation.STOP_RESCUE:
		return
	var stopped := interruption_reason(result.stopped_by)
	var clock := Simulation.format_game_time(GameSession.get_game_time())
	if not stopped.is_empty():
		notify(Loc.t("Interrupted: %s. It is %s.") % [stopped, clock])
	else:
		notify(Loc.t("%s is open now. It is %s.") % [HarbourFront.business_name(business), clock])
	var front := get_quay()
	if front:
		front.refresh()


## The café's counter: order a coffee and sit on the terrace.
func open_cafe() -> CafeMenu:
	if not is_on_quay() or not modals.is_empty():
		return null
	var menu := CafeMenu.new()
	menu.order_requested.connect(_on_cafe_order)
	modals.push(menu)
	return menu


func _on_cafe_order() -> void:
	var front := get_quay()
	if front == null:
		return
	if front.free_seat() < 0:
		notify(Loc.t("Every table on the terrace is taken just now. Try again in a little while."))
		return
	var result := GameSession.buy_cafe_coffee()
	if not String(result.error).is_empty():
		notify(result.error)
		return
	modals.clear()
	front.sit_at_cafe()
	notify(Loc.t("A coffee on the terrace for %s. Stay as long as you like.") % GameSession.format_money(int(result.price)))


## The harbour office (or, after hours, its hatch).
func open_harbour_office(hatch: bool) -> HarbourOfficeMenu:
	if not GameSession.is_active() or not modals.is_empty():
		return null
	var menu := HarbourOfficeMenu.new()
	menu.hatch = hatch
	var front := get_quay()
	if front:
		menu.layout = front.layout
	menu.repair_requested.connect(_on_hatch_repair)
	modals.push(menu)
	return menu


## The hatch's emergency repair: the yard's own repair, its time ashore.
func _on_hatch_repair() -> void:
	var result := GameSession.perform_service(BoatCare.SERVICE_REPAIR)
	if not String(result.error).is_empty():
		notify(result.error)
		return
	modals.clear()
	notify(Loc.t("The yard's night man sees to the hull for %s. The work takes %s.") % [GameSession.format_money(int(result.cost)),
		Simulation.format_duration(float(result.minutes) * 60.0)])
	await pass_time(func() -> Simulation.AdvanceResult: return Simulation.spend_time_ashore(float(result.minutes)))


## The fuel berth's pump on the quay (I027): open at any hour.
func open_fuel_berth() -> FuelMenu:
	if not GameSession.is_active() or not modals.is_empty() or not GameSession.is_moored_in_harbour():
		return null
	var menu := FuelMenu.new()
	modals.push(menu)
	FocusFrame.attach(menu, FocusFrame.Kind.STEEL)
	return menu


func open_noticeboard() -> NoticeboardMenu:
	if not GameSession.is_active() or not modals.is_empty():
		return null
	var menu := NoticeboardMenu.new()
	modals.push(menu)
	return menu


## The action wheel on the quay: back to the boat, standing up from the
## café table, calling the companions aboard, the coffee mug, the log.
func _quay_wheel_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var front := get_quay()
	var add := func(id: StringName, label: String, action: Callable) -> void:
		actions.append({"id": id, "label": label, "action": action})
	if front.is_seated():
		add.call(&"stand_up", Loc.t("Stand up"), front.stand_up)
	add.call(&"back_aboard", Loc.t("Back to the boat"), func() -> void: front.leave())
	if GameSession.is_companion_ashore():
		var ashore: Array[Dictionary] = []
		for companion in GameSession.get_companions_ashore():
			ashore.append(CompanionRemarks.identity(companion))
		add.call(&"call_aboard", CompanionRemarks.call_all_aboard_label(ashore), recall_companion)
	if GameSession.is_carrying_coffee():
		add.call(&"coffee_finish", Loc.t("Finish the coffee"), func() -> void: notify(GameSession.finish_coffee()))
	add.call(&"log", Loc.t("Captain's Log"), toggle_captains_log)
	return actions


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
	area.work_requested.connect(open_laptop)
	area.grocery_requested.connect(open_grocery)
	area.go_ashore_requested.connect(open_go_ashore)
	area.fishing_requested.connect(open_fishing)
	area.trophies_requested.connect(open_trophies)
	area.cooking_requested.connect(open_cooking)
	area.anchor_requested.connect(open_anchor)
	area.quay_requested.connect(open_quay)
	area.cabin_object_requested.connect(func(kind: StringName) -> void: open_cabin_object(kind))
	area.trim_requested.connect(func() -> void: open_sail_trim())
	_update_vhf_lamp.call_deferred()
	area.instruments_requested.connect(open_instruments)
	area.chartplotter_requested.connect(open_chartplotter)


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
	_hud_layer.visible = area != null or screen is WorldMap or screen is HarbourFront
	hud.set_chart_mode(screen is WorldMap)
	# On the chart, notifications are centred over the map like the clock bar.
	var toast_shift := -Hud.CHART_SIDEBAR_WIDTH / 2.0 if screen is WorldMap else 0.0
	toasts.offset_left = _toast_offsets.x + toast_shift
	toasts.offset_right = _toast_offsets.y + toast_shift
	hud.set_prompt("")
	if area:
		hud.set_area(area.area_id)
		hud.refresh()
	elif screen is HarbourFront:
		hud.set_area_title(Loc.t("The quay"))
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
	# I026: a menu opened from a counter on the quay wears its frame.
	if depth == 0:
		_quay_business = &""
	else:
		_frame_quay_modal()
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
