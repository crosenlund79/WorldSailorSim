class_name WaterLife
extends Node2D
## The water around the boat comes alive (0.100b): cosmetic, hand-drawn
## animation over the deck's water, under the boat.
##
## Moored: small ripple rings that open and fade, gentle wavelets and glints
## drifting slowly, lapping along the pontoon, and a few drifting things
## chosen by the harbour's broad atmosphere: an open marina (ripples, the odd
## leaf), a sheltered coastal harbour (seaweed, foam) or a city harbour
## (leaves, now and then a scrap of paper). The atmosphere comes from
## HarbourArt.atmosphere when a harbour sets it, otherwise from the
## catalogue's own fields (island harbours: coastal; major ports: city; others:
## marina). It never claims anything about a particular harbour.
##
## Underway: wave crests oriented by the WeatherModel's wind at the boat
## (seen from the boat: relative to the course), more and livelier as the
## wind rises, white crests from 20 kn, all streaming aft with the boat's
## speed. Calm water stays calm.
##
## Underway, too (Cozy Polish): a pool of small floating things (seaweed,
## driftwood, leaves, foam, kelp, a feather) lies still in the water, so they
## pass the boat from ahead to astern at its own speed (in the deck's own
## coordinates: the bow is +x, and the whole deck turns with the course view),
## drifting a little with the wind. One that falls behind the view comes back
## ahead at a new place, spacing and size, never across the hull's beam.
##
## Presentation only: it reads the game, never changes it. It runs on real
## time with its own fixed random seed, so it moves naturally while the game
## clock is paused (like the sails), and stops with the scene when a menu
## pauses the tree. The number of elements is fixed (at most MAX_WAVES
## crests, MAX_DRIFTERS drifters, MAX_RINGS rings), nothing accumulates.

const ATMOSPHERE_MARINA := &"marina"
const ATMOSPHERE_COASTAL := &"coastal"
const ATMOSPHERE_URBAN := &"urban"
const ATMOSPHERES: Array[StringName] = [ATMOSPHERE_MARINA, ATMOSPHERE_COASTAL, ATMOSPHERE_URBAN]

const MAX_WAVES := 70
const MAX_DRIFTERS := 6
const MAX_RINGS := 8
## Floating things around the boat at sea (a fixed pool, reused).
const SEA_DRIFTERS := 16
const SEA_KINDS: Array[StringName] = [&"seaweed", &"seaweed", &"driftwood", &"leaf", &"foam", &"foam", &"kelp", &"feather"]
## Pixels per second per knot the water passes the boat (as the wave crests).
const FLOW_PX_PER_KN := 9.0
const WAVELETS := 34
## Seconds between two looks at the wind (it changes slowly).
const WIND_REFRESH := 0.5

# Real Horizon: the sea surface itself (SeaSurface) carries the waves; these
# strokes are restrained accents on it, in the natural palette.
const CREST := Color(0.78, 0.85, 0.86, 0.32)
const CREST_DARK := Color(0.07, 0.15, 0.18, 0.22)
const FOAM := Color(0.90, 0.93, 0.92, 0.6)
const GLINT := Color(0.97, 0.98, 0.96, 0.4)
const SEAWEED := Color("#4a5a3c")
const LEAF_COLOURS := [Color("#8a6a45"), Color("#6f5a3c"), Color("#77784a")]
const PAPER := Color("#d6d6cf")
const DRIFTWOOD := Color("#7b7266")
const DRIFTWOOD_GRAIN := Color("#4f4a43")
const FEATHER := Color("#e3e3dc")

var _area: BoatArea
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _wind_timer := 0.0
var _underway := false
## Wind in this deck's coordinates: the direction it blows towards (unit) and
## its strength, plus the boat's speed (knots).
var _wind_dir := Vector2.LEFT
var _wind_kn := 0.0
var _boat_kn := 0.0
var _atmosphere: StringName = ATMOSPHERE_MARINA
var _view := Rect2(-900, -500, 1800, 1000)
var _pontoon := Rect2()
## Elements: arrays of dictionaries made once, updated in place.
var _waves: Array[Dictionary] = []
var _wavelets: Array[Dictionary] = []
var _drifters: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _sea_drifters: Array[Dictionary] = []
## The hull's beam band (local y) that floating things keep out of when they
## come back ahead, so none appears through the boat.
var _beam := Vector2(-120.0, 120.0)
## Points along the hulls' waterline with their outward normal and tangent,
## where the water laps against the boat.
var _laps: Array[Dictionary] = []
## Strokes collected while drawing, per line width, and drawn in one call per
## width at the end (far cheaper than a call per crest).
var _strokes := {}


func setup(area: BoatArea) -> void:
	_area = area
	_rng.seed = 2024
	var pontoon := area.mooring.get_node_or_null(^"Pontoon") as Polygon2D if area.mooring else null
	if pontoon:
		var bounds := Rect2(pontoon.polygon[0], Vector2.ZERO)
		for p in pontoon.polygon:
			bounds = bounds.expand(p)
		_pontoon = bounds
	_collect_laps(area)
	for i in MAX_WAVES:
		_waves.append({"p": _random_point(), "len": _rng.randf_range(10, 26), "phase": _rng.randf() * TAU, "speed": _rng.randf_range(0.7, 1.3)})
	for i in WAVELETS:
		_wavelets.append({"p": _random_point(), "len": _rng.randf_range(8, 20), "phase": _rng.randf() * TAU,
			"drift": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2, 6), "glint": _rng.randf() < 0.3})
	for i in MAX_RINGS:
		_rings.append({"p": _random_point(), "age": _rng.randf_range(0, 4), "life": _rng.randf_range(2.5, 4.5)})
	_measure_beam()
	for i in SEA_DRIFTERS:
		var d := {}
		_respawn_sea_drifter(d, true)
		_sea_drifters.append(d)
	refresh()


func _measure_beam() -> void:
	if _laps.is_empty():
		return
	var lo := INF
	var hi := -INF
	for lap in _laps:
		lo = minf(lo, lap.p.y)
		hi = maxf(hi, lap.p.y)
	_beam = Vector2(lo - 30.0, hi + 30.0)


## Places a floating thing: anywhere in view at first, later ahead of the bow
## (beyond the view, a varied distance on), clear of the hull's beam.
func _respawn_sea_drifter(d: Dictionary, anywhere: bool) -> void:
	var x := _rng.randf_range(_view.position.x, _view.end.x) if anywhere \
		else _view.end.x + _rng.randf_range(10.0, _view.size.x * 0.6)
	var y := _rng.randf_range(_view.position.y, _view.end.y)
	if y > _beam.x and y < _beam.y:
		# Off the beam band: to the nearer side, a little further out.
		y = _beam.x - _rng.randf_range(10.0, 160.0) if y < (_beam.x + _beam.y) / 2.0 else _beam.y + _rng.randf_range(10.0, 160.0)
	d.kind = SEA_KINDS[_rng.randi() % SEA_KINDS.size()]
	d.p = Vector2(x, y)
	d.angle = _rng.randf() * TAU
	d.spin = _rng.randf_range(-0.12, 0.12)
	d.drift = _rng.randf_range(0.4, 1.0)
	d.phase = _rng.randf() * TAU
	d.colour = LEAF_COLOURS[_rng.randi() % LEAF_COLOURS.size()]
	d.size = _rng.randf_range(0.7, 1.4)


func _collect_laps(area: BoatArea) -> void:
	var hulls := area.get_node_or_null(^"Visual/HullBase")
	if hulls == null:
		return
	for child in hulls.get_children():
		var poly := child as Polygon2D
		if poly == null or not (String(poly.name).contains("Hull") or String(poly.name).contains("Ama")) or poly.polygon.size() < 3:
			continue
		var points := PackedVector2Array()
		var center := Vector2.ZERO
		for p in poly.polygon:
			var local := to_local(poly.to_global(p))
			points.append(local)
			center += local
		center /= points.size()
		var carry := 0.0
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var length := a.distance_to(b)
			var d := 55.0 - carry
			while d < length:
				var p := a.lerp(b, d / length)
				var tangent := (b - a).normalized()
				var normal := tangent.orthogonal()
				if normal.dot(p - center) < 0.0:
					normal = -normal
				_laps.append({"p": p, "n": normal, "t": tangent, "phase": _rng.randf() * TAU})
				d += 55.0
			carry = length - (d - 55.0)


func get_lap_count() -> int:
	return _laps.size()


## Follows the Artwork setting, the harbour and whether the boat is underway.
func refresh() -> void:
	visible = SettingsManager.get_art_style() == SettingsManager.ART_ILLUSTRATED
	# The classic static ripple strokes show only with the classic art.
	for sibling in get_parent().get_children():
		if sibling is Line2D and String(sibling.name).begins_with("Ripple"):
			(sibling as CanvasItem).visible = not visible
	_underway = GameSession.is_underway()
	_atmosphere = atmosphere_for(GameSession.get_location_id())
	_make_drifters()
	_read_wind()
	queue_redraw()


func get_atmosphere() -> StringName:
	return _atmosphere


func get_wind_direction() -> Vector2:
	return _wind_dir


func get_wind_kn() -> float:
	return _wind_kn


func is_underway_mode() -> bool:
	return _underway


## How many wave crests are drawn now (more in stronger wind; at sea only).
func get_wave_count() -> int:
	if not _underway:
		return 0
	return clampi(18 + roundi(_wind_kn * 1.6), 18, MAX_WAVES)


func get_drifter_count() -> int:
	return _drifters.size() if not _underway else 0


## Floating things in view at sea (tests).
func get_sea_drifter_count() -> int:
	if not _underway:
		return 0
	var count := 0
	for d in _sea_drifters:
		if _view.has_point(d.p):
			count += 1
	return count


func get_sea_drifters() -> Array[Dictionary]:
	return _sea_drifters


## The broad atmosphere of a harbour: HarbourArt.atmosphere when set,
## otherwise derived from the catalogue (island harbour: coastal; a major
## port: city; anything else: marina). "" (at sea): marina.
static func atmosphere_for(port_id: StringName) -> StringName:
	var art := HarbourArt.for_port(port_id)
	if art and StringName(art.atmosphere) in ATMOSPHERES:
		return StringName(art.atmosphere)
	var port := PortCatalog.get_default().get_port(port_id)
	if port == null:
		return ATMOSPHERE_MARINA
	if port.island:
		return ATMOSPHERE_COASTAL
	if port.importance >= 3:
		return ATMOSPHERE_URBAN
	return ATMOSPHERE_MARINA


func _make_drifters() -> void:
	_drifters.clear()
	var kinds: Array[StringName] = []
	match _atmosphere:
		ATMOSPHERE_COASTAL:
			kinds = [&"seaweed", &"seaweed", &"foam", &"foam", &"leaf"]
		ATMOSPHERE_URBAN:
			kinds = [&"leaf", &"leaf", &"paper", &"foam"]
		_:
			kinds = [&"leaf", &"leaf"]
	for kind in kinds.slice(0, MAX_DRIFTERS):
		_drifters.append({"kind": kind, "p": _random_point(), "angle": _rng.randf() * TAU, "spin": _rng.randf_range(-0.15, 0.15),
			"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(3, 9), "phase": _rng.randf() * TAU,
			"colour": LEAF_COLOURS[_rng.randi() % LEAF_COLOURS.size()], "size": _rng.randf_range(0.8, 1.25)})


func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(_view.position.x, _view.end.x), _rng.randf_range(_view.position.y, _view.end.y))


func _read_wind() -> void:
	if not GameSession.is_active():
		return
	var wind := Simulation.get_weather_at_vessel()
	var heading := _area.get_view_heading() if GameSession.is_underway() else 0.0
	_wind_dir = Vector2.from_angle(deg_to_rad(wind.from_deg + 180.0 - heading))
	_wind_kn = wind.speed_kn
	_boat_kn = GameSession.get_vessel_speed_kn()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = WIND_REFRESH
		var was_underway := _underway
		_underway = GameSession.is_underway()
		if was_underway != _underway:
			refresh()
		_read_wind()
	_update_view()
	if _underway:
		_move_waves(delta)
	else:
		_move_harbour(delta)
	queue_redraw()


## The part of the world on screen (plus a margin), so elements wrap there.
func _update_view() -> void:
	# All four corners: the view may be turned (the course view).
	var to_local := get_global_transform().affine_inverse() * get_viewport().get_canvas_transform().affine_inverse()
	var size := get_viewport_rect().size
	var rect := Rect2(to_local * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(size.x, 0), size, Vector2(0, size.y)]:
		rect = rect.expand(to_local * corner)
	_view = rect.grow(60.0)


func _wrap(p: Vector2) -> Vector2:
	var r := _view
	if p.x < r.position.x:
		p.x += r.size.x
	elif p.x > r.end.x:
		p.x -= r.size.x
	if p.y < r.position.y:
		p.y += r.size.y
	elif p.y > r.end.y:
		p.y -= r.size.y
	return p


func _move_harbour(delta: float) -> void:
	for w in _wavelets:
		w.p = _wrap(w.p + w.drift * delta)
	for d in _drifters:
		d.p = _wrap(d.p + d.vel * delta)
		d.angle += d.spin * delta
	for r in _rings:
		r.age += delta
		if r.age > r.life:
			r.age = 0.0
			r.life = _rng.randf_range(2.5, 4.5)
			r.p = _random_point()


func _move_waves(delta: float) -> void:
	# Crests travel downwind; the boat's own speed streams them aft (-x).
	var flow := _wind_dir * (6.0 + _wind_kn * 1.4) + Vector2.LEFT * _boat_kn * FLOW_PX_PER_KN
	for w in _waves:
		w.p = _wrap(w.p + flow * w.speed * delta)
	# Floating things lie in the water: past the boat at its speed, plus a
	# little drift with the wind. Behind the view: back ahead, somewhere new.
	var pass_by := Vector2.LEFT * _boat_kn * FLOW_PX_PER_KN
	var wind_drift := _wind_dir * minf(_wind_kn, 25.0) * 0.25
	for d in _sea_drifters:
		d.p += (pass_by + wind_drift * d.drift) * delta
		d.angle += d.spin * delta
		if d.p.x < _view.position.x - 40.0:
			_respawn_sea_drifter(d, false)
		elif not Rect2(_view.position - Vector2(80, 80), _view.size + Vector2(_view.size.x + 160, 160)).has_point(d.p):
			# Drifted far off sideways (a turn, a calm, the view changing): back
			# somewhere new, ahead when the boat makes way, else anywhere.
			_respawn_sea_drifter(d, _boat_kn < 0.3)


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	_strokes.clear()
	if _underway:
		_draw_waves()
	else:
		_draw_harbour()
	for width: float in _strokes:
		var batch: Array = _strokes[width]
		draw_multiline_colors(PackedVector2Array(batch[0]), PackedColorArray(batch[1]), width, true)


func _draw_harbour() -> void:
	for lap in _laps:
		var wave := sin(_time * 1.2 + lap.phase)
		var at: Vector2 = lap.p + lap.n * (5.0 + 2.5 * wave)
		_arc(at, 18.0, lap.t, Color(FOAM, 0.22 + 0.18 * wave), 1.6, -0.12)
	for w in _wavelets:
		var a: float = 0.35 + 0.3 * sin(_time * 0.9 + w.phase)
		var c: Color = GLINT if w.glint else CREST
		_arc(w.p, w.len, Vector2.RIGHT, Color(c, c.a * a), 1.6, 0.25 * sin(_time * 0.6 + w.phase))
	for r in _rings:
		var t: float = r.age / r.life
		var radius: float = 4.0 + t * 22.0
		var alpha := (1.0 - t) * 0.6
		_ellipse(r.p, Vector2(radius, radius * 0.45), Color(CREST, alpha), 1.4)
	if _pontoon.size != Vector2.ZERO:
		# Water lapping along the pontoon's boat-side edge.
		var x := _pontoon.position.x + 30.0
		var i := 0
		while x < _pontoon.end.x:
			var lap := sin(_time * 1.3 + i * 0.9)
			_arc(Vector2(x, _pontoon.position.y - 9.0 - lap * 2.0), 16.0, Vector2.RIGHT, Color(FOAM, 0.25 + 0.2 * lap), 1.5, 0.15)
			x += 70.0
			i += 1
	for d in _drifters:
		_draw_drifter(d)


func _draw_drifter(d: Dictionary) -> void:
	var p: Vector2 = d.p
	var bob := sin(_time * 1.1 + d.phase) * 1.2
	var s: float = d.size
	var dir := Vector2.from_angle(d.angle)
	match d.kind:
		&"leaf":
			var pts := PackedVector2Array()
			for k in 12:
				var t := TAU * k / 12.0
				pts.append(p + dir * cos(t) * 7.0 * s + dir.orthogonal() * sin(t) * 3.2 * s * (1.0 - 0.4 * cos(t)) + Vector2(0, bob))
			draw_colored_polygon(pts, d.colour)
			draw_line(p - dir * 7.0 * s + Vector2(0, bob), p + dir * 8.5 * s + Vector2(0, bob), Color(0.25, 0.18, 0.1, 0.8), 1.0, true)
		&"seaweed":
			var strand := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				strand.append(p + dir * (t - 0.5) * 34.0 * s + dir.orthogonal() * sin(t * 6.0 + _time * 0.8 + d.phase) * 3.0)
			draw_polyline(strand, SEAWEED, 3.0 * s, true)
			draw_polyline(strand, SEAWEED.lightened(0.25), 1.0, true)
		&"foam":
			for k in 4:
				var o := Vector2.from_angle(k * 1.7 + d.phase) * (3.0 + k * 2.0) * s
				draw_circle(p + o, (3.5 - k * 0.5) * s, Color(FOAM, 0.35 + 0.1 * sin(_time + k)))
		&"paper":
			var side := dir.orthogonal()
			var quad := PackedVector2Array([p - dir * 5 * s - side * 4 * s, p + dir * 5 * s - side * 3 * s, p + dir * 4 * s + side * 4 * s,
				p - dir * 5 * s + side * 3 * s])
			draw_colored_polygon(quad, Color(PAPER, 0.8))
			draw_line(quad[0], quad[1], Color(0.3, 0.3, 0.3, 0.3), 0.8)
		&"driftwood":
			var side := dir.orthogonal()
			var length := 26.0 * s
			var stick := PackedVector2Array([p - dir * length / 2 - side * 2.4 * s, p + dir * length / 2 - side * 1.6 * s,
				p + dir * length / 2 + side * 1.8 * s, p - dir * length / 2 + side * 2.6 * s])
			for k in stick.size():
				stick[k] += Vector2(0, bob)
			draw_colored_polygon(stick, DRIFTWOOD)
			draw_line(p - dir * length * 0.35 + Vector2(0, bob), p + dir * length * 0.3 + Vector2(0, bob), DRIFTWOOD_GRAIN, 1.0, true)
			draw_line(p + dir * length * 0.1 + Vector2(0, bob), p + dir * length * 0.1 + side * 6.0 * s + Vector2(0, bob), DRIFTWOOD, 1.6, true)
			_arc(p - dir * (length / 2 + 3.0), 10.0 * s, dir.orthogonal(), Color(FOAM, 0.3), 1.2, 0.3)
		&"kelp":
			for k in 3:
				var o := Vector2.from_angle(k * 2.1 + d.phase) * 5.0 * s
				draw_circle(p + o + Vector2(0, bob), 2.6 * s, SEAWEED.darkened(0.15))
			var frond := PackedVector2Array()
			for k in 7:
				var t := k / 6.0
				frond.append(p + dir * t * 22.0 * s + dir.orthogonal() * sin(t * 5.0 + _time + d.phase) * 2.5)
			draw_polyline(frond, SEAWEED, 2.2 * s, true)
		&"feather":
			var side := dir.orthogonal()
			draw_line(p - dir * 7 * s + Vector2(0, bob), p + dir * 7 * s + Vector2(0, bob), Color(0.5, 0.45, 0.4, 0.8), 0.8, true)
			var vane := PackedVector2Array([p - dir * 5 * s, p - dir * 2 * s + side * 3 * s, p + dir * 6 * s + side * 1.2 * s, p + dir * 6.5 * s,
				p + dir * 5 * s - side * 1.5 * s, p - dir * 3 * s - side * 2.5 * s])
			for k in vane.size():
				vane[k] += Vector2(0, bob)
			draw_colored_polygon(vane, Color(FEATHER, 0.9))


func _draw_waves() -> void:
	var count := get_wave_count()
	var across := _wind_dir.orthogonal()
	var energy := clampf(_wind_kn / 30.0, 0.0, 1.4)
	for i in count:
		var w := _waves[i]
		var pulse := 0.5 + 0.5 * sin(_time * (1.0 + energy) * w.speed + w.phase)
		var length: float = w.len * (0.8 + energy * 0.7)
		_arc(w.p, length, across, Color(CREST, (0.1 + 0.18 * pulse) * (0.4 + energy * 0.5)), 1.2 + energy * 0.6, 0.12 + 0.08 * energy)
		_arc(w.p - _wind_dir * 3.0, length * 0.9, across, Color(CREST_DARK, 0.18 * (0.4 + energy * 0.5)), 1.0, 0.1)
		if _wind_kn >= 20.0 and i % 3 == 0:
			draw_circle(w.p + _wind_dir * 1.5, 1.5 + energy * 1.5, Color(FOAM, 0.4 * pulse))
	for d in _sea_drifters:
		if _view.has_point(d.p):
			_draw_drifter(d)


## A small crest: a curved stroke of `length` along `along`, bowed by `bow`.
func _arc(center: Vector2, length: float, along: Vector2, colour: Color, width: float, bow: float) -> void:
	var normal := along.orthogonal()
	var pts := PackedVector2Array()
	for k in 5:
		var t := k / 4.0 - 0.5
		pts.append(center + along * t * length - normal * (0.25 - t * t) * length * bow)
	_stroke(pts, colour, width)


func _ellipse(center: Vector2, radii: Vector2, colour: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 17:
		var t := TAU * k / 16.0
		pts.append(center + Vector2(cos(t) * radii.x, sin(t) * radii.y))
	_stroke(pts, colour, width)


## Queues a polyline (as segments) for the batched draw at the end of _draw().
func _stroke(pts: PackedVector2Array, colour: Color, width: float) -> void:
	var key := snappedf(width, 0.2)
	if not _strokes.has(key):
		_strokes[key] = [[], []]
	var segments: Array = _strokes[key][0]
	var colours: Array = _strokes[key][1]
	for k in pts.size() - 1:
		segments.append(pts[k])
		segments.append(pts[k + 1])
		colours.append(colour)
