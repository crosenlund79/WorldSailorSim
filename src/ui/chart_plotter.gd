class_name ChartPlotter
extends Control
## The chartplotter's screen (Iteration 17; I026: the helm plotter). A
## north-up plotter: the boat and its heading at the centre, the nearby
## coastline, the course being sailed, its next turn and the wind at the
## boat. Since I026 it is no longer a HUD panel: it is the screen of the
## chartplotter mounted at the helm, shown enlarged in the focused
## PlotterView (P, the action wheel, or the plotter itself at the helm),
## inside the fitted instrument package's bezel.
##
## Lightweight and bounded: it never builds the world chart. The coast is a
## small land/sea raster (RASTER x RASTER cells over the plotter's range)
## from the navigation grid the router itself uses, so the plotter shows
## exactly the water routes may cross. The raster is rebuilt only when the
## boat has moved REBUILD_FRACTION of the range or the range changes, a few
## rows per frame. The course is the voyage's own path (only its points
## near the boat are drawn). Positions use a local flat projection around
## the boat (nautical miles east/north), fine at these ranges. It only works
## while it is on screen.

## Ranges (nm from the centre to the edge).
const RANGES: Array[float] = [5.0, 12.0, 30.0, 80.0]
const RASTER := 96
const ROWS_PER_FRAME := 8
const REBUILD_FRACTION := 0.2
## Display chart colours (Real Horizon): a dark sea, muted olive-grey land,
## the route in instrument cyan and own ship in white; dimmed at night.
const WATER := Color("#172C37")
const LAND := Color("#4E5A52")
const ROUTE := MarinePalette.INSTRUMENT_CYAN
const BOAT := MarinePalette.DATA_WHITE
const TEXT := Color("#B7C4C6")
const NIGHT_DIM := 0.55
const Instrument := preload("res://src/ui/instrument_draw.gd")

## The range chosen, kept for the game run (not saved).
static var range_index := 1

## The plot's size in pixels and the coast raster's cells a side (set
## before it enters the tree; the focused view uses a finer raster, built
## with the same number of cells a frame).
var plot_size := 260.0
var raster := RASTER

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
	custom_minimum_size = Vector2(plot_size, plot_size)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = Image.create(raster, raster, false, Image.FORMAT_RGBA8)
	_image.fill(WATER)
	_texture = ImageTexture.create_from_image(_image)


func get_range_nm() -> float:
	return RANGES[range_index]


func change_range(step: int) -> void:
	range_index = clampi(range_index + step, 0, RANGES.size() - 1)
	queue_redraw()


## The plotter's data in words: the next turn, the course, the wind and
## the range.
func get_info_text() -> String:
	return _describe()


## True once the coast raster covers the current position and range.
func is_raster_ready() -> bool:
	return _build_row < 0 and _raster_center != Vector2.INF and is_equal_approx(_raster_range, get_range_nm()) \
		and _nm_offset(_raster_center, GameSession.get_vessel_position()).length() < get_range_nm() * REBUILD_FRACTION


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not GameSession.is_active():
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
	queue_redraw()


## A few raster rows per frame (land from the navigation grid).
func _build_rows() -> void:
	if _grid == null:  # loaded on first use, not at start-up (the router's graph is large)
		var router := SeaRouter.get_default()
		_grid = router.grid if router else null
	var end := mini(_build_row + maxi(ROWS_PER_FRAME * RASTER / raster, 2), raster)
	for y in range(_build_row, end):
		for x in raster:
			var offset := Vector2((x + 0.5) / raster * 2.0 - 1.0, 1.0 - (y + 0.5) / raster * 2.0) * _build_range
			var geo := GeoMath.normalize(_geo_at(_build_center, offset))
			var land := _grid != null and _grid.cell_class_at_geo(geo) == NavGrid.LAND
			_image.set_pixel(x, y, LAND if land else WATER)
	_build_row = end
	if _build_row >= raster:
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
	var half := plot_size / 2.0
	return Vector2(half, half) + Vector2(offset_nm.x, -offset_nm.y) / get_range_nm() * half


func _draw() -> void:
	if not GameSession.is_active():
		return
	var dim := 1.0 - NIGHT_DIM * UiTheme.blend
	var shade := func(c: Color) -> Color: return Color(c.r * dim, c.g * dim, c.b * dim, c.a)
	var scale := plot_size / 260.0
	var here := GameSession.get_vessel_position()
	var rect := Rect2(Vector2.ZERO, Vector2(plot_size, plot_size))
	draw_rect(rect, shade.call(WATER))
	if _raster_center != Vector2.INF:
		# The raster where it was built, scaled to the current range.
		var corner := _nm_offset(here, _raster_center) + Vector2(-_raster_range, _raster_range)
		var size := Vector2.ONE * _raster_range * 2.0 / get_range_nm() * plot_size / 2.0
		draw_texture_rect(_texture, Rect2(_to_plot(corner), size), false, Color(dim, dim, dim))
	# Range rings, a bearing ring with fine ticks, and north.
	var centre := rect.get_center()
	var text: Color = shade.call(TEXT)
	draw_arc(centre, plot_size / 4.0, 0.0, TAU, 64, Color(text, 0.25), 1.0, true)
	draw_arc(centre, plot_size / 2.0 - 8.0 * scale, 0.0, TAU, 128, Color(text, 0.18), 1.0, true)
	for i in 36:
		var d := Instrument.dir(i * 10.0)
		var length := (7.0 if i % 3 == 0 else 3.5) * scale
		draw_line(centre + d * (plot_size / 2.0 - 8.0 * scale), centre + d * (plot_size / 2.0 - 8.0 * scale - length),
			Color(text, 0.6 if i % 3 == 0 else 0.35), 1.0, true)
	var font := ThemeDB.fallback_font if UiTheme.theme == null else UiTheme.theme.default_font
	draw_string(font, Vector2(plot_size / 2.0 - 4.0 * scale, 28.0 * scale), Loc.t("N", "compass"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * scale), text)
	draw_string(font, Vector2(plot_size / 2.0 + 4.0 * scale, plot_size / 4.0 + 14.0 * scale), Loc.t("%s nm") % Loc.decimal(get_range_nm() / 2.0, 1 if get_range_nm() < 10.0 else 0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * scale), Color(text, 0.7))
	var voyage := GameSession.get_voyage()
	var route_colour: Color = shade.call(ROUTE)
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
			draw_polyline(points, route_colour, 2.0 * maxf(scale * 0.8, 1.0), true)
		var turn := WorldMap.get_next_turn()
		if not turn.is_empty():
			var at := _to_plot(_nm_offset(here, turn.geo))
			draw_arc(at, 6.0 * scale, 0.0, TAU, 20, route_colour, 1.5 * scale, true)
	# The boat, pointing along its heading (north up), with a heading line.
	var boat: Color = shade.call(BOAT)
	var heading := deg_to_rad(Simulation.get_current_heading()) if GameSession.is_underway() else 0.0
	var forward := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-forward.y, forward.x)
	draw_line(centre + forward * 10.0 * scale, centre + forward * (plot_size / 2.0 - 16.0 * scale), Color(boat, 0.55), 1.0, true)
	draw_colored_polygon(PackedVector2Array([centre + forward * 10.0 * scale, centre - forward * 6.0 * scale + side * 5.5 * scale,
		centre - forward * 3.0 * scale, centre - forward * 6.0 * scale - side * 5.5 * scale]), boat)
	# The wind at the boat (where it blows to), top right.
	var wind := Simulation.get_wind_at(here)
	if wind.speed_kn >= 0.5:
		var to := deg_to_rad(wind.from_deg + 180.0)
		var d := Vector2(sin(to), -cos(to))
		var base := Vector2(plot_size - 26.0 * scale, 26.0 * scale)
		var colour: Color = shade.call(WindLayer.color_for(wind.speed_kn))
		draw_line(base - d * 12.0 * scale, base + d * 12.0 * scale, colour, 3.0 * scale)
		draw_colored_polygon(PackedVector2Array([base + d * 16.0 * scale, base + d * 6.0 * scale + Vector2(-d.y, d.x) * 6.0 * scale,
			base + d * 6.0 * scale - Vector2(-d.y, d.x) * 6.0 * scale]), colour)


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
