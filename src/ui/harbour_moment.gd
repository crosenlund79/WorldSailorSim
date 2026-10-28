class_name HarbourMoment
extends PanelContainer
## Golden Harbour Moments: the first arrival in a harbour with illustrated
## art becomes a small travel memory. It is a card in the notice column with
## the harbour's own picture (HarbourLooks: its landmark strip or its look's
## illustration), painted into a sky and a sea for the hour:
##   day    the picture as drawn;
##   dawn   a pale sky and a little mist over the water;
##   dusk   a warm sky, the painting warmed, its own windows starting to glow,
##          lanterns along the quay;
##   night  a dark sky, the painting dimmed, its windows lit, lanterns.
## The lit windows are the painting's own dark window shapes, found once per
## picture (window_spots) and cached: no new art, nothing invented.
##
## Then the harbour's name, its one line of description, the Captain's Log
## line, and a "First visit" stamp ("Special harbour" for the harbours with
## their own art). A click anywhere on it puts it away, and it fades by itself
## after a while; it never takes the keyboard or blocks the game. Returning
## to a known harbour keeps the quiet small card (App).
##
## Drawn once when shown (and on resize): no per-frame work.

signal dismissed

const WIDTH := 560.0
const PICTURE_HEIGHT := 230.0
## The middle part of a picture strip that is shown (strips are very wide).
const CROP := 0.42
## Window spots: the picture is sampled on this grid (source pixels).
const SAMPLE_STEP := 6
const MAX_WINDOWS := 60
## How far from a window's middle its wall is looked for (source pixels).
const WALL_REACH := 12

static var _window_cache := {}

var port_id: StringName
var first_visit := true
var special := false
var picture: Texture2D
## The sun's elevation at the harbour (degrees) and the overcast (0..1).
var elevation := 30.0
var overcast := 0.0
var log_line := ""

var scene: Control


func _ready() -> void:
	name = "HarbourMoment"
	theme_type_variation = &"ToastPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	tooltip_text = Loc.t("Click to put it away")
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	add_child(box)
	var stamp := Label.new()
	stamp.name = "Stamp"
	stamp.theme_type_variation = &"MutedLabel"
	stamp.add_theme_font_size_override(&"font_size", 15)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamp.text = (Loc.t("✦ Special harbour") + "  ·  " if special else "") + Loc.t("First visit") + "  ·  " + \
		Simulation.format_game_time(GameSession.get_game_time()).get_slice(",", 0)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stamp)
	scene = HarbourScene.new()
	scene.name = "Scene"
	scene.moment = self
	scene.custom_minimum_size = Vector2(WIDTH - 24.0, PICTURE_HEIGHT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(scene)
	var port := PortCatalog.get_default().get_port(port_id)
	for line: Array in [[Loc.t("Arrived in %s.") % PortCatalog.get_default().get_display_name(port_id), &"HeaderLabel"],
			[port.get_description() if port else "", &""], [log_line, &"MutedLabel"]]:
		if String(line[0]).is_empty():
			continue
		var label := Label.new()
		label.text = line[0]
		label.theme_type_variation = line[1]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH - 24.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		dismiss()


## Puts the card away (a short fade).
func dismiss() -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
	dismissed.emit()


## The time of day as the card paints it: &"day", &"dawn", &"dusk" or &"night".
static func light_of(sun_elevation: float, morning: bool) -> StringName:
	if sun_elevation < -6.0:
		return &"night"
	if sun_elevation < 8.0:
		return &"dawn" if morning else &"dusk"
	return &"day"


## Where the painting's own windows are (its small dark, filled shapes), as
## rectangles in 0..1 picture coordinates; found once per picture and kept.
static func window_spots(texture: Texture2D) -> Array[Rect2]:
	var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_rid())
	if _window_cache.has(key):
		return _window_cache[key]
	var spots: Array[Rect2] = []
	var image := texture.get_image()
	if image == null:
		_window_cache[key] = spots
		return spots
	if image.is_compressed():
		image.decompress()
	var w := image.get_width()
	var h := image.get_height()
	var x0 := int(w * (0.5 - CROP * 0.5))
	var x1 := int(w * (0.5 + CROP * 0.5))
	var taken := {}
	for y in range(SAMPLE_STEP, h - SAMPLE_STEP, SAMPLE_STEP):
		for x in range(x0, x1, SAMPLE_STEP):
			if spots.size() >= MAX_WINDOWS:
				break
			var cell := Vector2i(x / (SAMPLE_STEP * 3), y / (SAMPLE_STEP * 3))
			if taken.has(cell) or not _is_window(image, x, y):
				continue
			taken[cell] = true
			spots.append(Rect2(float(x - 4) / w, float(y - 5) / h, 8.0 / w, 10.0 / h))
	_window_cache[key] = spots
	return spots


## A dark, opaque, filled spot (all of a small neighbourhood dark: not a
## thin outline) set in a lighter wall on at least three sides (not a dark
## leaf against the open sky): a painted window pane.
static func _is_window(image: Image, x: int, y: int) -> bool:
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		var c := image.get_pixel(x + offset.x, y + offset.y)
		if c.a < 0.9 or c.get_luminance() > 0.33:
			return false
	var walls := 0
	for offset: Vector2i in [Vector2i(-WALL_REACH, 0), Vector2i(WALL_REACH, 0), Vector2i(0, -WALL_REACH), Vector2i(0, WALL_REACH)]:
		var p := Vector2i(clampi(x + offset.x, 0, image.get_width() - 1), clampi(y + offset.y, 0, image.get_height() - 1))
		var c := image.get_pixel(p.x, p.y)
		if c.a > 0.9 and c.get_luminance() > 0.42:
			walls += 1
	return walls >= 3


## The picture with its sky, sea and the hour's light.
class HarbourScene:
	extends Control

	var moment: HarbourMoment

	func _draw() -> void:
		if moment == null:
			return
		var box := Rect2(Vector2.ZERO, size)
		var morning := Daylight.local_solar_hours(GameSession.get_vessel_position().x, GameSession.get_game_time()) < 12.0
		var light := HarbourMoment.light_of(moment.elevation, morning)
		# Real Horizon: a high grey-blue sky over sea haze; dawn and dusk softly warm, not amber.
		var sky: Array = {&"day": [Color(0.56, 0.66, 0.72), Color(0.8, 0.83, 0.82)], &"dawn": [Color(0.5, 0.55, 0.64), Color(0.88, 0.8, 0.76)],
			&"dusk": [Color(0.3, 0.32, 0.42), Color(0.86, 0.72, 0.64)], &"night": [Color(0.06, 0.09, 0.13), Color(0.13, 0.17, 0.22)]}[light]
		var grey := Color(0.55, 0.6, 0.63)
		var top: Color = (sky[0] as Color).lerp(grey * (0.4 if light == &"night" else 1.0), moment.overcast * 0.7)
		var low: Color = (sky[1] as Color).lerp(grey * (0.45 if light == &"night" else 1.0), moment.overcast * 0.6)
		var horizon := size.y * 0.78
		_gradient(Rect2(0, 0, size.x, horizon), top, low)
		var sea := WaterLook.water_colour(true) * Daylight.outside_colour(moment.elevation, moment.overcast).lerp(Color.WHITE, 0.35)
		_gradient(Rect2(0, horizon, size.x, size.y - horizon), sea, sea.darkened(0.25))
		if light == &"night" and moment.overcast < 0.5:
			for k in 24:
				var h := hash([k, moment.port_id]) % 1000
				draw_rect(Rect2(fmod(float(h) * 3.7, size.x), fmod(float(h) * 0.9, horizon * 0.5), 1.4, 1.4), Color(1, 0.97, 0.86, 0.8))
		# The painting: the middle of its strip, standing on the horizon.
		var picture := moment.picture
		var drawn := Rect2()
		if picture:
			var source := picture.get_size()
			var region := Rect2(source.x * (0.5 - CROP * 0.5), 0, source.x * CROP, source.y)
			var height := minf(size.x * region.size.y / region.size.x, horizon * 0.85)
			drawn = Rect2(0, horizon - height + 6.0, size.x, height)
			var tint: Color = {&"day": Color.WHITE, &"dawn": Color(0.95, 0.92, 0.92), &"dusk": Color(0.88, 0.8, 0.76), &"night": Color(0.34, 0.38, 0.48)}[light]
			tint = tint.lerp(Color(0.7, 0.72, 0.75), moment.overcast * 0.4)
			draw_texture_rect_region(picture, drawn, region, tint)
			# Its own windows, warm at dusk and lit at night.
			if light in [&"dusk", &"night"]:
				var glow := Color(1.0, 0.87, 0.66, 0.95 if light == &"night" else 0.55)
				for spot in HarbourMoment.window_spots(picture):
					var u := (spot.position.x - (0.5 - CROP * 0.5)) / CROP
					var r := Rect2(drawn.position + Vector2(u * drawn.size.x, spot.position.y * drawn.size.y),
						Vector2(spot.size.x / CROP * drawn.size.x, spot.size.y * drawn.size.y))
					draw_rect(r.grow(1.5), Color(glow, glow.a * 0.25))
					draw_rect(r, glow)
		# Lanterns along the quay at dusk and night.
		if light in [&"dusk", &"night"]:
			var y := horizon + 4.0
			for i in 7:
				var x := size.x * (0.07 + 0.143 * i)
				draw_circle(Vector2(x, y), 7.0, Color(1.0, 0.86, 0.64, 0.18))
				draw_circle(Vector2(x, y), 2.2, Color(1.0, 0.9, 0.72, 0.95))
				# A short reflection in the water.
				draw_line(Vector2(x, y + 6.0), Vector2(x, y + 16.0), Color(1.0, 0.87, 0.66, 0.35), 1.5)
		# A little mist over the water at dawn.
		if light == &"dawn":
			for i in 3:
				var band := Rect2(0, horizon - 10.0 + i * 9.0, size.x, 9.0)
				draw_rect(band, Color(1, 1, 1, 0.16 - i * 0.04))
		draw_rect(box, UiTheme.color(&"border"), false, 1.0)

	func _gradient(rect: Rect2, from: Color, to: Color) -> void:
		draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
			PackedColorArray([from, from, to, to]))
