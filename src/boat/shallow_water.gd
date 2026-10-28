class_name ShallowWater
extends Node2D
## A hint of the bottom through shallow water (I022, softer water): a few
## large, very faint, sandy patches in the water around a moored or anchored
## boat, over the Water colour and under the WaterLife crests and the hull.
##
## Drawn once (a handful of polygons, kept by the canvas), redrawn only when
## the boat leaves or comes back to shallow water; nothing per frame. The
## patches are placed by a fixed seed from the harbour, so a harbour always
## looks the same. Off at sea (there the boat moves, and the sea is deep) and
## when WaterLook.translucency is 0.

const PATCHES := 9
const SPREAD := 1500.0
const ALPHA := 0.07

var _seed := 0


func _ready() -> void:
	z_index = 0
	refresh()
	GameSession.voyage_started.connect(refresh)
	GameSession.voyage_arrived.connect(_on_arrived)
	GameSession.anchor_changed.connect(refresh)


func _on_arrived(_port: StringName) -> void:
	refresh()


func refresh() -> void:
	visible = WaterLook.is_shallow() and WaterLook.translucency > 0.0
	_seed = hash(String(GameSession.get_location_id())) if not GameSession.is_underway() else hash(GameSession.get_vessel_position())
	queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var colour := WaterLook.SEABED.lightened(0.15)
	colour.a = ALPHA * clampf(WaterLook.translucency, 0.0, 2.0)
	for i in PATCHES:
		var centre := Vector2(rng.randf_range(-SPREAD, SPREAD), rng.randf_range(-SPREAD * 0.6, SPREAD * 0.6))
		var radius := Vector2(rng.randf_range(160.0, 420.0), rng.randf_range(90.0, 240.0))
		var turn := rng.randf_range(0.0, PI)
		var points := PackedVector2Array()
		for k in 18:
			var a := TAU * k / 18.0
			var wobble := 1.0 + 0.12 * sin(a * 3.0 + i)
			points.append(centre + Vector2(cos(a) * radius.x, sin(a) * radius.y).rotated(turn) * wobble)
		draw_colored_polygon(points, colour)
		# A softer rim, so no patch has a hard edge.
		var rim := colour
		rim.a *= 0.6
		var outer := PackedVector2Array()
		for p in points:
			outer.append(centre + (p - centre) * 1.25)
		draw_colored_polygon(outer, rim)
