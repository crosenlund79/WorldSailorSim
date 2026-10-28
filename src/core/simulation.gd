extends Node
## The single authoritative simulation timeline.
##
## Every frame Simulation turns real time into game time (base rate × the
## player's time acceleration) and advances the clock and the active voyage
## by exactly that amount. Sleeping advances the same timeline in one call.
## Nothing else in the game advances time or moves the vessel.
##
## Speed varies with wind and propulsion. It is (re)evaluated only at fixed
## evaluation points: an absolute grid every EVALUATION_INTERVAL game seconds,
## every route vertex (the heading changes there), departure and changes of
## course. Between evaluation points the speed is constant, so events
## (arrival, weather warnings, the next vertex or grid point) can be solved
## exactly. Because the evaluation points do not depend on how time is
## chopped into calls, one 8-hour step and 9,600 three-second frames produce
## the same positions, propulsion changes and events. Cost per call grows with
## the number of evaluation points and events, not with frame count.
##
## Weather (Iteration 005a) comes from WeatherModel, the single authoritative
## source: propulsion, warnings, ETA, chart and HUD all read get_weather_at().
## While underway the weather at the boat and along the route ahead is
## assessed at every evaluation point (the same absolute 5-minute grid, plus
## departure), so warnings, sleep interruptions and the exposure record are
## identical at 1×, 20×, in one large step or while sleeping. Weather events
## are pure functions of (seed, time); nothing here changes the weather.
##
## The node is pausable: when the game is paused (menus), time stops.
##
## Long Passage (Iteration 16): on a long voyage the player can let whole hours
## pass per second (passage_rate). It is the same timeline and the same
## advance(), in chunks of one frame each that stop at the first event (as
## sleeping does), so the voyage, weather, stores and wear come out exactly as
## at 1×. It ends by itself when something wants the captain: arrival, a
## weather warning, a bite, the hat, low stores, a boat-care notice.

signal weather_warning(warning: Dictionary)
signal arrived(port_id: StringName)
## Long Passage time stopped by itself (Iteration 16): why, for the player.
signal passage_interrupted(reason: StringName, text: String)
## Long Passage time started (from normal time; not on a change of speed).
signal passage_started(rate: float)
## A vessel nearby is newly on a collision course (I019): see traffic_risks().
signal traffic_alert(info: Dictionary)
## A call on the VHF radio (I019): see VhfRadio.
signal vhf_call(call: Dictionary)

## Real seconds to game seconds at 1× (1 real second = 1 game minute).
const DEFAULT_GAME_SECONDS_PER_REAL_SECOND := 60.0
## Weather warnings look this far ahead along the course (sailing time at the
## estimated speed). Only weather that already exists is foreseen: storms that
## form later cannot be predicted.
const WARNING_HORIZON_HOURS := 6.0
## How far ahead the chart's Weather tab looks along a course.
const DISPLAY_HORIZON_HOURS := 12.0
## Distance step when looking along a course for weather (nm).
const FORECAST_STEP_NM := 2.0
## Thunderstorm cells this close (nm, from their edge) count as "nearby".
const NEARBY_STORM_NM := 15.0
## Wind and propulsion are re-evaluated on this absolute game-time grid.
const EVALUATION_INTERVAL := 300.0
## Step used to estimate remaining sailing time along a route (ETA).
const ESTIMATE_STEP_NM := 5.0
## Floor speed for time estimates, so a momentary calm never gives infinity.
const MIN_ESTIMATE_SPEED_KN := 0.5

const STOP_NONE := &""
const STOP_ARRIVAL := &"arrival"
const STOP_WARNING := &"warning"
## The boat was lost and its crew rescued (the voyage ended mid-advance).
const STOP_RESCUE := &"rescue"
## A fish took the lure, or the anchor needs the captain (Iteration 13).
const STOP_BITE := &"bite"
const STOP_ANCHOR := &"anchor"
## The boat reached an anchorage waypoint (Iteration 18).
const STOP_ANCHORAGE := &"anchorage"
## A vessel nearby is on a collision course (I019).
const STOP_TRAFFIC := &"traffic"
## A vessel nearby asks for assistance on the radio (I019).
const STOP_VHF := &"vhf"

## Traffic (I019, The Captain's Watch): the radar's reach and the levels of
## concern. Risk is judged at the evaluation points (as the weather), from
## the closest point of approach (CPA) and the time to it (TCPA).
const RADAR_RANGE_NM := 12.0
const TRAFFIC_NEARBY_NM := 6.0
const TRAFFIC_CAUTION_CPA_NM := 1.0
const TRAFFIC_CAUTION_TCPA_H := 0.75
const TRAFFIC_DANGER_CPA_NM := 0.3
const TRAFFIC_DANGER_TCPA_H := 0.5
const RISK_NONE := 0
const RISK_NEARBY := 1
const RISK_CAUTION := 2
const RISK_DANGER := 3
## Long Passage speeds: game seconds per real second (1, 4 and 12 hours).
const PASSAGE_RATES: Array[float] = [3600.0, 14400.0, 43200.0]
## Why Long Passage time stopped (besides the STOP_* reasons of advance()).
const STOP_STORES := &"stores"
const STOP_CARE := &"care"
const STOP_HAT := &"hat"
const STOP_ENDED := &"ended"

## Tunable for balancing (and for tests).
var game_seconds_per_real_second := DEFAULT_GAME_SECONDS_PER_REAL_SECOND
## Tests can switch off frame-driven advancing to step time manually.
var auto_advance := true
## Traffic warnings and VHF calls (I019). Always on in the game; the test
## runner turns them off as a fixture (like its calm wind) so voyage-timing
## suites written before them stay exact; their own suites turn them on.
var sea_encounters := true

var _eta_key := ""
var _eta_seconds := 0.0
## While sleeping or working the player is below deck: the hat is not at risk.
var _hat_sheltered := false
## Long Passage time (game seconds per real second), 0 when off. Not saved:
## loading a game or arriving always returns to normal time.
var passage_rate := 0.0
## A stores or boat-care notice arrived during Long Passage time.
var _passage_notice := {}


## Outcome of an advance() call.
class AdvanceResult:
	var elapsed_seconds := 0.0
	## Why advancing stopped early (STOP_ARRIVAL / STOP_WARNING), or STOP_NONE.
	var stopped_by: StringName = &""
	var warnings: Array[Dictionary] = []
	var arrived_at: StringName = &""
	## True when a rescue ended the voyage during this advance.
	var rescued := false
	## The captain's hat was warned about or blew away during this advance.
	var hat_warned := false
	var hat_lost := false
	## A fish bit during this advance (Iteration 13).
	var bite := false
	## The anchor alarm went ("poor" or "dragging"), or "".
	var anchor_alarm := ""
	## The boat reached an anchorage waypoint and waits there (Iteration 18).
	var anchorage := false
	## A vessel newly on a collision course (I019), or {}.
	var traffic := {}
	## A call on the radio (I019), or {}.
	var vhf := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	GameSession.voyage_started.connect(_on_voyage_started)
	GameSession.voyage_course_changed.connect(_on_course_changed)
	GameSession.state_replaced.connect(_on_state_replaced)
	GameSession.vessel_changed.connect(_on_vessel_changed)
	GameSession.rescued.connect(func(_info: Dictionary) -> void: invalidate_estimates())
	GameSession.provisions_warning.connect(func(_level: int, text: String) -> void:
		if passage_rate > 0.0:
			_passage_notice = {"reason": STOP_STORES, "text": text})
	GameSession.notice.connect(func(text: String) -> void:
		if passage_rate > 0.0 and (text.begins_with("Boat care:") or text.begins_with(Loc.t("Boat care:"))):
			_passage_notice = {"reason": STOP_CARE, "text": text})


func _process(delta: float) -> void:
	if auto_advance:
		tick(delta)


## Advances the game for `real_seconds` of real time at the current time
## acceleration (what happens every frame).
##
## While the player has paused the game (GameSession.is_paused()) the clock
## stands still: no time, no movement, no wind change, no companion moves.
## Explicit advances (sleeping) still work and leave the pause as it was.
func tick(real_seconds: float) -> void:
	if not GameSession.is_active() or GameSession.is_paused():
		return
	if passage_rate > 0.0:
		_passage_tick(real_seconds)
		return
	var result := advance(real_seconds * game_seconds_per_real_second * GameSession.get_time_scale())
	# Accelerated time drops back to normal speed when something needs the
	# player's attention, so nothing actionable flies past at 20×.
	if (not result.warnings.is_empty() or result.hat_warned or result.bite or result.anchor_alarm != "" or result.anchorage
			or not result.traffic.is_empty()) and GameSession.get_time_scale() > 1:
		GameSession.set_time_scale(1)


## Starts Long Passage time at `rate` (one of PASSAGE_RATES). Only underway,
## under sail or engine (not at anchor). Returns "" or why not.
func start_passage(rate: float) -> String:
	if not GameSession.is_underway():
		return Loc.t("Long Passage time is for voyages: set sail first.")
	if GameSession.is_anchored():
		return Loc.t("Raise the anchor first: at anchor the voyage is paused.")
	if GameSession.is_holding_at_anchorage():
		return Loc.t("The boat is waiting at the anchorage: drop the anchor, or sail on first.")
	if rate not in PASSAGE_RATES:
		return Loc.t("Unknown passage speed.")
	var was := passage_rate
	passage_rate = rate
	_passage_notice = {}
	if GameSession.is_paused():
		GameSession.set_paused(false)
	if was <= 0.0:
		SessionLog.write("long_passage_start", {"rate_h": rate / 3600.0, "remaining_nm": snappedf(GameSession.get_voyage_remaining_nm(), 0.1)})
		passage_started.emit(rate)
	return ""


## Back to normal time (the player's choice).
func stop_passage() -> void:
	if passage_rate > 0.0:
		passage_rate = 0.0
		SessionLog.write("long_passage_stop", {"remaining_nm": snappedf(GameSession.get_voyage_remaining_nm(), 0.1)})


func is_passage_running() -> bool:
	return passage_rate > 0.0


## One frame of Long Passage time: a chunk of passage_rate × real seconds,
## stopping at the first event. Then back to normal time when something
## needs the captain.
func _passage_tick(real_seconds: float) -> void:
	if not GameSession.is_underway() or GameSession.is_anchored() or GameSession.is_holding_at_anchorage():
		_interrupt_passage(STOP_ENDED, Loc.t("The passage is over."))
		return
	var result := advance(minf(real_seconds, 0.1) * passage_rate, true)
	var reason: StringName = result.stopped_by
	var text := ""
	match reason:
		STOP_ARRIVAL:
			text = Loc.t("Land ho! You have arrived at %s.") % PortCatalog.get_default().get_display_name(result.arrived_at)
		STOP_WARNING:
			text = Loc.t("Weather ahead: %s") % (String(result.warnings[0].get("text", "")) if not result.warnings.is_empty() else "a warning.")
		STOP_BITE:
			text = Loc.t("A fish is on the line!")
		STOP_RESCUE:
			text = Loc.t("The voyage ended with a rescue.")
		STOP_ANCHOR:
			text = Loc.t("The anchor alarm went.")
		STOP_ANCHORAGE:
			text = Loc.t("We've arrived at our anchorage.")
		STOP_TRAFFIC:
			text = describe_traffic(result.traffic)
		STOP_VHF:
			text = Loc.t("A call for assistance on the radio, channel 16.")
	if reason == STOP_NONE and result.hat_warned:
		reason = STOP_HAT
		text = Loc.t("Hold on to your hat: the wind is getting up.")
	if reason == STOP_NONE and not _passage_notice.is_empty():
		reason = _passage_notice.reason
		text = _passage_notice.text
	if reason != STOP_NONE:
		_interrupt_passage(reason, text)


func _interrupt_passage(reason: StringName, text: String) -> void:
	passage_rate = 0.0
	_passage_notice = {}
	GameSession.set_time_scale(1)
	SessionLog.write("long_passage_interrupted", {"reason": String(reason), "remaining_nm": snappedf(GameSession.get_voyage_remaining_nm(), 0.1)})
	passage_interrupted.emit(reason, text)


## Advances the game by `seconds` of game time. With `stop_at_events`, it stops
## at the first arrival or newly due weather warning (used by sleeping).
func advance(seconds: float, stop_at_events := false) -> AdvanceResult:
	var result := AdvanceResult.new()
	if not GameSession.is_active() or seconds <= 0.0:
		return result
	var remaining := seconds
	var guard := 1000000
	# A leftover below a microsecond is floating-point residue, not time: it
	# must not run one more iteration, or an evaluation point exactly at the
	# end would be handled in this call after one big step but in the next
	# call after many small ones (and the results would differ).
	while remaining > 1e-6 and guard > 0:
		guard -= 1
		var time := GameSession.get_game_time()
		if not GameSession.is_underway() or GameSession.is_anchored() or GameSession.is_holding_at_anchorage() or GameSession.is_standing_by():
			# In harbour, at anchor, waiting at an anchorage or standing by for
			# a vessel in need (I019) the boat stays
			# where it is. At anchor the weather and the anchor are checked on
			# the evaluation grid (waiting at an anchorage: the weather); with
			# the line out the bite checks run on their own grid.
			var anchored := GameSession.is_anchored()
			var standing_by := GameSession.is_standing_by()
			var holding := GameSession.is_holding_at_anchorage() or standing_by
			var end := time + remaining
			if standing_by:
				end = minf(end, GameSession.get_standby_until())  # then the voyage goes on, exactly then
			var anchor_grid := _next_grid_time(GameSession.get_anchor_checked_until()) if anchored else INF
			if holding:
				anchor_grid = _next_grid_time(GameSession.get_propulsion().last_evaluation_time)
			end = minf(end, maxf(anchor_grid, time))
			var fish_tick := _next_fish_tick(time, end)
			var step_end := minf(end, fish_tick)
			GameSession.apply_simulation_step(step_end, GameSession.get_voyage_progress_nm())
			_check_hat(time, step_end, -1.0, -1.0, result)
			if standing_by and not GameSession.is_standing_by():
				GameSession.end_standby()
				GameSession.notice.emit(Loc.t("The coastguard's boat has the yacht in tow. You sail on."))
			result.elapsed_seconds += step_end - time
			remaining -= step_end - time
			if fish_tick <= step_end + 1e-6 and GameSession.apply_fish_check(fish_tick):
				result.bite = true
				if stop_at_events:
					result.stopped_by = STOP_BITE
					break
			if holding and step_end >= anchor_grid - 1e-6:
				# Waiting at the anchorage: the weather goes on (on the grid).
				var propulsion := GameSession.get_propulsion()
				propulsion.last_evaluation_time = step_end
				GameSession.set_propulsion(propulsion)
				var holding_warned := _assess_weather(result)
				if result.rescued:
					result.stopped_by = STOP_RESCUE
					break
				if holding_warned and stop_at_events:
					result.stopped_by = STOP_WARNING
					break
			if anchored and step_end >= anchor_grid - 1e-6:
				var warned := _assess_weather(result)
				if result.rescued:
					result.stopped_by = STOP_RESCUE
					break
				var alarm := GameSession.apply_anchor_check(step_end)
				if alarm != "":
					result.anchor_alarm = alarm
					if stop_at_events:
						result.stopped_by = STOP_ANCHOR
						break
				if warned and stop_at_events:
					result.stopped_by = STOP_WARNING
					break
			continue
		var propulsion := GameSession.get_propulsion()
		var next_grid := _next_grid_time(propulsion.last_evaluation_time)
		if not propulsion.initialised or time >= next_grid - 1e-6:
			evaluate_propulsion()
			propulsion = GameSession.get_propulsion()
			next_grid = _next_grid_time(propulsion.last_evaluation_time)
			# The weather is assessed at every grid point (and nowhere else on
			# the way), so the result never depends on how time is chopped.
			var warned := _assess_weather(result)
			if result.rescued:
				# The voyage is over: never continue along it, whatever was asked.
				result.stopped_by = STOP_RESCUE
				break
			if warned and stop_at_events:
				result.stopped_by = STOP_WARNING
				break
			# Traffic on the same grid (I019): a vessel newly on a collision course.
			if _assess_traffic(result) and stop_at_events:
				result.stopped_by = STOP_TRAFFIC
				break
			# And now and then a call on the radio (I019).
			if _assess_vhf(result) and stop_at_events:
				result.stopped_by = STOP_VHF
				break
		var speed := propulsion.speed_kn
		var progress := GameSession.get_voyage_progress_nm()
		var total := GameSession.get_voyage_total_nm()
		var vertex := GameSession.get_voyage_next_vertex_nm()
		var event_at := minf(total, vertex)
		var to_event := (maxf(event_at - progress, 0.0) / speed * 3600.0) if speed > 0.0 else INF
		var to_grid := maxf(next_grid - time, 0.0)
		var fish_tick := _next_fish_tick(time, time + remaining)
		var step := minf(minf(remaining, fish_tick - time), minf(to_event, to_grid))
		var reached_event := to_event <= step
		var new_progress := event_at if reached_event else progress + speed * step / 3600.0
		GameSession.apply_simulation_step(time + step, new_progress)
		_check_hat(time, time + step, progress, new_progress, result)
		result.elapsed_seconds += step
		remaining -= step
		# Trolling: the bite check where the boat is now.
		if fish_tick <= time + step + 1e-6 and GameSession.apply_fish_check(fish_tick):
			result.bite = true
			if stop_at_events and not reached_event:
				result.stopped_by = STOP_BITE
				break
		if not reached_event:
			continue  # a grid point or the end of the requested time
		# An anchorage waypoint (Iteration 18): the boat stops and waits there.
		if GameSession.reach_anchorage_at(event_at):
			result.anchorage = true
			if stop_at_events:
				result.stopped_by = STOP_ANCHORAGE
				break
			continue
		if event_at >= total - 1e-9:
			var destination := GameSession.get_voyage_destination_id()
			GameSession.complete_voyage()
			result.arrived_at = destination
			arrived.emit(destination)
			if stop_at_events:
				result.stopped_by = STOP_ARRIVAL
				break
		else:
			evaluate_propulsion()  # new leg: new heading
	return result


## The next bite check in (t0, t1] with the line out, or INF (Iteration 13):
## one check every FishingCatalog.check_interval_s on an absolute grid, so
## bites do not depend on how time is chopped.
func _next_fish_tick(t0: float, t1: float) -> float:
	if not GameSession.is_line_out():
		return INF
	var interval := FishingCatalog.get_default().check_interval_s
	var tick := (floorf(GameSession.get_fish_checked_until() / interval + 1e-9) + 1.0) * interval
	tick = maxf(tick, t0)
	return tick if tick <= t1 + 1e-6 else INF


## Samples the wind at the vessel and lets the propulsion controller decide
## sail or engine and the speed until the next evaluation point.
## `reset_history` restarts the rolling average from the current heading;
## `reassess` lets clearly good or poor conditions decide at once (see
## PropulsionController).
func evaluate_propulsion(reset_history := false, reassess := false) -> void:
	if not GameSession.is_underway() or GameSession.is_anchored():
		return
	var wind := get_wind_at(GameSession.get_vessel_position())
	var heading := get_current_heading()
	var trim := GameSession.get_sail_trim()
	var factor := SailTrim.factor(trim.auto, trim.value, WindField.relative_angle(heading, wind.from_deg), wind.speed_kn)
	var state := PropulsionController.evaluate(GameSession.get_propulsion(), GameSession.get_vessel_profile(),
		GameSession.get_game_time(), heading, wind, reset_history, reassess, factor)
	GameSession.set_propulsion(state)


## The helm's "Check sail configuration": a fresh assessment of the current
## heading and local wind through the normal controller (same safeguards; no
## timer is reset). Returns {"changed", "before", "after"} (PropulsionStates)
## so the caller can describe the result. Does nothing in port.
func reassess_propulsion() -> Dictionary:
	if not GameSession.is_underway():
		return {}
	var before := GameSession.get_propulsion()
	evaluate_propulsion(false, true)
	var after := GameSession.get_propulsion()
	return {"changed": before.mode != after.mode, "before": before, "after": after}


## The weather (and wind) anywhere at the current game time: the one query
## used by the chart, HUD, sails, sounds and simulation. The returned sample's
## from_deg/speed_kn are the sustained effective wind (what propulsion uses).
func get_wind_at(geo: Vector2) -> WeatherSample:
	return get_weather_at(geo)


## The weather at `geo` at `time` (default: now). With `known_at`, only weather
## events that exist by then are included (a forecast made at that time).
func get_weather_at(geo: Vector2, time := -1.0, known_at := INF) -> WeatherSample:
	var at := GameSession.get_game_time() if time < 0.0 else time
	return WeatherModel.get_default().sample(geo, at, GameSession.get_wind_seed(), known_at)


## The weather at the vessel now.
func get_weather_at_vessel() -> WeatherSample:
	return get_weather_at(GameSession.get_vessel_position())


## Heading (true, degrees) of the route leg the vessel is on.
func get_current_heading() -> float:
	var voyage := GameSession.get_voyage()
	if voyage == null:
		return 0.0
	var i := GeoMath.segment_index_at(voyage.get_cumulative(), voyage.progress_nm)
	return GeoMath.rhumb_bearing(voyage.route.path[i - 1], voyage.route.path[i])


func _next_grid_time(last_evaluation: float) -> float:
	return (floorf(last_evaluation / EVALUATION_INTERVAL) + 1.0) * EVALUATION_INTERVAL


func _on_voyage_started() -> void:
	invalidate_estimates()
	evaluate_propulsion()
	_assess_weather(null)


func _on_course_changed() -> void:
	invalidate_estimates()
	evaluate_propulsion(true, true)


func _on_vessel_changed(_vessel_id: StringName) -> void:
	# Another hull sails differently: cached ETAs no longer hold.
	invalidate_estimates()


func _on_state_replaced() -> void:
	passage_rate = 0.0
	_passage_notice = {}
	invalidate_estimates()
	# Loaded voyages keep their saved controller state; only a migrated (never
	# evaluated) one is evaluated straight away.
	if GameSession.is_underway() and not GameSession.get_propulsion().initialised:
		evaluate_propulsion()


# --- Estimates ----------------------------------------------------------------------

## Estimated sailing time in seconds along `path` from `from_nm` to its end,
## starting at `start_time`. Walks the route in ESTIMATE_STEP_NM steps, using
## the wind expected at each point and time and a simple propulsion rule (sail
## if the potential beats the engine-start threshold, otherwise motor). It is
## an estimate: it ignores the controller's averaging and hysteresis.
func estimate_route_seconds(path: PackedVector2Array, from_nm := 0.0, start_time := -1.0, to_nm := -1.0) -> float:
	if path.size() < 2:
		return 0.0
	var profile := GameSession.get_vessel_profile()
	var cumulative := GeoMath.cumulative_distances(path)
	var total := cumulative[cumulative.size() - 1]
	if to_nm >= 0.0:
		total = minf(total, to_nm)
	var time := GameSession.get_game_time() if start_time < 0.0 else start_time
	var seconds := 0.0
	var d := from_nm
	var model := WeatherModel.get_default()
	var known_at := GameSession.get_game_time()
	while d < total - 1e-6:
		var i := GeoMath.segment_index_at(cumulative, d)
		var heading := GeoMath.rhumb_bearing(path[i - 1], path[i])
		var wind := model.sample(GeoMath.point_along(path, cumulative, d), time + seconds, GameSession.get_wind_seed(), known_at)
		var potential := profile.sail_speed_kn(wind.speed_kn, WindField.relative_angle(heading, wind.from_deg))
		var speed := potential if potential >= profile.engine_start_below_kn else profile.engine_speed_kn
		var ds := minf(ESTIMATE_STEP_NM, total - d)
		seconds += ds / maxf(speed, MIN_ESTIMATE_SPEED_KN) * 3600.0
		d += ds
	return seconds


## Estimated game time of arrival for the active voyage (cached; refreshed as
## the boat moves on or time passes).
func get_eta() -> float:
	if not GameSession.is_underway():
		return 0.0
	var progress := GameSession.get_voyage_progress_nm()
	var key := "%d|%s|%.3f|%d|%d|%d" % [GameSession.get_voyage_revision(), GameSession.get_voyage_destination_id(),
		GameSession.get_voyage_total_nm(), GameSession.get_wind_seed(), floori(progress / 2.0),
		floori(GameSession.get_game_time() / 1800.0)]
	if key != _eta_key:
		_eta_key = key
		var voyage := GameSession.get_voyage()
		_eta_seconds = estimate_route_seconds(voyage.route.path, progress)
	return GameSession.get_game_time() + _eta_seconds


## Forgets cached estimates (after the voyage, a loaded game or the wind changed).
func invalidate_estimates() -> void:
	_eta_key = ""


## Remote work in harbour for `hours` (1-8): the normal simulation advanced
## in one go (food and water are used as always), then GameSession pays for
## every completed hour. Works while paused, which it leaves as it was.
## Returns {"error", "hours", "earned", "elapsed", "stopped_by"}.
func work(hours: int) -> Dictionary:
	if not GameSession.can_work_remotely():
		return {"error": Loc.t("Remote work needs a steady connection: moor in a harbour first."), "hours": 0, "earned": 0, "elapsed": 0.0}
	hours = clampi(hours, GameSession.REMOTE_WORK_MIN_HOURS, GameSession.REMOTE_WORK_MAX_HOURS)
	_hat_sheltered = true
	var result := advance(hours * 3600.0, true)
	_hat_sheltered = false
	var completed := floori(result.elapsed_seconds / 3600.0 + 1e-6)
	var earned := GameSession.pay_remote_work(completed)
	return {"error": "", "hours": completed, "earned": earned, "elapsed": result.elapsed_seconds, "stopped_by": result.stopped_by}


## A Go Ashore outing (Iteration 12): `minutes` of ordinary harbour time
## pass while the captain is ashore (the hat is out of the wind, like below
## deck). Stops early for the same events as sleep.
func spend_time_ashore(minutes: float) -> AdvanceResult:
	_hat_sheltered = true
	var result := advance(maxf(minutes, 0.0) * 60.0, true)
	_hat_sheltered = false
	return result


## Time spent aboard at a task (Iteration 13): cooking below deck
## (`sheltered`: the hat is out of the wind), or waiting at the rod or the
## anchor on deck. Events stop it early like sleep.
func spend_time_aboard(minutes: float, sheltered := true) -> AdvanceResult:
	_hat_sheltered = sheltered
	var result := advance(maxf(minutes, 0.0) * 60.0, true)
	_hat_sheltered = false
	return result


## Sleeps for `hours`: the normal simulation advanced in one go, stopping
## early on arrival or when a weather warning becomes due.
func sleep(hours: float) -> AdvanceResult:
	_hat_sheltered = true
	var result := advance(hours * 3600.0, true)
	_hat_sheltered = false
	return result


# --- Traffic (I019, The Captain's Watch) -------------------------------------------

## The vessels within `range_nm` of the boat now, each with its approach
## (TrafficModel.approach: cpa_nm, tcpa_h, distance_nm) against our own
## course and speed, its "risk" (RISK_*) and its "bearing" (degrees true),
## most urgent first. Moored or at anchor our own speed is zero.
func traffic_risks(range_nm := RADAR_RANGE_NM) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not GameSession.is_active():
		return result
	var here := GameSession.get_vessel_position()
	var moving := GameSession.is_underway() and not GameSession.is_anchored() and not GameSession.is_holding_at_anchorage()
	var own_speed := GameSession.get_propulsion().speed_kn if moving else 0.0
	var own_course := get_current_heading() if moving else 0.0
	for vessel in TrafficModel.get_default().vessels_near(here, GameSession.get_game_time(), GameSession.get_wind_seed(), range_nm):
		var info := TrafficModel.approach(vessel.offset_nm, vessel.course, vessel.speed_kn, own_course, own_speed)
		info.merge(vessel)
		info["bearing"] = fposmod(rad_to_deg(atan2(vessel.offset_nm.x, vessel.offset_nm.y)), 360.0)
		info["risk"] = risk_level(info, moving)
		result.append(info)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.risk > b.risk if a.risk != b.risk else float(a.distance_nm) < float(b.distance_nm))
	return result


## The level of concern for one approach. Only a moving boat can be on a
## collision course; moored or at anchor, ships nearby are just nearby.
static func risk_level(info: Dictionary, moving := true) -> int:
	var tcpa: float = info.tcpa_h
	var cpa: float = info.cpa_nm
	if moving and tcpa > 0.0 and tcpa <= TRAFFIC_DANGER_TCPA_H and cpa < TRAFFIC_DANGER_CPA_NM:
		return RISK_DANGER
	if moving and tcpa > 0.0 and tcpa <= TRAFFIC_CAUTION_TCPA_H and cpa < TRAFFIC_CAUTION_CPA_NM:
		return RISK_CAUTION
	if float(info.distance_nm) <= TRAFFIC_NEARBY_NM:
		return RISK_NEARBY
	return RISK_NONE


## At an evaluation point underway: a vessel newly on a collision course is
## announced once per voyage (its key is kept with the voyage, so a load,
## sleep or Long Passage never announces it twice). True when one was.
func _assess_traffic(result: AdvanceResult) -> bool:
	if not sea_encounters or not GameSession.is_underway() or GameSession.is_anchored() or GameSession.is_holding_at_anchorage():
		return false
	for info in traffic_risks(TRAFFIC_NEARBY_NM * 1.5):
		if info.risk < RISK_DANGER:
			break
		var key := StringName("traffic>%s" % info.id)
		if GameSession.is_weather_warned(key):
			continue
		GameSession.record_weather_warning(key)
		info["text"] = describe_traffic(info)
		if result:
			result.traffic = info
		SessionLog.write("traffic_alert", {"kind": String(info.kind), "cpa_nm": snappedf(info.cpa_nm, 0.01),
			"tcpa_min": roundi(float(info.tcpa_h) * 60.0)})
		traffic_alert.emit(info)
		return true
	return false


## At an evaluation point underway: the radio call of this slot, when its
## time has come (VhfRadio: at most one per slot, once per voyage). True for
## a call for assistance (it wakes the captain and stops Long Passage).
func _assess_vhf(result: AdvanceResult) -> bool:
	var voyage := GameSession.get_voyage()
	if not sea_encounters or voyage == null or GameSession.is_anchored() or GameSession.is_holding_at_anchorage() or GameSession.is_standing_by():
		return false
	if voyage.progress_nm < 3.0 or GameSession.get_voyage_remaining_nm() < 5.0:
		return false  # not right at the harbour mouth
	var now := GameSession.get_game_time()
	var slot := floori(now / VhfRadio.SLOT_SECONDS)
	var key := StringName("vhf>%d" % slot)
	if GameSession.is_weather_warned(key):
		return false
	var hazardous := get_weather_at_vessel().hazard >= WeatherModel.HAZARD_CAUTION
	var call := VhfRadio.call_for_slot(voyage.departed_at, slot, GameSession.get_wind_seed(), hazardous)
	if call.is_empty() or now < float(call.due):
		return false
	GameSession.record_weather_warning(key)
	call["heard_at"] = now
	if result:
		result.vhf = call
	SessionLog.write("vhf_call", {"kind": String(call.kind), "id": String(call.id)})
	vhf_call.emit(call)
	return call.kind == VhfRadio.KIND_ASSIST


## "Collision risk: the cargo ship Nordlys will pass 0.2 nm off in about
## 12 min, from the NE. ..."
static func describe_traffic(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	if float(info.cpa_nm) < 0.1:
		return Loc.t("Collision risk: the %s %s will pass very close in about %d min, from the %s. Keep a sharp lookout and give way if needed.") % [
			TrafficModel.kind_name(info.kind).to_lower(), info.name, maxi(roundi(float(info.tcpa_h) * 60.0), 1),
			WindField.compass_name(float(info.bearing))]
	return Loc.format("Collision risk: the %s %s will pass %.1f nm off in about %d min, from the %s. Keep a sharp lookout and give way if needed.", [
		TrafficModel.kind_name(info.kind).to_lower(), info.name, float(info.cpa_nm), maxi(roundi(float(info.tcpa_h) * 60.0), 1),
		WindField.compass_name(float(info.bearing))])


# --- Captain's hat ------------------------------------------------------------------

## True when the worn hat is out in the wind (on deck, not sleeping or working).
func is_hat_at_risk() -> bool:
	return GameSession.is_hat_exposed() and not _hat_sheltered


## Hat checks for the game time (t0, t1] just simulated: one check on every
## absolute HatConfig.check_interval_s grid point. While the hat is worn on
## deck each check samples the WeatherModel at the boat's position at that
## moment (underway interpolated along the course between `p0` and `p1`, the
## progress at t0 and t1, which the constant speed between evaluation points
## makes exact). Otherwise the hat just recovers. The grid and the positions
## do not depend on how time is chopped, so the outcome is the same at 1x,
## 20x, in one long step and across save/load.
func _check_hat(t0: float, t1: float, p0: float, p1: float, result: AdvanceResult) -> void:
	var config := HatConfig.get_default()
	var interval := config.check_interval_s
	var tick := (floorf(GameSession.get_hat_checked_until() / interval + 1e-9) + 1.0) * interval
	if tick > t1 + 1e-6:
		return
	if not is_hat_at_risk():
		var ticks := floori((t1 + 1e-6 - tick) / interval) + 1
		GameSession.recover_hat(ticks, tick + (ticks - 1) * interval)
		return
	var model := WeatherModel.get_default()
	var underway := p0 >= 0.0 and GameSession.is_underway()
	while tick <= t1 + 1e-6:
		if not is_hat_at_risk():
			var rest := floori((t1 + 1e-6 - tick) / interval) + 1
			GameSession.recover_hat(rest, tick + (rest - 1) * interval)
			return
		var position := GameSession.get_vessel_position()
		if underway and t1 > t0:
			var fraction := clampf((tick - t0) / (t1 - t0), 0.0, 1.0)
			position = GameSession.get_voyage_position_at(lerpf(p0, p1, fraction))
		var sample := model.sample(position, tick, GameSession.get_wind_seed())
		var rate := config.strain_per_minute(sample.speed_kn, sample.gust_kn, not GameSession.is_underway())
		match GameSession.apply_hat_check(tick, rate, sample, position):
			&"warned":
				if result:
					result.hat_warned = true
			&"lost":
				if result:
					result.hat_lost = true
		tick += interval


# --- Weather along the course and warnings ------------------------------------------

## Hazardous weather (CAUTION or worse) along `path` from `from_nm`, within
## `horizon_hours` of sailing at the estimated speed: one entry per event (or
## per strong background wind), the first place it is met, with its worst
## level on the way: [{"key", "event_id", "label", "hazard", "hours",
## "distance_nm", "speed_kn", "gust_kn", "sample"}], nearest first.
## A forecast made now: only weather that already exists is foreseen. Times
## are estimates (the same simple propulsion rule as the ETA).
func route_hazards(path: PackedVector2Array, from_nm := 0.0, horizon_hours := DISPLAY_HORIZON_HOURS) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if path.size() < 2:
		return found
	var profile := GameSession.get_vessel_profile()
	var cumulative := GeoMath.cumulative_distances(path)
	var total := cumulative[cumulative.size() - 1]
	var now := GameSession.get_game_time()
	var model := WeatherModel.get_default()
	var seed := GameSession.get_wind_seed()
	var seconds := 0.0
	var d := from_nm
	var by_key := {}
	while seconds <= horizon_hours * 3600.0:
		var geo := GeoMath.point_along(path, cumulative, d)
		# The quick sample (the same wind, gust and hazard as sample()); the
		# full sample only where there is a hazard to keep (Turbocharge).
		var quick := model.sample_hazard(geo, now + seconds, seed, now)
		if int(quick[3]) >= WeatherModel.HAZARD_CAUTION:
			var sample := model.sample(geo, now + seconds, seed, now)
			var key := String(sample.event_id) if not sample.event_id.is_empty() else "wind"
			if not by_key.has(key):
				by_key[key] = {"key": key, "event_id": sample.event_id, "label": sample.get_label(), "hazard": sample.hazard,
					"hours": seconds / 3600.0, "distance_nm": d - from_nm, "speed_kn": sample.speed_kn, "gust_kn": sample.gust_kn,
					"sample": sample}
				found.append(by_key[key])
			elif sample.hazard > by_key[key].hazard:
				by_key[key].hazard = sample.hazard
				by_key[key].label = sample.get_label()
				by_key[key].speed_kn = maxf(by_key[key].speed_kn, sample.speed_kn)
				by_key[key].gust_kn = maxf(by_key[key].gust_kn, sample.gust_kn)
		if d >= total - 1e-6:
			break
		var i := GeoMath.segment_index_at(cumulative, d)
		var heading := GeoMath.rhumb_bearing(path[i - 1], path[i])
		var potential := profile.sail_speed_kn(quick[1], WindField.relative_angle(heading, quick[0]))
		var speed := potential if potential >= profile.engine_start_below_kn else profile.engine_speed_kn
		var ds := minf(FORECAST_STEP_NM, total - d)
		seconds += ds / maxf(speed, MIN_ESTIMATE_SPEED_KN) * 3600.0
		d += ds
	return found


## Hazards ahead on the active course (the Weather tab and HUD), nearest first.
func get_hazards_ahead(horizon_hours := DISPLAY_HORIZON_HOURS) -> Array[Dictionary]:
	if not GameSession.is_underway():
		var empty: Array[Dictionary] = []
		return empty
	var voyage := GameSession.get_voyage()
	return route_hazards(voyage.route.path, voyage.progress_nm, horizon_hours)


## Thunderstorm cells near (within NEARBY_STORM_NM of their edge) `geo` now.
func get_storms_near(geo: Vector2) -> Array[WeatherEvent]:
	var near: Array[WeatherEvent] = []
	var now := GameSession.get_game_time()
	for event in WeatherModel.get_default().events_of_kind(now, WeatherEvent.KIND_THUNDERSTORM, GameSession.get_wind_seed()):
		var distance := event.offset_nm(geo, now).length()
		if distance - event.outline_radius(atan2(event.offset_nm(geo, now).x, event.offset_nm(geo, now).y), now) <= NEARBY_STORM_NM \
				and event.life_factor(now) > 0.3:
			near.append(event)
	return near


## Assesses the weather at the boat and ahead (at evaluation points while
## underway): records the exposure and gives at most one new warning. Returns
## true when a warning was given.
func _assess_weather(result: AdvanceResult) -> bool:
	if not GameSession.is_underway():
		return false
	# Damage for the time since it was last applied, sampled on the fixed
	# WeatherDamage grid (so gust bursts between evaluation points count, and
	# no stretch of time is counted twice).
	var now := GameSession.get_game_time()
	# The weather here is recorded first, so a voyage lost in it still has
	# the storm in its log record.
	var here := get_weather_at_vessel()
	GameSession.update_weather_exposure(here)
	var damage := WeatherDamage.damage_between(GameSession.get_damage_applied_until(), now,
		GameSession.get_vessel_position(), GameSession.get_wind_seed(), GameSession.get_vessel_profile().weather_damage_factor) \
		* GameSession.get_anchor_damage_factor() * Difficulty.factor("weather_damage")
	if GameSession.apply_weather_damage(damage, now):
		if result:
			result.rescued = true
		return false
	var warning := _local_warning(here)
	if warning.is_empty():
		warning = _nearby_storm_warning()
	if warning.is_empty():
		warning = _route_warning()
	if warning.is_empty():
		return false
	GameSession.record_weather_warning(StringName(warning.key))
	if result:
		result.warnings.append(warning)
	weather_warning.emit(warning)
	return true


## True when this event (or the background wind) was already announced at
## `level` or worse on this voyage.
static func _is_warned(event_key: String, level: int) -> bool:
	for l in range(level, WeatherModel.HAZARD_SEVERE + 1):
		if GameSession.is_weather_warned(StringName("%s>%d" % [event_key, l])):
			return true
	return false


static func _event_key(sample: WeatherSample) -> String:
	return String(sample.event_id) if not sample.event_id.is_empty() else "wind"


func _local_warning(here: WeatherSample) -> Dictionary:
	if here.hazard < WeatherModel.HAZARD_CAUTION or _is_warned(_event_key(here), here.hazard):
		return {}
	var what := here.get_label()
	var text := ""
	match here.hazard:
		WeatherModel.HAZARD_CAUTION:
			text = Loc.t("%s at the boat: wind %s, gusts %d kn.") % [what, _wind_text(here), roundi(here.gust_kn)]
		WeatherModel.HAZARD_DANGEROUS:
			text = Loc.t("Dangerous conditions at the boat (%s): wind %s, gusts %d kn.") % [what.to_lower(), _wind_text(here), roundi(here.gust_kn)]
		_:
			text = Loc.t("Severe conditions at the boat (%s): wind %s, gusts %d kn.") % [what.to_lower(), _wind_text(here), roundi(here.gust_kn)]
	if here.classification == WeatherModel.CLASS_THUNDER_RISK:
		text = Loc.t("Thunderstorm risk at the boat: thunderstorms may develop nearby.")
	return _warning(here, "%s>%d" % [_event_key(here), here.hazard], text, 0.0, 0.0)


func _nearby_storm_warning() -> Dictionary:
	var vessel := GameSession.get_vessel_position()
	for storm in get_storms_near(vessel):
		var key := "%s>near" % storm.id
		if GameSession.is_weather_warned(StringName(key)) or _is_warned(String(storm.id), WeatherModel.HAZARD_CAUTION):
			continue
		var offset := storm.offset_nm(vessel, GameSession.get_game_time())
		var bearing := WindField.compass_name(rad_to_deg(atan2(-offset.x, -offset.y)))
		var severe := storm.peak_kn + storm.gust_kn >= WeatherModel.SEVERE_STORM_KN
		var text := Loc.t("%s %d nm to the %s, moving %s.") % [Loc.t("Severe squalls nearby:") if severe else Loc.t("Thunderstorm nearby:"),
			roundi(maxf(offset.length() - storm.radius_nm, 0.0)), bearing, WindField.compass_name(storm.heading_at(GameSession.get_game_time()))]
		var sample := get_weather_at(storm.center_at(GameSession.get_game_time()))
		return _warning(sample, key, text, 0.0, offset.length())
	return {}


func _route_warning() -> Dictionary:
	for hazard in get_hazards_ahead(GameSession.get_warning_horizon_hours()):
		var sample: WeatherSample = hazard.sample
		if _is_warned(hazard.key, hazard.hazard):
			continue
		var expected := expected_strength(hazard)
		var text := Loc.t("%s ahead on your route %s: wind up to %d kn, gusts %d kn.") % [hazard.label, describe_when(hazard.hours),
			roundi(expected[0]), roundi(expected[1])]
		if sample.classification == WeatherModel.CLASS_THUNDER_RISK:
			text = Loc.t("Thunderstorm risk ahead on your route %s.") % describe_when(hazard.hours)
		var warning := _warning(sample, "%s>%d" % [hazard.key, hazard.hazard], text, hazard.hours, hazard.distance_nm)
		warning.hazard = hazard.hazard
		return warning
	return {}


## The strongest wind and gusts a hazard ahead may bring: what the forecast
## met on the course, or the responsible event's core strength if more.
func expected_strength(hazard: Dictionary) -> Array:
	var sustained: float = hazard.speed_kn
	var gust: float = hazard.gust_kn
	var event := WeatherModel.get_default().find_event(hazard.event_id, GameSession.get_game_time(), GameSession.get_wind_seed()) \
		if not String(hazard.event_id).is_empty() else null
	if event:
		var sample: WeatherSample = hazard.sample
		var core := WeatherModel.event_strength(event, GameSession.get_game_time() + hazard.hours * 3600.0, sample.background_kn)
		sustained = maxf(sustained, core[0])
		gust = maxf(gust, core[1])
	return [sustained, gust]


func _warning(sample: WeatherSample, key: String, text: String, hours: float, distance_nm: float) -> Dictionary:
	return {"key": key, "text": text, "title": sample.get_label(), "hazard": sample.hazard, "hours": hours,
		"distance_nm": distance_nm, "event_id": sample.event_id, "classification": sample.classification,
		"event_kind": sample.event_kind, "sample": sample}


static func _wind_text(sample: WeatherSample) -> String:
	return Loc.t("%s %d kn") % [WindField.compass_name(sample.from_deg), roundi(sample.speed_kn)]


## "now", "within the hour", "in about 2–3 h": forecast times are estimates,
## shown as a range rather than to the minute.
static func describe_when(hours: float) -> String:
	if hours < 0.25:
		return "now"
	if hours < 1.0:
		return Loc.t("within the hour")
	return Loc.t("in about %d–%d h") % [floori(hours), floori(hours) + 1]


## "4 h 50 min", "35 min", "2 d 3 h".
static func format_duration(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	if minutes < 60:
		return Loc.t("%d min") % minutes
	var hours := minutes / 60
	if hours < 48:
		return Loc.t("%d h %02d min") % [hours, minutes % 60] if minutes % 60 else Loc.t("%d h") % hours
	return Loc.t("%d d %d h") % [hours / 24, hours % 24]


## "Fri 1 May 2026, 08:00 UTC" (Danish: "fre. 1. maj 2026, 08:00 UTC").
static func format_game_time(unix_time: float, with_zone := true) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return Loc.t("%s %d %s %d, %02d:%02d%s", "date") % [Loc.weekday_short(d.weekday), d.day, Loc.month_short(d.month), d.year, d.hour,
		d.minute, " UTC" if with_zone else ""]
