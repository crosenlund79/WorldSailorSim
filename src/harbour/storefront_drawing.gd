class_name StorefrontDrawing
extends Node2D
## One frontage on the quay (I026 stage 02, HarbourFront): a business's
## storefront, an ordinary house or the lane into town, drawn procedurally in
## the harbour's regional style (HarbourDressing.TOWNS: Nordic timber, Atlantic
## granite and render, Mediterranean stucco with shutters, tropical painted
## boards under tin).
##
## The facade is an upright elevation above the quay line (y = 0), gently
## foreshortened (FACADE_SCALE), like the painted harbour looks; what stands
## outside on the promenade (crates, a hull on stands, café tables, rolled
## sailcloth) is seen from above like the rest of the ground. Each business is
## recognisable by its architecture, its sign and what stands outside it:
##   boatyard - a corrugated workshop shed, its big doors open on a hull,
##              the yard office beside it, a hull on stands outside;
##   sail loft - a tall loft with a hoist beam and a loading door upstairs,
##              rolled sailcloth on trestles;
##   chandlery - display windows of rope and buoys, fenders hanging by the
##              door, a rack of fenders and coils outside;
##   grocery  - a striped awning, crates of fruit and vegetables, a chalkboard;
##   fishmonger - a stall with its shutter up and crates of fish on ice;
##   café     - a café window and awning, a terrace of tables (QuayLayout);
##   harbour office - a civic front with a clock, a flagpole and the
##              after-hours hatch beside the door.
## The door carries an open or closed sign and an hours plate
## (BusinessHours); while open its windows glow at dusk and at night, a
## closed shop is dark. Ordinary houses light a window or two in the evening.
##
## Art only: the walls, the stations and the people are HarbourFront's. No
## real brands: the signs say what the place is.

const INK := Color("#2A3236")
const SHADOW := Color(0.03, 0.05, 0.06, 0.28)
## The elevation's vertical scale (the slight look-down of the view).
const FACADE_SCALE := 0.62
## Ground-floor height and an upper floor's (drawn units).
const GF := 250.0
const FLOOR := 165.0
const ROOF := 120.0
const LIT := Color("#F4CF8E")
const LIT_SOFT := Color("#E8B56E")
const GLASS := Color("#34444F")
const GLASS_SHINE := Color("#7C8F99")

var front: Dictionary = {}
var layout: QuayLayout
var archetype: StringName = HarbourDressing.ARCHETYPE_NORDIC
## Open now (businesses), or the evening lamps lit (houses).
var is_open := true
## 0 (day) .. 1 (night): how much the lit windows show.
var darkness := 0.0
## The open/closed text on the door ("" for houses and the lane).
var hours_plate := ""
## The homes upstairs (and the houses) have their evening lamps on.
var lamps_on := false

var _w := 0.0
var _rng := RandomNumberGenerator.new()
var _town: Dictionary
var _wall := Color.WHITE
var _roof := Color.WHITE
var _trim := Color.WHITE
var _font: Font
## Window rectangles (local) and whether each is lit when the place is.
var _windows: Array[Dictionary] = []
var _door := Rect2()
var _sign := Rect2()
var _sign_text := ""
var _height := 0.0
var _lights: Node2D


func setup(front_: Dictionary, layout_: QuayLayout) -> void:
	front = front_
	layout = layout_
	archetype = layout.archetype
	_w = float(front.x1) - float(front.x0)
	position = Vector2(float(front.x0), 0.0)
	_town = HarbourDressing.TOWNS.get(archetype, HarbourDressing.TOWNS[HarbourDressing.ARCHETYPE_NORDIC])
	_rng.seed = int(front.seed)
	var facades: Array = _town.facades
	_wall = facades[_rng.randi() % facades.size()]
	var roofs: Array = ((_town.roofs as Dictionary).values()[0] as Array)
	_roof = (roofs[_rng.randi() % roofs.size()] as Array)[0]
	_trim = _town.frame if _town.frame != null else Color("#E8E2D4")
	var theme := ThemeDB.get_project_theme()
	_font = theme.get_font(&"font", &"DisplayHeader") if theme else ThemeDB.fallback_font
	if _font == null:
		_font = ThemeDB.fallback_font
	_compose()
	_lights = Node2D.new()
	_lights.name = "Lights"
	_lights.z_index = 1
	_lights.draw.connect(_draw_lights)
	add_child(_lights)


func get_kind() -> StringName:
	return front.get("kind", QuayLayout.HOUSE)


## The door's centre on the quay line (global x).
func get_door_x() -> float:
	return float(front.door)


## The storefront's outline for the focus highlight (global points): the
## ground floor with its sign.
func get_highlight_outline() -> PackedVector2Array:
	var top := -GF * FACADE_SCALE - 6.0
	if get_kind() == QuayLayout.BOATYARD:
		top = -_height * FACADE_SCALE
	var rect := Rect2(4.0, top, _w - 8.0, -top + 8.0)
	if get_kind() == QuayLayout.LANE:
		rect = Rect2(0.0, -220.0, _w, 230.0)
	var points := PackedVector2Array()
	for p in HighlightResolver.rounded_rect(rect, 10.0):
		points.append(to_global(p))
	return points


## Shows the state of the hour: open or shut, how dark it is.
func set_state(open: bool, dark: float, plate: String, lamps := false) -> void:
	if open == is_open and absf(dark - darkness) < 0.02 and plate == hours_plate and lamps == lamps_on:
		return
	is_open = open
	lamps_on = lamps
	darkness = dark
	hours_plate = plate
	queue_redraw()
	if _lights:
		_lights.queue_redraw()


func get_lights_node() -> Node2D:
	return _lights


## The lit window rectangles now (local), for tests and the lighting.
func get_lit_windows() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if darkness < 0.3:
		return out
	for window in _windows:
		if window.lit and (lamps_on if window.get("home", false) or get_kind() == QuayLayout.HOUSE else is_open):
			out.append(window.rect)
	return out


# --- Composition ------------------------------------------------------------------

func _s(h: float) -> float:
	return h * FACADE_SCALE


func _compose() -> void:
	_windows.clear()
	var kind := get_kind()
	var floors := 1
	match kind:
		QuayLayout.BOATYARD:
			_height = 420.0
			_wall = Color("#8E989B") if archetype != HarbourDressing.ARCHETYPE_TROPICAL else Color("#9DB0AA")
			_door = Rect2(_w * 0.82 - 50.0, -_s(170.0), 100.0, _s(170.0))
			_windows.append({"rect": Rect2(_w * 0.82 + 62.0, -_s(150.0), 110.0, _s(80.0)), "lit": true})
			_sign_text = Loc.t("Boatyard")
			return
		QuayLayout.SAIL_LOFT:
			floors = 3
		QuayLayout.FISHMONGER:
			_height = 250.0
			_wall = Color("#DCE3E2") if archetype != HarbourDressing.ARCHETYPE_NORDIC else Color("#5E7884")
			_door = Rect2(_w - 120.0, -_s(170.0), 90.0, _s(170.0))
			_sign_text = Loc.t("Fresh Fish")
			return
		QuayLayout.LANE:
			_height = 0.0
			return
		QuayLayout.HOUSE:
			floors = 2 + (_rng.randi() % 2)
		QuayLayout.HARBOUR_OFFICE:
			floors = 2
			if archetype in [HarbourDressing.ARCHETYPE_NORDIC, HarbourDressing.ARCHETYPE_ATLANTIC]:
				_wall = Color("#E6E2D6")
		_:
			floors = 2
	_height = GF + FLOOR * (floors - 1)
	var door_x := float(front.door) - float(front.x0)
	_door = Rect2(door_x - 50.0, -_s(165.0), 100.0, _s(165.0))
	# Ground-floor windows: a shop window beside the door for a business,
	# ordinary windows for a house; then the upper floors' windows.
	var pitch := 190.0 if kind != QuayLayout.SAIL_LOFT else 230.0
	if kind in [QuayLayout.CHANDLERY, QuayLayout.GROCERY, QuayLayout.CAFE]:
		for side: float in [-1.0, 1.0]:
			var x0 := _door.position.x - 20.0 - 330.0 if side < 0.0 else _door.end.x + 20.0
			var x1 := x0 + 330.0
			x0 = maxf(x0, 30.0)
			x1 = minf(x1, _w - 30.0)
			if x1 - x0 > 120.0:
				_windows.append({"rect": Rect2(x0, -_s(140.0), x1 - x0, _s(118.0)), "lit": true, "shop": true})
	else:
		var x := 40.0
		while x + 110.0 < _w - 30.0:
			if x + 110.0 < _door.position.x - 15.0 or x > _door.end.x + 15.0:
				_windows.append({"rect": Rect2(x, -_s(150.0), 110.0, _s(110.0)), "lit": kind != QuayLayout.HOUSE or _rng.randf() < 0.5})
			x += pitch
	for f in range(1, floors):
		var y := -_s(GF + FLOOR * f) + _s(40.0)
		var n := maxi(1, int((_w - 60.0) / pitch))
		for c in n:
			var cx := 30.0 + (c + 0.5) * (_w - 60.0) / n
			var big := kind == QuayLayout.SAIL_LOFT and f == floors - 1 and c == n / 2
			if big:
				continue  # the loading door
			_windows.append({"rect": Rect2(cx - 50.0, y, 100.0, _s(100.0)), "lit": _rng.randf() < 0.45, "home": true})
	match kind:
		QuayLayout.CHANDLERY:
			_sign_text = Loc.t("Chandlery")
		QuayLayout.SAIL_LOFT:
			_sign_text = Loc.t("Sail Loft")
		QuayLayout.GROCERY:
			_sign_text = Loc.t("Groceries")
		QuayLayout.CAFE:
			_sign_text = Loc.t("Café")
		QuayLayout.HARBOUR_OFFICE:
			_sign_text = Loc.t("Harbour Office")


# --- Drawing -----------------------------------------------------------------------

func _draw() -> void:
	_rng.seed = int(front.seed)  # the same frontage on every redraw
	var kind := get_kind()
	match kind:
		QuayLayout.LANE:
			_draw_lane()
			return
		QuayLayout.BOATYARD:
			_draw_boatyard()
		QuayLayout.FISHMONGER:
			_draw_fish_stall()
		_:
			_draw_building()
	_draw_outside()


func _draw_building() -> void:
	var kind := get_kind()
	var top := -_s(_height)
	# The wall, its base course and the floor bands.
	draw_rect(Rect2(0.0, top, _w, -top), _wall)
	_wall_texture(Rect2(0.0, top, _w, -top))
	draw_rect(Rect2(0.0, -_s(18.0), _w, _s(18.0)), _wall.darkened(0.25))  # plinth
	for f in range(1, int(round((_height - GF) / FLOOR)) + 1):
		var y := -_s(GF + FLOOR * (f - 1))
		draw_line(Vector2(0.0, y), Vector2(_w, y), Color(_wall.darkened(0.18), 0.8), 2.0)
	_draw_roof(top)
	for window in _windows:
		_draw_window(window)
	_draw_door()
	if kind == QuayLayout.GROCERY or kind == QuayLayout.CAFE:
		_draw_awning(kind)
	if kind == QuayLayout.CHANDLERY:
		_draw_chandlery_front()
	if kind == QuayLayout.SAIL_LOFT:
		_draw_loft_front()
	if kind == QuayLayout.HARBOUR_OFFICE:
		_draw_office_front()
	if not _sign_text.is_empty():
		_draw_sign()
	# The corners and the eaves' shadow on the wall.
	draw_line(Vector2(0.0, top), Vector2(0.0, 0.0), Color(INK, 0.45), 2.0)
	draw_line(Vector2(_w, top), Vector2(_w, 0.0), Color(INK, 0.45), 2.0)


func _wall_texture(rect: Rect2) -> void:
	match archetype:
		HarbourDressing.ARCHETYPE_NORDIC:
			# Vertical timber cladding, board and batten.
			var x := rect.position.x + 9.0
			while x < rect.end.x:
				draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(_wall.darkened(0.22), 0.55), 1.4)
				x += 18.0
		HarbourDressing.ARCHETYPE_ATLANTIC:
			# Granite quoins at the corners.
			var y := rect.end.y - 26.0
			var k := 0
			while y > rect.position.y:
				var w := 34.0 if k % 2 == 0 else 22.0
				draw_rect(Rect2(rect.position.x, y - 22.0, w, 22.0), _wall.darkened(0.12))
				draw_rect(Rect2(rect.end.x - w, y - 22.0, w, 22.0), _wall.darkened(0.12))
				y -= 26.0
				k += 1
		HarbourDressing.ARCHETYPE_TROPICAL:
			# Horizontal weatherboards.
			var y := rect.position.y + 10.0
			while y < rect.end.y:
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(_wall.darkened(0.15), 0.5), 1.2)
				y += 13.0
		_:
			# Stucco: a few soft patches.
			for i in 5:
				var c := Vector2(_rng.randf_range(rect.position.x + 30.0, rect.end.x - 30.0), _rng.randf_range(rect.position.y + 20.0, rect.end.y - 20.0))
				draw_circle(c, _rng.randf_range(18.0, 40.0), Color(_wall.darkened(0.06), 0.35))


func _draw_roof(top: float) -> void:
	var r := _s(ROOF)
	match archetype:
		HarbourDressing.ARCHETYPE_MEDITERRANEAN:
			# A low pantiled roof with a deep eave, or a terrace's parapet.
			if int(front.seed) % 3 == 0:
				draw_rect(Rect2(-4.0, top - 16.0, _w + 8.0, 16.0), _wall.lightened(0.08))
				draw_rect(Rect2(-4.0, top - 2.0, _w + 8.0, 4.0), Color(INK, 0.25))
			else:
				draw_colored_polygon(PackedVector2Array([Vector2(-14, top), Vector2(_w + 14, top), Vector2(_w - 20, top - r * 0.55),
					Vector2(20, top - r * 0.55)]), _roof)
				var x := -10.0
				while x < _w + 10.0:
					draw_line(Vector2(x, top), Vector2(x + (_w / 2.0 - x) * 0.04, top - r * 0.55), Color(_roof.darkened(0.25), 0.6), 3.0)
					x += 22.0
				draw_rect(Rect2(-14.0, top - 4.0, _w + 28.0, 6.0), _roof.darkened(0.3))
		HarbourDressing.ARCHETYPE_TROPICAL:
			draw_colored_polygon(PackedVector2Array([Vector2(-18, top + 4), Vector2(_w + 18, top + 4), Vector2(_w - 30, top - r * 0.6),
				Vector2(30, top - r * 0.6)]), _roof)
			var x := -14.0
			while x < _w + 14.0:
				draw_line(Vector2(x, top + 4), Vector2(x, top - r * 0.6 + 2), Color(_roof.lightened(0.15), 0.5), 1.6)
				x += 9.0
			draw_rect(Rect2(-18.0, top, _w + 36.0, 5.0), _roof.darkened(0.3))
		_:
			# A pitched roof seen along its ridge (tile or slate courses), with
			# a chimney now and then; Atlantic stacks at the gables.
			draw_colored_polygon(PackedVector2Array([Vector2(-10, top), Vector2(_w + 10, top), Vector2(_w - 10, top - r),
				Vector2(10, top - r)]), _roof)
			var y := top - 12.0
			while y > top - r:
				draw_line(Vector2(0, y), Vector2(_w, y), Color(_roof.darkened(0.25), 0.5), 1.4)
				y -= 13.0
			draw_rect(Rect2(-10.0, top - 3.0, _w + 20.0, 5.0), Color(INK, 0.35))
			if archetype == HarbourDressing.ARCHETYPE_ATLANTIC:
				for sx: float in [14.0, _w - 74.0]:
					draw_rect(Rect2(sx, top - r - 34.0, 60.0, 40.0), _wall.darkened(0.15))
					for k in 3:
						draw_rect(Rect2(sx + 6.0 + k * 18.0, top - r - 44.0, 12.0, 12.0), Color("#9A6A52"))
			elif int(front.seed) % 2 == 0:
				var cx := _w * 0.3 + float(int(front.seed) % 7) * 20.0
				draw_rect(Rect2(cx, top - r - 26.0, 40.0, 40.0), Color("#5C5550"))
				draw_rect(Rect2(cx - 3.0, top - r - 30.0, 46.0, 6.0), Color("#4A4440"))


func _draw_window(window: Dictionary) -> void:
	var rect: Rect2 = window.rect
	var lit: bool = darkness > 0.25 and (window.rect as Rect2) in get_lit_windows()
	var shop: bool = window.get("shop", false)
	var shutter_colours = _town.shutter
	if shutter_colours != null and not shop:
		var shutter: Color = (shutter_colours as Array)[int(front.seed) % (shutter_colours as Array).size()]
		var sw := rect.size.x * 0.42
		draw_rect(Rect2(rect.position.x - sw - 3.0, rect.position.y, sw, rect.size.y), shutter)
		draw_rect(Rect2(rect.end.x + 3.0, rect.position.y, sw, rect.size.y), shutter)
		for k in 5:
			var y := rect.position.y + rect.size.y * (k + 0.5) / 5.0
			draw_line(Vector2(rect.position.x - sw - 1.0, y), Vector2(rect.position.x - 5.0, y), shutter.darkened(0.3), 1.0)
			draw_line(Vector2(rect.end.x + 5.0, y), Vector2(rect.end.x + sw + 1.0, y), shutter.darkened(0.3), 1.0)
	draw_rect(rect.grow(4.0), _trim.darkened(0.05))
	draw_rect(rect, LIT_SOFT.lerp(LIT, 0.5) if lit else GLASS)
	if not lit:
		draw_colored_polygon(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x * 0.35, 0.0),
			rect.position + Vector2(0.0, rect.size.y * 0.6)]), Color(GLASS_SHINE, 0.35))
	if shop:
		_draw_display(rect)
	# Glazing bars: a cross for the Nordic and Atlantic houses.
	if not shop and archetype in [HarbourDressing.ARCHETYPE_NORDIC, HarbourDressing.ARCHETYPE_ATLANTIC]:
		draw_line(Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y), _trim, 3.0)
		draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), _trim, 3.0)
	draw_rect(Rect2(rect.position.x - 6.0, rect.end.y + 2.0, rect.size.x + 12.0, 5.0), _wall.darkened(0.2))  # sill


## What a shop shows in its window (seen through the glass).
func _draw_display(rect: Rect2) -> void:
	var base := rect.end.y - 6.0
	match get_kind():
		QuayLayout.CHANDLERY:
			for k in 3:
				var c := Vector2(rect.position.x + rect.size.x * (k + 0.5) / 3.0, base - 18.0)
				if k == 1:
					draw_arc(c + Vector2(0, -14), 20.0, 0, TAU, 20, Color("#D9783A"), 8.0, true)  # a life ring
				else:
					for ring in 3:
						draw_arc(c, 18.0 - ring * 5.0, 0, TAU, 18, Color("#C9BE9A"), 3.0, true)  # coiled rope
		QuayLayout.GROCERY:
			for k in 4:
				var c := Vector2(rect.position.x + rect.size.x * (k + 0.5) / 4.0, base - 10.0)
				draw_rect(Rect2(c - Vector2(26, 12), Vector2(52, 22)), Color("#8A6A44"))
				var fruit: Color = [Color("#C0533F"), Color("#E0A63A"), Color("#6E8B3D"), Color("#D27A3A")][k]
				for f in 4:
					draw_circle(c + Vector2(-16 + f * 11, -12), 6.0, fruit)
		QuayLayout.CAFE:
			draw_rect(Rect2(rect.position.x + 10.0, base - 26.0, rect.size.x - 20.0, 6.0), Color("#6B4E36"))  # the counter
			for k in 3:
				var c := Vector2(rect.position.x + rect.size.x * (k + 0.5) / 3.0, base - 34.0)
				draw_rect(Rect2(c - Vector2(8, 10), Vector2(16, 12)), Color("#E9E4D8"))  # cups
			draw_circle(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 20.0), 9.0, Color(LIT, 0.7))  # a pendant lamp


func _draw_door() -> void:
	var wood := Color("#5A4636") if archetype != HarbourDressing.ARCHETYPE_MEDITERRANEAN else Color("#4F6B55")
	if archetype == HarbourDressing.ARCHETYPE_TROPICAL:
		wood = Color("#4F6F7E")
	draw_rect(_door.grow(5.0), _trim.darkened(0.1))
	draw_rect(_door, wood)
	var glass := _door_glass()
	var lit := is_open and darkness > 0.25 and get_kind() != QuayLayout.HOUSE
	draw_rect(glass, LIT if lit else GLASS)
	draw_circle(Vector2(_door.end.x - 12.0, glass.end.y + 6.0), 3.0, Color("#C8B07A"))  # handle
	draw_rect(Rect2(_door.position.x - 8.0, -6.0, _door.size.x + 16.0, 6.0), _wall.darkened(0.35))  # step
	if hours_plate.is_empty() or get_kind() == QuayLayout.HOUSE:
		return
	# The open/closed sign hanging in the door's glass.
	var tag := Rect2(glass.get_center() - Vector2(30, 9), Vector2(60, 18))
	draw_rect(tag, Color("#F1EEE6") if is_open else Color("#B44A3A"))
	draw_rect(tag, Color(INK, 0.6), false, 1.0)
	var word := Loc.t("OPEN") if is_open else Loc.t("CLOSED")
	_centred_text(word, tag.get_center() + Vector2(0, 5), 13, Color("#2E5E3A") if is_open else Color("#F6EFE6"), tag.size.x - 4.0)
	# The hours on a small brass plate on the door's lower panel.
	var plate := Rect2(_door.position.x + 6.0, -31.0, _door.size.x - 12.0, 20.0)
	draw_rect(plate, Color("#B89B5E"))
	draw_rect(plate, Color("#7A643A"), false, 1.5)
	_centred_text(hours_plate, plate.get_center() + Vector2(0, 5), 12, Color("#2B2418"), plate.size.x - 6.0)


## The door's glass panel (local), under the transom.
func _door_glass() -> Rect2:
	return Rect2(_door.position + Vector2(16, 22), Vector2(_door.size.x - 32, _door.size.y * 0.38))


func _draw_sign() -> void:
	var kind := get_kind()
	var size := 30
	var text_w := minf(_font.get_string_size(_sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, _w - 80.0)
	var y := -_s(GF) + 7.0
	var cx := _w / 2.0
	_sign = Rect2(cx - text_w / 2.0 - 22.0, y, text_w + 44.0, 41.0)
	var board: Color
	var letters: Color
	match kind:
		QuayLayout.CHANDLERY:
			board = Color("#23394A")
			letters = Color("#EEF2F1")
		QuayLayout.SAIL_LOFT:
			board = Color("#EDE8DA")
			letters = Color("#2D3E52")
		QuayLayout.GROCERY:
			board = Color("#3F5E3A")
			letters = Color("#F2EEDC")
		QuayLayout.CAFE:
			board = Color("#EFE4CC")
			letters = Color("#5A3B28")
		QuayLayout.HARBOUR_OFFICE:
			board = Color("#1F2F45")
			letters = Color("#E3C779")
		_:
			board = Color("#23394A")
			letters = Color("#EEF2F1")
	draw_rect(Rect2(_sign.position + Vector2(3, 4), _sign.size), SHADOW)
	draw_rect(_sign, board)
	draw_rect(_sign, board.darkened(0.35), false, 2.0)
	_centred_text(_sign_text, _sign.get_center() + Vector2(0, 10), size, letters, _sign.size.x - 20.0)


func _draw_awning(kind: StringName) -> void:
	var y := -_s(GF) + 50.0
	var x0 := 20.0
	var x1 := _w - 20.0
	var depth := 16.0
	var a: Color = Color("#3F6B4A") if kind == QuayLayout.GROCERY else Color("#7A3B32")
	if archetype == HarbourDressing.ARCHETYPE_MEDITERRANEAN:
		a = Color("#3E5F7A") if kind == QuayLayout.CAFE else Color("#A9563E")
	var b := Color("#EEE8DA")
	var stripe := 40.0
	var x := x0
	var k := 0
	while x < x1:
		var w := minf(stripe, x1 - x)
		var c := a if k % 2 == 0 else (b if kind == QuayLayout.GROCERY else a.lightened(0.12))
		draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w + 3.0, y + depth),
			Vector2(x - 3.0 + 0.0, y + depth)]), c)
		for q in 2:  # the scalloped valance
			draw_circle(Vector2(x + w * (q + 0.5) / 2.0, y + depth), w / 4.5, c)
		x += stripe
		k += 1
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(INK, 0.5), 2.0)
	draw_rect(Rect2(x0, y + depth + 4.0, x1 - x0, 6.0), Color(0, 0, 0, 0.12))


func _draw_chandlery_front() -> void:
	# Fenders hanging on a rail beside the door, a buoy above them.
	var x := _free_wall_x(90.0)
	if x < 0.0:
		return
	draw_line(Vector2(x - 40.0, -_s(150.0)), Vector2(x + 40.0, -_s(150.0)), Color("#6E7678"), 3.0)
	for k in 3:
		var fx := x - 28.0 + k * 28.0
		var colour: Color = [Color("#2F3E4C"), Color("#E8E6DF"), Color("#2F3E4C")][k]
		draw_line(Vector2(fx, -_s(150.0)), Vector2(fx, -_s(130.0)), Color("#C4CBCC"), 1.4)
		draw_rect(Rect2(fx - 9.0, -_s(130.0), 18.0, 46.0), colour)
		draw_rect(Rect2(fx - 9.0, -_s(130.0), 18.0, 46.0), Color(INK, 0.5), false, 1.0)


## A stretch of ground-floor wall (centre x) this wide, clear of the door
## and the windows; -1 when there is none.
func _free_wall_x(width: float) -> float:
	var x := 30.0 + width / 2.0
	while x < _w - 30.0 - width / 2.0:
		var span := Rect2(x - width / 2.0, -_s(GF) + 50.0, width, _s(GF) - 50.0)
		var clear := not span.intersects(_door.grow(10.0))
		for window in _windows:
			if clear and span.intersects((window.rect as Rect2).grow(8.0)):
				clear = false
		if clear:
			return x
		x += 10.0
	return -1.0


func _draw_loft_front() -> void:
	# The loading door upstairs with its hoist beam and block.
	var top := -_s(_height)
	var door := Rect2(_w / 2.0 - 60.0, top + _s(50.0), 120.0, _s(130.0))
	draw_rect(door.grow(5.0), _trim)
	draw_rect(door, Color("#6A5440"))
	draw_line(door.position + Vector2(60, 0), door.position + Vector2(60, door.size.y), Color("#4A3A2C"), 2.0)
	draw_line(Vector2(_w / 2.0, top + 6.0), Vector2(_w / 2.0, top - 30.0), Color("#3A3330"), 6.0)
	draw_line(Vector2(_w / 2.0 - 4.0, top - 30.0), Vector2(_w / 2.0 + 70.0, top - 30.0), Color("#3A3330"), 7.0)
	draw_line(Vector2(_w / 2.0 + 64.0, top - 26.0), Vector2(_w / 2.0 + 64.0, top + 30.0), Color("#B9B2A0"), 1.6)
	draw_circle(Vector2(_w / 2.0 + 64.0, top + 32.0), 6.0, Color("#3A3330"))


func _draw_office_front() -> void:
	# A clock above the door, a flagpole, the after-hours hatch with its bell.
	var clock_at := Vector2(_door.get_center().x, -_s(GF) + 4.0 - 20.0)
	draw_circle(clock_at, 22.0, Color("#2B2B2B"))
	draw_circle(clock_at, 18.0, Color("#F2EEE2"))
	var h := 0.0
	if GameSession.is_active():
		h = BusinessHours.local_hours(layout.port_id, GameSession.get_game_time())
	var minute := fposmod(h, 1.0) * TAU
	var hour := fposmod(h, 12.0) / 12.0 * TAU
	draw_line(clock_at, clock_at + Vector2.from_angle(hour - PI / 2.0) * 9.0, Color("#2B2B2B"), 2.4)
	draw_line(clock_at, clock_at + Vector2.from_angle(minute - PI / 2.0) * 14.0, Color("#2B2B2B"), 1.6)
	var hatch := get_hatch_rect()
	draw_rect(hatch.grow(5.0), _trim.darkened(0.1))
	draw_rect(hatch, LIT if darkness > 0.25 else GLASS)
	draw_rect(Rect2(hatch.position.x - 8.0, hatch.end.y, hatch.size.x + 16.0, 8.0), Color("#6B5440"))  # the little shelf
	draw_circle(Vector2(hatch.end.x + 2.0, hatch.end.y - 4.0), 5.0, Color("#C8A85A"))  # the bell
	# The flagpole at the corner, the harbour's flag.
	var pole := Vector2(_w - 26.0, -_s(_height) - 30.0)
	draw_line(pole + Vector2(0, _s(_height) + 30.0 - _s(GF)), pole, Color("#D8D8D2"), 4.0)
	draw_colored_polygon(PackedVector2Array([pole + Vector2(2, 4), pole + Vector2(52, 10), pole + Vector2(50, 34), pole + Vector2(2, 30)]),
		Color("#B33A3A") if archetype == HarbourDressing.ARCHETYPE_NORDIC else Color("#2E4F7A"))


## The after-hours hatch beside the office door (local).
func get_hatch_rect() -> Rect2:
	var x := _door.end.x + 110.0 if _door.end.x + 190.0 < _w else _door.position.x - 170.0
	return Rect2(x, -_s(150.0), 70.0, _s(80.0))


func _draw_boatyard() -> void:
	var top := -_s(_height)
	# The shed: corrugated sheeting, its gable end to the quay.
	var gable := PackedVector2Array([Vector2(-6, top + 10), Vector2(_w * 0.36, top - 70), Vector2(_w * 0.72 + 6, top + 10)])
	draw_rect(Rect2(0.0, top + 10.0, _w * 0.72, -top - 10.0), _wall)
	draw_colored_polygon(gable, _wall.lightened(0.05))
	var x := 6.0
	while x < _w * 0.72:
		draw_line(Vector2(x, top + 10.0), Vector2(x, 0.0), Color(_wall.darkened(0.2), 0.6), 1.6)
		x += 12.0
	draw_polyline(gable, Color(INK, 0.5), 3.0)
	# The big doors, slid open on the hull inside.
	var doors := Rect2(_w * 0.08, -_s(330.0), _w * 0.56, _s(330.0))
	draw_rect(doors, Color("#1E2428"))
	var hull := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		hull.append(Vector2(doors.position.x + 40.0 + t * (doors.size.x - 80.0), doors.end.y - 50.0 - sin(t * PI) * 10.0))
	for i in range(16, -1, -1):
		var t := float(i) / 16.0
		hull.append(Vector2(doors.position.x + 40.0 + t * (doors.size.x - 80.0) + (12.0 if i == 16 else 0.0), doors.end.y - 50.0 - 52.0 + pow(t, 3.0) * 14.0))
	draw_colored_polygon(hull, Color("#C9CCC6"))
	draw_rect(Rect2(doors.position.x + 40.0, doors.end.y - 64.0, doors.size.x - 80.0, 14.0), Color("#8E3B30"))  # antifouling
	for sx: float in [0.25, 0.5, 0.75]:
		draw_line(Vector2(doors.position.x + doors.size.x * sx, doors.end.y - 48.0), Vector2(doors.position.x + doors.size.x * sx, doors.end.y),
			Color("#5A5F62"), 4.0)
	draw_rect(Rect2(doors.position.x - 30.0, doors.position.y, 30.0, doors.size.y), _wall.darkened(0.1))  # the slid door
	draw_rect(Rect2(doors.end.x, doors.position.y, 30.0, doors.size.y), _wall.darkened(0.1))
	draw_rect(doors, Color(INK, 0.6), false, 2.0)
	# The name, painted large on the gable.
	_centred_text(Loc.t("Boatyard"), Vector2(_w * 0.36, top + 46.0), 38, Color("#F2F0E8"), _w * 0.6)
	# The yard office beside it (timber, a door and a window).
	var office := Rect2(_w * 0.72, -_s(230.0), _w * 0.28, _s(230.0))
	draw_rect(office, _town.facades[0] if archetype == HarbourDressing.ARCHETYPE_NORDIC else _wall.darkened(0.1))
	draw_rect(Rect2(office.position.x - 8.0, office.position.y - 12.0, office.size.x + 16.0, 14.0), _roof)
	for window in _windows:
		_draw_window(window)
	_draw_door()
	_sign = Rect2()


func _draw_fish_stall() -> void:
	var top := -_s(_height)
	draw_rect(Rect2(0.0, top, _w, -top), _wall)
	# The stall's opening: the shutter rolled up (open) or down (closed).
	var opening := Rect2(30.0, -_s(200.0), _w - 170.0, _s(140.0))
	if is_open:
		draw_rect(opening, Color("#24343C"))
		draw_rect(Rect2(opening.position.x, opening.end.y - 22.0, opening.size.x, 22.0), Color("#DDE6E6"))  # the counter's ice
		for k in 6:
			var c := Vector2(opening.position.x + 30.0 + k * (opening.size.x - 60.0) / 5.0, opening.end.y - 14.0)
			_fish(c, 20.0, Color("#AFC0C6"))
		draw_rect(Rect2(opening.position.x, opening.position.y - 14.0, opening.size.x, 14.0), Color("#8A9AA0"))  # the rolled shutter
	else:
		draw_rect(opening, Color("#8A9AA0"))
		var y := opening.position.y + 8.0
		while y < opening.end.y:
			draw_line(Vector2(opening.position.x, y), Vector2(opening.end.x, y), Color("#6E7C82"), 1.5)
			y += 10.0
	# Blue and white awning over the counter.
	var y0 := opening.position.y - 30.0
	var x := opening.position.x - 10.0
	var k := 0
	while x < opening.end.x + 10.0:
		draw_rect(Rect2(x, y0, 30.0, 30.0), Color("#2E5E86") if k % 2 == 0 else Color("#ECEFEF"))
		x += 30.0
		k += 1
	draw_rect(Rect2(-8.0, top - 10.0, _w + 16.0, 12.0), _roof)
	_draw_door()
	# The sign: a fish board over the awning.
	var board := Rect2(opening.position.x + opening.size.x / 2.0 - 110.0, top + 4.0, 220.0, 40.0)
	_sign = board
	draw_rect(board, Color("#2E5E86"))
	_centred_text(_sign_text, board.get_center() + Vector2(0, 10), 26, Color("#F2F2EC"), board.size.x - 12.0)


func _fish(at: Vector2, length: float, colour: Color) -> void:
	var body := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		body.append(at + Vector2(cos(a) * length * 0.5, sin(a) * length * 0.16))
	draw_colored_polygon(body, colour)
	draw_colored_polygon(PackedVector2Array([at + Vector2(length * 0.45, 0), at + Vector2(length * 0.7, -length * 0.18),
		at + Vector2(length * 0.7, length * 0.18)]), colour.darkened(0.15))
	draw_circle(at + Vector2(-length * 0.32, -1.0), 1.4, Color("#1E2428"))


func _draw_lane() -> void:
	# A lane into town between the houses, rising away from the quay.
	var paving := (HarbourDressing.STYLES.get(archetype, HarbourDressing.STYLES[HarbourDressing.ARCHETYPE_NORDIC]).paving as Color).darkened(0.08)
	var far_y := -420.0
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(_w, 0), Vector2(_w * 0.7, far_y), Vector2(_w * 0.3, far_y)]), paving)
	var y := -20.0
	var k := 0
	while y > far_y:
		var t := y / far_y
		var x0 := lerpf(0.0, _w * 0.3, t)
		var x1 := lerpf(_w, _w * 0.7, t)
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(paving.darkened(0.2), 0.5 - t * 0.3), 1.5)
		y -= 22.0 * (1.0 - t * 0.6)
		k += 1
	# The walls of the houses either side, in shade, and a lamp on a bracket.
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(_w * 0.3, far_y), Vector2(0, far_y)]), Color(0.1, 0.12, 0.13, 0.45))
	draw_colored_polygon(PackedVector2Array([Vector2(_w, 0), Vector2(_w * 0.7, far_y), Vector2(_w, far_y)]), Color(0.1, 0.12, 0.13, 0.3))
	var lamp := Vector2(_w * 0.82, -220.0)
	draw_line(lamp + Vector2(30, 0), lamp, Color("#2E3336"), 3.0)
	draw_rect(Rect2(lamp + Vector2(-8, 0), Vector2(16, 22)), Color("#2E3336"))
	draw_rect(Rect2(lamp + Vector2(-5, 4), Vector2(10, 14)), LIT if darkness > 0.25 else Color("#E8E2C8"))
	# A finger post: into town.
	var post := Vector2(_w * 0.22, -10.0)
	draw_line(post, post + Vector2(0, -150), Color("#4A4440"), 5.0)
	var board := Rect2(post + Vector2(-6, -148), Vector2(150, 30))
	draw_colored_polygon(PackedVector2Array([board.position, board.position + Vector2(board.size.x - 14, 0),
		board.position + Vector2(board.size.x, board.size.y / 2.0), board.position + Vector2(board.size.x - 14, board.size.y),
		board.position + Vector2(0, board.size.y)]), Color("#EDE8DA"))
	_centred_text(Loc.t("Town"), board.get_center() + Vector2(-4, 6), 16, Color("#2D3E52"), board.size.x - 20.0)


## What stands outside on the promenade, seen from above.
func _draw_outside() -> void:
	match get_kind():
		QuayLayout.BOATYARD:
			_draw_hull_on_stands(Vector2(_w * 0.36, HULL_Y))
			for k in 2:
				var drum := Vector2(_w * 0.7 + k * 34.0, 70.0)
				draw_circle(drum + Vector2(4, 5), 15.0, SHADOW)
				draw_circle(drum, 15.0, Color("#3E6B8A") if k == 0 else Color("#8A3B30"))
				draw_circle(drum, 9.0, (Color("#3E6B8A") if k == 0 else Color("#8A3B30")).lightened(0.15))
			# A trestle workbench with tools.
			var bench := Rect2(_w * 0.06, 50.0, 160.0, 44.0)
			draw_rect(Rect2(bench.position + Vector2(5, 6), bench.size), SHADOW)
			draw_rect(bench, Color("#8B6A48"))
			draw_rect(Rect2(bench.position + Vector2(18, 12), Vector2(40, 8)), Color("#5A5F62"))
			draw_rect(Rect2(bench.position + Vector2(80, 22), Vector2(54, 10)), Color("#B34A32"))
		QuayLayout.SAIL_LOFT:
			for k in 2:
				var at := Vector2(_w * 0.2 + k * 90.0, 78.0)
				draw_rect(Rect2(at + Vector2(-60, -14) + Vector2(5, 6), Vector2(200, 28)), SHADOW)
				draw_rect(Rect2(at + Vector2(-60, -14), Vector2(200, 28)), Color("#EDEBE3"))  # rolled sailcloth
				for r in 4:
					draw_line(at + Vector2(-60 + r * 50, -14), at + Vector2(-60 + r * 50, 14), Color("#C9C5B8"), 1.2)
				draw_line(at + Vector2(-70, -20), at + Vector2(-70, 20), Color("#6B5440"), 5.0)  # trestle
				draw_line(at + Vector2(150, -20), at + Vector2(150, 20), Color("#6B5440"), 5.0)
		QuayLayout.CHANDLERY:
			var at := Vector2(_w * 0.82, 70.0)
			if absf(at.x + float(front.x0) - float(front.door)) < 120.0:
				at.x = _w * 0.16
			for k in 3:
				var buoy := at + Vector2(k * 30.0 - 30.0, 0.0)
				draw_circle(buoy + Vector2(3, 4), 13.0, SHADOW)
				draw_circle(buoy, 13.0, [Color("#D9783A"), Color("#E8E6DF"), Color("#2F3E4C")][k])
			var coil := at + Vector2(0.0, 48.0)
			for r in 4:
				draw_arc(coil, 22.0 - r * 5.0, 0, TAU, 22, Color("#C9BE9A").darkened(r * 0.06), 3.4, true)
		QuayLayout.GROCERY:
			var door_x := float(front.door) - float(front.x0)
			var x := door_x + 90.0 if door_x < _w / 2.0 else door_x - 90.0 - 4 * 64.0
			for k in 4:
				var crate := Rect2(x + k * 64.0, 40.0, 56.0, 40.0)
				if crate.position.x < 10.0 or crate.end.x > _w - 10.0:
					continue
				draw_rect(Rect2(crate.position + Vector2(4, 5), crate.size), SHADOW)
				draw_rect(crate, Color("#9A7650"))
				var fruit: Color = [Color("#C0533F"), Color("#6E8B3D"), Color("#E0A63A"), Color("#D27A3A")][k]
				for f in 6:
					draw_circle(crate.position + Vector2(10 + (f % 3) * 18, 12 + (f / 3) * 16), 7.0, fruit)
			# The chalkboard, on its A-frame.
			# The chalkboard on the door's other side from the crates.
			var board_x := door_x - 110.0 if door_x < _w / 2.0 else door_x + 110.0
			var board := Rect2(clampf(board_x, 40.0, _w - 40.0) - 30.0, 54.0, 60.0, 26.0)
			draw_rect(Rect2(board.position + Vector2(4, 5), board.size), SHADOW)
			draw_rect(board, Color("#2B2F2C"))
			draw_rect(board, Color("#7A5A3A"), false, 3.0)
		QuayLayout.FISHMONGER:
			# Crates of fish on ice on a table in front of the stall.
			var table := Rect2(30.0, 30.0, _w - 210.0, 70.0)
			draw_rect(Rect2(table.position + Vector2(5, 6), table.size), SHADOW)
			draw_rect(table, Color("#8E9A9E"))
			var crates := maxi(2, int(table.size.x / 90.0))
			for k in crates:
				var crate := Rect2(table.position.x + 8.0 + k * (table.size.x - 16.0) / crates, table.position.y + 8.0,
					(table.size.x - 16.0) / crates - 8.0, table.size.y - 16.0)
				draw_rect(crate, Color("#E8EEF0") if is_open else Color("#5E7884"))
				if is_open:
					for f in 3:
						_fish(crate.position + Vector2(crate.size.x * (f + 0.5) / 3.0, crate.size.y * 0.5 + (f % 2) * 6.0 - 3.0),
							minf(crate.size.x / 3.2, 30.0), [Color("#A8B7BD"), Color("#C79A7A"), Color("#9EAAA0")][(k + f) % 3])
			draw_circle(Vector2(_w - 150.0, 60.0), 12.0, Color("#B9C0C2"))  # the scale's pan
		QuayLayout.CAFE:
			_draw_terrace()
		QuayLayout.HARBOUR_OFFICE:
			# Two potted bay trees by the door.
			for side: float in [-1.0, 1.0]:
				var pot := Vector2(_door.get_center().x + side * 90.0, 26.0)
				draw_circle(pot + Vector2(4, 5), 18.0, SHADOW)
				draw_circle(pot, 16.0, Color("#8A5A3E"))
				draw_circle(pot, 12.0, Color("#4F6A45"))
		_:
			if int(front.seed) % 3 == 0:  # a bench or a bicycle by a house
				var at := Vector2(_w * 0.7, 40.0)
				draw_rect(Rect2(at + Vector2(-50, -10) + Vector2(4, 5), Vector2(100, 22)), SHADOW)
				draw_rect(Rect2(at + Vector2(-50, -10), Vector2(100, 22)), Color("#6E5A44"))
				for b in 4:
					draw_line(at + Vector2(-46 + b * 30, -10), at + Vector2(-46 + b * 30, 12), Color("#5A4636"), 1.0)


## The yacht ashore in the boatyard: its middle's height on the quay, its beam,
## and its length for a yard `w` wide (HarbourFront's collision uses the same).
const HULL_Y := 140.0
const HULL_BEAM := 190.0


static func hull_length(w: float) -> float:
	return minf(w * 0.62, 600.0)


func _draw_hull_on_stands(at: Vector2) -> void:
	# A small yacht ashore, seen from above: the hull, its keel's shadow and
	# the stands (props) on each side.
	var length := hull_length(_w)
	var outline := HarbourDressing.hull_outline(length, HULL_BEAM)
	var pts := PackedVector2Array()
	for p in outline:  # stern at 0, bow at +length: turned to lie along the quay
		pts.append(at + Vector2(p.y - length / 2.0, p.x))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(10, 14))
	draw_colored_polygon(shadow, SHADOW)
	for k in 3:
		for side: float in [-1.0, 1.0]:
			var stand := at + Vector2(-length * 0.3 + k * length * 0.3, side * (HULL_BEAM / 2.0 + 12.0))
			draw_line(stand, stand - Vector2(0, side * 26.0), Color("#3E6B8A"), 6.0)
			draw_circle(stand, 8.0, Color("#3E6B8A"))
	draw_colored_polygon(pts, Color("#E4E3DC"))
	var deck := PackedVector2Array()
	for p in outline:
		deck.append(at + Vector2((p.y - length / 2.0) * 0.92, p.x * 0.8))
	draw_colored_polygon(deck, Color("#CFC9B8"))
	draw_rect(Rect2(at + Vector2(-length * 0.18, -40), Vector2(length * 0.3, 80)), Color("#E8E6DE"))  # the coachroof
	draw_polyline(pts, Color(INK, 0.5), 1.6)


func _draw_terrace() -> void:
	for table in layout.cafe_tables:
		var local := table - position
		for side: float in [-1.0, 1.0]:
			var chair := local + Vector2(side * 52.0, 0.0)
			draw_rect(Rect2(chair + Vector2(-15, -15) + Vector2(3, 4), Vector2(30, 30)), SHADOW)
			draw_rect(Rect2(chair + Vector2(-15, -15), Vector2(30, 30)), Color("#4A5A4C") if archetype != HarbourDressing.ARCHETYPE_MEDITERRANEAN else Color("#5D7A88"))
			draw_rect(Rect2(chair + Vector2(side * 10.0 - 5.0, -15), Vector2(10, 30)), Color("#36423A"))  # the chair back
		draw_circle(local + Vector2(5, 7), 30.0, SHADOW)
		draw_circle(local, 29.0, Color("#D9D4C6"))
		draw_arc(local, 29.0, 0, TAU, 28, Color("#9A9486"), 2.0, true)
	# Planters marking the terrace.
	if not layout.cafe_tables.is_empty():
		for x: float in [10.0, _w - 70.0]:
			var box := Rect2(x, 290.0, 60.0, 26.0)
			draw_rect(box, Color("#7A5A3E"))
			for f in 4:
				draw_circle(box.position + Vector2(8 + f * 15, 10), 9.0, Color("#5F7A4A"))


## The lit windows and doors (drawn above the light of the hour, so they glow).
func _draw_lights() -> void:
	if darkness < 0.25:
		return
	var glow := clampf((darkness - 0.25) / 0.5, 0.0, 1.0)
	var bars := archetype in [HarbourDressing.ARCHETYPE_NORDIC, HarbourDressing.ARCHETYPE_ATLANTIC]
	for rect in get_lit_windows():
		_lights.draw_rect(rect.grow(6.0), Color(LIT, 0.12 * glow))
		if bars and rect.size.x < 200.0:
			# Four panes behind the glazing bars.
			var half := (rect.size - Vector2(3, 3)) / 2.0
			for k in 4:
				_lights.draw_rect(Rect2(rect.position + Vector2(k % 2, k / 2) * (half + Vector2(3, 3)), half), Color(LIT, 0.85 * glow))
		else:
			_lights.draw_rect(rect, Color(LIT, 0.85 * glow))
	if is_open and get_kind() in QuayLayout.BUSINESSES and _door.size.x > 0.0:
		_lights.draw_rect(_door_glass(), Color(LIT, 0.8 * glow))
	if get_kind() == QuayLayout.HARBOUR_OFFICE:
		_lights.draw_rect(get_hatch_rect(), Color(LIT, 0.85 * glow))
	if get_kind() == QuayLayout.LANE:
		_lights.draw_circle(Vector2(_w * 0.82, -209.0), 10.0, Color(LIT, 0.9 * glow))


func _centred_text(text: String, baseline_centre: Vector2, size: int, colour: Color, max_width := -1.0) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var font_size := size
	if max_width > 0.0 and w > max_width:
		font_size = maxi(9, int(size * max_width / w))
		w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, baseline_centre - Vector2(w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
