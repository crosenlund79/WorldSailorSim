class_name VoyageMap
extends CanvasLayer
## Long Passage as a journey (The Well-Run Ship): while the passage clock
## runs (Simulation.start_passage) the game view fades away and a
## chartplotter-style overview (Real Horizon: dark sea, muted land, the track
## sailed in instrument cyan) shows the voyage instead. The boat follows its planned
## route (the real path, Date Line and canals included: the line is the
## voyage's own route, the boat its real position), with the start, the
## destination, the date, the distance to go and the arrival estimate.
##
## Presentation only. The simulation is Simulation's, unchanged: the same
## timeline, advanced in chunks that stop at the first event, so the voyage,
## weather, stores and wear are exactly those of normal time. When the
## passage stops by itself (an event, arrival) the atlas says why and where,
## and offers "Back aboard" (manual control) or "Sail on" (resume the
## passage where it stopped). "Take the helm" returns to normal time at any
## moment.
##
## Light on the computer: while the atlas shows, the boat scene and the HUD
## below are hidden and not processed (nothing races along unseen), the land
## is one cached triangle batch drawn only when the view changes, and the
## route and boat redraw a few times a second.

signal closed

const LAYER := 15
const FADE_SECONDS := 0.6
## Redraws of the route and boat per real second.
const TRACK_FPS := 12.0
## The smallest part of the world shown (unit-square widths: 360° = 1).
const MIN_SPAN := 0.06
const MARGIN := 0.18

## The overview chart: a dark display chart by day, dimmed further at night.
const SEA_DAY := Color("#1C3340")
const SEA_NIGHT := Color("#0D1A21")
const LAND_DAY := Color("#46524D")
const LAND_NIGHT := Color("#29332F")
## A faint graticule every GRID_DEGREES.
const GRID_DEGREES := 10.0

## Set by App before adding: hidden and paused while the atlas shows.
var screen: Node
var hud_layer: CanvasLayer
var hud: Control

var _veil: ColorRect
var _paper: ColorRect
var _land: Control
var _track: Control
var _panel: PanelContainer
var _title: Label
var _when: Label
var _distance: Label
var _progress: ProgressBar
var _stop_box: VBoxContainer
var _stop_text: Label
var _sail_on: Button
var _rate_buttons: Array[Button] = []
## Route in unwrapped unit coordinates (x may run past 0..1 across the Date Line).
var _route := PackedVector2Array()
var _cumulative := PackedFloat64Array()
## Unit coordinates -> screen: screen = unit * _scale + _offset.
var _scale := Vector2.ONE
var _offset := Vector2.ZERO
var _route_key := ""
var _redraw_left := 0.0
var _closing := false
var _hidden_screen: Node


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = TimePassage.NIGHT_INK
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_veil)
	_paper = ColorRect.new()
	_paper.name = "Atlas"
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_STOP
	_paper.modulate.a = 0.0
	add_child(_paper)
	_land = Control.new()
	_land.name = "Land"
	_land.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_land.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_land.draw.connect(_draw_land)
	_paper.add_child(_land)
	_track = Control.new()
	_track.name = "Track"
	_track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.draw.connect(_draw_track)
	_paper.add_child(_track)
	_build_panel()
	_veil.modulate.a = 0.0
	Simulation.passage_interrupted.connect(_on_interrupted)
	GameSession.state_replaced.connect(close_now)
	GameSession.rescued.connect(_on_rescued)
	UiTheme.palette_changed.connect(_on_palette_changed)
	get_viewport().size_changed.connect(_fit)
	_on_palette_changed()
	_open()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"SidebarPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 28.0
	_panel.offset_bottom = -28.0
	_panel.custom_minimum_size = Vector2(440, 0)
	_paper.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	_panel.add_child(box)
	_title = _add_label(box, "Title", &"HeaderLabel")
	_when = _add_label(box, "When", &"Label")
	_distance = _add_label(box, "Distance", &"MutedLabel")
	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 10)
	box.add_child(_progress)
	_stop_box = VBoxContainer.new()
	_stop_box.name = "Stopped"
	_stop_box.visible = false
	box.add_child(_stop_box)
	_stop_text = _add_label(_stop_box, "Reason", &"WarningLabel")
	_stop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stop_row := HBoxContainer.new()
	stop_row.add_theme_constant_override(&"separation", 6)
	_stop_box.add_child(stop_row)
	_add_button(stop_row, "BackAboard", "Back aboard", "Return to the boat and see to it.").pressed.connect(take_the_helm)
	_sail_on = _add_button(stop_row, "SailOn", "Sail on", "Resume the passage from here.")
	_sail_on.pressed.connect(func() -> void: _set_rate(Simulation.PASSAGE_RATES[0] if _last_rate <= 0.0 else _last_rate))
	var row := HBoxContainer.new()
	row.name = "Speeds"
	row.add_theme_constant_override(&"separation", 6)
	box.add_child(row)
	for i in Simulation.PASSAGE_RATES.size():
		var rate: float = Simulation.PASSAGE_RATES[i]
		var button := _add_button(row, "Rate%d" % i, PassagePanel.RATE_LABELS[i], Loc.n("Let %d hour pass every second.", "Let %d hours pass every second.",
			roundi(rate / 3600.0)) % roundi(rate / 3600.0))
		button.toggle_mode = true
		button.pressed.connect(_set_rate.bind(rate))
		_rate_buttons.append(button)
	_add_button(row, "TakeHelm", "Take the helm", "Back to normal time, aboard.").pressed.connect(take_the_helm)


func _add_label(parent: Node, node_name: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	parent.add_child(label)
	return label


func _add_button(parent: Node, node_name: String, text: String, tip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


var _last_rate := 0.0


func _set_rate(rate: float) -> void:
	var error := Simulation.start_passage(rate)
	if error.is_empty():
		_last_rate = rate
		_stop_box.visible = false
	else:
		_stop_text.text = error
		_stop_box.visible = true
		_sail_on.visible = false
	_refresh()


# --- Opening and closing -----------------------------------------------------------------------

func _open() -> void:
	_last_rate = Simulation.passage_rate
	_open_tween = create_tween()
	_open_tween.tween_property(_veil, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	_open_tween.tween_callback(_hide_game)
	_open_tween.tween_property(_paper, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE)


var _open_tween: Tween


## Hides the game below and stops its processing (it is not seen).
func _hide_game() -> void:
	if _closing:
		return
	_fit()
	_hidden_screen = screen if is_instance_valid(screen) else null
	if _hidden_screen:
		_hidden_screen.process_mode = Node.PROCESS_MODE_DISABLED
		if _hidden_screen is CanvasItem:
			(_hidden_screen as CanvasItem).visible = false
	if hud_layer:
		hud_layer.visible = false
	if hud:
		hud.process_mode = Node.PROCESS_MODE_DISABLED


func _show_game() -> void:
	if is_instance_valid(_hidden_screen):
		_hidden_screen.process_mode = Node.PROCESS_MODE_INHERIT
		if _hidden_screen is CanvasItem:
			(_hidden_screen as CanvasItem).visible = true
	_hidden_screen = null
	if hud_layer:
		hud_layer.visible = true
	if hud:
		hud.process_mode = Node.PROCESS_MODE_INHERIT


## Back to normal time and aboard (the captain's choice).
func take_the_helm() -> void:
	Simulation.stop_passage()
	close()


## Fades back to the game.
func close() -> void:
	if _closing:
		return
	_closing = true
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()  # closed while still opening: the game was maybe never hidden
	var tween := create_tween()
	tween.tween_property(_paper, "modulate:a", 0.0, FADE_SECONDS * 0.7)
	tween.tween_callback(_show_game)
	tween.tween_property(_veil, "modulate:a", 0.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_finish)


func _on_rescued(_info: Dictionary) -> void:
	close_now()


## At once (a load, a rescue, another screen): the game is shown again now.
func close_now() -> void:
	if _closing and not is_inside_tree():
		return
	_closing = true
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	_show_game()
	_finish()


func _finish() -> void:
	closed.emit()
	queue_free()


func is_closing() -> bool:
	return _closing


# --- Interruptions -------------------------------------------------------------------------------

func _on_interrupted(reason: StringName, text: String) -> void:
	if _closing:
		return
	# The HUD's passage panel adds the fish that nibbled on the way: read it after.
	await get_tree().process_frame
	if not is_instance_valid(self) or _closing:
		return
	var said := text
	if hud and hud.get("passage_panel") and hud.passage_panel.get_stopped_text().begins_with("Normal time: "):
		said = hud.passage_panel.get_stopped_text().trim_prefix("Normal time: ")
	_stop_text.text = said
	_stop_box.visible = true
	_sail_on.visible = reason not in [Simulation.STOP_ARRIVAL, Simulation.STOP_RESCUE, Simulation.STOP_ENDED, Simulation.STOP_ANCHORAGE] \
		and GameSession.is_underway()
	_refresh()
	_track.queue_redraw()


func get_stop_text() -> String:
	return _stop_text.text if _stop_box.visible else ""


func is_stopped() -> bool:
	return _stop_box.visible


# --- Every frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _closing or not GameSession.is_active():
		return
	_redraw_left -= delta
	if _redraw_left > 0.0:
		return
	_redraw_left = 1.0 / TRACK_FPS
	_refresh()
	_track.queue_redraw()


func _refresh() -> void:
	var voyage := GameSession.get_voyage()
	var catalog := PortCatalog.get_default()
	var destination_id: StringName = voyage.route.destination_port_id if voyage else GameSession.get_location_id()
	_title.text = Loc.t("Long passage to %s") % catalog.get_display_name(destination_id)
	_when.text = "%s  ·  %s" % [TimePassage.date_text(GameSession.get_game_time()), Simulation.format_game_time(GameSession.get_game_time()).get_slice(", ", 1)]
	if voyage and GameSession.is_underway():
		var remaining := GameSession.get_voyage_remaining_nm()
		var total := GameSession.get_voyage_total_nm()
		_distance.text = Loc.t("%s nm to go  ·  arriving about %s") % [PassagePanel._thousands(roundi(remaining)),
			Simulation.format_game_time(Simulation.get_eta())]
		_progress.value = 100.0 * (1.0 - remaining / total) if total > 0.0 else 100.0
		_update_route(voyage)
	else:
		_distance.text = "Arrived."
		_progress.value = 100.0
	for i in _rate_buttons.size():
		_rate_buttons[i].set_pressed_no_signal(is_equal_approx(Simulation.passage_rate, Simulation.PASSAGE_RATES[i]))
		_rate_buttons[i].disabled = not GameSession.is_underway()


# --- The atlas --------------------------------------------------------------------------------------

func _on_palette_changed() -> void:
	_paper.color = SEA_DAY.lerp(SEA_NIGHT, UiTheme.blend)
	_land.self_modulate = LAND_DAY.lerp(LAND_NIGHT, UiTheme.blend)
	_land.queue_redraw()
	_track.queue_redraw()


## The route in unit coordinates, unwrapped across the Date Line (each point
## within half a world of the one before).
func _update_route(voyage: Voyage) -> void:
	var key := "%d|%d" % [voyage.revision, voyage.route.path.size()]
	if key == _route_key:
		return
	_route_key = key
	_route = unwrap(voyage.route.path)
	_cumulative = voyage.get_cumulative()
	_fit()


static func unwrap(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var shift := 0.0
	for i in path.size():
		var u := CabinWorldMap.to_unit(path[i])
		if i > 0:
			var x := u.x + shift
			while x - out[i - 1].x > 0.5:
				shift -= 1.0
				x -= 1.0
			while out[i - 1].x - x > 0.5:
				shift += 1.0
				x += 1.0
			u.x = x
		out.append(u)
	return out


## Fits the route (with some sea around it) into the screen, keeping the
## chart's proportions.
func _fit() -> void:
	if _route.is_empty():
		var voyage := GameSession.get_voyage()
		if voyage == null:
			return
		_route = unwrap(voyage.route.path)
		_cumulative = voyage.get_cumulative()
	var bounds := Rect2(_route[0], Vector2.ZERO)
	for p in _route:
		bounds = bounds.expand(p)
	var aspect := CabinWorldMap.aspect()  # unit width / unit height on paper
	var size := Vector2(maxf(bounds.size.x, MIN_SPAN), maxf(bounds.size.y, MIN_SPAN * aspect))
	size *= 1.0 + MARGIN * 2.0
	var view := get_viewport().get_visible_rect().size
	# The panel sits bottom left: keep the route a little up and to the right.
	var area := Rect2(Vector2(view.x * 0.04, view.y * 0.05), Vector2(view.x * 0.92, view.y * 0.72))
	var k := minf(area.size.x / size.x, area.size.y * aspect / size.y)
	_scale = Vector2(k, k / aspect)
	var centre := bounds.get_center()
	_offset = area.get_center() - centre * _scale
	_land.queue_redraw()
	_track.queue_redraw()


func to_screen(unit: Vector2) -> Vector2:
	return unit * _scale + _offset


## The land: the cabin map's cached triangles, drawn three times (the world
## to the west and east as well, for voyages across the Date Line).
func _draw_land() -> void:
	var triangles := CabinWorldMap.land_triangles()
	if triangles.is_empty():
		return
	var indices := CabinWorldMap.land_indices()
	var colours := CabinWorldMap.land_colours()
	for copy in [-1.0, 0.0, 1.0]:
		_land.draw_set_transform(_offset + Vector2(copy * _scale.x, 0.0), 0.0, _scale)
		RenderingServer.canvas_item_add_triangle_array(_land.get_canvas_item(), indices, triangles, colours)
	_land.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_track() -> void:
	if _route.size() < 2:
		return
	var ink := UiTheme.color(&"ink")
	var cyan := UiTheme.color(&"accent")
	var points := PackedVector2Array()
	points.resize(_route.size())
	for i in _route.size():
		points[i] = to_screen(_route[i])
	var progress := GameSession.get_voyage_progress_nm() if GameSession.is_underway() else (_cumulative[-1] if not _cumulative.is_empty() else 0.0)
	var boat := _boat_unit(progress)
	var split := GeoMath.segment_index_at(_cumulative, progress) if _cumulative.size() == _route.size() else 1
	_draw_graticule()
	# Ahead: a dashed white route; behind: the track sailed, solid cyan.
	for i in range(split, points.size()):
		var a := to_screen(boat) if i == split else points[i - 1]
		_track.draw_dashed_line(a, points[i], Color(ink, 0.75), 1.5, 8.0)
	var done := PackedVector2Array(points.slice(0, split))
	done.append(to_screen(boat))
	if done.size() >= 2:
		_track.draw_polyline(done, cyan, 2.5, true)
	# Start and destination.
	var catalog := PortCatalog.get_default()
	var voyage := GameSession.get_voyage()
	if voyage:
		_draw_port(points[0], catalog.get_display_name(voyage.route.origin_port_id), ink)
		_draw_port(points[-1], catalog.get_display_name(voyage.route.destination_port_id), ink)
	# The boat: a small hull pointing along the course.
	var at := to_screen(boat)
	var ahead := points[mini(split, points.size() - 1)]
	var dir := (ahead - at).normalized() if ahead.distance_to(at) > 0.5 else Vector2.RIGHT
	var side := dir.orthogonal()
	var hull := PackedVector2Array([at + dir * 13.0, at + side * 6.0 - dir * 7.0, at - dir * 9.0, at - side * 6.0 - dir * 7.0])
	_track.draw_arc(at, 15.0, 0.0, TAU, 32, Color(cyan, 0.45), 1.0, true)
	_track.draw_line(at + dir * 9.0, at + dir * 34.0, Color(cyan, 0.8), 1.5, true)  # heading line
	_track.draw_colored_polygon(hull, UiTheme.color(&"title"))
	_track.draw_polyline(PackedVector2Array([hull[0], hull[1], hull[2], hull[3], hull[0]]), UiTheme.color(&"surface_sunken"), 1.5, true)
	if is_stopped():
		_track.draw_arc(at, 22.0, 0.0, TAU, 32, Color(UiTheme.color(&"warning"), 0.9), 2.0, true)


## Faint meridians and parallels (every GRID_DEGREES) under the route.
func _draw_graticule() -> void:
	var view := _track.size
	var colour := Color(UiTheme.color(&"ink_soft"), 0.12)
	var lon := -540.0  # the world and its copies east and west (unit x is linear in longitude)
	while lon <= 540.0:
		var x := to_screen(Vector2((lon + 180.0) / 360.0, 0.0)).x
		if x >= 0.0 and x <= view.x:
			_track.draw_line(Vector2(x, 0.0), Vector2(x, view.y), colour, 1.0)
		lon += GRID_DEGREES
	var lat := -80.0
	while lat <= 80.0:
		var y := to_screen(CabinWorldMap.to_unit(Vector2(0.0, lat))).y
		if y >= 0.0 and y <= view.y:
			_track.draw_line(Vector2(0.0, y), Vector2(view.x, y), colour, 1.0)
		lat += GRID_DEGREES


func _draw_port(at: Vector2, label: String, ink: Color) -> void:
	_track.draw_circle(at, 6.0, UiTheme.color(&"surface_sunken"))
	_track.draw_arc(at, 6.0, 0.0, TAU, 20, ink, 1.5, true)
	_track.draw_circle(at, 2.5, UiTheme.color(&"accent"))
	var font := ThemeDB.fallback_font if UiTheme.theme == null else UiTheme.theme.default_font
	_track.draw_string_outline(font, at + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(_paper.color, 0.9))
	_track.draw_string(font, at + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)


## The boat's position on the unwrapped route (its real position, placed on
## the copy of the world the route is drawn in).
func _boat_unit(progress: float) -> Vector2:
	var u := CabinWorldMap.to_unit(GameSession.get_vessel_position())
	if _route.is_empty() or _cumulative.size() != _route.size():
		return u
	var i := GeoMath.segment_index_at(_cumulative, progress)
	var reference := _route[i - 1]
	while u.x - reference.x > 0.5:
		u.x -= 1.0
	while reference.x - u.x > 0.5:
		u.x += 1.0
	return u


func get_boat_screen_position() -> Vector2:
	return to_screen(_boat_unit(GameSession.get_voyage_progress_nm() if GameSession.is_underway() else 0.0))


func get_route_screen_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _route:
		out.append(to_screen(p))
	return out
