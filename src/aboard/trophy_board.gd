class_name TrophyBoard
extends Node2D
## The trophy board on the cabin wall (Iteration 13): five slots for the five
## most notable catches (FishingState.trophies, ranked by FishingCatalog.score).
## A filled slot shows the fish's own little picture (FishArt, Iteration 18;
## before, a fish shape in the species' colour); empty slots are faint
## outlines. Presentation only: the station beside it opens
## the list (TrophyMenu).
##
## The fish pictures are Sprite2D children, one per slot (fix after 0.105b):
## drawn with draw_texture_rect() in this node's own _draw, a thumbnail that
## had not been drawn anywhere before rendered as a plain white rectangle, and
## the board never redrew it. Empty slots are a recessed frame with a faint
## fish outline, so an empty place reads as "still to catch".

const WOOD := Color("#5E4C3C")
const WOOD_DARK := Color("#3F342A")
const BRASS := Color("#A88F5A")
const EMPTY := Color(0.94, 0.9, 0.8, 0.28)
const FISH_COLOURS := {
	"herring": Color("#9fb7c0"), "mackerel": Color("#4f8a8b"), "flatfish": Color("#a68b62"), "cod": Color("#9a8f6a"),
	"perch": Color("#7ba05b"), "garfish": Color("#6fa3a8"), "gilthead_bream": Color("#c0c4b8"), "sea_trout": Color("#b39a7a"),
	"sea_bass": Color("#a9b4b8"), "bonito": Color("#3f6f8f"),
	"mahi_mahi": Color("#9fbf4f"), "skipjack": Color("#4a6f99"), "snapper": Color("#c8705a"), "yellowfin": Color("#d9b84a"),
}
const SIZE := Vector2(132, 46)
## A slot's picture: 26 x 13 units, centred under its brass pin.
const PICTURE := Vector2(26.0, 13.0)
const SLOT_SHADE := Color(0.12, 0.10, 0.08, 0.35)

var _pictures: Array[Sprite2D] = []


func _ready() -> void:
	z_index = 3
	for i in FishingState.TROPHY_COUNT:
		var sprite := Sprite2D.new()
		sprite.name = "Fish%d" % i
		sprite.position = _slot_center(i)
		sprite.visible = false
		add_child(sprite)
		_pictures.append(sprite)
	GameSession.fishing_changed.connect(refresh)
	GameSession.state_replaced.connect(refresh)
	refresh()


## Shows the current trophies (pictures and the board under them).
func refresh() -> void:
	var trophies := GameSession.get_fishing().trophies
	for i in _pictures.size():
		var sprite := _pictures[i]
		var picture: Texture2D = FishArt.thumbnail(String(trophies[i].species)) if i < trophies.size() else null
		sprite.texture = picture
		sprite.visible = picture != null
		if picture:
			var size := picture.get_size()
			var factor := minf(PICTURE.x / size.x, PICTURE.y / size.y)
			sprite.scale = Vector2(factor, factor)
	queue_redraw()


## The picture in slot `i` (null when empty or drawn as a shape; tests).
func get_picture(i: int) -> Texture2D:
	return _pictures[i].texture if i < _pictures.size() and _pictures[i].visible else null


func _slot_center(i: int) -> Vector2:
	var rect := Rect2(-SIZE / 2.0, SIZE)
	return Vector2(rect.position.x + SIZE.x * (i + 0.5) / FishingState.TROPHY_COUNT, 2.0)


static func outline() -> PackedVector2Array:
	return HighlightResolver.rounded_rect(Rect2(-SIZE / 2.0 - Vector2(3, 3), SIZE + Vector2(6, 6)), 6.0)


func _draw() -> void:
	var rect := Rect2(-SIZE / 2.0, SIZE)
	draw_rect(rect.grow(2.0), WOOD_DARK)
	draw_rect(rect, WOOD)
	draw_line(rect.position + Vector2(4, 10), Vector2(rect.end.x - 4, rect.position.y + 10), Color(WOOD_DARK, 0.5), 1.0)
	draw_line(rect.position + Vector2(4, 34), Vector2(rect.end.x - 4, rect.position.y + 34), Color(WOOD_DARK, 0.5), 1.0)
	var trophies := GameSession.get_fishing().trophies
	for i in FishingState.TROPHY_COUNT:
		var center := _slot_center(i)
		draw_circle(center + Vector2(0, -14), 1.6, BRASS)
		if i < trophies.size():
			if i < _pictures.size() and _pictures[i].visible:
				if i == 0:
					draw_circle(center + Vector2(0, 12), 2.4, BRASS)
			else:
				_draw_fish(center, Color(FISH_COLOURS.get(trophies[i].species, Color("#9fb7c0"))), i == 0)
		else:
			# Empty: a recessed little frame with a faint fish outline.
			var slot := Rect2(center - PICTURE / 2.0 - Vector2(1.5, 1.5), PICTURE + Vector2(3, 3))
			draw_rect(slot, SLOT_SHADE)
			draw_rect(slot, Color(WOOD_DARK, 0.6), false, 0.8)
			_draw_fish(center, EMPTY, false, true)


func _draw_fish(center: Vector2, colour: Color, best: bool, outline_only := false) -> void:
	var body := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		body.append(center + Vector2(cos(a) * 9.0, sin(a) * 4.5) + Vector2(1, 0))
	var tail := PackedVector2Array([center + Vector2(-7, 0), center + Vector2(-13, -5), center + Vector2(-12, 0), center + Vector2(-13, 5)])
	if outline_only:
		var closed := body.duplicate()
		closed.append(body[0])
		draw_polyline(closed, colour, 1.0, true)
		draw_polyline(tail, colour, 1.0, true)
		return
	draw_colored_polygon(tail, colour.darkened(0.25))
	draw_colored_polygon(body, colour)
	draw_circle(center + Vector2(6, -1), 1.1, Color("#1f2a2e"))
	if best:
		draw_circle(center + Vector2(0, 12), 2.4, BRASS)
