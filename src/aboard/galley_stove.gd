class_name GalleyStove
extends Node2D
## The galley's little two-burner stove (Iteration 13), on the counter beside
## the provisions. A pan sits on it; after a meal is cooked it steams for a
## while. Presentation only: the station beside it opens the galley
## (CookingMenu).

const INK := Color("#1f2a2e")
const STEEL := Color("#9aa7ab")
const HOB := Color("#2c3436")
const FLAME := Color("#6FA7D8")  # gas burns blue
## Real seconds the pan steams after cooking.
const STEAM_SECONDS := 12.0

var _steam := 0.0
var _time := 0.0


func _ready() -> void:
	z_index = 3
	GameSession.meal_cooked.connect(func(_result: Dictionary) -> void: steam())


func steam(seconds := STEAM_SECONDS) -> void:
	_steam = seconds
	queue_redraw()


func is_steaming() -> bool:
	return _steam > 0.0


func _process(delta: float) -> void:
	_time += delta
	if _steam > 0.0:
		_steam = maxf(_steam - delta, 0.0)
		queue_redraw()


static func outline() -> PackedVector2Array:
	return HighlightResolver.rounded_rect(Rect2(-20, -15, 40, 30), 6.0)


func _draw() -> void:
	draw_rect(Rect2(-17, -12, 34, 24), INK)
	draw_rect(Rect2(-15, -10, 30, 20), HOB)
	for x in [-7.0, 7.0]:
		draw_arc(Vector2(x, 0), 5.5, 0.0, TAU, 16, STEEL, 1.2, true)
		if _steam > 0.0:
			draw_arc(Vector2(x, 0), 3.0, 0.0, TAU, 12, Color(FLAME, 0.8), 1.5, true)
	# The pan on the forward burner, its handle out to the side.
	draw_circle(Vector2(7, 0), 6.5, INK)
	draw_circle(Vector2(7, 0), 5.2, Color("#55605f"))
	draw_line(Vector2(12, 3), Vector2(22, 8), INK, 2.5, true)
	if _steam > 0.0:
		var strength := minf(_steam / 3.0, 1.0)
		for k in 3:
			var phase := fmod(_time * 0.6 + k / 3.0, 1.0)
			var p := Vector2(7 + 4.0 * sin(_time * 2.0 + k), -4.0 - phase * 22.0)
			draw_circle(p, 2.5 + phase * 4.0, Color(1, 1, 1, 0.35 * (1.0 - phase) * strength))
