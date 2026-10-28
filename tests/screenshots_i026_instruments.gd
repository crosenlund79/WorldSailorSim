extends Node
## I026 stage 03, marine electronics: rendered evidence from the running game.
## The HUD before and after (run --only=00 on the stage's starting commit
## for the "before"), the three instrument packages underway by day and by
## night, in the cabin, each focused instrument view, the focused
## chartplotter, the cockpit electronics at the helm of every boat, and the
## chandlery's Electronics section. Run rendered (Xvfb + software OpenGL):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/screenshots_i026_instruments.tscn -- [--out=DIR] [--only=PREFIX]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var out := "res://docs/screenshots/i026/instruments"
var only := ""


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(6)


func _wanted(file_name: String) -> bool:
	return only == "" or file_name.begins_with(only)


func _shot(file_name: String) -> void:
	app.toasts.clear()
	await get_tree().create_timer(0.7).timeout
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, file_name])
	print("SHOT %s" % file_name)


func _set_local_hour(hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	var geo := GameSession.get_vessel_position()
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - geo.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _wind(kn: float) -> void:
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(220.0, kn)
	WeatherModel.get_default().clear_cache()


func _show(area: StringName) -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(area, &"start")
	app._show_current_boat_area()
	await _idle()
	var screen := app.router.current_screen as BoatArea
	var lighting := screen.get_node_or_null("Lighting")
	if lighting:
		lighting._weather_at = -INF
		lighting.update_now()
	var sea := screen.get_node_or_null("SeaSurface") as SeaSurface
	if sea:
		sea._sample()
		for key: String in sea._target:
			sea.set(key, sea._target[key])
	app.toasts.clear()
	return screen


## Fits `package_id` (owning it first) to the boat aboard.
func _fit(package_id: String) -> void:
	GameSession.get_instruments().add_owned(package_id)
	GameSession.fit_instrument_package(package_id)
	await _frames(2)


func _board(vessel: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.vessel_id = vessel
	GameSession.replace_state(state)
	await _frames(2)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	_wind(13.0)
	WeatherFixtures.use([])
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	SettingsManager.set_ui_light(SettingsManager.UI_LIGHT_AUTO)
	SettingsManager.set_tips_enabled(false)
	app.start_new_game()
	await _idle()
	app.modals.clear()
	GameSession.test_all_boats_owned = true
	# In harbour: the chandlery and the cockpit electronics on every boat.
	_set_local_hour(11.0)
	if _wanted("40"):
		await _show(SessionState.AREA_EXTERIOR)
		var menu: ChandleryMenu = app.open_chandlery()
		await _frames(4)
		if menu:
			var heading := menu.find_child("ElectronicsHeading", true, false) as Control
			var scroll := menu.find_child("Scroll", true, false) as ScrollContainer
			await _frames(2)
			scroll.scroll_vertical = int(heading.position.y) - 8
			await _shot("40_chandlery_electronics")
		app.modals.clear()
	for spec in [["30_cockpit_starling_classic", &"starling_33", InstrumentPackage.CLASSIC],
			["31_cockpit_petrel_modern", &"petrel_36", InstrumentPackage.MODERN],
			["32_cockpit_halcyon_offshore", &"halcyon_40", InstrumentPackage.OFFSHORE],
			["33_cockpit_arctic_classic", &"arctic_wanderer_26", InstrumentPackage.CLASSIC]]:
		if not _wanted(spec[0]):
			continue
		await _board(spec[1])
		await _fit(spec[2])
		var deck := await _show(SessionState.AREA_EXTERIOR)
		var cockpit := deck.get_node_or_null(^"CockpitInstruments") as CockpitInstruments
		if cockpit == null:
			push_warning("no cockpit instruments on %s" % spec[1])
			continue
		var camera := deck.get_node(^"Camera2D") as Camera2D
		deck.set_process(false)
		camera.position = (cockpit.plotter_at + cockpit.units_at[1]) / 2.0
		camera.zoom = Vector2(4.0, 4.0)
		deck.player.position = cockpit.plotter_at + Vector2(-60, 30)
		await _shot(spec[0])
		deck.set_process(true)
	await _board(&"starling_33")
	await _fit(InstrumentPackage.CLASSIC)
	# Under way.
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	Simulation.advance(5400.0)
	if _wanted("00"):
		_set_local_hour(11.0)
		var deck := await _show(SessionState.AREA_EXTERIOR)
		deck.player.position += Vector2(60, 0)
		await _shot("00_sailing_hud_after")
	for spec in [["01_classic_day", InstrumentPackage.CLASSIC, 11.0], ["02_classic_night", InstrumentPackage.CLASSIC, 23.0],
			["03_modern_day", InstrumentPackage.MODERN, 11.0], ["04_modern_night", InstrumentPackage.MODERN, 23.0],
			["05_offshore_day", InstrumentPackage.OFFSHORE, 11.0], ["06_offshore_night", InstrumentPackage.OFFSHORE, 23.0]]:
		if not _wanted(spec[0]):
			continue
		await _fit(spec[1])
		_set_local_hour(spec[2])
		await _show(SessionState.AREA_EXTERIOR)
		await _shot(spec[0])
	if _wanted("07"):
		await _fit(InstrumentPackage.MODERN)
		_set_local_hour(15.0)
		await _show(SessionState.AREA_INTERIOR)
		await _shot("07_modern_in_the_cabin")
	# The focused views.
	for spec in [["10_view_classic", InstrumentPackage.CLASSIC, 11.0, ""], ["11_view_modern", InstrumentPackage.MODERN, 11.0, ""],
			["12_view_offshore", InstrumentPackage.OFFSHORE, 11.0, ""], ["13_view_offshore_night_navigation", InstrumentPackage.OFFSHORE, 23.0, "navigation"],
			["14_view_classic_night_weather", InstrumentPackage.CLASSIC, 23.0, "weather"], ["15_view_offshore_weather", InstrumentPackage.OFFSHORE, 11.0, "weather"],
			["16_view_offshore_sailing", InstrumentPackage.OFFSHORE, 11.0, "sailing"], ["17_view_modern_night", InstrumentPackage.MODERN, 23.0, ""]]:
		if not _wanted(spec[0]):
			continue
		await _fit(spec[1])
		_set_local_hour(spec[2])
		await _show(SessionState.AREA_EXTERIOR)
		if spec[3] != "":
			if spec[1] == InstrumentPackage.CLASSIC:
				InstrumentView.lcd_page = spec[3]
			else:
				GameSession.set_instrument_page(0, spec[3])
		app.open_instruments()
		await _frames(3)
		await _shot(spec[0])
		InstrumentView.lcd_page = "route"
		GameSession.set_instrument_page(0, "overview")
		app.modals.clear()
	for spec in [["20_plotter_classic", InstrumentPackage.CLASSIC, 11.0], ["21_plotter_offshore_night", InstrumentPackage.OFFSHORE, 23.0],
			["22_plotter_modern", InstrumentPackage.MODERN, 15.0]]:
		if not _wanted(spec[0]):
			continue
		await _fit(spec[1])
		_set_local_hour(spec[2])
		await _show(SessionState.AREA_EXTERIOR)
		var view: PlotterView = app.open_chartplotter()
		var guard := 0
		while view and not view.plotter.is_raster_ready() and guard < 400:
			guard += 1
			await _frames(1)
		await _shot(spec[0])
		app.modals.clear()
	print("I026 INSTRUMENT SHOTS DONE")
	get_tree().quit()
