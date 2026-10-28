class_name CabinSeaBackdrop
extends Node2D
## The sea outside the hull in the cabin view (I025, A Little More Room
## Aboard). Below deck the world beyond the hull used to be a dark void; now
## the same illustrated sea as on deck (SeaSurface and its shader, so the
## swell, the wind, the weather, the harbour's shelter and the boat's way
## through the water all match) lies around the hull, faded: a veil of the
## night-blue backdrop colour over it, thinnest along the hull and closing to
## the plain backdrop a little way out, darker and less saturated at night.
## Moored, the berth's pontoon shows very faintly on the quay side (starboard,
## where it lies on deck). The captain keeps a sense of the boat floating on
## the water without the hull ever looking like glass.
##
## It lives in the cabin's Backdrop (right above its Darkness polygon), so the
## cabin art, the furniture, the companion, the captain and every control are
## always drawn over it: it can only show where the cabin art is transparent,
## outside the hull (and between a catamaran's hulls or round a trimaran's
## floats). Cabin lamps do not light it (light_mask 0).
##
## Cost: one shader mesh (the deck's sea, reaching only as far as the fade
## and leaving out the cabin sole, which the opaque cabin art covers), one
## small vertex-coloured mesh for the veil, one rectangle for the pontoon; the
## veil is rebuilt only when the light changes (checked every
## REFRESH_SECONDS). Measured on the software renderer (llvmpipe, 1600x900,
## Wing 33 cabin): about +40 ms a frame with the whole rectangle shaded,
## see the report in docs for the cut mesh.
##
## BoatArea adds it with one call: CabinSeaBackdrop.attach(self).

const DATA_PATH := "res://data/vessels/cabin_windows.json"
const REFRESH_SECONDS := 1.0
## The veil, from the hull outwards: ring sizes (times the boat's half size,
## as a rounded rectangle) and how much of the sea shows through at each by
## day ("day") and at night ("night"). Beyond the last the backdrop is plain.
const RINGS := [0.0, 0.92, 1.08, 1.3, 1.6, 2.0, 2.5]
const SHOW_DAY := [0.46, 0.46, 0.4, 0.27, 0.14, 0.05, 0.0]
const SHOW_NIGHT := [0.34, 0.34, 0.28, 0.18, 0.09, 0.03, 0.0]
## The sun's glints on the sea are kept to this share of the deck's (under
## the veil they would read as specks, not light).
const GLINTS := 0.25
## Corners of the rounded rectangle (superellipse exponent: 2 an ellipse,
## higher is squarer).
const ROUNDNESS := 4.0
const SEGMENTS := 72
## The veil's colour: the backdrop's night blue, a little lighter by day.
const VEIL_NIGHT := Color(0.0392, 0.1098, 0.1451)
const VEIL_DAY := Color(0.11, 0.16, 0.19)
const PONTOON := Color(0.42, 0.39, 0.35, 0.5)

var area: BoatArea
## The boat's half size (scene units) the rings are measured from.
var half_size := Vector2(500, 170)
## SeaSurface's carrier polygon (hidden) and the mesh the sea is drawn on.
var sea: Polygon2D
var sea_mesh: MeshInstance2D
var surface: SeaSurface
var veil: MeshInstance2D
var pontoon: Polygon2D
## 0 night .. 1 day, as last sampled (tests).
var day := 1.0

var _refresh_left := 0.0
var _veil_day := -1.0
static var _data := {}


## Adds the faded sea to `boat_area`'s Backdrop when it is a cabin; returns
## it (null on a deck, or without a Backdrop). Calling it again returns the
## one already there.
static func attach(boat_area: BoatArea) -> CabinSeaBackdrop:
	if boat_area == null or boat_area.area_id != SessionState.AREA_INTERIOR:
		return null
	var backdrop := boat_area.get_node_or_null(^"Backdrop")
	if backdrop == null:
		return null
	var existing := backdrop.get_node_or_null(^"CabinSea") as CabinSeaBackdrop
	if existing:
		return existing
	var node := CabinSeaBackdrop.new()
	node.name = "CabinSea"
	backdrop.add_child(node)
	var darkness := backdrop.get_node_or_null(^"Darkness")
	if darkness:
		backdrop.move_child(node, darkness.get_index() + 1)
	node.setup(boat_area)
	return node


## The berth's pontoon for `vessel_id` in cabin units (empty when unknown).
static func pontoon_for(vessel_id: StringName) -> Rect2:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	var entry: Variant = (_data.get("sea", {}) as Dictionary).get(String(vessel_id), {})
	if entry is Dictionary and (entry as Dictionary).get("pontoon") is Array and (entry.pontoon as Array).size() == 4:
		var r: Array = entry.pontoon
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return Rect2()


## A point on the rounded rectangle of half size `half` * `scale_by` at angle `t`.
static func ring_point(half: Vector2, scale_by: float, t: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	var e := 2.0 / ROUNDNESS
	return Vector2(signf(c) * pow(absf(c), e) * half.x, signf(s) * pow(absf(s), e) * half.y) * scale_by


func setup(boat_area: BoatArea) -> void:
	area = boat_area
	var visual := area.get_node_or_null(^"Visual") as VesselVisual
	if visual and visual.canvas.size != Vector2.ZERO:
		half_size = visual.canvas.size * 0.5 * 0.92
	# The sea: SeaSurface drives the deck's sea shader on a (hidden) carrier
	# polygon; the shader is drawn on a mesh that reaches as far as the veil
	# lets the sea through and leaves out the cabin sole, which the opaque
	# cabin art always covers (no shading of pixels nobody sees).
	sea = Polygon2D.new()
	sea.name = "SeaCarrier"
	sea.visible = false
	add_child(sea)
	surface = SeaSurface.new()
	add_child(surface)
	surface.setup(area, sea)
	sea_mesh = MeshInstance2D.new()
	sea_mesh.name = "Sea"
	sea_mesh.light_mask = 0
	sea_mesh.material = surface.material
	sea_mesh.mesh = _sea_mesh(half_size * (RINGS[RINGS.size() - 1] + 0.05), _sole_outline())
	add_child(sea_mesh)
	# The berth's pontoon, very faint, under the veil.
	pontoon = Polygon2D.new()
	pontoon.name = "Pontoon"
	pontoon.light_mask = 0
	pontoon.color = PONTOON
	var rect := pontoon_for(GameSession.get_vessel_id())
	pontoon.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])
	pontoon.visible = false
	add_child(pontoon)
	veil = MeshInstance2D.new()
	veil.name = "Veil"
	veil.light_mask = 0
	add_child(veil)
	# After SeaSurface each frame (it sets the shader's sun), to soften the glints.
	process_priority = surface.process_priority + 1
	_refresh()


func _process(delta: float) -> void:
	if area == null or not GameSession.is_active():
		return
	if surface and surface.material:
		surface.material.set_shader_parameter(&"sun", surface.sun * GLINTS)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh()


## Reads the light and the berth, and rebuilds the veil (cheap: a few
## hundred vertices, once a second).
func _refresh() -> void:
	_refresh_left = REFRESH_SECONDS
	if GameSession.is_active():
		var elevation := Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time())
		var overcast := BoatLighting.overcast_of(Simulation.get_weather_at_vessel())
		day = Daylight.daylight(elevation) * (1.0 - overcast * 0.4)
		pontoon.visible = not GameSession.is_underway() and not GameSession.is_anchored() and pontoon.polygon.size() == 4 \
			and pontoon.polygon[0] != pontoon.polygon[2]
	if absf(day - _veil_day) > 0.01:
		_veil_day = day
		veil.mesh = _veil_mesh(day)


## The cabin sole (the walkable floor, Layout/Collision/Hull) in this node's
## coordinates, a little inset; empty when the cabin has none.
func _sole_outline() -> PackedVector2Array:
	var hull := area.get_node_or_null(^"Layout/Collision/Hull")
	if hull == null:
		return PackedVector2Array()
	for child in hull.get_children():
		if child is CollisionPolygon2D and (child as CollisionPolygon2D).polygon.size() >= 3:
			var into := get_global_transform().affine_inverse() * (child as CollisionPolygon2D).get_global_transform()
			var inset := Geometry2D.offset_polygon(into * (child as CollisionPolygon2D).polygon, -2.0)
			return inset[0] if inset.size() == 1 else PackedVector2Array()
	return PackedVector2Array()


## The sea's area: the rectangle of half size `half` without `hole`, built
## from vertical strips (each wide hole crosses its strips, so no strip is
## left with a hole inside it) and triangulated.
static func _sea_mesh(half: Vector2, hole: PackedVector2Array) -> ArrayMesh:
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var strips := 16
	for k in strips:
		var x0 := -half.x + 2.0 * half.x * float(k) / float(strips)
		var x1 := -half.x + 2.0 * half.x * float(k + 1) / float(strips)
		var strip := PackedVector2Array([Vector2(x0, -half.y), Vector2(x1, -half.y), Vector2(x1, half.y), Vector2(x0, half.y)])
		var pieces: Array[PackedVector2Array] = [strip]
		if hole.size() >= 3:
			var cut := Geometry2D.clip_polygons(strip, hole)
			var has_hole := cut.any(func(p: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(p))
			pieces = [strip] if has_hole else cut
		for piece in pieces:
			var tris := Geometry2D.triangulate_polygon(piece)
			var base := points.size()
			points.append_array(piece)
			for i in tris:
				indices.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not indices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## How much of the sea shows at ring `i` for the light `light` (0 night .. 1 day).
func show_at(i: int, light: float) -> float:
	return lerpf(SHOW_NIGHT[i], SHOW_DAY[i], light)


func _veil_mesh(light: float) -> ArrayMesh:
	var colour := VEIL_NIGHT.lerp(VEIL_DAY, light)
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	# Ring 0 is the centre point; the outermost ring is pushed far out so the
	# veil covers the view however it is zoomed.
	points.append(Vector2.ZERO)
	colours.append(Color(colour, 1.0 - show_at(0, light)))
	for r in range(1, RINGS.size() + 1):
		var scale_by: float = RINGS[r] if r < RINGS.size() else 40.0
		var alpha := 1.0 - show_at(mini(r, RINGS.size() - 1), light)
		for i in SEGMENTS:
			points.append(ring_point(half_size, scale_by, TAU * float(i) / float(SEGMENTS)))
			colours.append(Color(colour, alpha))
	var indices := PackedInt32Array()
	for i in SEGMENTS:
		indices.append_array([0, 1 + i, 1 + (i + 1) % SEGMENTS])
	for r in range(1, RINGS.size()):
		var inner := 1 + (r - 1) * SEGMENTS
		var outer := 1 + r * SEGMENTS
		for i in SEGMENTS:
			var j := (i + 1) % SEGMENTS
			indices.append_array([inner + i, outer + i, outer + j, inner + i, outer + j, inner + j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
