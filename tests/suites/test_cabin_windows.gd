extends RefCounted
## I022, the cabin windows and softer water: the cabin windows sit in the
## wall art only; the classic art has none; the water's translucency and the
## glass are separate; and what it costs to draw. I025: every boat's cabin has
## windows (portlights, the catamaran's forward saloon windows), and the faded
## sea outside the hull (CabinSeaBackdrop) lies under the whole cabin. The
## Captain's revision of I025: the windows are plain glass - no live view of
## the world outside, nothing redrawn as the Captain walks, only darker glass
## at night. Screenshots: day, night, each boat's cabin, and the deck's water
## before and after.

const APP_SCENE := preload("res://src/app/app.tscn")
## Each cabin's art canvas (VesselVisual.canvas, DEV_GUIDES/VESSEL_ART.md).
const CANVASES := {
	&"arctic_wanderer_26": Rect2(-440, -160, 880, 320), &"starling_33": Rect2(-560, -200, 1120, 400),
	&"halcyon_40": Rect2(-560, -330, 1120, 660), &"petrel_36": Rect2(-600, -320, 1200, 640),
}

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_data_in_the_walls()
	_test_water_look()
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_in_the_cabin()
	await _test_other_cabins()
	await _test_deck_water()
	app.queue_free()
	await t.frames(2)
	WaterLook.translucency = 1.0
	Simulation.auto_advance = true  # as the other suites leave it


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _aboard(vessel: StringName, area: StringName, hour_utc := 8.0, underway := false) -> void:
	GameSession.start_new_session()
	var state := GameSession.get_state_snapshot()
	state.vessel_id = vessel
	state.game_time = state.game_time - fposmod(state.game_time, 86400.0) + hour_utc * 3600.0
	GameSession.replace_state(state)
	if underway:
		GameSession.plan_route_to(&"helsingor")
		GameSession.depart()
	app.modals.clear()
	app._show_current_boat_area()
	await _settle()
	app._on_area_change_requested(area, &"start" if area == &"exterior" else &"from_deck")
	await _settle()


## Every opening lies on the illustrated wall: its corners are wall paint,
## never floor or the space outside the hull, on every boat (I025).
func _test_data_in_the_walls() -> void:
	var windows := CabinWindows.windows_for(&"starling_33")
	t.check(windows.size() == 6 and windows.filter(func(w: Dictionary) -> bool: return w.side == "port").size() == 3,
		"[windows] the Starling 33 has three windows each side")
	for vessel: StringName in CANVASES:
		var list := CabinWindows.windows_for(vessel)
		var port := list.filter(func(w: Dictionary) -> bool: return w.side == "port").size()
		var starboard := list.filter(func(w: Dictionary) -> bool: return w.side == "starboard").size()
		t.check(port >= 2 and starboard >= 2, "[windows] %s has windows on both sides (%d port, %d starboard)" % [vessel, port, starboard])
		var image := Image.load_from_file("res://assets/vessels/%s/illustrated/cabin/cabin_base.png" % vessel)
		var canvas: Rect2 = CANVASES[vessel]
		var scale := Vector2(image.get_width(), image.get_height()) / canvas.size
		var bad: Array[String] = []
		for w in list:
			var frame := CabinWindows.axes(w)
			var along: Vector2 = frame.right
			var across: Vector2 = frame.outward
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p: Vector2 = w.at + along * corner.x * (w.length * 0.5 + 1.5) + across * corner.y * (w.thickness * 0.5 + 1.5)
				var pixel := image.get_pixelv(Vector2i(((p - canvas.position) * scale).floor()))
				if pixel.a < 0.9 or pixel.r > 0.35:
					bad.append("%s %s" % [w.at, p])
		t.check(bad.is_empty(), "[windows] %s: every opening (with its frame) lies inside the wall paint: nothing shows through floor or hull (%s)" % [vessel, bad])
	var forward := CabinWindows.windows_for(&"halcyon_40").filter(func(w: Dictionary) -> bool: return w.side == "forward")
	t.check(forward.size() == 4, "[windows] the Clam 40's saloon has its four big windows looking forward")
	if forward.size() > 0:
		var frame := CabinWindows.axes(forward[0])
		t.check((frame.outward as Vector2).is_equal_approx(Vector2.RIGHT), "[windows] a forward window looks out over the bow")


func _test_water_look() -> void:
	WaterLook.translucency = 0.0
	var before := WaterLook.water_colour(true)
	WaterLook.translucency = 1.0
	var sea := WaterLook.water_colour(false)
	var shallow := WaterLook.water_colour(true)
	t.check(before == WaterLook.DEEP, "[water] translucency 0 is exactly the old water")
	t.check(sea.get_luminance() > before.get_luminance() and shallow.get_luminance() > sea.get_luminance() and shallow.s < before.s,
		"[water] softer: a little lighter and less saturated at sea, more so in harbour (%s → %s / %s)" % [before.to_html(false), sea.to_html(false), shallow.to_html(false)])
	t.check(sea.get_luminance() < 0.35, "[water] still clearly water, not washed out (%.2f)" % sea.get_luminance())
	var glass := CabinWindows.glass_colours(1.0)
	t.check(WaterLook.water_colour(false) == sea and glass[0] != sea, "[water] the window glass has its own colours, apart from the water's")


func _test_in_the_cabin() -> void:
	await _aboard(&"starling_33", &"interior")
	var area := app.router.current_screen as BoatArea
	var windows := area.get_cabin_windows() if area else null
	if not t.check(windows != null and windows.visible, "[windows] the Starling 33's cabin has its windows"):
		return
	var visual := area.get_node("Visual")
	t.check(windows.get_index() == visual.get_node("CabinBase").get_index() + 1 and windows.get_index() < visual.get_node("FurnitureVisual").get_index(),
		"[windows] drawn right over the wall art and under the furniture (frames and furniture stay in front)")
	# Plain glass: nothing of the world outside, nothing that follows the Captain.
	t.check(not "world" in windows and not windows.has_method("view_of"), "[glass] the windows hold no view of the world outside (no sea, harbour, boats or weather)")
	t.check(not windows.get_children().any(func(n: Node) -> bool: return n is SubViewport or n is Camera2D),
		"[glass] no second scene or viewport behind the glass")
	var day := CabinWindows.glass_colours(1.0)
	var night := CabinWindows.glass_colours(0.0)
	t.check(night[0].get_luminance() < day[0].get_luminance() * 0.5 and day[0].get_luminance() > day[1].get_luminance(),
		"[glass] lighter at the outer edge by day, dark glass at night")
	area.player.position = Vector2(-60, -100)
	await t.frames(3)
	await t.screenshot("i025_windows_glass_day")
	# The cost of drawing all six windows (CPU time of one redraw), and how often it happens.
	var samples: Array[int] = []
	for i in 30:
		windows.queue_redraw()
		await t.frames(1)
		samples.append(windows.last_draw_usec)
	samples.sort()
	var median := float(samples[samples.size() / 2]) / 1000.0
	var redraws := [0]
	windows.draw.connect(func() -> void: redraws[0] += 1)
	for spot in [Vector2(-140, -60), Vector2(-44, -100), Vector2(60, 80)]:
		area.player.position = spot
		await t.frames(20)
	t.check(median < 0.5, "[performance] one redraw of all six windows: median %.3f ms CPU (max %.3f ms)" % [median, float(samples.back()) / 1000.0])
	t.check(redraws[0] == 0, "[performance] walking about for 60 frames: %d redraws (the glass does not follow the Captain)" % redraws[0])
	# Night.
	await _aboard(&"starling_33", &"interior", 22.5)
	windows = (app.router.current_screen as BoatArea).get_cabin_windows()
	t.check(windows.daylight < 0.05, "[time] at night the glass is night glass (daylight %.2f)" % windows.daylight)
	(app.router.current_screen as BoatArea).player.position = Vector2(-60, -100)
	await t.frames(4)
	await t.screenshot("i025_windows_glass_night")
	# Classic art: no openings in its walls, so no windows.
	SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
	await t.frames(2)
	t.check(not windows.visible, "[windows] with the classic artwork the windows are not shown")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	await t.frames(2)
	t.check(windows.visible, "[windows] back with the illustrated art")


## I025: every cabin has its windows and the faded sea round the hull.
func _test_other_cabins() -> void:
	for vessel: StringName in [&"arctic_wanderer_26", &"petrel_36", &"halcyon_40"]:
		await _aboard(vessel, &"interior")
		var area := app.router.current_screen as BoatArea
		var windows := area.get_cabin_windows() if area else null
		if not t.check(windows != null and windows.visible and area.player != null, "[windows] %s: the cabin has its windows" % vessel):
			continue
		var visual := area.get_node("Visual")
		t.check(windows.get_index() == visual.get_node("CabinBase").get_index() + 1 and windows.get_index() < visual.get_node("FurnitureVisual").get_index(),
			"[windows] %s: drawn right over the wall art and under the furniture" % vessel)
		var port: Dictionary = windows.windows.filter(func(w: Dictionary) -> bool: return w.side == "port")[0]
		var starboard: Dictionary = windows.windows.filter(func(w: Dictionary) -> bool: return w.side == "starboard")[0]
		t.check((CabinWindows.axes(port).outward as Vector2).dot(CabinWindows.axes(starboard).outward) < -0.8,
			"[windows] %s: port and starboard windows face opposite ways" % vessel)
		await _test_sea_backdrop(area, vessel)
		await t.screenshot("i025_cabin_%s" % vessel)
	await _aboard(&"halcyon_40", &"interior", 9.0, true)
	var screen := app.router.current_screen as BoatArea
	await _test_sea_backdrop(screen, &"halcyon_40")
	await t.screenshot("i025_cabin_halcyon_40_underway")


## The faded sea (CabinSeaBackdrop): only in cabins, under everything (in the
## Backdrop, right above the Darkness), thin along the hull and closing to
## the backdrop outside, darker at night, no cabin lamp on it, the pontoon
## hinted only while moored, cheap.
func _test_sea_backdrop(area: BoatArea, vessel: StringName) -> void:
	var sea := CabinSeaBackdrop.attach(area)
	if not t.check(sea != null and CabinSeaBackdrop.attach(area) == sea, "[sea] %s: the cabin has its faded sea (once)" % vessel):
		return
	var backdrop := area.get_node("Backdrop")
	t.check(sea.get_parent() == backdrop and sea.get_index() == backdrop.get_node("Darkness").get_index() + 1
		and backdrop.get_index() < area.get_node("Visual").get_index(),
		"[sea] %s: drawn above the backdrop's darkness and under all the cabin art, furniture, captain and controls" % vessel)
	t.check(sea.show_at(0, 1.0) < 0.6 and sea.show_at(0, 1.0) > 0.2 and sea.show_at(CabinSeaBackdrop.RINGS.size() - 1, 1.0) == 0.0,
		"[sea] faded: at most %.0f%% of the sea shows by the hull, none at the edge of the fade" % [sea.show_at(0, 1.0) * 100.0])
	t.check(sea.show_at(0, 0.0) < sea.show_at(0, 1.0), "[sea] darker at night than by day")
	t.check(sea.sea_mesh.light_mask == 0 and sea.veil.light_mask == 0, "[sea] the cabin lamps do not light the water outside")
	t.check(sea.sea_mesh.material is ShaderMaterial and sea.sea_mesh.material == sea.surface.material and not sea.sea.visible,
		"[sea] one shader mesh with the deck's own sea (SeaSurface)")
	var walk: Vector2 = area.player.position
	var covered := false
	var arrays := sea.sea_mesh.mesh.surface_get_arrays(0)
	var a: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		if Geometry2D.point_is_inside_triangle(walk, a[idx[i]], a[idx[i + 1]], a[idx[i + 2]]):
			covered = true
			break
	t.check(not covered, "[sea] the sea is not shaded under the cabin floor where the captain stands (%s)" % walk)
	t.check(sea.pontoon.visible == (not GameSession.is_underway() and not GameSession.is_anchored()),
		"[sea] the pontoon is hinted only while moored")
	await t.frames(2)
	var deck := BoatArea.new()
	deck.area_id = SessionState.AREA_EXTERIOR
	t.check(CabinSeaBackdrop.attach(deck) == null, "[sea] never on a deck (no cabin, no sea backdrop)")
	deck.free()


func _test_deck_water() -> void:
	for underway in [false, true]:
		var label := "underway" if underway else "moored"
		for strength in [0.0, 1.0]:
			WaterLook.translucency = strength
			await _aboard(&"starling_33", &"exterior", 10.0, underway)
			var water := (app.router.current_screen as BoatArea).get_node(^"Surroundings/Water") as Polygon2D
			t.check(water.color == WaterLook.water_colour(not underway), "[water] %s, translucency %.0f: the deck water has the WaterLook colour" % [label, strength])
			await t.screenshot("i022_water_%s_%s" % [label, "before" if strength == 0.0 else "after"])
	WaterLook.translucency = 1.0
