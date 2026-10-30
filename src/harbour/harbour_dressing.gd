class_name HarbourDressing
extends Node2D
## The illustrated harbour around a moored boat (Real Horizon): a floating
## guest pontoon (weathered decking, galvanised edge, rubbing strip, shore
## power pedestals), the quay beyond it and the town seen from above, in one
## of four regional archetypes chosen from the harbour's sea area and country
## (ARCHETYPE_*): a Nordic fishing harbour (granite setts, falu-red and ochre
## timber, black and red-tiled roofs), an Atlantic port (granite, slate,
## white and grey render), a Mediterranean waterfront (limestone, stucco,
## terracotta, flat roof terraces, pines) or a tropical harbour (concrete,
## painted corrugated roofs, palms). Marina signage for the services the
## harbour has (the grocery store; the boatyard with repairs; Go Ashore) and
## the harbour's illustration beyond the quay: its own landmarks (HarbourArt)
## or the illustration of its look (HarbourLooks, I021); where neither covers
## the quay, the archetype's generated town.
##
## Art only. BoatArea adds it to the deck's Surroundings/Mooring, so it is
## shown only in port, above the water and below the boat. It reads the
## mooring's existing nodes (Pontoon, *Line, Cleat*, the sign labels) and the
## deck's stations for its positions, so it fits every boat's deck without
## changing any collision, station, spawn point or the mooring itself. While
## the Artwork setting is Classic it hides itself and the original pontoon
## drawing shows instead. A harbour with neither its own art nor a look gets
## the generic harbour, without an illustration.

const INK := Color("#2A3236")
const PLANK := Color("#8A8478")
const PLANK_DARK := Color("#686458")
const STONE := Color("#9A9C97")
const STONE_DARK := Color("#7B7E7A")
const ROPE := Color("#C9C3B2")
const GALVANISED := Color("#9AA3A5")
const RUBBER := Color("#2E3336")
const SIGN_BOARD := Color("#23394A")
const SIGN_TEXT := Color("#EEF2F1")
const LAMP := Color("#3A4044")
const LAMP_GLASS := Color("#E8E2C8")
const SHADOW := Color(0.04, 0.07, 0.09, 0.32)
## Scene units per metre around the moored boat (I025): the decks are drawn
## at about 1 cm per unit (the Starling 33's 10 m hull is 1000 units long and
## 3.4 m wide; the Arctic Wanderer 26's 7.9 m hull 770), so the harbour - its
## houses, quay fittings and the neighbours' boats - is drawn at that scale too.
const METRE := 100.0
## Depth of the quay drawn beyond the pontoon (scene units).
const QUAY_DEPTH := 130.0
## The quay's granite coping along the water (scene units).
const COPING := 32.0
## Where the buildings' fronts stand, beyond the quay edge (scene units); the
## harbour looks' illustrations put their facades on the same line.
const TOWN_FROM := 44.0
## The facade band seen below the eaves in the slightly tilted top-down view.
const LIP := 26.0
## The far side of the basin: the neighbours' boats, their free ends stopping
## this far short of our boat's art canvas (scene units).
const FAR_CLEARANCE := 36.0
## Atmospheric distance: how far the far side of the basin and the town's
## back fade towards the sea haze (lower contrast, less detail).
const FAR_HAZE := 0.1
const HAZE := Color("#CBD3D0")

const ARCHETYPE_NORDIC := &"nordic"
const ARCHETYPE_ATLANTIC := &"atlantic"
const ARCHETYPE_MEDITERRANEAN := &"mediterranean"
const ARCHETYPE_TROPICAL := &"tropical"
const REGION_ARCHETYPES := {
	"scandinavia": ARCHETYPE_NORDIC, "baltic": ARCHETYPE_NORDIC,
	"north_sea": ARCHETYPE_ATLANTIC, "british_isles": ARCHETYPE_ATLANTIC, "channel": ARCHETYPE_ATLANTIC,
	"biscay": ARCHETYPE_ATLANTIC, "iberia_atlantic": ARCHETYPE_ATLANTIC, "north_atlantic": ARCHETYPE_ATLANTIC,
	"mediterranean": ARCHETYPE_MEDITERRANEAN, "adriatic": ARCHETYPE_MEDITERRANEAN, "aegean": ARCHETYPE_MEDITERRANEAN,
	"ionian": ARCHETYPE_MEDITERRANEAN, "levant": ARCHETYPE_MEDITERRANEAN, "atlantic_islands": ARCHETYPE_MEDITERRANEAN,
	"caribbean": ARCHETYPE_TROPICAL, "pacific": ARCHETYPE_TROPICAL, "central_america": ARCHETYPE_TROPICAL,
}
## Country ids (lower case, spaces as underscores), not display text.
const NORDIC_COUNTRIES := ["denmark", "sweden", "norway", "finland", "iceland", "faroe_islands", "estonia", "latvia"]
## Per archetype: quay paving, its joints, facade colours, roof colours, tree
## canopy, roof form ("gable", "barrel", "flat", "metal").
const STYLES := {
	&"nordic": {"paving": Color("#8E918D"), "joint": Color("#6C706D"), "edge": Color("#7D817F"),
		"facades": [Color("#7E3F34"), Color("#B8955A"), Color("#D9D6CB"), Color("#8E6B3F"), Color("#6F2F2A"), Color("#C9B98F")],
		"roofs": [Color("#34383B"), Color("#3F4245"), Color("#7A4A3A"), Color("#2E3134"), Color("#6E4436")],
		"tree": Color("#56654A"), "forms": ["gable", "gable", "gable", "barrel"]},
	&"atlantic": {"paving": Color("#8F918C"), "joint": Color("#70736F"), "edge": Color("#7A7D79"),
		"facades": [Color("#DCDAD2"), Color("#B9BDB8"), Color("#CFC6B0"), Color("#9DA7AB"), Color("#E4E1D8")],
		"roofs": [Color("#4D5459"), Color("#565D62"), Color("#454B50"), Color("#5E6468")],
		"tree": Color("#4E5E47"), "forms": ["gable", "gable", "gable", "flat"]},
	&"mediterranean": {"paving": Color("#C2BAA7"), "joint": Color("#A39A86"), "edge": Color("#B2AA97"),
		"facades": [Color("#E2D9C6"), Color("#D7B98A"), Color("#E6E2D8"), Color("#C99F7C"), Color("#D9C6A3")],
		"roofs": [Color("#A8644A"), Color("#B5704F"), Color("#9A5A43"), Color("#D8D0BF")],
		"tree": Color("#5F6B49"), "forms": ["barrel", "barrel", "flat", "barrel"]},
	&"tropical": {"paving": Color("#A9A9A2"), "joint": Color("#8D8D86"), "edge": Color("#9B9C96"),
		"facades": [Color("#D9D4C4"), Color("#9FB8B0"), Color("#D8B98E"), Color("#C9CFC4")],
		"roofs": [Color("#8C4E44"), Color("#5E7F72"), Color("#9AA2A3"), Color("#4F6F7E")],
		"tree": Color("#4F6A45"), "forms": ["metal", "metal", "gable", "metal"]},
}
## Facilities shown as signs: station id -> [sign text, icon, the label node
## of the classic pontoon drawing whose place the sign takes].
const FACILITIES := {&"grocery": ["Groceries", &"basket", "GrocerySign"],
	&"boatyard": ["Boatyard · Repairs", &"wrench", "BoatyardSign"],
	&"go_ashore": ["Go Ashore", &"compass", "GoAshoreSign"],
	# I026: the walkway up to the quay, where the businesses now stand.
	&"quay": ["To the quay", &"quay", "QuaySign"]}
## Original mooring nodes the illustration replaces while it is shown (the
## sign labels stay: they get the sign's text and the display font).
const REPLACED_PREFIXES := ["Plank", "Cleat"]

var _area: BoatArea
var _mooring: Node2D
var _pontoon := Rect2()
var _lines: Array[PackedVector2Array] = []
var _cleats: Array[Vector2] = []
var _signs: Array[Dictionary] = []
var _landmarks: Array[HarbourLandmark] = []
var _art: HarbourArt
var _font: Font
var _label_settings_classic: LabelSettings
var _label_settings_sign: LabelSettings
var _port_id: StringName = &""
var _archetype: StringName = ARCHETYPE_NORDIC
## The town palette (TOWNS): the harbour's Detailed Cruising Region's look
## (Regions and Harbours 2026), else its archetype. Drawing only: prices and
## opening hours follow the archetype.
var _town_key: StringName = ARCHETYPE_NORDIC
## The classic sign labels' text and settings, to restore under Classic.
var _sign_classic := {}


## Reads the deck's mooring and stations. Call once, after adding to the tree.
func setup(area: BoatArea, mooring: Node2D) -> void:
	_area = area
	_mooring = mooring
	z_index = 0
	var pontoon := mooring.get_node_or_null(^"Pontoon") as Polygon2D
	if pontoon:
		var bounds := Rect2(pontoon.polygon[0], Vector2.ZERO)
		for p in pontoon.polygon:
			bounds = bounds.expand(p)
		_pontoon = bounds
	for child in mooring.get_children():
		if child is Line2D and String(child.name).ends_with("Line"):
			_lines.append((child as Line2D).points)
		elif child is Polygon2D and String(child.name).begins_with("Cleat"):
			var poly := (child as Polygon2D).polygon
			var c := Vector2.ZERO
			for p in poly:
				c += p
			_cleats.append(c / maxf(poly.size(), 1))
	var theme := ThemeDB.get_project_theme()
	_font = theme.get_font(&"font", &"DisplayHeader") if theme else ThemeDB.fallback_font
	var label := area.mooring_label
	if label:
		_label_settings_classic = label.label_settings
		_label_settings_sign = LabelSettings.new()
		_label_settings_sign.font = _font
		_label_settings_sign.font_size = 26
		_label_settings_sign.font_color = SIGN_TEXT
		_label_settings_sign.outline_size = 4
		_label_settings_sign.outline_color = Color(INK, 0.85)
	refresh()


## Follows the Artwork setting and the harbour the boat lies in.
func refresh() -> void:
	var illustrated := SettingsManager.get_art_style() == SettingsManager.ART_ILLUSTRATED
	visible = illustrated
	for child in _mooring.get_children():
		if child == self:
			continue
		for prefix: String in REPLACED_PREFIXES:
			if String(child.name).begins_with(prefix):
				(child as CanvasItem).visible = not illustrated
		if child is Line2D and String(child.name).ends_with("Line"):
			(child as CanvasItem).visible = not illustrated
	if _area.mooring_label:
		_area.mooring_label.label_settings = _label_settings_sign if illustrated else _label_settings_classic
	for facility: Array in FACILITIES.values():
		var sign_label := _mooring.get_node_or_null(NodePath(String(facility[2]))) as Label
		if sign_label == null:
			continue
		if not _sign_classic.has(sign_label.name):
			_sign_classic[sign_label.name] = [sign_label.text, sign_label.label_settings]
		var classic: Array = _sign_classic[sign_label.name]
		sign_label.text = facility[0] if illustrated else classic[0]
		sign_label.label_settings = _sign_text_settings() if illustrated else classic[1]
	_port_id = GameSession.get_location_id()
	_archetype = archetype_for(_port_id)
	_town_key = town_for(_port_id)
	# The harbour's own landmarks, else the illustration of its look (I021).
	_art = HarbourLooks.get_default().art_for(_port_id)
	_landmarks = _art.get_landmarks() if _art else ([] as Array[HarbourLandmark])
	_signs.clear()
	_walkway_x = NAN
	var stations := _area.get_node_or_null(^"Layout/Stations")
	if stations:
		for station: Interactable in stations.get_children():
			if FACILITIES.has(station.interaction_id) and station.enabled:
				var facility: Array = FACILITIES[station.interaction_id]
				var label := _mooring.get_node_or_null(NodePath(String(facility[2]))) as Control
				var at: Vector2
				if station.has_meta(&"sign_at"):  # the shore slot (Iteration 12)
					at = station.get_meta(&"sign_at")
				elif label:
					at = label.position + label.size / 2.0
				else:
					at = Vector2(station.position.x, _pontoon.position.y + 30.0)
				if station.interaction_id == WALKWAY_STATION:
					# I026: the walkway runs up from beside its sign (BoatArea).
					_walkway_x = station.position.x
				_signs.append({"id": station.interaction_id, "at": at, "text": facility[0], "icon": facility[1], "label": label != null})
	_update_sign_highlights()
	queue_redraw()


## The regional archetype of a harbour (ARCHETYPE_*), from its sea area,
## with the Nordic countries' North Sea harbours counted as Nordic.
static func archetype_for(port_id: StringName) -> StringName:
	var port := PortCatalog.get_default().get_port(port_id) if not port_id.is_empty() else null
	if port == null:
		return ARCHETYPE_NORDIC
	if port.country.to_lower().replace(" ", "_") in NORDIC_COUNTRIES:
		return ARCHETYPE_NORDIC
	return REGION_ARCHETYPES.get(port.region, ARCHETYPE_ATLANTIC)


func get_archetype() -> StringName:
	return _archetype


## The town palette of a harbour (TOWNS): its Detailed Cruising Region's look
## when TOWNS has it, else its archetype.
static func town_for(port_id: StringName) -> StringName:
	var look := CruisingRegions.get_default().look_for(port_id)
	return look if TOWNS.has(look) else archetype_for(port_id)


func get_town_key() -> StringName:
	return _town_key


## Each sign board is what its station highlights (Iteration 12).
func _update_sign_highlights() -> void:
	for child in get_children():
		if child is HighlightProvider:
			remove_child(child)
			child.queue_free()
	for sign in _signs:
		add_child(HighlightProvider.create(sign.id, HighlightResolver.rounded_rect(sign_board(sign).grow(5.0), 9.0)))


## The sign's board rectangle (this node's coordinates).
func sign_board(sign: Dictionary) -> Rect2:
	var text_width := _font.get_string_size(String(sign.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var center: Vector2 = sign.at
	return Rect2(center - Vector2(text_width / 2.0 + 38.0, 18), Vector2(text_width + 52.0, 36))


func _sign_text_settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = _font
	settings.font_size = 24
	settings.font_color = SIGN_TEXT
	return settings


## The services shown as signs right now (station ids), for tests.
func get_sign_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for sign in _signs:
		ids.append(sign.id)
	return ids


func get_landmarks() -> Array[HarbourLandmark]:
	return _landmarks


## The quay's lamp posts (this node's coordinates), as _draw_quay places
## them: every third post along the quay edge (Iteration 17: lit at night).
func get_lamp_positions() -> PackedVector2Array:
	var lamps := PackedVector2Array()
	if _pontoon.size == Vector2.ZERO:
		return lamps
	var top := _pontoon.end.y + 6.0
	var bx := _pontoon.position.x + 40.0
	var i := 0
	while bx < _pontoon.end.x:
		if i % 3 == 1:
			lamps.append(Vector2(bx, top + COPING * 0.5))
		bx += 190.0
		i += 1
	return lamps


## Soft walkway lights along the pontoon (this node's coordinates).
func get_pontoon_light_positions() -> PackedVector2Array:
	var spots := PackedVector2Array()
	if _pontoon.size == Vector2.ZERO:
		return spots
	var x := _pontoon.position.x + 120.0
	while x < _pontoon.end.x - 60.0:
		spots.append(Vector2(x, _pontoon.get_center().y))
		x += 320.0
	return spots


func get_quay_anchor() -> Vector2:
	return Vector2(_pontoon.get_center().x, _pontoon.end.y)


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	if _pontoon.size == Vector2.ZERO:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 17 + hash(_port_id)  # the same harbour every frame, its own per port
	_draw_water(rng)
	_draw_far_side(rng)
	_draw_quay(rng)
	_draw_town(rng)
	for landmark in _landmarks:
		_draw_landmark(landmark)
	_draw_pontoon(rng)
	_draw_walkway()
	for line in _lines:
		_draw_rope(line)
	for cleat in _cleats:
		_draw_cleat(cleat)
	for sign in _signs:
		_draw_sign(sign)


func _style() -> Dictionary:
	return STYLES.get(_archetype, STYLES[ARCHETYPE_NORDIC])


func _draw_water(_rng: RandomNumberGenerator) -> void:
	# The water in the pontoon's lee is darker and calmer (SeaSurface draws
	# the rest); a soft shadow band along the pontoon's float.
	var p := _pontoon
	for k in 4:
		var h := 10.0 + k * 9.0
		draw_rect(Rect2(p.position.x - 60.0, p.position.y - h, p.size.x + 120.0, h), Color(0.05, 0.12, 0.14, 0.05))


## Across the fairway (I025, at the boats' real size beside ours): the
## neighbours' boats moored side by side, their free ends towards us and the
## rest running on out of the picture. Nordic, Atlantic and tropical harbours
## moor bow-to with the sterns to the fairway; the Mediterranean moors stern-to
## the quay, bows out. A mix of cruising yachts like ours, larger yachts, small
## sailboats, the odd tender and the region's own working boats (FLEETS),
## slightly hazed as the farther side of the basin. Art only, clear of the
## boat and its stations.
func _draw_far_side(rng: RandomNumberGenerator) -> void:
	var visual := _area.get_node_or_null(^"Visual") as VesselVisual
	var top := visual.canvas.position.y if visual else -_pontoon.position.y
	var near := top - FAR_CLEARANCE
	var left := _pontoon.position.x - 260.0
	var right := _pontoon.end.x + 260.0
	var fleet: Array = FLEETS.get(_archetype, FLEETS[ARCHETYPE_NORDIC])
	var bows_out := _archetype == ARCHETYPE_MEDITERRANEAN
	var x := left - rng.randf_range(60.0, 260.0)
	var previous := &""
	while x < right:
		var kind: StringName = fleet[rng.randi() % fleet.size()]
		if kind == previous and kind != &"yacht":
			kind = &"yacht"
		previous = kind
		var size := boat_size(kind, rng)
		var length := size.x
		var beam := size.y
		var cx := x + beam / 2.0
		var towards := bows_out or (kind == &"catamaran" and rng.randf() < 0.5)
		var end_y := near - rng.randf_range(0.0, 28.0)
		# Drawn bow-up in its own frame (stern at 0, bow +y), then turned.
		if towards:
			_boat_frame(Vector2(cx, end_y - length), 0.0)
		else:
			_boat_frame(Vector2(cx, end_y), PI)
		match kind:
			&"cutter", &"crabber":
				_draw_fishing_boat(kind, length, beam, rng)
			&"snekke", &"gozzo", &"launch":
				_draw_open_boat(kind, length, beam, rng)
			&"catamaran":
				_draw_catamaran(length, beam, rng)
			&"tender":
				_draw_tender(length, beam, rng)
			&"motor_yacht":
				_draw_motor_yacht(length, beam, rng)
			_:
				_draw_sailing_yacht(length, beam, rng, kind == &"small_sail")
		draw_set_transform(Vector2.ZERO)
		x += beam + rng.randf_range(45.0, 110.0)  # fenders between the hulls


## A neighbour's size (length, beam) in scene units, from real boats of its kind.
static func boat_size(kind: StringName, rng: RandomNumberGenerator) -> Vector2:
	var spec: Array = BOAT_SIZES.get(kind, BOAT_SIZES[&"yacht"])
	var length := rng.randf_range(spec[0], spec[1]) * METRE
	return Vector2(length, length * float(spec[2]) * rng.randf_range(0.95, 1.05))


## Per kind: [shortest, longest length in metres, beam / length].
const BOAT_SIZES := {
	&"yacht": [9.5, 12.0, 0.335], &"large_yacht": [13.5, 16.0, 0.3], &"small_sail": [6.2, 7.6, 0.34],
	&"motor_yacht": [14.0, 18.0, 0.29], &"catamaran": [11.5, 13.5, 0.54], &"cutter": [11.0, 14.0, 0.36],
	&"crabber": [9.0, 12.0, 0.37], &"snekke": [5.0, 6.2, 0.36], &"gozzo": [5.5, 7.0, 0.36], &"launch": [7.0, 9.5, 0.25],
	&"tender": [2.6, 3.2, 0.5],
}
## The boats across the fairway, per archetype (drawn at random from the list).
const FLEETS := {
	&"nordic": [&"yacht", &"yacht", &"yacht", &"large_yacht", &"small_sail", &"small_sail", &"snekke", &"cutter", &"tender"],
	&"atlantic": [&"yacht", &"yacht", &"yacht", &"large_yacht", &"small_sail", &"crabber", &"crabber", &"tender"],
	&"mediterranean": [&"yacht", &"yacht", &"yacht", &"large_yacht", &"motor_yacht", &"gozzo", &"gozzo", &"small_sail", &"tender"],
	&"tropical": [&"yacht", &"yacht", &"catamaran", &"catamaran", &"large_yacht", &"launch", &"launch", &"tender"],
}
const HULL_COLOURS := [Color("#D8D9D2"), Color("#D8D9D2"), Color("#D8D9D2"), Color("#D3CDBD"), Color("#2F3E4C"),
	Color("#B9BDBA"), Color("#34483F")]
const CANVAS_COLOURS := [Color("#3F4D57"), Color("#2E4A66"), Color("#C9C3B2"), Color("#4A5A4C"), Color("#3F4D57")]

## The shadow offset in the boat's own frame (down-right on screen whichever way it lies).
var _shadow_local := Vector2(10, 12)


func _boat_frame(origin: Vector2, rotation_angle: float) -> void:
	draw_set_transform(origin, rotation_angle)
	_shadow_local = Vector2(12, 14).rotated(-rotation_angle)


## A colour of the far side, a little towards the haze.
static func _far(c: Color) -> Color:
	return c.lerp(HAZE, FAR_HAZE)


## A hull seen from above in its own frame: stern (transom) at y = 0, bow at
## y = length. `transom` is the stern's width as a share of the beam; the bow
## narrows from `fine` of the length.
static func hull_outline(length: float, beam: float, transom := 0.8, fine := 0.55) -> PackedVector2Array:
	var side := PackedVector2Array()
	for k in 19:
		var t := k / 18.0
		side.append(Vector2(hull_half_width(t, beam, transom, fine), t * length))
		if k == 0:  # the transom's rounded corners
			side.append(Vector2(hull_half_width(0.012, beam, transom, fine), 0.012 * length))
	var pts := PackedVector2Array()
	for k in range(side.size() - 1, -1, -1):
		pts.append(Vector2(-side[k].x, side[k].y))
	for q in side:
		pts.append(q)
	return pts


## The outline drawn smaller towards the centre line (a deck inside the hull).
static func _inset(outline: PackedVector2Array, k: float, length: float, margin: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in outline:
		out.append(Vector2(q.x * k, margin + q.y * (length - 2.0 * margin) / length))
	return out


func _hull_with_shadow(outline: PackedVector2Array, colour: Color) -> void:
	var shadow := PackedVector2Array()
	for q in outline:
		shadow.append(q + _shadow_local)
	draw_colored_polygon(shadow, SHADOW)
	draw_colored_polygon(outline, colour)


func _fenders(length: float, beam: float, at: Array, rng: RandomNumberGenerator) -> void:
	var colour: Color = [Color("#E4E4DE"), Color("#2F4F63"), Color("#E4E4DE"), Color("#D9783A")][rng.randi() % 4]
	for t: float in at:
		for side: float in [-1.0, 1.0]:
			var w := hull_half_width(t, beam)
			draw_rect(Rect2(Vector2(side * (w + 9.0) - 11.0, t * length - 28.0), Vector2(22, 56)), _far(colour))
			draw_rect(Rect2(Vector2(side * (w + 9.0) - 11.0, t * length - 28.0), Vector2(7, 56)), _far(colour.lightened(0.2)))


static func hull_half_width(t: float, beam: float, transom := 0.8, fine := 0.55) -> float:
	var w := lerpf(transom, 1.0, smoothstep(0.0, 0.4, t)) * (0.9 + 0.1 * smoothstep(0.0, 0.03, t))
	if t > fine:
		var f := (t - fine) / (1.0 - fine)
		w *= sqrt(maxf(1.0 - f * f, 0.0))
	return w * beam / 2.0


## A sailing yacht (stern at 0, bow +y): bathing platform and pushpit, a
## teak-seated cockpit with the wheel (a tiller and an outboard on a small
## one), sprayhood, coachroof with hatches, mast and the boom under its sail
## cover, stanchions and lifelines, pulpit, anchor and furler at the bow.
func _draw_sailing_yacht(length: float, beam: float, rng: RandomNumberGenerator, small: bool) -> void:
	var half := beam / 2.0
	var hull: Color = HULL_COLOURS[rng.randi() % HULL_COLOURS.size()] if not small else MarinePalette.FIBREGLASS
	var outline := hull_outline(length, beam, 0.62 if small else 0.8)
	_hull_with_shadow(outline, _far(hull))
	draw_colored_polygon(_inset(outline, 0.9, length, 14.0), _far(MarinePalette.NON_SKID))
	draw_polyline(outline, _far(hull.lightened(0.18)), 3.0, true)  # the toe rail catching the light
	var transom_w := hull_half_width(0.0, beam, 0.62 if small else 0.8)
	draw_rect(Rect2(-transom_w, -10, transom_w * 2.0, 10), _far(hull.darkened(0.22)))  # the transom's face
	var ck := Rect2(-half * 0.6, length * 0.045, beam * 0.6, length * (0.25 if not small else 0.22))
	draw_rect(Rect2(ck.position + Vector2(4, 4), ck.size), Color(0, 0, 0, 0.12))
	draw_rect(ck, _far(MarinePalette.TEAK_DARK))
	for sx: float in [ck.position.x, ck.end.x - beam * 0.12]:  # the cockpit seats
		draw_rect(Rect2(sx, ck.position.y, beam * 0.12, ck.size.y), _far(MarinePalette.TEAK))
		var sy := ck.position.y + 14.0
		while sy < ck.end.y:
			draw_line(Vector2(sx, sy), Vector2(sx + beam * 0.12, sy), _far(MarinePalette.TEAK_DARK), 1.5)
			sy += 14.0
	if small:
		draw_line(Vector2(0, length * 0.1), Vector2(beam * 0.08, length * 0.2), _far(MarinePalette.MARINE_TIMBER), 7.0, true)  # tiller
		_outboard(Vector2(beam * 0.2, 0))  # on its bracket
	else:
		draw_rect(Rect2(-half * 0.42, 0, beam * 0.42, 30), _far(MarinePalette.TEAK))  # bathing platform
		for lx: float in [half * 0.2, half * 0.32]:  # the swim ladder
			draw_line(Vector2(lx, -14), Vector2(lx, 26), _far(MarinePalette.STEEL_LIGHT), 3.0)
		draw_rect(Rect2(-beam * 0.15, length * 0.09 - 4, beam * 0.3, 8), _far(MarinePalette.BRUSHED_STEEL))  # the wheel, edge-on
		draw_rect(Rect2(-14, length * 0.11, 28, 34), _far(MarinePalette.STEEL_LIGHT))  # binnacle
	var pushpit := PackedVector2Array([Vector2(-half * 0.72, 46), Vector2(-half * 0.74, 14), Vector2(half * 0.74, 14), Vector2(half * 0.72, 46)])
	draw_polyline(pushpit, _far(MarinePalette.BRUSHED_STEEL), 3.0, true)
	# Coachroof, sprayhood and hatches.
	var roof_y := ck.end.y + 10.0
	var roof_len := length * (0.3 if small else 0.33)
	var roof := PackedVector2Array([Vector2(-half * 0.62, roof_y), Vector2(half * 0.62, roof_y),
		Vector2(half * 0.54, roof_y + roof_len), Vector2(-half * 0.54, roof_y + roof_len)])
	var roof_shadow := PackedVector2Array()
	for q in roof:
		roof_shadow.append(q + _shadow_local * 0.6)
	draw_colored_polygon(roof_shadow, Color(0, 0, 0, 0.14))
	draw_colored_polygon(roof, _far(MarinePalette.FIBREGLASS.lightened(0.04)))
	draw_polyline(roof + PackedVector2Array([roof[0]]), _far(Color(INK, 0.35)), 1.2, true)
	if not small and rng.randf() < 0.75:
		var hood: Color = CANVAS_COLOURS[rng.randi() % CANVAS_COLOURS.size()]
		draw_rect(Rect2(-half * 0.64, roof_y - 12.0, beam * 0.64, length * 0.06), _far(hood))
	for hy: float in [roof_y + roof_len * 0.45, roof_y + roof_len * 0.8]:
		draw_rect(Rect2(-26, hy - 24, 52, 48), _far(Color("#33424A")))
	# Mast, boom and sail cover.
	var mast := Vector2(0, roof_y + roof_len + length * 0.03)
	var cover: Color = CANVAS_COLOURS[rng.randi() % CANVAS_COLOURS.size()]
	draw_line(Vector2(0, ck.end.y - length * 0.04), mast, _far(cover), 32.0)
	draw_line(Vector2(-16, ck.end.y - length * 0.04), Vector2(-16, mast.y), _far(cover.lightened(0.15)), 4.0)
	draw_circle(mast + Vector2(4, 4), 13.0, Color(0, 0, 0, 0.18))
	draw_circle(mast, 11.0, _far(MarinePalette.STEEL_LIGHT))
	# Stanchions and lifelines, the pulpit, anchor and furler at the bow.
	for side: float in [-1.0, 1.0]:
		var line := PackedVector2Array()
		var t := 0.06
		while t < 0.9:
			var q := Vector2(side * (hull_half_width(t, beam, 0.8) - 12.0), t * length)
			line.append(q)
			draw_circle(q, 4.0, _far(MarinePalette.BRUSHED_STEEL))
			t += 2.1 * METRE / length
		draw_polyline(line, _far(Color(MarinePalette.STEEL_LIGHT, 0.8)), 1.6, true)
	var bow := Vector2(0, length)
	draw_polyline(PackedVector2Array([bow + Vector2(-beam * 0.16, -length * 0.1), bow + Vector2(0, -30), bow + Vector2(beam * 0.16, -length * 0.1)]),
		_far(MarinePalette.BRUSHED_STEEL), 3.0, true)
	draw_rect(Rect2(bow + Vector2(-6, -46), Vector2(12, 22)), _far(Color("#5A6064")))  # anchor on its roller
	draw_circle(bow + Vector2(0, -58), 6.0, _far(MarinePalette.BRUSHED_STEEL))  # furler drum
	_fenders(length, beam, [0.22, 0.48], rng)


## A motor yacht (stern at 0, bow +y): bathing platform, an aft deck with its
## sofa, the saloon's dark glass and the flybridge under a bimini, a sun pad
## on the foredeck.
func _draw_motor_yacht(length: float, beam: float, rng: RandomNumberGenerator) -> void:
	var half := beam / 2.0
	var outline := hull_outline(length, beam, 0.92, 0.6)
	_hull_with_shadow(outline, _far(MarinePalette.FIBREGLASS))
	draw_colored_polygon(_inset(outline, 0.92, length, 12.0), _far(MarinePalette.FIBREGLASS.lightened(0.05)))
	draw_rect(Rect2(-half * 0.9, 0, beam * 0.9, 60), _far(MarinePalette.TEAK))
	draw_rect(Rect2(-half * 0.84, 60, beam * 0.84, length * 0.2), _far(MarinePalette.TEAK))
	draw_rect(Rect2(-half * 0.7, 80, beam * 0.7, 70), _far(Color("#D9D3C2")))  # the aft sofa
	var house := Rect2(-half * 0.8, length * 0.24, beam * 0.8, length * 0.42)
	draw_rect(Rect2(house.position + _shadow_local, house.size), SHADOW)
	draw_rect(house, _far(MarinePalette.FIBREGLASS.lightened(0.06)))
	draw_rect(Rect2(house.position, Vector2(house.size.x, 22)), _far(Color("#2A353C")))  # the saloon's glass doors
	var fly := Rect2(-half * 0.66, length * 0.3, beam * 0.66, length * 0.24)
	draw_rect(Rect2(fly.position + _shadow_local * 0.7, fly.size), Color(0, 0, 0, 0.16))
	draw_rect(fly, _far(Color("#B9BAB3") if rng.randf() < 0.5 else MarinePalette.CANVAS_SPRAYHOOD))  # bimini
	draw_rect(Rect2(-half * 0.6, length * 0.66, beam * 0.6, 26), _far(Color("#2A353C")))  # windscreen
	draw_rect(Rect2(-half * 0.5, length * 0.74, beam * 0.5, length * 0.1), _far(Color("#D9D3C2")))  # sun pad
	draw_rect(Rect2(Vector2(-9, length - 70), Vector2(18, 34)), _far(Color("#4A5054")))
	draw_polyline(outline, _far(MarinePalette.STEEL_LIGHT), 2.4, true)
	_fenders(length, beam, [0.2, 0.45], rng)


## A catamaran (stern at 0, bows +y): two hulls, the bridgedeck saloon with
## its cockpit aft, the trampoline between the bows, the mast on the front beam.
func _draw_catamaran(length: float, beam: float, rng: RandomNumberGenerator) -> void:
	var hull_w := beam * 0.24
	for side: float in [-1.0, 1.0]:
		var one := hull_outline(length, hull_w, 0.85, 0.6)
		var placed := PackedVector2Array()
		for q in one:
			placed.append(q + Vector2(side * (beam - hull_w) / 2.0, 0))
		_hull_with_shadow(placed, _far(MarinePalette.FIBREGLASS))
		draw_rect(Rect2(side * (beam - hull_w) / 2.0 - hull_w * 0.35, 0, hull_w * 0.7, 54), _far(MarinePalette.TEAK))  # stern steps
	var deck := Rect2(-beam * 0.5 + hull_w * 0.3, length * 0.08, beam - hull_w * 0.6, length * 0.56)
	draw_rect(Rect2(deck.position + _shadow_local, deck.size), SHADOW)
	draw_rect(deck, _far(MarinePalette.NON_SKID))
	draw_rect(Rect2(deck.position.x + 20, deck.position.y, deck.size.x - 40, length * 0.16), _far(MarinePalette.TEAK))  # cockpit
	var saloon := Rect2(-beam * 0.32, length * 0.25, beam * 0.64, length * 0.3)
	draw_rect(Rect2(saloon.position + _shadow_local * 0.6, saloon.size), Color(0, 0, 0, 0.16))
	draw_rect(saloon, _far(MarinePalette.FIBREGLASS.lightened(0.05)))
	draw_rect(Rect2(saloon.position.x, saloon.end.y - 26, saloon.size.x, 26), _far(Color("#2A353C")))
	var net := Rect2(-beam * 0.5 + hull_w, deck.end.y, beam - hull_w * 2.0, length * 0.28)
	draw_rect(net, _far(Color("#2F3A40")))
	var gx := net.position.x
	while gx < net.end.x:
		draw_line(Vector2(gx, net.position.y), Vector2(gx, net.end.y), _far(Color("#4A575E")), 1.0)
		gx += 18.0
	draw_circle(Vector2(0, deck.end.y), 12.0, _far(MarinePalette.STEEL_LIGHT))
	_fenders(length, beam, [0.25], rng)


## A working boat (stern at 0, bow +y): painted hull with a pale bulwark
## rail, a steel deck, the wheelhouse forward of the working deck and, aft, a
## net drum and fish boxes (the Nordic cutter) or stacked creels and buoys
## (the Atlantic crabber).
func _draw_fishing_boat(kind: StringName, length: float, beam: float, rng: RandomNumberGenerator) -> void:
	var colours := [Color("#7E3F34"), Color("#2F4F63"), Color("#3E5A4A")] if kind == &"cutter" else [Color("#34556E"), Color("#3E5A4A"), Color("#5A3A34")]
	var hull: Color = colours[rng.randi() % colours.size()]
	var outline := hull_outline(length, beam, 0.82, 0.5)
	_hull_with_shadow(outline, _far(hull))
	var deck := _inset(outline, 0.86, length, 18.0)
	draw_colored_polygon(deck, _far(Color("#6F7472")))
	draw_polyline(_inset(outline, 0.93, length, 8.0), _far(Color("#D9D6CB")), 9.0, true)  # bulwark rail
	var house := Rect2(-beam * 0.32, length * 0.48, beam * 0.64, length * 0.2)
	draw_rect(Rect2(house.position + _shadow_local, house.size), SHADOW)
	draw_rect(house, _far(Color("#E3E4DE")))
	draw_rect(Rect2(house.position.x + 8, house.position.y + 6, house.size.x - 16, 24), _far(Color("#2A3A42")))
	draw_circle(house.get_center() + Vector2(0, 20), 14.0, _far(Color("#D9783A")))  # the radar's housing
	if kind == &"cutter":
		var drum := Rect2(-beam * 0.3, 70, beam * 0.6, 120)
		draw_rect(drum, _far(Color("#3F5A4E")))
		for k in 6:
			draw_circle(Vector2(drum.position.x + 20 + k * (drum.size.x - 40) / 5.0, drum.get_center().y), 9.0, _far(Color("#D9783A")))
		for k in 3:
			draw_rect(Rect2(beam * (-0.3 + k * 0.2), 230, beam * 0.17, 60), _far([Color("#5A7F9A"), Color("#D9D6CB"), Color("#5A7F9A")][k]))
	else:
		for k in 8:
			var at := Vector2(beam * rng.randf_range(-0.3, 0.2), rng.randf_range(60, length * 0.4))
			draw_rect(Rect2(at + Vector2(4, 4), Vector2(70, 52)), Color(0, 0, 0, 0.15))
			draw_rect(Rect2(at, Vector2(70, 52)), _far(Color("#2E3336")))
			draw_rect(Rect2(at + Vector2(6, 6), Vector2(58, 40)), _far(Color("#4A5458")))
		for k in 3:
			draw_circle(Vector2(beam * 0.3, 90 + k * 40), 15.0, _far(Color("#D9783A")))
	draw_line(Vector2(-beam * 0.36, 30), Vector2(beam * 0.36, 30), _far(Color("#4A5054")), 8.0)  # the stern gallows
	draw_polyline(outline, _far(Color(INK, 0.5)), 1.4, true)
	_fenders(length, beam, [0.3], rng)


## A small open boat (stern at 0, bow +y): a clinker Nordic snekke with its
## engine box, a Mediterranean gozzo with the blue sheer and its little
## canopy, or a brightly painted tropical launch with an outboard.
func _draw_open_boat(kind: StringName, length: float, beam: float, rng: RandomNumberGenerator) -> void:
	var transom := 0.12 if kind == &"snekke" else (0.2 if kind == &"gozzo" else 0.5)
	var outline := hull_outline(length, beam, transom, 0.5)
	var hull := Color("#E3E2DA")
	var inside := MarinePalette.TEAK
	var band := Color("#4A7A9A")
	match kind:
		&"snekke":
			hull = [Color("#E3E2DA"), Color("#3E5A4A"), Color("#8A6E50")][rng.randi() % 3]
			inside = Color("#9A8468")
		&"launch":
			hull = [Color("#3F6F8C"), Color("#D9C27A"), Color("#4E7D6A")][rng.randi() % 3]
			inside = Color("#8C7A60")
			band = Color("#B5523F")
	_hull_with_shadow(outline, _far(hull))
	draw_polyline(_inset(outline, 0.93, length, 6.0), _far(band if kind != &"snekke" else hull.darkened(0.25)), 7.0, true)
	var inner := _inset(outline, 0.82, length, 22.0)
	draw_colored_polygon(inner, _far(inside))
	if kind == &"snekke":  # the clinker strakes, seen inside
		for k in 3:
			draw_polyline(_inset(outline, 0.72 - k * 0.14, length, 30.0 + k * 10.0), _far(Color(inside.darkened(0.25), 0.6)), 1.4, true)
		draw_rect(Rect2(-beam * 0.18, length * 0.25, beam * 0.36, length * 0.16), _far(Color("#5C6A62")))  # engine box
	for t: float in [0.3, 0.55, 0.75]:
		var w := hull_half_width(t, beam, transom, 0.5) * 0.8
		draw_rect(Rect2(-w, t * length - 9.0, w * 2.0, 18.0), _far(MarinePalette.TEAK.lightened(0.1)))  # thwarts
	if kind == &"gozzo" and rng.randf() < 0.7:
		draw_rect(Rect2(-beam * 0.36, length * 0.08, beam * 0.72, length * 0.2), _far(Color("#E8E4D8")))  # the canopy
	if kind == &"launch":
		_outboard(Vector2.ZERO)
	draw_polyline(outline, _far(Color(INK, 0.45)), 1.2, true)


## An outboard motor's cowling seen from above, on the transom at `at`.
func _outboard(at: Vector2) -> void:
	var cowl := Rect2(at + Vector2(-13, -22), Vector2(26, 34))
	draw_rect(Rect2(cowl.position + _shadow_local * 0.5, cowl.size), Color(0, 0, 0, 0.2))
	draw_rect(cowl, _far(Color("#3A4044")))
	draw_rect(Rect2(cowl.position + Vector2(4, 4), Vector2(8, cowl.size.y - 8)), _far(Color("#5A6064")))


## A tender (stern at 0, bow +y): grey inflatable tubes, a floor and an outboard.
func _draw_tender(length: float, beam: float, _rng: RandomNumberGenerator) -> void:
	var outline := hull_outline(length, beam, 0.9, 0.55)
	_hull_with_shadow(outline, _far(Color("#8A9295")))
	draw_colored_polygon(_inset(outline, 0.55, length, 30.0), _far(Color("#B9BDBA")))
	_outboard(Vector2(0, 8))
	draw_polyline(outline, _far(Color(INK, 0.45)), 1.2, true)


func _draw_quay(rng: RandomNumberGenerator) -> void:
	var style := _style()
	var top := _pontoon.end.y + 6.0
	var quay := Rect2(_pontoon.position.x - 260.0, top, _pontoon.size.x + 520.0, QUAY_DEPTH + 220.0)
	draw_rect(Rect2(quay.position + Vector2(0, -6), Vector2(quay.size.x, 6)), Color(0.06, 0.12, 0.14, 0.95))  # gap of water
	var paving: Color = style.paving
	var joint: Color = style.joint
	draw_rect(quay, paving)
	# Granite coping along the edge (blocks of 1-1.7 m), then setts or slabs.
	var x := quay.position.x
	while x < quay.end.x:
		var w := rng.randf_range(100, 170)
		var block := Rect2(x, top, minf(w, quay.end.x - x), COPING)
		draw_rect(block, (style.edge as Color).lerp(joint, rng.randf_range(0.0, 0.3)))
		draw_line(block.position, Vector2(block.position.x, block.end.y), Color(joint.darkened(0.3), 0.8), 1.4)
		x += w
	draw_rect(Rect2(quay.position.x, top, quay.size.x, 3), Color(1, 1, 1, 0.08))  # the arris catches the light
	draw_line(Vector2(quay.position.x, top + COPING), Vector2(quay.end.x, top + COPING), Color(joint.darkened(0.25), 0.7), 1.4)
	var y := top + COPING + 2.0
	var slab := Vector2(26, 13) if _archetype in [ARCHETYPE_NORDIC, ARCHETYPE_ATLANTIC] else Vector2(60, 40)
	var row := 0
	while y < top + TOWN_FROM + 60.0:
		x = quay.position.x + (slab.x * 0.5 if row % 2 else 0.0)
		while x < quay.end.x:
			draw_rect(Rect2(Vector2(x, y), slab - Vector2(2, 2)), paving.lerp(joint, rng.randf_range(0.0, 0.22)))
			x += slab.x
		y += slab.y
		row += 1
	draw_rect(Rect2(quay.position.x, top + COPING, quay.size.x, 4), Color(0, 0, 0, 0.08))
	# Bollards, lamp posts, ladders and life rings along the quay, at their real size.
	var bx := _pontoon.position.x + 40.0
	var i := 0
	while bx < _pontoon.end.x:
		var at := Vector2(bx, top + COPING * 0.5)
		if i % 3 == 1:
			_draw_lamp_post(at)
		elif i % 6 == 4:
			_draw_life_ring(at)
		else:
			draw_circle(at + Vector2(5, 6), 14.0, SHADOW)  # a cast-iron bollard, about 30 cm across
			draw_circle(at, 14.0, Color("#3E464B"))
			draw_circle(at, 9.0, Color("#4C555A"))
			draw_circle(at + Vector2(-3, -3), 4.0, Color("#6E777B"))
		if i % 4 == 2:  # a steel ladder down to the water
			var lx := bx + 60.0
			draw_rect(Rect2(lx, top - 6, 44, 14), Color(0, 0, 0, 0.25))
			for rx: float in [lx, lx + 40.0]:
				draw_rect(Rect2(rx, top - 8, 5, 24), GALVANISED)
			draw_line(Vector2(lx, top - 2), Vector2(lx + 44, top - 2), GALVANISED.darkened(0.2), 3.0)
		bx += 190.0
		i += 1


func _draw_lamp_post(at: Vector2) -> void:
	# Seen from above: the post's foot, a short arm and the lantern head.
	draw_circle(at + Vector2(6, 8), 16.0, SHADOW)
	draw_circle(at, 9.0, LAMP)
	draw_line(at, at + Vector2(0, -18), LAMP, 5.0, true)
	var head := Rect2(at + Vector2(-17, -34), Vector2(34, 22))
	draw_rect(Rect2(head.position + Vector2(6, 8), head.size), SHADOW)
	draw_rect(head, LAMP)
	draw_rect(head.grow(-4.0), LAMP_GLASS)


func _draw_life_ring(at: Vector2) -> void:
	# A 75 cm life ring on its post.
	draw_circle(at + Vector2(6, 8), 32.0, SHADOW)
	draw_rect(Rect2(at + Vector2(-5, -10), Vector2(10, 20)), Color("#4A5054"))
	draw_arc(at, 26.0, 0, TAU, 40, Color("#D9783A"), 11.0, true)
	for k in 4:
		var a := k * PI / 2.0 + PI / 4.0
		draw_line(at + Vector2.from_angle(a) * 20.5, at + Vector2.from_angle(a) * 31.5, Color("#E8E6DF"), 8.0)
	draw_arc(at, 26.0, PI, PI * 1.5, 12, Color(1, 1, 1, 0.25), 3.0, true)


## The town beyond the quay at its real size (I025): waterfront houses of
## 5-9.5 m frontage and 8-12 m depth, boat sheds and warehouses, lanes between
## them and the odd tree, in the archetype's own building types (TOWNS):
## timber houses and gable-end boat sheds in the Nordic harbour, granite
## terraces with slate roofs and chimney stacks on the Atlantic, rendered
## houses with shutters, pantiles and roof terraces in the Mediterranean, low
## houses with verandas under painted tin among palms in the tropics. Only the
## front few metres show in play; the back of the town fades a little towards
## the haze. Where a harbour has its own illustration (or a look), the row is
## laid out from that picture's ends outwards, so no house is cut by it.
func _draw_town(rng: RandomNumberGenerator) -> void:
	var y0 := _pontoon.end.y + 6.0 + TOWN_FROM
	var left := _pontoon.position.x - 260.0
	var right := _pontoon.end.x + 260.0
	var skip := Rect2()
	for landmark in _landmarks:
		var size := landmark.texture.get_size()
		var drawn := Vector2(landmark.width, size.y * landmark.width / maxf(size.x, 1.0))
		var area := Rect2(get_quay_anchor() + landmark.offset - drawn / 2.0, drawn)
		skip = skip.merge(area) if skip.has_area() else area
	# The gutter along the house fronts.
	draw_rect(Rect2(left, y0 - 8.0, right - left, 8.0), (_style().paving as Color).darkened(0.16))
	if skip.has_area():
		_draw_row(rng, y0, skip.end.x - 4.0, right, 1.0)
		_draw_row(rng, y0, skip.position.x + 4.0, left, -1.0)
	else:
		_draw_row(rng, y0, left - rng.randf_range(0.0, 400.0), right, 1.0)
	# Atmospheric distance: the back of the town a little hazier.
	var back := y0 + 300.0
	for k in 4:
		draw_rect(Rect2(left, back + k * 120.0, right - left, 900.0), Color(HAZE, FAR_HAZE * 0.5))


## One run of buildings from `from` towards `to` (direction +1 or -1).
func _draw_row(rng: RandomNumberGenerator, y0: float, from: float, to: float, direction: float) -> void:
	var town: Dictionary = TOWNS.get(_town_key, TOWNS[ARCHETYPE_NORDIC])
	var x := from
	var guard := 0
	while (to - x) * direction > 0.0 and guard < 40:
		guard += 1
		var kind: Dictionary = (town.kinds as Array)[rng.randi() % (town.kinds as Array).size()]
		var w := rng.randf_range(kind.w[0], kind.w[1])
		var lane := rng.randf_range(town.lane[0], town.lane[1]) if rng.randf() < float(town.lane_chance) else 0.0
		var x0 := x if direction > 0.0 else x - w
		var rect := Rect2(x0, y0 + rng.randf_range(0.0, float(town.setback)), w, rng.randf_range(kind.d[0], kind.d[1]))
		_draw_building(rect, kind, town, rng)
		x += (w + lane) * direction
		if lane >= 200.0 and rng.randf() < float(town.tree_chance):  # a tree in the lane or the yard behind
			var r := rng.randf_range(town.tree_r[0], town.tree_r[1])
			var tx := (x - lane * 0.5 * direction)
			_draw_tree(Vector2(tx, y0 + r - 20.0 + rng.randf_range(0.0, 60.0)), r, town.tree, rng)


## Building types per archetype: frontage `w` and depth `d` (scene units),
## roof form ("ridge" along the quay, "gable" end-on, "hip", "flat"), roof
## material ("tile", "slate", "shingle", "pantile", "tin"), window pitch,
## and the town's lanes, set-backs, trees and colours.
const TOWNS := {
	&"nordic": {"kinds": [
			{"w": [600.0, 900.0], "d": [800.0, 1100.0], "form": "ridge", "roofs": "nordic", "pitch": 240.0, "dormer": 0.5, "chimney": 0.6},
			{"w": [460.0, 640.0], "d": [900.0, 1300.0], "form": "gable", "roofs": "nordic", "pitch": 0.0, "door": true},
			{"w": [600.0, 820.0], "d": [800.0, 1000.0], "form": "ridge", "roofs": "nordic", "pitch": 230.0, "chimney": 0.5}],
		"facades": [Color("#7E3F34"), Color("#B8955A"), Color("#D9D6CB"), Color("#6F2F2A"), Color("#C9B98F"), Color("#E0DCCF")],
		"roofs": {"nordic": [[Color("#34383B"), "tile"], [Color("#3F4245"), "shingle"], [Color("#7A4A3A"), "tile"], [Color("#2E3134"), "tile"]]},
		"frame": Color("#ECEAE2"), "shutter": null, "lane": [60.0, 280.0], "lane_chance": 0.7, "setback": 30.0,
		"tree": Color("#5E6E4E"), "tree_r": [180.0, 260.0], "tree_chance": 0.5},
	# Regional looks (Regions and Harbours 2026): Danish colour-washed houses
	# (ochre, white, pale rose, red brick) under red tile and the odd dark
	# thatch; Swedish falu-red and white timber with gable-end boathouses on the
	# water; New Zealand painted weatherboard villas and baches with verandas
	# under corrugated iron, among pōhutukawa.
	&"danish": {"kinds": [
			{"w": [560.0, 860.0], "d": [800.0, 1050.0], "form": "ridge", "roofs": "danish", "pitch": 230.0, "dormer": 0.35, "chimney": 0.7},
			{"w": [520.0, 760.0], "d": [800.0, 1000.0], "form": "ridge", "roofs": "danish", "pitch": 220.0, "chimney": 0.6},
			{"w": [460.0, 620.0], "d": [900.0, 1200.0], "form": "gable", "roofs": "danish", "pitch": 0.0, "door": true}],
		"facades": [Color("#D9B862"), Color("#ECE7DA"), Color("#D8B1A2"), Color("#A9563F"), Color("#E3CF96"), Color("#E9E3D3")],
		"roofs": {"danish": [[Color("#9C4A36"), "tile"], [Color("#A9543C"), "tile"], [Color("#5B5148"), "shingle"], [Color("#3A3C3E"), "tile"]]},
		"frame": Color("#F0EEE6"), "shutter": null, "lane": [60.0, 260.0], "lane_chance": 0.6, "setback": 20.0,
		"tree": Color("#61714F"), "tree_r": [180.0, 250.0], "tree_chance": 0.45},
	&"swedish": {"kinds": [
			{"w": [440.0, 600.0], "d": [900.0, 1300.0], "form": "gable", "roofs": "swedish", "pitch": 0.0, "door": true},
			{"w": [560.0, 820.0], "d": [800.0, 1050.0], "form": "ridge", "roofs": "swedish", "pitch": 240.0, "chimney": 0.5},
			{"w": [440.0, 600.0], "d": [900.0, 1200.0], "form": "gable", "roofs": "swedish", "pitch": 0.0, "door": true}],
		"facades": [Color("#8A3B2E"), Color("#7E3429"), Color("#E6E2D6"), Color("#D2B36A"), Color("#93412F"), Color("#E9E5DA")],
		"roofs": {"swedish": [[Color("#2F3234"), "tile"], [Color("#3B3E40"), "shingle"], [Color("#7A4537"), "tile"]]},
		"frame": Color("#F1EFE8"), "shutter": null, "lane": [80.0, 320.0], "lane_chance": 0.75, "setback": 40.0,
		"tree": Color("#4F6447"), "tree_r": [170.0, 240.0], "tree_chance": 0.55},
	&"new_zealand": {"kinds": [
			{"w": [620.0, 880.0], "d": [700.0, 1000.0], "form": "hip", "roofs": "iron", "pitch": 260.0, "veranda": true},
			{"w": [520.0, 760.0], "d": [700.0, 950.0], "form": "ridge", "roofs": "iron", "pitch": 250.0, "veranda": true},
			{"w": [480.0, 640.0], "d": [700.0, 900.0], "form": "gable", "roofs": "iron", "pitch": 0.0, "door": true}],
		"facades": [Color("#E8E4D8"), Color("#C9D3CF"), Color("#E2D6B4"), Color("#AEBFB4"), Color("#EEEBE2"), Color("#C7C1B2")],
		"roofs": {"iron": [[Color("#8E3F36"), "tin"], [Color("#4E6B57"), "tin"], [Color("#3E4447"), "tin"], [Color("#9AA2A3"), "tin"]]},
		"frame": Color("#F2F0E9"), "shutter": null, "lane": [120.0, 340.0], "lane_chance": 0.8, "setback": 70.0,
		"tree": Color("#4A5E3E"), "tree_r": [240.0, 320.0], "tree_chance": 0.6},
	&"atlantic": {"kinds": [
			{"w": [520.0, 720.0], "d": [800.0, 1100.0], "form": "ridge", "roofs": "slate", "pitch": 230.0, "stack": true},
			{"w": [520.0, 700.0], "d": [800.0, 1000.0], "form": "ridge", "roofs": "slate", "pitch": 240.0, "stack": true},
			{"w": [800.0, 1100.0], "d": [1000.0, 1300.0], "form": "hip", "roofs": "slate", "pitch": 260.0}],
		"facades": [Color("#DCDAD2"), Color("#9A978E"), Color("#CFC6B0"), Color("#A9B6BA"), Color("#E4E1D8"), Color("#8C8A84")],
		"roofs": {"slate": [[Color("#4D5459"), "slate"], [Color("#565D62"), "slate"], [Color("#454B50"), "slate"]]},
		"frame": Color("#E8E6DE"), "shutter": null, "lane": [40.0, 220.0], "lane_chance": 0.35, "setback": 6.0,
		"tree": Color("#4E5E47"), "tree_r": [200.0, 280.0], "tree_chance": 0.3},
	&"mediterranean": {"kinds": [
			{"w": [520.0, 800.0], "d": [800.0, 1100.0], "form": "ridge", "roofs": "terracotta", "pitch": 270.0},
			{"w": [500.0, 760.0], "d": [800.0, 1000.0], "form": "flat", "roofs": "terrace", "pitch": 280.0},
			{"w": [600.0, 900.0], "d": [900.0, 1200.0], "form": "hip", "roofs": "terracotta", "pitch": 280.0}],
		"facades": [Color("#E2D9C6"), Color("#D7B98A"), Color("#E6E2D8"), Color("#CFA27E"), Color("#D9C6A3"), Color("#C9B79A")],
		"roofs": {"terracotta": [[Color("#A8644A"), "pantile"], [Color("#B5704F"), "pantile"], [Color("#9A5A43"), "pantile"]],
			"terrace": [[Color("#D8D0BF"), "terrace"], [Color("#CFC5B0"), "terrace"]]},
		"frame": null, "shutter": [Color("#4F6B55"), Color("#5D7A88"), Color("#6E5440"), Color("#7C8A6A")],
		"lane": [60.0, 260.0], "lane_chance": 0.55, "setback": 20.0,
		"tree": Color("#55623F"), "tree_r": [240.0, 330.0], "tree_chance": 0.45},
	&"tropical": {"kinds": [
			{"w": [620.0, 900.0], "d": [700.0, 1000.0], "form": "ridge", "roofs": "tin", "pitch": 300.0, "veranda": true},
			{"w": [520.0, 760.0], "d": [700.0, 900.0], "form": "hip", "roofs": "tin", "pitch": 280.0},
			{"w": [500.0, 700.0], "d": [700.0, 900.0], "form": "flat", "roofs": "concrete", "pitch": 260.0}],
		"facades": [Color("#D9D4C4"), Color("#A9BFB6"), Color("#D8B98E"), Color("#E0CF96"), Color("#CDB4A6"), Color("#C9CFC4")],
		"roofs": {"tin": [[Color("#8C4E44"), "tin"], [Color("#5E7F72"), "tin"], [Color("#9AA2A3"), "tin"], [Color("#4F6F7E"), "tin"]],
			"concrete": [[Color("#BDB8AC"), "terrace"]]},
		"frame": Color("#E6E4DC"), "shutter": [Color("#4F6F7E"), Color("#5E7F72"), Color("#8C6A4E")],
		"lane": [140.0, 340.0], "lane_chance": 0.8, "setback": 60.0,
		"tree": Color("#55704A"), "tree_r": [260.0, 340.0], "tree_chance": 0.7},
}


func _draw_building(rect: Rect2, kind: Dictionary, town: Dictionary, rng: RandomNumberGenerator) -> void:
	var facades: Array = town.facades
	var facade: Color = facades[rng.randi() % facades.size()]
	var choices: Array = (town.roofs as Dictionary)[kind.roofs]
	var pick: Array = choices[rng.randi() % choices.size()]
	var roof: Color = pick[0]
	var material: String = pick[1]
	var form: String = kind.form
	# Cast shadow down-right onto the lane and the street.
	draw_rect(Rect2(rect.position + Vector2(34, 26), rect.size), Color(0.03, 0.05, 0.06, 0.26))
	# The facade's top below the eaves (the boat's slight look-down), with its window heads.
	var lip := Rect2(rect.position, Vector2(rect.size.x, LIP))
	draw_rect(lip, facade)
	var pitch: float = kind.get("pitch", 0.0)
	if kind.get("door", false):  # a boat shed's doors
		draw_rect(Rect2(rect.position.x + rect.size.x * 0.2, rect.position.y + 4, rect.size.x * 0.6, LIP - 4), facade.darkened(0.35))
		draw_line(Vector2(rect.get_center().x, rect.position.y + 4), Vector2(rect.get_center().x, rect.position.y + LIP), facade.darkened(0.5), 2.0)
	elif pitch > 0.0:
		var n := maxi(1, int(rect.size.x / pitch))
		var shutter_colours = town.shutter
		var shutter: Color = (shutter_colours as Array)[rng.randi() % (shutter_colours as Array).size()] if shutter_colours != null else Color.TRANSPARENT
		for c in n:
			var cx := rect.position.x + (c + 0.5) * rect.size.x / n
			var ww := 100.0
			var win := Rect2(cx - ww / 2.0, rect.position.y + 5.0, ww, LIP - 9.0)
			if shutter.a > 0.0:
				draw_rect(Rect2(win.position.x - 44.0, win.position.y, 42.0, win.size.y), shutter)
				draw_rect(Rect2(win.end.x + 2.0, win.position.y, 42.0, win.size.y), shutter)
			draw_rect(win, facade.darkened(0.55))
			if town.frame != null:
				draw_rect(win, town.frame, false, 3.0)
	draw_rect(Rect2(rect.position.x, rect.position.y + LIP - 5.0, rect.size.x, 5.0), Color(0, 0, 0, 0.18))  # the eaves' shadow
	var body := Rect2(rect.position + Vector2(-10, LIP), rect.size + Vector2(20, -LIP))  # the eaves overhang the walls
	if kind.get("veranda", false):  # a lean-to veranda roof along the front
		var ver := Rect2(body.position, Vector2(body.size.x, 120))
		draw_rect(ver, roof.lightened(0.18))
		_roof_texture(ver, roof.lightened(0.18), "tin", true)
		draw_line(Vector2(ver.position.x, ver.end.y), Vector2(ver.end.x, ver.end.y), roof.darkened(0.4), 3.0)
		body = Rect2(body.position + Vector2(0, 120), body.size - Vector2(0, 120))
	match form:
		"flat":
			draw_rect(body, roof)
			_roof_texture(body.grow(-18.0), roof.darkened(0.05), material, true)
			draw_rect(Rect2(body.position + Vector2(18, 18), Vector2(body.size.x - 36, 14)), Color(0, 0, 0, 0.12))  # the parapet's shadow
			draw_rect(body, roof.lightened(0.1), false, 3.0)
			if rng.randf() < 0.6:  # a pot of geraniums or a lemon tree on the terrace
				var pot := body.position + Vector2(rng.randf_range(80, body.size.x - 80), 90)
				draw_circle(pot + Vector2(10, 12), 34.0, Color(0, 0, 0, 0.18))
				draw_circle(pot, 34.0, (town.tree as Color).lightened(0.08))
				draw_circle(pot + Vector2(-8, -8), 6.0, Color("#C0533F"))
			if _archetype == ARCHETYPE_TROPICAL or rng.randf() < 0.3:  # a water tank
				var tank := body.position + Vector2(body.size.x - 120, 140)
				draw_circle(tank + Vector2(12, 14), 56.0, Color(0, 0, 0, 0.2))
				draw_circle(tank, 56.0, Color("#B4B8B4"))
				draw_circle(tank + Vector2(-14, -14), 24.0, Color("#C8CCC8"))
		"gable":
			# Gable-end to the quay: the left plane lit, the right in shade, the ridge running away.
			var mid := body.get_center().x
			var lit := roof.lightened(0.12)
			var dark := roof.darkened(0.12)
			draw_rect(Rect2(body.position, Vector2(mid - body.position.x, body.size.y)), lit)
			draw_rect(Rect2(mid, body.position.y, body.end.x - mid, body.size.y), dark)
			_roof_texture(Rect2(body.position, Vector2(mid - body.position.x, body.size.y)), lit, material, false)
			_roof_texture(Rect2(mid, body.position.y, body.end.x - mid, body.size.y), dark, material, false)
			draw_line(Vector2(mid, body.position.y), Vector2(mid, body.end.y), roof.darkened(0.4), 5.0)
			draw_rect(Rect2(body.position, Vector2(body.size.x, 8)), Color("#E4E1D6") if _archetype == ARCHETYPE_NORDIC else facade.lightened(0.1))  # bargeboards
		"hip":
			var inset := minf(body.size.x, body.size.y) * 0.45
			var a := Vector2(body.position.x + inset, body.position.y + inset)
			var b := Vector2(body.end.x - inset, body.position.y + inset)
			var near_plane := PackedVector2Array([body.position, Vector2(body.end.x, body.position.y), b, a])
			draw_colored_polygon(near_plane, roof.lightened(0.1))
			_roof_texture(Rect2(body.position, Vector2(body.size.x, inset)), roof.lightened(0.1), material, true, near_plane)
			draw_colored_polygon(PackedVector2Array([body.position, a, Vector2(a.x, body.end.y), Vector2(body.position.x, body.end.y)]), roof.lightened(0.16))
			draw_colored_polygon(PackedVector2Array([Vector2(body.end.x, body.position.y), b, Vector2(b.x, body.end.y), body.end]), roof.darkened(0.16))
			draw_rect(Rect2(a, Vector2(b.x - a.x, body.end.y - a.y)), roof.darkened(0.08))
			draw_line(body.position, a, roof.lightened(0.3), 3.0)
			draw_line(Vector2(body.end.x, body.position.y), b, roof.darkened(0.35), 3.0)
			draw_line(a, b, roof.darkened(0.3), 4.0)
		_:
			# Ridge along the quay: the near plane facing the light, the far one in shade.
			var ridge := body.position.y + body.size.y * 0.48
			var near_rect := Rect2(body.position, Vector2(body.size.x, ridge - body.position.y))
			draw_rect(near_rect, roof.lightened(0.1))
			_roof_texture(near_rect, roof.lightened(0.1), material, true)
			draw_rect(Rect2(body.position.x, ridge, body.size.x, body.end.y - ridge), roof.darkened(0.12))
			draw_line(Vector2(body.position.x, ridge), Vector2(body.end.x, ridge), roof.darkened(0.4), 6.0)
			if rng.randf() < float(kind.get("dormer", 0.0)):
				var dx := body.position.x + rng.randf_range(80.0, maxf(81.0, body.size.x - 230.0))
				var dormer := Rect2(dx, body.position.y + 40.0, 150.0, 130.0)
				draw_rect(Rect2(dormer.position + Vector2(18, 16), dormer.size), Color(0, 0, 0, 0.2))
				draw_rect(dormer, roof.lightened(0.06))
				draw_rect(Rect2(dormer.position, Vector2(dormer.size.x, 18)), facade)
				draw_line(Vector2(dormer.get_center().x, dormer.position.y + 18), Vector2(dormer.get_center().x, dormer.end.y), roof.darkened(0.3), 3.0)
			elif material != "pantile" and rng.randf() < 0.5:  # a roof window
				var sk := Rect2(body.position.x + rng.randf_range(60.0, maxf(61.0, body.size.x - 120.0)), body.position.y + 60.0, 56.0, 80.0)
				draw_rect(sk, Color("#3A4A55"))
				draw_rect(sk, roof.darkened(0.45), false, 3.0)
			if kind.get("stack", false):  # Atlantic chimney stacks on the party walls
				for sx: float in [body.position.x + 10.0, body.end.x - 130.0]:
					var stack := Rect2(sx, ridge - 34.0, 120.0, 60.0)
					draw_rect(Rect2(stack.position + Vector2(30, 24), stack.size), Color(0, 0, 0, 0.24))
					draw_rect(stack, facade.darkened(0.12))
					for k in 3:
						draw_circle(stack.position + Vector2(24 + k * 36, 30), 11.0, Color("#9A6A52"))
						draw_circle(stack.position + Vector2(24 + k * 36, 30), 6.0, Color("#2B2826"))
			elif rng.randf() < float(kind.get("chimney", 0.0)):
				var ch := Rect2(body.position.x + rng.randf_range(60.0, maxf(61.0, body.size.x - 120.0)), ridge - 30.0, 54.0, 54.0)
				draw_rect(Rect2(ch.position + Vector2(20, 18), ch.size), Color(0, 0, 0, 0.24))
				draw_rect(ch, Color("#6E625A") if _archetype != ARCHETYPE_NORDIC else Color("#5C5550"))
				draw_rect(ch.grow(-14.0), Color("#2B2826"))
	draw_line(Vector2(body.position.x, body.position.y), Vector2(body.end.x, body.position.y), Color(INK, 0.35), 2.0)  # gutter
	draw_rect(rect, Color(INK, 0.4), false, 1.5)


## A roof material at its real size, with the detail falling off away from the
## eaves (the courses fade; joints only near the front). `along` is true when
## the courses run along the quay (eaves at the rect's top), false for a
## gable-end plane (eaves on the rect's long sides).
func _roof_texture(area: Rect2, colour: Color, material: String, along: bool, _clip := PackedVector2Array()) -> void:
	var dark := colour.darkened(0.3)
	var depth := minf(area.size.y if along else area.size.x, 420.0)
	match material:
		"tin":
			var step := 8.0
			if along:
				var u := area.position.x + 3.0
				var k := 0
				while u < area.end.x:
					draw_line(Vector2(u, area.position.y), Vector2(u, area.position.y + depth), Color(colour.lightened(0.18) if k % 2 else dark, 0.35), 1.6)
					u += step
					k += 1
			else:
				var v := area.position.y + 3.0
				while v < area.position.y + depth:
					draw_line(Vector2(area.position.x, v), Vector2(area.end.x, v), Color(dark, 0.3), 1.6)
					v += step
		"pantile":
			var roll := 23.0
			if along:
				var u := area.position.x
				while u < area.end.x:
					draw_rect(Rect2(u, area.position.y, roll * 0.5, depth), Color(colour.lightened(0.1), 0.6))
					draw_line(Vector2(u + roll - 1.0, area.position.y), Vector2(u + roll - 1.0, area.position.y + depth), Color(dark, 0.55), 2.0)
					u += roll
				var v := area.position.y + 38.0
				var fade := 0.4
				while v < area.position.y + depth:
					draw_line(Vector2(area.position.x, v), Vector2(area.end.x, v), Color(dark, fade), 1.5)
					v += 38.0
					fade *= 0.85
			else:
				var v := area.position.y
				while v < area.position.y + depth:
					draw_rect(Rect2(area.position.x, v, area.size.x, roll * 0.5), Color(colour.lightened(0.1), 0.6))
					draw_line(Vector2(area.position.x, v + roll - 1.0), Vector2(area.end.x, v + roll - 1.0), Color(dark, 0.55), 2.0)
					v += roll
		"terrace":
			var tile := 42.0
			var v := area.position.y
			while v < area.position.y + minf(depth, area.size.y):
				draw_line(Vector2(area.position.x, v), Vector2(area.end.x, v), Color(dark, 0.18), 1.2)
				v += tile
			var u := area.position.x
			while u < area.end.x:
				draw_line(Vector2(u, area.position.y), Vector2(u, area.position.y + minf(depth, area.size.y)), Color(dark, 0.18), 1.2)
				u += tile
		_:
			# Tile, slate or shingle courses, the joints staggered near the eaves.
			var course: float = {"tile": 34.0, "slate": 24.0, "shingle": 20.0}.get(material, 30.0)
			var joint: float = {"tile": 24.0, "slate": 32.0, "shingle": 26.0}.get(material, 28.0)
			var fade := 0.42
			var row := 0
			var v := course
			while v < depth:
				if along:
					draw_line(Vector2(area.position.x, area.position.y + v), Vector2(area.end.x, area.position.y + v), Color(dark, fade), 1.5)
				else:
					var xx := area.position.x + v if area.position.x < area.end.x - v else area.end.x
					draw_line(Vector2(xx, area.position.y), Vector2(xx, area.end.y), Color(dark, fade), 1.5)
				if row < 5 and along:
					var u := area.position.x + (joint * 0.5 if row % 2 else 0.0)
					while u < area.end.x:
						draw_line(Vector2(u, area.position.y + v - course), Vector2(u, area.position.y + v), Color(dark, fade * 0.6), 1.0)
						u += joint
				v += course
				row += 1
				fade *= 0.9


func _draw_tree(at: Vector2, radius: float, colour: Color, rng: RandomNumberGenerator) -> void:
	draw_circle(at + Vector2(radius * 0.3, radius * 0.36), radius, Color(0.03, 0.05, 0.05, 0.28))
	if _town_key == &"new_zealand" and rng.randf() < 0.55:
		# A pōhutukawa: a broad, dark, glossy crown, flecked crimson in flower.
		draw_circle(at, radius, colour.darkened(0.15))
		for k in 8:
			var o := Vector2.from_angle(TAU * k / 8.0 + rng.randf()) * radius * 0.5
			draw_circle(at + o, radius * 0.45, colour.lerp(Color("#3E5233"), 0.4).lightened(0.05 * (k % 3)))
		for k in 14:
			var o := Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.2, 0.85)
			draw_circle(at + o, radius * 0.06, Color("#B23A32"))
		return
	if _town_key == ARCHETYPE_TROPICAL:
		# A palm: tapering fronds radiating from the crown, the old ones lower and brown.
		for k in 11:
			var a := TAU * k / 11.0 + rng.randf_range(-0.15, 0.15)
			var dir := Vector2.from_angle(a)
			var length := radius * rng.randf_range(0.85, 1.05)
			var side := dir.orthogonal() * length * 0.14
			var lit := 0.85 + 0.25 * dir.dot(Vector2(-0.8, -0.6))
			var c := colour.lerp(Color("#7C8C58"), 0.2) * lit
			c.a = 1.0
			draw_colored_polygon(PackedVector2Array([at, at + dir * length * 0.45 + side, at + dir * length, at + dir * length * 0.45 - side]), c)
			draw_line(at, at + dir * length * 0.96, c.lightened(0.2), 3.0, true)
		draw_circle(at, radius * 0.1, Color("#6B5A44"))
		return
	if _archetype == ARCHETYPE_MEDITERRANEAN and rng.randf() < 0.6:
		# An umbrella pine: a broad, flat crown of dark clusters.
		draw_circle(at, radius, colour.darkened(0.12))
		for k in 9:
			var o := Vector2.from_angle(TAU * k / 9.0 + rng.randf()) * radius * 0.55
			draw_circle(at + o, radius * 0.42, colour.lerp(Color("#4A5A3A"), 0.3).lightened(0.04 * (k % 3)))
		return
	for k in 7:
		var o := Vector2.from_angle(TAU * k / 7.0 + rng.randf()) * radius * 0.45
		draw_circle(at + o, radius * 0.62, colour.darkened(0.08))
	for k in 5:
		var o := Vector2.from_angle(TAU * k / 5.0 + rng.randf()) * radius * 0.3 + Vector2(-radius * 0.15, -radius * 0.15)
		draw_circle(at + o, radius * 0.42, colour.lightened(0.08))


func _draw_landmark(landmark: HarbourLandmark) -> void:
	var size := landmark.texture.get_size()
	var scale := landmark.width / maxf(size.x, 1.0)
	var center := get_quay_anchor() + landmark.offset
	draw_texture_rect(landmark.texture, Rect2(center - size * scale / 2.0, size * scale), false)


func _draw_pontoon(rng: RandomNumberGenerator) -> void:
	var p := _pontoon
	draw_rect(Rect2(p.position + Vector2(6, 9), p.size), SHADOW)  # shadow on the water
	# Weathered decking across the pontoon, between galvanised edge frames.
	draw_rect(p, PLANK)
	var x := p.position.x
	var board := 14.0
	while x < p.end.x - 0.5:
		var w := minf(board, p.end.x - x)
		draw_rect(Rect2(x + 0.5, p.position.y + 7.0, w - 1.0, p.size.y - 14.0), PLANK.lerp(PLANK_DARK, rng.randf_range(0.0, 0.3)))
		x += board
	# Fixings: rows of screws along the joists.
	for jy in [p.position.y + 24.0, p.get_center().y, p.end.y - 24.0]:
		draw_line(Vector2(p.position.x, jy), Vector2(p.end.x, jy), Color(PLANK_DARK.darkened(0.25), 0.35), 1.0)
	# The galvanised frame on both long edges and the black rubbing strip on the water side.
	draw_rect(Rect2(p.position, Vector2(p.size.x, 7)), GALVANISED)
	draw_rect(Rect2(p.position.x, p.end.y - 7, p.size.x, 7), GALVANISED.darkened(0.12))
	draw_rect(Rect2(p.position + Vector2(0, -4), Vector2(p.size.x, 4)), RUBBER)
	# Module joints and shore-power pedestals.
	var mx := p.position.x + 400.0
	while mx < p.end.x - 10.0:
		draw_line(Vector2(mx, p.position.y), Vector2(mx, p.end.y), Color(INK, 0.5), 2.0)
		mx += 400.0
	var px := p.position.x + 210.0
	while px < p.end.x - 80.0:
		var at := Vector2(px, p.position.y + 22.0)  # a shore-power pedestal, about 26 x 20 cm
		draw_rect(Rect2(at + Vector2(-13, -10) + Vector2(5, 6), Vector2(26, 20)), SHADOW)
		draw_rect(Rect2(at + Vector2(-13, -10), Vector2(26, 20)), Color("#DADBD5"))
		draw_rect(Rect2(at + Vector2(-10, -7), Vector2(20, 5)), Color("#3B6E8C"))
		draw_rect(Rect2(at + Vector2(-13, -10), Vector2(26, 20)), Color(INK, 0.6), false, 1.0)
		px += 560.0
	draw_rect(p, Color(INK, 0.6), false, 1.4)


# --- The walkway to the quay (I026 stage 02) -----------------------------------------

## The walkway station's interaction id (BoatArea.WALKWAY_ID), and how far
## its sign stands beside it.
const WALKWAY_STATION := &"quay"
const WALKWAY_SIGN_SHIFT := 160.0
const WALKWAY_HALF := 44.0
## Where the walkway runs up from the pontoon (NAN: none shown).
var _walkway_x := NAN


func get_walkway_x() -> float:
	return _walkway_x


## An aluminium brow from the back of the pontoon up onto the quay, with
## non-slip treads and hand rails (the walkway's own art).
func _draw_walkway() -> void:
	if is_nan(_walkway_x):
		return
	var top := _pontoon.end.y - ShoreAccess.SIGN_BAND + 4.0
	var bottom := _pontoon.end.y + 6.0 + COPING + 30.0
	var x0 := _walkway_x - WALKWAY_HALF
	var x1 := _walkway_x + WALKWAY_HALF
	draw_rect(Rect2(x0 + 6, top + 9, x1 - x0, bottom - top), SHADOW)
	draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color("#A3AAAB"))
	draw_rect(Rect2(x0, top, 4, bottom - top), Color("#6E7678"))
	draw_rect(Rect2(x1 - 4, top, 4, bottom - top), Color("#6E7678"))
	var y := top + 7.0
	while y < bottom - 4.0:
		draw_rect(Rect2(x0 + 6, y, x1 - x0 - 12, 3.0), Color("#3A4144"))
		y += 11.0
	for x: float in [x0 - 5.0, x1 + 5.0]:
		draw_line(Vector2(x, top), Vector2(x, bottom + 4), Color(INK, 0.6), 3.0, true)
		draw_line(Vector2(x, top), Vector2(x, bottom + 4), ROPE, 1.6, true)


func _draw_rope(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	# A gentle sag between the boat and the cleat.
	var a := points[0]
	var b := points[points.size() - 1]
	var pts := PackedVector2Array()
	var normal := (b - a).orthogonal().normalized()
	for k in 13:
		var t := k / 12.0
		pts.append(a.lerp(b, t) + normal * sin(t * PI) * 6.0)
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(3, 5))
	draw_polyline(shadow, SHADOW, 3.0, true)
	draw_polyline(pts, ROPE.darkened(0.35), 3.2, true)
	draw_polyline(pts, ROPE, 2.0, true)


func _draw_cleat(c: Vector2) -> void:
	var body := Rect2(c - Vector2(15, 3.5), Vector2(30, 7))
	draw_rect(Rect2(body.position + Vector2(2, 3), body.size), SHADOW)
	draw_rect(body, GALVANISED)
	draw_rect(Rect2(body.position, Vector2(body.size.x, 2.5)), GALVANISED.lightened(0.25))
	draw_rect(body, Color(INK, 0.7), false, 1.0)
	draw_circle(c, 3.0, GALVANISED.darkened(0.3))


func _draw_sign(sign: Dictionary) -> void:
	# Marina signage: a dark blue panel on two posts, a white pictogram
	# square; the text is the sign's own Label (drawn on top).
	var text: String = sign.text
	var text_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var center: Vector2 = sign.at
	var board := sign_board(sign)
	draw_rect(Rect2(board.position + Vector2(4, 6), board.size), SHADOW)
	draw_rect(board, SIGN_BOARD)
	draw_rect(Rect2(board.position, Vector2(board.size.x, 3)), Color("#5AA8B8"))
	draw_rect(board, Color(INK, 0.8), false, 1.0)
	var tile := Rect2(Vector2(board.position.x + 5, center.y - 13), Vector2(26, 26))
	draw_rect(tile, Color("#EEF2F1"))
	_draw_icon(sign.icon, tile.get_center())
	if not sign.label:
		draw_string(_font, Vector2(center.x - text_width / 2.0 + 8.0, center.y + 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, SIGN_TEXT)


func _draw_icon(icon: StringName, at: Vector2) -> void:
	# Plain pictograms in the sign's blue on its white tile.
	var ink := SIGN_BOARD
	match icon:
		&"basket":
			var basket := PackedVector2Array([at + Vector2(-8, -2), at + Vector2(8, -2), at + Vector2(5.5, 8), at + Vector2(-5.5, 8)])
			draw_colored_polygon(basket, ink)
			draw_arc(at + Vector2(0, -2), 6.0, PI, TAU, 12, ink, 1.8, true)
		&"compass":
			draw_arc(at, 8.5, 0, TAU, 24, ink, 1.8, true)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(2.6, 0), at + Vector2(-2.6, 0)]), Color("#B5523F"))
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, 7), at + Vector2(2.6, 0), at + Vector2(-2.6, 0)]), ink)
		&"quay":  # steps up to a little house: the way to the quay
			draw_colored_polygon(PackedVector2Array([at + Vector2(-2, -9), at + Vector2(8, -2), at + Vector2(-12, -2)]), ink)
			draw_rect(Rect2(at + Vector2(-10, -2), Vector2(16, 8)), ink)
			for k in 3:
				draw_rect(Rect2(at + Vector2(-9 + k * 5, 6 - k * 2), Vector2(5, 3 + k * 2)), Color("#5AA8B8"))
		&"wrench":
			draw_line(at + Vector2(-7, 7), at + Vector2(4, -4), ink, 3.2, true)
			draw_arc(at + Vector2(5.5, -5.5), 4.2, -PI * 0.25, PI * 1.25, 10, ink, 2.6, true)


static func _wobbly_rect(rect: Rect2, _rng: RandomNumberGenerator) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
		rect.position])
