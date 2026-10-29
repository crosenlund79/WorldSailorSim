class_name QuayDrawing
extends Node2D
## The ground of the quay (I026 stage 02, HarbourFront), seen from above at
## true scale: the promenade's paving in the harbour's regional style (setts
## in the north, limestone slabs in the south), the granite coping along the
## water with its bollards, lamp posts and benches, the water of the basin and
## the head of the guest pontoon with the walkway coming up from it, and,
## where the boatyard hauls out, the travel lift standing over its dock.
## The noticeboard stands by the walkway's head (an upright board on two
## posts, like the facades).
##
## Art only: HarbourFront owns the walls and the stations. Drawn once (the
## harbour does not change while the Captain is there).

const INK := Color("#2A3236")
const SHADOW := Color(0.04, 0.07, 0.09, 0.3)
const LAMP := Color("#3A4044")
const LAMP_GLASS := Color("#E8E2C8")
const PONTOON := Color("#8A8478")
const PONTOON_DARK := Color("#686458")
const GALVANISED := Color("#9AA3A5")
## The pontoon's head below the quay: its top edge and its depth.
const PONTOON_Y := 560.0
const PONTOON_DEPTH := 110.0
## Lamp posts and benches along the promenade (every so many units).
const LAMP_PITCH := 900.0

var layout: QuayLayout
var _style: Dictionary
var _font: Font


func setup(layout_: QuayLayout) -> void:
	layout = layout_
	_style = HarbourDressing.STYLES.get(layout.archetype, HarbourDressing.STYLES[HarbourDressing.ARCHETYPE_NORDIC])
	var theme := ThemeDB.get_project_theme()
	_font = theme.get_font(&"font", &"DisplayHeader") if theme else ThemeDB.fallback_font
	if _font == null:
		_font = ThemeDB.fallback_font
	queue_redraw()


## The lamp heads along the promenade (this node's coordinates).
func get_lamp_positions() -> PackedVector2Array:
	var lamps := PackedVector2Array()
	var x := ceilf((layout.left + 200.0) / LAMP_PITCH) * LAMP_PITCH - 450.0
	while x < layout.right - 150.0:
		# Not before the boatyard (I027): its hull leaves a lane along the coping.
		if absf(x) > QuayLayout.WALKWAY_CLEAR + 40.0 and not _over_lift(x) and not _before_yard(x):
			lamps.append(Vector2(x, QuayLayout.EDGE_Y - 34.0))
		x += LAMP_PITCH
	return lamps


## The benches along the edge, facing the water (centres).
func get_bench_positions() -> PackedVector2Array:
	var benches := PackedVector2Array()
	for lamp in get_lamp_positions():
		var at := lamp + Vector2(200.0, -24.0)
		if absf(at.x) > QuayLayout.WALKWAY_CLEAR + 120.0 and not _over_lift(at.x) and not _before_yard(at.x) and at.x < layout.right - 200.0:
			benches.append(at)
	return benches


## Bollards on the coping (centres).
func get_bollard_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	var x := ceilf(layout.left / 300.0) * 300.0 + 150.0
	while x < layout.right:
		if absf(x) > QuayLayout.WALKWAY_HALF + 40.0 and not _over_lift(x):
			out.append(Vector2(x, QuayLayout.EDGE_Y - QuayLayout.COPING * 0.5))
		x += 300.0
	return out


## In front of the boatyard, whose hull on its stands leaves only a lane
## along the coping: no bench there, or the lane is shut.
func _before_yard(x: float) -> bool:
	for front in layout.fronts:
		if front.kind == QuayLayout.BOATYARD and x > float(front.x0) - 80.0 and x < float(front.x1) + 80.0:
			return true
	return false


func _over_lift(x: float) -> bool:
	return layout.lift != Vector2.ZERO and x > layout.lift.x - 80.0 and x < layout.lift.y + 80.0


func _draw() -> void:
	if layout == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("quay-ground:%s" % layout.port_id)
	var x0 := layout.left - 1400.0
	var x1 := layout.right + 1400.0
	var paving: Color = _style.paving
	var joint: Color = _style.joint
	_draw_backdrop(x0, x1, rng)
	# The water of the basin, and the promenade above it.
	var water := WaterLook.water_colour(true)
	draw_rect(Rect2(x0, QuayLayout.EDGE_Y, x1 - x0, 900.0), water)
	for k in 5:
		draw_rect(Rect2(x0, QuayLayout.EDGE_Y + k * 9.0, x1 - x0, 9.0), Color(0.02, 0.06, 0.08, 0.1 - k * 0.018))  # the quay's shade
	draw_rect(Rect2(x0, -40.0, x1 - x0, QuayLayout.EDGE_Y + 40.0), paving)
	var slab := Vector2(26, 13) if layout.archetype in [HarbourDressing.ARCHETYPE_NORDIC, HarbourDressing.ARCHETYPE_ATLANTIC] else Vector2(62, 40)
	var y := 0.0
	var row := 0
	while y < QuayLayout.EDGE_Y - QuayLayout.COPING:
		var x := x0 + (slab.x * 0.5 if row % 2 else 0.0)
		var h := minf(slab.y, QuayLayout.EDGE_Y - QuayLayout.COPING - y)
		while x < x1:
			draw_rect(Rect2(Vector2(x, y), Vector2(slab.x - 2.0, h - 2.0)), paving.lerp(joint, rng.randf_range(0.0, 0.2)))
			x += slab.x
		y += slab.y
		row += 1
	# A granite kerb between the pavement before the shops and the promenade.
	draw_rect(Rect2(x0, 128.0, x1 - x0, 9.0), joint.lerp(paving, 0.35))
	draw_line(Vector2(x0, 137.0), Vector2(x1, 137.0), Color(joint.darkened(0.2), 0.5), 1.2)
	# A drainage gutter along the house fronts.
	draw_rect(Rect2(x0, 0.0, x1 - x0, 10.0), paving.darkened(0.18))
	# The granite coping.
	var cx := x0
	while cx < x1:
		var w := rng.randf_range(100.0, 170.0)
		var block := Rect2(cx, QuayLayout.EDGE_Y - QuayLayout.COPING, minf(w, x1 - cx), QuayLayout.COPING)
		draw_rect(block, (_style.edge as Color).lerp(joint, rng.randf_range(0.0, 0.3)))
		draw_line(block.position, Vector2(block.position.x, block.end.y), Color(joint.darkened(0.3), 0.8), 1.4)
		cx += w
	draw_rect(Rect2(x0, QuayLayout.EDGE_Y - QuayLayout.COPING, x1 - x0, 3.0), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(x0, QuayLayout.EDGE_Y - 3.0, x1 - x0, 3.0), Color(0, 0, 0, 0.2))
	_draw_lift_dock()
	_draw_pontoon_head()
	_draw_walkway()
	for at in get_bollard_positions():
		draw_circle(at + Vector2(5, 6), 14.0, SHADOW)
		draw_circle(at, 14.0, Color("#3E464B"))
		draw_circle(at, 9.0, Color("#4C555A"))
		draw_circle(at + Vector2(-3, -3), 4.0, Color("#6E777B"))
	for at in get_bench_positions():
		_draw_bench(at)
	for at in get_lamp_positions():
		_draw_lamp_post(at)
	_draw_travel_lift()
	_draw_fuel_pump(layout.fuel_berth)
	if layout.has_business(QuayLayout.NOTICEBOARD):
		_draw_noticeboard(layout.noticeboard)


## Beyond the quay's front row: the sky, and the town behind in the haze
## (seen between the houses and over their roofs).
func _draw_backdrop(x0: float, x1: float, rng: RandomNumberGenerator) -> void:
	var sky_top := Color("#B7C7CF")
	var sky_low := Color("#DCE2DE")
	if layout.archetype in [HarbourDressing.ARCHETYPE_MEDITERRANEAN, HarbourDressing.ARCHETYPE_TROPICAL]:
		sky_top = Color("#A9C3D3")
		sky_low = Color("#E4E4DA")
	var bands := 8
	for k in bands:
		var t := float(k) / bands
		draw_rect(Rect2(x0, -1400.0 + t * 1400.0, x1 - x0, 1400.0 / bands + 1.0), sky_top.lerp(sky_low, t))
	var town: Dictionary = HarbourDressing.TOWNS.get(layout.archetype, HarbourDressing.TOWNS[HarbourDressing.ARCHETYPE_NORDIC])
	var haze := HarbourDressing.HAZE
	# A far ridge or hill line, then two rows of houses fading into the haze.
	var ridge := PackedVector2Array([Vector2(x0, -300.0)])
	var x := x0
	while x < x1:
		x += rng.randf_range(300.0, 700.0)
		ridge.append(Vector2(minf(x, x1), -rng.randf_range(420.0, 620.0)))
	ridge.append(Vector2(x1, -300.0))
	ridge.append(Vector2(x1, 0.0))
	ridge.append(Vector2(x0, 0.0))
	draw_colored_polygon(ridge, (town.tree as Color).lerp(haze, 0.62))
	for row in 2:
		var fade := 0.55 - row * 0.2
		x = x0 + rng.randf_range(0.0, 200.0)
		while x < x1:
			var w := rng.randf_range(260.0, 520.0)
			var h := rng.randf_range(260.0, 420.0) - row * 60.0
			var facade: Color = (town.facades as Array)[rng.randi() % (town.facades as Array).size()]
			var roof: Color = (((town.roofs as Dictionary).values()[0] as Array)[0] as Array)[0]
			draw_rect(Rect2(x, -h, w, h), facade.lerp(haze, fade))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 8, -h), Vector2(x + w + 8, -h), Vector2(x + w - 30, -h - 70),
				Vector2(x + 30, -h - 70)]), roof.lerp(haze, fade))
			for c in int(w / 120.0):
				draw_rect(Rect2(x + 30 + c * 120, -h + 40, 50, 46), Color("#34444F").lerp(haze, fade + 0.1))
			x += w + rng.randf_range(10.0, 90.0)
	draw_rect(Rect2(x0, -60.0, x1 - x0, 60.0), (_style.paving as Color).darkened(0.12).lerp(haze, 0.3))  # the lanes behind


func _draw_pontoon_head() -> void:
	# The guest pontoon running along below the quay; the walkway comes up
	# from it to the coping.
	var p := Rect2(-1300.0, PONTOON_Y, 2600.0, PONTOON_DEPTH)
	draw_rect(Rect2(p.position + Vector2(6, 9), p.size), SHADOW)
	draw_rect(p, PONTOON)
	var x := p.position.x
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	while x < p.end.x:
		draw_rect(Rect2(x + 0.5, p.position.y + 7.0, 13.0, p.size.y - 14.0), PONTOON.lerp(PONTOON_DARK, rng.randf_range(0.0, 0.3)))
		x += 14.0
	draw_rect(Rect2(p.position, Vector2(p.size.x, 7)), GALVANISED)
	draw_rect(Rect2(p.position.x, p.end.y - 7, p.size.x, 7), GALVANISED.darkened(0.12))
	draw_rect(p, Color(INK, 0.6), false, 1.4)
	# The cleats along its edge.
	var c := p.position.x + 160.0
	while c < p.end.x:
		draw_rect(Rect2(c - 15.0, p.position.y + 10.0, 30.0, 7.0), GALVANISED)
		c += 520.0


func _draw_walkway() -> void:
	# An aluminium brow from the pontoon up to the quay, hinged at the top,
	# with non-slip treads and hand rails.
	var top := QuayLayout.EDGE_Y - QuayLayout.COPING - 6.0
	var bottom := PONTOON_Y + 40.0
	var x0 := -QuayLayout.WALKWAY_HALF
	var x1 := QuayLayout.WALKWAY_HALF
	draw_rect(Rect2(x0 + 6, top + 9, x1 - x0, bottom - top), SHADOW)
	draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color("#A3AAAB"))
	draw_rect(Rect2(x0, top, 4, bottom - top), Color("#6E7678"))
	draw_rect(Rect2(x1 - 4, top, 4, bottom - top), Color("#6E7678"))
	var y := top + 7.0
	while y < bottom - 4.0:
		draw_rect(Rect2(x0 + 6, y, x1 - x0 - 12, 3.0), Color("#3A4144"))
		y += 11.0
	for x: float in [x0 - 5.0, x1 + 5.0]:
		draw_line(Vector2(x, top - 6), Vector2(x, bottom), Color(INK, 0.6), 3.0, true)
		draw_line(Vector2(x, top - 6), Vector2(x, bottom), Color("#C4CBCC"), 1.6, true)
	# A small sign at its head: the guest pontoon.
	var board := Rect2(x1 + 22.0, QuayLayout.EDGE_Y - 96.0, 190.0, 30.0)
	draw_rect(Rect2(board.position + Vector2(3, 4), board.size), SHADOW)
	draw_rect(board, Color("#23394A"))
	draw_rect(Rect2(board.position, Vector2(board.size.x, 3)), Color("#5AA8B8"))
	var text := Loc.t("Guest pontoon")
	var w := minf(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, board.size.x - 12.0)
	draw_string(_font, Vector2(board.get_center().x - w / 2.0, board.get_center().y + 7.0), text, HORIZONTAL_ALIGNMENT_LEFT, board.size.x - 12.0, 18,
		Color("#EEF2F1"))


func _draw_lift_dock() -> void:
	if layout.lift == Vector2.ZERO:
		return
	# The travel lift's dock: a slot of water cut into the quay.
	var dock := Rect2(layout.lift.x + 140.0, QuayLayout.EDGE_Y - 230.0, layout.lift.y - layout.lift.x - 280.0, 232.0)
	draw_rect(dock, WaterLook.water_colour(true).darkened(0.08))
	draw_rect(Rect2(dock.position.x - 26.0, dock.position.y - 26.0, 26.0, dock.size.y + 26.0), (_style.edge as Color))
	draw_rect(Rect2(dock.end.x, dock.position.y - 26.0, 26.0, dock.size.y + 26.0), (_style.edge as Color))
	draw_rect(Rect2(dock.position.x - 26.0, dock.position.y - 26.0, dock.size.x + 52.0, 26.0), (_style.edge as Color))
	draw_rect(dock, Color(INK, 0.5), false, 2.0)


## The dock cut into the quay for the travel lift (empty without one).
func get_lift_dock() -> Rect2:
	if layout.lift == Vector2.ZERO:
		return Rect2()
	return Rect2(layout.lift.x + 140.0, QuayLayout.EDGE_Y - 230.0, layout.lift.y - layout.lift.x - 280.0, 232.0)


## The fuel berth's pump (I027): a slim cabinet seen from above, its hose
## coiled on the coping and a small plate, in the harbour's light.
func _draw_fuel_pump(at: Vector2) -> void:
	if at == Vector2.ZERO:
		return
	draw_rect(Rect2(at + Vector2(-13, -11), Vector2(28, 24)), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(at + Vector2(-14, -13), Vector2(28, 24)), Color("#B5452F"))
	draw_rect(Rect2(at + Vector2(-11, -10), Vector2(22, 8)), Color("#2B3236"))
	draw_rect(Rect2(at + Vector2(-9, -9), Vector2(18, 5)), Color("#9FD6B4"))
	draw_rect(Rect2(at + Vector2(-14, 9), Vector2(28, 3)), Color("#7E2F22"))
	draw_arc(at + Vector2(22, 4), 7.0, 0.0, TAU, 18, Color("#22282B"), 2.0, true)
	draw_line(at + Vector2(14, 0), at + Vector2(16, 3), Color("#22282B"), 2.0, true)


func _draw_travel_lift() -> void:
	if layout.lift == Vector2.ZERO:
		return
	var dock := get_lift_dock()
	# Two long runways either side of the dock, the portal frame across them,
	# the slings hanging into the water - painted steel, seen from above.
	var blue := Color("#3E6B8A")
	var y0 := dock.position.y - 120.0
	var y1 := QuayLayout.EDGE_Y - 8.0
	for x: float in [dock.position.x - 70.0, dock.end.x + 40.0]:
		draw_rect(Rect2(Vector2(x + 8.0, y0 + 10.0), Vector2(30.0, y1 - y0)), SHADOW)
		draw_rect(Rect2(Vector2(x, y0), Vector2(30.0, y1 - y0)), blue)
		draw_rect(Rect2(Vector2(x, y0), Vector2(30.0, y1 - y0)), Color(INK, 0.5), false, 1.4)
		for wy: float in [y0 + 10.0, y1 - 40.0]:
			draw_rect(Rect2(x - 8.0, wy, 46.0, 34.0), Color("#232628"))  # the wheels
	for y: float in [y0 + 20.0, y1 - 30.0]:
		draw_rect(Rect2(dock.position.x - 70.0, y, dock.size.x + 140.0, 22.0), blue.lightened(0.08))
	for k in 2:
		var sy := dock.position.y + 60.0 + k * 90.0
		draw_line(Vector2(dock.position.x - 40.0, sy), Vector2(dock.end.x + 40.0, sy), Color("#C9C3B2"), 5.0)


## The lift's outline (global), for its station's highlight.
func get_lift_outline() -> PackedVector2Array:
	var dock := get_lift_dock()
	var rect := Rect2(dock.position.x - 80.0, dock.position.y - 124.0, dock.size.x + 160.0, QuayLayout.EDGE_Y - dock.position.y + 120.0)
	var out := PackedVector2Array()
	for p in HighlightResolver.rounded_rect(rect, 10.0):
		out.append(to_global(p))
	return out


func _draw_lamp_post(at: Vector2) -> void:
	draw_circle(at + Vector2(6, 8), 16.0, SHADOW)
	draw_circle(at, 9.0, LAMP)
	draw_line(at, at + Vector2(0, -18), LAMP, 5.0, true)
	var head := Rect2(at + Vector2(-17, -34), Vector2(34, 22))
	draw_rect(Rect2(head.position + Vector2(6, 8), head.size), SHADOW)
	draw_rect(head, LAMP)
	draw_rect(head.grow(-4.0), LAMP_GLASS)


func _draw_bench(at: Vector2) -> void:
	var seat := Rect2(at + Vector2(-80, -14), Vector2(160, 34))
	draw_rect(Rect2(seat.position + Vector2(5, 6), seat.size), SHADOW)
	draw_rect(seat, Color("#7A6048"))
	for b in 4:
		draw_line(Vector2(seat.position.x, seat.position.y + 4 + b * 8), Vector2(seat.end.x, seat.position.y + 4 + b * 8), Color("#5E4836"), 1.2)
	draw_rect(Rect2(seat.position.x, seat.position.y - 6.0, seat.size.x, 7.0), Color("#5E4836"))  # the backrest
	for x: float in [seat.position.x + 10.0, seat.end.x - 18.0]:
		draw_rect(Rect2(x, seat.position.y - 6.0, 8.0, seat.size.y + 6.0), Color("#2E3336"))


func _draw_noticeboard(foot: Vector2) -> void:
	# An upright board on two posts, under a little roof, with notes pinned.
	var board := Rect2(foot + Vector2(-80, -150), Vector2(160, 100))
	for x: float in [board.position.x + 14.0, board.end.x - 14.0]:
		draw_line(Vector2(x, board.end.y), Vector2(x, foot.y), Color("#4A3A2C"), 7.0)
	draw_rect(Rect2(board.position + Vector2(4, 5), board.size), SHADOW)
	draw_rect(board, Color("#6B5440"))
	draw_rect(board.grow(-8.0), Color("#C8B48E"))  # cork
	var roof := PackedVector2Array([board.position + Vector2(-12, 2), Vector2(board.end.x + 12, board.position.y + 2),
		Vector2(board.get_center().x, board.position.y - 24.0)])
	draw_colored_polygon(roof, Color("#4A4440"))
	var notes := [Rect2(14, 16, 40, 30), Rect2(62, 12, 34, 40), Rect2(104, 18, 42, 28), Rect2(24, 54, 46, 32), Rect2(82, 58, 56, 30)]
	var colours := [Color("#F2EEE2"), Color("#EDE3B0"), Color("#F2EEE2"), Color("#D8E2E6"), Color("#F2EEE2")]
	for i in notes.size():
		var note: Rect2 = notes[i]
		note.position += board.position
		draw_rect(note, colours[i])
		for l in 3:
			draw_line(note.position + Vector2(5, 8 + l * 7), note.position + Vector2(note.size.x - 5, 8 + l * 7), Color(INK, 0.35), 1.0)
		draw_circle(note.position + Vector2(note.size.x / 2.0, 3), 2.2, Color("#B33A3A"))


## The noticeboard's outline (global), for its station's highlight.
func get_noticeboard_outline() -> PackedVector2Array:
	var foot := layout.noticeboard
	var out := PackedVector2Array()
	for p in HighlightResolver.rounded_rect(Rect2(foot + Vector2(-94, -182), Vector2(188, 186)), 10.0):
		out.append(to_global(p))
	return out
