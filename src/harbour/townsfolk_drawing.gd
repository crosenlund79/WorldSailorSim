class_name TownsfolkDrawing
extends RefCounted
## The harbour's people (I026 stage 02, HarbourLife), seen from above and
## drawn like the Captain (SailorDrawing) and the girl (GirlDrawing): form by
## tone, a soft ink line, lit from the upper left, natural adult proportions.
## No faces to speak of, nothing cartoonish: a coat, shoulders, arms that
## swing a little, hair or a hat.
##
## Clothing follows the harbour's region (PALETTES: oilskins and wool in the
## north, waxed cotton and navy on the Atlantic, linen in the Mediterranean,
## light cotton and straw hats in the tropics). A look is made once per
## person (make_look) from a seed, so the same person always looks the same.
## Poses: standing or walking (`swing`), sitting at a table (`seated`),
## carrying something (`item`: a shopping bag, a newspaper, a cup, keys).
## The same numbers always give the same drawing.

const INK := Color(0.12, 0.15, 0.17, 0.75)
const SHADOW := Color(0.02, 0.04, 0.05, 0.26)
const SHOULDER := 16.5
const DEPTH := 9.0
const HEAD := 9.0
const SWING := 6.0

const ITEM_NONE := &""
const ITEM_BAG := &"bag"
const ITEM_PAPER := &"paper"
const ITEM_CUP := &"cup"
const ITEM_KEYS := &"keys"

## Per archetype: coats, hats (null: bare-headed), hair and skin tones.
const PALETTES := {
	&"nordic": {"coats": [Color("#2F3E4C"), Color("#C9A33A"), Color("#6E7173"), Color("#8E3B30"), Color("#3F5A48"), Color("#4A4F5A")],
		"hats": [Color("#3A4A5A"), Color("#8E3B30"), Color("#5A5F62"), null, null],
		"hair": [Color("#B89A6A"), Color("#8A6A48"), Color("#4A3A2E"), Color("#C9C2B4"), Color("#D2B48A")],
		"skin": [Color("#E2BFA4"), Color("#D9B092"), Color("#C99C7E")]},
	&"atlantic": {"coats": [Color("#2F3E4C"), Color("#3E4A36"), Color("#B8A888"), Color("#4D6170"), Color("#B08A3A"), Color("#5A4A44")],
		"hats": [Color("#2F3E4C"), Color("#6E5A44"), null, null, null],
		"hair": [Color("#6A4A32"), Color("#4A3A2E"), Color("#A8774C"), Color("#B9B2A6"), Color("#2E2622")],
		"skin": [Color("#E0BCA0"), Color("#C99C7E"), Color("#A87A5E")]},
	&"mediterranean": {"coats": [Color("#D9D0BC"), Color("#E8E6DF"), Color("#B5704F"), Color("#7F9CB0"), Color("#7A7A4E"), Color("#3E5F7A")],
		"hats": [Color("#D8C48E"), null, null, null, Color("#E8E6DF")],
		"hair": [Color("#2E2622"), Color("#4A3A2E"), Color("#6A4A32"), Color("#B9B2A6")],
		"skin": [Color("#C99C7E"), Color("#B58468"), Color("#9A6A4E"), Color("#D9B092")]},
	&"tropical": {"coats": [Color("#3F8A8A"), Color("#D9785F"), Color("#E8E6DF"), Color("#D9B95A"), Color("#5E8B4A"), Color("#4F6F7E")],
		"hats": [Color("#D8C48E"), Color("#E0D2A0"), null, null, Color("#2F3E4C")],
		"hair": [Color("#1E1A18"), Color("#2E2622"), Color("#4A3A2E")],
		"skin": [Color("#8A5A3E"), Color("#6E4632"), Color("#A87A5E"), Color("#C99C7E")]},
}


## A person's look from `seed` in `archetype`'s palette:
## {"coat", "coat_light", "sleeve", "hat" (Color or null), "hair", "skin", "build"}.
static func make_look(archetype: StringName, seed: int) -> Dictionary:
	var palette: Dictionary = PALETTES.get(archetype, PALETTES[&"nordic"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var coats: Array = palette.coats
	var coat: Color = coats[rng.randi() % coats.size()]
	var hats: Array = palette.hats
	var hairs: Array = palette.hair
	var skins: Array = palette.skin
	return {"coat": coat, "coat_light": coat.lightened(0.16), "sleeve": coat.darkened(0.12), "hat": hats[rng.randi() % hats.size()],
		"hair": hairs[rng.randi() % hairs.size()], "skin": skins[rng.randi() % skins.size()], "build": rng.randf_range(0.9, 1.06)}


static func draw(canvas: CanvasItem, facing: Vector2, swing: float, look: Dictionary, seated := false, item: StringName = ITEM_NONE) -> void:
	var k: float = look.get("build", 1.0)
	var side := facing.orthogonal()
	var body_center := -facing * 2.5
	var coat: Color = look.coat
	var skin: Color = look.skin
	canvas.draw_colored_polygon(SailorDrawing._ellipse(body_center + Vector2(3, 4), (SHOULDER + 1.0) * k, (DEPTH + 2.0) * k, side), SHADOW)
	var right_hand := Vector2.ZERO
	var left_hand := Vector2.ZERO
	for side_sign: float in [-1.0, 1.0]:
		var shoulder: Vector2 = body_center + side * (SHOULDER - 3.0) * k * side_sign
		var hand: Vector2
		if seated:
			# Both forearms forward, on the table.
			hand = body_center + facing * 13.0 * k + side * side_sign * 8.0 * k
		else:
			var arm_swing := swing * side_sign
			if item != ITEM_NONE and side_sign > 0.0:
				arm_swing = 0.2
			hand = side * (SHOULDER - 2.0) * k * side_sign - facing * 2.5 + facing * (5.0 + SWING * arm_swing) + side * side_sign * 3.0
		canvas.draw_line(shoulder, hand, INK, 7.0 * k, true)
		canvas.draw_line(shoulder, hand, look.sleeve, 5.6 * k, true)
		canvas.draw_circle(hand, 3.0 * k, Color(INK, 0.6))
		canvas.draw_circle(hand, 2.4 * k, skin)
		if side_sign > 0.0:
			right_hand = hand
		else:
			left_hand = hand
	var body := SailorDrawing._ellipse(body_center, SHOULDER * k, DEPTH * k, side)
	canvas.draw_colored_polygon(body, coat)
	canvas.draw_colored_polygon(SailorDrawing._ellipse(body_center + Vector2(-1.4, -1.4), SHOULDER * 0.7 * k, DEPTH * 0.58 * k, side),
		Color(look.coat_light, 0.6))
	canvas.draw_polyline(SailorDrawing._closed(body), INK, 1.0, true)
	# A collar line, and the head: hair or a hat.
	canvas.draw_arc(body_center + facing * 2.0, HEAD * 0.9 * k, side.angle() + PI * 0.15, side.angle() + PI * 0.85, 8, Color(coat.darkened(0.3), 0.8), 2.0, true)
	canvas.draw_circle(Vector2(1.4, 1.8), HEAD * k + 0.5, SHADOW)
	canvas.draw_circle(Vector2.ZERO, HEAD * k + 0.7, INK)
	var hat = look.get("hat")
	if hat != null:
		var hat_colour: Color = hat
		var brimmed := hat_colour.get_luminance() > 0.6  # straw and white hats have a brim
		if brimmed:
			canvas.draw_circle(Vector2.ZERO, HEAD * k * 1.55, Color(INK, 0.5))
			canvas.draw_circle(Vector2.ZERO, HEAD * k * 1.5, hat_colour.darkened(0.08))
		canvas.draw_circle(Vector2.ZERO, HEAD * k, hat_colour)
		canvas.draw_circle(Vector2(-1.6, -1.6), HEAD * k * 0.5, Color(hat_colour.lightened(0.2), 0.6))
	else:
		var hair: Color = look.hair
		canvas.draw_circle(Vector2.ZERO, HEAD * k, hair)
		canvas.draw_circle(Vector2(-1.8, -1.8), HEAD * 0.55 * k, Color(hair.lightened(0.18), 0.6))
		var face := PackedVector2Array()
		for i in 13:
			var a := -PI * 0.5 + PI * i / 12.0
			face.append(facing * HEAD * k * 0.95 * cos(a) * 0.5 + facing * HEAD * k * 0.42 + side * HEAD * k * 0.92 * sin(a))
		canvas.draw_colored_polygon(face, skin)
	canvas.draw_circle(facing * (HEAD * k + 0.5), 1.5, skin.darkened(0.1))
	match item:
		ITEM_BAG:
			var bag := right_hand + side * 4.0
			canvas.draw_rect(Rect2(bag - Vector2(6, 5), Vector2(12, 10)), Color("#B9A27A"))
			canvas.draw_rect(Rect2(bag - Vector2(6, 5), Vector2(12, 10)), Color(INK, 0.5), false, 1.0)
			canvas.draw_circle(bag + Vector2(-2, -4), 2.6, Color("#6E8B3D"))  # leeks and bread in the bag
		ITEM_PAPER:
			var at := (left_hand + right_hand) / 2.0 + facing * 3.0
			var paper := PackedVector2Array([at - side * 11.0 - facing * 6.0, at + side * 11.0 - facing * 6.0,
				at + side * 11.0 + facing * 7.0, at - side * 11.0 + facing * 7.0])
			canvas.draw_colored_polygon(paper, Color("#E8E4D8"))
			canvas.draw_line(at - facing * 6.0, at + facing * 7.0, Color(INK, 0.4), 1.0)
		ITEM_CUP:
			CoffeeMug.draw_mug(canvas, right_hand + facing * 3.0, 0.65, side.angle())
		ITEM_KEYS:
			canvas.draw_circle(right_hand + facing * 2.0, 2.6, Color("#C8B07A"))
