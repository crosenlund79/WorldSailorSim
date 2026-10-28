class_name PostcardView
extends Control
## One postcard, drawn (I022, Postcards from the Sea): the preview while one
## is made and the pages of the scrapbook. The picture is the game's own art -
## the harbour's landmark (HarbourLooks), the fish (FishArt), the companion's
## resting pose (CompanionVisualSet) - or, for a voyage, the weather and the
## evening light, a small painted sea in the colours of the loading screen.
##
## Three layouts: "classic" (picture left, words and stamp right),
## "snapshot" (a photo with a white border, words below) and "banner" (the
## picture to the edges, the words on a band across the bottom).

const PAPER := Color(0.93, 0.92, 0.88)
const INK := Color(0.16, 0.2, 0.24)
const INK_SOFT := Color(0.38, 0.4, 0.42)
const STAMP := Color(0.62, 0.3, 0.26)

## {"kind", "subject", "caption", "layout", "place"} (a draft or a scrapbook
## card).
var card := {}:
	set(value):
		card = value
		_picture = _find_picture()
		queue_redraw()

var _picture: Texture2D


func _init() -> void:
	custom_minimum_size = Vector2(600, 390)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The words on the card: the caption with the subject's names filled in.
func caption() -> String:
	return Pastimes.caption_text(String(card.get("kind", "")), int(card.get("caption", 0)), _args())


func _args() -> Array:
	return Pastimes.args_for(String(card.get("kind", "")), String(card.get("subject", "")))


func _find_picture() -> Texture2D:
	var subject := String(card.get("subject", ""))
	match String(card.get("kind", "")):
		"harbour":
			return HarbourLooks.get_default().picture_for(StringName(subject))
		"fish":
			return FishArt.thumbnail(subject) if FishArt.has_art(subject) else null
		"companion":
			var visuals := CompanionVisualSet.for_kind(StringName(subject))
			return visuals.get_texture(&"resting") if visuals else null
	return null


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(area.position + Vector2(6, 8), area.size), Color(0, 0, 0, 0.25))
	draw_rect(area, PAPER)
	var font := get_theme_default_font()
	match String(card.get("layout", "classic")):
		"snapshot":
			var photo := Rect2(Vector2(28, 24), Vector2(size.x - 56, size.y * 0.66))
			draw_rect(photo.grow(8), Color.WHITE)
			_draw_scene(photo)
			_draw_words(font, Rect2(Vector2(32, photo.end.y + 18), Vector2(size.x - 64, size.y - photo.end.y - 24)), HORIZONTAL_ALIGNMENT_CENTER)
		"banner":
			var band := size.y * 0.3
			_draw_scene(Rect2(Vector2.ZERO, Vector2(size.x, size.y - band)))
			draw_rect(Rect2(Vector2(0, size.y - band), Vector2(size.x, band)), PAPER)
			draw_line(Vector2(0, size.y - band), Vector2(size.x, size.y - band), STAMP, 4.0)
			_draw_words(font, Rect2(Vector2(28, size.y - band + 16), Vector2(size.x - 56, band - 24)), HORIZONTAL_ALIGNMENT_LEFT)
		_:
			var photo := Rect2(Vector2(22, 22), Vector2(size.x * 0.56, size.y - 44))
			_draw_scene(photo)
			var x := photo.end.x + 22
			draw_line(Vector2(x - 11, 30), Vector2(x - 11, size.y - 30), INK_SOFT * Color(1, 1, 1, 0.4), 1.5)
			var stamp := Rect2(Vector2(size.x - 78, 24), Vector2(54, 64))
			draw_rect(stamp, STAMP, false, 3.0)
			draw_rect(stamp.grow(-8), STAMP * Color(1, 1, 1, 0.35))
			_draw_words(font, Rect2(Vector2(x, 104), Vector2(size.x - x - 22, size.y - 128)), HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(area, INK_SOFT * Color(1, 1, 1, 0.5), false, 2.0)


func _draw_words(font: Font, box: Rect2, align: HorizontalAlignment) -> void:
	var text := caption()
	var font_size := 26 if text.length() < 60 else 22
	draw_multiline_string(font, box.position + Vector2(0, font_size), text, align, box.size.x, font_size, maxi(int(box.size.y / (font_size * 1.3)) - 1, 1), INK)
	var place := String(card.get("place", ""))
	if not place.is_empty():
		draw_string(font, Vector2(box.position.x, box.end.y - 4), place, align, box.size.x, 17, INK_SOFT)


## The picture: a painted sky and sea for the subject, with the game's art on it.
func _draw_scene(box: Rect2) -> void:
	var kind := String(card.get("kind", ""))
	var top := Color(0.56, 0.66, 0.72)
	var low := MarinePalette.SEA_HAZE
	var sea := MarinePalette.OPEN_WATER
	match kind:
		"sunset":
			top = Color(0.3, 0.32, 0.42)
			low = Color(0.86, 0.72, 0.64)
			sea = Color(0.22, 0.28, 0.36)
		"weather":
			top = Color(0.33, 0.38, 0.42)
			low = Color(0.55, 0.6, 0.62)
			sea = Color(0.2, 0.3, 0.34)
	var horizon := box.position.y + box.size.y * 0.6
	_gradient(Rect2(box.position, Vector2(box.size.x, horizon - box.position.y)), top, low)
	_gradient(Rect2(Vector2(box.position.x, horizon), Vector2(box.size.x, box.end.y - horizon)), sea, sea.darkened(0.3))
	match kind:
		"sunset":
			draw_circle(Vector2(box.position.x + box.size.x * 0.62, horizon - 4), box.size.y * 0.12, Color(0.98, 0.9, 0.78))
			_gradient(Rect2(Vector2(box.position.x, horizon), Vector2(box.size.x, 3)), Color(0.96, 0.86, 0.74, 0.7), Color(0.96, 0.86, 0.74, 0.0))
		"weather":
			for i in 22:
				var x := box.position.x + fmod(i * 37.0, box.size.x)
				var y := box.position.y + fmod(i * 23.0, box.size.y * 0.8)
				draw_line(Vector2(x, y), Vector2(x - 10, y + 26), Color(0.85, 0.9, 0.95, 0.55), 1.5)
	for i in 6:
		var y := horizon + (i + 1) * (box.end.y - horizon) / 7.0
		var x := box.position.x + fmod(i * 61.0, box.size.x * 0.7)
		draw_line(Vector2(x, y), Vector2(x + box.size.x * 0.2, y), Color(1, 1, 1, 0.18), 2.0)
	if kind in ["voyage", "weather", "sunset"]:
		_draw_boat(Vector2(box.position.x + box.size.x * 0.34, horizon + 6), box.size.y * 0.28)
	if _picture:
		var fit := _picture.get_size()
		var scale := minf(box.size.x * 0.86 / fit.x, box.size.y * 0.86 / fit.y)
		var drawn := fit * scale
		draw_texture_rect(_picture, Rect2(box.get_center() - drawn * 0.5 + Vector2(0, box.size.y * 0.04), drawn), false)


func _draw_boat(at: Vector2, height: float) -> void:
	var hull := PackedVector2Array([at + Vector2(-height * 0.45, -height * 0.08), at + Vector2(height * 0.5, -height * 0.08),
		at + Vector2(height * 0.36, height * 0.06), at + Vector2(-height * 0.36, height * 0.06)])
	draw_colored_polygon(hull, Color(0.95, 0.95, 0.92))
	draw_line(at + Vector2(0, -height * 0.08), at + Vector2(0, -height), INK, 2.0)
	draw_colored_polygon(PackedVector2Array([at + Vector2(3, -height * 0.95), at + Vector2(height * 0.42, -height * 0.14),
		at + Vector2(3, -height * 0.14)]), Color(1, 1, 1, 0.95))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -height * 0.8), at + Vector2(-height * 0.3, -height * 0.14),
		at + Vector2(-3, -height * 0.14)]), Color(0.97, 0.95, 0.9, 0.9))


func _gradient(box: Rect2, from: Color, to: Color) -> void:
	draw_polygon(PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]),
		PackedColorArray([from, from, to, to]))
