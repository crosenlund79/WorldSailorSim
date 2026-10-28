class_name ChartPlotter
extends PanelContainer
## The cockpit chartplotter (Iteration 17): a small north-up plotter on deck
## while underway. The boat and its heading at the centre, the nearby
## coastline, the course being sailed, its next turn with distance and course,
## and the wind at the boat. Toggled with P or from the action wheel.
##
## Lightweight and bounded: it never builds the world chart. The coast is a
## small land/sea raster (RASTER x RASTER cells over the plotter's range)
## from the navigation grid the router itself uses, so the plotter shows
## exactly the water routes may cross. The raster is rebuilt only when the
## boat has moved REBUILD_FRACTION of the range or the range changes, a few
## rows per frame. The course is the voyage's own path (only its points
## near the boat are drawn). Positions use a local flat projection around
## the boat (nautical miles east/north), fine at these ranges.

## Ranges (nm from the centre to the edge).
const RANGES: Array[float] = [5.0, 12.0, 30.0, 80.0]
const RASTER := 96
const ROWS_PER_FRAME := 8
const REBUILD_FRACTION := 0.2
const PLOT_SIZE := 260.0
## Display chart colours (Real Horizon): a dark sea, muted olive-grey land,
## the route in instrument cyan and own ship in white.
const WATER := Color("#172C37")
const LAND := Color("#4E5A52")
const ROUTE := MarinePalette.INSTRUMENT_CYAN
const BOAT := MarinePalette.DATA_WHITE
const TEXT := Color("#B7C4C6")
const Instrument := preload("res://src/ui/instrument_draw.gd")

## Shown or not, kept for the game run (not saved).
static var shown := false
static var range_index := 1
## Whether the captain is on deck (set by the HUD): only shown there.
var on_deck := Callable()

var _plot: Control
var _info: Label
var _image: Image
var _texture: ImageTexture
var _raster_center := Vector2.INF
var _raster_range := 0.0
var _build_row := -1
var _build_center := Vector2.ZERO
var _build_range := 0.0
var _grid: NavGrid


func _ready() -> void:
	name = "ChartPlotter"
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Chartplotter"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for spec in [["ZoomIn", "+", -1], ["ZoomOut", "–", 1]]:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Closer" if spec[2] < 0 else "Farther"
		button.pressed.connect(change_range.bind(spec[2]))
		header.add_child(button)
	_plot = Control.new()
	_plot.name = "Plot"
	_plot.custom_minimum_size = Vector2(PLOT_SIZE, PLOT_SIZE)
	_plot.clip_contents = true
	_plot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plot.draw.connect(_draw_plot)
	box.add_child(_plot)
	_info = Label.new()
	_info.name = "Info"
	_info.add_theme_font_size_override(&"font_size", 16)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(PLOT_SIZE, 0)
	box.add_child(_info)
	_image = Image.create(RASTER, RASTER, false, Image.FORMAT_RGBA8)
	_image.fill(WATER)
	_texture = ImageTexture.create_from_image(_image)
	visible = false


func should_show() -> bool:
	return shown and GameSession.is_active() and GameSession.is_underway() and (not on_deck.is_valid() or on_deck.call())


func get_range_nm() -> float:
	return RANGES[range_index]


func change_range(step: int) -> void:
	range_index = clampi(range_index + step, 0, RANGES.size() - 1)
	_plot.queue_redraw()


func get_info_text() -> String:
	return _info.text


## True once the coast raster covers the current position and range.
func is_raster_ready() -> bool:
	return _build_row < 0 and _raster_center != Vector2.INF and is_equal_approx(_raster_range, get_range_nm()) \
		and _nm_offset(_raster_center, GameSession.get_vessel_position()).length() < get_range_nm() * REBUILD_FRACTION


func _process(_delta: float) -> void:
	visible = should_show()
	if not visible:
		return
	var here := GameSession.get_vessel_position()
	var range_nm := get_range_nm()
	if _build_row < 0 and (_raster_center == Vector2.INF or not is_equal_approx(_raster_range, range_nm)
			or _nm_offset(_raster_center, here).length() >= range_nm * REBUILD_FRACTION):
		_build_row = 0
		_build_center = here
		_build_range = range_nm
	if _build_row >= 0:
		_build_rows()
	_info.text = _describe()
	_plot.queue_redraw()


## A few raster rows per frame (land from the navigation grid).
func _build_rows() -> void:
	if _grid == null:  # loaded on first use, not at start-up (the router's graph is large)
		var router := SeaRouter.get_default()
		_grid = router.grid if router else null
	var end := mini(_build_row + ROWS_PER_FRAME, RASTER)
	for y in range(_build_row, end):
		for x in RASTER:
			var offset := Vector2((x + 0.5) / RASTER * 2.0 - 1.0, 1.0 - (y + 0.5) / RASTER * 2.0) * _build_range
			var geo := GeoMath.normalize(_geo_at(_build_center, offset))
			var land := _grid != null and _grid.cell_class_at_geo(geo) == NavGrid.LAND
			_image.set_pixel(x, y, LAND if land else WATER)
	_build_row = end
	if _build_row >= RASTER:
		_build_row = -1
		_raster_center = _build_center
		_raster_range = _build_range
		_texture.update(_image)


## Nautical miles east and north of `origin` to `geo` (local flat projection).
static func _nm_offset(origin: Vector2, geo: Vector2) -> Vector2:
	var dlon := wrapf(geo.x - origin.x, -180.0, 180.0)
	return Vector2(dlon * 60.0 * cos(deg_to_rad(origin.y)), (geo.y - origin.y) * 60.0)


static func _geo_at(origin: Vector2, offset_nm: Vector2) -> Vector2:
	return Vector2(origin.x + offset_nm.x / (60.0 * maxf(cos(deg_to_rad(origin.y)), 0.05)), origin.y + offset_nm.y / 60.0)


## Plot coordinates (pixels) of a position `offset_nm` from the centre.
func _to_plot(offset_nm: Vector2) -> Vector2:
	var half := PLOT_SIZE / 2.0
	return Vector2(half, half) + Vector2(offset_nm.x, -offset_nm.y) / get_range_nm() * half


func _draw_plot() -> void:
	var here := GameSession.get_vessel_position()
	var rect := Rect2(Vector2.ZERO, Vector2(PLOT_SIZE, PLOT_SIZE))
	_plot.draw_rect(rect, WATER)
	if _raster_center != Vector2.INF:
		# The raster where it was built, scaled to the current range.
		var corner := _nm_offset(here, _raster_center) + Vector2(-_raster_range, _raster_range)
		var size := Vector2.ONE * _raster_range * 2.0 / get_range_nm() * PLOT_SIZE / 2.0
		_plot.draw_texture_rect(_texture, Rect2(_to_plot(corner), size), false)
	# Range rings, a bearing ring with fine ticks, and north.
	var centre := rect.get_center()
	_plot.draw_arc(centre, PLOT_SIZE / 4.0, 0.0, TAU, 48, Color(TEXT, 0.25), 1.0, true)
	_plot.draw_arc(centre, PLOT_SIZE / 2.0 - 8.0, 0.0, TAU, 96, Color(TEXT, 0.18), 1.0, true)
	for i in 36:
		var d := Instrument.dir(i * 10.0)
		var length := 7.0 if i % 3 == 0 else 3.5
		_plot.draw_line(centre + d * (PLOT_SIZE / 2.0 - 8.0), centre + d * (PLOT_SIZE / 2.0 - 8.0 - length), Color(TEXT, 0.6 if i % 3 == 0 else 0.35), 1.0, true)
	var font := ThemeDB.fallback_font if UiTheme.theme == null else UiTheme.theme.default_font
	_plot.draw_string(font, Vector2(PLOT_SIZE / 2.0 - 4.0, 28.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
	var voyage := GameSession.get_voyage()
	if voyage and voyage.route and voyage.route.path.size() >= 2:
		var points := PackedVector2Array()
		var path := voyage.route.path
		var cumulative := voyage.get_cumulative()
		var from := maxi(GeoMath.segment_index_at(cumulative, voyage.progress_nm) - 1, 0)
		points.append(_to_plot(_nm_offset(here, voyage.get_position())))
		for i in range(from + 1, path.size()):
			var offset := _nm_offset(here, path[i])
			points.append(_to_plot(offset))
			if offset.length() > get_range_nm() * 3.0:
				break  # far beyond the edge: the rest is not drawn
		if points.size() >= 2:
			_plot.draw_polyline(points, ROUTE, 2.0, true)
		var turn := WorldMap.get_next_turn()
		if not turn.is_empty():
			var at := _to_plot(_nm_offset(here, turn.geo))
			_plot.draw_arc(at, 6.0, 0.0, TAU, 20, ROUTE, 1.5, true)
	# The boat, pointing along its heading (north up), with a heading line.
	var heading := deg_to_rad(Simulation.get_current_heading())
	var forward := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-forward.y, forward.x)
	_plot.draw_line(centre + forward * 10.0, centre + forward * (PLOT_SIZE / 2.0 - 16.0), Color(BOAT, 0.55), 1.0, true)
	_plot.draw_colored_polygon(PackedVector2Array([centre + forward * 10.0, centre - forward * 6.0 + side * 5.5,
		centre - forward * 3.0, centre - forward * 6.0 - side * 5.5]), BOAT)
	# The wind at the boat (where it blows to), top right.
	var wind := Simulation.get_wind_at(here)
	if wind.speed_kn >= 0.5:
		var to := deg_to_rad(wind.from_deg + 180.0)
		var d := Vector2(sin(to), -cos(to))
		var base := Vector2(PLOT_SIZE - 26.0, 26.0)
		_plot.draw_line(base - d * 12.0, base + d * 12.0, WindLayer.color_for(wind.speed_kn), 3.0)
		_plot.draw_colored_polygon(PackedVector2Array([base + d * 16.0, base + d * 6.0 + Vector2(-d.y, d.x) * 6.0,
			base + d * 6.0 - Vector2(-d.y, d.x) * 6.0]), WindLayer.color_for(wind.speed_kn))
	_plot.draw_rect(rect.grow(-0.5), Color(TEXT, 0.35), false, 1.0)


func _describe() -> String:
	var wind := Simulation.get_wind_at(GameSession.get_vessel_position())
	var lines := PackedStringArray()
	var turn := WorldMap.get_next_turn()
	if GameSession.is_anchored():
		lines.append(Loc.t("At anchor"))
	elif turn.is_empty():
		lines.append(Loc.t("No course"))
	elif float(turn.next_course) < 0.0:
		lines.append(Loc.format("Destination %.1f nm  ·  course %03d°", [float(turn.nm), roundi(turn.course)]))
	else:
		lines.append(Loc.format("Next turn %.1f nm  ·  then %03d°", [float(turn.nm), roundi(turn.next_course)]))
		lines.append(Loc.t("Course now %03d°") % roundi(turn.course))
	lines.append(Loc.t("%s  ·  range %d nm") % [Hud.describe_wind(wind), roundi(get_range_nm())])
	return "\n".join(lines)
