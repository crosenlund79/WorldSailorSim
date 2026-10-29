class_name DevTools
extends RefCounted
## Development-only test tools: make dangerous weather, wear the boat down
## and run low on stores on demand, so damage, rescue and provisions can be
## verified without waiting for rare weather (the in-game panel is
## DevTestPanel, F10 or the pause menu's "Developer tests").
##
## Everything acts on the real game: weather scenarios are WeatherFixtures in
## the one WeatherModel (they change the wind the boat sails in, the chart,
## warnings and damage exactly like natural weather), and condition, stores
## and time go through GameSession and Simulation.
##
## Enabled only when running the project from the Godot editor binary in a
## debug build (the editor, or `godot --path .`). Exported games never show
## it. Start with `-- --no-dev-tools` to hide it while testing like a player.
##
## Test weather is not part of the game state: it is never saved, and it is
## removed when a game starts, is loaded or ends, so it cannot leak into a
## normal game. "Normal weather" removes it at any time.

const SCENARIO_NONE := &""
const SCENARIO_GALE := &"gale_near"
const SCENARIO_STORM := &"storm_here"
const SCENARIO_SQUALL := &"squall_here"
const SCENARIO_STORM_AHEAD := &"storm_ahead"
const SCENARIO_NAMES := {
	SCENARIO_GALE: "Strong winds: a gale around the boat",
	SCENARIO_STORM: "Severe storm at the boat",
	SCENARIO_SQUALL: "Thunderstorm / severe squalls at the boat",
	SCENARIO_STORM_AHEAD: "Severe storm 20 nm ahead on the course",
}
## Condition presets (percent).
const CONDITION_PRESETS: Array[float] = [100.0, 75.0, 40.0, 15.0, 1.0]

## Tests switch the tools on or off regardless of the build (null = auto).
static var force_enabled: Variant = null
## The active test weather (SCENARIO_*), or SCENARIO_NONE.
static var scenario: StringName = SCENARIO_NONE


static func is_enabled() -> bool:
	if force_enabled != null:
		return bool(force_enabled)
	return OS.is_debug_build() and OS.has_feature("editor") and not "--no-dev-tools" in OS.get_cmdline_user_args()


static func is_scenario_active() -> bool:
	return scenario != SCENARIO_NONE


## Creates test weather `id` around the boat now. Returns "" or the reason
## it could not be made. Repeatable: the same state gives the same weather.
static func activate_scenario(id: StringName) -> String:
	if not is_enabled():
		return "Developer tools are not available in this build."
	if not GameSession.is_active():
		return "Start or load a game first."
	var here := GameSession.get_vessel_position()
	var now := GameSession.get_game_time()
	var event: WeatherEvent
	match id:
		SCENARIO_GALE:
			event = WeatherFixtures.gale("dev_gale", here, 30.0, 38.0, now - 3600.0, 24.0, 90.0, 0.0, 250.0, true)
		SCENARIO_STORM:
			event = WeatherFixtures.gale("dev_storm", here, 30.0, 52.0, now - 3600.0, 12.0, 90.0, 0.0, 240.0, true)
			event.display_name = "Storm"
		SCENARIO_SQUALL:
			event = WeatherFixtures.thunderstorm("dev_squall", here, 12.0, 28.0, 30.0, now - 5400.0, 5.0, 0.0, 0.0)
		SCENARIO_STORM_AHEAD:
			var voyage := GameSession.get_voyage()
			if voyage == null:
				return "Set sail first: the storm is placed on the course ahead."
			var path := voyage.route.path
			var ahead := GeoMath.point_along(path, GeoMath.cumulative_distances(path), voyage.progress_nm + 20.0)
			event = WeatherFixtures.gale("dev_storm_ahead", ahead, 12.0, 52.0, now - 3600.0, 12.0, 90.0, 0.0, 240.0, true)
			event.display_name = "Storm"
		_:
			return "Unknown scenario '%s'." % id
	# Test weather is at full strength at once (no slow build-up).
	event.develop_fraction = minf(event.develop_fraction, 0.5 / (event.lifetime / 3600.0))
	WeatherFixtures.use([event], true)
	scenario = id
	return ""


## Back to the ordinary weather model (removes all test weather).
static func restore_normal_weather() -> void:
	WeatherFixtures.clear()
	scenario = SCENARIO_NONE


## Removes test weather when a game starts, loads or ends (App calls this).
static func on_session_changed() -> void:
	if is_scenario_active():
		restore_normal_weather()


## Sets the boat's condition (1-100 %). Zero is reached only through the real
## weather damage, which then triggers the real rescue.
static func set_condition(percent: float) -> void:
	if is_enabled():
		GameSession.set_condition_for_testing(percent)


## The rescue test: underway, the boat is left at 1 % and a severe storm is
## put on it. At the next evaluation point (within 5 game minutes) the storm's
## real damage sinks the condition to zero and the real rescue runs.
static func prepare_rescue() -> String:
	if not GameSession.is_underway():
		return "Set sail first: a rescue only happens at sea."
	set_condition(1.0)
	return activate_scenario(SCENARIO_STORM)


static func set_provisions(days: float) -> void:
	if is_enabled():
		GameSession.set_provisions_for_testing(days)


# --- I027 playtest: more test shortcuts (existing systems only) -------------------------

static func add_money(euros: int) -> void:
	if is_enabled():
		GameSession.add_funds_for_testing(euros)


static func set_fuel(share: float) -> void:
	if is_enabled():
		GameSession.set_fuel_for_testing(share)


static func add_lures(count: int) -> void:
	if is_enabled():
		GameSession.add_lures_for_testing(count)


## A rare, Gold-sized fish on the line now. Returns "" or why not.
static func rare_bite() -> String:
	return GameSession.force_rare_bite_for_testing() if is_enabled() else "Developer tools are off."


## An animal on this harbour's dock now (moored in a harbour only).
static func dock_animal(kind: StringName) -> String:
	if not is_enabled():
		return "Developer tools are off."
	if not GameSession.is_moored_in_harbour():
		return "Moor in a harbour first: the animal waits on the pontoon."
	GameSession.test_place_dock_animal(kind)
	return ""


## The next dream comes true. Returns "" or why not.
static func fulfil_dream() -> String:
	if not is_enabled():
		return "Developer tools are off."
	return "" if not GameSession.fulfil_next_dream_for_testing().is_empty() else "Every active dream has come true already."


## Lets time pass (the normal simulation) to the next `hour` (local) at this
## harbour: the shops' hours, the café and the evening light can be tried.
static func advance_to_local_hour(hour: float) -> void:
	if not is_enabled():
		return
	var place := GameSession.get_location_id()
	var now := GameSession.get_game_time()
	var local := BusinessHours.local_hours(place, now) if place != &"" else fposmod(now / 3600.0, 24.0)
	var wait := fposmod(hour - local, 24.0)
	advance_hours(wait if wait > 0.01 else 24.0)


## Plans a course to the nearest other harbour (5 nm or more away) for a
## passage test. Returns "" or why not.
static func plan_short_passage() -> String:
	if not is_enabled():
		return "Developer tools are off."
	if GameSession.is_underway():
		return "Already under way."
	var here := GameSession.get_vessel_position()
	var best: PortData = null
	var best_nm := INF
	for port in PortCatalog.get_default().ports_in_rect(Rect2(here - Vector2(2.0, 1.5), Vector2(4.0, 3.0))):
		var nm := here.distance_to(port.get_geo_position()) * 60.0
		if port.id != GameSession.get_location_id() and nm >= 5.0 and nm < best_nm:
			best = port
			best_nm = nm
	if best == null:
		return "No other harbour nearby."
	GameSession.plan_route_to(best.id)
	return "" if GameSession.get_planned_route() != null else "No course could be plotted to %s." % best.display_name


## Lets `hours` of game time pass through the normal simulation.
static func advance_hours(hours: float) -> Simulation.AdvanceResult:
	return Simulation.advance(hours * 3600.0)


## One line about the weather at the boat, for the panel.
static func describe_weather_here() -> String:
	var here := Simulation.get_weather_at_vessel()
	return "Wind %d kn, gusts %d kn  ·  %s  ·  %s" % [roundi(here.speed_kn), roundi(here.gust_kn), here.get_label(),
		here.get_hazard_name()]
