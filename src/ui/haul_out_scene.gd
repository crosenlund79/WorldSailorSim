class_name HaulOutScene
extends Control
## A small illustration of the haul-out (Iteration 14): the boat in the slings
## of the yard's travel lift, lifted clear of the water (`lift` 0..1), weed on
## the bottom until it is scrubbed (`fouled` 0..1). Drawn in code as a
## schematic on a display (Real Horizon): dark glass with a faint grid, the
## hull and lift in white hairlines, the water and slings in instrument cyan,
## fouling in warning amber, and a lift scale at the side. Catamarans hang as
## two hulls under a bridge deck.

const Instrument := preload("res://src/ui/instrument_draw.gd")
const GRID := 24.0

## 0: afloat, 1: lifted clear of the water.
var lift := 0.0:
	set(value):
		lift = clampf(value, 0.0, 1.0)
		queue_redraw()
## 0: a clean bottom, 1: well fouled.
var fouled := 0.0:
	set(value):
		fouled = clampf(value, 0.0, 1.0)
		queue_redraw()
var catamaran := false
var _drips := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(620, 240)
	clip_contents = true
	UiTheme.palette_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	if lift > 0.05 and lift < 1.0 or lift >= 1.0 and _drips < 3.0:
		_drips += delta
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var water_y := h * 0.66
	var ink := UiTheme.color(&"ink")
	var soft := UiTheme.color(&"ink_soft")
	var cyan := UiTheme.color(&"accent")
	var steel := Color(soft, 0.9)
	# The display: dark glass with a faint grid.
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UiTheme.color(&"surface_sunken"))
	var grid := UiTheme.color(&"border_soft")
	var x0 := GRID
	while x0 < w:
		draw_line(Vector2(x0, 0), Vector2(x0, h), grid, 1.0)
		x0 += GRID
	var y0 := GRID
	while y0 < h:
		draw_line(Vector2(0, y0), Vector2(w, y0), grid, 1.0)
		y0 += GRID
	# Quays either side of the lifting dock.
	for qx in [0.0, w * 0.83]:
		var quay := Rect2(qx, water_y - 6.0, w * 0.17, h - water_y + 6.0)
		draw_rect(quay, UiTheme.color(&"surface_raised"))
		draw_line(quay.position, Vector2(quay.end.x, quay.position.y), steel, 1.0)
	# The boat: waterline at the surface when afloat, clear of it when lifted.
	var hull_w := w * 0.5
	var cx := w * 0.5
	var depth := h * 0.2
	var freeboard := h * 0.1
	var waterline := water_y - lift * (depth + 10.0)
	var deck := waterline - freeboard
	var mast_top := maxf(deck - h * 0.5, 0.0)
	draw_line(Vector2(cx - hull_w * 0.05, deck), Vector2(cx - hull_w * 0.05, mast_top), steel, 2.0)
	if catamaran:
		var bridge := Rect2(cx - hull_w * 0.5, deck, hull_w, freeboard * 0.55)
		draw_rect(bridge, UiTheme.color(&"surface_raised"))
		draw_rect(bridge, ink, false, 1.5)
		for side in [-1.0, 1.0]:
			_draw_hull(Vector2(cx + side * hull_w * 0.33, deck), hull_w * 0.34, freeboard, depth * 0.7, waterline, false)
	else:
		_draw_hull(Vector2(cx, deck), hull_w, freeboard, depth, waterline, true)
	# Water in front of the hull while afloat.
	var front := PackedVector2Array([Vector2(w * 0.17, water_y), Vector2(w * 0.83, water_y), Vector2(w * 0.83, h), Vector2(w * 0.17, h)])
	draw_colored_polygon(front, Color(UiTheme.color(&"surface_sunken").lerp(cyan, 0.16), 0.92))
	draw_line(Vector2(w * 0.17, water_y), Vector2(w * 0.83, water_y), cyan, 1.5)
	# Drips while she comes up.
	if lift > 0.05:
		for i in 7:
			var x := cx - hull_w * 0.35 + hull_w * 0.7 * float(i) / 6.0
			var fall := fmod(_drips * 90.0 + i * 23.0, maxf(water_y - waterline - depth * 0.5, 1.0))
			draw_circle(Vector2(x, waterline + depth * 0.5 + fall), 1.4, Color(cyan, 0.8))
	# The travel lift: two frames and a beam, slings under the hull.
	var beam_y := h * 0.1
	for x in [w * 0.19, w * 0.81]:
		draw_rect(Rect2(x - 3.0, beam_y, 6.0, water_y - 6.0 - beam_y), steel, false, 1.5)
		draw_line(Vector2(x - 14.0, water_y - 6.0), Vector2(x + 14.0, water_y - 6.0), steel, 2.0)
	draw_rect(Rect2(w * 0.19 - 3.0, beam_y - 4.0, w * 0.62 + 6.0, 8.0), steel, false, 1.5)
	for x in [cx - hull_w * 0.28, cx + hull_w * 0.28]:
		var bottom_y := waterline + depth * 0.55
		draw_line(Vector2(x - 10.0, beam_y + 4.0), Vector2(x - 10.0, bottom_y), cyan, 2.0)
		draw_line(Vector2(x + 10.0, beam_y + 4.0), Vector2(x + 10.0, bottom_y), cyan, 2.0)
		draw_line(Vector2(x - 10.0, bottom_y), Vector2(x + 10.0, bottom_y), cyan, 2.0)
	# A lift scale at the left: fine ticks, the keel's height in cyan.
	var top := beam_y + 10.0
	var scale_x := 14.0
	draw_line(Vector2(scale_x, top), Vector2(scale_x, water_y - 8.0), Color(soft, 0.7), 1.0)
	for i in 11:
		var y := lerpf(water_y - 8.0, top, i / 10.0)
		draw_line(Vector2(scale_x, y), Vector2(scale_x + (8.0 if i % 5 == 0 else 4.0), y), Color(soft, 0.7), 1.0)
	var marker_y := lerpf(water_y - 8.0, top, lift)
	draw_colored_polygon(PackedVector2Array([Vector2(scale_x + 4.0, marker_y), Vector2(scale_x + 14.0, marker_y - 5.0),
		Vector2(scale_x + 14.0, marker_y + 5.0)]), cyan)
	draw_rect(rect.grow(-0.5), UiTheme.color(&"border"), false, 1.0)


## One hull seen from the side: topsides above the waterline, the bottom
## below, fouling along it (amber) when fouled; a keel fin on a monohull.
func _draw_hull(deck_mid: Vector2, length: float, freeboard: float, depth: float, waterline: float, keel: bool) -> void:
	var ink := UiTheme.color(&"ink")
	var amber := UiTheme.color(&"warning")
	var l := deck_mid.x - length * 0.5
	var r := deck_mid.x + length * 0.5
	var bottom := waterline + depth * 0.45
	var outline := PackedVector2Array([Vector2(l, deck_mid.y), Vector2(r, deck_mid.y - 4.0), Vector2(r - length * 0.06, waterline),
		Vector2(r - length * 0.22, bottom), Vector2(l + length * 0.12, bottom), Vector2(l + length * 0.02, waterline)])
	draw_colored_polygon(outline, UiTheme.color(&"surface_raised"))
	var under := PackedVector2Array([Vector2(r - length * 0.06, waterline), Vector2(r - length * 0.22, bottom),
		Vector2(l + length * 0.12, bottom), Vector2(l + length * 0.02, waterline)])
	var bottom_fill := Color(UiTheme.color(&"ink_soft"), 0.28).lerp(Color(amber, 0.55), fouled * 0.85)
	draw_colored_polygon(under, bottom_fill)
	Instrument.outline(self, outline, ink, 1.5)
	draw_line(Vector2(l + length * 0.02, waterline), Vector2(r - length * 0.06, waterline), Color(ink, 0.6), 1.0)
	draw_line(Vector2(l + 4.0, deck_mid.y + 5.0), Vector2(r - 4.0, deck_mid.y + 1.0), Color(ink, 0.35), 1.0)
	if keel:
		var fin := PackedVector2Array([Vector2(deck_mid.x - length * 0.02, bottom), Vector2(deck_mid.x + length * 0.12, bottom),
			Vector2(deck_mid.x + length * 0.08, bottom + depth * 0.55), Vector2(deck_mid.x, bottom + depth * 0.55)])
		draw_colored_polygon(fin, bottom_fill)
		Instrument.outline(self, fin, ink, 1.5)
	if fouled > 0.2:
		for i in 9:
			var x := l + length * (0.16 + 0.07 * i)
			draw_line(Vector2(x, bottom), Vector2(x + 3.0, bottom + 4.0 + fouled * 6.0), amber, 1.5)
