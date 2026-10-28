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
## Depth of the quay drawn beyond the pontoon (scene units).
const QUAY_DEPTH := 130.0
## Where the buildings start, beyond the quay edge (scene units).
const TOWN_FROM := 46.0
## The far side of the basin: a pontoon with neighbouring boats moored bow-in;
## their bows stop this far short of our boat's art canvas (scene units).
const FAR_CLEARANCE := 36.0
const NEIGHBOUR_MAX_LENGTH := 300.0

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
	&"go_ashore": ["Go Ashore", &"compass", "GoAshoreSign"]}
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
	# The harbour's own landmarks, else the illustration of its look (I021).
	_art = HarbourLooks.get_default().art_for(_port_id)
	_landmarks = _art.get_landmarks() if _art else ([] as Array[HarbourLandmark])
	_signs.clear()
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
	var left := _pontoon.position.x - 40.0
	var right := _pontoon.end.x + 40.0
	var bx := left + 80.0
	var i := 0
	while bx < right - 40.0:
		if i % 3 == 1:
			lamps.append(Vector2(bx, top + 8.0))
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


## Across the fairway: a pontoon parallel to ours with the neighbours' boats
## lying alongside it - cruising yachts, and the archetype's own local boats
## (a Nordic fishing cutter, an Atlantic trawler, a Mediterranean gozzo, a
## tropical catamaran). Art only, clear of the boat and its stations.
func _draw_far_side(rng: RandomNumberGenerator) -> void:
	var visual := _area.get_node_or_null(^"Visual") as VesselVisual
	var top := visual.canvas.position.y if visual else -_pontoon.position.y
	var max_beam := NEIGHBOUR_MAX_LENGTH * 0.36
	var row := top - FAR_CLEARANCE - max_beam  # the neighbours' outer side
	var left := _pontoon.position.x - 200.0
	var right := _pontoon.end.x + 200.0
	draw_rect(Rect2(left + 6, row - 40 + 8, right - left, 34), SHADOW)
	draw_rect(Rect2(left, row - 40, right - left, 34), PLANK.darkened(0.05))
	draw_rect(Rect2(left, row - 40, right - left, 5), GALVANISED.darkened(0.1))
	draw_rect(Rect2(left, row - 6, right - left, 4), RUBBER)
	var x := left + rng.randf_range(10.0, 60.0)
	while x < right - 80.0:
		var local := rng.randf() < 0.3
		var length := rng.randf_range(210.0, NEIGHBOUR_MAX_LENGTH)
		var beam := length * rng.randf_range(0.3, 0.36)
		var centre_y := row + beam / 2.0 + 4.0
		_draw_rope(PackedVector2Array([Vector2(x + 30.0, centre_y - beam * 0.3), Vector2(x + 10.0, row - 8.0)]))
		_draw_rope(PackedVector2Array([Vector2(x + length - 50.0, centre_y - beam * 0.3), Vector2(x + length - 20.0, row - 8.0)]))
		# Drawn bow-up in their own frame, turned to lie bow east like ours.
		draw_set_transform(Vector2(x, centre_y), -PI / 2.0)
		if local:
			_draw_local_boat(Vector2.ZERO, length, beam, rng)
		else:
			_draw_neighbour_yacht(Vector2.ZERO, length, beam, rng)
		draw_set_transform(Vector2.ZERO)
		x += length + rng.randf_range(30.0, 90.0)


## The shadow offset in a boat's own frame (turned by -90 degrees): down-right on screen.
const NEIGHBOUR_SHADOW := Vector2(-10, 7)


## A cruising yacht seen from above, stern to the pontoon at `stern`, bow +y.
func _draw_neighbour_yacht(stern: Vector2, length: float, beam: float, rng: RandomNumberGenerator) -> void:
	var hull := PackedVector2Array()
	var half := beam / 2.0
	for k in 13:
		var t := k / 12.0
		var w := half * (0.86 + 0.14 * sin(t * PI * 0.9)) * (1.0 - pow(maxf(t - 0.55, 0.0) / 0.45, 1.7))
		hull.append(stern + Vector2(-w, 6.0 + t * length))
	for k in range(12, -1, -1):
		var t := k / 12.0
		var w := half * (0.86 + 0.14 * sin(t * PI * 0.9)) * (1.0 - pow(maxf(t - 0.55, 0.0) / 0.45, 1.7))
		hull.append(stern + Vector2(w, 6.0 + t * length))
	var offset := PackedVector2Array()
	for q in hull:
		offset.append(q + NEIGHBOUR_SHADOW)
	draw_colored_polygon(offset, SHADOW)
	draw_colored_polygon(hull, MarinePalette.FIBREGLASS)
	var deck := PackedVector2Array()
	for q in hull:
		deck.append(stern + (q - stern - Vector2(0, length * 0.5)) * Vector2(0.86, 0.95) + Vector2(0, length * 0.5))
	draw_colored_polygon(deck, MarinePalette.NON_SKID)
	draw_rect(Rect2(stern + Vector2(-half * 0.55, 14), Vector2(beam * 0.55, length * 0.2)), MarinePalette.TEAK)  # cockpit
	var roof := Rect2(stern + Vector2(-half * 0.48, 14 + length * 0.22), Vector2(beam * 0.48, length * 0.32))
	draw_rect(roof, MarinePalette.FIBREGLASS.lightened(0.05))
	draw_rect(roof, Color(INK, 0.35), false, 1.0)
	if rng.randf() < 0.6:  # a sprayhood
		draw_rect(Rect2(roof.position + Vector2(-2, -10), Vector2(roof.size.x + 4, 12)), MarinePalette.CANVAS_SPRAYHOOD)
	draw_line(stern + Vector2(0, 14 + length * 0.24), stern + Vector2(0, 14 + length * 0.52), MarinePalette.CANVAS_SPRAYHOOD, 6.0)  # sail cover
	draw_circle(stern + Vector2(0, 14 + length * 0.55), 4.0, MarinePalette.BRUSHED_STEEL)  # mast
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(MarinePalette.BRUSHED_STEEL, 0.9), 1.6, true)


## The archetype's own working or local boat.
func _draw_local_boat(stern: Vector2, length: float, beam: float, rng: RandomNumberGenerator) -> void:
	var colours := {ARCHETYPE_NORDIC: [Color("#7E3F34"), Color("#2F4F63")], ARCHETYPE_ATLANTIC: [Color("#2F4F63"), Color("#3E5A4A")],
		ARCHETYPE_MEDITERRANEAN: [Color("#E3E2DA"), Color("#4A7A9A")], ARCHETYPE_TROPICAL: [Color("#E3E2DA"), Color("#5E7F72")]}
	var pair: Array = colours.get(_archetype, colours[ARCHETYPE_NORDIC])
	var half := beam / 2.0
	if _archetype == ARCHETYPE_TROPICAL:
		# A cruising catamaran: two hulls, a bridgedeck, a trampoline forward.
		for side: float in [-1.0, 1.0]:
			var h := Rect2(stern + Vector2(side * half * 1.3 - half * 0.35, 6), Vector2(half * 0.7, length))
			draw_rect(Rect2(h.position + NEIGHBOUR_SHADOW, h.size), SHADOW)
			draw_rect(h, MarinePalette.FIBREGLASS)
		draw_rect(Rect2(stern + Vector2(-half * 1.3, 30), Vector2(half * 2.6, length * 0.5)), MarinePalette.NON_SKID)
		draw_rect(Rect2(stern + Vector2(-half * 0.9, 40), Vector2(half * 1.8, length * 0.36)), MarinePalette.FIBREGLASS.lightened(0.05))
		draw_rect(Rect2(stern + Vector2(-half * 0.95, 30 + length * 0.5), Vector2(half * 1.9, length * 0.4)), Color("#2A3A42"))
		return
	var hull := PackedVector2Array()
	for k in 11:
		var t := k / 10.0
		hull.append(stern + Vector2(-half * (1.0 - pow(maxf(t - 0.5, 0.0) / 0.5, 2.0) * 0.9), 6.0 + t * length * 0.9))
	hull.append(stern + Vector2(0, 6.0 + length * 0.96))
	for k in range(10, -1, -1):
		var t := k / 10.0
		hull.append(stern + Vector2(half * (1.0 - pow(maxf(t - 0.5, 0.0) / 0.5, 2.0) * 0.9), 6.0 + t * length * 0.9))
	var offset := PackedVector2Array()
	for q in hull:
		offset.append(q + NEIGHBOUR_SHADOW)
	draw_colored_polygon(offset, SHADOW)
	draw_colored_polygon(hull, pair[0])
	var deck := PackedVector2Array()
	for q in hull:
		deck.append(stern + (q - stern - Vector2(0, length * 0.5)) * Vector2(0.84, 0.94) + Vector2(0, length * 0.5))
	var deck_colour := Color("#8A8478") if _archetype == ARCHETYPE_MEDITERRANEAN else Color("#7D817F")
	draw_colored_polygon(deck, deck_colour)
	if _archetype == ARCHETYPE_MEDITERRANEAN:
		# A wooden gozzo: varnished thwarts, a small canopy.
		for k in 4:
			draw_rect(Rect2(stern + Vector2(-half * 0.8, 30 + k * length * 0.18), Vector2(half * 1.6, 6)), MarinePalette.TEAK)
		draw_rect(Rect2(stern + Vector2(-half * 0.7, 20), Vector2(half * 1.4, length * 0.22)), pair[1])
	else:
		# A fishing boat: the wheelhouse forward of the working deck, a net drum aft.
		var house := Rect2(stern + Vector2(-half * 0.6, length * 0.45), Vector2(half * 1.2, length * 0.22))
		draw_rect(Rect2(house.position + NEIGHBOUR_SHADOW * 0.7, house.size), SHADOW)
		draw_rect(house, Color("#E3E4DE"))
		draw_rect(Rect2(house.position + Vector2(3, house.size.y - 7), Vector2(house.size.x - 6, 5)), Color("#2A3A42"))
		draw_circle(stern + Vector2(0, length * 0.16), half * 0.26, pair[1])
		draw_circle(stern + Vector2(0, length * 0.16), half * 0.12, Color("#3A4044"))
		draw_line(stern + Vector2(0, length * 0.7), stern + Vector2(0, length * 0.85), Color("#4A5054"), 4.0)
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(INK, 0.5), 1.2, true)
	# Name boards and the odd fender, in the region's colours.
	if rng.randf() < 0.5:
		draw_rect(Rect2(stern + Vector2(-half - 4, length * 0.3), Vector2(8, 16)), Color("#D9783A"))


func _draw_quay(rng: RandomNumberGenerator) -> void:
	var style := _style()
	var top := _pontoon.end.y + 6.0
	var quay := Rect2(_pontoon.position.x - 260.0, top, _pontoon.size.x + 520.0, QUAY_DEPTH + 220.0)
	draw_rect(Rect2(quay.position + Vector2(0, -6), Vector2(quay.size.x, 6)), Color(0.06, 0.12, 0.14, 0.95))  # gap of water
	var paving: Color = style.paving
	var joint: Color = style.joint
	draw_rect(quay, paving)
	# Coping stones along the edge, then setts or slabs.
	var x := quay.position.x
	while x < quay.end.x:
		var w := rng.randf_range(54, 86)
		var block := Rect2(x, top, minf(w, quay.end.x - x), 15)
		draw_rect(block, (style.edge as Color).lerp(joint, rng.randf_range(0.0, 0.3)))
		draw_line(block.position, Vector2(block.position.x, block.end.y), Color(joint.darkened(0.3), 0.8), 1.0)
		x += w
	draw_line(Vector2(quay.position.x, top + 15), Vector2(quay.end.x, top + 15), Color(joint.darkened(0.25), 0.7), 1.2)
	var y := top + 18.0
	var slab := Vector2(26, 13) if _archetype in [ARCHETYPE_NORDIC, ARCHETYPE_ATLANTIC] else Vector2(60, 30)
	var row := 0
	while y < top + TOWN_FROM - 4.0:
		x = quay.position.x + (slab.x * 0.5 if row % 2 else 0.0)
		while x < quay.end.x:
			var r := Rect2(Vector2(x, y), slab - Vector2(2, 2))
			draw_rect(r, paving.lerp(joint, rng.randf_range(0.0, 0.22)))
			x += slab.x
		y += slab.y
		row += 1
	# A soft shadow of the edge onto the paving, light from the upper left.
	draw_rect(Rect2(quay.position.x, top + 15, quay.size.x, 3), Color(0, 0, 0, 0.08))
	# Bollards, lamp posts, ladders and a life ring along the quay edge.
	var bx := _pontoon.position.x - 40.0 + 80.0
	var i := 0
	while bx < _pontoon.end.x + 40.0 - 40.0:
		var at := Vector2(bx, top + 8.0)
		if i % 3 == 1:
			_draw_lamp_post(at)
		elif i % 6 == 4:
			_draw_life_ring(at + Vector2(0, 2))
		else:
			draw_circle(at + Vector2(2, 3), 6.5, SHADOW)
			draw_circle(at, 6.5, Color("#2F3438"))
			draw_circle(at + Vector2(-1.5, -1.5), 2.5, Color("#5A6064"))
		if i % 4 == 2:  # a steel ladder down to the water
			draw_rect(Rect2(bx + 40, top - 6, 12, 8), GALVANISED)
			draw_line(Vector2(bx + 40, top - 2), Vector2(bx + 52, top - 2), Color(INK, 0.6), 1.0)
		bx += 190.0
		i += 1


func _draw_lamp_post(at: Vector2) -> void:
	# Seen from above: the post's foot, a short arm and the lantern head.
	draw_circle(at + Vector2(2, 3), 8.0, SHADOW)
	draw_circle(at, 4.0, LAMP)
	draw_line(at, at + Vector2(0, -9), LAMP, 2.0, true)
	var head := Rect2(at + Vector2(-7, -15), Vector2(14, 8))
	draw_rect(head, LAMP)
	draw_rect(head.grow(-2.0), LAMP_GLASS)


func _draw_life_ring(at: Vector2) -> void:
	draw_circle(at + Vector2(2, 3), 9.0, SHADOW)
	draw_rect(Rect2(at + Vector2(-2, -12), Vector2(4, 24)), Color("#4A5054"))
	draw_arc(at, 7.0, 0, TAU, 24, Color("#D9783A"), 4.0, true)
	for k in 4:
		var a := k * PI / 2.0 + PI / 4.0
		draw_line(at + Vector2.from_angle(a) * 5.0, at + Vector2.from_angle(a) * 9.0, Color("#E8E6DF"), 3.0)


## The town beyond the quay, seen from above: a row of buildings with their
## roofs (the archetype's materials), alleys between them, the odd tree.
## Where the harbour has its own landmark illustration, that takes the place.
func _draw_town(rng: RandomNumberGenerator) -> void:
	var style := _style()
	var y0 := _pontoon.end.y + 6.0 + TOWN_FROM
	var left := _pontoon.position.x - 260.0
	var right := _pontoon.end.x + 260.0
	var skip := Rect2()
	for landmark in _landmarks:
		var size := landmark.texture.get_size()
		var drawn := Vector2(landmark.width, size.y * landmark.width / maxf(size.x, 1.0))
		var area := Rect2(get_quay_anchor() + landmark.offset - drawn / 2.0, drawn)
		skip = skip.merge(area) if skip.has_area() else area
	# The street in front of the houses.
	draw_rect(Rect2(left, y0 - 24.0, right - left, 24.0), (style.paving as Color).darkened(0.18))
	var x := left
	while x < right:
		var w := rng.randf_range(70.0, 150.0)
		var depth := rng.randf_range(120.0, 180.0)
		var gap := rng.randf_range(6.0, 30.0) if rng.randf() < 0.6 else 0.0
		var rect := Rect2(x, y0 + rng.randf_range(0.0, 10.0), w, depth)
		if not (skip.has_area() and skip.grow(10.0).intersects(rect)):
			if rng.randf() < 0.12 and gap > 0.0:
				_draw_tree(Vector2(x + w * 0.5, y0 + 30.0), rng.randf_range(26.0, 40.0), style.tree, rng)
			else:
				_draw_building(rect, style, rng)
		x += w + gap


func _draw_building(rect: Rect2, style: Dictionary, rng: RandomNumberGenerator) -> void:
	var facades: Array = style.facades
	var roofs: Array = style.roofs
	var forms: Array = style.forms
	var facade: Color = facades[rng.randi() % facades.size()]
	var roof: Color = roofs[rng.randi() % roofs.size()]
	var form: String = forms[rng.randi() % forms.size()]
	# Cast shadow down-right onto the street.
	draw_rect(Rect2(rect.position + Vector2(8, 10), rect.size), Color(0.03, 0.05, 0.06, 0.28))
	# The facade's top edge seen just in front of the eaves (a slight
	# perspective from the boat), with its windows' heads.
	var lip := Rect2(rect.position, Vector2(rect.size.x, 9.0))
	draw_rect(lip, facade)
	var wx := rect.position.x + 9.0
	while wx < rect.end.x - 12.0:
		draw_rect(Rect2(wx, rect.position.y + 3.0, 7.0, 6.0), facade.darkened(0.45))
		wx += 18.0
	var body := Rect2(rect.position + Vector2(0, 9.0), rect.size - Vector2(0, 9.0))
	match form:
		"flat":
			draw_rect(body, roof)
			draw_rect(body.grow(-4.0), roof.darkened(0.06))
			draw_rect(body, roof.darkened(0.3), false, 1.2)
			if rng.randf() < 0.6:  # a roof terrace or plant on top
				draw_rect(Rect2(body.position + Vector2(10, 10), Vector2(24, 14)), Color("#6F6A60"))
				draw_circle(body.position + Vector2(body.size.x - 18, 20), 7.0, (style.tree as Color).lightened(0.05))
		"barrel":
			# Pantiles: two planes, rows of tiles running down the slope.
			var ridge := body.position.y + body.size.y * 0.45
			draw_rect(Rect2(body.position, Vector2(body.size.x, ridge - body.position.y)), roof.lightened(0.08))
			draw_rect(Rect2(body.position.x, ridge, body.size.x, body.end.y - ridge), roof.darkened(0.14))
			var tx := body.position.x + 3.0
			while tx < body.end.x - 1.0:
				draw_line(Vector2(tx, body.position.y + 1), Vector2(tx, body.end.y - 1), Color(roof.darkened(0.35), 0.55), 1.0)
				tx += 6.0
			draw_line(Vector2(body.position.x, ridge), Vector2(body.end.x, ridge), roof.darkened(0.4), 2.0)
		"metal":
			var ridge := body.position.y + body.size.y * 0.5
			draw_rect(Rect2(body.position, Vector2(body.size.x, ridge - body.position.y)), roof.lightened(0.1))
			draw_rect(Rect2(body.position.x, ridge, body.size.x, body.end.y - ridge), roof.darkened(0.12))
			var cx := body.position.x + 2.0
			while cx < body.end.x:
				draw_line(Vector2(cx, body.position.y), Vector2(cx, body.end.y), Color(roof.darkened(0.3), 0.4), 1.0)
				cx += 4.0
			draw_line(Vector2(body.position.x, ridge), Vector2(body.end.x, ridge), roof.lightened(0.25), 1.5)
			if rng.randf() < 0.4:  # weathering
				draw_rect(Rect2(body.position + Vector2(body.size.x * 0.3, 6), Vector2(body.size.x * 0.25, 12)), Color(0.45, 0.3, 0.22, 0.25))
		_:
			# A pitched roof with its ridge along the street: the plane facing
			# the light (towards the quay) lighter, the far one in shade.
			var ridge := body.position.y + body.size.y * 0.42
			draw_rect(Rect2(body.position, Vector2(body.size.x, ridge - body.position.y)), roof.lightened(0.12))
			draw_rect(Rect2(body.position.x, ridge, body.size.x, body.end.y - ridge), roof.darkened(0.1))
			var ty := body.position.y + 5.0
			while ty < body.end.y:
				draw_line(Vector2(body.position.x + 1, ty), Vector2(body.end.x - 1, ty), Color(roof.darkened(0.25), 0.3), 1.0)
				ty += 5.0
			draw_line(Vector2(body.position.x, ridge), Vector2(body.end.x, ridge), roof.darkened(0.35), 2.2)
			if rng.randf() < 0.5:  # a roof window
				var sk := Rect2(body.position.x + rng.randf_range(10, maxf(11, body.size.x - 30)), body.position.y + 8, 16, 12)
				draw_rect(sk, Color("#3A4A55"))
				draw_rect(sk, roof.darkened(0.45), false, 1.0)
	if rng.randf() < 0.55 and form != "flat":  # a chimney
		var ch := Vector2(body.position.x + rng.randf_range(12, maxf(13, body.size.x - 20)), body.position.y + body.size.y * 0.32)
		draw_rect(Rect2(ch + Vector2(3, 4), Vector2(10, 10)), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(ch, Vector2(10, 10)), Color("#6E625A") if _archetype != ARCHETYPE_NORDIC else Color("#5C5550"))
		draw_rect(Rect2(ch + Vector2(2.5, 2.5), Vector2(5, 5)), Color("#2B2826"))
	# Eaves line.
	draw_rect(rect, Color(INK, 0.55), false, 1.0)


func _draw_tree(at: Vector2, radius: float, colour: Color, rng: RandomNumberGenerator) -> void:
	draw_circle(at + Vector2(radius * 0.35, radius * 0.45), radius, Color(0.03, 0.05, 0.05, 0.3))
	if _archetype == ARCHETYPE_TROPICAL:
		# A palm: fronds radiating from the crown.
		for k in 9:
			var a := TAU * k / 9.0 + rng.randf_range(-0.15, 0.15)
			var tip := at + Vector2.from_angle(a) * radius * rng.randf_range(0.85, 1.1)
			draw_line(at, tip, colour.lerp(Color("#7C8C58"), 0.25), 5.0, true)
			draw_line(at, tip, colour.lightened(0.15), 1.5, true)
		draw_circle(at, 4.0, Color("#6B5A44"))
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
		var at := Vector2(px, p.position.y + 18.0)
		draw_rect(Rect2(at + Vector2(-7, -5) + Vector2(3, 4), Vector2(14, 10)), SHADOW)
		draw_rect(Rect2(at + Vector2(-7, -5), Vector2(14, 10)), Color("#DADBD5"))
		draw_rect(Rect2(at + Vector2(-5, -3), Vector2(10, 3)), Color("#3B6E8C"))
		draw_rect(Rect2(at + Vector2(-7, -5), Vector2(14, 10)), Color(INK, 0.6), false, 1.0)
		px += 560.0
	draw_rect(p, Color(INK, 0.6), false, 1.4)


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
		&"wrench":
			draw_line(at + Vector2(-7, 7), at + Vector2(4, -4), ink, 3.2, true)
			draw_arc(at + Vector2(5.5, -5.5), 4.2, -PI * 0.25, PI * 1.25, 10, ink, 2.6, true)


static func _wobbly_rect(rect: Rect2, _rng: RandomNumberGenerator) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
		rect.position])
