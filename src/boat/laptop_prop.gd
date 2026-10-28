class_name LaptopProp
extends Node2D
## The Captain's laptop on the cabin table (I024, The Company We Keep): a
## small, practical laptop, open, its screen facing the work station where
## the Captain sits. Drawn in the cabin's top-down view (seen from above and a
## little in front), in the Real Horizon palette: graphite body, a keyboard,
## the screen softly lit (brighter at night).
##
## Presentation only: the work station's Interactable (interaction "work")
## stays where it was and opens the laptop (App.open_laptop()). BoatArea
## places one on the table nearest that station in every cabin (place()).

## Width of the laptop in scene units (a 14-inch laptop on a yacht's table,
## a little larger than life so it reads at 1×).
const WIDTH := 26.0
const BODY := Color("#3A4146")
const BODY_EDGE := Color("#565F64")
const KEYS := Color("#252B2F")
const KEY := Color("#4A5358")
const SCREEN := Color("#9FC3CC")
const SCREEN_DARK := Color("#2C4752")
const INK := Color(0.16, 0.2, 0.22, 0.6)
const TABLE_NAMES: Array[String] = ["SaloonTable", "Desk", "Table"]

## How bright the screen is (0..1); a little more at night (BoatArea's light).
var glow := 0.7


## Puts a laptop on the table nearest `station` in `area` (cabins only).
## Returns it, or null when the cabin has no table.
static func place(area: Node2D, station: Node2D) -> LaptopProp:
	var table: BoatFixture = null
	var best := INF
	for table_name in TABLE_NAMES:
		var fixture := area.get_node_or_null(NodePath("Layout/Collision/" + table_name)) as BoatFixture
		if fixture == null:
			continue
		var d := area.to_local(fixture.global_position).distance_to(area.to_local(station.global_position))
		if d < best:
			best = d
			table = fixture
	if table == null:
		return null
	var points := table.transform * table.get_points()
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	var toward := area.to_local(station.global_position) - rect.get_center()
	var prop := LaptopProp.new()
	prop.name = "Laptop"
	# On the table, a hand's width in from the edge on the Captain's side.
	var inset := clampf(minf(rect.size.x, rect.size.y) * 0.5 - 14.0, 0.0, 40.0)
	prop.position = rect.get_center() + (toward.normalized() * inset if toward.length() > 1.0 else Vector2.ZERO)
	prop.position.x += 6.0  # a little off-centre, as a laptop is
	prop.z_index = 3
	area.add_child(prop)
	return prop


func _draw() -> void:
	var w := WIDTH
	var h := w * 0.6
	# Shadow on the table, down and to the right.
	draw_rect(Rect2(Vector2(-w * 0.5 + 1.5, -h * 0.15 + 2.0), Vector2(w, h * 0.8)), Color(0.05, 0.07, 0.08, 0.28))
	# Screen light spilling onto the table in front of it.
	draw_colored_polygon(_ellipse(Vector2(0, h * 0.42), Vector2(w * 0.55, h * 0.3)), Color(SCREEN, 0.06 + 0.06 * glow))
	# The base with the keyboard (towards the Captain, below).
	var base := Rect2(Vector2(-w * 0.5, -h * 0.12), Vector2(w, h * 0.62))
	draw_rect(base, BODY)
	draw_rect(Rect2(base.position, Vector2(base.size.x, 1.0)), BODY_EDGE)
	var keys := Rect2(base.position + Vector2(2.0, 1.6), Vector2(base.size.x - 4.0, base.size.y * 0.55))
	draw_rect(keys, KEYS)
	for row in 4:
		for col in 11:
			var k := Rect2(keys.position + Vector2(0.6 + col * (keys.size.x - 1.2) / 11.0, 0.6 + row * keys.size.y / 4.0),
				Vector2((keys.size.x - 1.2) / 11.0 - 0.5, keys.size.y / 4.0 - 0.6))
			draw_rect(k, KEY)
	draw_rect(Rect2(Vector2(-w * 0.14, keys.end.y + 1.2), Vector2(w * 0.28, base.end.y - keys.end.y - 2.4)), BODY_EDGE.darkened(0.15))
	draw_rect(base, INK, false, 0.6)
	# The lid, open, its screen towards the Captain (foreshortened, above).
	var lid := PackedVector2Array([Vector2(-w * 0.5, -h * 0.12), Vector2(w * 0.5, -h * 0.12),
		Vector2(w * 0.46, -h * 0.62), Vector2(-w * 0.46, -h * 0.62)])
	draw_colored_polygon(lid, BODY.darkened(0.25))
	var screen := PackedVector2Array([Vector2(-w * 0.44, -h * 0.17), Vector2(w * 0.44, -h * 0.17),
		Vector2(w * 0.41, -h * 0.57), Vector2(-w * 0.41, -h * 0.57)])
	draw_colored_polygon(screen, SCREEN_DARK.lerp(SCREEN, 0.35 + 0.45 * glow))
	# A hint of what is on it: a header and a few lines.
	draw_line(Vector2(-w * 0.36, -h * 0.5), Vector2(w * 0.1, -h * 0.5), Color(1, 1, 1, 0.35 * glow), 1.0)
	for i in 3:
		draw_line(Vector2(-w * 0.36, -h * (0.41 - i * 0.07)), Vector2(w * (0.3 - i * 0.12), -h * (0.41 - i * 0.07)), Color(SCREEN_DARK, 0.5), 0.8)
	draw_polyline(PackedVector2Array([lid[0], lid[3], lid[2], lid[1]]), INK, 0.6)


static func _ellipse(center: Vector2, radii: Vector2, steps := 18) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		var a := TAU * i / steps
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points
