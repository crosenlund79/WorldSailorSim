class_name BoatArea
extends Node2D
## One physical area of the boat (cabin or deck): places the player, routes
## interactions and reports what the UI should show.
##
## The area is presentation only. It reads the player's spawn or position
## from GameSession, writes the position back while active, and turns
## interactions into requests (signals) that the application flow handles.
## It never changes scenes or opens UI itself.
##
## Scene structure (every vessel, deck and cabin alike):
##   Visual   - the art (VesselVisual: procedural slots or sprites), no physics
##   Layout   - gameplay: Collision, Stations (interactables), SpawnPoints,
##              CompanionSpots (cabin) and SailMarkers (deck)
##   SailRig  - the dynamic sails (deck), Companion (cabin), Player, Camera2D
## On entering, the active vessel's visual profile is applied to Visual and
## the SailRig, so replacing art never touches the layout.

signal area_change_requested(area: StringName, spawn_point: StringName)
signal chart_requested
## The framed world map in the cabin: the Dreamer's Map (Iteration 17).
signal world_map_requested
signal sleep_requested
signal helm_requested
signal boatyard_requested
## The provisions station (cabin) was used.
signal provisions_requested
## The work station (cabin) was used.
signal work_requested
## The grocery store on the pontoon (deck, in harbour) was used.
signal grocery_requested
## The Go Ashore sign on the pontoon (Iteration 12) was used.
signal go_ashore_requested
## The fishing rod on the stern rail (Iteration 13) was used.
signal fishing_requested
## The windlass on the foredeck (Iteration 13) was used.
signal anchor_requested
## The galley stove in the cabin (Iteration 13) was used.
signal cooking_requested
## The trophy board in the cabin (Iteration 13) was used.
signal trophies_requested
signal message_requested(text: String)
## Prompt text for the focused interactable, or "" when nothing is in range.
signal interaction_prompt_changed(prompt: String)

@export var area_id: StringName
## Where the companionway in this area leads.
@export var companionway_target_area: StringName
@export var companionway_target_spawn: StringName
## Used when the requested spawn point does not exist in this area.
@export var default_spawn: StringName = &"start"
## Rectangle (in this node's coordinates) a restored player position must lie
## in; positions outside it fall back to the default spawn point.
@export var walkable_bounds := Rect2(-500, -200, 1000, 400)
@export var ambience: AudioStream
@export var interaction_sound: AudioStream
## Optional node shown only while the boat lies in a port (e.g. the pontoon),
## and a label inside it that names the port.
@export var mooring: Node2D
@export var mooring_label: Label

## Underway the deck camera eases out a little (0.100b) so more of the sea
## around the boat shows; in harbour it is as framed in the scene. Cosmetic.
const UNDERWAY_ZOOM_FACTOR := 0.86
const ZOOM_TRANSITION_S := 1.8

const HELM_PROMPT_IN_PORT := "Take the helm"
const HELM_PROMPT_UNDERWAY := "Check sail configuration"
## The cabin's hat hook (station id `hat`), by hat state.
const HAT_PROMPTS := {
	HatState.STORED: "Put on captain's hat",
	HatState.WORN: "Hang up captain's hat",
	HatState.CARRIED: "Hang up captain's hat",
	HatState.LOST: "Look at the empty hat hook",
}

var _leaving := false
## The deck camera's zoom as framed in the scene (the harbour view).
var _base_zoom := Vector2.ONE
var _base_camera_position := Vector2.ZERO
var _base_walkable_bounds := Rect2()
var _camera_ready := false
var _logged_course_view := false
var _zoom_tween: Tween
## Presentation only (tests): draw the deck as if sailing this heading.
var view_heading_override := NAN
## The course view's smallest zoom (keeps the deck readable at N/S headings)
## and the screen room kept free for the HUD (pixels, both sides together).
const COURSE_MIN_ZOOM := 0.78
const COURSE_SCREEN_MARGIN := Vector2(120.0, 300.0)
## Walking ashore over the gangplank (decks in harbour, Iteration 12).
var _shore: ShoreAccess
## Shore stations, by facility id (grocery, boatyard, go_ashore).
var _shore_stations := {}
## How fast the camera follows the player ashore and back (per second).
const SHORE_CAMERA_RATE := 3.5
## The boat this area belongs to (its art follows the Artwork setting).
var _vessel: VesselDefinition
var _table_mug_station: Interactable

@onready var player: Player = $Player
@onready var _spawn_points: Node2D = $Layout/SpawnPoints


func _ready() -> void:
	_vessel = GameSession.get_vessel_definition()
	apply_visual_profile(_vessel.get_active_visual_profile())
	SettingsManager.art_style_changed.connect(_on_art_style_changed)
	_setup_shore()
	_setup_aboard_gear()
	_place_player()
	player.focus_changed.connect(_on_player_focus_changed)
	_setup_second_companion()  # I025: a node for a second companion (before the connections below)
	for node in find_children("*", "Interactable", true, false):
		(node as Interactable).interacted.connect(_on_interacted)
	AudioManager.play_ambience(ambience)
	show_condition()
	GameSession.condition_changed.connect(func(_percent: float) -> void: show_condition())
	_update_mooring()
	GameSession.voyage_started.connect(_update_mooring)
	GameSession.voyage_arrived.connect(_on_voyage_arrived)
	_setup_harbour_dressing()
	_setup_water_life()
	_setup_water_look()
	_setup_cabin_windows()
	CabinSeaBackdrop.attach(self)  # I025: the faded sea outside the cabin (nothing on deck)
	_setup_anchor_ambience()
	_setup_camera()
	_setup_lighting()
	_setup_overhead()
	_setup_laptop()
	_setup_dock_encounter()
	_setup_pair_moments()
	_setup_hat_hook()
	_update_hat_station()
	_resolve_highlights.call_deferred()
	GameSession.hat_changed.connect(func(_status: StringName) -> void: _update_hat_station())
	GameSession.state_replaced.connect(_update_hat_station)
	GameSession.hat_lost.connect(_on_hat_lost)


## Shows the vessel's art: sprites where the profile has them, procedural
## placeholder art elsewhere.
func apply_visual_profile(profile: VesselVisualProfile) -> void:
	var visual := get_node_or_null("Visual") as VesselVisual
	if visual:
		visual.apply(profile)
	var rig := get_node_or_null("SailRig") as SailRig
	if rig:
		rig.apply_profile(profile)
		rig.set_cloth(GameSession.get_sail_cloth())
	update_fenders()


## Fenders out in harbour, stowed underway (Iteration 17, FenderStowage).
## Returns how many fenders the deck art shows when they are out.
func update_fenders() -> int:
	if area_id != SessionState.AREA_EXTERIOR or not is_inside_tree():
		return 0
	return FenderStowage.apply(get_node_or_null("Visual") as VesselVisual, not GameSession.is_underway())


func are_fenders_out() -> bool:
	return not GameSession.is_underway()


## The illustrated harbour (art only) on the deck's mooring, if it has one.
func _setup_harbour_dressing() -> void:
	if mooring == null:
		return
	var dressing := HarbourDressing.new()
	dressing.name = "HarbourDressing"
	mooring.add_child(dressing)
	# Right above the pontoon's base shape, under the harbour's name sign.
	var pontoon := mooring.get_node_or_null(^"Pontoon")
	if pontoon:
		mooring.move_child(dressing, pontoon.get_index() + 1)
	dressing.setup(self, mooring)


## Softer water (I022, WaterLook): the water's colour, a little lighter in
## shallow water, and faint sandy patches (ShallowWater) when moored or at
## anchor, over the water and under the crests.
func _setup_water_look() -> void:
	var water := get_node_or_null(^"Surroundings/Water") as Polygon2D
	if water == null:
		return
	_recolour_water()
	GameSession.voyage_started.connect(_recolour_water)
	GameSession.voyage_arrived.connect(_on_arrived_recolour_water)
	GameSession.anchor_changed.connect(_recolour_water)
	var shallows := ShallowWater.new()
	shallows.name = "ShallowWater"
	water.add_child(shallows)  # over the water, still under WaterLife (its next sibling)


func _recolour_water() -> void:
	var water := get_node_or_null(^"Surroundings/Water") as Polygon2D
	if water:
		water.color = WaterLook.water_colour(WaterLook.is_shallow())


func _on_arrived_recolour_water(_port: StringName) -> void:
	_recolour_water()


## The world beyond the cabin windows (I022, CabinWindows): in the cabins
## that have windows in their illustrated art, right above the cabin's wall
## art and under the furniture.
func _setup_cabin_windows() -> void:
	if area_id != SessionState.AREA_INTERIOR:
		return
	var visual := get_node_or_null(^"Visual") as VesselVisual
	var base := visual.get_slot(&"CabinBase") if visual else null
	if base == null:
		return
	var windows := CabinWindows.new()
	windows.name = "CabinWindows"
	if not windows.setup(self, _vessel.id):
		windows.free()
		return
	base.add_sibling(windows)
	_update_cabin_windows()


## The windows belong to the illustrated cabin art (their openings are in
## its walls), so they show only with it.
func _update_cabin_windows() -> void:
	var windows := get_node_or_null(^"Visual/CabinWindows") as CabinWindows
	var visual := get_node_or_null(^"Visual") as VesselVisual
	if windows and visual:
		windows.visible = visual.profile != null and not visual.profile.procedural_only and visual.profile.get_texture(&"CabinBase") != null


func get_cabin_windows() -> CabinWindows:
	return get_node_or_null(^"Visual/CabinWindows") as CabinWindows


## The animated water (art only) on decks, over the water, under everything else.
func _setup_water_life() -> void:
	var surroundings := get_node_or_null(^"Surroundings")
	var water := surroundings.get_node_or_null(^"Water") if surroundings else null
	if water == null:
		return
	if water is Polygon2D:
		var sea := SeaSurface.new()
		add_child(sea)
		sea.setup(self, water)
	var life := WaterLife.new()
	life.name = "WaterLife"
	surroundings.add_child(life)
	surroundings.move_child(life, water.get_index() + 1)
	life.setup(self)


## Life at anchor (0.102b): the time-of-day tint while settled at anchor,
## and below deck the cabin lamp's glow (over the saloon and the galley).
func _setup_anchor_ambience() -> void:
	var ambience := AnchorAmbience.new()
	ambience.name = "AnchorAmbience"
	if area_id == SessionState.AREA_INTERIOR:
		var cabin := _cabin_polygon()
		if cabin.size() >= 3:
			var bounds := Rect2(cabin[0], Vector2.ZERO)
			for p in cabin:
				bounds = bounds.expand(p)
			var centre := bounds.get_center()
			ambience.lamps.append(Vector3(centre.x, centre.y, minf(bounds.size.x, bounds.size.y) * 0.55))
		var stove := get_gear("GalleyStove")
		if stove:
			ambience.lamps.append(Vector3(stove.position.x, stove.position.y, 46.0))
	add_child(ambience)


func get_anchor_ambience() -> AnchorAmbience:
	return get_node_or_null(^"AnchorAmbience") as AnchorAmbience


func get_water_life() -> WaterLife:
	return get_node_or_null(^"Surroundings/WaterLife") as WaterLife


# --- Camera -------------------------------------------------------------------------

## Decks (the areas with a mooring) frame wider underway. The camera stays
## fixed on the boat; only its zoom changes, eased, so nothing jitters.
func _setup_camera() -> void:
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera == null or mooring == null:
		return
	_base_zoom = camera.zoom
	_base_camera_position = camera.position
	_base_walkable_bounds = _shore.get_boat_bounds() if _shore else walkable_bounds
	_camera_ready = true
	camera.ignore_rotation = false
	camera.zoom = get_target_zoom()
	camera.rotation = get_target_rotation()
	camera.set_meta(&"course_view", is_course_view())
	if is_course_view():
		camera.position = get_course_camera_target(camera.zoom, camera.rotation)
	# Water wide enough to fill a turned view.
	var water := get_node_or_null(^"Surroundings/Water") as Polygon2D
	if water:
		water.polygon = PackedVector2Array([Vector2(-2600, -2600), Vector2(2600, -2600), Vector2(2600, 2600), Vector2(-2600, 2600)])
	GameSession.voyage_course_changed.connect(_update_camera)
	SettingsManager.course_view_changed.connect(func(_enabled: bool) -> void: _update_camera())
	GameSession.voyage_started.connect(_update_camera)
	GameSession.voyage_arrived.connect(func(_port: StringName) -> void: _update_camera())
	GameSession.state_replaced.connect(_update_camera)
	GameSession.rescued.connect(func(_info: Dictionary) -> void: _update_camera())


## The zoom the deck camera settles on: wider while underway; in the course
## view also small enough for the turned boat to fit, but never below
## COURSE_MIN_ZOOM, so the deck stays readable when sailing north or south.
func get_target_zoom() -> Vector2:
	var zoom := _base_zoom * (UNDERWAY_ZOOM_FACTOR if GameSession.is_underway() else 1.0)
	if not is_course_view():
		return zoom
	var bounds := _boat_view_bounds()
	var turned := Rect2(bounds.position.rotated(-get_target_rotation()), Vector2.ZERO)
	for corner in [Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		turned = turned.expand(corner.rotated(-get_target_rotation()))
	var room := get_viewport_rect().size - COURSE_SCREEN_MARGIN
	var fit := minf(room.x / turned.size.x, room.y / turned.size.y)
	return Vector2.ONE * clampf(minf(zoom.x, fit), minf(COURSE_MIN_ZOOM, zoom.x), zoom.x)


## The course view (Iteration 12): underway, with the setting on, the deck
## turns so the bow points along the course on screen, north up.
func is_course_view() -> bool:
	return _camera_ready and SettingsManager.get_course_view() and GameSession.is_underway()


## The camera rotation for the course view (0 otherwise): the bow (+x) drawn
## towards the heading's octant (Iteration 13), with north up.
func get_target_rotation() -> float:
	return deg_to_rad(90.0 - get_view_octant() * OCTANT_DEG) if is_course_view() else 0.0


## The eight directions the boat is drawn in (Iteration 13): N, NE, E, … NW.
const OCTANT_DEG := 45.0
## A new octant is taken only this far past the halfway line between two, so
## a course wavering around 22.5° does not flip the view back and forth.
const OCTANT_HYSTERESIS_DEG := 8.0
const OCTANT_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
var _octant := -1
var _logged_octant := -1
## The (course view, octant) the camera was last turned for. The heading also
## changes without any signal (the autopilot passing a waypoint, a steering
## change taking effect at the next evaluation), so _process compares it each
## frame (Iteration 17: the deck no longer stays drawn on an old heading).
var _applied_view := Vector2i(-1, -1)


func _view_key() -> Vector2i:
	var course := is_course_view()
	return Vector2i(int(course), get_view_octant() if course else -1)


## The octant the deck is drawn in (0 = north … 7 = north-west), from the
## heading with hysteresis. Presentation only: the simulation keeps the full
## heading.
func get_view_octant() -> int:
	_octant = octant_for(get_view_heading(), _octant)
	return _octant


## The octant for `heading` (degrees), keeping `previous` (or -1) while the
## heading is within OCTANT_HYSTERESIS_DEG past its edge.
static func octant_for(heading: float, previous := -1, hysteresis := OCTANT_HYSTERESIS_DEG) -> int:
	var h := fposmod(heading, 360.0)
	var nearest := posmod(roundi(h / OCTANT_DEG), 8)
	if previous < 0 or previous == nearest:
		return nearest
	var off := absf(wrapf(h - previous * OCTANT_DEG, -180.0, 180.0))
	return previous if off <= OCTANT_DEG / 2.0 + hysteresis else nearest


## The heading the deck is drawn for: the course of the voyage leg (a test can
## set view_heading_override to see the deck on any heading; presentation
## only, the simulation never reads it).
func get_view_heading() -> float:
	return view_heading_override if not is_nan(view_heading_override) else Simulation.get_current_heading()


## The boat's own extent (the deck without the shore), with room ahead for
## the spinnaker while it flies.
func _boat_view_bounds() -> Rect2:
	var bounds := _base_walkable_bounds.grow(30.0)
	var rig := get_node_or_null(^"SailRig") as SailRig
	if rig and rig.spinnaker_amount > 0.5:
		bounds.end.x += 140.0
	return bounds


func _update_camera() -> void:
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera == null or not is_inside_tree():
		return
	var course := is_course_view()
	_applied_view = _view_key()
	camera.set_meta(&"course_view", course)
	if course:
		camera.offset.x = 0.0
	var zoom := get_target_zoom()
	camera.rotation = wrapf(camera.rotation, -PI, PI)
	var rotation_target := camera.rotation + wrapf(get_target_rotation() - camera.rotation, -PI, PI)
	var center := _boat_view_bounds().get_center() if course else _base_camera_position
	if _zoom_tween:
		_zoom_tween.kill()
	if camera.zoom.is_equal_approx(zoom) and is_equal_approx(camera.rotation, rotation_target) and (course or camera.position.is_equal_approx(center)):
		return
	_zoom_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel()
	_zoom_tween.tween_property(camera, "zoom", zoom, ZOOM_TRANSITION_S)
	_zoom_tween.tween_property(camera, "rotation", rotation_target, ZOOM_TRANSITION_S)
	if not course:
		_zoom_tween.tween_property(camera, "position", center, ZOOM_TRANSITION_S)
	_zoom_tween.chain().tween_callback(func() -> void: camera.rotation = wrapf(camera.rotation, -PI, PI))
	if course and not _logged_course_view:
		_logged_course_view = true
		SessionLog.write("course_view", {"heading": roundi(get_view_heading()), "octant": OCTANT_NAMES[get_view_octant()],
			"zoom": snappedf(zoom.x, 0.01), "min_zoom_reached": zoom.x <= COURSE_MIN_ZOOM + 0.001})
	if course and get_view_octant() != _logged_octant:
		_logged_octant = get_view_octant()
		SessionLog.write("view_octant", {"heading": snappedf(get_view_heading(), 0.1), "octant": OCTANT_NAMES[_logged_octant]})


## What is above head height on deck (Iteration 17): the rigging, boom and
## sails are drawn above the captain (z OVERHEAD_Z) instead of under them; the
## sail rig turns see-through while the captain is under it (SailRig).
const OVERHEAD_Z := 20
const OVERHEAD_NODES := ["Visual/RiggingVisual", "Visual/BoomVisual", "Visual/MainSailVisual", "Visual/HeadSailVisual",
	"Visual/SpinnakerVisual", "SailRig"]


func _setup_overhead() -> void:
	if area_id != SessionState.AREA_EXTERIOR:
		return
	for path: String in OVERHEAD_NODES:
		var node := get_node_or_null(NodePath(path)) as CanvasItem
		if node:
			node.z_as_relative = false
			node.z_index = OVERHEAD_Z
	var rig := get_node_or_null(^"SailRig") as SailRig
	if rig:
		rig.see_through = player


## The Captain's laptop on the cabin table (I024): the work station opens it
## (renown, publications, achievements, remote work).
func _setup_laptop() -> void:
	var station := get_node_or_null(^"Layout/Stations/Work") as Interactable
	if station == null:
		return
	station.prompt = Loc.t("Use the laptop")
	LaptopProp.place(self, station)


func get_laptop() -> LaptopProp:
	return get_node_or_null(^"Laptop") as LaptopProp


## Day and night, lamps and soft shadows (Iteration 17, BoatLighting).
func _setup_lighting() -> void:
	var lighting := BoatLighting.new()
	add_child(lighting)
	lighting.setup(self)
	GameSession.state_replaced.connect(lighting.update_now)
	if area_id == SessionState.AREA_EXTERIOR:
		var weather := WeatherVisuals.new()
		add_child(weather)
		weather.setup(self)
		# The anchor ball, rode and buoy (Iteration 18).
		var signals := AnchorSignals.new()
		add_child(signals)
		signals.setup(self, lighting)
		_setup_deck_companion()


func get_lighting() -> BoatLighting:
	return get_node_or_null(^"Lighting") as BoatLighting


## The companion's deck presence (Iteration 18): safe resting places worked
## out from this boat's layout, and a ShipCompanion that shows while the
## companion is up here.
func _setup_deck_companion() -> void:
	var spots := DeckCompanionSpots.new()
	get_node(^"Layout").add_child(spots)
	spots.setup(self)
	for slot in CompanionState.MAX_COMPANIONS:
		var companion := ShipCompanion.new()
		companion.name = "Companion" if slot == 0 else "Companion%d" % (slot + 1)
		companion.slot = slot
		companion.on_deck = true
		companion.deck_spots = spots
		companion.spots_path = ^"../Layout/DeckCompanionSpots"
		add_child(companion)
		# Made after _ready connected the scene's interactables: connect its "Pet"
		# here, or E would focus the cat on deck and do nothing (fix after 0.105b).
		if companion.interactable and not companion.interactable.interacted.is_connected(_on_interacted):
			companion.interactable.interacted.connect(_on_interacted)
	if get_lighting():
		get_lighting().add_contact_shadows()


## I025: the cabin scene has one ShipCompanion ("Companion", slot 0); a
## second companion gets its own node beside it ("Companion2", slot 1). Both
## show nothing while their slot is empty.
func _setup_second_companion() -> void:
	var first := get_node_or_null(^"Companion") as ShipCompanion
	if first == null or first.on_deck or has_node(^"Companion2"):
		return
	var second := ShipCompanion.new()
	second.name = "Companion2"
	second.slot = 1
	second.spots_path = first.spots_path
	first.add_sibling(second)


## The companion nodes of this area (both slots), first first.
func get_companion_nodes() -> Array[ShipCompanion]:
	var out: Array[ShipCompanion] = []
	for path in [^"Companion", ^"Companion2"]:
		var node := get_node_or_null(path) as ShipCompanion
		if node:
			out.append(node)
	return out


func get_deck_companion() -> ShipCompanion:
	var companion := get_node_or_null(^"Companion") as ShipCompanion
	return companion if companion and companion.on_deck else null


func get_anchor_signals() -> AnchorSignals:
	return get_node_or_null(^"AnchorSignals") as AnchorSignals


func get_weather_visuals() -> WeatherVisuals:
	return get_node_or_null(^"WeatherVisuals") as WeatherVisuals


func get_harbour_dressing() -> HarbourDressing:
	return mooring.get_node_or_null(^"HarbourDressing") as HarbourDressing if mooring else null


## The Artwork setting changed: show the other art (and harbour) at once.
func _on_art_style_changed(_style: StringName) -> void:
	var life := get_water_life()
	if life:
		life.refresh()
	var dressing := get_harbour_dressing()
	if dressing:
		dressing.refresh()
	apply_visual_profile(_vessel.get_active_visual_profile())
	_update_cabin_windows()
	show_condition()
	var provisions := get_node_or_null(^"ProvisionDisplay")
	if provisions and provisions.has_method(&"refresh"):
		provisions.refresh()


## Shows the boat's wear and damage over its art (VesselVisual.set_condition).
func show_condition() -> void:
	var visual := get_node_or_null("Visual") as VesselVisual
	if visual:
		visual.set_condition(GameSession.get_condition(), "%s/%s" % [GameSession.get_vessel_id(), area_id])


## A spawn point's position, or Vector2.INF when it does not exist.
func get_spawn_position(spawn_point: StringName) -> Vector2:
	var marker := _spawn_points.get_node_or_null(NodePath(String(spawn_point))) as Node2D
	return marker.position if marker else Vector2.INF


func _physics_process(_delta: float) -> void:
	if not _leaving:
		GameSession.set_player_position(player.position)
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera:
		player.view_rotation = camera.rotation


## Stops gameplay in this area while a transition away from it runs.
func begin_exit() -> void:
	_leaving = true
	player.set_input_enabled(false)


## The exit did not happen after all (I025: the Captain stayed on deck at the
## companionway question).
func cancel_exit() -> void:
	_leaving = false
	player.set_input_enabled(true)


func _place_player() -> void:
	var position := Vector2.ZERO
	if GameSession.has_player_position() and is_valid_player_position(GameSession.get_player_position()):
		position = GameSession.get_player_position()
	else:
		var marker := _spawn_points.get_node_or_null(NodePath(String(GameSession.get_spawn_point()))) as Node2D
		if marker == null:
			marker = _spawn_points.get_node_or_null(NodePath(String(default_spawn))) as Node2D
		if marker:
			position = marker.position
	player.position = position
	GameSession.set_player_position(position)


## Whether a restored player position (area coordinates: relative to the
## boat, never the world) is somewhere the captain can stand: inside the
## area's bounds and, on deck, inside the hull's lifeline, or on the pontoon
## while it is reachable (Iteration 17). Anything else falls back to the spawn
## point, so a stale or damaged position never puts the captain in the water.
func is_valid_player_position(position: Vector2) -> bool:
	if not walkable_bounds.has_point(position):
		return false
	if _shore and _shore.is_active() and _shore.get_shore_rect().grow(4.0).has_point(position):
		return true
	var lifeline := get_node_or_null(^"Layout/Collision/Lifeline/CollisionPolygon2D") as CollisionPolygon2D
	if lifeline == null:
		return true
	# The lifeline is drawn in its own nodes' coordinates; bring it to the area's.
	var outline := (global_transform.affine_inverse() * lifeline.global_transform) * lifeline.polygon
	return Geometry2D.is_point_in_polygon(position, outline)


## Moves the player to a spawn marker without reloading the scene (waking up
## in the cabin when already there).
func place_player_at_spawn(spawn_point: StringName) -> void:
	var marker := _spawn_points.get_node_or_null(NodePath(String(spawn_point))) as Node2D
	if marker == null:
		return
	player.position = marker.position
	player.velocity = Vector2.ZERO
	GameSession.set_player_position(marker.position)


func _on_interacted(interactable: Interactable, _actor: Node) -> void:
	if _leaving:
		return
	if interactable.interaction_id != &"pet":  # the companion makes its own sound
		AudioManager.play_sfx(interaction_sound)
	match interactable.interaction_id:
		&"companionway":
			begin_exit()
			area_change_requested.emit(companionway_target_area, companionway_target_spawn)
		&"nav_table":
			begin_exit()
			chart_requested.emit()
		&"world_map":
			begin_exit()
			world_map_requested.emit()
		&"bed":
			sleep_requested.emit()
		&"helm":
			helm_requested.emit()
		&"boatyard":
			boatyard_requested.emit()
		&"provisions":
			provisions_requested.emit()
		&"work":
			work_requested.emit()
		&"grocery":
			grocery_requested.emit()
		&"go_ashore":
			go_ashore_requested.emit()
		&"fishing":
			fishing_requested.emit()
		&"anchor":
			anchor_requested.emit()
		&"cook":
			cooking_requested.emit()
		&"trophies":
			trophies_requested.emit()
		&"hat":
			message_requested.emit(GameSession.use_hat_hook())
		&"cup_holder", &"coffee_table":
			if GameSession.is_carrying_coffee() and interactable.interaction_id == &"cup_holder":
				message_requested.emit(GameSession.put_coffee_down())
			elif GameSession.coffee_waits_here():
				message_requested.emit(GameSession.pick_up_coffee())
			else:
				message_requested.emit(Loc.t("The cup holder, just the size of a mug. Make a coffee in the galley."))
		&"pet":
			if GameSession.free_hands() == 0:
				var held := interactable.get_parent() as ShipCompanion
				message_requested.emit(CompanionRemarks.hands_full(CompanionRemarks.identity(held.get_companion_state() if held else null)))
				return
			var companion := interactable.get_parent() as ShipCompanion
			if companion:
				companion.pet()
				SessionLog.write("companion_pet", {"kind": String(companion.kind), "pose": String(companion.pose)})
				# A kind word now and then (not every time: see ShipCompanion.take_remark).
				var remark := companion.take_remark()
				if remark != "":
					message_requested.emit(remark)
		_:
			if not interactable.message.is_empty():
				message_requested.emit(interactable.message)
			else:
				push_warning("Interactable '%s' has no behaviour." % interactable.interaction_id)


# --- Docking arrival (Iteration 17) -----------------------------------------------------
# A short presentation after the simulation has already moored the boat: the
# pontoon and harbour glide in alongside while the engine runs, the captain at
# the helm; then harbour play resumes. Presentation only: nothing in the game
# state changes during it (no second arrival, rewards, stores or route
# changes), and any key skips it.

const DOCKING_SECONDS := 2.4
const DOCKING_OFFSET := Vector2(-420.0, 240.0)
signal docking_finished
var _docking: Tween


func is_docking() -> bool:
	return _docking != null and _docking.is_running()


func play_docking_arrival() -> void:
	if mooring == null or area_id != SessionState.AREA_EXTERIOR or not GameSession.is_moored_in_harbour():
		docking_finished.emit()
		return
	place_player_at_spawn(&"start")
	player.set_input_enabled(false)
	# The harbour view straight away (not still turned to the last course).
	_update_camera()
	if _zoom_tween:
		_zoom_tween.custom_step(ZOOM_TRANSITION_S * 2.0)
	var rest := mooring.position
	mooring.position = rest + DOCKING_OFFSET
	mooring.modulate.a = 0.0
	if _shore:
		_shore.visible = false
	_docking = create_tween().set_parallel()
	_docking.tween_property(mooring, "position", rest, DOCKING_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_docking.tween_property(mooring, "modulate:a", 1.0, DOCKING_SECONDS * 0.35)
	_docking.chain().tween_callback(_finish_docking.bind(rest))


func skip_docking() -> void:
	if is_docking():
		_docking.custom_step(DOCKING_SECONDS * 2.0)


func _finish_docking(rest: Vector2) -> void:
	mooring.position = rest
	mooring.modulate.a = 1.0
	if _shore:
		_shore.visible = _shore.is_active()
	if not _leaving:
		player.set_input_enabled(true)
	docking_finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_docking() and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		skip_docking()


func _on_voyage_arrived(_port: StringName) -> void:
	_update_mooring()
	if get_dock_encounter_scene():
		get_dock_encounter_scene().refresh.call_deferred()
	var life := get_water_life()
	if life:
		life.refresh()
	var dressing := get_harbour_dressing()
	if dressing:
		dressing.refresh()


## Shows the pontoon only in port; while underway the boat is at sea. The
## helm offers to set sail in port and to check the sails underway.
func _update_mooring() -> void:
	for node in find_children("*", "Interactable", true, false):
		var interactable := node as Interactable
		if interactable.interaction_id == &"helm":
			interactable.prompt = HELM_PROMPT_UNDERWAY if GameSession.is_underway() else HELM_PROMPT_IN_PORT
		elif interactable.interaction_id in HarbourFacilities.ALL and _shore == null:
			# Without a shore (no pontoon in the scene) the services stay where
			# the scene put them, offered only where the harbour has them.
			_set_station_available(interactable, GameSession.has_facility(interactable.interaction_id))
	_update_shore()
	if player and player.get_focused_interactable():
		interaction_prompt_changed.emit(player.get_focused_interactable().prompt)
	if mooring:
		mooring.visible = not GameSession.is_underway()
	update_fenders()
	if mooring_label and GameSession.get_location():
		mooring_label.text = Loc.t("GUEST PONTOON · %s") % GameSession.get_location().display_name.to_upper()


# --- Ashore (Iteration 12) ----------------------------------------------------------

## Decks with a pontoon get the gangplank and the shore strip. Runs before the
## player is placed, so a position saved ashore is restored.
func _setup_shore() -> void:
	if mooring == null or area_id != SessionState.AREA_EXTERIOR:
		return
	var shore := ShoreAccess.new()
	shore.name = "ShoreAccess"
	add_child(shore)
	var visual := get_node_or_null(^"Visual")
	if visual:
		move_child(shore, visual.get_index() + 1)
	if not shore.setup(self):
		shore.queue_free()
		return
	_shore = shore
	var stations := get_node(^"Layout/Stations")
	for child in stations.get_children():
		var station := child as Interactable
		if station and station.interaction_id in HarbourFacilities.ALL:
			_shore_stations[station.interaction_id] = station
	if not _shore_stations.has(HarbourFacilities.GO_ASHORE):
		var go := Interactable.new()
		go.name = "GoAshore"
		go.interaction_id = HarbourFacilities.GO_ASHORE
		go.prompt = Loc.t("Go ashore")
		go.highlight_target = ^""
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		shape.shape = RectangleShape2D.new()
		go.add_child(shape)
		stations.add_child(go)
		_shore_stations[HarbourFacilities.GO_ASHORE] = go
	# A classic sign label for Go Ashore, like the scenes' grocery and boatyard ones.
	var yard_label := mooring.get_node_or_null(^"BoatyardSign") as Label
	if yard_label and mooring.get_node_or_null(^"GoAshoreSign") == null:
		var go_label := yard_label.duplicate() as Label
		go_label.name = "GoAshoreSign"
		go_label.text = "GO ASHORE"
		mooring.add_child(go_label)
	# The harbour's name is painted on the front of the pontoon, beside the
	# gangplank, out of the way of the signs at the back.
	if mooring_label:
		var pontoon := shore.get_pontoon_rect()
		mooring_label.position = Vector2(shore.get_plank_x() + ShoreAccess.SLOT_OFFSETS[0], pontoon.position.y + 24.0) \
			- mooring_label.size / 2.0
	_update_shore()


## In harbour: the gangplank is out and the services the harbour offers stand
## on the pontoon; otherwise the rail is closed and the services are gone.
func _update_shore() -> void:
	if _shore == null:
		return
	var in_port := GameSession.is_moored_in_harbour()
	var was_ashore := _shore.is_off_the_boat(player.position) if player else false
	_shore.set_active(in_port)
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera and not in_port:
		camera.offset.y = 0.0
	if was_ashore and not in_port:
		# Never leave the player on a pontoon that is no longer there.
		place_player_at_spawn(&"from_boatyard")
	var available := GameSession.get_harbour_facilities().get_ids() if in_port else ([] as Array[StringName])
	var slots := _shore.get_service_slots(available.size())
	var index := 0
	for id: StringName in HarbourFacilities.ALL:
		var station := _shore_stations.get(id) as Interactable
		if station == null:
			continue
		var offered := id in available and index < slots.size()
		if offered:
			var slot: Dictionary = slots[index]
			index += 1
			station.position = slot.station
			station.set_meta(&"sign_at", slot.sign)
			var shape := station.get_node(^"CollisionShape2D") as CollisionShape2D
			if not shape.has_meta(&"own_shape"):
				shape.shape = shape.shape.duplicate()
				shape.set_meta(&"own_shape", true)
			(shape.shape as RectangleShape2D).size = Vector2(180, 64)
			shape.position = Vector2.ZERO
		_set_station_available(station, offered)
		var label := mooring.get_node_or_null(NodePath(String(SIGN_LABELS[id]))) as Label
		if label:
			label.visible = offered
			if offered:
				label.position = Vector2(station.get_meta(&"sign_at")) - label.size / 2.0
	var dressing := get_harbour_dressing()
	if dressing:
		dressing.refresh()
	if is_inside_tree():
		_resolve_highlights.call_deferred()


func _set_station_available(station: Interactable, available: bool) -> void:
	station.enabled = available
	station.visible = available
	station.monitorable = available
	if not available:
		station.set_focused(false)


func get_shore_access() -> ShoreAccess:
	return _shore


## The animal on the dock (I025): shown on decks with a shore.
func _setup_dock_encounter() -> void:
	if _shore == null:
		return
	var scene := DockEncounterScene.new()
	scene.name = "DockEncounter"
	add_child(scene)
	scene.setup(self, _shore)


## Two companions now and then notice each other (I025).
func _setup_pair_moments() -> void:
	if get_companion_nodes().size() < 2:
		return
	var moments := PairMoments.new()
	moments.name = "PairMoments"
	add_child(moments)
	moments.setup(self)


func get_pair_moments() -> PairMoments:
	return get_node_or_null(^"PairMoments") as PairMoments


func get_dock_encounter_scene() -> DockEncounterScene:
	return get_node_or_null(^"DockEncounter") as DockEncounterScene


## The shore station for a facility (tests), or null.
func get_shore_station(facility: StringName) -> Interactable:
	return _shore_stations.get(facility) as Interactable


func _process(delta: float) -> void:
	if _camera_ready and not _leaving and _view_key() != _applied_view:
		_update_camera()
	_follow_in_course_view(delta)
	if _shore == null or not _shore.is_active() or _leaving:
		return
	_shore.update_player(player.position)
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera == null:
		return
	camera.offset.y = lerpf(camera.offset.y, get_shore_camera_target(), 1.0 - exp(-SHORE_CAMERA_RATE * delta))


## In the course view the camera follows the captain along the turned boat
## (Iteration 13), so on a north or south course, when the whole boat does not
## fit at a readable zoom, the part of the deck they stand on is always in
## view. It never shows more water past the boat's ends than needed.
func _follow_in_course_view(delta: float) -> void:
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera == null or not camera.get_meta(&"course_view", false) or _leaving:
		return
	var target := get_course_camera_target(camera.zoom, camera.rotation)
	camera.position = camera.position.lerp(target, 1.0 - exp(-COURSE_FOLLOW_RATE * delta))


## How fast the course view follows the captain (per second).
const COURSE_FOLLOW_RATE := 3.0


## Where the course-view camera aims for `zoom` and `rotation`: the captain,
## kept as far inside the boat as the view allows (the boat's centre along an
## axis where the whole boat fits).
func get_course_camera_target(zoom: Vector2, rotation_rad: float) -> Vector2:
	var bounds := _boat_view_bounds()
	var view := (get_viewport_rect().size - Vector2(0.0, COURSE_SCREEN_MARGIN.y * 0.5)) / zoom / 2.0
	var c := absf(cos(rotation_rad))
	var s_ := absf(sin(rotation_rad))
	# The visible half-extent along the boat's own axes.
	var half := Vector2(c * view.x + s_ * view.y, s_ * view.x + c * view.y)
	var target := Vector2.ZERO
	for axis in 2:
		var lo := bounds.position[axis] + half[axis]
		var hi := bounds.end[axis] - half[axis]
		target[axis] = bounds.get_center()[axis] if lo >= hi else clampf(player.position[axis], lo, hi)
	return target


## Walking ashore, the view glides down so the pontoon and its signs show
## (0 aboard, or when the pontoon is already in view).
func get_shore_camera_target() -> float:
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera == null or _shore == null or not _shore.is_off_the_boat(player.position):
		return 0.0
	var half_height := get_viewport_rect().size.y / 2.0
	var visible_bottom := camera.position.y + (half_height - SHORE_HUD_MARGIN) / camera.zoom.y
	return maxf(_shore.get_pontoon_rect().end.y + 24.0 - visible_bottom, 0.0)


## The mooring's sign label for each shore facility (classic art and text).
const SIGN_LABELS := {&"grocery": "GrocerySign", &"boatyard": "BoatyardSign", &"go_ashore": "GoAshoreSign"}
## Screen pixels at the bottom taken by the HUD's prompt and shortcuts.
const SHORE_HUD_MARGIN := 150.0


# --- Aboard gear (Iteration 13) -----------------------------------------------------

## Stations for the fishing rod (stern rail, port quarter) and the windlass
## (foredeck) on decks, and the galley stove and the trophy board in cabins.
## Placed from each boat's own outline and fixtures, so no per-boat offsets;
## each draws its object and highlights it (HighlightProvider).
func _setup_aboard_gear() -> void:
	var stations := get_node_or_null(^"Layout/Stations")
	if stations == null:
		return
	if area_id == SessionState.AREA_EXTERIOR:
		var hull := _lifeline_polygon()
		if hull.size() < 3:
			return
		var helm := stations.get_node_or_null(^"Helm") as Node2D
		var rod_at := rod_holder_position(hull, helm.position if helm else Vector2.INF)
		if rod_at != Vector2.INF:
			var rod := RodHolder.new()
			rod.name = "RodHolder"
			rod.position = rod_at
			_add_gear(rod, RodHolder.outline())
			_add_station(stations, "Fishing", &"fishing", "Fishing rod", rod_at + ROD_STATION_OFFSET, 40.0)
		var windlass_at := windlass_position(hull)
		if windlass_at != Vector2.INF:
			var windlass := Windlass.new()
			windlass.name = "Windlass"
			windlass.position = windlass_at
			windlass.bow = Vector2(_bow_x(hull) - windlass_at.x - 8.0, 0.0)
			_add_gear(windlass, Windlass.outline())
			_add_station(stations, "Anchor", &"anchor", "Anchor", windlass_at + Vector2(-30, 0), 40.0)
		# The coffee cup holder (Cozy Polish): on the starboard coaming by the helm.
		var cup := cup_holder_position(hull, helm.position if helm else Vector2.INF)
		# A deck can place it itself (the Petrel 36's helm stands aft of its
		# wheel, closed in by the wheel and the cockpit bench).
		var spot := get_node_or_null(^"Layout/CupHolderSpot") as Node2D
		if spot and spot.has_node(^"Station"):
			cup = [spot.position, spot.position + (spot.get_node(^"Station") as Node2D).position]
		if cup.size() == 2:
			var holder := CoffeeMug.new()
			holder.name = "CupHolder"
			holder.place = GameSession.COFFEE_HOLDER
			holder.position = cup[0]
			add_child(holder)
			move_child(holder, get_node(^"Layout").get_index())
			var station := _add_station(stations, "CupHolder", &"cup_holder", "Cup holder", cup[1], 20.0)
			station.focus_priority = -1  # never takes E from the helm unless closer
	elif area_id == SessionState.AREA_INTERIOR:
		var provisions := stations.get_node_or_null(^"Provisions") as Node2D
		var galley := _nearest_fixture(provisions.position if provisions else Vector2.ZERO, HighlightResolver.FIXTURES[&"provisions"])
		if provisions and galley:
			var cook_at := provisions.position + Vector2(_clear_offset(provisions.position, STOVE_OFFSETS, stations, STOVE_CLEARANCE), 0.0)
			var stove := GalleyStove.new()
			stove.name = "GalleyStove"
			stove.position = Vector2(cook_at.x, lerpf(provisions.position.y, galley.position.y, 0.85))
			_add_gear(stove, GalleyStove.outline())
			# The station sits at the counter, so the stove is used from in front
			# of it, not from across the cabin (or from beside the cat).
			_add_station(stations, "Cook", &"cook", "Cook a meal or make coffee", Vector2(cook_at.x, lerpf(provisions.position.y, galley.position.y, 0.5)), 24.0)
		_setup_table_mug(stations)
		var hat_spot := get_node_or_null(^"Layout/HatSpot") as Node2D
		var hat := stations.get_node_or_null(^"Hat") as Node2D
		if hat_spot and hat:
			var place := trophy_place(hat_spot.position, hat.position, stations)
			var board := TrophyBoard.new()
			board.name = "TrophyBoard"
			board.position = place[0]
			_add_gear(board, TrophyBoard.outline())
			var station := _add_station(stations, "Trophies", &"trophies", "Look at the trophy board", place[1], 26.0)
			# A board to look at: like the companion, it never takes the E key
			# from a station nearby unless the captain stands closer to it.
			station.focus_priority = -1
		setup_decor()
	if not GameSession.home_changed.is_connected(_on_home_changed):
		GameSession.home_changed.connect(_on_home_changed)


## A boat of your own (I020): the Captain's cabin things shown aboard this
## boat (GameSession.get_cabin_decor), each in a place found from the cabin
## (CabinDecor.place_all), clear of every station, companion spot and fitted
## gear. Rebuilt when the choice changes. Returns the placed things by id.
func setup_decor() -> Dictionary:
	for old in get_children():
		if old is CabinDecor:
			old.queue_free()
	var visual := get_node_or_null(^"Visual")
	if visual:
		for old in visual.get_children():
			if old is CabinDecor:
				old.queue_free()
	var items := GameSession.get_cabin_decor()
	if area_id != SessionState.AREA_INTERIOR or items.is_empty() or not has_node(^"Layout/Stations"):
		return {}
	var avoid: Array[Vector2] = []
	for station in get_node(^"Layout/Stations").get_children():
		if station is Node2D:
			avoid.append((station as Node2D).position)
	var spots := get_node_or_null(^"Layout/CompanionSpots")
	if spots:
		for marker in spots.get_children():
			if marker is Node2D:
				avoid.append((marker as Node2D).position)
	for gear_name in [^"TrophyBoard", ^"GalleyStove", ^"TableMug", ^"Layout/HatSpot"]:
		var gear := get_node_or_null(gear_name) as Node2D
		if gear:
			avoid.append(gear.position)
	var fixtures: Array[PackedVector2Array] = []
	for fixture in get_node(^"Layout/Collision").get_children():
		if fixture is BoatFixture:
			fixtures.append((fixture as BoatFixture).transform * (fixture as BoatFixture).get_points())
	var ordered: Array[String] = []
	for item: Dictionary in HarbourTrades.get_decor():
		if String(item.id) in items:
			ordered.append(String(item.id))
	var placed := CabinDecor.place_all(ordered, _cabin_polygon(), fixtures, avoid)
	for id: String in placed:
		var decor := CabinDecor.new()
		decor.name = "Decor_%s" % id
		decor.item_id = id
		decor.position = placed[id][0]
		decor.side = placed[id][1]
		var base := visual.get_node_or_null(^"CabinBase") if visual else null
		if decor.side == 0.0 and base:
			# The rug lies on the cabin sole, under the furniture.
			visual.add_child(decor)
			visual.move_child(decor, base.get_index() + 1)
		else:
			add_child(decor)
			move_child(decor, get_node(^"Layout").get_index())
	return placed


func _on_home_changed() -> void:
	if not is_inside_tree():
		return
	var rig := get_node_or_null(^"SailRig") as SailRig
	if rig:
		rig.set_cloth(GameSession.get_sail_cloth())
	if area_id == SessionState.AREA_INTERIOR:
		setup_decor()


## A mug set down below stands on the saloon table; its station (picking it
## up) is next to it, active only while the mug is there.
func _setup_table_mug(stations: Node) -> void:
	var table := _nearest_fixture(Vector2.ZERO, ["SaloonTable", "Table"])
	if table == null:
		return
	var size: Vector2 = table.get(&"size") if table.get(&"size") is Vector2 else Vector2(80, 34)
	var mug_at := table.position + Vector2(size.x * 0.25, 0.0)
	var station_at := Vector2.INF
	for side in [-1.0, 1.0]:
		var at := mug_at + Vector2(0.0, side * (size.y / 2.0 + 22.0))
		if _is_clear(at, stations, 30.0):
			station_at = at
			break
	if station_at == Vector2.INF:
		station_at = mug_at + Vector2(0.0, size.y / 2.0 + 22.0)
	var mug := CoffeeMug.new()
	mug.name = "TableMug"
	mug.place = GameSession.COFFEE_TABLE
	mug.position = mug_at
	add_child(mug)
	move_child(mug, get_node(^"Layout").get_index() + 1)
	var station := _add_station(stations, "TableMug", &"coffee_table", "Your coffee", station_at, 22.0)
	station.focus_priority = -1
	station.enabled = GameSession.get_coffee() == GameSession.COFFEE_TABLE
	_table_mug_station = station
	if not GameSession.coffee_changed.is_connected(_on_coffee_changed):
		GameSession.coffee_changed.connect(_on_coffee_changed)


func _on_coffee_changed(place: StringName) -> void:
	if is_instance_valid(_table_mug_station):
		_table_mug_station.enabled = place == GameSession.COFFEE_TABLE


## The cup holder by the helm: [holder, station] on the starboard coaming
## within reach of the helm (scanning a little aft and forward of it), the
## station inboard of the holder and clear of the helm's own; [] when the
## outline has no room.
static func cup_holder_position(hull: PackedVector2Array, helm: Vector2) -> Array[Vector2]:
	if helm == Vector2.INF:
		return []
	for dx in [0.0, -24.0, 24.0, -48.0, 48.0, -72.0, 72.0]:
		var x: float = helm.x + dx
		var edge := starboard_edge(hull, x)
		if edge <= 40.0:
			continue
		var holder := Vector2(x, edge - 14.0)
		var station := holder + Vector2(0.0, -26.0)
		if Geometry2D.is_point_in_polygon(station, hull) and Geometry2D.is_point_in_polygon(holder, hull) \
				and station.distance_to(helm) >= CUP_HELM_CLEARANCE:
			return [holder, station]
	return []


const CUP_HELM_CLEARANCE := 44.0


## The deck's starboard edge at `x`: the most positive y inside the outline.
static func starboard_edge(hull: PackedVector2Array, x: float) -> float:
	var y := 420.0
	while y > 0.0:
		if Geometry2D.is_point_in_polygon(Vector2(x, y), hull):
			return y
		y -= 2.0
	return 0.0


## The stove stands beside the provisions, and the trophy board on the hat's
## wall, at the first of these offsets (along the boat) whose station keeps
## clear of the companion's resting spots and the other stations, so neither
## takes the E key where the cat or dog lies.
const STOVE_OFFSETS: Array[float] = [64.0, 80.0, 96.0, -64.0]
const STOVE_CLEARANCE := 72.0
const TROPHY_OFFSETS: Array[float] = [-140.0, 140.0, -160.0, 160.0, -180.0, 180.0, -200.0, 200.0, 120.0, -120.0]
## Clearances tried in turn: wide first, so the board's station is never
## between the captain and a resting cat or dog when there is room.
const TROPHY_CLEARANCES: Array[float] = [100.0, 90.0, 64.0]


## Where the trophy board hangs and where its station is: [board, station].
## On the hat's wall when there is a clear stretch (TROPHY_OFFSETS from the
## hook); otherwise on the opposite wall, mirrored across the centreline, at
## the clear place nearest the hook's position along the boat.
func trophy_place(hat_spot: Vector2, hat_station: Vector2, stations: Node) -> Array[Vector2]:
	# The station stands a little in front of the board (closer to the wall
	# than the hat's), so it is used from in front of it.
	var inward := (hat_station - hat_spot) * 0.6
	var mirror := Vector2(1.0, -1.0)
	for clearance in TROPHY_CLEARANCES:
		for offset in TROPHY_OFFSETS:
			var board := hat_spot + Vector2(offset, 0.0)
			if _is_clear(board + inward, stations, clearance, [&"Hat"]):
				return [board, board + inward]
		for k in 27:
			var offset := (k + 1) / 2 * 20.0 * (1.0 if k % 2 == 0 else -1.0)
			var board := hat_spot * mirror + Vector2(offset, 0.0)
			if _is_clear(board + inward * mirror, stations, clearance, [&"Hat"]):
				return [board, board + inward * mirror]
	var fallback := hat_spot + Vector2(TROPHY_OFFSETS[0], 0.0)
	return [fallback, fallback + inward]


## True when `at` lies in the cabin and keeps `clearance` from the companion's
## resting spots and from every station (except those named in `ignore`).
func _is_clear(at: Vector2, stations: Node, clearance: float, ignore: Array[StringName] = []) -> bool:
	var hull := _cabin_polygon()
	if hull.size() >= 3 and not Geometry2D.is_point_in_polygon(at, hull):
		return false
	for child in stations.get_children():
		if child is Node2D and not child.name in ignore and (child as Node2D).position.distance_to(at) < clearance:
			return false
	var spots := get_node_or_null(^"Layout/CompanionSpots")
	if spots:
		for marker in spots.get_children():
			if marker is Node2D and (marker as Node2D).position.distance_to(at) < clearance:
				return false
	return true


## The first offset in `offsets` (along x from `from`) whose point lies in
## the cabin and keeps `clearance` from every companion spot and every other
## station (`ignore`: station names that do not count); else the first.
func _clear_offset(from: Vector2, offsets: Array[float], stations: Node, clearance: float) -> float:
	for offset in offsets:
		var at := from + Vector2(offset, 0.0)
		# The station it stands beside (at `from`) does not count.
		if _is_clear(at, stations, clearance, [_station_at(stations, from)]):
			return offset
	return offsets[0]


func _station_at(stations: Node, at: Vector2) -> StringName:
	for child in stations.get_children():
		if child is Node2D and (child as Node2D).position.distance_to(at) < 1.0:
			return child.name
	return &""


func _cabin_polygon() -> PackedVector2Array:
	var shape := get_node_or_null(^"Layout/Collision/Hull/CollisionPolygon2D") as CollisionPolygon2D
	return shape.polygon if shape else PackedVector2Array()


func _add_gear(gear: Node2D, outline: PackedVector2Array) -> void:
	var layout := get_node(^"Layout")
	add_child(gear)
	move_child(gear, layout.get_index())
	var interaction := {&"RodHolder": &"fishing", &"Windlass": &"anchor", &"GalleyStove": &"cook", &"TrophyBoard": &"trophies"}
	gear.add_child(HighlightProvider.create(interaction[gear.name], outline))


func _add_station(stations: Node, node_name: String, id: StringName, prompt_text: String, at: Vector2, radius: float) -> Interactable:
	var station := Interactable.new()
	station.name = node_name
	station.interaction_id = id
	station.prompt = prompt_text
	station.highlight_target = ^""
	station.position = at
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	station.add_child(shape)
	stations.add_child(station)
	return station


func _lifeline_polygon() -> PackedVector2Array:
	var shape := get_node_or_null(^"Layout/Collision/Lifeline/CollisionPolygon2D") as CollisionPolygon2D
	return shape.polygon if shape else PackedVector2Array()


static func _bow_x(hull: PackedVector2Array) -> float:
	var x := -INF
	for p in hull:
		x = maxf(x, p.x)
	return x


static func _stern_x(hull: PackedVector2Array) -> float:
	var x := INF
	for p in hull:
		x = minf(x, p.x)
	return x


## How far the deck reaches to port (negative y) or starboard at `x`.
static func deck_half_width(hull: PackedVector2Array, x: float, side := -1.0) -> float:
	var y := 0.0
	if not Geometry2D.is_point_in_polygon(Vector2(x, 0.0), hull):
		return 0.0
	while y < 400.0 and Geometry2D.is_point_in_polygon(Vector2(x, side * (y + 2.0)), hull):
		y += 2.0
	return y


## The rod holder: on the port rail near the stern (the gangplank is to
## starboard), a little inside the lifeline, with its station clear of the
## helm: the first such spot going forward from the stern.
static func rod_holder_position(hull: PackedVector2Array, helm := Vector2.INF) -> Vector2:
	var stern := _stern_x(hull)
	var x := stern + 30.0
	while x < stern + 260.0:
		var edge := port_edge(hull, x)
		if edge < -40.0:
			var rod := Vector2(x, edge + 22.0)
			var station := rod + ROD_STATION_OFFSET
			if Geometry2D.is_point_in_polygon(station, hull) and (helm == Vector2.INF or station.distance_to(helm) >= ROD_HELM_CLEARANCE):
				return rod
		x += 6.0
	return Vector2.INF


## The rod's station, from the rod holder (inboard of it), and how far it
## keeps from the helm's station.
const ROD_STATION_OFFSET := Vector2(10, 26)
const ROD_HELM_CLEARANCE := 75.0


## The deck's port edge at `x`: the most negative y inside the outline (0
## when the outline does not reach `x`).
static func port_edge(hull: PackedVector2Array, x: float) -> float:
	var y := -420.0
	while y < 0.0:
		if Geometry2D.is_point_in_polygon(Vector2(x, y), hull):
			return y
		y += 2.0
	return 0.0


## The windlass: on the centreline of the foredeck, far enough aft of the
## stem for the deck to be wide enough to stand beside it.
static func windlass_position(hull: PackedVector2Array) -> Vector2:
	var bow := _bow_x(hull)
	var x := bow - 50.0
	while x > bow - 260.0:
		if deck_half_width(hull, x) >= 56.0 and deck_half_width(hull, x, 1.0) >= 56.0:
			return Vector2(x, 0.0)
		x -= 6.0
	return Vector2.INF


func _nearest_fixture(at: Vector2, names: Array) -> Node2D:
	var collision := get_node_or_null(^"Layout/Collision")
	var best: Node2D = null
	var best_distance := INF
	if collision == null:
		return null
	for child in collision.get_children():
		if String(child.name) in names and child is Node2D and (child as Node2D).position.distance_to(at) < best_distance:
			best = child
			best_distance = (child as Node2D).position.distance_to(at)
	return best


## The Iteration 13 gear in this area by name (tests): RodHolder, Windlass,
## GalleyStove or TrophyBoard; null when this area has none.
func get_gear(gear_name: String) -> Node2D:
	return get_node_or_null(NodePath(gear_name)) as Node2D


# --- Captain's hat ------------------------------------------------------------------

## Gives every station the outline of the object it belongs to (Iteration 12;
## see HighlightResolver). Deferred, so harbour and shore art exist first.
func _resolve_highlights() -> void:
	if not is_inside_tree():
		return
	for node in find_children("*", "Interactable", true, false):
		var station := node as Interactable
		if station.highlight_target.is_empty():
			station.set_highlight_outline_global(HighlightResolver.resolve(self, station))


## The cabin's hat hook (art) at Layout/HatSpot, drawn under the player.
func _setup_hat_hook() -> void:
	var spot := get_node_or_null(^"Layout/HatSpot") as Node2D
	if spot == null:
		return
	var hook := HatHook.new()
	hook.name = "HatHook"
	hook.position = spot.position
	add_child(hook)
	move_child(hook, $Layout.get_index())


func get_hat_hook() -> HatHook:
	return get_node_or_null(^"HatHook") as HatHook


## The hat station's prompt follows the hat (put on, hang up, empty hook).
func _update_hat_station() -> void:
	var station := get_node_or_null(^"Layout/Stations/Hat") as Interactable
	if station == null:
		return
	station.prompt = HAT_PROMPTS.get(GameSession.get_hat_status(), Loc.t("Captain's hat"))
	if player and player.get_focused_interactable() == station:
		interaction_prompt_changed.emit(station.prompt)
	# Its outline follows the hook (the hat, or the empty plate); deferred so
	# the hook has seen the change first.
	_resolve_highlights.call_deferred()


## The hat blew away: on deck it is seen tumbling downwind.
func _on_hat_lost(_info: Dictionary) -> void:
	if area_id != SessionState.AREA_EXTERIOR or _leaving:
		return
	var effect := HatBlowAway.new()
	effect.name = "HatBlowAway"
	add_child(effect)
	effect.setup(player.position, wind_direction_on_deck())


## Where the wind blows towards in this deck's coordinates (+x is the bow,
## +y starboard), from the WeatherModel at the boat and the course heading
## (north while moored).
func wind_direction_on_deck() -> Vector2:
	var wind := Simulation.get_weather_at_vessel()
	var heading := get_view_heading() if GameSession.is_underway() else 0.0
	return Vector2.from_angle(deg_to_rad(wind.from_deg + 180.0 - heading))


func _on_player_focus_changed(interactable: Interactable) -> void:
	interaction_prompt_changed.emit(interactable.prompt if interactable else "")
