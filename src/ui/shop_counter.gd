class_name ShopCounter
extends Control
## The shop-counter frame (I026 stage 02): a business's existing menu, shown
## as a focused view that visibly belongs to that shop. Behind the panel the
## shop's interior is drawn - its back wall and shelves with what it sells
## (rope and fenders at the chandlery, rolls of sailcloth at the sail loft,
## tins and fruit at the grocery, crates on ice at the fishmonger's, cups and
## the coffee machine at the café, tools and a half model at the yard, charts
## and keys at the harbour office) and the counter in front - with the shop's
## own sign hanging above the panel.
##
## Presentation only: attach() adds it to a menu that is already open, just
## above the menu's dimmed backdrop and under its panel, so the menu's logic,
## buttons, focus and Esc are exactly as before. Without a business (the
## cabin's provisions locker opening the grocery) nothing is attached.

const INK := Color("#2A3236")

var business: StringName = &""
var archetype: StringName = HarbourDressing.ARCHETYPE_NORDIC
## The sign's text (the business's name as on its storefront).
var sign_text := ""
var _font: Font
var _panel: Control


## Frames `menu` (a ModalPanel just pushed) as the counter of `business`.
## Returns the frame, or null when the menu has no backdrop to sit on.
static func attach(menu: Control, business_: StringName, archetype_: StringName) -> ShopCounter:
	if menu == null or not is_instance_valid(menu):
		return null
	var frame := ShopCounter.new()
	frame.name = "ShopCounter"
	frame.business = business_
	frame.archetype = archetype_
	frame.sign_text = HarbourFront.business_name(business_) if business_ != HarbourFront.HATCH else Loc.t("Harbour Office")
	if business_ == QuayLayout.LANE:
		frame.sign_text = Loc.t("Town")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := menu.get_node_or_null(^"Dim")
	menu.add_child(frame)
	menu.move_child(frame, dim.get_index() + 1 if dim else 0)
	frame._panel = menu.find_child("Panel", true, false) as Control
	return frame


func _ready() -> void:
	var theme := ThemeDB.get_project_theme()
	_font = theme.get_font(&"font", &"DisplayHeader") if theme else ThemeDB.fallback_font
	if _font == null:
		_font = ThemeDB.fallback_font
	resized.connect(queue_redraw)
	if _panel:
		_panel.resized.connect(queue_redraw)
		_panel.item_rect_changed.connect(queue_redraw)


## The sign board's rectangle (this control's coordinates), for tests.
func get_sign_rect() -> Rect2:
	var view := Rect2(Vector2.ZERO, size)
	var panel := _panel_rect()
	var text_w := _font.get_string_size(sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x if _font else 200.0
	var board := Vector2(text_w + 70.0, 58.0)
	if panel.position.y - view.position.y >= board.y + 22.0:
		return Rect2(Vector2(panel.get_center().x - board.x / 2.0, panel.position.y - board.y - 12.0), board)
	# A tall panel: the sign hangs beside it, at the top of the wider margin.
	var left_room := panel.position.x
	var right_room := size.x - panel.end.x
	var room := maxf(left_room, right_room) - 24.0
	if room >= 140.0:
		board.x = minf(board.x, room)
		var x := (left_room - board.x) / 2.0 if left_room >= right_room else panel.end.x + (right_room - board.x) / 2.0
		return Rect2(Vector2(x, 40.0), board)
	return Rect2()


func _panel_rect() -> Rect2:
	if _panel and _panel.is_inside_tree():
		return Rect2(_panel.global_position - global_position, _panel.size)
	return Rect2(size * 0.25, size * 0.5)


func _draw() -> void:
	var view := Rect2(Vector2.ZERO, size)
	var counter_top := size.y * 0.74
	var wall := _wall_colour()
	draw_rect(view, wall)
	_wall_texture(Rect2(0, 0, size.x, counter_top))
	if business in [QuayLayout.NOTICEBOARD, QuayLayout.LANE]:
		# Not a shop: the board up close, or the lane into town.
		_draw_goods(view)
		for k in 6:
			draw_rect(view.grow(-k * 18.0), Color(0, 0, 0, 0.05), false, 18.0)
		_draw_sign()
		return
	_draw_goods(Rect2(0, 0, size.x, counter_top))
	# The counter across the front: its top, its front boards.
	var top := Rect2(0, counter_top, size.x, 26)
	draw_rect(Rect2(0, counter_top + 26, size.x, size.y - counter_top), Color("#5A4232"))
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, counter_top + 26), Vector2(x, size.y), Color("#4A3628"), 2.0)
		x += 64.0
	draw_rect(top, Color("#8B6A48"))
	draw_rect(Rect2(0, counter_top + 22, size.x, 4), Color(0, 0, 0, 0.25))
	_draw_counter_things(counter_top)
	# A soft vignette, so the panel stays the focus.
	for k in 6:
		draw_rect(view.grow(-k * 18.0), Color(0, 0, 0, 0.05), false, 18.0)
	draw_rect(view, Color(0.04, 0.07, 0.09, 0.22))
	_draw_sign()


func _wall_colour() -> Color:
	match business:
		QuayLayout.FISHMONGER:
			return Color("#DCE6E8")
		QuayLayout.CAFE:
			return Color("#B98E66") if archetype != HarbourDressing.ARCHETYPE_NORDIC else Color("#8E6A4C")
		QuayLayout.BOATYARD:
			return Color("#7E8A8E")
		QuayLayout.HARBOUR_OFFICE, HarbourFront.HATCH:
			return Color("#D8D2C2")
		QuayLayout.LANE:
			return Color("#9FB3BC")
		QuayLayout.NOTICEBOARD:
			return Color("#8E6E50")
	return Color("#7A6048") if archetype in [HarbourDressing.ARCHETYPE_NORDIC, HarbourDressing.ARCHETYPE_ATLANTIC] else Color("#C9B79A")


func _wall_texture(rect: Rect2) -> void:
	if business == QuayLayout.FISHMONGER:
		var y := rect.position.y
		var row := 0
		while y < rect.end.y:
			var x := -20.0 if row % 2 else 0.0
			while x < rect.end.x:
				draw_rect(Rect2(x, y, 40, 20), Color("#E8EEF0") if (int(x / 40.0) + row) % 7 else Color("#9CB6C4"), false, 1.0)
				x += 40.0
			y += 20.0
			row += 1
		return
	# Tongue-and-groove boards (or plaster with a dado rail in the south).
	if archetype in [HarbourDressing.ARCHETYPE_NORDIC, HarbourDressing.ARCHETYPE_ATLANTIC] or business == QuayLayout.BOATYARD:
		var x := 0.0
		while x < rect.end.x:
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0, 0, 0, 0.12), 2.0)
			x += 30.0
	else:
		draw_rect(Rect2(0, rect.end.y - 120, rect.size.x, 6), Color(0, 0, 0, 0.15))


func _shelf(y: float, x0: float, x1: float) -> void:
	draw_rect(Rect2(x0, y, x1 - x0, 12), Color("#6B5440"))
	draw_rect(Rect2(x0, y + 12, x1 - x0, 6), Color(0, 0, 0, 0.2))


func _draw_goods(rect: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(business))
	var w := rect.size.x
	match business:
		QuayLayout.CHANDLERY:
			for row in 3:
				var y := 150.0 + row * 170.0
				_shelf(y, 30, w - 30)
				var x := 50.0
				while x < w - 60.0:
					match rng.randi() % 4:
						0:  # a coil of rope
							for r in 4:
								draw_arc(Vector2(x + 30, y - 32), 28.0 - r * 6.0, 0, TAU, 24, Color("#C9BE9A").darkened(r * 0.07), 5.0, true)
						1:  # a fender
							draw_rect(Rect2(x + 14, y - 78, 34, 78), [Color("#2F3E4C"), Color("#E8E6DF")][rng.randi() % 2])
						2:  # tins of varnish
							for k in 3:
								draw_rect(Rect2(x + k * 22, y - 34, 18, 34), Color("#B08A3A").lerp(Color("#5A6E7A"), rng.randf()))
						_:  # a brass lamp
							draw_rect(Rect2(x + 18, y - 54, 26, 40), Color("#C8A85A"))
							draw_circle(Vector2(x + 31, y - 34), 9.0, Color("#F1E4B0"))
					x += 80.0
			draw_arc(Vector2(w - 120, 70), 42.0, 0, TAU, 32, Color("#D9783A"), 16.0, true)  # the life ring on the wall
		QuayLayout.SAIL_LOFT:
			for row in 2:
				var y := 220.0 + row * 200.0
				_shelf(y, 30, w - 30)
				var x := 40.0
				while x < w - 60.0:
					var cloth: Color = [Color("#EDEBE3"), Color("#E0DCCF"), Color("#C9B98F"), Color("#9EB2BE")][rng.randi() % 4]
					draw_rect(Rect2(x, y - 60, 120, 60), cloth)
					draw_circle(Vector2(x + 120, y - 30), 30.0, cloth.darkened(0.08))
					draw_circle(Vector2(x + 120, y - 30), 8.0, Color("#8A7A5A"))
					x += 150.0
			for k in 5:  # spools of thread
				draw_rect(Rect2(60 + k * 34, 60, 22, 34), [Color("#2D3E52"), Color("#B33A3A"), Color("#E8E6DF"), Color("#3F5A48"), Color("#C9A33A")][k])
		QuayLayout.GROCERY:
			for row in 3:
				var y := 150.0 + row * 160.0
				_shelf(y, 30, w - 30)
				var x := 40.0
				while x < w - 40.0:
					var kind := rng.randi() % 3
					if kind == 0:
						for k in 4:
							draw_rect(Rect2(x + k * 18, y - 40, 16, 40), Color("#C0533F").lerp(Color("#E0A63A"), rng.randf()))
					elif kind == 1:
						for k in 3:
							draw_rect(Rect2(x + k * 24, y - 30, 20, 30), Color("#D8D2C2"))
							draw_rect(Rect2(x + k * 24, y - 22, 20, 10), Color("#3F5E3A").lerp(Color("#2E5E86"), rng.randf()))
					else:
						draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 70, y), Vector2(x + 60, y - 28), Vector2(x + 10, y - 28)]),
							Color("#C9965A"))  # a loaf
					x += 90.0
		QuayLayout.FISHMONGER:
			for k in 6:
				var crate := Rect2(40 + k * (w - 80) / 6.0, 330, (w - 80) / 6.0 - 16, 90)
				draw_rect(crate, Color("#E8EEF0"))
				draw_rect(crate, Color("#9CB6C4"), false, 3.0)
				for f in 3:
					var c := crate.position + Vector2(crate.size.x * (f + 0.5) / 3.0, 45)
					draw_colored_polygon(_fish_shape(c, minf(crate.size.x / 3.4, 46.0)), [Color("#A8B7BD"), Color("#C79A7A"), Color("#9EAAA0")][(k + f) % 3])
			draw_circle(Vector2(w - 140, 150), 46.0, Color("#B9C0C2"))  # the scale
			draw_circle(Vector2(w - 140, 150), 36.0, Color("#F2F2EC"))
		QuayLayout.CAFE:
			_shelf(170, 30, w - 30)
			var cx := 60.0
			while cx < w - 80.0:
				draw_rect(Rect2(cx, 136, 30, 34), Color("#E9E4D8"))
				draw_rect(Rect2(cx + 28, 146, 8, 14), Color("#E9E4D8"), false, 3.0)
				cx += 56.0
			# The coffee machine and the chalkboard menu.
			draw_rect(Rect2(w * 0.62, 260, 220, 160), Color("#B9BFC2"))
			draw_rect(Rect2(w * 0.62 + 20, 290, 180, 50), Color("#2B2F2C"))
			for k in 2:
				draw_rect(Rect2(w * 0.62 + 50 + k * 90, 360, 22, 30), Color("#3A4044"))
			draw_rect(Rect2(60, 230, 260, 200), Color("#2B2F2C"))
			draw_rect(Rect2(60, 230, 260, 200), Color("#7A5A3A"), false, 8.0)
			for l in 5:
				draw_line(Vector2(84, 270 + l * 32), Vector2(84 + rng.randf_range(120, 220), 270 + l * 32), Color(1, 1, 1, 0.55), 2.0)
		QuayLayout.BOATYARD:
			# A pegboard of tools and a half model of a hull on the wall.
			draw_rect(Rect2(40, 80, w * 0.4, 300), Color("#C9B48E"))
			for k in 9:
				var at := Vector2(70 + (k % 3) * (w * 0.12), 120 + (k / 3) * 90)
				draw_line(at, at + Vector2(0, 60), Color("#3A4044"), 6.0)
				draw_rect(Rect2(at + Vector2(-12, -4), Vector2(24, 14)), Color("#B34A32"))
			var model := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				model.append(Vector2(w * 0.55 + t * w * 0.35, 200 + sin(t * PI) * 6.0))
			for i in range(12, -1, -1):
				var t := i / 12.0
				model.append(Vector2(w * 0.55 + t * w * 0.35, 250 - pow(t, 2.0) * 30.0))
			draw_rect(Rect2(w * 0.53, 170, w * 0.39, 110), Color("#6B5440"))
			draw_colored_polygon(model, Color("#E4E3DC"))
		QuayLayout.HARBOUR_OFFICE, HarbourFront.HATCH:
			# A chart on the wall, a key cabinet, the tide clock.
			draw_rect(Rect2(60, 70, w * 0.38, 260), Color("#E9E2CC"))
			draw_rect(Rect2(60, 70, w * 0.38, 260), Color("#6B5440"), false, 6.0)
			for k in 6:
				draw_line(Vector2(80, 110 + k * 36), Vector2(60 + w * 0.36, 100 + k * 40), Color("#9FB3BC"), 2.0)
			draw_rect(Rect2(w * 0.6, 80, 240, 200), Color("#6B5440"))
			for k in 12:
				draw_circle(Vector2(w * 0.6 + 30 + (k % 6) * 36, 130 + (k / 6) * 70), 6.0, Color("#C8A85A"))
			draw_circle(Vector2(w - 120, 100), 40.0, Color("#2B2B2B"))
			draw_circle(Vector2(w - 120, 100), 34.0, Color("#F2EEE2"))
		QuayLayout.LANE:
			# Houses along a lane rising into town.
			for k in 6:
				var house := Rect2(k * w / 6.0, 120 + (k % 2) * 30, w / 6.0 - 6, 380)
				draw_rect(house, (HarbourDressing.TOWNS.get(archetype, HarbourDressing.TOWNS[&"nordic"]).facades as Array)[k % 5])
				draw_rect(Rect2(house.position + Vector2(30, 60), Vector2(50, 60)), Color("#34444F"))
		QuayLayout.NOTICEBOARD:
			draw_rect(Rect2(30, 30, w - 60, rect.size.y - 40), Color("#C8B48E"))


func _fish_shape(at: Vector2, length: float) -> PackedVector2Array:
	var body := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		body.append(at + Vector2(cos(a) * length * 0.5, sin(a) * length * 0.18))
	return body


func _draw_counter_things(counter_top: float) -> void:
	match business:
		QuayLayout.CAFE:
			for k in 3:  # cups waiting on saucers
				var at := Vector2(size.x * (0.12 + k * 0.05), counter_top + 6)
				draw_circle(at, 16.0, Color("#D9D2C4"))
				draw_circle(at, 10.0, Color("#E9E4D8"))
				draw_circle(at, 7.0, Color("#5A3B28"))
		QuayLayout.HARBOUR_OFFICE, HarbourFront.HATCH:
			draw_circle(Vector2(size.x * 0.88, counter_top + 2), 12.0, Color("#C8A85A"))  # the bell
		QuayLayout.SAIL_LOFT:
			draw_rect(Rect2(size.x * 0.1, counter_top - 40, 120, 42), Color("#3A4044"))  # the sewing machine
		_:
			draw_rect(Rect2(size.x * 0.86, counter_top - 30, 80, 32), Color("#3A4044"))  # the till


func _draw_sign() -> void:
	if sign_text.is_empty():
		return
	var board := get_sign_rect()
	if not board.has_area():
		return
	var colours := _sign_colours()
	for x: float in [board.position.x + 24.0, board.end.x - 24.0]:
		draw_line(Vector2(x, maxf(board.position.y - 40.0, 0.0)), Vector2(x, board.position.y), Color("#3A3330"), 3.0)
	draw_rect(Rect2(board.position + Vector2(4, 6), board.size), Color(0, 0, 0, 0.3))
	draw_rect(board, colours[0])
	draw_rect(board, (colours[0] as Color).darkened(0.35), false, 3.0)
	var size_px := 34
	var text_w := _font.get_string_size(sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	if text_w > board.size.x - 24.0:
		size_px = maxi(14, int(size_px * (board.size.x - 24.0) / text_w))
		text_w = _font.get_string_size(sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(_font, Vector2(board.get_center().x - text_w / 2.0, board.get_center().y + size_px * 0.36), sign_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colours[1])


func _sign_colours() -> Array[Color]:
	match business:
		QuayLayout.SAIL_LOFT:
			return [Color("#EDE8DA"), Color("#2D3E52")]
		QuayLayout.GROCERY:
			return [Color("#3F5E3A"), Color("#F2EEDC")]
		QuayLayout.CAFE:
			return [Color("#EFE4CC"), Color("#5A3B28")]
		QuayLayout.HARBOUR_OFFICE, HarbourFront.HATCH:
			return [Color("#1F2F45"), Color("#E3C779")]
		QuayLayout.FISHMONGER:
			return [Color("#2E5E86"), Color("#F2F2EC")]
		QuayLayout.BOATYARD:
			return [Color("#8E989B"), Color("#F2F0E8")]
	return [Color("#23394A"), Color("#EEF2F1")]
