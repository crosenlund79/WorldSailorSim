extends Node
## The Captain's Illustrated Catalogue: renders previews of the art that the game
## draws in code (GDScript _draw()), through the game itself, so the contact sheets
## show exactly what the player sees. Nothing is drawn here; the game's own nodes
## and screens are shown and photographed.
##
## Writes PNGs to docs/art/previews/ (or --out=DIR):
##   decor_<id>.png          each cabin thing (CabinDecor), on a cabin-floor colour
##   boat_<id>_moored.png    each boat moored in Copenhagen, by day (the whole screen,
##                           saved at 1280 x 720 to keep the repository small)
##   boat_<id>_underway.png  each boat under sail (sails and rigging are drawn in code)
##   boat_<id>_cabin.png     each boat's cabin with every cabin thing shown
##   chart_<symbol>_<day|night>.png   chart markers cropped from the real chart
## Run rendered (Xvfb and software OpenGL are fine):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tools/art/capture_previews.tscn -- --out=docs/art/previews
## Then build the sheets: python3 tools/art/build_contact_sheets.py

const APP_SCENE := preload("res://src/app/app.tscn")
const VESSELS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]
const FLOOR := Color("#c9b99a")

var app: Node
var out := "res://docs/art/previews"


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _image() -> Image:
	await _frames(4)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## The image pixels of a rectangle given in canvas units (the game lays out a
## 1920 x 1080 canvas and shows it in the window's size).
func _crop(image: Image, canvas_rect: Rect2) -> Image:
	var k := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var rect := Rect2i(Vector2i((canvas_rect.position * k).round()), Vector2i((canvas_rect.size * k).round()))
	return image.get_region(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))


func _save(image: Image, file_name: String) -> void:
	image.save_png("%s/%s.png" % [out, file_name])
	print("PREVIEW %s" % file_name)


## The whole screen, as the player sees it, at 1280 x 720.
func _screen() -> Image:
	var image := await _image()
	image.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	return image


func _idle() -> void:
	var guard := 0
	while app.router.is_busy() and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _frames(6)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	await _capture_decor()
	Simulation.auto_advance = false
	WindField.get_default().test_override = func(_geo: Vector2, _time: float) -> WindField.Sample:
		return WindField.Sample.make(220.0, 11.0)
	app = APP_SCENE.instantiate()
	add_child(app)
	await _frames(12)
	app.start_new_game()
	await _idle()
	await _capture_boats()
	for mood in ["day", "night"]:
		await _capture_chart(mood)
	print("PREVIEWS DONE")
	get_tree().quit()


# --- Cabin things -------------------------------------------------------------------

## Each cabin thing alone, drawn by CabinDecor at three times its cabin size on a
## plain cabin-floor colour (wall things facing up, as on the starboard wall).
func _capture_decor() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var back := ColorRect.new()
	back.color = FLOOR
	back.size = get_viewport().get_visible_rect().size
	layer.add_child(back)
	var holder := Node2D.new()
	layer.add_child(holder)
	var cell := Vector2(260, 220)
	var items := HarbourTrades.get_decor()
	for i in items.size():
		var id := String(items[i].id)
		var decor := CabinDecor.new()
		decor.item_id = id
		decor.side = 0.0 if id == "rug" else 1.0
		holder.add_child(decor)
		decor.scale = Vector2.ONE * (2.0 if id == "rug" else 3.0)
		decor.position = Vector2(130 + (i % 6) * cell.x, 150 + (i / 6) * cell.y)
	var image := await _image()
	for i in items.size():
		var centre := Vector2(130 + (i % 6) * cell.x, 150 + (i / 6) * cell.y) + Vector2(0, -25)
		_save(_crop(image, Rect2(centre - cell / 2.0, cell)), "decor_%s" % String(items[i].id))
	layer.queue_free()
	await _frames(2)


# --- Boats ---------------------------------------------------------------------------

func _moor(port_id: StringName, vessel_id: StringName, hour: float) -> void:
	var state := GameSession.get_state_snapshot()
	state.vessel_id = vessel_id
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	var day_start := floorf(state.game_time / 86400.0) * 86400.0
	state.game_time = day_start + fposmod(hour - state.vessel_position.x / 15.0, 24.0) * 3600.0
	GameSession.replace_state(state)
	UiTheme.set_blend(UiTheme._target_blend(), true)


func _show(area: StringName) -> void:
	app.modals.clear()
	GameSession.enter_boat_area(area, &"start")
	app._show_current_boat_area()
	await _idle()
	var lighting := (app.router.current_screen as Node).get_node_or_null("Lighting")
	if lighting:
		lighting.update_now()
	app.toasts.clear()


func _capture_boats() -> void:
	for id: String in ["model_ship", "sea_glass", "barometer", "rug", "herbs", "chart_print", "oil_lamp", "books", "bunting", "compass"]:
		GameSession.buy_decor(id)
	for vessel_id in VESSELS:
		_moor(&"copenhagen", vessel_id, 12.5)
		await _show(SessionState.AREA_EXTERIOR)
		_save(await _screen(), "boat_%s_moored" % vessel_id)
		await _show(SessionState.AREA_INTERIOR)
		for item: Dictionary in HarbourTrades.get_decor():
			GameSession.set_cabin_decor(String(item.id), true)
		await _show(SessionState.AREA_INTERIOR)
		_save(await _screen(), "boat_%s_cabin" % vessel_id)
		GameSession.plan_route_to(&"gothenburg")  # downwind in the south-westerly: under sail
		GameSession.depart()
		Simulation.advance(1800.0)
		await _show(SessionState.AREA_EXTERIOR)
		_save(await _screen(), "boat_%s_underway" % vessel_id)
		_moor(&"copenhagen", vessel_id, 12.5)


# --- Chart symbols -------------------------------------------------------------------

## The chart's own markers, cropped from the real chart: an ordinary harbour, a
## selected one, the destination, a special harbour (its brass star), the boat in
## harbour, a route waypoint, and the Dreamer's Map's red visited pins.
func _capture_chart(mood: String) -> void:
	var hour := 12.5 if mood == "day" else 23.5
	_moor(&"syracuse", &"starling_33", hour)
	await _show(SessionState.AREA_EXTERIOR)
	var waypoint := Vector2(15.6, 36.3)
	GameSession.plan_route_to(&"valletta", [waypoint] as Array[Vector2])
	app.open_chart_for_port(&"catania")
	await _idle()
	await _frames(10)
	var chart := app.router.current_screen as WorldMap
	var view := chart.get_map_view()
	view.frame_geo_points(PackedVector2Array([Vector2(13.6, 35.6), Vector2(16.4, 38.4)]))
	await _frames(10)
	var image := await _image()
	var crops := {
		"harbour": [PortCatalog.get_default().get_port(&"messina").get_geo_position(), Vector2(150, 70)],
		"selected": [PortCatalog.get_default().get_port(&"catania").get_geo_position(), Vector2(150, 70)],
		"destination_special": [PortCatalog.get_default().get_port(&"valletta").get_geo_position(), Vector2(160, 80)],
		"boat_in_harbour": [PortCatalog.get_default().get_port(&"syracuse").get_geo_position(), Vector2(170, 90)],
		"waypoint": [waypoint, Vector2(120, 70)],
	}
	for name: String in crops:
		var at: Vector2 = view.geo_to_screen(crops[name][0])  # already in screen (canvas) units
		var size: Vector2 = crops[name][1]
		_save(_crop(image, Rect2(at - Vector2(size.x * 0.35, size.y * 0.5), size)), "chart_%s_%s" % [name, mood])
	app.close_chart()
	await _idle()
	# The Dreamer's Map: red visited pins (one harbour, and a cluster).
	app.open_dream_map()
	await _idle()
	await _frames(10)
	var dream := app.router.current_screen as WorldMap
	var dview := dream.get_map_view()
	dview.visited_pins = [&"copenhagen", &"helsingor", &"malmo", &"kiel"] as Array[StringName]
	dview.frame_geo_points(PackedVector2Array([Vector2(9.0, 53.6), Vector2(14.0, 56.8)]))
	await _frames(10)
	image = await _image()
	for pair: Array in [["visited_pin", &"kiel"], ["visited_cluster", &"copenhagen"]]:
		var at: Vector2 = dview.geo_to_screen(PortCatalog.get_default().get_port(pair[1]).get_geo_position())
		_save(_crop(image, Rect2(at - Vector2(60, 70), Vector2(200, 100))), "chart_%s_%s" % [pair[0], mood])
	app.close_chart()
	await _idle()
