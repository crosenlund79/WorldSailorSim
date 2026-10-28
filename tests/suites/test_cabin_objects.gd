extends RefCounted
## I026, A World You Can Touch - life aboard (stage 04): the things a sailor
## uses below are objects in every cabin (CabinObject) - the logbook and the
## VHF set at the nav station, the switch panel, the sea chest by the berth,
## the newest postcard on the saloon table - each reachable by the Captain
## (a free place beside it where E focuses it), each opening its focused
## view framed as the object (FocusFrame), each closed with Esc; the existing
## locker, stove, trophy board and berth menus are framed too. The VHF lamp
## blinks while a call waits and the call is answered from the set; the
## systems panel shows only what the game keeps; the postcard appears once
## one is made.

const APP_SCENE := preload("res://src/app/app.tscn")
const BOATS: Array[StringName] = [&"arctic_wanderer_26", &"starling_33", &"petrel_36", &"halcyon_40"]

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	WeatherFixtures.use([])
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game(&"")
	await _settle()
	for boat in BOATS:
		await _test_cabin(boat)
	await _test_views()
	await _test_vhf()
	await _test_postcard()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _cabin() -> BoatArea:
	app.modals.clear()
	GameSession.enter_boat_area(SessionState.AREA_INTERIOR, &"from_deck")
	app._show_current_boat_area()
	await _settle()
	return app.router.current_screen as BoatArea


## A free place beside `object` (inside the cabin, outside every piece of
## furniture) from which E focuses it, or Vector2.INF.
func _stand_by(area: BoatArea, object: CabinObject) -> Vector2:
	var solids: Array[PackedVector2Array] = []
	for fixture in area.get_node("Layout/Collision").get_children():
		if fixture is BoatFixture and String(fixture.name) != "Hull":
			solids.append((fixture as BoatFixture).transform * (fixture as BoatFixture).get_points())
	for radius in [34.0, 46.0, 58.0]:
		for i in 16:
			var p: Vector2 = object.position + Vector2.from_angle(TAU * i / 16.0) * radius
			if not area.walkable_bounds.grow(-22.0).has_point(p):
				continue
			if solids.any(func(poly: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(p, poly)):
				continue
			area.player.position = p
			area.player.velocity = Vector2.ZERO
			area.player.set_facing((object.position - p).normalized())
			await t.physics_frames(4)
			if area.player.get_focused_interactable() == object.interactable:
				return p
	return Vector2.INF


func _test_cabin(boat: StringName) -> void:
	await t.board(boat, app)
	var area := await _cabin()
	var found: Array[String] = []
	for kind in [CabinObject.LOGBOOK, CabinObject.VHF, CabinObject.SYSTEMS, CabinObject.CHEST]:
		var object := area.get_cabin_object(kind)
		if not t.check(object != null, "[%s] the %s is in the cabin" % [boat, kind]):
			continue
		found.append(String(kind))
		var spot := await _stand_by(area, object)
		t.check(spot != Vector2.INF, "[%s] the %s can be reached: E focuses it ('%s')" % [boat, kind, object.interactable.prompt])
	t.check(area.get_cabin_object(CabinObject.POSTCARD) == null or not area.get_cabin_object(CabinObject.POSTCARD).visible,
		"[%s] no postcard yet: none on the table" % boat)
	await t.screenshot("i026_cabin_objects_%s" % boat)


## Each object opens its focused view, framed, and Esc closes it.
func _test_views() -> void:
	await t.board(&"starling_33", app)
	var area := await _cabin()
	var expected := {CabinObject.LOGBOOK: "CaptainsLogMenu", CabinObject.VHF: "VhfSetView", CabinObject.SYSTEMS: "SystemsView",
		CabinObject.CHEST: "CabinHomeMenu"}
	for kind: StringName in expected:
		var object := area.get_cabin_object(kind)
		object.interactable.interacted.emit(object.interactable, area.player)
		await t.frames(4)
		var top: Node = app.modals.get_top()
		t.check(top != null and top.get_script().get_global_name() == expected[kind], "[%s] E opens %s" % [kind, expected[kind]])
		if kind != CabinObject.CHEST:  # the sea chest keeps "Make it home"'s side panel over the cabin
			t.check(top != null and top.has_node(^"FocusFrame"), "[%s] framed as the object (FocusFrame)" % kind)
		await t.screenshot("i026_view_%s" % kind)
		await t.press_key(KEY_ESCAPE)
		await t.frames(4)
		t.check(app.modals.is_empty(), "[%s] Esc closes it" % kind)
	# The logbook holds the real Captain's Log.
	var log: ModalPanel = app.open_cabin_object(CabinObject.LOGBOOK)
	t.check(log is CaptainsLogMenu, "[logbook] the Captain's Log itself, not a copy")
	app.modals.clear()
	# The existing cabin menus, framed as their objects.
	app.open_provisions()
	await t.frames(3)
	t.check(app.modals.get_top() and app.modals.get_top().has_node(^"FocusFrame"), "[locker] the provisions locker's view is framed")
	await t.screenshot("i026_view_locker")
	app.modals.clear()
	app.open_trophies()
	await t.frames(3)
	t.check(app.modals.get_top() and app.modals.get_top().has_node(^"FocusFrame"), "[trophies] the trophy board's view is framed")
	app.modals.clear()
	app.open_sleep_menu()
	await t.frames(3)
	t.check(app.modals.get_top() and app.modals.get_top().has_node(^"FocusFrame"), "[berth] the berth's sleep view is framed")
	await t.screenshot("i026_view_berth")
	app.modals.clear()
	# The systems panel: only what the game keeps.
	var rows := SystemsView.rows()
	var labels := rows.map(func(r: Array) -> String: return String(r[0]))
	t.check(labels.has("Hull") and labels.has("Food aboard") and labels.has("Water aboard") and not labels.any(func(l: String) -> bool: return l.containsn("battery") or l.containsn("fuel")),
		"[systems] hull, care survey, food and water - no invented battery or fuel (%s)" % [labels])
	await t.frames(2)


func _test_vhf() -> void:
	var area := await _cabin()
	var radio := area.get_cabin_object(CabinObject.VHF)
	t.check(not radio.call_waiting, "[vhf] no call: the lamp is dark")
	# A call comes in (the same signal as at sea) while nothing can show it.
	var call := VhfRadio.call_for_slot(GameSession.get_game_time() - 3600.0, 0, 7, false)
	var answerable := false
	if not call.is_empty():
		GameSession.plan_route_to(&"kiel")
		GameSession.depart()
		await _cabin()
		area = app.router.current_screen as BoatArea
		radio = area.get_cabin_object(CabinObject.VHF)
		app._on_vhf_call(call)
		answerable = GameSession.can_answer_vhf(call)
	t.check(call.is_empty() or radio.call_waiting, "[vhf] a call waiting: the set's lamp blinks")
	var view: VhfSetView = app.open_vhf_set()
	await t.frames(3)
	t.check(view != null and view.has_node(^"FocusFrame"), "[vhf] the set opens, framed as the radio")
	t.check(VhfSetView.broadcast_lines().size() >= 1 and VhfSetView.broadcast_lines()[0].containsn("kn"),
		"[vhf] the weather broadcast from the game's own weather: '%s'" % VhfSetView.broadcast_lines()[0])
	var answer := view.find_child("AnswerButton", true, false) as Button if view else null
	if answerable and t.check(answer != null, "[vhf] the waiting call can be answered at the set"):
		await t.click(answer)
		await t.frames(4)
		t.check(app.modals.get_top() is VhfDialog and not radio.call_waiting, "[vhf] answering opens the call (the usual dialog); the lamp goes dark")
	await t.screenshot("i026_view_vhf_call")
	app.modals.clear()
	await t.frames(2)


func _test_postcard() -> void:
	GameSession.start_new_session(&"")
	var state := GameSession.get_state_snapshot()
	state.pastimes.postcards.append({"kind": "harbour", "subject": "copenhagen", "caption": 0, "layout": "classic",
		"place": "copenhagen", "time": state.game_time})
	GameSession.replace_state(state)
	var area := await _cabin()
	var card := area.get_cabin_object(CabinObject.POSTCARD)
	if not t.check(card != null and card.visible and card.interactable.enabled, "[postcard] the newest postcard lies on the saloon table"):
		return
	card.interactable.interacted.emit(card.interactable, area.player)
	await t.frames(4)
	t.check(app.modals.get_top() is ScrapbookMenu and (app.modals.get_top() as ScrapbookMenu).page == 0, "[postcard] E opens the scrapbook at it")
	await t.screenshot("i026_view_postcard")
	app.modals.clear()
	await t.frames(2)
