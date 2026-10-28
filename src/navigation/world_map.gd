class_name WorldMap
extends Node2D
## The chart screen: shows Europe, the vessel's actual position, the active or
## planned course and weather areas, and lets the player plan and edit a course.
##
## Editing happens on a *draft*. The committed course (GameSession's planned
## route in port, or the active voyage at sea) is never touched until the
## player presses Apply, and only a fully valid draft can be applied. Discard
## returns to the committed course. All routes come from SeaRouter, so the
## course shown is exactly the course the vessel will sail.
##
## Sidebar (I003b UI hotfix): a fixed-size panel in three parts.
## - Header (always visible): title, voyage status, progress, distance and ETA.
##   One line each, cut with an ellipsis (full text in the tooltip), so live
##   values never change its height.
## - Tabs (fill the rest): Course (destination, course, waypoint tools),
##   Weather (wind at the boat, weather along the course) and Details
##   (position, projection, help). Each tab scrolls on its own, with a reserved
##   scroll-bar gutter, so long text never resizes or pushes anything.
## - Footer (always visible): Apply/Change course and Discard, Set sail and
##   Sleep, Back. Their positions never change; unusable ones are disabled.
## Time controls are not here: the HUD's shared clock bar is shown on the chart.

signal close_requested
signal depart_requested
signal sleep_requested
## Dreamer's Map: the player wants to plan the voyage to this harbour at the
## chart table.
signal plan_requested(port_id: StringName)

## Iteration 17: the three navigation views share one chart, router,
## catalogue, boat and voyage; this scene is two of them.
## - MODE_STATION: the navigation station's working chart. Opens on the
##   region around the boat (about STATION_SPAN_NM across, latitude-aware),
##   shows the course, its next turn and the weather, and plans courses to
##   anywhere in the world (zoom out or search).
## - MODE_DREAM: the cabin's Dreamer's Map. The whole world to explore, the
##   harbours, their stories and which were visited, and "Imagine this
##   voyage". No wind, no weather areas, no course editing: nothing here
##   samples the weather or changes the game.
const MODE_STATION := 0
const MODE_DREAM := 1
## The working chart's opening view: this many nautical miles across the
## shorter side of the chart area.
const STATION_SPAN_NM := 400.0
var mode := MODE_STATION

## Width of the side panel plus its margin, in unscaled UI pixels.
const SIDE_PANEL_WIDTH := 544.0
## How far (nm) a waypoint let go on land may move to reach open water.
const WAYPOINT_SNAP_NM := 15.0
## Minimum real time between route recalculations while dragging a waypoint.
const DRAG_RECALC_INTERVAL := 0.1
const LIVE_REFRESH_INTERVAL := 0.25
const TAB_COURSE := 0
const TAB_WEATHER := 1
const TAB_DETAILS := 2

var _selected_port_id: StringName
var _draft_destination: StringName
var _draft_waypoints: Array[Vector2] = []
## Which draft waypoints are anchorages (Iteration 18), parallel to the above.
var _draft_anchorages: Array[bool] = []
## A suitable spot offered for an anchorage that is not (Vector2.INF: none),
## and for which waypoint.
var _anchorage_suggestion := Vector2.INF
var _anchorage_suggestion_for := -1
var _anchorage_button: Button
var _suggestion_button: Button
## Legs of the draft as [{"path", "ok"}] and its validated route (or null).
var _draft_legs: Array[Dictionary] = []
var _draft_route: PlannedRoute
var _draft_error := ""
var _draft_dirty := false
var _selected_waypoint := -1
var _dragging_waypoint := -1
var _pending_drag_geo := Vector2.INF
var _drag_timer := 0.0
var _live_timer := 0.0
var _feedback := ""
## A one-off hint shown under the course status (Iteration 18).
var _feedback_hint := ""
## Estimated sailing time of the draft course (seconds), refreshed when it changes.
var _draft_estimate_seconds := 0.0
var _hazards_key := ""
var _hazards: Array[Dictionary] = []

@onready var _map: MapView = $MapView
@onready var _status: Label = %StatusLabel
@onready var _position: Label = %PositionLabel
@onready var _tabs: TabContainer = %Tabs
@onready var _wind_here: Label = %WindHereLabel
@onready var _propulsion: Label = %PropulsionLabel
@onready var _voyage_bar: ProgressBar = %VoyageProgress
@onready var _voyage_label: Label = %VoyageLabel
@onready var _selection_title: Label = %SelectionTitle
@onready var _selection_details: Label = %SelectionDetails
@onready var _plot_button: Button = %PlotButton
@onready var _course_label: Label = %CourseLabel
@onready var _course_status: Label = %CourseStatus
@onready var _readiness_label: Label = %ReadinessLabel
@onready var _apply_button: Button = %ApplyButton
@onready var _discard_button: Button = %DiscardButton
@onready var _remove_button: Button = %RemoveWaypointButton
@onready var _clear_button: Button = %ClearButton
@onready var _sail_button: Button = %SetSailButton
@onready var _weather_label: Label = %WeatherLabel
@onready var _cursor_label: Label = %CursorLabel
@onready var _wind_toggle: CheckButton = %WindToggle
@onready var _wind_legend: Control = %WindLegend
@onready var _edit_help: Control = $Ui/Root/SidePanel/VBox/Tabs/Course/VBox/EditHelp

## Whether the wind overlay is shown (kept while the game runs).
static var wind_shown := true
## Results listed by the harbour search.
const SEARCH_RESULTS := 6

var _search: LineEdit
var _search_results: VBoxContainer


func _ready() -> void:
	_fit_map_to_free_area(SettingsManager.get_ui_scale())
	SettingsManager.ui_scale_changed.connect(_fit_map_to_free_area)
	_map.port_clicked.connect(select_port)
	_map.map_clicked.connect(func(_geo: Vector2) -> void: _select_waypoint(-1))
	_map.route_pressed.connect(_on_route_pressed)
	_map.waypoint_pressed.connect(_select_waypoint)
	_map.waypoint_dragged.connect(_on_waypoint_dragged)
	_map.waypoint_released.connect(_on_waypoint_released)
	_map.waypoint_remove_requested.connect(remove_waypoint)
	_map.cursor_moved.connect(_on_cursor_moved)
	_plot_button.pressed.connect(func() -> void: plot_course_to(_selected_port_id))
	_apply_button.pressed.connect(apply_course)
	_discard_button.pressed.connect(discard_changes)
	_remove_button.pressed.connect(func() -> void: remove_waypoint(_selected_waypoint))
	_build_anchorage_buttons()
	_clear_button.pressed.connect(clear_course)
	_sail_button.pressed.connect(depart_requested.emit)
	%BackButton.pressed.connect(close_requested.emit)
	%SleepButton.pressed.connect(sleep_requested.emit)
	_tabs.set_tab_title(TAB_COURSE, "Course")
	_tabs.set_tab_title(TAB_WEATHER, "Weather")
	_tabs.set_tab_title(TAB_DETAILS, "Details")
	for tab in _tabs.get_children():
		(tab as ScrollContainer).follow_focus = true
	%ZoomInButton.pressed.connect(_map.zoom_by.bind(MapView.ZOOM_STEP))
	%ZoomOutButton.pressed.connect(_map.zoom_by.bind(1.0 / MapView.ZOOM_STEP))
	%ResetViewButton.pressed.connect(_map.reset_view)
	%CenterBoatButton.pressed.connect(center_on_vessel)
	_build_wind_legend()
	_build_wind_time_controls()
	_build_search()
	var legend := WeatherLegend.new()
	legend.name = "WeatherLegend"
	_weather_label.get_parent().add_child(legend)
	_wind_toggle.button_pressed = wind_shown
	_wind_toggle.toggled.connect(set_wind_shown)
	set_wind_shown(wind_shown)
	_build_anchorage_controls()
	# Captain's Chartroom: small, quiet map controls.
	for control in %ZoomInButton.get_parent().get_children():
		if control is CheckButton:
			control.theme_type_variation = &"MapToggle"
		elif control is Button:
			control.theme_type_variation = &"MapButton"
	GameSession.route_changed.connect(_on_committed_changed)
	GameSession.voyage_started.connect(_on_committed_changed)
	GameSession.voyage_course_changed.connect(_on_committed_changed)
	GameSession.voyage_arrived.connect(_on_committed_changed)
	_load_committed()
	_selected_port_id = _draft_destination
	if mode == MODE_DREAM:
		_setup_dream()
	_refresh()
	center_on_vessel()
	if mode == MODE_STATION:
		_map.center_on_geo(GameSession.get_vessel_position(), get_station_zoom())
	else:
		_map.reset_view()
		_map.camera.position.x = _map.projection.geo_to_map(GameSession.get_vessel_position()).x
		_map._clamp_camera()


## The working chart's opening zoom: STATION_SPAN_NM across the shorter side
## of the free chart area at the boat's latitude (Mercator stretches a
## nautical mile by 1 / cos(latitude)).
func get_station_zoom() -> float:
	var free := _map._free_view_size()
	var lat := clampf(GameSession.get_vessel_position().y, -75.0, 75.0)
	var units := STATION_SPAN_NM / 60.0 * _map.units_per_degree / cos(deg_to_rad(lat))
	return minf(free.x, free.y) / units


func _process(delta: float) -> void:
	_update_anchorage_info(delta)
	if _dragging_waypoint >= 0 and _pending_drag_geo != Vector2.INF:
		_drag_timer -= delta
		if _drag_timer <= 0.0:
			_move_waypoint(_dragging_waypoint, _pending_drag_geo)
			_pending_drag_geo = Vector2.INF
			_drag_timer = DRAG_RECALC_INTERVAL
	_live_timer -= delta
	if _live_timer <= 0.0:
		_live_timer = LIVE_REFRESH_INTERVAL
		# The vessel keeps sailing while the chart is open.
		if GameSession.is_underway() and not _draft_dirty and _dragging_waypoint < 0:
			_load_committed()
		_refresh()
		_update_wind_time()  # the NOW clock moves on


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode in [KEY_DELETE, KEY_BACKSPACE] and _selected_waypoint >= 0:
		remove_waypoint(_selected_waypoint)
		get_viewport().set_input_as_handled()
	elif key and key.pressed and not key.echo and key.keycode == KEY_M and _selected_waypoint >= 0 and mode == MODE_STATION:
		toggle_anchorage(_selected_waypoint)
		get_viewport().set_input_as_handled()


## Called by the application when Esc is pressed on this screen.
func handle_back() -> void:
	close_requested.emit()


func has_unapplied_changes() -> bool:
	return _draft_dirty


# --- Planning actions (also used by tests) ------------------------------------------------

func select_port(port_id: StringName) -> void:
	_selected_port_id = port_id
	if is_node_ready():
		show_tab(TAB_COURSE)  # what the player clicked is shown there
	_refresh()


## The harbour search on the Course tab: every harbour can be found by name or
## country, also when its marker is hidden at the current zoom.
func _build_search() -> void:
	var header := %SelectionTitle.get_parent().get_node("DestinationHeader") as Label
	_search = LineEdit.new()
	_search.name = "HarbourSearch"
	_search.placeholder_text = "Find a harbour…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(search_harbours)
	_search.text_submitted.connect(func(_text: String) -> void:
		if _search_results.get_child_count() > 0:
			(_search_results.get_child(0) as Button).pressed.emit())
	header.add_sibling(_search)
	_search_results = VBoxContainer.new()
	_search_results.name = "SearchResults"
	_search_results.add_theme_constant_override("separation", 2)
	_search.add_sibling(_search_results)


## Lists the harbours matching `text` (a button each).
func search_harbours(text: String) -> void:
	if _search.text != text:
		_search.text = text
	for child in _search_results.get_children():
		_search_results.remove_child(child)
		child.queue_free()
	for port in PortCatalog.get_default().search(text, SEARCH_RESULTS):
		var button := Button.new()
		button.name = "Result_%s" % port.id
		button.text = "%s, %s" % [port.display_name, port.country]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.pressed.connect(_choose_search_result.bind(port.id))
		_search_results.add_child(button)


func get_search_result_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for child in _search_results.get_children():
		if not child.is_queued_for_deletion():
			ids.append(StringName(String(child.name).trim_prefix("Result_")))
	return ids


## Selects a harbour found by the search and shows it on the chart, zoomed in
## far enough for its marker.
func _choose_search_result(port_id: StringName) -> void:
	var port := PortCatalog.get_default().get_port(port_id)
	search_harbours("")
	select_port(port_id)
	var needed := MapView.PORT_MARKER_PX_PER_DEGREE[port.importance] * 1.3 / _map.units_per_degree
	_map.center_on_geo(port.get_geo_position(), maxf(_map.get_zoom(), needed))


func get_selected_port_id() -> StringName:
	return _selected_port_id


## Starts a new draft: an automatic sea route from the vessel to the port.
func plot_course_to(port_id: StringName) -> void:
	if port_id.is_empty():
		return
	_draft_destination = port_id
	_draft_waypoints.clear()
	_draft_anchorages.clear()
	_clear_suggestion()
	_selected_waypoint = -1
	_draft_dirty = true
	_feedback = ""
	_recalculate()


## Inserts a waypoint into leg `leg_index` (0 = before the first waypoint).
func insert_waypoint(leg_index: int, geo: Vector2) -> int:
	var index := clampi(leg_index, 0, _draft_waypoints.size())
	_draft_waypoints.insert(index, geo)
	_draft_anchorages.insert(index, false)
	_clear_suggestion()
	_selected_waypoint = index
	if GameSession.take_hint("anchorage"):
		_feedback_hint = ANCHORAGE_HINT
	_draft_dirty = true
	_recalculate()
	return index


func remove_waypoint(index: int) -> void:
	if index < 0 or index >= _draft_waypoints.size():
		return
	_draft_waypoints.remove_at(index)
	_draft_anchorages.remove_at(index)
	_clear_suggestion()
	_selected_waypoint = -1
	_draft_dirty = true
	_recalculate()


## Moves a waypoint and recalculates the legs on either side of it.
func move_waypoint(index: int, geo: Vector2) -> void:
	_move_waypoint(index, geo)


## Makes the draft the committed course. In port it becomes the planned
## route; at sea the voyage changes course from the vessel's current position.
func apply_course() -> String:
	if _draft_route == null:
		return _set_feedback(Loc.t("This course cannot be used: %s") % _draft_error)
	var error := ""
	for i in _draft_waypoints.size():
		if _draft_anchorages[i] and not _spot(_draft_waypoints[i]).ok:
			return _set_feedback(Loc.t("Anchorage %d cannot be used: %s Move it, or unmark it.") % [i + 1, _spot(_draft_waypoints[i]).reason])
	if GameSession.is_underway():
		error = GameSession.change_course(_draft_destination, _draft_waypoints, _draft_anchorages)
	else:
		error = GameSession.set_planned_route(_draft_route)
	if not error.is_empty():
		return _set_feedback(Loc.t("Course not changed: %s Your current course is unchanged.") % error)
	_draft_dirty = false
	_load_committed()
	_set_feedback(Loc.t("Course set for %s.") % PortCatalog.get_default().get_display_name(_draft_destination))
	return ""


func discard_changes() -> void:
	_draft_dirty = false
	_load_committed()
	_set_feedback(Loc.t("Changes discarded."))


func clear_course() -> void:
	if GameSession.is_underway():
		return
	GameSession.clear_planned_route()
	_draft_dirty = false
	_load_committed()


func center_on_vessel() -> void:
	_map.center_on_geo(GameSession.get_vessel_position(), maxf(_map.get_zoom(), 0.6))


func get_map_view() -> MapView:
	return _map


## The next turn of the course being sailed: {"geo", "nm" (to go), "course"
## (now, degrees), "next_course" (after it, or -1 at the destination)}, or {}
## in harbour. The same voyage the boat sails, the HUD and the chartplotter use.
static func get_next_turn() -> Dictionary:
	var voyage := GameSession.get_voyage()
	if voyage == null or voyage.route == null or voyage.route.path.size() < 2:
		return {}
	var path := voyage.route.path
	var cumulative := voyage.get_cumulative()
	var i := GeoMath.segment_index_at(cumulative, voyage.progress_nm)
	var next_course := -1.0
	if i + 1 < path.size():
		next_course = GeoMath.rhumb_bearing(path[i], path[i + 1])
	return {"geo": path[i], "nm": maxf(cumulative[i] - voyage.progress_nm, 0.0),
		"course": GeoMath.rhumb_bearing(path[i - 1], path[i]), "next_course": next_course}


# --- Dreamer's Map (MODE_DREAM) ---------------------------------------------------------------

var _daydream_label: Label
var _imagine_button: Button
var _plan_here_button: Button
var _daydream := {}
var _daydream_port := &""


## A node of the side panel by name (those without a unique name).
func _ui(node_name: String) -> Node:
	return $Ui/Root/SidePanel.find_child(node_name, true, false)


func _setup_dream() -> void:
	_map.set_dream_style(true)
	_map.show_weather = false
	_map.wind_layer.set_shown(false)
	_wind_toggle.visible = false
	_wind_legend.visible = false
	if _anchor_toggle:
		_anchor_toggle.visible = false
		_anchor_legend.visible = false
		_map.anchorage_layer.set_shown(false)
	(_ui("Title") as Label).text = "Dreamer's Map"
	%BackButton.text = "Back to the cabin (Esc)"
	_tabs.set_tab_hidden(TAB_WEATHER, true)
	_tabs.set_tab_title(TAB_COURSE, "Harbours")
	for node in [_plot_button, _course_label, _course_status, _readiness_label, _ui("CourseHeader"), _ui("Sep1"),
			_ui("WaypointButtons"), _ui("EditHelp"), _ui("CourseButtons"), _ui("ActionRow"), _voyage_bar]:
		(node as CanvasItem).visible = false
	(_ui("DestinationHeader") as Label).text = "Where shall I dream of?"
	_imagine_button = Button.new()
	_imagine_button.name = "ImagineButton"
	_imagine_button.text = "Imagine this voyage"
	_imagine_button.pressed.connect(func() -> void: imagine_voyage(_selected_port_id))
	_plot_button.add_sibling(_imagine_button)
	_daydream_label = Label.new()
	_daydream_label.name = "DaydreamLabel"
	_daydream_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_daydream_label.custom_minimum_size = Vector2(440, 0)
	_daydream_label.add_theme_font_size_override(&"font_size", 19)
	_imagine_button.add_sibling(_daydream_label)
	_plan_here_button = Button.new()
	_plan_here_button.name = "PlanAtChartTableButton"
	_plan_here_button.text = "Plan it at the chart table"
	_plan_here_button.tooltip_text = "Open the navigation station's chart with this harbour selected"
	_plan_here_button.pressed.connect(func() -> void: plan_requested.emit(_selected_port_id))
	_daydream_label.add_sibling(_plan_here_button)
	_map.map_clicked.disconnect(_map.map_clicked.get_connections()[0].callable)
	_map.route_pressed.disconnect(_on_route_pressed)


## Imagines the voyage to `port_id` (VoyageDaydream; read-only, cached).
func imagine_voyage(port_id: StringName) -> Dictionary:
	if port_id.is_empty():
		return {}
	_daydream = VoyageDaydream.imagine(port_id)
	_daydream_port = port_id
	if _daydream.get("ok", false) and (_daydream.path as PackedVector2Array).size() >= 2:
		_map.frame_geo_points(_daydream.path)
	_refresh()
	return _daydream


func get_daydream_text() -> String:
	return _daydream_label.text if _daydream_label else ""


func _refresh_dream() -> void:
	var catalog := PortCatalog.get_default()
	var display := {
		"boat_port_id": GameSession.get_location_id(),
		"selected_port_id": _selected_port_id,
		"vessel_geo": GameSession.get_vessel_position(),
		"draft_is_proposal": true,
		"editing_enabled": false,
		# Little red pins: the harbours visited (Captain's Log; each once).
		"visited_pins": GameSession.get_captains_log().get_visited_ids(),
	}
	if _daydream_port == _selected_port_id and _daydream.get("ok", false):
		display["draft_legs"] = [{"path": _daydream.path, "ok": true}] as Array[Dictionary]
		display["destination_port_id"] = _selected_port_id
	_map.set_display(display)
	var location := GameSession.get_location()
	if GameSession.is_underway():
		_set_text(_status, Loc.t("At sea, dreaming of other harbours"))
	elif location:
		_set_text(_status, Loc.t("In the cabin at %s, %s") % [location.display_name, location.country])
	_set_text(_position, GeoMath.format_position(GameSession.get_vessel_position()))
	var log := GameSession.get_captains_log()
	_set_text(_voyage_label, Loc.n("%d harbour visited so far", "%d harbours visited so far", log.get_distinct_harbours()) % log.get_distinct_harbours())
	var selected := catalog.get_port(_selected_port_id)
	if selected == null:
		_set_text(_selection_title, Loc.t("No harbour selected"))
		_set_text(_selection_details, Loc.t("Click a harbour on the map, or find one by name."))
		_imagine_button.disabled = true
		_plan_here_button.disabled = true
		_daydream_label.text = ""
		return
	_set_text(_selection_title, "%s, %s" % [selected.display_name, selected.country])
	var visited := Loc.t("Visited") if log.has_visited(selected.id) else Loc.t("Not visited yet")
	_set_text(_selection_details, Loc.t("%s\n%s\n%s  ·  %s  ·  %d nm in a straight line") % [selected.get_description() + _special_line(selected.id),
		HarbourFacilities.describe_services(selected.id), visited,
		GeoMath.format_position(selected.get_geo_position()),
		roundi(GeoMath.distance_nm(GameSession.get_vessel_position(), selected.get_geo_position()))])
	_imagine_button.disabled = false
	_plan_here_button.disabled = false
	_daydream_label.text = _daydream.get("text", "") if _daydream_port == _selected_port_id else ""


func get_draft_route() -> PlannedRoute:
	return _draft_route


func get_draft_error() -> String:
	return _draft_error


func get_draft_waypoints() -> Array[Vector2]:
	return _draft_waypoints.duplicate()


func get_draft_legs() -> Array[Dictionary]:
	return _draft_legs


# --- Draft handling -------------------------------------------------------------------------

## Resets the draft to the committed course (planned route or active voyage).
func _load_committed() -> void:
	_draft_legs.clear()
	_draft_route = null
	_draft_error = ""
	_draft_waypoints.clear()
	_draft_anchorages.clear()
	_clear_suggestion()
	_draft_destination = &""
	if GameSession.is_underway():
		var voyage := GameSession.get_voyage()
		_draft_destination = voyage.route.destination_port_id
		_draft_waypoints = voyage.get_remaining_waypoints()
		_draft_anchorages = voyage.get_remaining_anchorages()
		var remaining := voyage.get_remaining_path()
		for leg in _split_at_waypoints(remaining, _draft_waypoints):
			_draft_legs.append({"path": leg, "ok": true})
	else:
		var planned := GameSession.get_planned_route()
		if planned and planned.has_path():
			_draft_route = planned
			_draft_estimate_seconds = Simulation.estimate_route_seconds(planned.path)
			_draft_destination = planned.destination_port_id
			_draft_waypoints = planned.waypoints.duplicate()
			_draft_anchorages = planned.anchorage_flags()
			for leg_range in planned.get_leg_ranges():
				_draft_legs.append({"path": planned.path.slice(leg_range.x, leg_range.y + 1), "ok": true})
	if _selected_waypoint >= _draft_waypoints.size():
		_selected_waypoint = -1


func _recalculate() -> void:
	_feedback = ""  # A new edit makes earlier messages ("Course set…") stale.
	var location := GameSession.get_location()
	var origin_port: StringName = location.id if location and not GameSession.is_underway() else &""
	var result := SeaRouter.get_default().plan_route(origin_port, GameSession.get_vessel_position(),
		_draft_waypoints, _draft_destination)
	_draft_route = result.route
	if _draft_route:
		_draft_route.anchorages = _draft_anchorages.duplicate()
	_draft_error = result.error
	if result.is_ok():
		SessionLog.write("route_completed", {"to": String(_draft_destination), "nm": snappedf(result.route.get_distance_nm(), 0.1),
			"waypoints": _draft_waypoints.size()})
	else:
		SessionLog.write("route_refused", {"to": String(_draft_destination), "error": result.error})
	_draft_estimate_seconds = Simulation.estimate_route_seconds(_draft_route.path) if _draft_route else 0.0
	_draft_legs.clear()
	var stops: Array[Vector2] = [GameSession.get_vessel_position()]
	stops.append_array(_draft_waypoints)
	var destination := PortCatalog.get_default().get_port(_draft_destination)
	if destination:
		stops.append(destination.get_geo_position())
	for i in result.legs.size():
		var leg: SeaRouter.Leg = result.legs[i]
		if leg.ok:
			_draft_legs.append({"path": leg.path, "ok": true})
		elif i + 1 < stops.size():
			_draft_legs.append({"path": PackedVector2Array([stops[i], stops[i + 1]]), "ok": false})
	_refresh()


func _move_waypoint(index: int, geo: Vector2) -> void:
	if index < 0 or index >= _draft_waypoints.size():
		return
	_draft_waypoints[index] = geo
	_draft_dirty = true
	_clear_suggestion()
	_recalculate()
	if index < _draft_anchorages.size() and _draft_anchorages[index]:
		var spot := _spot(geo)
		_set_feedback((Loc.t("Anchorage %d: %s") % [index + 1, spot.reason]) if spot.ok else
			(Loc.t("Anchorage %d is no good here: %s") % [index + 1, spot.reason]))


func _select_waypoint(index: int) -> void:
	_selected_waypoint = index
	if index >= 0:
		show_tab(TAB_COURSE)  # its Remove button is there
	_refresh()


func _on_route_pressed(leg_index: int, geo: Vector2) -> void:
	show_tab(TAB_COURSE)
	var index := insert_waypoint(leg_index, geo)
	_dragging_waypoint = index
	_map.begin_waypoint_drag(index)


func _on_waypoint_dragged(index: int, geo: Vector2) -> void:
	_dragging_waypoint = index
	_selected_waypoint = index
	_pending_drag_geo = geo
	if index < _draft_waypoints.size():
		_draft_waypoints[index] = geo  # Marker follows the mouse; legs follow at a throttled rate.
		_refresh_map_only()


func _on_waypoint_released(index: int, geo: Vector2) -> void:
	_dragging_waypoint = -1
	_pending_drag_geo = Vector2.INF
	place_waypoint(index, geo)


## A waypoint let go on land or too near the coast moves to the nearest water
## a course may use (within WAYPOINT_SNAP_NM); with none near, it is taken
## away again with a word why, instead of leaving a blocked leg on the chart.
func place_waypoint(index: int, geo: Vector2) -> void:
	var router := SeaRouter.get_default()
	if router.is_point_reachable(geo):
		_move_waypoint(index, geo)
		return
	var water := router.nearest_navigable(geo, WAYPOINT_SNAP_NM)
	if water != Vector2.INF:
		_move_waypoint(index, water)
		_set_feedback(Loc.t("Waypoint %d was on land: moved to the nearest open water.") % (index + 1))
		return
	remove_waypoint(index)
	_set_feedback(Loc.t("That spot is on land, far from open water: no waypoint added there."))


func _on_committed_changed(_value: Variant = null) -> void:
	if not _draft_dirty:
		_load_committed()
	_refresh()


## Splits a path into legs at the given waypoint positions (which are path points).
static func _split_at_waypoints(path: PackedVector2Array, points: Array[Vector2]) -> Array[PackedVector2Array]:
	var legs: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	var next := 0
	for p in path:
		current.append(p)
		if next < points.size() and p.is_equal_approx(points[next]) and current.size() > 1:
			legs.append(current)
			current = PackedVector2Array([p])
			next += 1
	if current.size() > 1:
		legs.append(current)
	return legs


# --- Anchorage waypoints (Iteration 18) --------------------------------------------------

const ANCHORAGE_HINT := "Found a sheltered bay? Place a waypoint near the coast and mark it as an anchorage (M). I'll stop there so you can drop the anchor."


func _build_anchorage_buttons() -> void:
	var row := _remove_button.get_parent()
	_anchorage_button = Button.new()
	_anchorage_button.name = "AnchorageButton"
	_anchorage_button.text = "Anchorage"
	_anchorage_button.tooltip_text = "Make the selected waypoint tonight's anchorage (M): the boat stops there and asks you to drop the anchor."
	_anchorage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anchorage_button.clip_text = true
	_anchorage_button.pressed.connect(func() -> void: toggle_anchorage(_selected_waypoint))
	row.add_child(_anchorage_button)
	row.move_child(_anchorage_button, 1)
	_suggestion_button = Button.new()
	_suggestion_button.name = "AnchorageSuggestionButton"
	_suggestion_button.text = "Move it to the nearest good spot"
	_suggestion_button.visible = false
	_suggestion_button.pressed.connect(use_anchorage_suggestion)
	row.get_parent().add_child(_suggestion_button)
	row.get_parent().move_child(_suggestion_button, row.get_index() + 1)


func is_anchorage(index: int) -> bool:
	return index >= 0 and index < _draft_anchorages.size() and _draft_anchorages[index]


func get_course_status_text() -> String:
	return _course_status.text


func get_draft_anchorages() -> Array[bool]:
	return _draft_anchorages.duplicate()


## Marks waypoint `index` as an anchorage, or unmarks it. A spot that the
## anchoring rule does not allow is not marked: the reason is shown, with the
## nearest suitable spot offered. Returns "" or the reason.
func toggle_anchorage(index: int) -> String:
	if index < 0 or index >= _draft_waypoints.size():
		return ""
	_feedback_hint = ""
	if _draft_anchorages[index]:
		_draft_anchorages[index] = false
		_clear_suggestion()
		_draft_dirty = true
		_recalculate()
		_set_feedback(Loc.t("Waypoint %d is an ordinary waypoint again.") % (index + 1))
		return ""
	var spot := _spot(_draft_waypoints[index])
	if not spot.ok:
		var nearest := GameSession.nearest_anchorage_spot(_draft_waypoints[index], 12.0, GameSession.has_magic_anchor())
		_anchorage_suggestion = nearest
		_anchorage_suggestion_for = index if nearest != Vector2.INF else -1
		var offer := Loc.format(" The nearest suitable spot is %.1f nm away.", GeoMath.distance_nm(_draft_waypoints[index], nearest)) if nearest != Vector2.INF else Loc.t(" There is no suitable spot nearby.")
		_set_feedback(Loc.t("Not an anchorage: %s%s") % [spot.reason, offer])
		return String(spot.reason)
	_draft_anchorages[index] = true
	_clear_suggestion()
	_draft_dirty = true
	_recalculate()
	_set_feedback(Loc.t("Waypoint %d is an anchorage. %s") % [index + 1, spot.reason])
	return ""


## Moves the waypoint to the offered spot and makes it the anchorage.
func use_anchorage_suggestion() -> void:
	var index := _anchorage_suggestion_for
	var spot := _anchorage_suggestion
	if index < 0 or index >= _draft_waypoints.size() or spot == Vector2.INF:
		return
	_draft_waypoints[index] = spot
	_draft_anchorages[index] = true
	_clear_suggestion()
	_draft_dirty = true
	_recalculate()
	_set_feedback(Loc.t("Waypoint %d moved to a suitable spot and made an anchorage. %s") % [index + 1, _spot(spot).reason])


## The anchorage rule for the anchors the captain has (0.105b: the Magic
## Anchor opens deep water too). The anchor a spot needs follows from its
## position (the depth is deterministic), so it is worked out again, not saved.
func _spot(geo: Vector2) -> Dictionary:
	# Remembered per position (the chart refreshes every second; the rule does
	# not change with time), bounded.
	var key := "%s|%s" % [geo, GameSession.has_magic_anchor()]
	if not _spot_cache.has(key):
		if _spot_cache.size() >= 64:
			_spot_cache.clear()
		_spot_cache[key] = GameSession.anchorage_spot(geo, GameSession.has_magic_anchor())
	return _spot_cache[key]


var _spot_cache := {}


## For each anchorage waypoint: whether only the Magic Anchor will hold there.
func _anchorage_magic_flags() -> Array[bool]:
	var flags: Array[bool] = []
	for i in _draft_waypoints.size():
		flags.append(i < _draft_anchorages.size() and _draft_anchorages[i] and _spot(_draft_waypoints[i]).get("kind", &"") == AnchorSite.KIND_MAGIC)
	return flags


func get_anchorage_suggestion() -> Vector2:
	return _anchorage_suggestion


func _clear_suggestion() -> void:
	_anchorage_suggestion = Vector2.INF
	_anchorage_suggestion_for = -1


func _set_feedback(text: String) -> String:
	_feedback = text
	_refresh()
	return text


# --- Presentation ----------------------------------------------------------------------------

func _refresh_map_only() -> void:
	var invalid := PackedInt32Array()
	var router := SeaRouter.get_default()
	for i in _draft_waypoints.size():
		if not router.is_point_reachable(_draft_waypoints[i]) \
				or (i < _draft_anchorages.size() and _draft_anchorages[i] and not _spot(_draft_waypoints[i]).ok):
			invalid.append(i)
	var voyage := GameSession.get_voyage()
	var display := {
		"boat_port_id": GameSession.get_location_id(),
		"selected_port_id": _selected_port_id,
		"destination_port_id": _draft_destination,
		"vessel_geo": GameSession.get_vessel_position(),
		"draft_legs": _draft_legs,
		"draft_is_proposal": _draft_dirty,
		"waypoints": _draft_waypoints,
		"anchorages": _draft_anchorages,
		"anchorage_magic": _anchorage_magic_flags(),
		"invalid_waypoints": invalid,
		"selected_waypoint": _selected_waypoint,
		"editing_enabled": not _draft_legs.is_empty(),
	}
	if voyage:
		var travelled := PackedVector2Array()
		var cumulative := voyage.get_cumulative()
		for i in voyage.route.path.size():
			if cumulative[i] <= voyage.progress_nm:
				travelled.append(voyage.route.path[i])
		travelled.append(voyage.get_position())
		display["travelled_path"] = travelled
		if _draft_dirty:
			display["active_path"] = voyage.get_remaining_path()
		var turn := get_next_turn()
		if not turn.is_empty():
			display["next_waypoint_geo"] = turn.geo
	_map.set_display(display)


## Sets a label's text; the full text is also its tooltip (the header's
## one-line labels are cut with an ellipsis when too long).
static func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
		label.tooltip_text = text


func _refresh() -> void:
	if mode == MODE_DREAM:
		_refresh_dream()
		return
	_refresh_map_only()
	var catalog := PortCatalog.get_default()
	var speed := GameSession.get_vessel_speed_kn()
	var location := GameSession.get_location()

	# Status and clock.
	if GameSession.is_underway():
		if GameSession.is_anchored():
			_set_text(_status, Loc.t("At anchor on the way to %s") % catalog.get_display_name(GameSession.get_voyage_destination_id()))
		else:
			_set_text(_status, Loc.format("Underway to %s  ·  %.1f kn %s", [catalog.get_display_name(GameSession.get_voyage_destination_id()),
				speed, Loc.t("under engine") if GameSession.is_motoring() else Loc.t("under sail")]))
	elif location:
		var verb := Loc.t("Arrived at") if GameSession.get_vessel_status() == SessionState.STATUS_ARRIVED else Loc.t("Moored at")
		_set_text(_status, "%s %s, %s" % [verb, location.display_name, location.country])
	_set_text(_position, GeoMath.format_position(GameSession.get_vessel_position()))
	_refresh_wind()

	# Voyage progress.
	# Always shown (also in port), so the panel below never moves on departure/arrival.
	if not GameSession.is_underway():
		_voyage_bar.value = 0.0
		_set_text(_voyage_label, Loc.t("No voyage in progress  ·  plan a course on the Course tab"))
	else:
		var total := GameSession.get_voyage_total_nm()
		var remaining := GameSession.get_voyage_remaining_nm()
		_voyage_bar.value = 100.0 * (1.0 - remaining / total) if total > 0.0 else 100.0
		var eta := Simulation.get_eta()
		_set_text(_voyage_label, Loc.t("%d nm to go  ·  ETA about %s") % [roundi(remaining), Simulation.format_game_time(eta)])

	# Selected port.
	var selected := catalog.get_port(_selected_port_id)
	if selected == null:
		_set_text(_selection_title, Loc.t("No port selected"))
		_set_text(_selection_details, Loc.t("Click a port on the chart to choose a destination."))
		_plot_button.disabled = true
		_plot_button.text = "Plot course"
	else:
		_set_text(_selection_title, "%s, %s" % [selected.display_name, selected.country])
		# Captain's Chartroom: a compact summary (the services by name and the
		# distance); the explanations and the coordinates are in the tooltip.
		var away := roundi(GeoMath.distance_nm(GameSession.get_vessel_position(), selected.get_geo_position()))
		_set_text(_selection_details, Loc.t("%s\n%s\n%d nm away in a straight line") % [selected.get_description() + _special_line(selected.id),
			HarbourFacilities.describe_services(selected.id, true), away])
		_selection_details.tooltip_text = Loc.t("%s\n%s  ·  %d nm in a straight line") % [HarbourFacilities.describe_services(selected.id),
			GeoMath.format_position(selected.get_geo_position()), away]
		var here := location != null and selected.id == location.id and not GameSession.is_underway()
		_plot_button.disabled = here
		_plot_button.text = "You are here" if here else Loc.t("Plot course to %s") % selected.display_name

	# Course.
	if _draft_destination.is_empty():
		_set_text(_course_label, Loc.t("No course planned."))
	else:
		var distance := GeoMath.path_length_nm(_draft_route.path) if _draft_route else -1.0
		var seconds := _draft_estimate_seconds
		var summary := Loc.t("To %s") % catalog.get_display_name(_draft_destination)
		if _draft_route == null and not _draft_dirty and GameSession.is_underway():
			# Being sailed: distance to go and ETA are live values in the header.
			summary += Loc.t("  ·  %d nm course") % roundi(GameSession.get_voyage_total_nm())
			var turn := get_next_turn()
			if not turn.is_empty():
				summary += Loc.format("\nSteering %03d°  ·  %s in %.1f nm", [roundi(turn.course), Loc.t("next turn to %03d°") % roundi(turn.next_course)
					if turn.next_course >= 0.0 else "arrival", turn.nm])
		elif distance >= 0.0:
			summary += Loc.t("  ·  %d nm  ·  about %s with the expected wind") % [roundi(distance), Simulation.format_duration(seconds)]
		if not _draft_waypoints.is_empty():
			summary += "\n" + Loc.n("%d waypoint", "%d waypoints", _draft_waypoints.size()) % _draft_waypoints.size()
		_set_text(_course_label, summary)
	var valid := _draft_route != null or (not _draft_dirty and not _draft_legs.is_empty())
	var course_status := ""
	if _draft_destination.is_empty():
		course_status = ""
	elif not valid:
		course_status = Loc.t("NOT NAVIGABLE: %s") % _draft_error
	elif _draft_dirty:
		course_status = Loc.t("Sea route found. Press %s to use it.") % (Loc.t("Change course") if GameSession.is_underway() else Loc.t("Apply course"))
	else:
		course_status = Loc.t("Current course") + (Loc.t(" (being sailed)") if GameSession.is_underway() else "")
	if not _feedback.is_empty():
		course_status += "\n" + _feedback
	if not _feedback_hint.is_empty():
		course_status += "\n" + _feedback_hint
	_set_text(_course_status, course_status)
	_edit_help.visible = not _draft_destination.is_empty() and mode == MODE_STATION
	_update_readiness(valid)
	_apply_button.text = "Change course" if GameSession.is_underway() else Loc.t("Apply course")
	_apply_button.disabled = not _draft_dirty or _draft_route == null
	_discard_button.disabled = not _draft_dirty
	_remove_button.disabled = _selected_waypoint < 0
	_anchorage_button.disabled = _selected_waypoint < 0
	_anchorage_button.text = "Unmark" if is_anchorage(_selected_waypoint) else Loc.t("Anchorage")
	_suggestion_button.visible = _anchorage_suggestion != Vector2.INF
	_clear_button.disabled = GameSession.is_underway() or GameSession.get_planned_route() == null
	# Always in the footer; disabled (not hidden) when it cannot be used.
	_sail_button.disabled = GameSession.is_underway() or _draft_dirty or GameSession.get_planned_route() == null
	_sail_button.tooltip_text = "Already underway" if GameSession.is_underway() else Loc.t("Depart on the planned course")

	_set_text(_weather_label, _describe_weather())
	var warnings := _count_weather_warnings()
	_tabs.set_tab_title(TAB_WEATHER, Loc.t("Weather (%d)") % warnings if warnings > 0 else Loc.t("Weather"))


## Passage Readiness for the course in harbour (Iteration 14): advisory,
## recomputed only when the course, the boat or the half hour changes.
func _update_readiness(valid: bool) -> void:
	var path := PackedVector2Array()
	if valid and not GameSession.is_underway():
		path = _draft_route.path if _draft_route else (GameSession.get_planned_route().path if GameSession.get_planned_route() else path)
	if path.size() < 2:
		_readiness_key = ""
		_set_text(_readiness_label, "")
		return
	var provisions := GameSession.get_provisions()
	var key := "%d|%.3f|%d|%s|%.1f|%.1f|%.1f" % [path.size(), GeoMath.path_length_nm(path), floori(GameSession.get_game_time() / 1800.0),
		GameSession.get_vessel_id(), GameSession.get_condition(), provisions.food_days, provisions.water_days]
	if key == _readiness_key:
		return
	_readiness_key = key
	readiness = PassageReadiness.assess(path)
	# The headline and the most important note; the rest in the tooltip.
	_set_text(_readiness_label, Loc.t("Passage readiness: ") + PassageReadiness.describe(readiness, 1))
	_readiness_label.tooltip_text = Loc.t("Passage readiness: ") + PassageReadiness.describe(readiness, 3)
	_readiness_label.theme_type_variation = [&"SuccessLabel", &"", &"WarningLabel"][int(readiness.level)]


## The last Passage Readiness shown (tests).
var readiness := {}
var _readiness_key := ""


## Shows one of the sidebar's tabs (TAB_COURSE, TAB_WEATHER, TAB_DETAILS).
func show_tab(index: int) -> void:
	_tabs.current_tab = index


func get_current_tab() -> int:
	return _tabs.current_tab


## Weather at the boat (and how it sails in it) for the Weather tab.
func _refresh_wind() -> void:
	var here := Simulation.get_weather_at_vessel()
	var text := Hud.describe_wind(here)
	if here.speed_kn >= 0.5:
		text += Loc.t(" (from the %s)") % WindField.compass_name(here.from_deg)
	text += Loc.t("\nGusts %d kn  ·  %s  ·  %s") % [roundi(here.gust_kn), here.get_label(), here.get_hazard_name()]
	if here.cyclone_risk > 0.05:
		text += (Loc.t("\nTropical cyclone season: high risk (%s)") if here.cyclone_risk > 0.6 else Loc.t("\nTropical cyclone season: some risk (%s)")) % Loc.t(here.cyclone_basin)
	_set_text(_wind_here, text)
	if GameSession.is_underway():
		var propulsion := GameSession.get_propulsion()
		var side := PropulsionState.wind_side(propulsion.true_wind_angle)
		_set_text(_propulsion, Loc.t("%s\nWind %d° %s") % [propulsion.describe(), roundi(absf(propulsion.true_wind_angle)),
			side if side else Loc.t("off the bow")])
	else:
		_set_text(_propulsion, Loc.t("In port. The boat chooses sail or engine itself once underway."))


## The course shown (draft or active) as one path, or empty when it is not navigable.
func _shown_path() -> PackedVector2Array:
	var path := PackedVector2Array()
	for leg in _draft_legs:
		if not leg.ok:
			return PackedVector2Array()
		for p: Vector2 in leg.path:
			if path.is_empty() or not path[path.size() - 1].is_equal_approx(p):
				path.append(p)
	return path


## Hazardous weather along the shown course (from the weather model; cached
## per course and 5 game minutes).
func get_route_hazards() -> Array[Dictionary]:
	var path := _shown_path()
	var from_nm := 0.0
	if GameSession.is_underway() and not _draft_dirty:
		var voyage := GameSession.get_voyage()
		path = voyage.route.path
		from_nm = voyage.progress_nm
	var key := "%d|%s|%.2f|%d" % [path.size(), path[path.size() - 1] if path.size() > 0 else Vector2.ZERO, from_nm,
		floori(GameSession.get_game_time() / 300.0)]
	if key != _hazards_key:
		_hazards_key = key
		_hazards = Simulation.route_hazards(path, from_nm) if path.size() >= 2 else ([] as Array[Dictionary])
	return _hazards


func _count_weather_warnings() -> int:
	return get_route_hazards().size()


func _describe_weather() -> String:
	var lines := PackedStringArray()
	if GameSession.is_underway():
		for storm in Simulation.get_storms_near(GameSession.get_vessel_position()):
			lines.append(Loc.t("%s nearby, moving %s.") % [WeatherStyle.label(storm, GameSession.get_game_time()).capitalize(),
				WindField.compass_name(storm.heading_at(GameSession.get_game_time()))])
	var path := _shown_path()
	if path.size() < 2 and not GameSession.is_underway():
		lines.append(Loc.t("Plot a course to see the weather along it."))
		return "\n".join(lines)
	var hazards := get_route_hazards()
	if hazards.is_empty():
		lines.append(Loc.t("No hazardous weather expected along the next %d hours of the course.") % roundi(Simulation.DISPLAY_HORIZON_HOURS))
	for hazard in hazards:
		var expected := Simulation.expected_strength(hazard)
		var outlook := Loc.t("Wind to %d kn, gusts %d kn.") % [roundi(expected[0]), roundi(expected[1])]
		if (hazard.sample as WeatherSample).classification == WeatherModel.CLASS_THUNDER_RISK:
			outlook = Loc.t("Thunderstorms may form there.")
		lines.append(Loc.t("%s (%s): %s, %d nm ahead. %s") % [hazard.label, WeatherModel.hazard_name(hazard.hazard).to_lower(),
			Simulation.describe_when(hazard.hours), roundi(hazard.distance_nm), outlook])
	return "\n".join(lines)


func _fit_map_to_free_area(ui_scale: float) -> void:
	_map.occluded_right_px = SIDE_PANEL_WIDTH * ui_scale
	_map.reset_view()


func _on_cursor_moved(geo: Variant) -> void:
	if not geo is Vector2:
		_cursor_label.text = ""
		return
	_cursor_label.text = GeoMath.format_position(geo)
	_anchor_hover_geo = geo
	_anchor_hover_wait = ANCHOR_HOVER_DELAY
	if wind_shown and mode == MODE_STATION:
		# The wind of the snapshot the chart shows (Now, past or forecast).
		var layer := _map.wind_layer
		var known := GameSession.get_game_time() if layer.get_offset_steps() > 0 else INF
		var at := GameSession.get_game_time() if layer.get_offset_steps() == 0 else layer.get_snapshot_time()
		_cursor_label.text += "  ·  " + Hud.describe_wind(Simulation.get_weather_at(geo, at, known))


# --- Anchorage highlights (0.105b) -------------------------------------------------------

const ANCHOR_HOVER_DELAY := 0.25
var _anchor_toggle: CheckButton
var _anchor_legend: PanelContainer
var _anchor_note: Label
var _anchor_info: Label
var _anchor_hover_geo := Vector2.INF
var _anchor_hover_wait := -1.0
var _anchor_info_geo := Vector2.INF


func _build_anchorage_controls() -> void:
	_anchor_toggle = CheckButton.new()
	_anchor_toggle.name = "AnchorageToggle"
	_anchor_toggle.text = "Anchorages"
	_anchor_toggle.tooltip_text = "Show where you can anchor (zoom in on a coast)"
	_wind_toggle.get_parent().add_child(_anchor_toggle)
	_wind_toggle.get_parent().move_child(_anchor_toggle, _wind_toggle.get_index() + 1)
	_anchor_toggle.toggled.connect(set_anchorages_shown)
	_anchor_legend = PanelContainer.new()
	_anchor_legend.name = "AnchorageLegend"
	_anchor_legend.theme_type_variation = &"HudPanel"
	_anchor_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_legend.position = Vector2(24, 92)
	_anchor_legend.custom_minimum_size = Vector2(340, 0)
	_wind_legend.get_parent().add_child(_anchor_legend)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_legend.add_child(box)
	var title := Label.new()
	title.text = "Anchorages"
	title.theme_type_variation = &"HeaderLabel"
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	for entry: Array in [[AnchorageLayer.NORMAL_COLOUR, Loc.t("Normal anchor")], [AnchorageLayer.MAGIC_COLOUR, Loc.t("Magic Anchor (deep)")]]:
		var swatch := ColorRect.new()
		swatch.color = Color(entry[0], 0.9)
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = entry[1]
		label.add_theme_font_size_override(&"font_size", 16)
		row.add_child(label)
	_anchor_note = Label.new()
	_anchor_note.name = "AnchorageNote"
	_anchor_note.theme_type_variation = &"MutedLabel"
	_anchor_note.add_theme_font_size_override(&"font_size", 15)
	box.add_child(_anchor_note)
	_anchor_info = Label.new()
	_anchor_info.name = "AnchorageInfo"
	_anchor_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anchor_info.custom_minimum_size = Vector2(330, 0)
	_anchor_info.add_theme_font_size_override(&"font_size", 16)
	box.add_child(_anchor_info)
	set_anchorages_shown(false)


## Shows or hides the anchorage highlights and their legend.
func set_anchorages_shown(on: bool) -> void:
	if _anchor_toggle == null:
		return
	_anchor_toggle.set_pressed_no_signal(on)
	_anchor_legend.visible = on
	_map.anchorage_layer.set_shown(on)
	_anchor_info.text = ""
	_anchor_info_geo = Vector2.INF


func are_anchorages_shown() -> bool:
	return _map.anchorage_layer.shown


func get_anchorage_info_text() -> String:
	return _anchor_info.text if _anchor_info else ""


func _update_anchorage_info(delta: float) -> void:
	if _anchor_toggle == null or not _map.anchorage_layer.shown:
		return
	var zoomed := _map.anchorage_layer.is_zoomed_in()
	_anchor_note.text = (Loc.t("Depths are GAME ESTIMATES, for play, not navigation. Point at the water to see more.") if zoomed
		else Loc.t("Zoom in on a coast to see where you can anchor."))
	if not zoomed:
		_anchor_info.text = ""
		return
	if _anchor_hover_wait < 0.0:
		return
	_anchor_hover_wait -= delta
	if _anchor_hover_wait < 0.0 and _anchor_hover_geo != Vector2.INF and _anchor_hover_geo != _anchor_info_geo:
		inspect_anchorage(_anchor_hover_geo)


## Explains the anchorage at `geo` in the legend (the cursor rested there).
func inspect_anchorage(geo: Vector2) -> String:
	_anchor_info_geo = geo
	var site := AnchorSite.evaluate(geo, Simulation.get_weather_at(geo), GameSession.has_magic_anchor(), false)
	_anchor_info.text = AnchorSite.describe_for_chart(site, GameSession.has_magic_anchor())
	return _anchor_info.text


## Shows or hides the wind overlay and its legend.
func set_wind_shown(shown: bool) -> void:
	wind_shown = shown
	_wind_toggle.set_pressed_no_signal(shown)
	_wind_legend.visible = shown
	_map.wind_layer.set_shown(shown)
	if shown:
		_map.wind_layer.update_time(GameSession.get_game_time())


func is_wind_shown() -> bool:
	return _map.wind_layer.visible


## The read-only wind time navigator (Iteration 17) under the wind legend:
## Previous / Now / Next in 30-minute steps up to two hours either way, the
## snapshot's label and time, the forecast note, and the zoom notice. It only
## changes which modelled time the overlay shows; nothing in the game moves.
func _build_wind_time_controls() -> void:
	var box := _wind_legend.get_node("VBox") as VBoxContainer
	var row := HBoxContainer.new()
	row.name = "WindTime"
	row.add_theme_constant_override(&"separation", 6)
	box.add_child(row)
	var previous := Button.new()
	previous.name = "WindPrevious"
	previous.text = "◀ 1 h"
	previous.tooltip_text = "Show the wind an hour earlier (up to six hours)"
	previous.pressed.connect(step_wind_time.bind(-1))
	row.add_child(previous)
	var now := Button.new()
	now.name = "WindNow"
	now.text = "Now"
	now.tooltip_text = "Show the wind now"
	now.pressed.connect(func() -> void: _map.wind_layer.set_offset_steps(0))
	row.add_child(now)
	var next := Button.new()
	next.name = "WindNext"
	next.text = "1 h ▶"
	next.tooltip_text = "Show the forecast an hour later (up to six hours)"
	next.pressed.connect(step_wind_time.bind(1))
	row.add_child(next)
	var label := Label.new()
	label.name = "WindTimeLabel"
	label.add_theme_font_size_override(&"font_size", 16)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var note := Label.new()
	note.name = "WindForecastNote"
	note.text = "Estimated conditions. Actual wind may differ."
	note.theme_type_variation = &"MutedLabel"
	note.add_theme_font_size_override(&"font_size", 15)
	box.add_child(note)
	var zoom := Label.new()
	zoom.name = "WindZoomNotice"
	zoom.text = "Zoom in to see wind details."
	zoom.theme_type_variation = &"MutedLabel"
	zoom.add_theme_font_size_override(&"font_size", 15)
	box.add_child(zoom)
	_map.wind_layer.snapshot_changed.connect(_update_wind_time)
	_map.wind_layer.detail_changed.connect(func(_hidden: bool) -> void: _update_wind_time())
	_update_wind_time()


## Moves the wind snapshot by `steps` hours (clamped to ±6 h; Iteration 18).
func step_wind_time(steps: int) -> void:
	var layer := _map.wind_layer
	layer.set_offset_steps(layer.get_offset_steps() + steps)


func _update_wind_time() -> void:
	var layer := _map.wind_layer
	var offset := layer.get_offset_steps()
	var label := _wind_legend.find_child("WindTimeLabel", true, false) as Label
	if label == null:
		return
	var time := GameSession.get_game_time() if offset == 0 else layer.get_snapshot_time()
	label.text = "%s  ·  %s" % [layer.snapshot_label(), Simulation.format_game_time(time)]
	if offset != 0:
		label.text += " (%s%s)" % ["+" if offset > 0 else "−", Simulation.format_duration(absi(offset) * WindLayer.OFFSET_STEP)]
	(_wind_legend.find_child("WindForecastNote", true, false) as Control).visible = offset > 0
	(_wind_legend.find_child("WindZoomNotice", true, false) as Control).visible = layer.detail_hidden
	(_wind_legend.find_child("WindPrevious", true, false) as Button).disabled = offset <= -WindLayer.MAX_OFFSET_STEPS
	(_wind_legend.find_child("WindNext", true, false) as Button).disabled = offset >= WindLayer.MAX_OFFSET_STEPS
	(_wind_legend.find_child("WindNow", true, false) as Button).disabled = offset == 0


func _build_wind_legend() -> void:
	var bands := %WindLegendBands
	var lower := 0
	for band: Array in WindLayer.BANDS:
		var swatch := ColorRect.new()
		swatch.color = band[1]
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bands.add_child(swatch)
		var label := Label.new()
		label.text = "%d+" % lower if is_inf(band[0]) else "%d-%d" % [lower, int(band[0])]
		label.theme_type_variation = &"MutedLabel"
		label.add_theme_font_size_override(&"font_size", 16)
		bands.add_child(label)
		lower = int(band[0]) if not is_inf(band[0]) else lower


## A special harbour's line in the harbour details (I021): what makes it
## special, in the current language; "" for any other harbour.
static func _special_line(port_id: StringName) -> String:
	var note := HarbourLooks.get_default().special_note(port_id)
	return "\n" + Loc.t("Special harbour: %s") % note if note != "" else ""
