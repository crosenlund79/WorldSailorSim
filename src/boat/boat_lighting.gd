class_name BoatLighting
extends Node2D
## Light for a boat area (Iteration 17), driven by the game clock and where
## the boat is (Daylight):
## - a CanvasModulate for the light of the hour: the sky outside on deck,
##   daylight through the ports and hatches in the cabin;
## - warm lamps in the cabin, placed at the boat's own fixtures (saloon
##   table, galley, chart table, berths), so they fit all four boats and keep
##   fitting when furniture finishes change (they follow fixture names, not
##   art); daylight pools at the companionway and forward hatch by day;
## - on deck at night: a soft cool glow at the helm instruments, warm cabin
##   light spilling from the companionway and small navigation lights (red
##   to port, green to starboard, white astern), restrained;
## - in harbour at night: the quay's lamps (from the shared harbour
##   dressing, so every harbour gets them) and soft lights along the pontoon;
## - soft shadows beside the fixtures and under the captain and companion,
##   for depth (not physically exact; drawn once).
## Lightning (flash()) brightens everything for a moment, gently.
##
## Cost: a handful of PointLight2D nodes sharing one gradient texture, one
## colour blend a frame, a weather look-up every few game minutes.

const LAMP_WARM := Color(1.0, 0.85, 0.66)
const LAMP_GALLEY := Color(1.0, 0.9, 0.76)
const LAMP_CHART := Color(1.0, 0.36, 0.3)  # red night-vision chart light
const DAY_HATCH := Color(0.86, 0.93, 1.0)
const INSTRUMENT := Color(0.72, 0.86, 1.0)
const NAV_RED := Color(1.0, 0.25, 0.2)
const NAV_GREEN := Color(0.3, 1.0, 0.45)
const NAV_WHITE := Color(1.0, 0.97, 0.9)
const QUAY_LAMP := Color(1.0, 0.87, 0.68)
const SHADOW := Color(0.02, 0.04, 0.05)
## Fixture names that carry a lamp in the cabin: name -> [colour, size, strength].
## Iteration 18: stronger, with a tighter falloff (pool_texture), so each lamp
## makes a warm pool and the floor between them and the corners stays dim -
## more light at the saloon table and the galley especially.
const CABIN_LAMPS := {
	"SaloonTable": [LAMP_WARM, 1.9, 1.15], "Table": [LAMP_WARM, 1.9, 1.15],
	"Galley": [LAMP_GALLEY, 1.35, 1.05], "GalleySide": [LAMP_GALLEY, 1.35, 1.05],
	"NavTable": [LAMP_CHART, 0.95, 0.9], "NavDesk": [LAMP_CHART, 0.95, 0.9],
	"VBerth": [LAMP_WARM, 1.1, 0.6], "OwnerBerth": [LAMP_WARM, 1.1, 0.6], "GuestBerth": [LAMP_WARM, 1.0, 0.55],
	"Desk": [LAMP_WARM, 1.0, 0.7], "OwnerSofa": [LAMP_WARM, 1.2, 0.65],
}
## How quickly the light follows the clock (per second): fast time (Long
## Passage at hours per second) shows a gentle swell, never a strobe.
const FOLLOW_RATE := 2.5
const WEATHER_REFRESH := 600.0

static var _texture: GradientTexture2D
static var _pool_texture: GradientTexture2D

var area: BoatArea
var _modulate: CanvasModulate
## [{"light": PointLight2D, "energy": float, "when": "night" | "day" | "dark" |
## "harbour" | "underway" | "anchor"}]
var _lights: Array[Dictionary] = []
var _lamps: Lamps
var _corner_shade: CornerShade
var _colour := Color.WHITE
var _darkness := 0.0
var _overcast := 0.0
var _weather_at := -INF
var _flash := 0.0
var _initialised := false


static func light_texture() -> GradientTexture2D:
	if _texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.45))
		_texture = GradientTexture2D.new()
		_texture.gradient = gradient
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = 256
		_texture.height = 256
	return _texture


## The cabin lamps' light (Iteration 18): bright near the lamp, falling off
## sooner than light_texture(), and soft at the rim - a pool, not a wash.
static func pool_texture() -> GradientTexture2D:
	if _pool_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.3, Color(1, 1, 1, 0.62))
		gradient.add_point(0.62, Color(1, 1, 1, 0.16))
		_pool_texture = GradientTexture2D.new()
		_pool_texture.gradient = gradient
		_pool_texture.fill = GradientTexture2D.FILL_RADIAL
		_pool_texture.fill_from = Vector2(0.5, 0.5)
		_pool_texture.fill_to = Vector2(1.0, 0.5)
		_pool_texture.width = 256
		_pool_texture.height = 256
	return _pool_texture


func setup(boat_area: BoatArea) -> void:
	area = boat_area
	# A node name, not text the Captain reads: BoatArea.get_lighting() and
	# App find it by this name in every language.
	name = "Lighting"
	_modulate = CanvasModulate.new()
	_modulate.name = "Ambient"
	area.add_child(_modulate)
	var interior := area.area_id == SessionState.AREA_INTERIOR
	var collision := area.get_node_or_null(^"Layout/Collision")
	if collision:
		for child in collision.get_children():
			var fixture := child as BoatFixture
			if fixture == null:
				continue
			var spec: Array = CABIN_LAMPS.get(String(fixture.name), [])
			if interior and not spec.is_empty():
				_add_light(fixture.position, spec[0], spec[1], spec[2], "dark").texture = pool_texture()
			if not interior and String(fixture.name) in ["Wheel", "Tiller", "Pedestal"]:
				_add_light(fixture.position, INSTRUMENT, 0.7, 0.55, "night")
	# The companionway (every boat has one): daylight down it into the cabin,
	# lamplight up it onto the deck at night.
	for station in area.find_children("*", "Interactable", true, false):
		if (station as Interactable).interaction_id == &"companionway":
			var at := area.to_local((station as Node2D).global_position)
			if interior:
				_add_light(at, DAY_HATCH, 1.6, 0.35, "day")
			else:
				_add_light(at, LAMP_WARM, 1.2, 0.6, "night")
			break
	if interior:
		var berth := collision.get_node_or_null(^"VBerth") if collision else null
		if berth:
			_add_light((berth as Node2D).position + Vector2(-20, 0), DAY_HATCH, 1.3, 0.25, "day")
	else:
		_add_navigation_lights()
		_add_anchor_light()
		_add_harbour_lights()
		_lamps = Lamps.new()
		_lamps.name = "Lamps"
		_lamps.lighting = self
		_lamps.z_index = 26
		_lamps.z_as_relative = false
		area.add_child(_lamps)
	_add_shadows(collision)
	if interior:
		_add_corner_shade()
	_add_contact_shadows()
	update_now()


func _add_light(at: Vector2, colour: Color, size: float, energy: float, when: String, parent: Node = null, lamp := false) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = light_texture()
	light.texture_scale = size
	light.color = colour
	light.energy = 0.0
	light.position = at
	light.blend_mode = Light2D.BLEND_MODE_ADD
	(parent if parent else self).add_child(light)
	_lights.append({"light": light, "energy": energy, "when": when, "lamp": lamp})
	return light


## The boat's outline on deck (for lights and signals at its edges).
func boat_bounds() -> Rect2:
	var bounds := area.walkable_bounds
	var shore := area.get_shore_access()
	if shore:
		bounds = shore.get_boat_bounds()
	return bounds


## Red to port, green to starboard at the bow, white at the stern (the boat's
## bow is +x, port -y): small, at night, underway only (not moored, not at
## anchor). Iteration 18: each also shows its little lamp (a bright dot with
## a small glow), so the lights read as lights over the dark sea, and they
## sit at the hull's edges.
func _add_navigation_lights() -> void:
	var bounds := boat_bounds()
	var bow := bounds.end.x - bounds.size.x * 0.14
	var sides := _hull_sides_at(bow)
	var port := sides.x if is_finite(sides.x) else bounds.position.y + bounds.size.y * 0.16
	var starboard := sides.y if is_finite(sides.y) else bounds.end.y - bounds.size.y * 0.16
	_add_light(Vector2(bow, port), NAV_RED, 0.26, 1.0, "underway", null, true)
	_add_light(Vector2(bow, starboard), NAV_GREEN, 0.26, 1.0, "underway", null, true)
	_add_light(Vector2(bounds.position.x + 6.0, bounds.get_center().y), NAV_WHITE, 0.3, 0.9, "underway", null, true)


## Where the hull's edges are, across the boat at `x` (just inside the
## lifeline, port and starboard), so the side lights sit on the rail rather
## than out over the water where the bow narrows. INF when unknown.
func _hull_sides_at(x: float) -> Vector2:
	var lifeline := area.get_node_or_null(^"Layout/Collision/Lifeline/CollisionPolygon2D") as CollisionPolygon2D
	if lifeline == null:
		return Vector2(INF, INF)
	var outline := (area.global_transform.affine_inverse() * lifeline.global_transform) * lifeline.polygon
	var low := INF
	var high := -INF
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if (a.x - x) * (b.x - x) > 0.0 or is_equal_approx(a.x, b.x):
			continue
		var y := lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
		low = minf(low, y)
		high = maxf(high, y)
	if not is_finite(low) or not is_finite(high):
		return Vector2(INF, INF)
	return Vector2(low + 6.0, high - 6.0)


## The white all-round anchor light (Iteration 18): at the masthead, at night
## at anchor only (never with the red and green).
func _add_anchor_light() -> void:
	var rig := area.get_node_or_null(^"SailRig") as SailRig
	var at := rig.mast if rig else boat_bounds().get_center()
	_add_light(at, NAV_WHITE, 0.55, 1.0, "anchor", null, true)


## The quay's lamps and the pontoon, from the shared harbour dressing (every
## harbour: no per-harbour lighting scenes).
func _add_harbour_lights() -> void:
	var dressing := area.get_harbour_dressing()
	if dressing == null:
		return
	# In the mooring (beside the dressing): they move with the harbour
	# during the docking arrival.
	var mooring := dressing.get_parent()
	for lamp in dressing.get_lamp_positions():
		_add_light(dressing.position + lamp, QUAY_LAMP, 1.1, 0.55, "harbour", mooring)
	for spot in dressing.get_pontoon_light_positions():
		_add_light(dressing.position + spot, QUAY_LAMP, 0.7, 0.22, "harbour", mooring)


## Soft shadows beside the furniture and fittings: the fixture's outline
## moved down and right a little, minus the fixture itself, in a few soft
## layers. Drawn once (a node behind the captain, above the art).
func _add_shadows(collision: Node) -> void:
	if collision == null:
		return
	var shadows := FixtureShadows.new()
	shadows.name = "FixtureShadows"
	var visual := area.get_node_or_null(^"Visual")
	area.add_child(shadows)
	if visual:
		area.move_child(shadows, visual.get_index() + 1)
	var bounds := area.walkable_bounds.get_area()
	for child in collision.get_children():
		var fixture := child as BoatFixture
		if fixture == null or not fixture.solid or String(fixture.name) in ["Hull", "Lifeline"]:
			continue
		var outline := fixture.transform * fixture.get_points()
		var box := Rect2(outline[0], Vector2.ZERO)
		for p in outline:
			box = box.expand(p)
		if box.get_area() > bounds * 0.3:
			continue
		shadows.outlines.append(outline)
	shadows.queue_redraw()


## Iteration 18: the cabin's corners and walls fall into soft shade at night,
## away from the lamps - a gentle gradient along the floor's edges (deepest
## where two walls meet), drawn once with the fixture shadows and faded in
## with the dark. No occlusion, no per-frame work beyond one alpha.
func _add_corner_shade() -> void:
	_corner_shade = CornerShade.new()
	_corner_shade.name = "CornerShade"
	_corner_shade.bounds = area.walkable_bounds.grow(24.0)
	# Only inside the cabin's own outline (never over the water or the dark
	# beyond the hull).
	var hull := area.get_node_or_null(^"Layout/Collision/Hull/CollisionPolygon2D") as CollisionPolygon2D
	if hull and hull.polygon.size() >= 3:
		_corner_shade.clip = (area.global_transform.affine_inverse() * hull.global_transform) * hull.polygon
	var shadows := area.get_node_or_null(^"FixtureShadows")
	area.add_child(_corner_shade)
	if shadows:
		area.move_child(_corner_shade, shadows.get_index())
	_corner_shade.modulate.a = 0.0


func add_contact_shadows() -> void:
	_add_contact_shadows()


func _add_contact_shadows() -> void:
	for node in [area.player] + area.find_children("*", "ShipCompanion", true, false):
		if node == null or (node as Node).has_node(^"ContactShadow"):
			continue
		var shadow := ContactShadow.new()
		shadow.name = "ContactShadow"
		shadow.show_behind_parent = true
		(node as Node).add_child(shadow)


## A lightning flash, 0..1 (scaled by the Flash brightness setting).
func flash(amount: float) -> void:
	_flash = maxf(_flash, amount * SettingsManager.get_flash_intensity() / 100.0)


func get_ambient_colour() -> Color:
	return _modulate.color if _modulate else Color.WHITE


## 0 in full daylight .. 1 at night.
func get_darkness() -> float:
	return _darkness


func get_light_count(when := "") -> int:
	var count := 0
	for entry in _lights:
		if when.is_empty() or entry.when == when:
			count += 1
	return count


## The current energy of the lights of a kind (tests).
func get_light_energy(when: String) -> float:
	var total := 0.0
	for entry in _lights:
		if entry.when == when:
			total += (entry.light as PointLight2D).energy
	return total


## Jumps straight to the light of the current hour (after a load, sleep or
## entering the area); otherwise the light follows the clock smoothly.
func update_now() -> void:
	_initialised = false
	_process(0.0)


## How overcast the sky is for a weather sample (0 clear .. 0.8 stormy); also
## used by the cabin windows and the Golden Harbour Moments.
static func overcast_of(weather: WeatherSample) -> float:
	if weather == null:
		return 0.0
	if weather.thunder_active or weather.classification in [WeatherModel.CLASS_THUNDERSTORM, WeatherModel.CLASS_SQUALL,
			WeatherModel.CLASS_STORM, WeatherModel.CLASS_TROPICAL_STORM, WeatherModel.CLASS_HURRICANE]:
		return 0.8
	if weather.classification == WeatherModel.CLASS_GALE or weather.thunder_possible:
		return 0.5
	if weather.classification == WeatherModel.CLASS_STRONG_WIND:
		return 0.25
	return 0.0


func _process(delta: float) -> void:
	if area == null or not GameSession.is_active():
		return
	var now := GameSession.get_game_time()
	var geo := GameSession.get_vessel_position()
	if absf(now - _weather_at) >= WEATHER_REFRESH:
		_weather_at = now
		_overcast = overcast_of(Simulation.get_weather_at_vessel())
	var elevation := Daylight.sun_elevation(geo, now)
	var interior := area.area_id == SessionState.AREA_INTERIOR
	var target := Daylight.inside_colour(elevation, _overcast) if interior else Daylight.outside_colour(elevation, _overcast)
	var darkness_target := clampf(1.0 - Daylight.daylight(elevation) * (1.0 - _overcast * 0.5), 0.0, 1.0)
	var t := 1.0 if not _initialised else 1.0 - exp(-FOLLOW_RATE * delta)
	_initialised = true
	_colour = _colour.lerp(target, t)
	_darkness = lerpf(_darkness, darkness_target, t)
	_flash = maxf(_flash - delta * 3.5, 0.0)
	_modulate.color = _colour.lerp(Color(0.95, 0.97, 1.0), _flash * (0.55 if interior else 0.8))
	var moored := not GameSession.is_underway()
	var anchored := GameSession.is_anchored()
	for entry in _lights:
		var light := entry.light as PointLight2D
		var strength := 0.0
		match entry.when:
			"dark":  # cabin lamps: lit from dusk, and on grey days
				strength = clampf(_darkness * 1.3 - 0.1 + _overcast * 0.4, 0.0, 1.0)
			"night":
				strength = smoothstep(0.45, 0.85, _darkness)
			"day":
				strength = 1.0 - _darkness
			"harbour":
				strength = smoothstep(0.45, 0.85, _darkness) if moored else 0.0
			"underway":
				strength = smoothstep(0.45, 0.85, _darkness) if not moored and not anchored else 0.0
			"anchor":
				strength = smoothstep(0.45, 0.85, _darkness) if anchored else 0.0
		light.energy = float(entry.energy) * strength
		light.visible = light.energy > 0.01
	if _corner_shade:
		_corner_shade.modulate.a = smoothstep(0.35, 0.9, _darkness)
	# Highlights and the captain stay readable in the dark.
	Interactable.light_compensation = Color(1.0 / maxf(_modulate.color.r, 0.3), 1.0 / maxf(_modulate.color.g, 0.3),
		1.0 / maxf(_modulate.color.b, 0.3))
	if _lamps:
		_lamps.self_modulate = Interactable.light_compensation
		_lamps.queue_redraw()


## The lit lamps (navigation and anchor lights), for tests: [{"colour", "at", "when"}].
func get_lit_lamps() -> Array[Dictionary]:
	var lit: Array[Dictionary] = []
	for entry in _lights:
		var light := entry.light as PointLight2D
		if entry.get("lamp", false) and light.visible:
			lit.append({"colour": light.color, "at": light.position, "when": entry.when})
	return lit


## The lamps themselves: a bright dot with a small soft glow at each lit
## navigation or anchor light (drawn above the deck; kept bright against the
## night's tint, like the highlights).
class Lamps extends Node2D:
	var lighting: BoatLighting

	func _draw() -> void:
		for entry in lighting._lights:
			if not entry.get("lamp", false):
				continue
			var light := entry.light as PointLight2D
			if not light.visible:
				continue
			var strength := clampf(light.energy / maxf(float(entry.energy), 0.01), 0.0, 1.0)
			var c := light.color
			draw_circle(light.position, 9.0, Color(c, 0.18 * strength))
			draw_circle(light.position, 5.0, Color(c, 0.45 * strength))
			draw_circle(light.position, 2.6, Color(c.lerp(Color.WHITE, 0.5), strength))


## Soft shadows beside fixtures (see BoatLighting._add_shadows).
class FixtureShadows extends Node2D:
	var outlines: Array[PackedVector2Array] = []

	func _draw() -> void:
		for outline in outlines:
			for layer in 3:
				var offset := Vector2(4.0 + layer * 3.0, 5.0 + layer * 3.5)
				var moved := PackedVector2Array()
				for p in outline:
					moved.append(p + offset)
				for piece in Geometry2D.clip_polygons(moved, outline):
					if Geometry2D.is_polygon_clockwise(piece):
						continue  # a hole, not a shadow
					draw_colored_polygon(piece, Color(SHADOW, 0.17 - layer * 0.05))


## Soft shade along the cabin floor's edges (see BoatLighting._add_corner_shade):
## four bands fading inward from the walls; where two meet, the corner is
## deepest. Clipped to the cabin's outline; each vertex's shade follows its
## distance from the band's wall, so clipping keeps the gradient exact.
class CornerShade extends Node2D:
	const DEPTH := 0.34
	const WIDTH := 120.0
	var bounds := Rect2()
	var clip := PackedVector2Array()

	func _draw() -> void:
		var r := bounds
		var w := minf(WIDTH, minf(r.size.x, r.size.y) * 0.35)
		var outer := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var inner := [r.position + Vector2(w, w), Vector2(r.end.x - w, r.position.y + w), r.end - Vector2(w, w), Vector2(r.position.x + w, r.end.y - w)]
		for i in 4:
			var j := (i + 1) % 4
			var band := PackedVector2Array([outer[i], outer[j], inner[j], inner[i]])
			var pieces: Array[PackedVector2Array] = [band]
			if clip.size() >= 3:
				pieces = Geometry2D.intersect_polygons(band, clip)
			var a: Vector2 = outer[i]
			var b: Vector2 = outer[j]
			for piece in pieces:
				if piece.size() < 3 or Geometry2D.is_polygon_clockwise(piece) != Geometry2D.is_polygon_clockwise(band):
					continue  # a hole
				var colours := PackedColorArray()
				for p in piece:
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment_uncapped(p, a, b))
					colours.append(Color(SHADOW, DEPTH * clampf(1.0 - d / w, 0.0, 1.0)))
				draw_polygon(piece, colours)


## A soft oval under the captain or a companion (drawn behind it).
class ContactShadow extends Node2D:
	func _draw() -> void:
		for i in 3:
			var scale := 1.0 - i * 0.22
			var points := PackedVector2Array()
			for k in 20:
				var a := TAU * k / 20.0
				points.append(Vector2(cos(a) * 15.0 * scale, sin(a) * 9.0 * scale + 6.0))
			draw_colored_polygon(points, Color(SHADOW, 0.12))
