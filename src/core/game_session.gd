extends Node
## Authoritative owner of the active game session's state.
##
## GameSession holds a SessionState and is the only code that mutates it.
## Scenes read from it and request changes through its methods; it announces
## changes with signals. It never loads scenes or touches the UI, so the state
## stays valid whichever scene (cabin, deck, map, menu) is currently visible.

signal session_started
signal session_ended
## Emitted after a loaded state has replaced the current one.
signal state_replaced
signal boat_area_changed(area: StringName)
## `route` is a PlannedRoute, or null when the route was cleared.
signal route_changed(route: PlannedRoute)
signal time_scale_changed(scale: int)
## The player paused or resumed the simulation clock.
signal pause_changed(paused: bool)
signal voyage_started
## The active voyage's course was replaced (change of course at sea).
signal voyage_course_changed
signal voyage_arrived(port_id: StringName)
## Sail <-> engine changed (or propulsion ended on arrival: mode is then &"").
signal propulsion_changed(mode: StringName)
## The sail trim changed (Iteration 18).
signal sail_trim_changed
## The boat arrived at an anchorage waypoint and waits there (Iteration 18).
signal anchorage_reached(waypoint_index: int)
## The player switched boats at the boatyard.
signal vessel_changed(vessel_id: StringName)
## The ship's companion moved to another resting spot (see CompanionState).
signal companion_moved(spot: StringName)
## The companion went up on deck or down to the cabin (Iteration 18).
signal companion_area_changed(area: StringName)
## Something the player should be told that is not an error of their action
## (e.g. an old save's route had to be dropped).
signal notice(text: String)
## The active boat's condition (percent) changed (weather, repair, rescue).
signal condition_changed(percent: float)
signal funds_changed(funds: int)
## Food or water changed noticeably (restock, a new warning level; the
## steady consumption is read every frame by the UI instead).
signal provisions_changed
## Stores ran low (Provisions.WARN_*): given once per level until restocked.
signal provisions_warning(level: int, text: String)
## The boat was lost and its crew rescued: the voyage is over and the boat is
## back in the home harbour. `info` = {"fee", "funds_after", "port_id", "from"}.
signal rescued(info: Dictionary)
## A voyage ended and was written to the Captain's Log (see
## CaptainsLog.make_record()); `new_harbour` is true on a first visit.
signal voyage_logged(record: Dictionary, new_harbour: bool)
## Objectives completed by a voyage or a hat event paid renown: [{"id",
## "title", "reward", "text", "secret", "tone"}]. Emitted once per event,
## after voyage_logged (a voyage) or hat_lost / hat_bought (the hat).
signal renown_awarded(awards: Array)
## A travel update was published: {"renown", "euros", "funds_after"}.
signal travel_update_published(info: Dictionary)
## The captain's hat changed hands: put on, taken off, hung up, lost or
## bought (HatState.STORED / WORN / CARRIED / LOST).
signal hat_changed(status: StringName)
## The coffee mug moved: into a hand, the holder, onto the table, or finished.
signal coffee_changed(place: StringName)
## The wind is strong enough to take a worn hat (once per exposure).
signal hat_warning(text: String)
## The hat blew away: {"time", "text", "log_text", "lost_count", "serial",
## "wind_kn", "gust_kn", "in_harbour", "position": {"lon", "lat"}}.
signal hat_lost(info: Dictionary)
## A replacement hat was bought: {"price", "funds_after", "serial"}.
signal hat_bought(info: Dictionary)
## Iteration 13. A fish took the lure: {"species", "kg", "time"} (a fight
## follows at the rod).
signal fish_bite(info: Dictionary)
## The line went out or came in, a lure was chosen or bought, the cool box
## changed.
signal fishing_changed
## Something about the line needs attention: {"text", "kind"} (e.g. trolling
## too fast).
signal fishing_warning(info: Dictionary)
## A fish was landed: the result of land_fish().
signal fish_landed(result: Dictionary)
## A meal was cooked: the result of cook().
signal meal_cooked(result: Dictionary)
## The anchor went down or up, or its holding changed.
signal anchor_changed
## The anchor needs the captain: {"level": "poor" | "dragging", "text"}.
signal anchor_alarm(info: Dictionary)
## A boat's care record changed: a service, an upgrade, or wear crossing a
## level (Iteration 14). Not emitted for every bit of wear.
signal boat_care_changed
## A boat of your own (I020): cabin things or sailcloth changed.
signal home_changed
## I022: a boat was bought (the owned boats changed).
signal fleet_changed
## I022: the difficulty was changed during the game.
signal difficulty_changed(level: StringName)
## A loaded position or course was invalid under the current chart and was
## moved or re-planned (Iteration 14): {kind, from, to, moved_nm, replanned}.
signal location_recovered(info: Dictionary)
## Life at anchor (0.102b): the boat became settled at anchor, or stopped
## being so (anchor raised, dragging, the wind rose).
signal anchor_life_changed(settled: bool)
## A quiet moment aboard at anchor: kind "settled", "evening", "wake" or
## "pet", and its line. Each happens at most once per stay (or per day).
signal anchor_moment(kind: String, text: String)

const START_LOCATION := &"copenhagen"
## Where a rescued boat is brought back to (fixed in this version).
const HOME_PORT := &"copenhagen"
## Where the player is put aboard after a rescue (a cabin spawn every boat has).
const RESCUE_AREA := SessionState.AREA_INTERIOR
const RESCUE_SPAWN := &"start"
const START_AREA := SessionState.AREA_INTERIOR
const START_SPAWN := &"start"

var _state: SessionState
var _has_unsaved_changes := false


func is_active() -> bool:
	return _state != null


## True when the session changed since it was started, saved or loaded.
func has_unsaved_changes() -> bool:
	return _state != null and _has_unsaved_changes


func _exit_tree() -> void:
	PortCatalog.clear_default()
	ObjectiveCatalog.clear_default()
	HatConfig.clear_default()
	HatArt.clear_default()
	SeaRouter.clear_default()
	WeatherModel.clear_default()
	WindField.clear_default()
	VesselProfile.clear_default()
	VesselCatalog.clear_default()


# --- Lifecycle ----------------------------------------------------------------

## Starts a new game with the chosen ship's companion ("cat" or "dog").
func start_new_session(companion_kind: StringName = CompanionState.DEFAULT_KIND, level: StringName = Difficulty.STANDARD) -> void:
	_state = SessionState.create_new(START_LOCATION, START_AREA, START_SPAWN, companion_kind, level)
	_has_unsaved_changes = false
	_asleep = false
	if _settled:
		_settled = false
		anchor_life_changed.emit(false)
	session_started.emit()


func end_session() -> void:
	if _state == null:
		return
	_state = null
	_has_unsaved_changes = false
	_settled = false
	_asleep = false
	session_ended.emit()


func _ready() -> void:
	# Life at anchor follows every change to the anchor (dropped, adjusted,
	# alarm, raised) without waiting for the next simulation step.
	anchor_changed.connect(_update_anchor_life.bind(false))


## Replaces the whole state at once (used by loading). The caller must pass an
## already validated state; the previous state is untouched until this point.
func replace_state(new_state: SessionState) -> void:
	assert(new_state != null)
	var was_active := _state != null
	_state = new_state.duplicate_state()
	_has_unsaved_changes = false
	_complete_legacy_route()
	_recover_location()
	_check_vessel()
	_asleep = false
	_update_anchor_life(false)
	if not was_active:
		session_started.emit()
	state_replaced.emit()


## A copy of the current state, safe to serialize while the game continues.
func get_state_snapshot() -> SessionState:
	return _state.duplicate_state() if _state else null


func mark_saved() -> void:
	_has_unsaved_changes = false


# --- Boat and player -----------------------------------------------------------

func get_boat_area() -> StringName:
	return _state.boat_area if _state else &""


## Moves the player to another boat area, arriving at `spawn_point`.
func enter_boat_area(area: StringName, spawn_point: StringName) -> void:
	if _state == null or area not in SessionState.BOAT_AREAS:
		push_error("Cannot enter boat area '%s'" % area)
		return
	_state.boat_area = area
	_state.spawn_point = spawn_point
	_state.has_player_position = false
	_has_unsaved_changes = true
	boat_area_changed.emit(area)


func set_player_position(position: Vector2) -> void:
	if _state == null:
		return
	if _state.has_player_position and _state.player_position.is_equal_approx(position):
		return
	_state.player_position = position
	_state.has_player_position = true
	_has_unsaved_changes = true


func has_player_position() -> bool:
	return _state != null and _state.has_player_position


func get_player_position() -> Vector2:
	return _state.player_position if _state else Vector2.ZERO


func get_spawn_point() -> StringName:
	return _state.spawn_point if _state else &""


# --- Clock ---------------------------------------------------------------------------

## Game time in seconds since the Unix epoch (UTC).
func get_game_time() -> float:
	return _state.game_time if _state else 0.0


func get_time_scale() -> int:
	return _state.time_scale if _state else 1


## Selects 1x/5x/20x. Choosing a speed while paused also resumes the clock.
func set_time_scale(scale: int) -> void:
	if _state == null or scale not in SessionState.TIME_SCALES:
		return
	if scale != _state.time_scale:
		_state.time_scale = scale
		_has_unsaved_changes = true
		time_scale_changed.emit(scale)
	set_paused(false)


## True while the player has paused the simulation clock. This is the one
## shared pause: Simulation does not advance time while it is set, in any
## scene. (Menus pausing the scene tree are a separate, temporary thing.)
func is_paused() -> bool:
	return _state.paused if _state else false


## Pauses or resumes the simulation clock; resuming continues at the selected
## time scale.
func set_paused(paused: bool) -> void:
	if _state == null or _state.paused == paused:
		return
	_state.paused = paused
	_has_unsaved_changes = true
	pause_changed.emit(paused)


# --- Vessel and location -------------------------------------------------------

func get_location_id() -> StringName:
	return _state.location_id if _state else &""


## The port the vessel lies in, or null while underway.
func get_location() -> PortData:
	return PortCatalog.get_default().get_port(get_location_id())


func get_vessel_status() -> StringName:
	return _state.vessel_status if _state else &""


func is_underway() -> bool:
	return _state != null and _state.vessel_status == SessionState.STATUS_UNDERWAY


func get_vessel_position() -> Vector2:
	return _state.vessel_position if _state else Vector2.ZERO


## Current speed through the water in knots (0 when not underway).
func get_vessel_speed_kn() -> float:
	return _state.propulsion.speed_kn if is_underway() and not _state.anchor.active and not is_holding_at_anchorage() else 0.0


## The boat's performance profile (one starter boat for now).
## Sailing performance of the active vessel.
func get_vessel_profile() -> VesselProfile:
	var base := get_base_vessel_profile()
	if _state == null:
		return base
	# Wear (Iteration 14) costs a little speed and makes a worn rig take
	# weather a little worse: a copy of the boat's profile with those applied,
	# cached while the effect stays the same (to the half percent).
	var effects := BoatCare.effects(_state.get_boat_care(_state.vessel_id), _state.game_time)
	var key := "%s|%.3f|%.3f|%.3f" % [_state.vessel_id, snappedf(effects.sail, 0.005), snappedf(effects.engine, 0.005),
		snappedf(effects.damage, 0.005)]
	if key == "%s|1.000|1.000|1.000" % _state.vessel_id:
		return base
	if key != _profile_key:
		_profile_key = key
		_profile = base.duplicate() as VesselProfile
		_profile.max_sail_speed_kn = base.max_sail_speed_kn * snappedf(effects.sail, 0.005)
		_profile.engine_speed_kn = base.engine_speed_kn * snappedf(effects.engine, 0.005)
		_profile.weather_damage_factor = base.weather_damage_factor * snappedf(effects.damage, 0.005)
	return _profile


## The boat's own performance, without wear.
func get_base_vessel_profile() -> VesselProfile:
	var vessel := get_vessel_definition()
	return vessel.performance if vessel and vessel.performance else VesselProfile.get_default()


var _profile: VesselProfile
var _profile_key := ""


## The boat the player owns (the starter boat when no game is running).
func get_vessel_definition() -> VesselDefinition:
	var catalog := VesselCatalog.get_default()
	if _state == null:
		return catalog.get_starter()
	var vessel := catalog.get_vessel(_state.vessel_id)
	return vessel if vessel else catalog.get_starter()


func get_vessel_id() -> StringName:
	return _state.vessel_id if _state else VesselCatalog.STARTER_ID


## True when the boatyard may be used: in harbour, not on a passage, and the
## harbour has a boatyard (Iteration 12).
func can_change_vessel() -> bool:
	return has_facility(HarbourFacilities.BOATYARD)


## True when moored in a harbour that offers `facility` (HarbourFacilities).
func has_facility(facility: StringName) -> bool:
	return is_moored_in_harbour() and get_harbour_facilities().has(facility)


## The facilities of the harbour the boat lies in (defaults at sea).
func get_harbour_facilities() -> HarbourFacilities:
	return HarbourFacilities.for_port(_state.location_id if _state and not is_underway() else &"")


## Why `facility` cannot be used here, or "" when it can.
func facility_refusal(facility: StringName) -> String:
	if not is_moored_in_harbour():
		return Loc.t("The %s is only reachable while moored in harbour.") % HarbourFacilities.describe(facility)
	if not get_harbour_facilities().has(facility):
		return Loc.t("There is no %s in %s.") % [HarbourFacilities.describe(facility), get_location().display_name]
	return ""


# --- Pastimes (I022): postcards and the little game -------------------------------------------

func get_pastimes() -> PastimesState:
	return _state.pastimes if _state else PastimesState.new()


## Starts (or replaces) the postcard being made: a subject from
## Pastimes.subjects(), a caption index and a layout.
func set_postcard_draft(kind: String, subject: String, caption: int, layout: String) -> void:
	if _state == null:
		return
	var minutes: float = float(_state.pastimes.draft.get("minutes", 0.0)) if _state.pastimes.draft.get("subject") == subject \
		and _state.pastimes.draft.get("kind") == kind else 0.0
	_state.pastimes.draft = {"kind": kind, "subject": subject, "caption": caption, "layout": layout if layout in Pastimes.LAYOUTS else "classic",
		"minutes": minutes}
	_has_unsaved_changes = true


func abandon_postcard() -> void:
	if _state and not _state.pastimes.draft.is_empty():
		_state.pastimes.draft = {}
		_has_unsaved_changes = true


## Minutes still needed for the postcard being made.
func postcard_minutes_left() -> float:
	if _state == null or _state.pastimes.draft.is_empty():
		return Pastimes.postcard_minutes()
	return maxf(Pastimes.postcard_minutes() - float(_state.pastimes.draft.minutes), 0.0)


## `minutes` were spent on the draft (the one clock has already passed them).
## When it is done it goes into the scrapbook, and a subject posted for the
## first time earns renown. Returns {"done": bool, "award": {} or the award}.
func work_on_postcard(minutes: float) -> Dictionary:
	if _state == null or _state.pastimes.draft.is_empty():
		return {"done": false, "award": {}}
	var draft := _state.pastimes.draft
	draft.minutes = float(draft.minutes) + maxf(minutes, 0.0)
	_has_unsaved_changes = true
	if float(draft.minutes) < Pastimes.postcard_minutes() - 0.5:
		return {"done": false, "award": {}}
	var card := {"kind": draft.kind, "subject": draft.subject, "caption": int(draft.caption), "layout": draft.layout,
		"time": _state.game_time, "place": Pastimes.where_now()}
	_state.pastimes.postcards.append(card)
	var keep := int(Pastimes.postcard_data().get("scrapbook_size", 40))
	while _state.pastimes.postcards.size() > keep:
		_state.pastimes.postcards.remove_at(0)
	_state.pastimes.draft = {}
	var award := _award_once(Pastimes.renown_key(card.kind, card.subject), Loc.t("Postcard: %s") % Pastimes.kind_name(card.kind).to_lower(),
		Pastimes.postcard_renown())
	SessionLog.write("postcard", {"kind": card.kind, "subject": card.subject, "renown": int(award.get("reward", 0))})
	if not award.is_empty():
		renown_awarded.emit([award])
	return {"done": true, "award": award, "card": card}


## A session on the little game: `minutes` of `task_id` were worked (the one
## clock has passed them), with `choice`. Points count for the share of the
## task's hours actually worked; an unfinished task is kept to go on with.
## Returns {"points", "done": bool, "milestone": {} or the milestone reached,
## "award": {}, "euros": int}.
func work_on_game(task_id: String, choice: int, minutes: float) -> Dictionary:
	var out := {"points": 0.0, "done": false, "milestone": {}, "award": {}, "euros": 0}
	var task := Pastimes.task(task_id)
	if _state == null or task.is_empty():
		return out
	var game := _state.pastimes.game
	var total := float(task.hours) * 60.0
	var before := float((game.task as Dictionary).get("minutes", 0.0)) if (game.task as Dictionary).get("id") == task_id else 0.0
	var worked := minf(before + maxf(minutes, 0.0), total)
	var points := Pastimes.session_points(task_id, choice) * (worked - before) / total
	out.points = points
	out.done = worked >= total - 0.5
	game.task = {} if out.done else {"id": task_id, "choice": choice, "minutes": worked}
	if out.done:
		game.sessions = int(game.sessions) + 1
	game.points = float(game.points) + points
	var stones := Pastimes.milestones()
	if int(game.milestone) < stones.size() and float(game.points) >= float(stones[int(game.milestone)].points) - 1e-6:
		var stone: Dictionary = stones[int(game.milestone)]
		game.points = float(game.points) - float(stone.points)
		game.log.append({"milestone": int(game.milestone), "time": _state.game_time})
		game.milestone = int(game.milestone) + 1
		out.milestone = stone
		out.award = _award_once("gamedev:%s" % stone.id, Loc.t("%s: %s") % [Pastimes.game_title(), Loc.t(String(stone.name))],
			int(Pastimes.game_data().get("renown_per_milestone", 4)))
		if int(game.milestone) >= stones.size():
			out.euros = int(Pastimes.game_data().get("release_euros", 0))
			_state.funds += out.euros
			funds_changed.emit(_state.funds)
		if not out.award.is_empty():
			renown_awarded.emit([out.award])
	_has_unsaved_changes = true
	SessionLog.write("game_dev", {"task": task_id, "choice": choice, "minutes": snappedf(minutes, 0.1), "points": snappedf(points, 0.01),
		"milestone": int(game.milestone)})
	return out


## True when every milestone of the little game is done.
func is_game_released() -> bool:
	return _state != null and int(_state.pastimes.game.milestone) >= Pastimes.milestones().size()


## The difficulty of the game being played (Difficulty; Standard without a game).
func get_difficulty() -> StringName:
	return _state.difficulty if _state else Difficulty.STANDARD


## Changes the difficulty during the game (I022): it counts from now on; money
## already spent or earned and the boat's state stay as they are.
func set_difficulty(level: StringName) -> void:
	if _state == null or Difficulty.valid(level) == _state.difficulty:
		return
	_state.difficulty = Difficulty.valid(level)
	_has_unsaved_changes = true
	SessionLog.write("difficulty", {"level": String(_state.difficulty)})
	difficulty_changed.emit(_state.difficulty)


## Tests only (the test runner): every boat counts as owned, so the many
## suites that sail each boat need not buy them first. Ownership tests turn
## it off.
var test_all_boats_owned := false


## True when the captain owns `vessel_id` (I022).
func owns_vessel(vessel_id: StringName) -> bool:
	return _state != null and (vessel_id in _state.owned_vessels or test_all_boats_owned)


func get_owned_vessels() -> Array[StringName]:
	return _state.owned_vessels.duplicate() if _state else ([] as Array[StringName])


## Buys a boat at the boatyard (I022): never twice, never below zero money.
## Returns "" or why not. Moving aboard is then switch_vessel().
func buy_vessel(vessel_id: StringName) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if not can_change_vessel():
		return facility_refusal(HarbourFacilities.BOATYARD)
	var vessel := VesselCatalog.get_default().get_vessel(vessel_id)
	if vessel == null:
		return Loc.t("Unknown boat '%s'.") % vessel_id
	if owns_vessel(vessel_id):
		return Loc.t("The %s is already yours.") % vessel.display_name
	if vessel.price > _state.funds:
		return Loc.t("The %s costs %s; you have %s.") % [vessel.display_name, format_money(vessel.price), format_money(_state.funds)]
	_state.funds -= vessel.price
	_state.owned_vessels.append(vessel_id)
	_state.get_boat_care(vessel_id)
	_has_unsaved_changes = true
	SessionLog.write("vessel_bought", {"vessel": String(vessel_id), "price": vessel.price, "funds": _state.funds})
	funds_changed.emit(_state.funds)
	fleet_changed.emit()
	return ""


## Switches to another boat at the boatyard. Only in harbour; refused (with a
## reason) underway. Everything long-term stays: time, location, planned
## course, companion, saves. The player goes on deck of the new boat at its
## boatyard spawn point; the companion keeps its resting spot, which every
## cabin provides. The propulsion controller starts afresh, so no rolling
## average from the old boat's performance carries over.
func switch_vessel(vessel_id: StringName) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if is_underway():
		return Loc.t("You can only change boats in harbour, not during a passage.")
	if get_location() == null:
		return Loc.t("The boatyard is only available in harbour.")
	if not can_change_vessel():
		return facility_refusal(HarbourFacilities.BOATYARD)
	var vessel := VesselCatalog.get_default().get_vessel(vessel_id)
	if vessel == null:
		return Loc.t("Unknown boat '%s'.") % vessel_id
	if vessel_id == _state.vessel_id:
		return ""
	if not owns_vessel(vessel_id):
		return Loc.t("The %s is not yours yet: buy it first (%s).") % [vessel.display_name, format_money(vessel.price)]
	_state.vessel_id = vessel_id
	_state.get_boat_care(vessel_id)
	# Stores beyond what the new boat can stow stay ashore.
	_state.provisions.food_days = minf(_state.provisions.food_days, maxf(vessel.passage_stores_days, Provisions.CAPACITY_DAYS))
	_state.provisions.water_days = minf(_state.provisions.water_days, maxf(vessel.passage_stores_days, Provisions.CAPACITY_DAYS))
	_state.propulsion = PropulsionState.new()
	_state.fishing.line_out = false
	_pending_bite = {}
	_has_unsaved_changes = true
	enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
	vessel_changed.emit(vessel_id)
	return ""


## A save naming a boat this version does not know falls back to the starter
## boat, and the player is told (the rest of the save is kept).
func _check_vessel() -> void:
	var catalog := VesselCatalog.get_default()
	if catalog.has_vessel(_state.vessel_id):
		return
	var unknown := _state.vessel_id
	_state.vessel_id = catalog.get_starter().id
	if not _state.vessel_id in _state.owned_vessels:
		_state.owned_vessels.append(_state.vessel_id)
	_state.spawn_point = &"start"
	_state.has_player_position = false
	push_warning("Unknown vessel id '%s' in the loaded game; using '%s'." % [unknown, _state.vessel_id])
	notice.emit.call_deferred(Loc.t("The saved boat '%s' is not available; you are aboard the %s.") % [unknown, catalog.get_starter().display_name])


## A copy of the propulsion state (mode, potential speed, wind, sails).
func get_propulsion() -> PropulsionState:
	return _state.propulsion.duplicate_state() if _state else PropulsionState.new()


## True while the engine is driving the boat (never at anchor: anchoring
## stops the engine, 0.105b).
func is_motoring() -> bool:
	return is_underway() and not is_anchored() and _state.propulsion.is_motoring()


## Starting the engine is the crew's job underway (the game has no manual
## engine switch); anything that asks for it while the anchor is down gets
## this answer (0.105b). Returns "" when the engine may run.
func engine_start_refusal() -> String:
	if is_anchored():
		return Loc.t("Let's raise the anchor before starting the engine.")
	return ""


## True while sails are drawing on a voyage (false in port or when motoring).
func are_sails_set() -> bool:
	return is_underway() and _state.propulsion.initialised and _state.propulsion.sails_set()


## A copy of the ship's companion (kind, resting spot, schedule).
func get_companion() -> CompanionState:
	return _state.companion.duplicate_state() if _state else null


## Whether the companion may be on deck now (Iteration 18): moored, or at
## anchor, in reasonable weather (not underway, no gale or rain, not at night
## in strong wind). Underway it stays below, as before.
func companion_may_be_on_deck() -> bool:
	if _state == null or (is_underway() and not is_anchored()):
		return false
	var weather := Simulation.get_weather_at_vessel()
	return weather.speed_kn < COMPANION_DECK_MAX_WIND_KN and WeatherAudio.rain_level(weather) <= 0.0 and not weather.thunder_active


## Moves the companion up on deck (to deck resting place `deck_spot`) or down
## to the cabin. Refused on deck when it may not be there. Returns whether
## it moved.
func set_companion_area(area: StringName, deck_spot := 0) -> bool:
	if _state == null or not area in [CompanionState.AREA_CABIN, CompanionState.AREA_DECK]:
		return false
	if area == CompanionState.AREA_DECK and not companion_may_be_on_deck():
		return false
	var companion := _state.companion
	if companion.area == area and (area == CompanionState.AREA_CABIN or companion.deck_spot == deck_spot):
		return false
	companion.area = area
	companion.deck_spot = clampi(deck_spot, 0, 2)
	_has_unsaved_changes = true
	SessionLog.write("companion_area", {"area": String(area), "deck_spot": companion.deck_spot})
	companion_area_changed.emit(area)
	return true


## Brings the companion below when the deck stops being a place for it (the
## boat sets off, the anchor comes up, the weather turns).
func _companion_to_cabin_if_needed() -> void:
	if _state and _state.companion.area == CompanionState.AREA_DECK and not companion_may_be_on_deck():
		set_companion_area(CompanionState.AREA_CABIN)


func get_wind_seed() -> int:
	return _state.wind_seed if _state else 1


# --- Planned route (in port) ---------------------------------------------------------

## Returns a copy of the planned route, or null.
func get_planned_route() -> PlannedRoute:
	if _state == null or _state.planned_route == null:
		return null
	return _state.planned_route.duplicate_route()


## Calculates a sea route from the current port to `destination_id` and makes
## it the planned route. Returns "" on success, otherwise the reason.
func plan_route_to(destination_id: StringName, waypoints: Array[Vector2] = []) -> String:
	if _state == null or is_underway():
		return Loc.t("A course can only be planned in port.")
	var location := get_location()
	if location == null:
		return Loc.t("The vessel is not in a port.")
	if destination_id == location.id and waypoints.is_empty():
		return Loc.t("The vessel is already in %s.") % location.display_name
	var result := SeaRouter.get_default().plan_route(location.id, location.get_geo_position(), waypoints, destination_id)
	if not result.is_ok():
		return result.error
	return set_planned_route(result.route)


## Makes an already calculated route the planned route, after validating it
## against the chart. Returns "" on success, otherwise the reason.
func set_planned_route(route: PlannedRoute) -> String:
	if _state == null or is_underway():
		return Loc.t("A course can only be planned in port.")
	var location := get_location()
	if location == null or route.origin_port_id != location.id \
			or not route.origin_position.is_equal_approx(location.get_geo_position()):
		return Loc.t("The course must start from %s.") % (location.display_name if location else Loc.t("the vessel"))
	var problem := SeaRouter.get_default().validate_route(route)
	if not problem.is_empty():
		return problem
	_state.planned_route = route.duplicate_route()
	_has_unsaved_changes = true
	route_changed.emit(get_planned_route())
	return ""


func clear_planned_route() -> void:
	if _state == null or _state.planned_route == null:
		return
	_state.planned_route = null
	_has_unsaved_changes = true
	route_changed.emit(null)


# --- Voyage ---------------------------------------------------------------------------

## A copy of the active voyage, or null when not underway.
func get_voyage() -> Voyage:
	return _state.voyage.duplicate_voyage() if _state and _state.voyage else null


## Cheap read-only queries for UI that refreshes every frame.
func get_voyage_destination_id() -> StringName:
	return _state.voyage.route.destination_port_id if _state and _state.voyage else &""


func get_voyage_progress_nm() -> float:
	return _state.voyage.progress_nm if _state and _state.voyage else 0.0


func get_voyage_remaining_nm() -> float:
	return _state.voyage.get_remaining_nm() if _state and _state.voyage else 0.0


func get_voyage_total_nm() -> float:
	return _state.voyage.get_total_nm() if _state and _state.voyage else 0.0


## Distance along the course of the next route vertex ahead of the vessel
## (where the heading changes), or the total if none is left.
func get_voyage_next_vertex_nm() -> float:
	if _state == null or _state.voyage == null:
		return 0.0
	var cumulative := _state.voyage.get_cumulative()
	var i := cumulative.bsearch(_state.voyage.progress_nm + 1e-9, false)
	return cumulative[mini(i, cumulative.size() - 1)]


## The position at `distance_nm` along the active voyage's course (Simulation).
func get_voyage_position_at(distance_nm: float) -> Vector2:
	return _state.voyage.position_at(distance_nm) if _state and _state.voyage else get_vessel_position()


func get_voyage_revision() -> int:
	return _state.voyage.revision if _state and _state.voyage else 0


## Sets sail on the planned route. Returns "" on success, otherwise the reason.
func depart() -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if is_underway():
		return Loc.t("The vessel is already underway.")
	var route := _state.planned_route
	if route == null or not route.has_path():
		return Loc.t("Plot a course at the chart table first.")
	if _state.provisions.is_empty():
		return Loc.t("You are out of food or water. Buy provisions at the grocery store before setting sail.")
	var location := get_location()
	if location == null or route.origin_port_id != location.id:
		return Loc.t("The planned course does not start here.")
	var problem := SeaRouter.get_default().validate_route(route)
	if not problem.is_empty():
		return problem
	_state.voyage = Voyage.create(route, _state.game_time)
	_state.hat.voyage_worn_hazard = 0
	_state.hat.voyage_lost = false
	_state.weather_exposure.reset(_state.game_time)
	_state.damage_applied_until = _state.game_time
	_state.propulsion = PropulsionState.new()  # evaluated by Simulation on voyage_started
	_state.planned_route = null
	_state.vessel_status = SessionState.STATUS_UNDERWAY
	_state.location_id = &""
	_state.vessel_position = _state.voyage.get_position()
	_has_unsaved_changes = true
	route_changed.emit(null)
	voyage_started.emit()
	_companion_to_cabin_if_needed()  # casting off: the companion goes below
	return ""


## Changes course at sea: plans a new route from the vessel's current position
## (via the waypoints) to `destination_id` and replaces the remaining voyage.
## The clock, progress already made and position are preserved. If no valid
## route exists the current voyage stays exactly as it was. Returns "" on success.
## `anchorages` (Iteration 18): which of `waypoints` are anchorages.
func change_course(destination_id: StringName, waypoints: Array[Vector2], anchorages: Array[bool] = []) -> String:
	if not is_underway():
		return Loc.t("The vessel is not underway.")
	var origin := _state.vessel_position
	var result := SeaRouter.get_default().plan_route(&"", origin, waypoints, destination_id)
	if not result.is_ok():
		return result.error
	var voyage := _state.voyage
	result.route.anchorages = anchorages.duplicate()
	result.route.anchorages.resize(result.route.waypoints.size())
	voyage.route = result.route
	voyage.holding_at = -1
	voyage.anchorages_done.clear()
	voyage.progress_nm = 0.0
	voyage.revision += 1
	voyage.warned_conditions.clear()
	_state.vessel_position = voyage.get_position()
	_has_unsaved_changes = true
	voyage_course_changed.emit()
	return ""


# --- Simulation hooks (called by Simulation only) ------------------------------------

## Applies a simulation step: new game time and, when underway, new progress.
## Food and water are used up with the elapsed game time, wherever the boat is.
func apply_simulation_step(game_time: float, progress_nm: float) -> void:
	if _state == null:
		return
	var elapsed := game_time - _state.game_time
	_state.game_time = game_time
	if elapsed > 0.0:
		# A well-fed crew eats a little less (only the well-fed part of the step).
		var well_fed := clampf(_state.galley.well_fed_until - (game_time - elapsed), 0.0, elapsed)
		var factor := lerpf(1.0, WELL_FED_FOOD_FACTOR, well_fed / elapsed)
		_state.provisions.consume(elapsed / Provisions.DAY_SECONDS * Difficulty.factor("provisions_use"), factor)
		_check_provisions()
	# The companion's resting schedule runs on the same clock (pure function of time).
	if _state.companion.advance_to(game_time):
		companion_moved.emit(_state.companion.spot)
	_companion_to_cabin_if_needed()
	if _state.voyage:
		var progress := clampf(progress_nm, 0.0, _state.voyage.get_total_nm())
		if elapsed > 0.0 and not _state.anchor.active:
			_wear(elapsed, maxf(progress - _state.voyage.progress_nm, 0.0))
		_state.voyage.sailed_nm += maxf(progress - _state.voyage.progress_nm, 0.0)
		_state.voyage.progress_nm = progress
		var before := _state.vessel_position
		_state.vessel_position = GeoMath.normalize(_state.anchor.position if _state.anchor.active else _state.voyage.get_position())
		_note_crossings(before, _state.vessel_position)
	_has_unsaved_changes = true
	if _state.anchor.active or _settled:
		_update_anchor_life()


## Diagnostics (Iteration 16): the Date Line and the chart regions (detailed
## Denmark, Europe, the world chart) crossed underway. Not saved.
var _chart_region := "?"


func _note_crossings(before: Vector2, after: Vector2) -> void:
	if absf(after.x - before.x) > 180.0:
		SessionLog.write("dateline_crossed", {"from_lon": snappedf(before.x, 0.01), "to_lon": snappedf(after.x, 0.01), "lat": snappedf(after.y, 0.01)})
	var router := SeaRouter.get_loaded()
	if router == null:
		return
	var region := router.grid.grid_at(after).region_id
	if region != _chart_region:
		if _chart_region != "?":
			SessionLog.write("region_transition", {"from": _chart_region if _chart_region != "" else "world",
				"to": region if region != "" else "world", "lon": snappedf(after.x, 0.01), "lat": snappedf(after.y, 0.01)})
		_chart_region = region


## Ends the voyage at its destination.
## Replaces the propulsion state (Simulation only). Announces mode changes.
## The sail trim (Iteration 18): {"auto", "value"}.
func get_sail_trim() -> Dictionary:
	return {"auto": _state.trim_auto, "value": _state.trim_value} if _state else {"auto": true, "value": 0.0}


## Sets the sail trim: left to the crew (`auto`), or the captain's `value`
## (-1 eased .. +1 sheeted in). Under sail the boat's speed follows at once
## (from the wind at the last evaluation); nothing else changes.
func set_sail_trim(auto: bool, value: float) -> void:
	if _state == null:
		return
	_state.trim_auto = auto
	_state.trim_value = clampf(value, -1.0, 1.0)
	_has_unsaved_changes = true
	var propulsion := _state.propulsion
	if is_underway() and not is_anchored() and propulsion.initialised and not propulsion.is_motoring():
		propulsion.speed_kn = propulsion.potential_kn * get_trim_factor()
		Simulation.invalidate_estimates()
	sail_trim_changed.emit()


## The speed factor of the current trim, from the wind at the last sail
## evaluation (1.0 when the crew trims, or under engine).
func get_trim_factor() -> float:
	if _state == null:
		return 1.0
	var propulsion := _state.propulsion
	return SailTrim.factor(_state.trim_auto, _state.trim_value, propulsion.true_wind_angle, propulsion.wind_speed_kn)


func set_propulsion(state: PropulsionState) -> void:
	if _state == null:
		return
	var changed := state.mode != _state.propulsion.mode or not _state.propulsion.initialised
	_state.propulsion = state.duplicate_state()
	_has_unsaved_changes = true
	if changed:
		propulsion_changed.emit(state.mode)


func complete_voyage() -> void:
	if not is_underway():
		return
	var destination := PortCatalog.get_default().get_port(_state.voyage.route.destination_port_id)
	var record := CaptainsLog.make_record(_state.voyage, _state.game_time, _state.vessel_id, CaptainsLog.OUTCOME_ARRIVED)
	var new_harbour := _state.captains_log.record_voyage(record)
	var awards := _award_objectives(record, new_harbour)
	awards.append_array(_award_world_firsts(record, destination))
	_state.voyage = null
	_state.vessel_status = SessionState.STATUS_ARRIVED
	_state.location_id = destination.id
	_state.vessel_position = destination.get_geo_position()
	_state.propulsion = PropulsionState.new()
	_state.weather_exposure.reset(_state.game_time)
	_has_unsaved_changes = true
	propulsion_changed.emit(&"")
	voyage_logged.emit(record, new_harbour)
	if not awards.is_empty():
		renown_awarded.emit(awards)
	voyage_arrived.emit(destination.id)


## Records the weather at the boat (Simulation only, on its evaluation grid).
func update_weather_exposure(sample: WeatherSample) -> void:
	if _state == null:
		return
	_state.weather_exposure.record(sample, _state.game_time)
	if _state.voyage:
		_state.voyage.worst_hazard = maxi(_state.voyage.worst_hazard, sample.hazard)
	_has_unsaved_changes = true


## A copy of the weather exposure record: the hazard level the boat is in, since
## when, the responsible event and the peaks (see WeatherExposure).
func get_weather_exposure() -> WeatherExposure:
	return _state.weather_exposure.duplicate_exposure() if _state else WeatherExposure.new()


## Records that a weather warning (key "<event>><level>") was given on this voyage.
func record_weather_warning(condition_id: StringName) -> void:
	if _state and _state.voyage and condition_id not in _state.voyage.warned_conditions:
		_state.voyage.warned_conditions.append(condition_id)
		_has_unsaved_changes = true


func is_weather_warned(condition_id: StringName) -> bool:
	return _state != null and _state.voyage != null and condition_id in _state.voyage.warned_conditions


# --- Condition, repair and rescue ---------------------------------------------------

## The active boat's condition in percent (100 = perfect).
func get_condition() -> float:
	return _state.get_condition(_state.vessel_id) if _state else VesselCondition.FULL


## Condition of any boat (each boat keeps its own, also when not sailed).
func get_vessel_condition(vessel_id: StringName) -> float:
	return _state.get_condition(vessel_id) if _state else VesselCondition.FULL


## Weather damage has been applied up to this game time (Simulation only).
func get_damage_applied_until() -> float:
	return _state.damage_applied_until if _state else 0.0


## Applies weather damage for the voyage up to `until` (Simulation only, at
## its evaluation points). When the condition reaches zero the crew is rescued
## at once (see rescue()). Returns true if that happened.
func apply_weather_damage(percent: float, until: float) -> bool:
	if _state == null or not is_underway():
		return false
	_state.damage_applied_until = maxf(_state.damage_applied_until, until)
	_has_unsaved_changes = true
	if percent <= 0.0:
		return false
	var before := get_condition()
	_state.set_condition(_state.vessel_id, before - percent)
	_state.voyage.damage_percent += before - get_condition()
	# Heavy weather also wears the rig (Iteration 14).
	var care := _state.get_boat_care(_state.vessel_id)
	care.rig_wear = minf(care.rig_wear + (before - get_condition()) * BoatCare.RIG_WEAR_PER_DAMAGE, 100.0)
	condition_changed.emit(get_condition())
	if get_condition() <= 0.0:
		rescue()
		return true
	return false


## Repairs and restocking are harbour services: moored or arrived in port.
func is_moored_in_harbour() -> bool:
	return _state != null and not is_underway() and get_location() != null


## Repairs the active boat's hull and structure to 100 % at the boatyard
## (Iteration 14: for a fee and a little time, see BoatCare). Returns "" on
## success, otherwise the reason.
func repair_vessel() -> String:
	return perform_service(BoatCare.SERVICE_REPAIR).error


## Rescue at sea: the boat's condition reached zero. One complete transaction,
## applied to the state at once, so a save can never hold half of it: the
## voyage ends, the boat and crew are brought back to the home harbour, the
## boat is repaired, and the fee (at most what the player has) is paid. The
## companion, provisions, other boats and the clock are kept; time acceleration
## drops to 1× (a player pause stays as it was). Does nothing if not underway,
## so one incident can only ever be rescued once.
func rescue() -> void:
	if _state == null or not is_underway():
		return
	var port := PortCatalog.get_default().get_port(HOME_PORT)
	var from := _state.vessel_position
	# Towed home: the anchor is recovered and the line comes in (Iteration 13).
	_state.anchor.active = false
	_state.anchor.alarm = false
	_state.fishing.line_out = false
	_pending_bite = {}
	var fee := mini(roundi(SessionState.RESCUE_FEE * Difficulty.factor("rescue_fee")), _state.funds)
	_state.funds -= fee
	var record := CaptainsLog.make_record(_state.voyage, _state.game_time, _state.vessel_id, CaptainsLog.OUTCOME_RESCUED)
	_state.captains_log.record_voyage(record)
	var awards := _award_objectives(record, false)
	_state.voyage = null
	_state.planned_route = null
	_state.vessel_status = SessionState.STATUS_MOORED
	_state.location_id = port.id
	_state.vessel_position = port.get_geo_position()
	_state.propulsion = PropulsionState.new()
	_state.weather_exposure.reset(_state.game_time)
	_state.damage_applied_until = _state.game_time
	_state.set_condition(_state.vessel_id, VesselCondition.FULL)
	_state.boat_area = RESCUE_AREA
	_state.spawn_point = RESCUE_SPAWN
	_state.has_player_position = false
	_state.time_scale = 1
	_state.rescue_count += 1
	var info := {"time": _state.game_time, "fee": fee, "funds_after": _state.funds, "port_id": String(port.id),
		"from": {"lon": from.x, "lat": from.y}}
	_state.last_rescue = info.duplicate(true)
	_has_unsaved_changes = true
	time_scale_changed.emit(1)
	propulsion_changed.emit(&"")
	route_changed.emit(null)
	condition_changed.emit(get_condition())
	funds_changed.emit(_state.funds)
	voyage_logged.emit(record, false)
	if not awards.is_empty():
		renown_awarded.emit(awards)
	rescued.emit(info)


# --- Boat care (Iteration 14) ----------------------------------------------------------

## A copy of a boat's care record (the active boat by default).
func get_boat_care(vessel_id: StringName = &"") -> BoatCareState:
	if _state == null:
		return BoatCareState.create(0.0)
	return _state.get_boat_care(vessel_id if vessel_id != &"" else _state.vessel_id).duplicate_state()


func has_upgrade(id: String) -> bool:
	return _state != null and _state.get_boat_care(_state.vessel_id).has_upgrade(id)


## The level of a care area of the active boat (BoatCare.LEVEL_*).
func get_care_level(area: StringName) -> StringName:
	if _state == null:
		return BoatCare.LEVEL_GOOD
	return BoatCare.area_level(area, _state.get_boat_care(_state.vessel_id), get_condition(), _state.game_time)


## Everyday wear for `elapsed` seconds underway and `nm` sailed: engine hours
## while motoring, rig wear under sail (more in a strong breeze).
func _wear(elapsed: float, nm: float) -> void:
	var care := _state.get_boat_care(_state.vessel_id)
	var before := [BoatCare.area_level(BoatCare.AREA_RIG, care, get_condition(), _state.game_time),
		BoatCare.area_level(BoatCare.AREA_ENGINE, care, get_condition(), _state.game_time)]
	var wear := Difficulty.factor("wear")  # I022 (Standard: 1.0)
	if _state.propulsion.is_motoring():
		care.engine_hours += elapsed / 3600.0 * wear
	else:
		care.rig_wear = minf(care.rig_wear + BoatCare.rig_wear_for(nm, _state.propulsion.wind_speed_kn, care) * wear, 100.0)
	var after := [BoatCare.area_level(BoatCare.AREA_RIG, care, get_condition(), _state.game_time),
		BoatCare.area_level(BoatCare.AREA_ENGINE, care, get_condition(), _state.game_time)]
	if after != before:
		boat_care_changed.emit()
		for i in 2:
			if after[i] == BoatCare.LEVEL_RECOMMENDED and before[i] != after[i]:
				notice.emit.call_deferred(Loc.t("Boat care: %s could do with a service at the next boatyard. (Captain's Log, Boat tab)") % \
					Loc.t(BoatCare.AREA_NAMES[[BoatCare.AREA_RIG, BoatCare.AREA_ENGINE][i]]).to_lower())


## Which yard a service or upgrade needs: the boatyard, or a yard that can
## haul boats out.
static func service_facility(service: StringName) -> StringName:
	return HarbourFacilities.HAUL_OUT if service == BoatCare.SERVICE_HAUL_OUT else HarbourFacilities.BOATYARD


## Why a service cannot be had here now, or "".
func service_refusal(service: StringName) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if not is_moored_in_harbour():
		return Loc.t("Boatyard work is done while moored in harbour.")
	var facility := service_facility(service)
	if not has_facility(facility):
		return facility_refusal(facility)
	var care := _state.get_boat_care(_state.vessel_id)
	match service:
		BoatCare.SERVICE_REPAIR:
			if get_condition() >= VesselCondition.FULL:
				return Loc.t("The %s is already in perfect condition.") % get_vessel_definition().display_name
		BoatCare.SERVICE_ENGINE:
			if care.engine_hours < 1.0:
				return Loc.t("The engine was serviced recently.")
		BoatCare.SERVICE_RIG:
			if care.rig_wear < 1.0:
				return Loc.t("The rigging and sails are in fine order.")
	var quote := service_quote(service)
	if int(quote.cost) > _state.funds:
		return Loc.t("Not enough money: %s needed.") % format_money(int(quote.cost))
	return ""


## {"cost", "minutes"} for a service on the active boat.
func service_quote(service: StringName) -> Dictionary:
	if _state == null:
		return {"cost": 0, "minutes": 0.0}
	var quote := BoatCare.quote(service, _state.get_boat_care(_state.vessel_id), get_condition(), get_base_vessel_profile().length_ft)
	quote.cost = ceili(int(quote.cost) * Difficulty.factor("costs") - 1e-6)  # I022 difficulty (Standard: unchanged)
	return quote


## Has a service done: one transaction that pays, restores and records it.
## The time it takes is spent by the caller (Simulation.spend_time_ashore).
## Returns {"error", "cost", "minutes", "first"}.
func perform_service(service: StringName) -> Dictionary:
	var result := {"error": service_refusal(service), "cost": 0, "minutes": 0.0, "first": false}
	if result.error != "":
		return result
	var quote := service_quote(service)
	var care := _state.get_boat_care(_state.vessel_id)
	match service:
		BoatCare.SERVICE_REPAIR:
			_state.set_condition(_state.vessel_id, VesselCondition.FULL)
			condition_changed.emit(get_condition())
		BoatCare.SERVICE_ENGINE:
			care.engine_hours = 0.0
		BoatCare.SERVICE_RIG:
			care.rig_wear = 0.0
		BoatCare.SERVICE_HAUL_OUT:
			# Out of the water: the bottom is cleaned and the hull and structure
			# are seen to, all in one.
			care.hull_cleaned_at = _state.game_time
			_state.set_condition(_state.vessel_id, VesselCondition.FULL)
			condition_changed.emit(get_condition())
	_state.funds -= int(quote.cost)
	care.add_history(_state.game_time, String(service), String(get_location_id()), int(quote.cost))
	result.cost = int(quote.cost)
	result.minutes = float(quote.minutes)
	if service == BoatCare.SERVICE_HAUL_OUT:
		var award := _award_once("care:first_haul_out", Loc.t("First haul-out: %s") % get_location().display_name, 2)
		result.first = not award.is_empty()
		if result.first:
			renown_awarded.emit([award])
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	boat_care_changed.emit()
	return result


## Work the yard can do while the boat is out of the water (haul-out
## options): engine and rig services when they are due, and the hard
## antifouling coating when it is not fitted yet.
const HAUL_OUT_EXTRAS: Array[StringName] = [BoatCare.SERVICE_ENGINE, BoatCare.SERVICE_RIG, &"hard_antifouling"]


## The extras that make sense for the active boat now (subset of HAUL_OUT_EXTRAS).
func get_haul_out_extras() -> Array[StringName]:
	var extras: Array[StringName] = []
	if _state == null:
		return extras
	var care := _state.get_boat_care(_state.vessel_id)
	if care.engine_hours >= 1.0:
		extras.append(BoatCare.SERVICE_ENGINE)
	if care.rig_wear >= 1.0:
		extras.append(BoatCare.SERVICE_RIG)
	if not care.has_upgrade("hard_antifouling"):
		extras.append(&"hard_antifouling")
	return extras


## {"cost", "minutes", "items": [[name, cost]]} for a haul-out with `extras`.
## The extras are done while the boat is out, so they add cost, not time.
func haul_out_quote(extras: Array[StringName]) -> Dictionary:
	var quote := service_quote(BoatCare.SERVICE_HAUL_OUT)
	var items: Array = [[Loc.t(BoatCare.SERVICE_NAMES[BoatCare.SERVICE_HAUL_OUT]), int(quote.cost)]]
	var cost := int(quote.cost)
	for extra in extras:
		var price := upgrade_price(String(extra)) if extra == &"hard_antifouling" else int(service_quote(extra).cost)
		var name: String = BoatCare.get_upgrade(String(extra)).get("name", "") if extra == &"hard_antifouling" \
			else Loc.t(BoatCare.SERVICE_NAMES.get(extra, String(extra)))
		items.append([name, price])
		cost += price
	return {"cost": cost, "minutes": float(quote.minutes), "items": items}


## Hauls the boat out (bottom cleaned, hull repaired) and has `extras` done at
## the same time: one transaction, refused as a whole when anything is not
## possible or affordable. The caller spends the time (24 h). Returns
## {"error", "cost", "minutes", "first", "done": [names]}.
func haul_out(extras: Array[StringName] = []) -> Dictionary:
	var result := {"error": service_refusal(BoatCare.SERVICE_HAUL_OUT), "cost": 0, "minutes": 0.0, "first": false, "done": []}
	var allowed := get_haul_out_extras()
	for extra in extras:
		if result.error == "" and not extra in allowed:
			result.error = Loc.t("That work is not needed now.")
	var quote := haul_out_quote(extras)
	if result.error == "" and int(quote.cost) > _state.funds:
		result.error = Loc.t("Not enough money: %s needed.") % format_money(int(quote.cost))
	if result.error != "":
		return result
	var care := _state.get_boat_care(_state.vessel_id)
	for extra in extras:
		match extra:
			BoatCare.SERVICE_ENGINE:
				care.engine_hours = 0.0
			BoatCare.SERVICE_RIG:
				care.rig_wear = 0.0
			&"hard_antifouling":
				care.upgrades.append("hard_antifouling")
	var hauled := perform_service(BoatCare.SERVICE_HAUL_OUT)
	var extras_cost := int(quote.cost) - int(hauled.cost)
	_state.funds -= extras_cost
	for i in range(1, quote.items.size()):
		care.add_history(_state.game_time, "haul_out_extra:" + String(extras[i - 1]), String(get_location_id()), int(quote.items[i][1]))
	result.cost = int(quote.cost)
	result.minutes = float(hauled.minutes)
	result.first = hauled.first
	for item: Array in quote.items:
		result.done.append(item[0])
	funds_changed.emit(_state.funds)
	boat_care_changed.emit()
	return result


## Why an upgrade cannot be fitted here now, or "".
func upgrade_refusal(id: String) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	var upgrade := BoatCare.get_upgrade(id)
	if upgrade.is_empty():
		return Loc.t("Unknown equipment.")
	if has_upgrade(id):
		return Loc.t("The %s already has it.") % get_vessel_definition().display_name
	if not is_moored_in_harbour():
		return Loc.t("Equipment is fitted while moored in harbour.")
	var facility := HarbourFacilities.HAUL_OUT if upgrade.get("yard", "boatyard") == "haul_out" else HarbourFacilities.BOATYARD
	if not has_facility(facility):
		return facility_refusal(facility)
	var price := upgrade_price(id)
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed.") % format_money(price)
	return ""


func upgrade_price(id: String) -> int:
	return BoatCare.upgrade_price(id, get_base_vessel_profile().length_ft)


## Fits an upgrade to the active boat: pays once, fitted once. Returns
## {"error", "cost", "minutes"}; the fitting time is spent by the caller.
func install_upgrade(id: String) -> Dictionary:
	var result := {"error": upgrade_refusal(id), "cost": 0, "minutes": 0.0}
	if result.error != "":
		return result
	var care := _state.get_boat_care(_state.vessel_id)
	var price := upgrade_price(id)
	care.upgrades.append(id)
	_state.funds -= price
	care.add_history(_state.game_time, "upgrade:" + id, String(get_location_id()), price)
	result.cost = price
	result.minutes = BoatCare.UPGRADE_MINUTES
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	boat_care_changed.emit()
	fishing_changed.emit()
	return result


## Equipment effects (Iteration 14) used by other systems.
func get_cool_box_capacity() -> int:
	return FishingState.LARGE_HOLD_CAPACITY if has_upgrade("large_cool_box") else FishingState.HOLD_CAPACITY


func get_calm_cooking_wind_kn() -> float:
	return GIMBALLED_COOKING_WIND_KN if has_upgrade("gimballed_stove") else CALM_COOKING_WIND_KN


func get_anchor_holding_bonus_kn() -> float:
	return HEAVY_ANCHOR_BONUS_KN if has_upgrade("heavy_anchor") else 0.0


func get_warning_horizon_hours() -> float:
	return RECEIVER_WARNING_HOURS if has_upgrade("weather_receiver") else Simulation.WARNING_HORIZON_HOURS


const GIMBALLED_COOKING_WIND_KN := 26.0
const HEAVY_ANCHOR_BONUS_KN := 5.0
const RECEIVER_WARNING_HOURS := 10.0


# --- Captain's Log ---------------------------------------------------------------

## A copy of the Captain's Log.
func get_captains_log() -> CaptainsLog:
	return _state.captains_log.duplicate_log() if _state else CaptainsLog.new()


## Everything sailed so far, nm: ended voyages plus the voyage under way.
func get_total_nm_sailed() -> float:
	if _state == null:
		return 0.0
	return _state.captains_log.total_nm + (_state.voyage.sailed_nm if _state.voyage else 0.0)


func get_voyage_sailed_nm() -> float:
	return _state.voyage.sailed_nm if _state and _state.voyage else 0.0


# --- Objectives and renown ----------------------------------------------------------

## A copy of renown and the objectives completed.
func get_objective_progress() -> ObjectiveProgress:
	return _state.progress.duplicate_progress() if _state else ObjectiveProgress.new()


## All renown ever earned (never decreases).
func get_lifetime_renown() -> int:
	return _state.progress.lifetime_renown if _state else 0


## Renown not yet published in a travel update.
func get_unpublished_renown() -> int:
	return _state.progress.unpublished_renown if _state else 0


## What publishing a travel update would do now: {"renown", "rate", "euros",
## "funds", "funds_after", "error"} ("" when it is possible).
func get_publish_quote() -> Dictionary:
	var rate := ObjectiveCatalog.get_default().euros_per_renown
	var renown := get_unpublished_renown()
	var error := ""
	if not is_moored_in_harbour():
		error = Loc.t("Publishing needs a steady connection: moor in a harbour first.")
	elif renown <= 0:
		error = Loc.t("No unpublished renown yet: sail, explore and complete objectives to earn some.")
	return {"renown": renown, "rate": rate, "euros": renown * rate, "funds": get_funds(),
		"funds_after": get_funds() + renown * rate, "error": error}


## Publishes a travel update (social media): all unpublished renown becomes
## money at the configured rate, in one transaction. The renown deduction and
## the payment happen together or not at all; lifetime renown stays. In
## harbour only. Returns {"error", "renown", "euros", "funds_after"}.
func publish_travel_update() -> Dictionary:
	if _state == null:
		return {"error": Loc.t("No game is running."), "renown": 0, "euros": 0, "funds_after": 0}
	var quote := get_publish_quote()
	if not String(quote.error).is_empty():
		return {"error": quote.error, "renown": 0, "euros": 0, "funds_after": _state.funds}
	var progress := _state.progress
	var renown := progress.unpublished_renown
	var euros: int = renown * int(quote.rate)
	progress.unpublished_renown = 0
	progress.publications += 1
	progress.published_renown += renown
	progress.published_euros += euros
	_state.funds += euros
	_has_unsaved_changes = true
	var info := {"error": "", "renown": renown, "euros": euros, "funds_after": _state.funds}
	funds_changed.emit(_state.funds)
	travel_update_published.emit(info.duplicate())
	return info


## Pays the objectives the voyage just logged completes (inside
## complete_voyage() and rescue(), so the reward is part of the same
## transaction as the record and can never be paid twice).
func _award_objectives(record: Dictionary, new_harbour: bool) -> Array[Dictionary]:
	var awards := ObjectiveCatalog.get_default().evaluate(_state.captains_log, record, new_harbour, _state.progress, _state.hat)
	for award in awards:
		_state.progress.award(StringName(award.id), award.title, award.reward, float(record.ended))
	return awards


## Harbour regions outside Europe (Iteration 16).
const WORLD_REGIONS := ["atlantic_islands", "caribbean", "central_america", "pacific"]
## A passage at least this long (nm, in one voyage) is an offshore crossing.
const OFFSHORE_CROSSING_NM := 500.0


## The worldwide Captain's Log firsts (Iteration 16), each paid once.
func _award_world_firsts(record: Dictionary, destination: PortData) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var from := Vector2(float(record.from_position.lon), float(record.from_position.lat))
	var to := destination.get_geo_position()
	var international := destination.region in WORLD_REGIONS
	if international:
		SessionLog.write("international_arrival", {"port": String(destination.id), "region": destination.region, "nm": snappedf(float(record.nm), 0.1)})
	var firsts := [
		[_beyond_danish_waters(to), "world:beyond_denmark", Loc.t("Beyond Danish waters: %s") % destination.display_name, 3],
		[international, "world:first_international", Loc.t("Your first international destination: %s") % destination.display_name, 4],
		[float(record.nm) >= OFFSHORE_CROSSING_NM, "world:offshore_crossing", Loc.t("Your first offshore crossing: %d nm to %s") % [roundi(float(record.nm)), destination.display_name], 4],
		[_is_atlantic_crossing(from, to), "world:atlantic_crossing", Loc.t("Across the Atlantic to %s") % destination.display_name, 6],
		[destination.region == "pacific", "world:pacific_arrival", Loc.t("Into the Pacific: %s") % destination.display_name, 5],
		[destination.country == "French Polynesia", "world:french_polynesia", Loc.t("French Polynesia: %s") % destination.display_name, 5],
		[destination.country == "New Zealand", "world:new_zealand", Loc.t("New Zealand: %s") % destination.display_name, 5],
	]
	for first: Array in firsts:
		if first[0]:
			var award := _award_once(first[1], first[2], first[3])
			if not award.is_empty():
				found.append(award)
	return found


## Outside the detailed Danish chart (the Danish waters with the Kattegat and
## the western Baltic around them).
static func _beyond_danish_waters(geo: Vector2) -> bool:
	var router := SeaRouter.get_loaded()
	return router != null and router.grid.grid_at(geo).region_id != "denmark"


## From one side of the Atlantic to the other in one voyage: between the
## eastern Atlantic (east of 30°W: Europe, Africa and the eastern islands)
## and the western (west of 50°W: the Americas and the Caribbean).
static func _is_atlantic_crossing(from: Vector2, to: Vector2) -> bool:
	var atlantic := func(p: Vector2) -> bool: return p.x > -100.0 and p.x < 30.0 and p.y > -60.0 and p.y < 70.0
	if not (atlantic.call(from) and atlantic.call(to)):
		return false
	return (from.x > -30.0 and to.x < -50.0) or (from.x < -50.0 and to.x > -30.0)


## Pays the (secret) objectives a hat event completes, inside the hat's own
## transaction, so each pays exactly once (see ObjectiveProgress.can_pay()).
func _award_hat_objectives(event: Dictionary) -> Array[Dictionary]:
	var awards := ObjectiveCatalog.get_default().evaluate_hat_event(event, _state.captains_log, _state.hat, _state.progress)
	for award in awards:
		_state.progress.award(StringName(award.id), award.title, award.reward, float(event.time))
	return awards


# --- Fishing (Iteration 13) ---------------------------------------------------------

## A well-fed crew uses this fraction of the usual food (water is unchanged).
const WELL_FED_FOOD_FACTOR := 0.75
## A fish on the line waits this long (real seconds) for the captain to reach
## the rod before it gets away (App; real time so 20x does not rush it).
const BITE_WAIT_SECONDS := 45.0

## The companion stays below in more wind than this (Iteration 18).
const COMPANION_DECK_MAX_WIND_KN := 20.0
## A bite waiting for the captain (not saved: after loading the line is just out).
var _pending_bite := {}
## "Too fast to troll" was said for this stretch (said once, not every check).
var _warned_too_fast := false
## Bites let go quietly in fast time (Iteration 18; not saved).
var _quiet_nibbles := 0
## In fast time a bite stops the clock at most once this often (game seconds).
const FAST_BITE_COOLDOWN_S := 3.0 * 3600.0
var _last_fast_bite_at := -INF


func get_fishing() -> FishingState:
	return _state.fishing.duplicate_state() if _state else FishingState.new()


func is_line_out() -> bool:
	return _state != null and _state.fishing.line_out


## How one fishes here now: from a still boat (in harbour or at anchor) or
## trolling behind a moving one.
func get_fishing_mode() -> StringName:
	return FishingState.MODE_TROLLING if is_underway() and not is_anchored() and not is_holding_at_anchorage() else FishingState.MODE_STATIONARY


## Why the line cannot go out now, or "".
func fishing_refusal(lure_id: String) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if not _state.fishing.rod:
		return Loc.t("You have no fishing rod.")
	if _state.fishing.get_lure_count(lure_id) <= 0:
		return Loc.t("You have no %s left. The harbour grocery store sells lures.") % FishingCatalog.get_default().get_lure(lure_id).get("name", "lure").to_lower()
	if get_fishing_mode() == FishingState.MODE_TROLLING and get_vessel_speed_kn() > FishingCatalog.get_default().max_trolling_kn:
		return Loc.format("Too fast to troll: %.1f kn. A trolled lure only works below %d kn; wait for a gentler stretch or anchor.", [
			get_vessel_speed_kn(), roundi(FishingCatalog.get_default().max_trolling_kn)])
	return ""


## Lets the line out with `lure_id` (or brings it in with out = false).
## Returns "" or the reason it cannot.
func set_line(out: bool, lure_id := "") -> String:
	if _state == null:
		return Loc.t("No game is running.")
	var fishing := _state.fishing
	if not out:
		if fishing.line_out:
			fishing.line_out = false
			_pending_bite = {}
			_has_unsaved_changes = true
			fishing_changed.emit()
		return ""
	var lure := lure_id if lure_id != "" else fishing.lure
	var refusal := fishing_refusal(lure)
	if refusal != "":
		return refusal
	fishing.lure = lure
	fishing.line_out = true
	fishing.line_mode = get_fishing_mode()
	fishing.line_since = _state.game_time
	fishing.checked_until = maxf(fishing.checked_until, _state.game_time)
	_has_unsaved_changes = true
	fishing_changed.emit()
	return ""


## One bite check at `tick` with the line out (Simulation only, on its fixed
## grid). Returns true when a fish bites.
func apply_fish_check(tick: float) -> bool:
	if _state == null:
		return false
	var fishing := _state.fishing
	fishing.checked_until = maxf(fishing.checked_until, tick)
	if not fishing.line_out or not _pending_bite.is_empty():
		return false
	var catalog := FishingCatalog.get_default()
	var mode := get_fishing_mode()
	fishing.line_mode = mode
	var speed := get_vessel_speed_kn()
	if mode == FishingState.MODE_TROLLING and speed > catalog.max_trolling_kn:
		if _warned_too_fast:
			return false
		_warned_too_fast = true
		fishing_warning.emit({"kind": "too_fast", "text": Loc.format("The line is skipping on the surface at %.1f kn: too fast to troll. Bring it in, or wait for a gentler stretch.", speed)})
		return false
	_warned_too_fast = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|fish|%d" % [_state.wind_seed, int(tick)])
	var wind := Simulation.get_weather_at_vessel()
	if rng.randf() >= catalog.bite_chance(_state.vessel_position, mode, fishing.lure, speed, wind.speed_kn):
		return false
	var fish := catalog.pick(rng, _state.vessel_position, mode, fishing.lure)
	# Now and then something else takes the hook (Iteration 18).
	if not fish.is_empty() and rng.randf() < catalog.junk_chance:
		fish = catalog.pick_junk(rng)
	if fish.is_empty():
		return false
	var kind := catalog.kind_of(fish.species)
	var rarity := catalog.rarity_of(fish.species)
	# In fast time the captain may only want to be stopped for keepers: the
	# rest nibble and swim off (no fish is landed, nothing is gained).
	if is_fast_time() and fishing.passage_posture == FishingState.PASSAGE_KEEPERS \
			and (kind != FishingCatalog.KIND_FISH or FishingCatalog.rarity_index(rarity) < FishingCatalog.rarity_index(fishing.keep_min_rarity)):
		_quiet_nibbles += 1
		return false
	# In fast time a bite stops the clock at most once every few game hours;
	# bites in between nibble and swim off (measured: an ocean passage at
	# 12 h/s otherwise stopped about every two real seconds).
	if is_fast_time() and tick >= _last_fast_bite_at and tick - _last_fast_bite_at < FAST_BITE_COOLDOWN_S:
		_quiet_nibbles += 1
		return false
	if is_fast_time():
		_last_fast_bite_at = tick
	_pending_bite = {"species": fish.species, "kg": fish.kg, "time": tick, "mode": String(mode), "lure": fishing.lure,
		"kind": String(kind), "rarity": rarity}
	fish_bite.emit(_pending_bite.duplicate())
	return true


## Long Passage or the fastest clock (Iteration 18: where a bite's
## interruption can be spared by the captain's choice).
func is_fast_time() -> bool:
	return Simulation.is_passage_running() or (_state != null and _state.time_scale >= 20)


## Bites let go in fast time because they were not keepers (since the
## counter was last read; see take_quiet_nibbles()).
func take_quiet_nibbles() -> int:
	var count := _quiet_nibbles
	_quiet_nibbles = 0
	return count


func get_pending_bite() -> Dictionary:
	return _pending_bite.duplicate()


## The fish got away before the captain reached the rod (the lure stays).
func expire_bite() -> void:
	_pending_bite = {}


## The reel-in ended. `landed`: it is aboard and counted once; otherwise it
## escaped, and a broken line (`line_broke`) costs the lure. `perfects`:
## Perfect hits in the reel-in, which nudge the weight within the species'
## range (Iteration 18). What then happens to it:
##   - a fish the keep preferences want goes into the cool box (when there is
##     room) and onto the trophy board if notable enough;
##   - any other fish goes back ("preferences" or "cool_box_full") and never
##     onto the trophy board;
##   - a shark is always released; junk is discarded.
## Returns {"landed", "fish", "kind", "rarity", "grade", "kept",
## "released_reason", "first", "new_species", "personal_best", "exceptional",
## "awards", "text"}.
func finish_fight(landed: bool, line_broke := false, perfects := 0) -> Dictionary:
	var result := {"landed": false, "fish": {}, "kind": "", "rarity": "", "grade": "", "kept": false, "released_reason": "",
		"first": false, "new_species": false, "personal_best": false, "exceptional": false, "awards": [], "text": ""}
	if _state == null or _pending_bite.is_empty():
		return result
	var bite := _pending_bite
	_pending_bite = {}
	var fishing := _state.fishing
	var catalog := FishingCatalog.get_default()
	var species: String = bite.species
	var kind := catalog.kind_of(species)
	result.kind = String(kind)
	result.rarity = catalog.rarity_of(species)
	if not landed:
		if line_broke:
			fishing.lures[bite.lure] = maxi(fishing.get_lure_count(bite.lure) - 1, 0)
			if fishing.get_lure_count(bite.lure) <= 0:
				fishing.line_out = false
			result.text = Loc.t("Snap! The line broke and the %s went with the fish.") % String(catalog.get_lure(bite.lure).get("name", "lure")).to_lower()
		else:
			result.text = "It got away."
		_has_unsaved_changes = true
		fishing_changed.emit()
		return result
	result.landed = true
	var name := catalog.get_species_name(species)
	if kind == FishingCatalog.KIND_JUNK:
		fishing.junk_caught += 1
		result.fish = {"species": species, "kg": 0.0}
		result.released_reason = "junk"
		result.text = "%s. %s" % [name, String(catalog.get_junk(species).get("text", Loc.t("Into the bin with it.")))]
		_has_unsaved_changes = true
		fishing_changed.emit()
		fish_landed.emit(result.duplicate(true))
		return result
	var kg := catalog.landed_kg(species, float(bite.kg), perfects)
	var grade := catalog.grade(species, kg)
	result.grade = String(grade)
	var fish := {"uid": fishing.next_uid, "species": species, "kg": kg, "caught_at": _state.game_time, "where": _fishing_place()}
	fishing.next_uid += 1
	fishing.total_caught += 1
	var record: Dictionary = fishing.records.get(species, {"count": 0, "best_kg": 0.0})
	result.new_species = int(record.count) == 0
	record.count = int(record.count) + 1
	result.first = fishing.total_caught == 1
	# Keep it, or let it go.
	if kind == FishingCatalog.KIND_SHARK:
		result.released_reason = "shark"
	elif not fishing.wants(result.rarity, grade):
		result.released_reason = "preferences"
	elif fishing.hold.size() >= get_cool_box_capacity():
		result.released_reason = "cool_box_full"
	else:
		result.kept = true
	if result.kept:
		fish["prev_best_kg"] = float(record.best_kg)
		fishing.hold.append(fish)
		# Personal bests, exceptional fish and the trophy board count kept fish only.
		result.personal_best = not result.new_species and kg > float(record.best_kg)
		result.exceptional = catalog.is_exceptional(species, kg)
		record.best_kg = maxf(float(record.best_kg), kg)
		var trophy := fish.duplicate()
		trophy["score"] = snappedf(catalog.score(species, kg) + (10.0 if result.personal_best or result.new_species else 0.0), 0.01)
		fishing.trophies.append(trophy)
		fishing.trophies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.score) > float(b.score) or (is_equal_approx(float(a.score), float(b.score)) and int(a.uid) < int(b.uid)))
		fishing.trophies = fishing.trophies.slice(0, FishingState.TROPHY_COUNT)
	else:
		fishing.released += 1
		if kind == FishingCatalog.KIND_SHARK:
			fishing.sharks_released += 1
	fishing.records[species] = record
	result.fish = fish
	# Milestones pay renown once; ordinary fish do not.
	var awards: Array[Dictionary] = []
	if result.first:
		awards.append(_award_once("fish:first", Loc.t("Your first fish: %s") % name, 3))
	if result.new_species:
		awards.append(_award_once("fish:species:%s" % species, Loc.t("A new species: %s") % name, 2))
	if result.exceptional:
		awards.append(_award_once("fish:exceptional:%s" % species, Loc.format("An exceptional fish: %s, %.1f kg", [name, kg]), 4))
	if result.personal_best:
		_state.progress.mark(StringName("fish:best:%s" % species), _state.game_time)
	awards = awards.filter(func(a: Dictionary) -> bool: return not a.is_empty())
	result.awards = awards
	var weight := Loc.format("%s, %.1f kg", [name, kg])
	match result.released_reason:
		"shark":
			result.text = Loc.t("%s. That's quite a catch. Better let this one swim free.") % weight
		"preferences":
			result.text = Loc.t("%s. Not one to keep by your preferences, so it goes back.") % weight
		"cool_box_full":
			result.text = Loc.t("%s. The cool box is full, so it goes back.") % weight
		_:
			result.text = weight
	_has_unsaved_changes = true
	fishing_changed.emit()
	fish_landed.emit(result.duplicate(true))
	if not awards.is_empty():
		renown_awarded.emit(awards)
	return result


## The captain's keep preferences (Iteration 18): minimum rarity
## (FishingCatalog.RARITY_ORDER) and minimum specimen grade.
func set_keep_preferences(min_rarity: String, min_grade: StringName) -> void:
	if _state == null or not min_rarity in FishingCatalog.RARITY_ORDER or not min_grade in FishingCatalog.GRADES:
		return
	_state.fishing.keep_min_rarity = min_rarity
	_state.fishing.keep_min_grade = min_grade
	_has_unsaved_changes = true
	fishing_changed.emit()


## Long Passage fishing (Iteration 18): FishingState.PASSAGE_ALL or PASSAGE_KEEPERS.
func set_passage_posture(posture: StringName) -> void:
	if _state == null or not posture in FishingState.PASSAGE_POSTURES:
		return
	_state.fishing.passage_posture = posture
	_has_unsaved_changes = true
	fishing_changed.emit()


## Pays `renown` for milestone `id` the first time only (an existing
## ObjectiveProgress record, like Go Ashore), or {} when already paid.
func _award_once(id: String, title: String, renown: int) -> Dictionary:
	if _state.progress.is_completed(StringName(id)):
		return {}
	_state.progress.award(StringName(id), title, renown, _state.game_time)
	return {"id": id, "reward": renown, "title": title, "text": "", "secret": false, "tone": ""}


## Where a fish was caught: the harbour, or the sea near the nearest one.
func _fishing_place() -> String:
	if not is_underway():
		return get_location().display_name if get_location() else ""
	var place := HatStory.describe_place(_state.vessel_position, &"")
	return String(place.get("text", ""))


## Puts a fish from the cool box back into the sea.
func release_fish(uid: int) -> bool:
	var index := _state.fishing.find_in_hold(uid) if _state else -1
	if index < 0:
		return false
	var fish: Dictionary = _state.fishing.hold[index]
	_state.fishing.hold.remove_at(index)
	_state.fishing.released += 1
	# A released fish is not a trophy, nor the species' best (Iteration 18):
	# if it held the record, the record goes back to the best before it (or
	# the heaviest of that species still kept).
	_state.fishing.trophies = _state.fishing.trophies.filter(func(trophy: Dictionary) -> bool: return int(trophy.uid) != uid)
	var species := String(fish.species)
	var record: Dictionary = _state.fishing.records.get(species, {})
	if not record.is_empty() and is_equal_approx(float(record.best_kg), float(fish.kg)):
		var best := float(fish.get("prev_best_kg", 0.0))
		for other: Dictionary in _state.fishing.hold + _state.fishing.trophies:
			if String(other.species) == species:
				best = maxf(best, float(other.kg))
		record.best_kg = best
	_has_unsaved_changes = true
	fishing_changed.emit()
	return true


## Sells a fish from the cool box at the harbour grocery store. Returns
## {"error", "price"}.
func sell_fish(uid: int) -> Dictionary:
	if _state == null:
		return {"error": Loc.t("No game is running."), "price": 0}
	if not has_facility(HarbourFacilities.FISHMONGER):
		return {"error": Loc.t("Fish can be sold at a harbour fishmonger, while moored."), "price": 0}
	var index := _state.fishing.find_in_hold(uid)
	if index < 0:
		return {"error": Loc.t("That fish is no longer aboard."), "price": 0}
	var fish: Dictionary = _state.fishing.hold[index]
	var price := FishingCatalog.get_default().price(fish.species, float(fish.kg))
	_state.fishing.hold.remove_at(index)
	_state.fishing.sold += 1
	_state.funds += price
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	fishing_changed.emit()
	return {"error": "", "price": price}


## Sells the whole cool box at the fishmonger (I020), in one transaction:
## every fish priced as in sell_fish(), paid once, the hold emptied. Trophies
## and species records stay (they are the catch's history, not the fish).
## Returns {"error", "count", "total"}.
func sell_catch() -> Dictionary:
	if _state == null:
		return {"error": Loc.t("No game is running."), "count": 0, "total": 0}
	if not has_facility(HarbourFacilities.FISHMONGER):
		return {"error": facility_refusal(HarbourFacilities.FISHMONGER), "count": 0, "total": 0}
	if _state.fishing.hold.is_empty():
		return {"error": Loc.t("The cool box is empty."), "count": 0, "total": 0}
	var catalog := FishingCatalog.get_default()
	var total := 0
	for fish: Dictionary in _state.fishing.hold:
		total += catalog.price(fish.species, float(fish.kg))
	var count := _state.fishing.hold.size()
	_state.fishing.hold.clear()
	_state.fishing.sold += count
	_state.funds += total
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	fishing_changed.emit()
	return {"error": "", "count": count, "total": total}


## Buys one lure at the grocery store or the chandlery. Returns "" or the reason.
func buy_lure(lure_id: String) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if not has_facility(HarbourFacilities.GROCERY) and not has_facility(HarbourFacilities.CHANDLERY):
		return facility_refusal(HarbourFacilities.GROCERY)
	var lure := FishingCatalog.get_default().get_lure(lure_id)
	if lure.is_empty():
		return Loc.t("Unknown lure.")
	var price := int(lure.price)
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed.") % format_money(price)
	_state.funds -= price
	_state.fishing.lures[lure_id] = _state.fishing.get_lure_count(lure_id) + 1
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	fishing_changed.emit()
	return ""


func select_lure(lure_id: String) -> void:
	if _state and not FishingCatalog.get_default().get_lure(lure_id).is_empty():
		_state.fishing.lure = lure_id
		_has_unsaved_changes = true
		fishing_changed.emit()


# --- The galley (Iteration 13) ------------------------------------------------------

func get_galley() -> GalleyState:
	return _state.galley.duplicate_state() if _state else GalleyState.new()


func is_well_fed() -> bool:
	return _state != null and _state.game_time < _state.galley.well_fed_until


## Why the stove cannot be used now, or "": in harbour and at a holding
## anchor always; underway only in moderate conditions (one simple rule).
func cooking_refusal() -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if not is_underway():
		return ""
	if is_anchored():
		return Loc.t("The anchor is dragging: see to it first.") if _state.anchor.holding == AnchorState.HOLDING_DRAGGING else ""
	var here := Simulation.get_weather_at_vessel()
	if here.speed_kn >= get_calm_cooking_wind_kn() or here.hazard >= WeatherModel.HAZARD_CAUTION:
		return Loc.t("Too lively for the stove (wind %d kn). Wait for calmer water, or anchor somewhere sheltered.") % roundi(here.speed_kn)
	return ""

## Underway the stove is used only in winds below this (knots).
const CALM_COOKING_WIND_KN := 18.0


# --- Morning coffee (revision 0.102b) ----------------------------------------------
# A tiny galley ritual, not a mechanic: a few minutes pass, a warm line, and
# the first morning coffee at a quiet anchorage is a Captain's Log moment
# (once). No stat, no inventory, nothing to farm.

const COFFEE_MINUTES := 10.0


## Why coffee cannot be made now, or "". The stove's own rule applies (always
## in harbour and at a holding anchor; underway only in moderate conditions).
func coffee_refusal() -> String:
	var refusal := cooking_refusal()
	if refusal != "":
		return refusal
	if _state.provisions.water_days <= 0.0:
		return Loc.t("There is no fresh water left aboard for coffee.")
	return ""


## Makes a pot of coffee. Returns {"error", "minutes", "text", "context",
## "award"}; the caller spends the minutes (below deck).
func make_coffee() -> Dictionary:
	var result := {"error": coffee_refusal(), "minutes": 0.0, "text": "", "context": "", "award": {}}
	if result.error != "":
		return result
	var phase := get_day_phase()
	var morning := phase == AnchorLife.PHASE_MORNING
	if is_anchored() and _settled and morning:
		result.context = "anchor_morning"
		result.text = "Coffee by the open hatch, the anchor chain quiet in the water. The day can wait a little."
		result.award = _award_once("coffee:morning_at_anchor", Loc.t("Morning coffee at anchor"), 2)
		if not result.award.is_empty():
			renown_awarded.emit([result.award])
	elif is_anchored():
		result.context = "anchor"
		result.text = "A hot mug at anchor. The boat swings gently around it." if phase != AnchorLife.PHASE_NIGHT \
			else Loc.t("A late coffee by the lamp. The anchorage is dark and still.")
	elif is_underway():
		result.context = "underway"
		result.text = "A mug of coffee at the helm, held carefully. The miles go by a little easier."
	else:
		result.context = "harbour"
		result.text = "Coffee aboard while the harbour wakes around you." if morning \
			else Loc.t("Coffee aboard. Halyards tap along the pontoon.")
	result.minutes = COFFEE_MINUTES
	# The coffee goes into the captain's hand, in the one mug aboard.
	_set_coffee(COFFEE_CARRIED)
	_has_unsaved_changes = true
	return result


# --- The coffee mug and the captain's hands (Cozy Polish) ----------------------------
# A simple rule, not an inventory: two hands; the hat carried under the arm
# takes one, the coffee mug the other. With both full, the things that need a
# hand say so kindly (hands_refusal); walking, the stairs, the helm and the
# menus stay free. There is one mug; nothing about it is simulated.

const COFFEE_NONE := &""
const COFFEE_CARRIED := &"carried"
const COFFEE_HOLDER := &"holder"
const COFFEE_TABLE := &"table"


func get_coffee() -> StringName:
	return _state.galley.coffee if _state else COFFEE_NONE


func is_carrying_coffee() -> bool:
	return get_coffee() == COFFEE_CARRIED


## Free hands: two, less the carried hat and the carried mug.
func free_hands() -> int:
	if _state == null:
		return 2
	return 2 - (1 if _state.hat.status == HatState.CARRIED else 0) - (1 if is_carrying_coffee() else 0)


## Why an action needing a free hand cannot be done now, or "".
func hands_refusal() -> String:
	if free_hands() > 0:
		return ""
	return Loc.t("Your hands are full: the hat and a mug of coffee. Put your hat back on (H) or set the coffee down first.")


## Puts the carried mug in the cup holder by the helm (on deck) or on the
## cabin table. Returns the message for the player.
func put_coffee_down() -> String:
	if not is_carrying_coffee():
		return Loc.t("You have no coffee in hand.")
	if get_boat_area() == SessionState.AREA_EXTERIOR:
		_set_coffee(COFFEE_HOLDER)
		return Loc.t("You set your coffee in the cup holder by the helm.")
	_set_coffee(COFFEE_TABLE)
	return Loc.t("You set your coffee down on the table.")


## Takes the mug from where it stands here (holder on deck, table below).
func pick_up_coffee() -> String:
	var here := COFFEE_HOLDER if get_boat_area() == SessionState.AREA_EXTERIOR else COFFEE_TABLE
	if get_coffee() != here:
		return Loc.t("There is no coffee here.")
	if free_hands() == 0:
		return Loc.t("Your hands are full. Put your hat back on (H) first.")
	_set_coffee(COFFEE_CARRIED)
	return Loc.t("You pick up your coffee. Still warm enough.")


## Drinks up: the mug is empty and goes back to the galley.
func finish_coffee() -> String:
	if not is_carrying_coffee():
		return Loc.t("You have no coffee in hand.")
	_set_coffee(COFFEE_NONE)
	return Loc.t("You finish your coffee. Lovely.")


## Whether the mug stands here, to be picked up (holder on deck, table below).
func coffee_waits_here() -> bool:
	return get_coffee() == (COFFEE_HOLDER if get_boat_area() == SessionState.AREA_EXTERIOR else COFFEE_TABLE)


func _set_coffee(place: StringName) -> void:
	if _state == null or _state.galley.coffee == place:
		return
	_state.galley.coffee = place
	_has_unsaved_changes = true
	coffee_changed.emit(place)


## Why `recipe_id` cannot be cooked (ingredients), or "".
func recipe_refusal(recipe_id: String) -> String:
	var recipe := Recipes.get_recipe(recipe_id)
	if recipe.is_empty():
		return Loc.t("Unknown dish.")
	if _state.fishing.hold.size() < int(recipe.fish):
		return Loc.t("Needs %d fish from the cool box.") % int(recipe.fish)
	if _state.provisions.food_days + 1e-9 < float(recipe.groceries):
		return Loc.t("Not enough food in the stores.")
	return ""


## Cooks a dish: one transaction that takes its fish (the oldest in the cool
## box) and groceries, adds the cooked catch to the food stores and leaves the
## crew well fed. Refused, with nothing changed, without the ingredients or in
## rough conditions. Returns {"error", "recipe", "minutes", "food_added",
## "fish", "well_fed_until", "awards", "evening"}. The cooking time itself is
## spent by Simulation.spend_time_aboard().
func cook(recipe_id: String) -> Dictionary:
	var result := {"error": "", "recipe": recipe_id, "minutes": 0, "food_added": 0.0, "fish": [], "well_fed_until": 0.0,
		"awards": [], "evening": false}
	if _state == null:
		result.error = Loc.t("No game is running.")
		return result
	result.error = cooking_refusal()
	if result.error == "":
		result.error = recipe_refusal(recipe_id)
	if result.error != "":
		return result
	var recipe := Recipes.get_recipe(recipe_id)
	var used: Array[Dictionary] = []
	var kg := 0.0
	for i in int(recipe.fish):
		var fish: Dictionary = _state.fishing.hold.pop_front()
		used.append(fish)
		kg += float(fish.kg)
	_state.provisions.take_food(float(recipe.groceries))
	result.food_added = _state.provisions.add_food(Recipes.food_gained(recipe, kg), get_passage_store_days())
	var galley := _state.galley
	galley.well_fed_until = maxf(galley.well_fed_until, _state.game_time + float(recipe.well_fed_hours) * 3600.0)
	galley.meals_cooked += 1
	galley.last_meal = recipe_id
	galley.last_meal_at = _state.game_time
	result.minutes = int(recipe.minutes)
	result.fish = used
	result.well_fed_until = galley.well_fed_until
	var awards: Array[Dictionary] = [_award_once("cook:first", Loc.t("Your first meal from the galley: %s") % String(recipe.name).to_lower(), 2)]
	if not used.is_empty():
		awards.append(_award_once("cook:own_catch", Loc.t("Supper from your own catch"), 3))
		# The little story of the day: caught, anchored safely, cooked it.
		if is_anchored() and _state.anchor.holding != AnchorState.HOLDING_DRAGGING:
			result.evening = true
			awards.append(_award_once("evening:catch_anchor_cook", Loc.t("A quiet evening at anchor. Fresh fish for supper."), 5))
	awards = awards.filter(func(a: Dictionary) -> bool: return not a.is_empty())
	result.awards = awards
	_has_unsaved_changes = true
	_check_provisions()
	fishing_changed.emit()
	meal_cooked.emit(result.duplicate(true))
	if not awards.is_empty():
		renown_awarded.emit(awards)
	return result


# --- The anchor (Iteration 13) ------------------------------------------------------

## Dragging moves the boat this far downwind per anchor check (5 minutes).
const DRAG_NM_PER_CHECK := 0.04
## Dragging this close to land scrapes the boat (condition per check).
const DRAG_GROUND_NM := 0.6
const DRAG_GROUND_DAMAGE := 1.5
## A stay this long at anchor without dragging counts as a night at anchor.
const NIGHT_AT_ANCHOR_S := 8.0 * 3600.0


func is_anchored() -> bool:
	return _state != null and _state.anchor.active


func get_anchor() -> AnchorState:
	return _state.anchor.duplicate_state() if _state else AnchorState.new()


## The anchorage here, in the wind now (AnchorSite.evaluate()), for the
## anchors aboard (the Magic Anchor if the captain has it).
func evaluate_anchorage() -> Dictionary:
	if _state == null:
		return {"class": AnchorSite.CLASS_UNSUITABLE, "ok": false, "reason": Loc.t("No game is running.")}
	return AnchorSite.evaluate(_state.vessel_position, Simulation.get_weather_at_vessel(), has_magic_anchor())


## Why `kind` of anchor (normal / magic) cannot go down here, or "".
func anchoring_refusal(kind: StringName = AnchorState.KIND_NORMAL) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if is_anchored():
		return Loc.t("The anchor is already down.")
	if not is_underway():
		return Loc.t("In harbour the boat is moored: anchoring is for the coast between harbours.")
	if kind == AnchorState.KIND_MAGIC and not has_magic_anchor():
		return Loc.t("There is no Magic Anchor aboard.")
	var site := evaluate_anchorage()
	if kind == AnchorState.KIND_MAGIC:
		return "" if site.magic_ok else String(site.reason)
	if site.normal_ok:
		return ""
	return String(site.reason) if not site.magic_ok else Loc.t("Deep water (%s, %s): too deep for the normal anchor to reach the bottom. The Magic Anchor could hold here.") % [
		DepthService.describe_depth(float(site.depth_m)), site.depth_label]


# --- The Magic Anchor (0.105b) ----------------------------------------------------------

const MAGIC_ANCHOR_MARK := &"equipment:magic_anchor"
const MAGIC_ANCHOR_NAME := "Magic Anchor"
const MAGIC_ANCHOR_LONG_NAME := "Multi-purpose Deep Anchor"
const MAGIC_ANCHOR_TEXT := "For waters where the charts grow uncertain. A little engineering, a little seamanship, and a suspicious amount of nautical magic. Somehow it always finds a useful piece of seabed. (A fictional anchor: the game translates real-world depths into game-code magic. Not real seamanship.)"


## The captain owns the Magic Anchor (kept with the captain, so it goes to any
## boat; a progress mark in the save, no new field).
# --- A boat of your own (I020) ------------------------------------------------------------

func get_home() -> HomeState:
	return _state.home if _state else HomeState.new()


## The cabin things shown aboard `vessel_id` (the boat aboard by default).
func get_cabin_decor(vessel_id: StringName = &"") -> Array[String]:
	return _state.home.get_decor(vessel_id if vessel_id != &"" else _state.vessel_id) if _state else ([] as Array[String])


## Buys a cabin thing at the chandlery: once (it is the Captain's, for any
## boat), paid in full or not at all. Returns "" or why not.
func buy_decor(id: String) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	var item := HarbourTrades.get_decor_item(id)
	if item.is_empty():
		return Loc.t("Unknown item.")
	if not has_facility(HarbourFacilities.CHANDLERY):
		return facility_refusal(HarbourFacilities.CHANDLERY)
	if _state.home.owns_decor(id):
		return Loc.t("You already have it.")
	var price := int(item.price)
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed.") % format_money(price)
	_state.funds -= price
	_state.home.owned_decor.append(id)
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	home_changed.emit()
	return ""


## Shows (or puts away) one of the Captain's cabin things aboard the boat
## the Captain is on. Anywhere, any time: it is your cabin. Returns "" or why not.
func set_cabin_decor(id: String, shown: bool) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if not _state.home.owns_decor(id):
		return Loc.t("You do not have that yet: the chandlery sells it.")
	_state.home.set_decor_shown(_state.vessel_id, id, shown)
	_has_unsaved_changes = true
	home_changed.emit()
	return ""


## The sailcloth of `vessel_id` (the boat aboard by default).
func get_sail_cloth(vessel_id: StringName = &"") -> String:
	return _state.home.get_sails(vessel_id if vessel_id != &"" else _state.vessel_id) if _state else HarbourTrades.CLASSIC_CLOTH


## What the sailmaker asks to cut sails of `cloth` for this boat: 0 when the
## boat already has them (they are bent on again for nothing).
func sail_cloth_price(cloth: String) -> int:
	if _state == null or _state.home.has_cloth(_state.vessel_id, cloth):
		return 0
	return HarbourTrades.sail_cloth_price(cloth, get_base_vessel_profile().length_ft)


## The sailmaker cuts (or bends on again) sails of `cloth` for the boat
## aboard. A look only: the sails draw exactly as before. Returns "" or why not.
func order_sail_cloth(cloth: String) -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if HarbourTrades.get_sail_cloth(cloth).is_empty():
		return Loc.t("Unknown sailcloth.")
	if not has_facility(HarbourFacilities.SAILMAKER):
		return facility_refusal(HarbourFacilities.SAILMAKER)
	if get_sail_cloth() == cloth:
		return Loc.t("The sails are already that cloth.")
	var price := sail_cloth_price(cloth)
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed.") % format_money(price)
	_state.funds -= price
	_state.home.set_sails(_state.vessel_id, cloth)
	_has_unsaved_changes = true
	if price > 0:
		funds_changed.emit(_state.funds)
	home_changed.emit()
	return ""


## The Magic Anchor at the chandlery (I020; before, a free prototype at the
## boatyard). Once, for every boat. Returns "" or why not.
func buy_magic_anchor() -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if has_magic_anchor():
		return Loc.t("The Magic Anchor is already aboard.")
	if not has_facility(HarbourFacilities.CHANDLERY):
		return facility_refusal(HarbourFacilities.CHANDLERY)
	var price := HarbourTrades.get_magic_anchor_price()
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed.") % format_money(price)
	_state.funds -= price
	funds_changed.emit(_state.funds)
	return fit_magic_anchor()


func has_magic_anchor() -> bool:
	return _state != null and _state.progress.is_completed(MAGIC_ANCHOR_MARK)


## Prototype access (0.105b, until the chandlery of Iteration 20): fitted free
## at any boatyard. Returns "" or why not.
func fit_magic_anchor() -> String:
	if _state == null:
		return Loc.t("No game is running.")
	if has_magic_anchor():
		return Loc.t("The Magic Anchor is already aboard.")
	_state.progress.mark(MAGIC_ANCHOR_MARK, _state.game_time)
	_has_unsaved_changes = true
	boat_care_changed.emit()
	anchor_changed.emit()
	return ""


## How many good turns the Magic Anchor's dial asks for in this wind: 1 in
## ordinary conditions, 2 when it is blowing, 3 in a gale or storm.
func magic_anchor_checks() -> int:
	var wind := Simulation.get_weather_at_vessel().speed_kn
	if wind >= 28.0:
		return 3
	if wind >= 17.0:
		return 2
	return 1


## Lets the anchor go here on `scope`:1 chain, set with `set_quality` (0..1,
## from the setting interaction). The voyage pauses where the boat is.
## Returns {"error", "holding", "site"}.
func drop_anchor(scope: int, set_quality: float) -> Dictionary:
	return _let_go(AnchorState.KIND_NORMAL, scope, set_quality, 0)


## The Magic Anchor goes down (0.105b) after its dial: `perfects` Perfect hits
## earn a small holding bonus (bounded). Same anchored state, holding and
## drag model as the normal anchor. Returns {"error", "holding", "site"}.
func drop_magic_anchor(scope: int, set_quality: float, perfects := 0) -> Dictionary:
	return _let_go(AnchorState.KIND_MAGIC, scope, set_quality, perfects)


func _let_go(kind: StringName, scope: int, set_quality: float, perfects: int) -> Dictionary:
	var refusal := anchoring_refusal(kind)
	if refusal != "":
		return {"error": refusal, "holding": &"", "site": {}}
	if not scope in AnchorState.SCOPES:
		return {"error": Loc.t("Choose 3, 5 or 7 times the depth of chain."), "holding": &"", "site": {}}
	var site := evaluate_anchorage()
	var anchor := _state.anchor
	anchor.active = true
	anchor.position = _state.vessel_position
	anchor.scope = scope
	anchor.set_quality = clampf(set_quality, 0.0, 1.0)
	anchor.dragged_nm = 0.0
	anchor.alarm = false
	anchor.alarm_level = 0
	anchor.good_since = -1.0
	anchor.dragged_this_stay = false
	anchor.moments.clear()
	anchor.anchored_at = _state.game_time
	anchor.checked_until = _state.game_time
	anchor.kind = kind
	anchor.depth_m = float(site.get("depth_m", -1.0))
	anchor.depth_source = StringName(site.get("depth_source", &""))
	anchor.bonus_kn = minf(1.0 * maxi(perfects, 0), AnchorState.MAGIC_BONUS_MAX_KN) if kind == AnchorState.KIND_MAGIC else 0.0
	# Anchoring stops the engine (0.105b): the one propulsion state, stopped.
	_state.propulsion.mode = PropulsionState.MODE_SAIL
	_state.propulsion.engine_reason = PropulsionState.REASON_NONE
	_state.propulsion.speed_kn = 0.0
	# Anchored at the anchorage the voyage was waiting at: that stop is done.
	if _state.voyage and _state.voyage.holding_at >= 0:
		_state.voyage.anchorages_done.append(_state.voyage.holding_at)
		_state.voyage.holding_at = -1
	anchor.holding = AnchorSite.holding(scope, anchor.set_quality, site.shelter, Simulation.get_weather_at_vessel(), _holding_bonus())
	_has_unsaved_changes = true
	if anchor.holding in [AnchorState.HOLDING_WELL, AnchorState.HOLDING_FAIR]:
		var award := _award_once("anchor:first", Loc.t("Your first anchorage"), 3)
		if not award.is_empty():
			renown_awarded.emit([award])
	anchor_changed.emit()
	propulsion_changed.emit(PropulsionState.MODE_SAIL)
	return {"error": "", "holding": anchor.holding, "site": site}


## Holding bonus of the gear now down (knots): heavier ground tackle, and the
## Magic Anchor's well-placed bonus.
func _holding_bonus() -> float:
	return get_anchor_holding_bonus_kn() + (_state.anchor.bonus_kn if _state.anchor.kind == AnchorState.KIND_MAGIC else 0.0)


## Lets out (or takes in) chain, or sets the anchor again: the holding is
## worked out afresh. Answers an alarm. Returns the new holding.
func adjust_anchor(scope: int, set_quality := -1.0) -> StringName:
	if not is_anchored() or not scope in AnchorState.SCOPES:
		return &""
	var anchor := _state.anchor
	var was_dragging := anchor.holding == AnchorState.HOLDING_DRAGGING or anchor.dragged_this_stay
	anchor.scope = scope
	if set_quality >= 0.0:
		anchor.set_quality = clampf(set_quality, 0.0, 1.0)
		anchor.position = _state.vessel_position
	var shelter := AnchorSite.shelter_at(anchor.position, Simulation.get_weather_at_vessel())
	anchor.holding = AnchorSite.holding(scope, anchor.set_quality, shelter, Simulation.get_weather_at_vessel(), _holding_bonus())
	anchor.alarm = anchor.holding in [AnchorState.HOLDING_POOR, AnchorState.HOLDING_DRAGGING] and anchor.alarm
	if was_dragging and anchor.holding in [AnchorState.HOLDING_WELL, AnchorState.HOLDING_FAIR]:
		anchor.dragged_this_stay = false
		var award := _award_once("anchor:drag_handled", Loc.t("You stopped the anchor dragging"), 4)
		if not award.is_empty():
			renown_awarded.emit([award])
	_has_unsaved_changes = true
	anchor_changed.emit()
	return anchor.holding


## The alarm was seen (it sounds again if things get worse).
func acknowledge_anchor_alarm() -> void:
	if is_anchored() and _state.anchor.alarm:
		_state.anchor.alarm = false
		_has_unsaved_changes = true
		anchor_changed.emit()


# --- Anchorage waypoints (Iteration 18) ---------------------------------------------

## True the first time a one-off hint `id` is asked for in this game (then
## remembered in the save, so it is never repeated).
func take_hint(id: String) -> bool:
	if _state == null or _state.progress.is_completed(StringName("hint:" + id)):
		return false
	_state.progress.mark(StringName("hint:" + id), _state.game_time)
	_has_unsaved_changes = true
	return true

## The boat has reached an anchorage waypoint and waits there (stopped, the
## anchor not yet down).
func is_holding_at_anchorage() -> bool:
	return _state != null and _state.voyage != null and _state.voyage.holding_at >= 0 and not _state.anchor.active


## Standing by for a vessel in need (I019): the boat stays where it is.
func is_standing_by() -> bool:
	return _state != null and _state.voyage != null and not _state.anchor.active and _state.game_time < _state.voyage.standby_until - 1e-6


func get_standby_until() -> float:
	return _state.voyage.standby_until if _state and _state.voyage else 0.0


## Whether a VHF call (VhfRadio) can still be answered: underway, not yet
## answered, and heard less than VhfRadio.ANSWER_WITHIN_SECONDS ago.
func can_answer_vhf(call: Dictionary) -> bool:
	if _state == null or not is_underway() or call.is_empty():
		return false
	if _state.progress.is_completed(StringName("vhf:" + String(call.id))):
		return false
	return _state.game_time <= float(call.due) + VhfRadio.ANSWER_WITHIN_SECONDS


## The captain answers (or declines) a VHF call. Answering an assist call
## stands the boat by for its hours (the voyage waits); the thanks (renown,
## and for an assist a small gift) are paid once per call, whatever is saved
## and loaded. Returns {"answered", "text", "renown", "money"}.
func answer_vhf(call: Dictionary, accept: bool) -> Dictionary:
	var result := {"answered": false, "text": "", "renown": 0, "money": 0}
	if not accept or not can_answer_vhf(call):
		result.text = "Another vessel answers the call. The radio goes quiet." if not accept \
			else Loc.t("The call has been answered by another vessel.")
		return result
	var award := _award_once("vhf:" + String(call.id), Loc.t("Answered a call on channel 16: %s") % String(call.vessel), int(call.renown))
	if award.is_empty():
		result.text = "The call has been answered by another vessel."
		return result
	result.answered = true
	result.renown = int(call.renown)
	if call.kind == VhfRadio.KIND_ASSIST:
		_state.voyage.standby_until = _state.game_time + float(call.hours) * 3600.0
		_state.funds += int(call.money)
		result.money = int(call.money)
		result.text = Loc.t("You answer and heave to nearby. The crew of %s wave across the water. The coastguard expects to be there in about %d hours.") % [String(call.vessel), int(call.hours)]
		funds_changed.emit(_state.funds)
	else:
		result.text = "You read them the forecast. \"Thank you, skipper. Fair winds.\""
	_has_unsaved_changes = true
	renown_awarded.emit([award])
	return result


## Standing by ends: the coastguard has the yacht in tow (I019).
func end_standby() -> void:
	if _state and _state.voyage and _state.voyage.standby_until > 0.0:
		_state.voyage.standby_until = 0.0
		_has_unsaved_changes = true


## The next anchorage ahead on the voyage: {"index", "nm", "geo"} or {}.
func get_next_anchorage() -> Dictionary:
	return _state.voyage.next_anchorage() if _state and _state.voyage else {}


## Simulation only: the boat has come to `progress_nm`; if an anchorage
## waypoint not yet reached lies there, the boat stops and waits for the
## captain (the anchor is not set by itself). Returns whether it did.
func reach_anchorage_at(progress_nm: float) -> bool:
	if _state == null or _state.voyage == null or _state.anchor.active:
		return false
	var index := _state.voyage.anchorage_at(progress_nm)
	if index < 0:
		return false
	_state.voyage.holding_at = index
	_has_unsaved_changes = true
	SessionLog.write("anchorage_reached", {"waypoint": index, "geo": _geo_dict(_state.vessel_position)})
	anchorage_reached.emit(index)
	return true


## The captain chooses not to anchor at the anchorage the boat waits at and
## sails on along the course. Returns "" or why not.
func sail_on_from_anchorage() -> String:
	if not is_holding_at_anchorage():
		return Loc.t("The boat is not waiting at an anchorage.")
	_state.voyage.anchorages_done.append(_state.voyage.holding_at)
	_state.voyage.holding_at = -1
	_has_unsaved_changes = true
	voyage_course_changed.emit()
	return ""


## Whether a spot is fit to be an anchorage waypoint (0.105b: the worldwide
## rule of AnchorSite.evaluate - water, not too close to the shore, a safe
## approach, and a depth the normal anchor reaches, or any of those depths
## with `magic`). Shelter depends on the wind on arrival, so it is not judged
## here. Returns {"ok", "kind" (normal / magic), "reason", "land_nm",
## "depth_m", "depth_label"}.
static func anchorage_spot(geo: Vector2, magic := false) -> Dictionary:
	var calm := WindField.Sample.make(0.0, 0.0)
	var site := AnchorSite.evaluate(geo, calm, magic, false)
	var result := {"ok": site.ok, "kind": site.kind, "land_nm": site.land_nm, "depth_m": site.depth_m, "depth_label": site.depth_label,
		"offshore": site.offshore}
	if not site.ok:
		result.reason = String(site.reason)
	elif site.kind == AnchorSite.KIND_MAGIC:
		result.reason = Loc.t("Deep water (%s, %s): only the Magic Anchor will hold here.%s") % [DepthService.describe_depth(site.depth_m), site.depth_label,
			Loc.t(" Open sea: no shelter from wind or waves.") if site.offshore else ""]
	else:
		result.reason = Loc.format("Good for the normal anchor (%s, %s; land %.1f nm away). How sheltered it is depends on the wind when you arrive.", [
			DepthService.describe_depth(site.depth_m), site.depth_label, float(site.land_nm)])
	return result


## The nearest spot fit for an anchorage within `max_nm` of `geo`, or INF
## (for the normal anchor, or any anchor with `magic`). Cheap checks first
## (clear water, depth), the approach search only for the best of a ring.
static func nearest_anchorage_spot(geo: Vector2, max_nm := 12.0, magic := false) -> Vector2:
	var coast := CoastalGeography.get_default()
	var depths := DepthService.get_default()
	var step := 0.25
	var r := step
	while r <= max_nm:
		var candidates: Array = []
		for k in 32:
			var point := GeoMath.normalize(AnchorSite.offset(geo, TAU * k / 32.0, r))
			if not coast.is_clear(point):
				continue
			var depth := float(depths.sample(point).depth_m)
			if magic or (depth >= AnchorSite.MIN_DEPTH_M and depth <= AnchorSite.NORMAL_MAX_DEPTH_M):
				candidates.append([absf(depth - 8.0), point])
		candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for candidate: Array in candidates:
			if anchorage_spot(candidate[1], magic).ok:
				return candidate[1]
		r += step
	return Vector2.INF


## Weighs anchor: the voyage continues along its course from where it paused.
func raise_anchor() -> String:
	if not is_anchored():
		return Loc.t("The anchor is not down.")
	_state.anchor.active = false
	_state.anchor.alarm = false
	_state.anchor.alarm_level = 0
	_state.anchor.good_since = -1.0
	_state.vessel_position = _state.voyage.get_position()
	_state.propulsion = PropulsionState.new()
	_has_unsaved_changes = true
	anchor_changed.emit()
	_companion_to_cabin_if_needed()  # sailing on: the companion goes below
	return ""


## One anchor check at the current game time (Simulation only, on its fixed
## grid): the holding against the wind now; dragging moves the boat downwind
## a little (never jumps) and, very near land, scrapes it. Returns "" or
## "poor" / "dragging" when the captain must be woken.
func apply_anchor_check(tick: float) -> String:
	if not is_anchored():
		return ""
	var anchor := _state.anchor
	anchor.checked_until = maxf(anchor.checked_until, tick)
	var sample := Simulation.get_weather_at_vessel()
	var shelter := AnchorSite.shelter_at(anchor.position, sample)
	var before := anchor.holding
	anchor.holding = AnchorSite.holding(anchor.scope, anchor.set_quality, shelter, sample, _holding_bonus())
	var event := ""
	# I019: an alarm only when the concern rises (poor 1, dragging 2) past what
	# was already announced; holding well again is said once, quietly, and
	# after an hour of good holding the next trouble is news again.
	var level := 2 if anchor.holding == AnchorState.HOLDING_DRAGGING else (1 if anchor.holding == AnchorState.HOLDING_POOR else 0)
	if level == 0:
		if anchor.alarm_level > 0 and anchor.good_since < 0.0:
			anchor.good_since = tick
			anchor.alarm = false
			notice.emit(Loc.t("The anchor is holding well again."))
		elif anchor.alarm_level > 0 and tick - anchor.good_since >= AnchorState.GOOD_RESET_SECONDS:
			anchor.alarm_level = 0
	else:
		anchor.good_since = -1.0
	if anchor.holding == AnchorState.HOLDING_DRAGGING:
		anchor.dragged_this_stay = true
		# Downwind a little; never up onto the land (0.105b, fine coast): on the
		# shore's edge the boat stays and scrapes.
		var next := AnchorSite.offset(anchor.position, deg_to_rad(sample.from_deg + 180.0), DRAG_NM_PER_CHECK)
		var coast := CoastalGeography.get_default()
		if SeaRouter.get_default().is_afloat(next):
			anchor.position = next
			anchor.dragged_nm += DRAG_NM_PER_CHECK
			_state.vessel_position = anchor.position
		if coast.shore_distance_nm(anchor.position, DRAG_GROUND_NM) < DRAG_GROUND_NM:
			apply_weather_damage(DRAG_GROUND_DAMAGE, tick)
		if anchor.alarm_level < 2:
			anchor.alarm = true
			anchor.alarm_level = 2
			event = "dragging"
			anchor_alarm.emit({"level": "dragging", "text": Loc.t("Anchor dragging! The boat is moving downwind. Let out more chain, set the anchor again or weigh anchor.")})
	elif anchor.holding == AnchorState.HOLDING_POOR and anchor.alarm_level < 1:
		anchor.alarm = true
		anchor.alarm_level = 1
		event = "poor"
		anchor_alarm.emit({"level": "poor", "text": Loc.t("The anchor is holding poorly as the wind rises. Check it: more chain helps.")})
	if before != anchor.holding:
		anchor_changed.emit()
	if tick - anchor.anchored_at >= NIGHT_AT_ANCHOR_S and not anchor.dragged_this_stay:
		var award := _award_once("anchor:night", Loc.t("A night at anchor"), 3)
		if not award.is_empty():
			renown_awarded.emit([award])
	_has_unsaved_changes = true
	return event


## Weather damage at anchor: a sheltered, holding anchorage takes less.
func get_anchor_damage_factor() -> float:
	if not is_anchored() or _state.anchor.holding == AnchorState.HOLDING_DRAGGING:
		return 1.0
	return float(AnchorSite.EXPOSURE.get(AnchorSite.shelter_at(_state.anchor.position, Simulation.get_weather_at_vessel()), 1.0))


func get_anchor_checked_until() -> float:
	return _state.anchor.checked_until if _state else 0.0


func get_fish_checked_until() -> float:
	return _state.fishing.checked_until if _state else 0.0


## Notable moments of fishing, cooking and anchoring for the Captain's Log:
## [{"time", "text"}] from the milestone records.
func get_aboard_moments() -> Array[Dictionary]:
	var moments: Array[Dictionary] = []
	if _state == null:
		return moments
	var catalog := FishingCatalog.get_default()
	for key: String in _state.progress.completed:
		var entry: Dictionary = _state.progress.completed[key]
		var text := ""
		var time := float(entry.first)
		if key == "fish:first":
			text = Loc.t("Caught my first fish")
		elif key.begins_with("fish:species:"):
			text = Loc.t("First %s caught") % catalog.get_species_name(key.get_slice(":", 2)).to_lower()
		elif key.begins_with("fish:exceptional:"):
			text = Loc.t("An exceptional %s") % catalog.get_species_name(key.get_slice(":", 2)).to_lower()
		elif key.begins_with("fish:best:"):
			var species := key.get_slice(":", 2)
			text = Loc.format("New personal best: %s, %.1f kg", [catalog.get_species_name(species), float(_state.fishing.records.get(species, {}).get("best_kg", 0.0))])
			time = float(entry.last_event)
		elif key == "cook:first":
			text = Loc.t("First meal cooked in the galley")
		elif key == "cook:own_catch":
			text = Loc.t("Supper from my own catch")
		elif key == "evening:catch_anchor_cook":
			text = Loc.t("A quiet evening at anchor. Fresh fish for supper.")
		elif key == "anchor:first":
			text = Loc.t("First anchorage of my own")
		elif key == "anchor:night":
			text = Loc.t("A night at anchor")
		elif key == "anchor:drag_handled":
			text = Loc.t("Stopped the anchor dragging")
		elif key == "coffee:morning_at_anchor":
			text = Loc.t("Morning coffee at anchor. The day could wait a little.")
		elif key == "care:first_haul_out":
			text = Loc.t("First haul-out: the bottom scrubbed clean")
		if text != "":
			moments.append({"time": time, "text": text})
	return moments


# --- Go Ashore (Iteration 12) -------------------------------------------------------

## What Go Ashore offers now: {} where it is not available; {"resting": true,
## "until": game time} shortly after an outing in this harbour; otherwise
## {"event": the ShoreEvents event, "seen": true when every event here has
## been enjoyed before (no more rewards)}. Events not yet enjoyed in this
## harbour come first, in an order that is stable for the game (no
## re-rolling by reopening).
func get_shore_event() -> Dictionary:
	if not has_facility(HarbourFacilities.GO_ASHORE):
		return {}
	var port := _state.location_id
	var last := _last_shore_time(port)
	if last > -INF and _state.game_time - last < ShoreEvents.REST_HOURS * 3600.0:
		return {"resting": true, "until": last + ShoreEvents.REST_HOURS * 3600.0}
	var events := ShoreEvents.for_port(port)
	var fresh: Array[Dictionary] = []
	var outings := 0
	for event in events:
		var key := ShoreEvents.record_id(port, event.id)
		if _state.progress.is_completed(StringName(key)):
			outings += _state.progress.get_count(StringName(key))
		else:
			fresh.append(event)
	var pool := fresh if not fresh.is_empty() else events
	var index := absi(hash("%d|%s|%d" % [_state.wind_seed, port, outings])) % pool.size()
	return {"event": pool[index], "seen": fresh.is_empty()}


## Makes choice `choice_index` of event `event_id` here: one transaction that
## pays its small cost, records the outing and, the first time in this
## harbour, pays its renown (a notable moment in the Captain's Log). Refused,
## with nothing changed, when Go Ashore is not offered here, the harbour is
## resting, the event is not the one on offer, or the money is not enough.
## Returns {"error", "cost", "minutes", "renown", "outcome", "title"}. The
## time itself is spent by Simulation.spend_time_ashore().
func apply_shore_choice(event_id: String, choice_index: int) -> Dictionary:
	var result := {"error": "", "cost": 0, "minutes": 0, "renown": 0, "outcome": "", "title": ""}
	if _state == null or not has_facility(HarbourFacilities.GO_ASHORE):
		result.error = facility_refusal(HarbourFacilities.GO_ASHORE) if _state else Loc.t("No game is running.")
		return result
	var offer := get_shore_event()
	if offer.get("resting", false):
		result.error = Loc.t("You have just been ashore. Come back a little later.")
		return result
	var event: Dictionary = offer.get("event", {})
	if event.is_empty() or event.id != event_id or choice_index < 0 or choice_index >= event.choices.size():
		result.error = Loc.t("That outing is not on offer here.")
		return result
	var choice: Dictionary = event.choices[choice_index]
	var cost := int(choice.cost)
	if cost > _state.funds:
		result.error = Loc.t("Not enough money: %s needed, you have %s.") % [format_money(cost), format_money(_state.funds)]
		return result
	var port := _state.location_id
	var harbour_name := get_location().display_name
	var key := StringName(ShoreEvents.record_id(port, event_id))
	var first := not _state.progress.is_completed(key)
	var title := Loc.t("Ashore in %s: %s") % [harbour_name, event.title]
	var renown := int(choice.renown) if first else 0
	if cost > 0:
		_state.funds -= cost
	if renown > 0:
		_state.progress.award(key, title, renown, _state.game_time)
	else:
		_state.progress.mark(key, _state.game_time)
	_has_unsaved_changes = true
	result.cost = cost
	result.minutes = int(choice.minutes)
	result.renown = renown
	result.title = title
	result.outcome = ShoreEvents.fill(String(choice.outcome), harbour_name)
	if cost > 0:
		funds_changed.emit(_state.funds)
	if renown > 0:
		renown_awarded.emit([{"id": String(key), "reward": renown, "title": title, "text": result.outcome, "secret": false, "tone": ""}])
	return result


## The most recent outing in `port_id` (game time), or -INF.
func _last_shore_time(port_id: StringName) -> float:
	var prefix := "%s%s:" % [ShoreEvents.RECORD_PREFIX, port_id]
	var last := -INF
	for key: String in _state.progress.completed:
		if key.begins_with(prefix):
			last = maxf(last, float(_state.progress.completed[key].last_event))
	return last


## Go Ashore outings as notable moments: [{"time", "text"}], oldest first
## (the first time each was enjoyed).
func get_shore_moments() -> Array[Dictionary]:
	var moments: Array[Dictionary] = []
	if _state == null:
		return moments
	for key: String in _state.progress.completed:
		if not key.begins_with(ShoreEvents.RECORD_PREFIX):
			continue
		var parts := key.split(":")
		if parts.size() != 3:
			continue
		var event := ShoreEvents.find(StringName(parts[1]), parts[2])
		var harbour := PortCatalog.get_default().get_display_name(StringName(parts[1]))
		if not event.is_empty():
			moments.append({"time": float(_state.progress.completed[key].first), "text": Loc.t("Ashore in %s: %s") % [harbour, event.title]})
	moments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	return moments


func get_rescue_count() -> int:
	return _state.rescue_count if _state else 0


func get_last_rescue() -> Dictionary:
	return _state.last_rescue.duplicate(true) if _state else {}


## Development tools only (DevTools): sets the active boat's condition.
## Zero is not allowed here; losing the boat is left to the real weather path.
func set_condition_for_testing(percent: float) -> void:
	if _state == null:
		return
	_state.set_condition(_state.vessel_id, clampf(percent, 0.1, VesselCondition.FULL))
	_has_unsaved_changes = true
	condition_changed.emit(get_condition())


# --- Money ----------------------------------------------------------------------------

## Euros (whole).
func get_funds() -> int:
	return _state.funds if _state else 0


## "€1,200" (Danish: "1.200 €").
static func format_money(euros: int) -> String:
	var grouped := Loc.thousands(absi(euros))
	return Loc.t("€%s", "money") % grouped


# --- Provisions -----------------------------------------------------------------------

## A copy of the food and water aboard.
func get_provisions() -> Provisions:
	return _state.provisions.duplicate_provisions() if _state else Provisions.new()


func get_food_days() -> float:
	return _state.provisions.food_days if _state else 0.0


func get_water_days() -> float:
	return _state.provisions.water_days if _state else 0.0


## Price of provisions at the grocery store: euros per missing day of food or
## of water (combined), the same in every harbour.
const PROVISIONS_PRICE_PER_DAY := 10
## Remote work: euros per completed hour, and the hours one session may last.
const REMOTE_WORK_PAY_PER_HOUR := 25
const REMOTE_WORK_MIN_HOURS := 1
const REMOTE_WORK_MAX_HOURS := 8


## Days missing to fill food and water to `target` days each, both counted
## (0-28 for the everyday stores).
func get_missing_provision_days(target := Provisions.CAPACITY_DAYS) -> float:
	if _state == null:
		return 0.0
	return maxf(target - _state.provisions.food_days, 0.0) + maxf(target - _state.provisions.water_days, 0.0)


## What filling food and water to `target` days costs now (whole euros,
## rounded up, so a fraction of a day is never free).
func get_provisions_price(target := Provisions.CAPACITY_DAYS) -> int:
	return ceili(get_missing_provision_days(target) * PROVISIONS_PRICE_PER_DAY * Difficulty.factor("costs") - 1e-6)


## Days of food and water the active boat can stow for a long passage
## (Iteration 16).
func get_passage_store_days() -> float:
	var vessel := VesselCatalog.get_default().get_vessel(_state.vessel_id) if _state else null
	return maxf(vessel.passage_stores_days, Provisions.CAPACITY_DAYS) if vessel else Provisions.CAPACITY_DAYS


## Buys food and water up to `target` days each (the everyday 14 by default)
## at the grocery store: one transaction that pays get_provisions_price() and
## fills both stores. Harbour only, and refused (nothing changes) when the
## money is not enough. Returns "" on success, otherwise the reason.
func buy_provisions(target := Provisions.CAPACITY_DAYS) -> String:
	if not is_moored_in_harbour():
		return Loc.t("The grocery store is only reachable while moored in harbour.")
	if not has_facility(HarbourFacilities.GROCERY):
		return facility_refusal(HarbourFacilities.GROCERY)
	target = minf(target, get_passage_store_days())
	if _state.provisions.is_full(target):
		return Loc.t("Food and water are already full.")
	var price := get_provisions_price(target)
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed, you have %s.") % [format_money(price), format_money(_state.funds)]
	_state.funds -= price
	_state.provisions.restock(target)
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	provisions_changed.emit()
	return ""


## Remote work is possible while moored in harbour (a reliable connection).
func can_work_remotely() -> bool:
	return is_moored_in_harbour()


## Pays for `hours` completed hours of remote work (Simulation.work only,
## after it has advanced the time).
func pay_remote_work(hours: int) -> int:
	if _state == null or hours <= 0:
		return 0
	var earned := hours * REMOTE_WORK_PAY_PER_HOUR
	_state.funds += earned
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	return earned


## Development tools only (DevTools): sets food and water to `days`.
func set_provisions_for_testing(days: float) -> void:
	if _state == null:
		return
	_state.provisions.food_days = clampf(days, 0.0, Provisions.MAX_STORE_DAYS)
	_state.provisions.water_days = clampf(days, 0.0, Provisions.MAX_STORE_DAYS)
	_state.provisions.warning_level = Provisions.WARN_NONE
	_has_unsaved_changes = true
	_check_provisions()
	provisions_changed.emit()


## Gives each low-stores warning once (until the stores are refilled).
func _check_provisions() -> void:
	var needed := _state.provisions.needed_warning()
	if needed <= _state.provisions.warning_level:
		return
	_state.provisions.warning_level = needed
	var text := ""
	match needed:
		Provisions.WARN_LOW:
			text = Loc.t("Provisions are running low: %s of food and water left.") % Provisions.format_days(_state.provisions.endurance_days())
		Provisions.WARN_CRITICAL:
			text = Loc.t("Provisions are critically low: less than a day of food or water left.")
		_:
			text = Loc.t("You have run out of food or water. Head for a harbour and buy provisions before the next passage.")
	provisions_changed.emit()
	provisions_warning.emit(needed, text)


# --- Captain's hat -------------------------------------------------------------------

## Open water is looked for this far around a hat lost at sea (nm).
const OFFSHORE_CHECK_NM := 30.0


## A copy of the hat (state, strain, history).
func get_hat() -> HatState:
	return _state.hat.duplicate_hat() if _state else HatState.new()


func get_hat_status() -> StringName:
	return _state.hat.status if _state else HatState.STORED


## True while the worn hat has had its wind warning and the player is on deck:
## the HUD shows it fluttering (Iteration 12; read only, nothing changes).
func is_hat_at_risk() -> bool:
	return _state != null and _state.hat.status == HatState.WORN and _state.hat.warned \
		and _state.boat_area == SessionState.AREA_EXTERIOR


## What a replacement hat costs (data/hat/hat_config.json).
func get_hat_price() -> int:
	return HatConfig.get_default().price_eur


## The hook in the cabin: puts the hat on when it hangs there, hangs it up
## when the player has it. Returns the message for the player.
func use_hat_hook() -> String:
	if _state == null:
		return ""
	match _state.hat.status:
		HatState.STORED:
			_set_hat_status(HatState.WORN)
			return Loc.t("You put on your captain's hat. Very distinguished.")
		HatState.WORN, HatState.CARRIED:
			_set_hat_status(HatState.STORED)
			return Loc.t("You hang your captain's hat on its hook.")
	return Loc.t("An empty hat hook. Replacement captain's hats are sold at the harbour grocery store (%s).") % format_money(get_hat_price())


## The hat key (H): takes a worn hat off (it is tucked under the arm, safe from
## the wind) or puts a carried one back on. A hat on its hook stays there.
## Returns the message for the player.
func toggle_hat() -> String:
	if _state == null:
		return ""
	match _state.hat.status:
		HatState.WORN:
			if free_hands() == 0:
				return hands_refusal()
			_set_hat_status(HatState.CARRIED)
			return Loc.t("You take off your captain's hat and tuck it under your arm.")
		HatState.CARRIED:
			_set_hat_status(HatState.WORN)
			return Loc.t("You put your captain's hat back on.")
		HatState.STORED:
			return Loc.t("Your captain's hat hangs on its hook in the cabin.")
	return Loc.t("You have no captain's hat. The harbour grocery store sells replacements (%s).") % format_money(get_hat_price())


## The worn hat is out in the wind: on deck. (Simulation also treats sleeping
## and working as below deck.)
func is_hat_exposed() -> bool:
	return _state != null and _state.hat.status == HatState.WORN and _state.boat_area == SessionState.AREA_EXTERIOR


## Hat checks have been made up to this game time (Simulation only).
func get_hat_checked_until() -> float:
	return _state.hat.checked_until if _state else 0.0


## The hat recovers for `ticks` hat checks in which it was not at risk (below
## deck, taken off, or light wind), the last of them at `until` (Simulation
## only).
func recover_hat(ticks: int, until: float) -> void:
	if _state == null:
		return
	var hat := _state.hat
	hat.checked_until = maxf(hat.checked_until, until)
	if ticks <= 0 or (hat.strain <= 0.0 and not hat.warned):
		return
	var config := HatConfig.get_default()
	hat.strain = maxf(hat.strain - config.recovery_per_min * config.check_interval_s / 60.0 * ticks, 0.0)
	# A new warning only after the hat has fully recovered and a while has
	# passed, so stepping in and out of the companionway never repeats it.
	if hat.strain <= 0.0 and until - hat.warned_at >= config.warning_repeat_min * 60.0:
		hat.warned = false
	_has_unsaved_changes = true


## One hat check at `time` while the hat is worn on deck (Simulation only):
## `strain_per_min` from HatConfig for the weather `sample` at `position`.
## The first check with any risk only warns; later ones add strain, and the
## hat blows away at its threshold. Returns &"" , &"warned" or &"lost".
func apply_hat_check(time: float, strain_per_min: float, sample: WeatherSample, position: Vector2) -> StringName:
	if _state == null or _state.hat.status != HatState.WORN:
		return &""
	var hat := _state.hat
	var config := HatConfig.get_default()
	hat.checked_until = maxf(hat.checked_until, time)
	if _state.voyage:
		hat.voyage_worn_hazard = maxi(hat.voyage_worn_hazard, sample.hazard)
	_has_unsaved_changes = true
	if strain_per_min <= 0.0:
		recover_hat(1, time)
		return &""
	if not hat.warned:
		hat.warned = true
		hat.warned_at = time
		hat_warning.emit(Loc.t("Better hold onto your hat! The wind is %d kn%s. Go below, or press H to take it off.") % [
			roundi(sample.speed_kn), Loc.t(", gusting %d") % roundi(sample.gust_kn) if sample.gust_kn >= sample.speed_kn + 6.0 else ""])
		return &"warned"
	hat.strain += strain_per_min * config.check_interval_s / 60.0
	if hat.strain < config.threshold_for(_state.wind_seed, hat.serial):
		return &""
	_lose_hat(time, sample, position)
	return &"lost"


func _lose_hat(time: float, sample: WeatherSample, position: Vector2) -> void:
	var hat := _state.hat
	hat.status = HatState.LOST
	hat.strain = 0.0
	hat.warned = false
	hat.lost_count += 1
	if _state.voyage:
		hat.voyage_lost = true
	var in_harbour := not is_underway()
	var place := HatStory.describe_place(position, _state.location_id if in_harbour else &"")
	var log_text := HatStory.loss_log_line(hat.lost_count, place, sample)
	hat.add_history(time, HatState.EVENT_LOST, log_text)
	_has_unsaved_changes = true
	# How far from land, for "The Sea Wears a Hat Now" (only at sea).
	var open_water := 0.0 if in_harbour else HatStory.open_water_nm(position, OFFSHORE_CHECK_NM)
	var info := {"time": time, "text": HatStory.loss_message(hat.lost_count), "log_text": log_text,
		"lost_count": hat.lost_count, "serial": hat.serial, "wind_kn": sample.speed_kn, "gust_kn": sample.gust_kn,
		"in_harbour": in_harbour, "position": {"lon": position.x, "lat": position.y},
		"bought_at": hat.bought_at, "open_water_nm": open_water}
	var awards := _award_hat_objectives({"kind": ObjectiveCatalog.HAT_EVENT_LOST, "time": time, "underway": not in_harbour,
		"open_water_nm": open_water, "bought_at": hat.bought_at})
	hat_changed.emit(hat.status)
	hat_lost.emit(info)
	if not awards.is_empty():
		renown_awarded.emit(awards)


## Buys a replacement hat at the harbour grocery store: one transaction that
## pays get_hat_price() and hands the player the new hat (carried, ready to
## put on). Harbour only, only without a hat, and refused (nothing changes)
## when the money is not enough. Returns "" on success, otherwise the reason.
func buy_hat() -> String:
	if not is_moored_in_harbour():
		return Loc.t("Captain's hats are sold at the harbour grocery store, while moored in harbour.")
	if not has_facility(HarbourFacilities.GROCERY):
		return facility_refusal(HarbourFacilities.GROCERY)
	if _state.hat.is_owned():
		return Loc.t("You already have your captain's hat.")
	var price := get_hat_price()
	if price > _state.funds:
		return Loc.t("Not enough money: %s needed, you have %s.") % [format_money(price), format_money(_state.funds)]
	var hat := _state.hat
	_state.funds -= price
	hat.status = HatState.CARRIED
	hat.serial += 1
	hat.bought_count += 1
	hat.spent += price
	hat.bought_at = _state.game_time
	hat.strain = 0.0
	hat.warned = false
	var place := get_location()
	hat.add_history(_state.game_time, HatState.EVENT_BOUGHT, Loc.t("Bought a new captain's hat in %s for %s%s.") % [
		place.display_name if place else "harbour", format_money(price),
		"" if hat.bought_count == 1 else Loc.t(" (hat number %d)") % hat.serial])
	var awards := _award_hat_objectives({"kind": ObjectiveCatalog.HAT_EVENT_BOUGHT, "time": _state.game_time})
	_has_unsaved_changes = true
	funds_changed.emit(_state.funds)
	hat_changed.emit(hat.status)
	hat_bought.emit({"price": price, "funds_after": _state.funds, "serial": hat.serial})
	if not awards.is_empty():
		renown_awarded.emit(awards)
	return ""


func _set_hat_status(status: StringName) -> void:
	if _state.hat.status == status:
		return
	_state.hat.status = status
	_has_unsaved_changes = true
	hat_changed.emit(status)


# --- Internals ------------------------------------------------------------------------

## Saves from before route calculation only stored a destination. Calculate the
## sea route now; if that is impossible, drop the plan and tell the player.
func _complete_legacy_route() -> void:
	var route := _state.planned_route
	if route == null or route.has_path() or is_underway():
		return
	var location := get_location()
	var result := SeaRouter.get_default().plan_route(location.id, location.get_geo_position(),
		route.waypoints, route.destination_port_id)
	if result.is_ok():
		_state.planned_route = result.route
	else:
		_state.planned_route = null
		notice.emit.call_deferred(Loc.t("The saved course to %s could not be recalculated and was removed.") %
			PortCatalog.get_default().get_display_name(route.destination_port_id))


## Iteration 14: a more detailed chart can place a position saved under the
## old chart on land, or make a saved course cross a new island. The vessel is
## never stranded or erased: it is moved to the nearest open water and the
## remaining course is re-planned from there. Changes are reported through
## location_recovered and get_last_location_recovery().
func _recover_location() -> void:
	_last_recovery = {}
	# 0.105b: anchoring stops the engine; an older save at anchor with the
	# engine running is set right (the one propulsion state, stopped).
	if _state.anchor.active and _state.propulsion.is_motoring():
		_state.propulsion.mode = PropulsionState.MODE_SAIL
		_state.propulsion.engine_reason = PropulsionState.REASON_NONE
		_state.propulsion.speed_kn = 0.0
	var router := SeaRouter.get_default()
	if is_underway():
		_recover_voyage(router)
	elif _state.planned_route != null and _state.planned_route.has_path() \
			and not router.validate_route(_state.planned_route).is_empty():
		var route := _state.planned_route
		var location := get_location()
		var result := router.plan_route(location.id, location.get_geo_position(), _navigable(router, route.waypoints),
			route.destination_port_id)
		_state.planned_route = result.route if result.is_ok() else null
		_report_recovery({"kind": "planned_route", "replanned": result.is_ok()})


func _recover_voyage(router: SeaRouter) -> void:
	var voyage := _state.voyage
	var anchor := _state.anchor
	var position := anchor.position if anchor.active else voyage.get_position()
	var remaining := voyage.get_remaining_path()
	var check := PlannedRoute.new()
	check.origin_port_id = voyage.route.origin_port_id
	check.destination_port_id = voyage.route.destination_port_id
	check.waypoints = voyage.get_remaining_waypoints()
	check.path = remaining
	check.origin_position = remaining[0] if not remaining.is_empty() else position
	# The remaining path is a cut of the voyage's route: the first leg out of a
	# harbour may be a berth link, allowed only from the port itself, so the
	# cut alone can fail although nothing changed. The whole route still being
	# valid is enough (Iteration 18: a save just after leaving harbour asked
	# for the course to be plotted again).
	var path_ok := remaining.size() >= 2 and (router.validate_route(check).is_empty() or router.validate_route(voyage.route).is_empty())
	var position_ok := _near_route_port(router, position, voyage.route) or router.is_afloat(position)
	if path_ok and position_ok:
		return
	var start := position
	if not position_ok:
		start = router.nearest_navigable(position)
		if start == Vector2.INF:
			start = router.nearest_navigable(position, 60.0)
	if start == Vector2.INF:
		_report_recovery({"kind": "voyage", "from": _geo_dict(position), "replanned": false, "failed": true})
		return
	var waypoints := _navigable(router, check.waypoints)
	var result := router.plan_route(&"", start, waypoints, check.destination_port_id)
	if not result.is_ok() and not waypoints.is_empty():
		result = router.plan_route(&"", start, [] as Array[Vector2], check.destination_port_id)
	if result.is_ok():
		voyage.route = result.route
		voyage.progress_nm = 0.0
		voyage.revision += 1
		voyage.warned_conditions.clear()
	if anchor.active:
		anchor.position = start
	_state.vessel_position = start if anchor.active or not result.is_ok() else voyage.get_position()
	_report_recovery({"kind": "voyage", "from": _geo_dict(position), "to": _geo_dict(start),
		"moved_nm": snappedf(GeoMath.rhumb_distance_nm(position, start), 0.01), "replanned": result.is_ok(),
		"anchored": anchor.active})


func _near_route_port(router: SeaRouter, position: Vector2, route: PlannedRoute) -> bool:
	for id: StringName in [route.origin_port_id, route.destination_port_id]:
		var port := PortCatalog.get_default().get_port(id)
		if port and GeoMath.rhumb_distance_nm(port.get_geo_position(), position) <= router.approach_radius_nm(port.get_geo_position()) \
				and router.grid.cell_class_at_geo(position) >= NavGrid.APPROACH:
			return true
	return false


func _navigable(router: SeaRouter, points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		if router.is_point_reachable(point):
			result.append(point)
	return result


static func _geo_dict(geo: Vector2) -> Dictionary:
	return {"lon": snappedf(geo.x, 0.0001), "lat": snappedf(geo.y, 0.0001)}


func _report_recovery(info: Dictionary) -> void:
	_last_recovery = info
	if info.get("failed", false):  # (a recovery itself is logged as "location_recovered")
		SessionLog.write("invalid_position", info)
	location_recovered.emit.call_deferred(info)
	var text := Loc.t("The chart has been updated. Your course was re-planned.") if info.get("replanned", false) \
		else Loc.t("The chart has been updated. Please plot your course again.")
	if info.get("kind") == "voyage" and float(info.get("moved_nm", 0.0)) > 0.0:
		text = Loc.format("The chart has been updated. The boat has been moved %.1f nm to nearby open water.", float(info.moved_nm))
	notice.emit.call_deferred(text)


## The last load's location recovery ({} when nothing needed changing).
func get_last_location_recovery() -> Dictionary:
	return _last_recovery


var _last_recovery := {}


# --- Life at anchor (revision 0.102b) ----------------------------------------------

var _settled := false
var _asleep := false


## True while the boat lies safely and quietly at anchor: holding well or
## fair, no alarm, and a moderate wind where she lies (AnchorLife).
func is_settled_at_anchor() -> bool:
	return _settled


## The local solar hour at the boat (0..24) and the time of day it makes.
func get_local_hour() -> float:
	return AnchorLife.local_hour(get_game_time(), get_vessel_position().x) if _state else 12.0


func get_day_phase() -> StringName:
	return AnchorLife.phase_at(get_local_hour())


## Works out whether the boat is settled and, when it is, whether a quiet
## moment is due (never while the captain sleeps; one at a time).
func _update_anchor_life(moments := true) -> void:
	if _state == null:
		return
	var anchor := _state.anchor
	var settled := anchor.active and not anchor.alarm \
		and anchor.holding in [AnchorState.HOLDING_WELL, AnchorState.HOLDING_FAIR] \
		and Simulation.get_weather_at_vessel().speed_kn < AnchorLife.SETTLED_WIND_KN
	if settled != _settled:
		_settled = settled
		anchor_life_changed.emit(settled)
	if not settled or not moments or _asleep:
		return
	var day := AnchorLife.local_day(_state.game_time, _state.vessel_position.x)
	if not "settled" in anchor.moments:
		if _state.game_time >= anchor.anchored_at + AnchorLife.SETTLE_DELAY_S:
			_record_moment("settled", "settled", AnchorLife.pick(AnchorLife.SETTLED_LINES, day))
		return
	var phase := get_day_phase()
	var evening_key := "evening:%d" % day
	if phase == AnchorLife.PHASE_EVENING and not evening_key in anchor.moments:
		_record_moment(evening_key, "evening", AnchorLife.pick(AnchorLife.EVENING_LINES, day))


func _record_moment(key: String, kind: String, text: String) -> void:
	var anchor := _state.anchor
	if key in anchor.moments:
		return
	anchor.moments.append(key)
	while anchor.moments.size() > AnchorState.MAX_MOMENTS:
		anchor.moments.pop_front()
	_has_unsaved_changes = true
	anchor_moment.emit(kind, text)


## The App calls these around a sleep. Waking after a real sleep safely at
## anchor in the morning or day brings the wake-up moment (once a day);
## returns its line, or "".
func begin_sleep() -> void:
	_asleep = true


## True while the captain sleeps (between begin_sleep and end_sleep).
func is_asleep() -> bool:
	return _asleep


func end_sleep(slept_seconds: float) -> String:
	_asleep = false
	if _state == null:
		return ""
	_update_anchor_life(false)
	if not _settled or slept_seconds < AnchorLife.WAKE_MIN_SLEEP_S \
			or not get_day_phase() in [AnchorLife.PHASE_MORNING, AnchorLife.PHASE_DAY]:
		return ""
	var day := AnchorLife.local_day(_state.game_time, _state.vessel_position.x)
	var key := "wake:%d" % day
	if key in _state.anchor.moments:
		return ""
	var text := AnchorLife.pick(AnchorLife.WAKE_LINES, day)
	_record_moment(key, "wake", text)
	return text


## Petting a companion on a settled evening or night: one soft line a stay.
func note_companion_petted(kind: StringName) -> void:
	if _state == null or not _settled or not get_day_phase() in [AnchorLife.PHASE_EVENING, AnchorLife.PHASE_NIGHT]:
		return
	if not "pet" in _state.anchor.moments:
		_record_moment("pet", "pet", String(AnchorLife.PET_LINES.get(kind, "")))
