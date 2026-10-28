class_name Hud
extends Control
## Gameplay overlay shared by both boat areas: area and location, game clock
## with time acceleration, voyage status (destination, speed, progress, ETA),
## weather warnings, the interaction prompt and a menu button.
##
## The HUD only reads state; it refreshes its text every frame from
## GameSession, so it can never drift from the simulation.
##
## The clock bar (game time, PAUSED badge, Pause / 1× / 5× / 20×) is the one
## shared time control. On the chart the HUD runs in "chart mode": only the
## clock bar is shown, centred over the map (left of the chart's sidebar).

signal menu_requested
signal chart_requested
## The Long Passage panel's Save button (Iteration 16).
signal save_requested

@onready var _area: Label = %AreaLabel
@onready var _location: Label = %LocationLabel
@onready var _status: Label = %StatusLabel
@onready var _clock: Label = %ClockLabel
@onready var _paused_badge: Control = %PausedBadge
@onready var _clock_panel: Control = $ClockPanel
@onready var _route_caption: Label = %RouteCaption
@onready var _route: Label = %RouteLabel
@onready var _route_detail: Label = %RouteDetail
@onready var _progress: ProgressBar = %VoyageProgress
@onready var _propulsion: Label = %PropulsionLabel
@onready var _wind: Label = %WindLabel
@onready var _prompt_panel: Control = %PromptPanel
@onready var _prompt: Label = %PromptLabel
@onready var _warning_panel: Control = %WarningPanel
@onready var _warning_text: Label = %WarningText


## The shortcut strip at the bottom left (Iteration 12): key caps on a slim,
## translucent bar (the theme's KeyBar, day or night) so it reads over any
## deck, pontoon or quay.
const SHORTCUTS: Array = [["WASD / ↑↓←→", "move"], ["E", "interact"], ["Q", "actions"], ["R", "rod"], ["H", "hat"], ["L", "Captain's Log"],  # i18n
	["Esc", "menu"]]  # i18n

## Space between the panels of the right-hand column.
const COLUMN_GAP := 12.0
## Half the prompt's usual width (hud.tscn).
const PROMPT_HALF_WIDTH := 160.0
## The right-hand column's margin.
const RIGHT_MARGIN := 24.0

var hat_badge: HatBadge
## Fishing, anchor and galley indicators (Iteration 13), under the hat badge.
var aboard_badge: AboardBadge
## Long Passage (Iteration 16): bottom right, underway on long voyages.
var passage_panel: PassagePanel
## Iteration 17: the sailing panel (right, underway) and the chartplotter
## (left, on deck underway, P or the action wheel).
var sailing_panel: SailingPanel
var chart_plotter: ChartPlotter
var radar_panel: RadarPanel
var _area_id: StringName
var _planned_key := ""
var _planned_estimated_at := -INF
var _planned_seconds := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	%MenuButton.pressed.connect(menu_requested.emit)
	%WarningChartButton.pressed.connect(func() -> void:
		hide_warning()
		chart_requested.emit())
	%WarningDismissButton.pressed.connect(hide_warning)
	set_prompt("")
	hide_warning()
	_build_controls()
	hat_badge = HatBadge.new()
	hat_badge.name = "HatBadge"
	hat_badge.position = Vector2(24, 106)
	add_child(hat_badge)
	aboard_badge = AboardBadge.new()
	aboard_badge.name = "AboardBadge"
	add_child(aboard_badge)
	passage_panel = PassagePanel.new()
	passage_panel.theme_type_variation = &"HudPanel"
	passage_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	passage_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	passage_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	passage_panel.offset_right = -24.0
	passage_panel.offset_bottom = -18.0
	passage_panel.visible = false
	passage_panel.chart_requested.connect(chart_requested.emit)
	passage_panel.save_requested.connect(save_requested.emit)
	add_child(passage_panel)
	sailing_panel = SailingPanel.new()
	sailing_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	sailing_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sailing_panel.offset_right = -24.0
	sailing_panel.offset_top = 150.0
	add_child(sailing_panel)
	chart_plotter = ChartPlotter.new()
	chart_plotter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	chart_plotter.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chart_plotter.offset_left = 24.0
	chart_plotter.offset_bottom = -64.0
	chart_plotter.on_deck = func() -> bool: return _area_id == SessionState.AREA_EXTERIOR
	add_child(chart_plotter)
	# The radar (I019): bottom left, beside the chartplotter when both show.
	radar_panel = RadarPanel.new()
	radar_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	radar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	radar_panel.offset_left = 24.0
	radar_panel.offset_bottom = -64.0
	radar_panel.on_deck = func() -> bool: return _area_id == SessionState.AREA_EXTERIOR
	add_child(radar_panel)


func _build_controls() -> void:
	var strip := $Controls as PanelContainer
	strip.theme_type_variation = &"KeyBar"
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	strip.add_child(row)
	for i in SHORTCUTS.size():
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size.x = 6
			row.add_child(gap)
		var key := Label.new()
		key.theme_type_variation = &"KeyLabel"
		key.text = SHORTCUTS[i][0]
		row.add_child(key)
		var what := Label.new()
		what.text = SHORTCUTS[i][1]
		what.add_theme_font_size_override(&"font_size", 17)
		row.add_child(what)


## The shortcut strip as text, "E interact · H hat · …" (tests, diagnostics).
func get_controls_text() -> String:
	var parts := PackedStringArray()
	for pair: Array in SHORTCUTS:
		parts.append("%s %s" % [pair[0], pair[1]])
	return "  ·  ".join(parts)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()
	if radar_panel:
		var left := 24.0 + (chart_plotter.size.x + 12.0 if chart_plotter.visible else 0.0)
		if not is_equal_approx(radar_panel.offset_left, left):
			radar_panel.offset_left = left
	_keep_prompt_clear()


## The interaction prompt sits centred at the bottom, but steps right of the
## chartplotter and the radar when they would reach it (Steady Hands: at a
## large interface size the radar covered "Go below").
func _keep_prompt_clear() -> void:
	var left_edge := 0.0
	for panel: Control in [chart_plotter, radar_panel]:
		if panel and panel.visible:
			left_edge = maxf(left_edge, panel.position.x + panel.size.x)
	var shift := 0.0
	if left_edge > 0.0:
		shift = maxf(0.0, left_edge + COLUMN_GAP - (size.x - _prompt_panel.size.x) / 2.0)
	if not is_equal_approx(_prompt_panel.offset_left, -PROMPT_HALF_WIDTH + shift):
		_prompt_panel.offset_left = -PROMPT_HALF_WIDTH + shift
		_prompt_panel.offset_right = PROMPT_HALF_WIDTH + shift


## Width the chart's sidebar takes on the right, in unscaled UI pixels; the
## clock bar is centred over the remaining map area in chart mode.
const CHART_SIDEBAR_WIDTH := 544.0
## Half the clock bar's width (Cozy Polish: a compact bar).
const CLOCK_HALF_WIDTH := 190.0

var _chart_mode := false
var _warning_pending := false


## Chart mode: only the shared clock bar, centred over the map. A weather
## warning that arrives meanwhile is shown again on returning to the boat.
func set_chart_mode(enabled: bool) -> void:
	_chart_mode = enabled
	for node_name in ["AreaPanel", "RoutePanel", "PromptPanel", "Controls", "HatBadge", "AboardBadge", "PassagePanel",
			"SailingPanel", "ChartPlotter", "RadarPanel"]:
		var node := get_node_or_null(node_name) as Control
		if node == null:
			continue
		if node_name in ["HatBadge", "AboardBadge", "PassagePanel", "SailingPanel", "ChartPlotter", "RadarPanel"]:
			node.process_mode = Node.PROCESS_MODE_DISABLED if enabled else Node.PROCESS_MODE_INHERIT
			if enabled:
				node.hide()
			elif node_name == "AboardBadge":
				node.show()
			continue
		node.visible = not enabled if node_name != "PromptPanel" else (not enabled and not _prompt.text.is_empty())
	_warning_panel.visible = _warning_pending and not enabled
	var shift := -CHART_SIDEBAR_WIDTH / 2.0 if enabled else 0.0
	_clock_panel.offset_left = -CLOCK_HALF_WIDTH + shift
	_clock_panel.offset_right = CLOCK_HALF_WIDTH + shift


func is_chart_mode() -> bool:
	return _chart_mode


func set_area(area: StringName) -> void:
	_area_id = area
	_area.text = SessionState.get_area_display_name(area)


func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt_panel.visible = not text.is_empty() and not _chart_mode


func get_prompt() -> String:
	return _prompt.text if _prompt_panel.visible else ""


func show_warning(text: String) -> void:
	_warning_text.text = text
	_warning_pending = true
	_warning_panel.visible = not _chart_mode


func hide_warning() -> void:
	_warning_pending = false
	_warning_panel.hide()


## True while a warning is waiting to be dismissed (also while it is kept
## out of the way on the chart).
func is_warning_visible() -> bool:
	return _warning_pending


func get_route_text() -> String:
	return _route.text


## The right-hand column, top to bottom: the route panel, Trip Details (the
## sailing panel, underway) and a weather warning. Each piece hangs only from
## the ones above it, so a warning appearing, changing its text or being
## dismissed never moves Trip Details (Steady Hands: before, Trip Details
## was pushed down below every warning, and a long warning, e.g. in Danish,
## ran over it because the warning's height was assumed to be 124 px). The
## warning takes the height its text needs. Cheap: offsets are only written
## when they change.
func _stack_right_column() -> void:
	var route_panel := $RoutePanel as Control
	# Never under the clock: at a large interface size on a 16:9 screen the
	# route panel gives up width (its lines end in "…") rather than overlap.
	var clock := $ClockPanel as Control
	var room := size.x - RIGHT_MARGIN - (clock.position.x + clock.size.x) - COLUMN_GAP
	var wanted := ROUTE_PANEL_WIDTH if _route.visible else ROUTE_PANEL_COMPACT
	var width := minf(wanted, maxf(room, ROUTE_PANEL_COMPACT))
	if not is_equal_approx(route_panel.offset_left, -(width + RIGHT_MARGIN)):
		route_panel.offset_left = -(width + RIGHT_MARGIN)
	# The route panel shrinks again when lines are hidden.
	if route_panel.size.y > route_panel.get_combined_minimum_size().y + 0.5:
		route_panel.offset_bottom = route_panel.offset_top
	var below_route := route_panel.offset_top + route_panel.size.y + COLUMN_GAP
	if not is_equal_approx(sailing_panel.offset_top, below_route):
		sailing_panel.offset_top = below_route
	var warning_top := sailing_panel.offset_top + sailing_panel.size.y + COLUMN_GAP if sailing_panel.visible else below_route
	if not is_equal_approx(_warning_panel.offset_top, warning_top):
		_warning_panel.offset_top = warning_top
		_warning_panel.offset_bottom = warning_top  # grows to fit its text


func refresh() -> void:
	if not GameSession.is_active():
		return
	var catalog := PortCatalog.get_default()
	_clock.text = Simulation.format_game_time(GameSession.get_game_time())
	_paused_badge.visible = GameSession.is_paused()
	_stack_right_column()
	# The hat badge sits just below the area panel, whose height follows its text.
	var area_panel := $AreaPanel as Control
	hat_badge.position = Vector2(area_panel.position.x, area_panel.position.y + area_panel.size.y + 10.0)
	aboard_badge.position = hat_badge.position + Vector2(0.0, (hat_badge.size.y + 8.0) if hat_badge.visible else 0.0)
	_status.text = describe_status()
	var alarm := GameSession.get_condition() <= 40.0 or GameSession.get_provisions().endurance_days() <= Provisions.LOW_DAYS
	var status_style := &"WarningLabel" if alarm else &"MutedLabel"
	if _status.theme_type_variation != status_style:
		_status.theme_type_variation = status_style
	var wind := Simulation.get_wind_at(GameSession.get_vessel_position())
	_wind.text = describe_wind(wind)
	if GameSession.is_underway():
		var destination := catalog.get_display_name(GameSession.get_voyage_destination_id())
		var remaining := GameSession.get_voyage_remaining_nm()
		var total := GameSession.get_voyage_total_nm()
		var propulsion := GameSession.get_propulsion()
		if GameSession.is_anchored():
			# I019: the anchor's condition at a glance.
			_location.text = Loc.t("At anchor, %s  ·  bound for %s") % [Loc.t(AnchorSite.holding_text(GameSession.get_anchor().holding)).to_lower(),
				destination]
		else:
			_location.text = Loc.t("Underway to %s") % destination
		_route_caption.text = "At anchor  ·  voyage paused" if GameSession.is_anchored() else \
			Loc.format("Underway  ·  %.1f kn", GameSession.get_vessel_speed_kn())
		_route.text = Loc.t("To %s  ·  %d nm to go") % [destination, roundi(remaining)]
		_route_detail.text = Loc.t("ETA about %s (estimate)") % Simulation.format_game_time(Simulation.get_eta())
		_propulsion.text = propulsion.describe()
		# Speed, sails and wind are on the sailing panel underway: the route
		# panel keeps to the voyage (and the holding, at anchor).
		_propulsion.visible = GameSession.is_anchored()
		_wind.visible = false
		_set_route_lines(true)
		if GameSession.is_holding_at_anchorage():
			_route_caption.text = "At the anchorage  ·  0.0 kn"
			_route_detail.text = "Drop the anchor, or sail on (Q)"
			_propulsion.text = "Sails down  ·  waiting at the anchorage"
		if GameSession.is_anchored():
			_route_detail.text = "Raise the anchor at the windlass to sail on"
			_propulsion.text = Loc.t("%s  ·  %d × the depth of chain") % [AnchorSite.holding_text(GameSession.get_anchor().holding),
				GameSession.get_anchor().scope]
		var side := PropulsionState.wind_side(propulsion.true_wind_angle)
		if not GameSession.is_anchored():
			_wind.text += "  ·  %d° %s" % [roundi(absf(propulsion.true_wind_angle)), side if side else Loc.t("off the bow")]
		_progress.visible = true
		_progress.value = 100.0 * (1.0 - remaining / total) if total > 0.0 else 100.0
	else:
		var location := GameSession.get_location()
		var arrived := GameSession.get_vessel_status() == SessionState.STATUS_ARRIVED
		_location.text = "%s %s" % [Loc.t("Arrived at") if arrived else Loc.t("Moored at"), location.display_name if location else "?"]
		var planned := GameSession.get_planned_route()
		_route_caption.text = "Planned route"
		_route.text = PlannedRoute.describe(planned, catalog)
		if planned and planned.has_path():
			var key := "%s|%d|%.3f" % [planned.destination_port_id, planned.path.size(), planned.get_distance_nm()]
			if key != _planned_key or GameSession.get_game_time() - _planned_estimated_at > 1800.0:
				_planned_key = key
				_planned_estimated_at = GameSession.get_game_time()
				_planned_seconds = Simulation.estimate_route_seconds(planned.path)
			_route_detail.text = Loc.t("About %s with the expected wind  ·  set sail at the helm") % \
				Simulation.format_duration(_planned_seconds)
		else:
			_route_detail.text = "Plot a course at the chart table"
		_propulsion.visible = false
		_progress.visible = false
		# No course planned: no empty route panel, just the wind and the menu.
		_set_route_lines(planned != null and planned.has_path())
		_wind.visible = true


## Width of the route panel with a voyage or a planned course; without one
## it shrinks to the wind and the menu button.
const ROUTE_PANEL_WIDTH := 536.0
const ROUTE_PANEL_COMPACT := 300.0


func _set_route_lines(shown: bool) -> void:
	if _route.visible != shown:
		_route_caption.visible = shown
		_route.visible = shown
		_route_detail.visible = shown
		_stack_right_column()  # the panel's width follows (wide with a course)


## The boat's condition, money and stores in one compact line:
## "Hull 87 % · Sound   €9,000   Food 12.5 d · Water 12.5 d".
static func describe_status() -> String:
	var provisions := GameSession.get_provisions()
	return Loc.format("Hull %s   %s   Food %.1f d · Water %.1f d", [VesselCondition.describe(GameSession.get_condition()),
		GameSession.format_money(GameSession.get_funds()), floorf(provisions.food_days * 10.0 + 1e-6) / 10.0,
		floorf(provisions.water_days * 10.0 + 1e-6) / 10.0])


## "Wind WSW 14 kn" (where it blows from), with gusts when they stand out
## ("gusts 31") and the weather when it is hazardous ("Gale"): the sustained
## wind, as the boat sails with it.
static func describe_wind(wind: WindField.Sample) -> String:
	if wind.speed_kn < 0.5:
		return Loc.t("Wind calm")
	var text := Loc.t("Wind %s %d kn") % [WindField.compass_name(wind.from_deg), roundi(wind.speed_kn)]
	var weather := wind as WeatherSample
	if weather:
		if weather.gust_kn >= weather.speed_kn + 6.0:
			text += Loc.t(", gusts %d") % roundi(weather.gust_kn)
		if weather.hazard >= WeatherModel.HAZARD_CAUTION:
			text += "  ·  %s" % weather.get_label()
	return text
