@tool
class_name ProvisionDisplay
extends Node2D
## The food and water stores in the cabin, drawn from the real quantities:
## four food items (a loaf, apples, a jar of preserves, a cheese) and four
## water jerrycans in a stores locker (Real Horizon: muted, real colours), each standing for 3.5 days (Cozy Polish: real things, no longer
## crates and cans). Full
## items are filled, used ones are outlines, so full, moderate, low and empty
## stores look different at a glance; low stores turn amber and empty ones
## red. Presentation only (no collision); the provisions station next to it
## opens the numbers (ProvisionsMenu).
##
## Drawn art can replace it: a PNG at <art_folder>/cabin/provisions_<level>.png
## (level = full, moderate, low or empty, of the scarcer supply) is shown
## centred on this node instead of the drawing.

const ITEMS := 4
const DAYS_PER_ITEM := Provisions.CAPACITY_DAYS / ITEMS
const FOOD := Color("#A88E68")
const FOOD_DARK := Color("#5E4E3A")
const WATER := Color("#6F98A5")
const WATER_DARK := Color("#38535C")
const EMPTY := Color(0.86, 0.88, 0.86, 0.3)
const LOW := Color("#D49A4B")
const OUT := Color("#C9634E")
const LABEL_FONT: Font = preload("res://assets/fonts/Barlow-SemiBold.ttf")

## Rotation-free layout: crates in the top row, cans in the bottom row.
@export var item_spacing := 17.0

var food_days := Provisions.CAPACITY_DAYS
var water_days := Provisions.CAPACITY_DAYS

var _sprite: Sprite2D


func _ready() -> void:
	z_index = 3
	if Engine.is_editor_hint():
		return
	GameSession.provisions_changed.connect(refresh)
	GameSession.state_replaced.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not GameSession.is_active():
		return
	# Consumption is continuous; redraw only when an item changes.
	if filled_items(GameSession.get_food_days()) != filled_items(food_days) \
			or filled_items(GameSession.get_water_days()) != filled_items(water_days) \
			or Provisions.level_of(GameSession.get_food_days()) != Provisions.level_of(food_days):
		refresh()


func refresh() -> void:
	if not GameSession.is_active():
		return
	food_days = GameSession.get_food_days()
	water_days = GameSession.get_water_days()
	var texture := _art_for(get_level())
	if texture:
		if _sprite == null:
			_sprite = Sprite2D.new()
			add_child(_sprite)
		_sprite.texture = texture
		_sprite.visible = true
	elif _sprite:
		_sprite.visible = false
	queue_redraw()


## Items drawn full for `days` (rounded up: a started crate still counts).
static func filled_items(days: float) -> int:
	return clampi(ceili(days / DAYS_PER_ITEM - 1e-6), 0, ITEMS)


## The level shown: that of the scarcer supply.
func get_level() -> StringName:
	return Provisions.level_of(minf(food_days, water_days))


func get_filled() -> Vector2i:
	return Vector2i(filled_items(food_days), filled_items(water_days))


func _draw() -> void:
	if _sprite and _sprite.visible:
		return
	var width := item_spacing * ITEMS
	var tray := Rect2(-width / 2.0 - 6.0, -24.0, width + 12.0, 48.0)
	# A stores locker: marine-timber bottom, a stainless fiddle rail round it.
	draw_rect(Rect2(tray.position + Vector2(2, 3), tray.size), Color(0.02, 0.03, 0.04, 0.35))
	draw_rect(tray, Color("#4A3F34"))
	draw_rect(tray.grow(-2.0), Color("#5A4C3E"), false, 1.0)
	draw_rect(tray, _tint(minf(food_days, water_days), Color("#8F9A9D")), false, 1.6)
	var food_filled := filled_items(food_days)
	var water_filled := filled_items(water_days)
	for i in ITEMS:
		var x := -width / 2.0 + item_spacing * (i + 0.5)
		# Food: recognisable things in turn (Cozy Polish), not crates.
		_draw_food(FOOD_KINDS[i % FOOD_KINDS.size()], Vector2(x, -13.0), i < food_filled)
		_draw_jug(Vector2(x, 5.0), i < water_filled)
	var label_colour := _tint(minf(food_days, water_days), Color(0.86, 0.89, 0.88, 0.75))
	draw_string(LABEL_FONT, Vector2(-width / 2.0 - 4.0, 22.0), Loc.t("FOOD · WATER"), HORIZONTAL_ALIGNMENT_LEFT, width + 8.0, 8, label_colour)


## The food slots, left to right: what a cruising galley keeps.
const FOOD_KINDS: Array[StringName] = [&"bread", &"apples", &"jar", &"cheese"]
const BREAD := Color("#A87B4F")
const BREAD_DARK := Color("#6A4B30")
const APPLE := Color("#8E3F33")
const APPLE_GREEN := Color("#6E7A45")
const JAR_GLASS := Color(0.80, 0.86, 0.86, 0.5)
const JAR_FILL := Color("#A86B3A")
const JAR_LID := Color("#8D9396")
const CHEESE := Color("#CDB36E")
const CHEESE_RIND := Color("#9A8248")
## Water: translucent jerrycans with a grey cap.
const JUG := Color("#C9D3D2")
const JUG_DARK := Color("#56666B")
const GHOST := Color(0.86, 0.88, 0.86, 0.28)


func _draw_food(kind: StringName, c: Vector2, full: bool) -> void:
	match kind:
		&"bread":
			var loaf := _oval(c, Vector2(7.5, 4.6))
			if full:
				draw_colored_polygon(loaf, BREAD)
				for k in 3:
					var sx := c.x - 3.5 + k * 3.5
					draw_line(Vector2(sx - 1.0, c.y - 2.5), Vector2(sx + 1.2, c.y + 2.0), BREAD_DARK, 1.0, true)
				draw_polyline(_closed(loaf), BREAD_DARK, 1.0, true)
			else:
				draw_polyline(_closed(loaf), GHOST, 1.0, true)
		&"apples":
			for o in [Vector2(-3.4, 0.8), Vector2(3.2, 0.8), Vector2(0.0, -2.6)]:
				if full:
					draw_circle(c + o, 3.4, APPLE)
					draw_circle(c + o + Vector2(-1.0, -1.0), 0.8, Color(1, 1, 1, 0.25))
				else:
					draw_arc(c + o, 3.4, 0.0, TAU, 12, GHOST, 1.0, true)
			if full:
				draw_line(c + Vector2(0, -6.0), c + Vector2(1.5, -7.6), APPLE_GREEN, 1.4, true)
		&"jar":
			var body := Rect2(c + Vector2(-4.5, -3.5), Vector2(9.0, 9.5))
			if full:
				draw_rect(body, JAR_FILL)
				draw_rect(body, JAR_GLASS, false, 1.0)
				draw_rect(Rect2(c + Vector2(-5.0, -6.0), Vector2(10.0, 2.6)), JAR_LID)
				draw_line(c + Vector2(-2.5, -1.5), c + Vector2(-2.5, 4.0), Color(1, 1, 1, 0.3), 1.0)
			else:
				draw_rect(body, GHOST, false, 1.0)
				draw_rect(Rect2(c + Vector2(-5.0, -6.0), Vector2(10.0, 2.6)), GHOST, false, 1.0)
		&"cheese":
			var wedge := PackedVector2Array([c + Vector2(-6.5, 4.0), c + Vector2(6.5, 4.0), c + Vector2(6.5, -1.5), c + Vector2(-6.5, 0.5)])
			if full:
				draw_colored_polygon(wedge, CHEESE)
				draw_line(wedge[2], wedge[1], CHEESE_RIND, 2.0)
				draw_circle(c + Vector2(-1.5, 2.0), 1.0, CHEESE_RIND)
				draw_circle(c + Vector2(2.5, 1.0), 0.8, CHEESE_RIND)
			else:
				draw_polyline(_closed(wedge), GHOST, 1.0, true)


## A water jug: stoneware body, a cap, a handle, and the water seen through
## its little window; an empty one is only its outline.
func _draw_jug(c: Vector2, full: bool) -> void:
	var body := PackedVector2Array([c + Vector2(-4.5, 8.0), c + Vector2(4.5, 8.0), c + Vector2(5.5, 1.0), c + Vector2(3.0, -2.5),
		c + Vector2(1.6, -4.0), c + Vector2(-1.6, -4.0), c + Vector2(-3.0, -2.5), c + Vector2(-5.5, 1.0)])
	if not full:
		draw_polyline(_closed(body), GHOST, 1.0, true)
		return
	draw_arc(c + Vector2(5.6, 1.5), 2.6, -PI * 0.5, PI * 0.6, 8, JUG_DARK, 1.4, true)
	draw_colored_polygon(body, JUG)
	draw_polyline(_closed(body), JUG_DARK, 1.0, true)
	draw_rect(Rect2(c + Vector2(-1.8, -6.0), Vector2(3.6, 2.2)), JUG_DARK)
	draw_rect(Rect2(c + Vector2(-3.0, 1.0), Vector2(6.0, 5.5)), _tint(water_days, WATER))
	draw_line(c + Vector2(-3.0, 1.0), c + Vector2(3.0, 1.0), Color(1, 1, 1, 0.35), 1.0)


static func _oval(c: Vector2, radii: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 14:
		var t := TAU * k / 14.0
		pts.append(c + Vector2(cos(t) * radii.x, sin(t) * radii.y))
	return pts


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result


static func _tint(days: float, normal: Color) -> Color:
	match Provisions.level_of(days):
		Provisions.LEVEL_EMPTY:
			return OUT
		Provisions.LEVEL_LOW:
			return LOW
	return normal


func _art_for(level: StringName) -> Texture2D:
	var profile := GameSession.get_vessel_definition().get_active_visual_profile()
	if profile == null or profile.procedural_only or profile.art_folder.is_empty():
		return null
	var path := profile.art_folder.path_join("cabin").path_join("provisions_%s.png" % level)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
