extends RefCounted
## Marine electronics (I026 stage 03): how the instruments look. Static
## drawing for the three packages (InstrumentPackage), used at any size by
## the HUD's InstrumentCluster, the focused InstrumentView and the
## PlotterView's bezel. Everything is drawn from one InstrumentData reading;
## nothing here reads the game.
##
## Used with preload (no class_name): const Face := preload("res://src/electronics/instrument_face.gd")
##
## The units:
##   Classic   dial_speed, dial_heading, dial_wind: round analogue dials in a
##             satin housing, warm ivory markings, a red needle and a small
##             LCD window; lcd: the LCD repeater (route, next turn, weather,
##             trim) in grey-green early-digital glass. Red at night.
##   Modern    page: a square colour display, one page at a time (speed,
##             heading, wind, route, turn, weather, trim). Red at night.
##   Offshore  mfd: a wide multifunction display with layouts (overview,
##             sailing, navigation, weather). Dimmed at night.
## A unit's size sets its scale (BASE is the HUD size of a dial or display),
## and every text shrinks to fit its place (long Danish words included).
##
## Instrument angles are degrees: 0 at the top, clockwise.

const BASE := 118.0
const FONT_PATHS := {&"digits": "res://assets/fonts/Barlow-SemiBold.ttf", &"condensed": "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
	&"condensed_medium": "res://assets/fonts/BarlowCondensed-Medium.ttf", &"body": "res://assets/fonts/Barlow-Medium.ttf"}
## The classic close-hauled sectors on a wind dial (red to port, green to starboard).
const PORT_RED := Color("#B5483A")
const STARBOARD_GREEN := Color("#4C9A6A")

static var _fonts := {}


static func font(kind: StringName) -> Font:
	if not _fonts.has(kind):
		_fonts[kind] = load(FONT_PATHS.get(kind, FONT_PATHS[&"body"]))
	return _fonts[kind]


## An instrument caption, translated (context "instrument").
static func cap(text: String) -> String:
	return Loc.t(text, "instrument")


static func dir(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(sin(a), -cos(a))


# --- Text ---------------------------------------------------------------------------------------

## The size `text` takes at most `max_width` wide (never below 6 px).
static func fit_size(text: String, kind: StringName, size: float, max_width: float) -> int:
	var f := font(kind)
	var s := maxi(roundi(size), 6)
	while max_width > 0.0 and s > 6 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_width:
		s -= 1
	return s


## Text with its capitals centred on `center` (shrunk to `max_width`).
static func text_at(ci: CanvasItem, center: Vector2, text: String, size: float, colour: Color, kind: StringName = &"condensed",
		max_width := 0.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	if text.is_empty():
		return
	if size < 13.0:
		text = text.replace(" ", "  ")  # the condensed face's space all but vanishes when small
	var f := font(kind)
	var s := fit_size(text, kind, size, max_width)
	var width := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var x := center.x - width / 2.0
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		x = center.x
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = center.x - width
	ci.draw_string(f, Vector2(x, center.y + s * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, colour)


## A big figure with a small unit after it, the pair centred on `center`.
static func figure(ci: CanvasItem, center: Vector2, value: String, unit: String, size: float, colour: Color, unit_colour: Color,
		max_width := 0.0, kind: StringName = &"digits") -> void:
	var f := font(kind)
	var uf := font(&"condensed")
	var s := float(maxi(roundi(size), 6))
	var us := maxf(s * 0.34, 7.0)
	var gap := s * 0.08 if not unit.is_empty() else 0.0
	var total := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s)).x + gap + (uf.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(us)).x if not unit.is_empty() else 0.0)
	while max_width > 0.0 and total > max_width and s > 8.0:
		s -= 1.0
		us = maxf(s * 0.34, 7.0)
		gap = s * 0.08 if not unit.is_empty() else 0.0
		total = f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s)).x + gap + (uf.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(us)).x if not unit.is_empty() else 0.0)
	var x := center.x - total / 2.0
	var baseline := center.y + s * 0.36
	ci.draw_string(f, Vector2(x, baseline), value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s), colour)
	if not unit.is_empty():
		var vx := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s)).x
		ci.draw_string(uf, Vector2(x + vx + gap, baseline), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, int(us), unit_colour)


# --- Shapes -------------------------------------------------------------------------------------

## A rounded box (a housing, a screen, a key).
static func box(ci: CanvasItem, rect: Rect2, fill: Color, radius := 3.0, border := Color.TRANSPARENT, border_width := 0.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(maxi(roundi(radius), 0))
	style.anti_aliasing = true
	if border_width > 0.0:
		style.border_color = border
		style.set_border_width_all(maxi(roundi(border_width), 1))
	style.draw(ci.get_canvas_item(), rect)


## The unit's housing: a soft shadow below, the moulded case, a lit top edge.
static func housing(ci: CanvasItem, rect: Rect2, package: InstrumentPackage, night: float, radius: float) -> void:
	var s := rect.size.y / BASE
	box(ci, Rect2(rect.position + Vector2(0.0, 2.5 * s), rect.size), Color(0, 0, 0, 0.38), radius + 1.0)
	box(ci, rect, package.colour_at("housing", night * 0.6), radius, package.colour_at("housing_edge", night * 0.7).darkened(0.25), maxf(1.0, s))
	ci.draw_line(rect.position + Vector2(radius, 1.5), Vector2(rect.end.x - radius, rect.position.y + 1.5), Color(1, 1, 1, 0.12 * (1.0 - night * 0.7)), 1.0, true)


## Display glass: the screen colour and a faint daylight reflection.
static func glass(ci: CanvasItem, rect: Rect2, colour: Color, radius: float, night: float) -> void:
	box(ci, rect, colour, radius)
	var a := 0.05 * (1.0 - night)
	if a > 0.001:
		var top := rect.grow(-maxf(radius * 0.5, 1.0))
		var lit := Color(1, 1, 1, a)
		var clear := Color(1, 1, 1, 0.0)
		ci.draw_polygon(PackedVector2Array([top.position, Vector2(top.end.x, top.position.y), Vector2(top.end.x, top.position.y + top.size.y * 0.45),
			Vector2(top.position.x, top.position.y + top.size.y * 0.45)]), PackedColorArray([lit, Color(lit, a * 0.4), clear, clear]))


## A boat seen from above, pointing up, `length` long.
static func boat_outline(center: Vector2, length: float, angle_deg := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in [Vector2(0, -0.5), Vector2(0.16, -0.22), Vector2(0.18, 0.12), Vector2(0.13, 0.5), Vector2(-0.13, 0.5), Vector2(-0.18, 0.12), Vector2(-0.16, -0.22)]:
		points.append(center + (p * length).rotated(deg_to_rad(angle_deg)))
	return points


static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var copy := points.duplicate()
	copy.append(points[0])
	return copy


static func ticks(ci: CanvasItem, center: Vector2, r: float, from_deg: float, to_deg: float, step: float, major_every: int,
		minor_len: float, major_len: float, colour: Color, width := 1.0) -> void:
	var n := int(round((to_deg - from_deg) / step))
	for i in n + 1:
		var deg := from_deg + i * step
		if i == n and n > 0 and is_equal_approx(fposmod(to_deg - from_deg, 360.0), 0.0):
			break
		var major := major_every > 0 and i % major_every == 0
		var d := dir(deg)
		ci.draw_line(center + d * r, center + d * (r - (major_len if major else minor_len)), colour if major else Color(colour, colour.a * 0.6),
			width * (1.6 if major else 1.0), true)


static func arc(ci: CanvasItem, center: Vector2, r: float, from_deg: float, to_deg: float, colour: Color, width: float) -> void:
	var points := maxi(int(absf(to_deg - from_deg) / 3.0), 6)
	ci.draw_arc(center, r, deg_to_rad(from_deg - 90.0), deg_to_rad(to_deg - 90.0), points, colour, width, true)


static func needle(ci: CanvasItem, center: Vector2, deg: float, length: float, colour: Color, width: float, hub: Color) -> void:
	var d := dir(deg)
	var side := d.orthogonal() * width * 0.5
	var tail := center - d * length * 0.18
	ci.draw_colored_polygon(PackedVector2Array([center + d * length, tail + side * 1.4, tail - side * 1.4]), Color(0, 0, 0, 0.35))
	ci.draw_colored_polygon(PackedVector2Array([center + d * length, center + side * 1.2 - d * length * 0.02, tail, center - side * 1.2 - d * length * 0.02]), colour)
	ci.draw_circle(center, width * 1.6, hub)
	ci.draw_circle(center, width * 0.7, Color(colour, 0.9))


# --- Values on the displays ---------------------------------------------------------------------

static func speed_text(data: InstrumentData) -> String:
	return Loc.decimal(data.speed_kn, 1)


static func heading_text(data: InstrumentData) -> String:
	return "%03d°" % roundi(fposmod(data.heading_deg, 360.0)) if data.underway and not data.anchored and not data.holding else "---"


static func wind_speed_text(data: InstrumentData) -> String:
	return "%d" % roundi(data.wind_kn)


## "65° STBD" / "40° PORT" (the true wind's angle to the bow).
static func wind_angle_text(data: InstrumentData) -> String:
	if not data.underway or data.anchored or data.holding or data.wind_kn < 0.5:
		return "---"
	var angle := roundi(absf(data.wind_angle))
	if angle <= 2 or angle >= 178:
		return "%d°" % angle
	return "%d° %s" % [angle, Loc.t("STBD", "instrument") if data.wind_angle > 0.0 else Loc.t("PORT", "instrument")]


static func distance_text(nm: float) -> String:
	return Loc.decimal(nm, 1) if nm < 100.0 else Loc.thousands(roundi(nm))


static func eta_text(data: InstrumentData) -> String:
	return InstrumentData.clock_time(data.eta).to_upper() if data.underway else "---"


## The state in one capital word or two (what the boat is doing).
static func state_text(data: InstrumentData) -> String:
	if not data.underway:
		return Loc.t("MOORED", "instrument")
	if data.anchored:
		return Loc.t("AT ANCHOR", "instrument")
	if data.holding:
		return Loc.t("AT THE ANCHORAGE", "instrument")
	return Loc.t("UNDER ENGINE", "instrument") if data.motoring else Loc.t("UNDER SAIL", "instrument")


## The page's own title (Modern displays, the focused view's page keys).
static func page_title(page: String) -> String:
	match page:
		"speed":
			return Loc.t("BOAT SPEED", "instrument")
		"heading":
			return Loc.t("HEADING", "instrument")
		"wind":
			return Loc.t("TRUE WIND", "instrument")
		"route":
			return Loc.t("ROUTE", "instrument")
		"turn":
			return Loc.t("NEXT TURN", "instrument")
		"weather":
			return Loc.t("WEATHER", "instrument")
		"trim":
			return Loc.t("SAIL TRIM", "instrument")
		"overview":
			return Loc.t("OVERVIEW", "instrument")
		"sailing":
			return Loc.t("SAILING", "instrument")
		"navigation":
			return Loc.t("NAVIGATION", "instrument")
	return page.to_upper()


# --- Classic: dials -------------------------------------------------------------------------------

## One classic dial (`kind`: dial_speed, dial_heading, dial_wind).
static func draw_dial(ci: CanvasItem, rect: Rect2, package: InstrumentPackage, kind: String, data: InstrumentData, night: float, pulse := 0.0) -> void:
	var s := rect.size.x / BASE
	housing(ci, rect, package, night, 8.0 * s)
	var c := rect.get_center()
	var r := rect.size.x * 0.455
	# The bezel: brushed steel, lit along its top.
	ci.draw_circle(c, r, package.colour_at("housing_edge", night * 0.8))
	ci.draw_arc(c, r - 1.2 * s, deg_to_rad(195.0), deg_to_rad(345.0), 40, Color(1, 1, 1, 0.28 * (1.0 - night * 0.8)), 2.0 * s, true)
	ci.draw_arc(c, r - 1.2 * s, deg_to_rad(15.0), deg_to_rad(165.0), 40, Color(0, 0, 0, 0.30), 2.0 * s, true)
	var face_r := r - 4.0 * s
	ci.draw_circle(c, face_r, package.colour_at("dial_face", night))
	var ink := package.colour_at("dial_ink", night)
	var needle_colour := package.colour_at("accent", night)
	match kind:
		"dial_speed":
			_dial_speed(ci, c, face_r, s, package, data, night, ink, needle_colour)
		"dial_heading":
			_dial_heading(ci, c, face_r, s, package, data, night, ink, needle_colour, pulse)
		"dial_wind":
			_dial_wind(ci, c, face_r, s, package, data, night, ink, needle_colour)
	# The glass over the dial.
	ci.draw_arc(c, face_r - 1.0, deg_to_rad(200.0), deg_to_rad(260.0), 16, Color(1, 1, 1, 0.10 * (1.0 - night)), 3.0 * s, true)


## A small LCD window on a dial, its digits centred.
static func _lcd_window(ci: CanvasItem, center: Vector2, size: Vector2, text: String, unit: String, package: InstrumentPackage, night: float, s: float,
		pulse := 0.0) -> void:
	var rect := Rect2(center - size / 2.0, size)
	box(ci, rect.grow(1.0 * s), Color(0, 0, 0, 0.55), 2.0 * s)
	box(ci, rect, package.colour_at("screen", night), 2.0 * s)
	var ink := package.colour_at("ink", night).lerp(package.colour_at("accent", night), pulse)
	figure(ci, center + Vector2(0, 0.5 * s), text, unit, size.y * 0.78, ink, Color(ink, 0.8), size.x - 4.0 * s, &"condensed_medium")


static func _dial_speed(ci: CanvasItem, c: Vector2, r: float, s: float, package: InstrumentPackage, data: InstrumentData, night: float,
		ink: Color, needle_colour: Color) -> void:
	const MAX_KN := 10.0
	const FROM := -135.0
	const TO := 135.0
	ticks(ci, c, r - 2.0 * s, FROM, TO, (TO - FROM) / 20.0, 4, 3.5 * s, 7.5 * s, ink, maxf(1.0, s * 0.9))
	for k in 6:
		var deg := FROM + (TO - FROM) * k / 5.0
		text_at(ci, c + dir(deg) * (r - 15.0 * s), "%d" % (k * 2), 10.5 * s, ink, &"condensed_medium")
	text_at(ci, c + Vector2(0, r * 0.24), Loc.t("KNOTS", "instrument"), 8.0 * s, Color(ink, 0.8), &"condensed", r * 0.9)
	_lcd_window(ci, c + Vector2(0, r * 0.55), Vector2(r * 0.74, r * 0.28), speed_text(data), "", package, night, s)
	needle(ci, c, lerpf(FROM, TO, clampf(data.speed_kn / MAX_KN, 0.0, 1.04)), r - 6.0 * s, needle_colour, 3.0 * s, package.colour_at("housing", night))


static func _dial_heading(ci: CanvasItem, c: Vector2, r: float, s: float, package: InstrumentPackage, data: InstrumentData, night: float,
		ink: Color, needle_colour: Color, pulse: float) -> void:
	# The compass card turns under a fixed lubber line: the heading is at the top.
	var heading := data.heading_deg if data.underway else 0.0
	for i in 72:
		var bearing := i * 5.0
		var d := dir(bearing - heading)
		var major := i % 6 == 0
		ci.draw_line(c + d * (r - 2.0 * s), c + d * (r - (8.0 if major else 4.5) * s), ink if major else Color(ink, 0.55), (1.5 if major else 1.0) * maxf(s * 0.9, 1.0), true)
	for i in 12:
		var bearing := i * 30.0
		var label: String = [Loc.t("N", "compass"), "3", "6", Loc.t("E", "compass"), "12", "15", Loc.t("S", "compass"), "21", "24", Loc.t("W", "compass"), "30", "33"][i]
		var colour := needle_colour if i == 0 else ink
		text_at(ci, c + dir(bearing - heading) * (r - 16.0 * s), label, (11.0 if i % 3 == 0 else 9.0) * s, colour, &"condensed")
	# The lubber line.
	var top := c + Vector2(0, -r + 1.0 * s)
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(0, 9.0 * s), top + Vector2(-4.0 * s, 0), top + Vector2(4.0 * s, 0)]), needle_colour)
	_lcd_window(ci, c + Vector2(0, r * 0.10), Vector2(r * 0.80, r * 0.30), heading_text(data), "", package, night, s, pulse)


static func _dial_wind(ci: CanvasItem, c: Vector2, r: float, s: float, package: InstrumentPackage, data: InstrumentData, night: float,
		ink: Color, needle_colour: Color) -> void:
	var sector_alpha := 0.85 if night < 0.5 else 0.5
	arc(ci, c, r - 4.0 * s, -60.0, -20.0, Color(PORT_RED, sector_alpha), 5.0 * s)
	arc(ci, c, r - 4.0 * s, 20.0, 60.0, Color(STARBOARD_GREEN, sector_alpha * (0.4 if night > 0.5 else 1.0)), 5.0 * s)
	ticks(ci, c, r - 2.0 * s, 0.0, 360.0, 10.0, 3, 3.5 * s, 7.5 * s, ink, maxf(1.0, s * 0.9))
	for deg in [-120, -90, -60, -30, 30, 60, 90, 120]:
		text_at(ci, c + dir(deg) * (r - 15.5 * s), "%d" % absi(deg), 8.0 * s, Color(ink, 0.85), &"condensed_medium")
	var boat := boat_outline(c + Vector2(0, -r * 0.10), r * 0.62)
	ci.draw_polyline(closed(boat), Color(ink, 0.55), maxf(1.0, 1.2 * s), true)
	_lcd_window(ci, c + Vector2(0, r * 0.56), Vector2(r * 0.66, r * 0.27), wind_speed_text(data), Loc.t("KN", "instrument"), package, night, s)
	if data.wind_kn >= 0.5:
		var angle := data.wind_angle if data.underway and not data.anchored and not data.holding else 0.0
		needle(ci, c, angle, r - 5.0 * s, needle_colour, 3.0 * s, package.colour_at("housing", night))


# --- Classic: the LCD repeater ------------------------------------------------------------------------

## The classic LCD repeater (`page`: route, turn, weather, trim): four
## readouts in two rows, a caption and a value each.
static func draw_lcd(ci: CanvasItem, rect: Rect2, package: InstrumentPackage, page: String, data: InstrumentData, night: float, marks := false) -> void:
	var s := rect.size.y / 56.0
	housing(ci, rect, package, night, 6.0 * s)
	var screen := rect.grow(-6.0 * s)
	box(ci, screen.grow(1.0), Color(0, 0, 0, 0.6), 3.0 * s)
	box(ci, screen, package.colour_at("screen", night), 3.0 * s)
	# The LCD's faint inner shadow along the top.
	ci.draw_line(screen.position + Vector2(3 * s, 1.5), Vector2(screen.end.x - 3 * s, screen.position.y + 1.5), Color(0, 0, 0, 0.18), 2.0, true)
	var ink := package.colour_at("ink", night)
	var soft := Color(ink, 0.62)
	var cells := lcd_cells(page, data)
	var pad := 7.0 * s
	var cell_size := Vector2(screen.size.x / 2.0, (screen.size.y - 4.0 * s) / 2.0)
	for i in mini(cells.size(), 4):
		var cell := Rect2(screen.position + Vector2((i % 2) * cell_size.x, (i / 2) * cell_size.y + 1.0 * s), cell_size)
		var y := cell.get_center().y
		var caption: String = cells[i][0]
		var value: String = cells[i][1]
		text_at(ci, Vector2(cell.position.x + pad, y), caption, cell.size.y * 0.58, soft, &"condensed", cell.size.x * 0.44, HORIZONTAL_ALIGNMENT_LEFT)
		text_at(ci, Vector2(cell.end.x - pad, y), value, cell.size.y * 0.80, ink, &"condensed_medium", cell.size.x * 0.54, HORIZONTAL_ALIGNMENT_RIGHT)
	ci.draw_line(Vector2(screen.get_center().x, screen.position.y + 4.0 * s), Vector2(screen.get_center().x, screen.end.y - 4.0 * s), Color(ink, 0.15), 1.0)
	# The page marks (which page shows), along the bottom edge of the glass.
	var index := package.pages.find(page)
	for i in package.pages.size() if marks else 0:
		var at := Vector2(screen.get_center().x + (i - (package.pages.size() - 1) / 2.0) * 6.0 * s, screen.end.y - 2.5 * s)
		ci.draw_circle(at, 1.3 * s, ink if i == index else Color(ink, 0.22))


## The repeater's four readouts: [[caption, value] x 4].
static func lcd_cells(page: String, data: InstrumentData) -> Array:
	var wind_now := "%s %d %s" % [WindField.compass_name(data.wind_from_deg), roundi(data.wind_kn), Loc.t("KN", "instrument")] if data.wind_kn >= 0.5 else Loc.t("CALM", "instrument")
	if not data.underway:
		return [[Loc.t("MOORED", "instrument"), data.location.to_upper()], [Loc.t("WIND", "instrument"), wind_now], [Loc.t("SPEED", "instrument"), "%s %s" % [speed_text(data), Loc.t("KN", "instrument")]], ["", ""]]
	if data.anchored:
		return [[Loc.t("AT ANCHOR", "instrument"), Loc.t("CHAIN %d×", "instrument") % data.anchor_scope], [Loc.t("WIND", "instrument"), wind_now],
			[Loc.t("DEPTH", "instrument"), (Loc.t("ABOUT %d M", "instrument") % roundi(data.anchor_depth_m)) if data.anchor_depth_m > 0.0 else "---"], [Loc.t("ESTIMATE", "instrument"), ""]]
	match page:
		"turn":
			if data.has_next_leg():
				var wind := data.next_leg_wind()
				var leg_wind := ("%s %d %s" % [WindField.compass_name(wind.from_deg), roundi(wind.speed_kn), Loc.t("KN", "instrument")]) if wind and wind.speed_kn >= 0.5 else Loc.t("CALM", "instrument")
				var minutes := float(data.turn.nm) / data.speed_kn * 60.0 if data.speed_kn > 0.3 else -1.0
				return [[Loc.t("NEXT TURN", "instrument"), "%s %s" % [distance_text(float(data.turn.nm)), Loc.t("NM", "instrument")]], [Loc.t("THEN", "instrument"), "%03d°" % roundi(float(data.turn.next_course))],
					[Loc.t("IN", "instrument"), Simulation.format_duration(minutes * 60.0).to_upper() if minutes >= 0.0 else "---"], [Loc.t("WIND THERE", "instrument"), leg_wind]]
			return [[Loc.t("NEXT TURN", "instrument"), Loc.t("NONE", "instrument")], [Loc.t("TO %s", "instrument") % data.destination.to_upper(), "%s %s" % [distance_text(data.remaining_nm), Loc.t("NM", "instrument")]],
				[Loc.t("ETA", "instrument"), eta_text(data)], ["", ""]]
		"weather":
			var cells: Array = [[Loc.t("NOW", "instrument"), wind_now]]
			for i in mini(data.forecast.size(), 3):
				var sample := data.forecast[i]
				cells.append([Loc.t("+%d H", "instrument") % InstrumentData.FORECAST_HOURS[i],
					("%s %d %s" % [WindField.compass_name(sample.from_deg), roundi(sample.speed_kn), Loc.t("KN", "instrument")]) if sample.speed_kn >= 0.5 else Loc.t("CALM", "instrument")])
			while cells.size() < 4:
				cells.append(["", ""])
			return cells
		"trim":
			return [[Loc.t("SAIL TRIM", "instrument"), _trim_word(data)], [Loc.t("SPEED", "instrument"), "%s %s" % [speed_text(data), Loc.t("KN", "instrument")]],
				[Loc.t("WIND ANGLE", "instrument"), wind_angle_text(data)], [Loc.t("WIND", "instrument"), wind_now]]
	if data.holding:
		return [[Loc.t("ANCHORAGE", "instrument"), Loc.t("WAITING", "instrument")], [Loc.t("WIND", "instrument"), wind_now], [Loc.t("TO %s", "instrument") % data.destination.to_upper(), "%s %s" % [distance_text(data.remaining_nm), Loc.t("NM", "instrument")]],
			[Loc.t("ETA", "instrument"), eta_text(data)]]
	var turn := ["%s %s" % [distance_text(float(data.turn.nm)), Loc.t("NM", "instrument")], "%03d°" % roundi(float(data.turn.next_course))] if data.has_next_leg() else [Loc.t("NONE", "instrument"), "---"]
	return [[Loc.t("TO %s", "instrument") % data.destination.to_upper(), "%s %s" % [distance_text(data.remaining_nm), Loc.t("NM", "instrument")]], [Loc.t("ETA", "instrument"), eta_text(data)],
		[Loc.t("NEXT TURN", "instrument"), turn[0]], [Loc.t("THEN", "instrument"), turn[1]]]


# --- Modern: square displays with pages --------------------------------------------------------------

static func draw_page(ci: CanvasItem, rect: Rect2, package: InstrumentPackage, page: String, data: InstrumentData, night: float, pulse := 0.0) -> void:
	var s := rect.size.x / BASE
	housing(ci, rect, package, night, 4.0 * s)
	var screen := rect.grow(-5.0 * s)
	glass(ci, screen, package.colour_at("screen", night), 2.0 * s, night)
	var ink := package.colour_at("ink", night)
	var accent := package.colour_at("accent", night)
	var soft := Color(ink, 0.62)
	# The page title in a slim header, a hairline under it.
	var header := Rect2(screen.position, Vector2(screen.size.x, 18.0 * s))
	var corner := ""
	match page:
		"speed", "trim":
			corner = heading_text(data)
		"heading":
			corner = "%s %s" % [speed_text(data), Loc.t("KN", "instrument")]
		"wind":
			corner = WindField.compass_name(data.wind_from_deg) if data.wind_kn >= 0.5 else ""
	text_at(ci, Vector2(header.position.x + 5.0 * s, header.get_center().y), page_title(page), 10.5 * s, soft, &"condensed",
		screen.size.x * (0.6 if corner != "" else 1.0) - 10.0 * s, HORIZONTAL_ALIGNMENT_LEFT)
	text_at(ci, Vector2(header.end.x - 5.0 * s, header.get_center().y), corner, 11.0 * s, ink.lerp(accent, pulse), &"condensed_medium",
		screen.size.x * 0.4 - 6.0 * s, HORIZONTAL_ALIGNMENT_RIGHT)
	ci.draw_line(Vector2(screen.position.x + 4 * s, header.end.y), Vector2(screen.end.x - 4 * s, header.end.y), Color(ink, 0.18), 1.0)
	var body := Rect2(Vector2(screen.position.x, header.end.y), Vector2(screen.size.x, screen.size.y - header.size.y))
	var footer_y := body.end.y - 10.0 * s
	var big := body.size.y * 0.50
	var width := body.size.x - 10.0 * s
	match page:
		"speed":
			figure(ci, body.get_center() + Vector2(0, -6.0 * s), speed_text(data), Loc.t("KN", "instrument"), big, ink, soft, width)
			text_at(ci, Vector2(body.get_center().x, footer_y), state_text(data), 10.5 * s, accent if data.motoring else soft, &"condensed", width)
		"heading":
			figure(ci, body.get_center() + Vector2(0, -10.0 * s), heading_text(data), "", big * 0.92, ink.lerp(accent, pulse), soft, width)
			_tape(ci, Rect2(body.position.x + 6 * s, body.end.y - 22.0 * s, body.size.x - 12 * s, 16.0 * s), data.heading_deg, ink, accent, s)
		"wind":
			var c := body.get_center() + Vector2(0, -7.0 * s)
			_rose(ci, c, body.size.y * 0.36, data, ink, accent, night, s)
			figure(ci, c + Vector2(0, 2.0 * s), wind_speed_text(data), Loc.t("KN", "instrument"), 20.0 * s, ink, soft, body.size.y * 0.5)
			text_at(ci, Vector2(body.get_center().x, footer_y), wind_angle_text(data), 10.5 * s, soft, &"condensed", width)
		"route":
			if data.anchored or data.holding or not data.underway:
				figure(ci, body.get_center() + Vector2(0, -6.0 * s), speed_text(data), Loc.t("KN", "instrument"), big * 0.8, ink, soft, width)
				text_at(ci, Vector2(body.get_center().x, footer_y), state_text(data), 10.5 * s, accent, &"condensed", width)
			else:
				text_at(ci, Vector2(body.get_center().x, body.position.y + 10.0 * s), Loc.t("TO %s", "instrument") % data.destination.to_upper(), 11.0 * s, accent, &"condensed", width)
				figure(ci, body.get_center() + Vector2(0, -1.0 * s), distance_text(data.remaining_nm), Loc.t("NM", "instrument"), big * 0.78, ink, soft, width)
				text_at(ci, Vector2(body.get_center().x, footer_y - 5.0 * s), "%s %s" % [Loc.t("ETA", "instrument"), eta_text(data)], 10.5 * s, soft, &"condensed", width)
				var bar := Rect2(body.position.x + 8 * s, body.end.y - 5.0 * s, body.size.x - 16 * s, 2.0 * s)
				ci.draw_rect(bar, Color(ink, 0.15))
				ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * data.progress, bar.size.y)), accent)
		"turn":
			if data.has_next_leg():
				figure(ci, body.get_center() + Vector2(0, -8.0 * s), distance_text(float(data.turn.nm)), Loc.t("NM", "instrument"), big * 0.8, ink, soft, width)
				text_at(ci, Vector2(body.get_center().x, footer_y - 4.0 * s), "%s %03d°" % [Loc.t("THEN", "instrument"), roundi(float(data.turn.next_course))], 11.5 * s, accent, &"condensed", width)
			else:
				text_at(ci, body.get_center() + Vector2(0, -8.0 * s), Loc.t("NO MORE TURNS", "instrument") if data.underway else "---", 11.0 * s, ink, &"condensed", width)
				if data.underway and not data.anchored:
					text_at(ci, Vector2(body.get_center().x, footer_y - 4.0 * s), Loc.t("TO %s", "instrument") % data.destination.to_upper(), 10.5 * s, accent, &"condensed", width)
		"weather":
			_weather_rows(ci, body.grow_individual(-6 * s, -2 * s, -6 * s, -4 * s), data, ink, soft, accent, s, false)
		"trim":
			var word := Loc.t("ENGINE", "instrument") if data.motoring else (data.get_value("trim").split("  ·  ")[0].to_upper() if data.underway else "---")
			text_at(ci, body.get_center() + Vector2(0, -10.0 * s), word, 14.0 * s, ink, &"condensed", width)
			text_at(ci, Vector2(body.get_center().x, footer_y - 4.0 * s), "%s  %s" % [Loc.t("WIND ANGLE", "instrument"), wind_angle_text(data)], 10.5 * s, soft, &"condensed", width)


## A compass tape (the heading at the centre mark).
static func _tape(ci: CanvasItem, rect: Rect2, heading: float, ink: Color, accent: Color, s: float) -> void:
	var span := 60.0
	var mid := rect.get_center().x
	for k in range(-6, 7):
		var bearing := floorf(heading / 10.0) * 10.0 + k * 10.0
		var x := mid + (bearing - heading) / span * rect.size.x
		if x < rect.position.x or x > rect.end.x:
			continue
		var major := fposmod(bearing, 30.0) < 0.5
		ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y + (6.0 if major else 3.5) * s), Color(ink, 0.7 if major else 0.4), 1.0)
		if major:
			var label := "%d" % roundi(fposmod(bearing, 360.0) / 10.0)
			match roundi(fposmod(bearing, 360.0)):
				0:
					label = Loc.t("N", "compass")
				90:
					label = Loc.t("E", "compass")
				180:
					label = Loc.t("S", "compass")
				270:
					label = Loc.t("W", "compass")
			text_at(ci, Vector2(x, rect.position.y + 11.0 * s), label, 7.5 * s, Color(ink, 0.75), &"condensed")
	ci.draw_colored_polygon(PackedVector2Array([Vector2(mid, rect.position.y + 4.0 * s), Vector2(mid - 3.0 * s, rect.position.y - 1.0 * s),
		Vector2(mid + 3.0 * s, rect.position.y - 1.0 * s)]), accent)


## A wind rose: the boat at the centre, close-hauled sectors and the pointer.
static func _rose(ci: CanvasItem, c: Vector2, r: float, data: InstrumentData, ink: Color, accent: Color, night: float, s: float) -> void:
	ci.draw_arc(c, r, 0.0, TAU, 64, Color(ink, 0.30), maxf(1.0, s), true)
	arc(ci, c, r - 2.5 * s, -60.0, -20.0, Color(PORT_RED, 0.9 if night < 0.5 else 0.7), 3.5 * s)
	arc(ci, c, r - 2.5 * s, 20.0, 60.0, Color(STARBOARD_GREEN, 0.9 if night < 0.5 else 0.25), 3.5 * s)
	ticks(ci, c, r, 0.0, 360.0, 30.0, 3, 3.0 * s, 5.5 * s, Color(ink, 0.7), maxf(1.0, s * 0.8))
	ci.draw_polyline(closed(boat_outline(c, r * 0.95)), Color(ink, 0.25), maxf(1.0, s), true)
	if data.wind_kn >= 0.5 and data.underway and not data.anchored and not data.holding:
		# The wind arrow on the ring, pointing in towards the boat.
		var d := dir(data.wind_angle)
		var outer := c + d * (r + 2.0 * s)
		var tip := c + d * (r - 13.0 * s)
		var side := d.orthogonal() * 5.5 * s
		ci.draw_colored_polygon(PackedVector2Array([tip, outer + side, outer - side]), accent)


## Now and the forecast (+3, +6, +12 h at the boat), one row each.
static func _weather_rows(ci: CanvasItem, rect: Rect2, data: InstrumentData, ink: Color, soft: Color, accent: Color, s: float, large: bool) -> void:
	var rows: Array[Array] = [[Loc.t("NOW", "instrument"), data.wind_from_deg, data.wind_kn, data.gust_kn, data.hazard]]
	for i in mini(data.forecast.size(), InstrumentData.FORECAST_HOURS.size()):
		var sample := data.forecast[i]
		rows.append([Loc.t("+%d H", "instrument") % InstrumentData.FORECAST_HOURS[i], sample.from_deg, sample.speed_kn, sample.gust_kn, sample.hazard])
	var row_h := rect.size.y / maxf(rows.size(), 1.0)
	var size := row_h * (0.48 if large else 0.55)
	for i in rows.size():
		var row: Array = rows[i]
		var y := rect.position.y + row_h * (i + 0.5)
		text_at(ci, Vector2(rect.position.x, y), row[0], size * 0.9, soft, &"condensed", rect.size.x * 0.28, HORIZONTAL_ALIGNMENT_LEFT)
		var kn := float(row[2])
		var colour := ink if int(row[4]) < WeatherModel.HAZARD_CAUTION else UiTheme.color(&"warning")
		if kn >= 0.5:
			# A small arrow: where the wind goes (north up).
			var at := Vector2(rect.position.x + rect.size.x * 0.40, y)
			var d := dir(float(row[1]) + 180.0)
			var length := row_h * 0.30
			ci.draw_line(at - d * length, at + d * length * 0.6, Color(accent, 0.9), maxf(1.0, 1.4 * s), true)
			ci.draw_colored_polygon(PackedVector2Array([at + d * length, at + d * length * 0.3 + d.orthogonal() * length * 0.4,
				at + d * length * 0.3 - d.orthogonal() * length * 0.4]), accent)
		var words := ("%s %d" % [WindField.compass_name(float(row[1])), roundi(kn)]) if kn >= 0.5 else Loc.t("CALM", "instrument")
		if large and float(row[3]) >= kn + 6.0:
			words += "  " + Loc.t("G%d", "instrument") % roundi(float(row[3]))
		text_at(ci, Vector2(rect.end.x, y), words, size, colour, &"condensed_medium", rect.size.x * 0.48, HORIZONTAL_ALIGNMENT_RIGHT)


# --- Offshore: the multifunction display --------------------------------------------------------------

## The multifunction display (`layout`: overview, sailing, navigation, weather).
static func draw_mfd(ci: CanvasItem, rect: Rect2, package: InstrumentPackage, layout: String, data: InstrumentData, night: float, pulse := 0.0) -> void:
	var s := rect.size.y / 190.0
	housing(ci, rect, package, night, 6.0 * s)
	# A slim aluminium rim inside the case.
	box(ci, rect.grow(-3.0 * s), Color(0, 0, 0, 0), 5.0 * s, Color(package.colour_at("housing_edge", night), 0.55 * (1.0 - 0.6 * night)), 1.0)
	var screen := rect.grow(-7.0 * s)
	glass(ci, screen, package.colour_at("screen", night), 3.0 * s, night)
	var ink := package.colour_at("ink", night)
	var accent := package.colour_at("accent", night)
	var soft := Color(ink, 0.58)
	# The status bar: the layout, the state and the maker's mark.
	var bar := Rect2(screen.position, Vector2(screen.size.x, 19.0 * s))
	box(ci, bar, Color(accent, 0.10), 3.0 * s)
	text_at(ci, Vector2(bar.position.x + 6.0 * s, bar.get_center().y), page_title(layout), 11.0 * s, accent, &"condensed", bar.size.x * 0.4, HORIZONTAL_ALIGNMENT_LEFT)
	text_at(ci, Vector2(bar.get_center().x, bar.get_center().y), state_text(data), 10.5 * s, soft, &"condensed", bar.size.x * 0.34)
	text_at(ci, Vector2(bar.end.x - 6.0 * s, bar.get_center().y), InstrumentPackage.brand(), 9.0 * s, Color(ink, 0.35), &"condensed", bar.size.x * 0.2,
		HORIZONTAL_ALIGNMENT_RIGHT)
	var body := Rect2(Vector2(screen.position.x + 4.0 * s, bar.end.y + 4.0 * s), Vector2(screen.size.x - 8.0 * s, screen.end.y - bar.end.y - 8.0 * s))
	if layout != "overview":
		# The data bar: the essentials stay in view on every layout.
		var strip := Rect2(Vector2(body.position.x, body.end.y - 20.0 * s), Vector2(body.size.x, 20.0 * s))
		body.size.y -= strip.size.y + 4.0 * s
		_data_bar(ci, strip, data, ink, soft, accent, s, pulse)
	match layout:
		"sailing":
			var left := Rect2(body.position, Vector2(body.size.y, body.size.y))
			_rose(ci, left.get_center(), left.size.y * 0.46, data, ink, accent, night, s)
			figure(ci, left.get_center() + Vector2(0, 4.0 * s), wind_speed_text(data), Loc.t("KN", "instrument"), 24.0 * s, ink, soft, left.size.x * 0.5)
			text_at(ci, left.get_center() + Vector2(0, -18.0 * s), Loc.t("TRUE WIND", "instrument"), 9.0 * s, soft, &"condensed", left.size.x * 0.5)
			_tiles(ci, Rect2(Vector2(left.end.x + 6.0 * s, body.position.y), Vector2(body.end.x - left.end.x - 6.0 * s, body.size.y)), 2, [
				[Loc.t("SPEED", "instrument"), speed_text(data), Loc.t("KN", "instrument")], [Loc.t("HEADING", "instrument"), heading_text(data), ""],
				[Loc.t("WIND ANGLE", "instrument"), wind_angle_text(data), ""], [Loc.t("SAIL TRIM", "instrument"), _trim_word(data), ""]], ink, soft, accent, s, pulse)
		"navigation":
			var left := Rect2(body.position, Vector2(body.size.x * 0.42, body.size.y))
			_highway(ci, left, data, ink, soft, accent, night, s)
			var turn_value := "%s %s" % [distance_text(float(data.turn.nm)), Loc.t("NM", "instrument")] if data.has_next_leg() else Loc.t("NONE", "instrument")
			var then_value := "%03d°" % roundi(float(data.turn.next_course)) if data.has_next_leg() else "---"
			_tiles(ci, Rect2(Vector2(left.end.x + 6.0 * s, body.position.y), Vector2(body.end.x - left.end.x - 6.0 * s, body.size.y)), 2, [
				[Loc.t("TO GO", "instrument"), distance_text(data.remaining_nm) if data.underway else "---", Loc.t("NM", "instrument")], [Loc.t("ETA", "instrument"), eta_text(data), ""],
				[Loc.t("NEXT TURN", "instrument"), turn_value, ""], [Loc.t("NEW COURSE", "instrument"), then_value, ""]], ink, soft, accent, s, 0.0)
		"weather":
			var left := Rect2(body.position, Vector2(body.size.x * 0.38, body.size.y))
			box(ci, left, Color(ink, 0.04), 3.0 * s)
			text_at(ci, Vector2(left.get_center().x, left.position.y + 12.0 * s), Loc.t("WIND NOW", "instrument"), 10.0 * s, soft, &"condensed", left.size.x - 8 * s)
			figure(ci, left.get_center() + Vector2(0, -2.0 * s), wind_speed_text(data), Loc.t("KN", "instrument"), 40.0 * s, ink, soft, left.size.x - 10 * s)
			text_at(ci, Vector2(left.get_center().x, left.get_center().y + 26.0 * s), WindField.compass_name(data.wind_from_deg), 12.0 * s, accent, &"condensed")
			var label := data.weather_label.to_upper() if data.weather_label != "" else ""
			if data.gust_kn >= data.wind_kn + 6.0:
				label = (label + "  " if label != "" else "") + Loc.t("GUSTS %d", "instrument") % roundi(data.gust_kn)
			text_at(ci, Vector2(left.get_center().x, left.end.y - 10.0 * s), label, 8.5 * s, UiTheme.color(&"warning") if data.hazard >= WeatherModel.HAZARD_CAUTION else soft,
				&"condensed", left.size.x - 8 * s)
			var right := Rect2(Vector2(left.end.x + 10.0 * s, body.position.y), Vector2(body.end.x - left.end.x - 10.0 * s, body.size.y))
			text_at(ci, Vector2(right.position.x, right.position.y + 8.0 * s), Loc.t("FORECAST HERE (ESTIMATE)", "instrument"), 9.5 * s, soft, &"condensed", right.size.x,
				HORIZONTAL_ALIGNMENT_LEFT)
			_weather_rows(ci, Rect2(right.position + Vector2(0, 16.0 * s), right.size - Vector2(0, 16.0 * s)), data, ink, soft, accent, s, true)
		_:
			_tiles(ci, body, 3, [[Loc.t("SPEED", "instrument"), speed_text(data), Loc.t("KN", "instrument")], [Loc.t("HEADING", "instrument"), heading_text(data), ""],
				[Loc.t("WIND", "instrument"), wind_speed_text(data), Loc.t("KN", "instrument")], [Loc.t("WIND ANGLE", "instrument"), wind_angle_text(data), ""],
				[Loc.t("TO GO", "instrument"), distance_text(data.remaining_nm) if data.underway else "---", Loc.t("NM", "instrument")], [Loc.t("ETA", "instrument"), eta_text(data), ""]], ink, soft, accent, s, pulse)


## One line of the essentials: speed, heading, wind, distance and ETA.
static func _data_bar(ci: CanvasItem, rect: Rect2, data: InstrumentData, ink: Color, soft: Color, accent: Color, s: float, pulse: float) -> void:
	box(ci, rect, Color(ink, 0.06), 2.0 * s)
	var items := [[Loc.t("SPEED", "instrument"), "%s %s" % [speed_text(data), Loc.t("KN", "instrument")]], [Loc.t("HEADING", "instrument"), heading_text(data)],
		[Loc.t("WIND", "instrument"), "%s %s" % [wind_speed_text(data), Loc.t("KN", "instrument")]], [Loc.t("TO GO", "instrument"), ("%s %s" % [distance_text(data.remaining_nm), Loc.t("NM", "instrument")]) if data.underway else "---"],
		[Loc.t("ETA", "instrument"), eta_text(data)]]
	var width := rect.size.x / items.size()
	for i in items.size():
		var cell := Rect2(rect.position + Vector2(i * width, 0), Vector2(width, rect.size.y))
		var item: Array = items[i]
		text_at(ci, Vector2(cell.position.x + 4.0 * s, cell.get_center().y), item[0], 8.5 * s, accent, &"condensed", width * 0.40, HORIZONTAL_ALIGNMENT_LEFT)
		text_at(ci, Vector2(cell.end.x - 4.0 * s, cell.get_center().y), item[1], 11.0 * s, ink.lerp(accent, pulse) if i == 1 else ink, &"condensed_medium",
			width * 0.56, HORIZONTAL_ALIGNMENT_RIGHT)
		if i > 0:
			ci.draw_line(cell.position + Vector2(0, 3.0 * s), cell.position + Vector2(0, cell.size.y - 3.0 * s), Color(soft, 0.3), 1.0)


static func _trim_word(data: InstrumentData) -> String:
	if not data.underway or data.anchored or data.holding:
		return "---"
	return Loc.t("ENGINE", "instrument") if data.motoring else data.get_value("trim").split("  ·  ")[0].to_upper()


## Data tiles in a grid: [caption, value, unit] each.
static func _tiles(ci: CanvasItem, rect: Rect2, columns: int, tiles: Array, ink: Color, soft: Color, accent: Color, s: float, pulse: float) -> void:
	var rows := ceili(tiles.size() / float(columns))
	var gap := 4.0 * s
	var size := Vector2((rect.size.x - gap * (columns - 1)) / columns, (rect.size.y - gap * (rows - 1)) / rows)
	for i in tiles.size():
		var cell := Rect2(rect.position + Vector2((i % columns) * (size.x + gap), (i / columns) * (size.y + gap)), size)
		box(ci, cell, Color(ink, 0.05), 3.0 * s)
		ci.draw_line(cell.position + Vector2(0, 2.0 * s), cell.position + Vector2(0, cell.size.y - 2.0 * s), Color(accent, 0.55), 2.0 * s)
		var tile: Array = tiles[i]
		text_at(ci, Vector2(cell.position.x + 7.0 * s, cell.position.y + 10.0 * s), tile[0], 10.5 * s, accent, &"condensed", cell.size.x - 12.0 * s,
			HORIZONTAL_ALIGNMENT_LEFT)
		var colour := ink.lerp(accent, pulse) if tile[0] == Loc.t("HEADING", "instrument") else ink
		figure(ci, cell.get_center() + Vector2(0, 5.0 * s), tile[1], tile[2], minf(cell.size.y * 0.50, cell.size.x * 0.40), colour, soft, cell.size.x - 12.0 * s)


## A "highway" view of the course: the boat at the bottom, the leg ahead to
## the next turn and the new leg bending off after it.
static func _highway(ci: CanvasItem, rect: Rect2, data: InstrumentData, ink: Color, soft: Color, accent: Color, _night: float, s: float) -> void:
	box(ci, rect, Color(ink, 0.04), 3.0 * s)
	var bottom := Vector2(rect.get_center().x, rect.end.y - 12.0 * s)
	var horizon := rect.position.y + 10.0 * s
	# The lane, narrowing towards the horizon.
	var lane := PackedVector2Array([bottom + Vector2(-rect.size.x * 0.32, 0), bottom + Vector2(rect.size.x * 0.32, 0),
		Vector2(bottom.x + rect.size.x * 0.06, horizon), Vector2(bottom.x - rect.size.x * 0.06, horizon)])
	ci.draw_colored_polygon(lane, Color(accent, 0.10))
	ci.draw_line(lane[0], lane[3], Color(accent, 0.45), 1.0, true)
	ci.draw_line(lane[1], lane[2], Color(accent, 0.45), 1.0, true)
	if data.underway and not data.anchored and not data.holding and data.has_next_leg():
		var range_nm := maxf(float(data.turn.nm) * 1.6, 1.0)
		var f := clampf(float(data.turn.nm) / range_nm, 0.0, 1.0)
		var y := lerpf(bottom.y, horizon, sqrt(f))
		var at := Vector2(bottom.x, y)
		ci.draw_line(bottom, at, accent, 2.0 * s, true)
		var bend := angle_difference(deg_to_rad(float(data.turn.course)), deg_to_rad(float(data.turn.next_course)))
		var out := at + Vector2(sin(bend), -cos(bend)) * (y - horizon + 6.0 * s)
		ci.draw_line(at, out, Color(accent, 0.6), 2.0 * s, true)
		ci.draw_arc(at, 4.0 * s, 0.0, TAU, 16, ink, 1.5 * s, true)
		text_at(ci, at + Vector2(8.0 * s, 0), "%s %s" % [distance_text(float(data.turn.nm)), Loc.t("NM", "instrument")], 10.0 * s, soft, &"condensed", rect.size.x * 0.45,
			HORIZONTAL_ALIGNMENT_LEFT)
	elif data.underway and not data.anchored and not data.holding:
		ci.draw_line(bottom, Vector2(bottom.x, horizon + 6.0 * s), accent, 2.0 * s, true)
		text_at(ci, Vector2(bottom.x, horizon + 12.0 * s), data.destination.to_upper(), 8.5 * s, ink, &"condensed", rect.size.x - 8 * s)
	ci.draw_colored_polygon(PackedVector2Array([bottom + Vector2(0, -9.0 * s), bottom + Vector2(5.0 * s, 4.0 * s), bottom + Vector2(-5.0 * s, 4.0 * s)]), ink)
