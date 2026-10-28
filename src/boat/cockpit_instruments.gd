class_name CockpitInstruments
extends Node2D
## Marine electronics (I026 stage 03): the fitted instrument package at the
## helm, drawn in the deck's coordinates (+x the bow, -y the port side) at
## true scale (about 1 cm per unit): the chartplotter on the pedestal (or
## on the bulkhead by the wheel, or beside the companionway on a tiller
## boat), and a row of instrument displays on the bulkhead over the
## companionway (or beside the catamaran's wheel). Seen from above the
## screens tilt towards the helmsman; at night they glow softly (red or
## dimmed, as the package's night mode).
##
## Presentation only. The plotter has its own station beside it (E: the
## focused PlotterView), and a click on the plotter or on the instruments
## opens their focused views (`plotter_clicked`, `instruments_clicked`).
## BoatArea places it from the deck's own fixtures (cockpit_layout), so no
## boat needs per-boat offsets. It redraws when the package or the light
## changes, a few times a second at most - never every frame.

signal plotter_clicked
signal instruments_clicked

const INK := Color("#1f2a2e")
const REDRAW_SECONDS := 0.5
## How far (deck units) a click may miss a unit.
const CLICK_MARGIN := 6.0

## The plotter's centre and the instrument displays' centres (this node's
## coordinates), and the direction the bulkhead runs (the row's axis).
var plotter_at := Vector2.ZERO
var units_at: Array[Vector2] = []
var package: InstrumentPackage
var _redraw := 0.0
var _night := -1.0


func _ready() -> void:
	z_index = 2
	package = GameSession.get_instrument_package()
	GameSession.instruments_changed.connect(_on_changed)
	GameSession.state_replaced.connect(_on_changed)


func _on_changed() -> void:
	package = GameSession.get_instrument_package()
	queue_redraw()


func _process(delta: float) -> void:
	_redraw -= delta
	if _redraw > 0.0:
		return
	_redraw = REDRAW_SECONDS
	if absf(UiTheme.blend - _night) > 0.02:
		_night = UiTheme.blend
		queue_redraw()


## The plotter's outline (for the focus highlight), in this node's coordinates.
func plotter_rect() -> Rect2:
	var size := Vector2(package.plotter_size.y * 0.62 + 3.0, package.plotter_size.x + 3.0) if package else Vector2(12, 18)
	return Rect2(plotter_at - size / 2.0, size)


func units_rect() -> Rect2:
	if units_at.is_empty():
		return Rect2()
	var half := (package.cockpit_unit if package else 11.0) / 2.0 + 1.0
	var rect := Rect2(units_at[0] - Vector2(half, half), Vector2(half, half) * 2.0)
	for at in units_at:
		rect = rect.merge(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0))
	return rect


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not is_visible_in_tree():
		return
	var at := get_local_mouse_position()
	if plotter_rect().grow(CLICK_MARGIN).has_point(at):
		get_viewport().set_input_as_handled()
		plotter_clicked.emit()
	elif units_rect().grow(CLICK_MARGIN).has_point(at):
		get_viewport().set_input_as_handled()
		instruments_clicked.emit()


func _draw() -> void:
	if package == null:
		return
	var night := UiTheme.blend
	# Screens are lit: they keep their brightness under the night's light.
	var glow := Interactable.light_compensation.lerp(Color.WHITE, 0.35) if night > 0.0 else Color.WHITE
	_draw_plotter(night, glow)
	for at in units_at:
		_draw_unit(at, night, glow)


func _lit(colour: Color, glow: Color) -> Color:
	return Color(colour.r * glow.r, colour.g * glow.g, colour.b * glow.b, colour.a)


## The plotter, tilted towards the helm (its screen faces aft, -x).
func _draw_plotter(night: float, glow: Color) -> void:
	var rect := plotter_rect().grow(-1.5)
	# The bracket and its shadow on the deck.
	draw_rect(Rect2(rect.position + Vector2(1.5, 1.5), rect.size), Color(0, 0, 0, 0.30))
	draw_rect(rect.grow(0.8), INK)
	draw_rect(rect, package.colour("housing"))
	var screen := rect.grow_individual(-1.6, -1.6, -2.4, -1.6)
	draw_rect(screen, _lit(package.colour_at("screen", night) if package.units != InstrumentPackage.UNITS_DIALS else Color("#0E171C"), glow))
	# A hint of the chart: a coast and the course in cyan (red at night on the red packages).
	var line := _lit(package.colour_at("accent", night) if package.units != InstrumentPackage.UNITS_DIALS else Color("#5AA8B8"), glow)
	var land := _lit(Color("#4E5A52").darkened(night * 0.5), glow)
	draw_colored_polygon(PackedVector2Array([screen.position + Vector2(screen.size.x * 0.15, 0), screen.position + Vector2(screen.size.x, 0),
		screen.position + Vector2(screen.size.x, screen.size.y * 0.35), screen.position + Vector2(screen.size.x * 0.55, screen.size.y * 0.25)]), land)
	draw_line(screen.get_center() + Vector2(-screen.size.x * 0.3, screen.size.y * 0.3), screen.get_center() + Vector2(screen.size.x * 0.25, -screen.size.y * 0.25), line, 0.8, true)
	draw_circle(screen.get_center(), 0.9, _lit(Color("#E4EAE8"), glow))
	# The lit edge towards the light.
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(1, 1, 1, 0.18 * (1.0 - night)), 0.6)


## One instrument display on the bulkhead (round for Classic).
func _draw_unit(at: Vector2, night: float, glow: Color) -> void:
	var size := package.cockpit_unit
	var half := size / 2.0
	var lit_screen := _lit(package.colour_at("screen" if package.units != InstrumentPackage.UNITS_DIALS else "dial_face", night), glow)
	var ink := _lit(package.colour_at("dial_ink" if package.units == InstrumentPackage.UNITS_DIALS else "ink", night), glow)
	if package.units == InstrumentPackage.UNITS_DIALS:
		draw_circle(at + Vector2(0.8, 0.8), half + 0.6, Color(0, 0, 0, 0.30))
		draw_circle(at, half + 0.6, INK)
		draw_circle(at, half, package.colour("housing_edge"))
		draw_circle(at, half - 1.2, lit_screen)
		draw_line(at, at + Vector2(0.55, -0.83) * (half - 2.0), _lit(package.colour_at("accent", night), glow), 0.7, true)
		draw_arc(at, half - 2.2, 0.0, TAU, 16, Color(ink, 0.5), 0.4, true)
	else:
		var rect := Rect2(at - Vector2(half * 0.62, half), Vector2(size * 0.62, size))
		draw_rect(Rect2(rect.position + Vector2(0.8, 0.8), rect.size), Color(0, 0, 0, 0.30))
		draw_rect(rect.grow(0.6), INK)
		draw_rect(rect, package.colour("housing"))
		var screen := rect.grow(-1.0)
		draw_rect(screen, lit_screen)
		# A big figure and a hairline, too small to read from the deck.
		draw_rect(Rect2(screen.position + Vector2(screen.size.x * 0.3, screen.size.y * 0.3), Vector2(screen.size.x * 0.4, screen.size.y * 0.35)), Color(ink, 0.55))
		draw_line(screen.position + Vector2(0.5, screen.size.y * 0.18), Vector2(screen.end.x - 0.5, screen.position.y + screen.size.y * 0.18), Color(ink, 0.3), 0.3)
