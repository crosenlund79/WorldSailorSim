extends Node
## I027, The Cost of the Wind: rendered evidence from the running game.
## Tier 1: beating to windward on deck (sails close-hauled, the wind ahead),
## the instruments with the tack and the progress made good, the
## chartplotter's zigzag, the deck after a tack by hand (K), and the chart.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/screenshots_i027.tscn -- [--out=DIR] [--shots=a,b]
## Uses the test save and settings files; never touches the player's own.

const APP_SCENE := preload("res://src/app/app.tscn")

var app: Node
var out := "res://docs/screenshots/i027/tier1"
var only: Array[String] = []


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--shots="):
			for s in a.trim_prefix("--shots=").split(",", false):
				only.append(s)
	_run.call_deferred()


func _wanted(name: String) -> bool:
	if only.is_empty():
		return true
	for s in only:
		if name.begins_with(s):
			return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(6)


func _shot(name: String, settle := 0.6) -> void:
	await get_tree().create_timer(settle).timeout
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT %s" % name)


func _set_wind(from_deg: float, kn: float) -> void:
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(from_deg, kn)
	WeatherModel.get_default().clear_cache()
	Simulation.invalidate_estimates()


## Five minutes on with the wind kept dead on the nose of the current leg.
func _beat(minutes: int) -> void:
	for i in maxi(minutes / 5, 1):
		var voyage := GameSession.get_voyage()
		if voyage == null:
			return
		_set_wind(voyage.leg_bearing_at(voyage.progress_nm), 13.0)
		Simulation.advance(300.0)


func _deck() -> void:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_cabin")
	app._show_current_boat_area()
	await _idle()
	await get_tree().create_timer(BoatArea.ZOOM_TRANSITION_S + 0.3).timeout


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	_set_wind(0.0, 13.0)
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	app.start_new_game()
	await _idle()
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	await _idle()
	_beat(150)
	if _wanted("01"):
		await _deck()
		await _shot("01_beating_on_deck", 1.2)
	if _wanted("02"):
		app.open_instruments()
		await _frames(6)
		await _shot("02_instruments_on_a_tack")
		app.modals.clear()
	if _wanted("03"):
		app.open_chartplotter()
		await _frames(6)
		await _shot("03_plotter_zigzag", 1.5)
		app.modals.clear()
	if _wanted("04"):
		await _deck()
		app.tack_now()
		Simulation.advance(300.0)
		await _frames(6)
		await _shot("04_after_a_tack_by_hand", 1.2)
	if _wanted("05"):
		app.open_action_wheel()
		await _frames(8)
		await _shot("05_wheel_tack_now")
		app.modals.clear()
		app.close_action_wheel() if app.has_method("close_action_wheel") else null
	print("I027 SHOTS DONE")
	get_tree().quit()
