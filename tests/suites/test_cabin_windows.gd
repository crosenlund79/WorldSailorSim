extends RefCounted
## I022, the world beyond the windows and softer water: the Starling 33's
## cabin windows sit in its wall art only, change with where the captain
## stands, which side they face, the heading, the place, the hour and the
## weather; the classic art has none; the other cabins are untouched; the
## water's translucency and the glass tint are separate settings; and what it
## costs to draw. Screenshots: two viewpoints, dusk, night, underway, and the
## deck's water before and after.

const APP_SCENE := preload("res://src/app/app.tscn")

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
	CabinWindows.glass_strength = 0.2
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
## never floor or the space outside the hull.
func _test_data_in_the_walls() -> void:
	var windows := CabinWindows.windows_for(&"starling_33")
	t.check(windows.size() == 6 and windows.filter(func(w: Dictionary) -> bool: return w.side == "port").size() == 3,
		"[windows] the Starling 33 has three windows each side")
	var image := Image.load_from_file("res://assets/vessels/starling_33/illustrated/cabin/cabin_base.png")
	var canvas := Rect2(-560, -200, 1120, 400)
	var scale := Vector2(image.get_width(), image.get_height()) / canvas.size
	var bad: Array[String] = []
	for w in windows:
		var along := Vector2.RIGHT.rotated(deg_to_rad(w.angle))
		var across := along.orthogonal()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = w.at + along * corner.x * (w.length * 0.5 + 1.5) + across * corner.y * (w.thickness * 0.5 + 1.5)
			var pixel := image.get_pixelv(Vector2i(((p - canvas.position) * scale).floor()))
			if pixel.a < 0.9 or pixel.r > 0.35:
				bad.append("%s %s" % [w.at, p])
	t.check(bad.is_empty(), "[windows] every opening (with its frame) lies inside the wall paint: nothing shows through floor or hull (%s)" % [bad])
	t.check(CabinWindows.windows_for(&"arctic_wanderer_26").is_empty() and CabinWindows.windows_for(&"halcyon_40").is_empty(),
		"[windows] the other cabins are left as they are (proof of concept on one cabin)")


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
	CabinWindows.glass_strength = 0.6
	t.check(WaterLook.water_colour(false) == sea, "[water] the window glass tint does not touch the water's own colour")
	CabinWindows.glass_strength = 0.2


func _test_in_the_cabin() -> void:
	await _aboard(&"starling_33", &"interior")
	var area := app.router.current_screen as BoatArea
	var windows := area.get_cabin_windows() if area else null
	if not t.check(windows != null and windows.visible, "[windows] the Starling 33's cabin has its windows"):
		return
	var visual := area.get_node("Visual")
	t.check(windows.get_index() == visual.get_node("CabinBase").get_index() + 1 and windows.get_index() < visual.get_node("FurnitureVisual").get_index(),
		"[windows] drawn right over the wall art and under the furniture (frames and furniture stay in front)")
	t.check(windows.world.get("picture") != null and bool(windows.world.moored), "[windows] moored: the harbour's own art is outside")
	var port: Dictionary = windows.windows[1]
	var starboard: Dictionary = windows.windows[4]
	var aft := windows.view_of(port, Vector2(port.at.x - 200.0, 0))
	var abeam := windows.view_of(port, Vector2(port.at.x, 0))
	var close := windows.view_of(port, Vector2(port.at.x, -110))
	var other := windows.view_of(starboard, Vector2(starboard.at.x, 0))
	t.check(absf(CabinWindows._angle_diff(abeam.centre, 0.0)) < 1.0 and absf(CabinWindows._angle_diff(other.centre, 180.0)) < 1.0,
		"[view] moored heading east: port looks north (%.0f°), starboard south (%.0f°)" % [abeam.centre, other.centre])
	t.check(CabinWindows._angle_diff(aft.centre, abeam.centre) > 20.0, "[view] seen from aft the view turns towards the bow (%.0f° → %.0f°)" % [abeam.centre, aft.centre])
	t.check(close.fov > abeam.fov * 2.0, "[view] up close a window shows a wider view (%.0f° vs %.0f°)" % [close.fov, abeam.fov])
	area.player.position = Vector2(-140, -60)
	await t.frames(3)
	await t.screenshot("i022_windows_view_aft")
	area.player.position = Vector2(-44, -100)
	await t.frames(3)
	await t.screenshot("i022_windows_view_close")
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
	await t.frames(60)
	t.check(median < 1.0, "[performance] one redraw of all six windows: median %.3f ms CPU (max %.3f ms)" % [median, float(samples.back()) / 1000.0])
	t.check(redraws[0] <= 2, "[performance] standing still for 60 frames: %d redraws (only the %d-second refresh)" % [redraws[0], int(CabinWindows.REFRESH_SECONDS)])
	# Dusk and night.
	await _aboard(&"starling_33", &"interior", 18.7)
	(app.router.current_screen as BoatArea).player.position = Vector2(-60, -100)
	await t.frames(4)
	await t.screenshot("i022_windows_dusk")
	await _aboard(&"starling_33", &"interior", 22.5)
	windows = (app.router.current_screen as BoatArea).get_cabin_windows()
	t.check(float(windows.world.daylight) < 0.05, "[time] at night the windows know it is night")
	(app.router.current_screen as BoatArea).player.position = Vector2(-60, -100)
	await t.frames(4)
	await t.screenshot("i022_windows_night")
	# Underway: open sea, the view turns with the heading.
	await _aboard(&"starling_33", &"interior", 9.0, true)
	windows = (app.router.current_screen as BoatArea).get_cabin_windows()
	var heading := Simulation.get_current_heading()
	var seen := windows.view_of(windows.windows[1], Vector2(windows.windows[1].at.x, 0))
	t.check(windows.world.get("picture") == null and absf(CabinWindows._angle_diff(seen.centre, heading - 90.0)) < 1.0,
		"[view] underway: open sea, the port windows look out at the heading −90° (%.0f°, heading %.0f°)" % [seen.centre, heading])
	(app.router.current_screen as BoatArea).player.position = Vector2(-60, 100)
	await t.frames(4)
	await t.screenshot("i022_windows_underway")
	# Classic art: no openings in its walls, so no windows.
	SettingsManager.set_art_style(SettingsManager.ART_CLASSIC)
	await t.frames(2)
	t.check(not windows.visible, "[windows] with the classic artwork the windows are not shown")
	SettingsManager.set_art_style(SettingsManager.ART_ILLUSTRATED)
	await t.frames(2)
	t.check(windows.visible, "[windows] back with the illustrated art")


func _test_other_cabins() -> void:
	for vessel: StringName in [&"arctic_wanderer_26", &"petrel_36", &"halcyon_40"]:
		await _aboard(vessel, &"interior")
		var area := app.router.current_screen as BoatArea
		t.check(area != null and area.get_cabin_windows() == null and area.player != null,
			"[windows] %s: cabin unchanged, no windows node" % vessel)


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
